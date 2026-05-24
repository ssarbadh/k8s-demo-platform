import json
import os
import random
import threading
import time
import uuid
from datetime import datetime, timezone
from typing import Dict

import psycopg2
import redis
import requests
from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse, PlainTextResponse
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest


SERVICE_NAME = os.getenv("SERVICE_NAME", "unknown-service")
SERVICE_PORT = int(os.getenv("PORT", "8080"))
DB_URL = os.getenv("DB_URL", "")
REDIS_URL = os.getenv("REDIS_URL", "")
OTLP_ENDPOINT = os.getenv(
    "OTLP_ENDPOINT", "http://jaeger.observability.svc.cluster.local:4318/v1/traces"
)
FAILURE_MODE = os.getenv("FAILURE_MODE", "none")
FAILURE_RATE = float(os.getenv("FAILURE_RATE", "0.0"))
SLOW_MS = int(os.getenv("SLOW_MS", "0"))
EXPECTED_DEPS = [
    dep.strip() for dep in os.getenv("EXPECTED_DEPS", "").split(",") if dep.strip()
]
DOWNSTREAMS = {
    k[11:].lower(): v
    for k, v in os.environ.items()
    if k.startswith("DOWNSTREAM_") and v.strip()
}


REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["service", "method", "path", "status"],
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "Request latency",
    ["service", "method", "path"],
)
DEPENDENCY_ERRORS = Counter(
    "dependency_errors_total",
    "Dependency errors",
    ["service", "dependency", "error_type"],
)
FAILURE_EVENTS = Counter(
    "failure_injections_total",
    "Failure injection events",
    ["service", "mode"],
)

app = FastAPI(title=SERVICE_NAME)
_redis_client = None
_tracer = None
_mem_holder = []
_cpu_spike_enabled = False

# FastAPI instrumentation must be installed before app startup.
FastAPIInstrumentor.instrument_app(app)


def _setup_tracing() -> None:
    global _tracer
    provider = TracerProvider(resource=Resource.create({"service.name": SERVICE_NAME}))
    exporter = OTLPSpanExporter(endpoint=OTLP_ENDPOINT)
    provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(provider)
    _tracer = trace.get_tracer(__name__)


def _log(level: str, message: str, request_id: str = "", trace_id: str = "", **kwargs) -> None:
    payload = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "level": level,
        "service": SERVICE_NAME,
        "message": message,
        "request_id": request_id,
        "trace_id": trace_id,
    }
    payload.update(kwargs)
    print(json.dumps(payload), flush=True)


def _maybe_init_redis():
    global _redis_client
    if REDIS_URL and _redis_client is None:
        _redis_client = redis.Redis.from_url(REDIS_URL, socket_connect_timeout=2, socket_timeout=2)
    return _redis_client


def _db_ping() -> bool:
    if not DB_URL:
        return True
    try:
        conn = psycopg2.connect(DB_URL, connect_timeout=2)
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.fetchone()
        cur.close()
        conn.close()
        return True
    except Exception:
        DEPENDENCY_ERRORS.labels(service=SERVICE_NAME, dependency="postgres", error_type="connect").inc()
        return False


def _redis_ping() -> bool:
    if not REDIS_URL:
        return True
    try:
        client = _maybe_init_redis()
        client.ping()
        return True
    except Exception:
        DEPENDENCY_ERRORS.labels(service=SERVICE_NAME, dependency="redis", error_type="connect").inc()
        return False


def _cpu_spike() -> None:
    while _cpu_spike_enabled:
        _ = 42 * 42


@app.on_event("startup")
def startup() -> None:
    _setup_tracing()
    RequestsInstrumentor().instrument()
    if FAILURE_MODE == "cpu_spike":
        global _cpu_spike_enabled
        _cpu_spike_enabled = True
        for _ in range(2):
            thread = threading.Thread(target=_cpu_spike, daemon=True)
            thread.start()
    _log("info", "service started", failure_mode=FAILURE_MODE)


@app.on_event("shutdown")
def shutdown() -> None:
    global _cpu_spike_enabled
    _cpu_spike_enabled = False


@app.middleware("http")
async def metrics_and_logging(request: Request, call_next):
    request_id = request.headers.get("x-request-id", str(uuid.uuid4()))
    traceparent = request.headers.get("traceparent", "")
    trace_id = traceparent.split("-")[1] if traceparent.count("-") >= 2 else ""
    path = request.url.path
    method = request.method
    start = time.time()
    status = 500
    error_code = ""
    try:
        response = await call_next(request)
        status = response.status_code
    except Exception:
        error_code = "UNHANDLED_EXCEPTION"
        status = 500
        response = JSONResponse(status_code=500, content={"error": "internal_error"})
    duration = time.time() - start
    REQUEST_COUNT.labels(service=SERVICE_NAME, method=method, path=path, status=str(status)).inc()
    REQUEST_LATENCY.labels(service=SERVICE_NAME, method=method, path=path).observe(duration)
    _log(
        "info" if status < 500 else "error",
        "request complete",
        request_id=request_id,
        trace_id=trace_id,
        method=method,
        path=path,
        status=status,
        latency_ms=int(duration * 1000),
        error_code=error_code,
    )
    response.headers["x-request-id"] = request_id
    return response


def _apply_failure_mode() -> Dict[str, str]:
    if FAILURE_MODE == "none":
        return {}
    if FAILURE_RATE > 0 and random.random() > FAILURE_RATE:
        return {}
    FAILURE_EVENTS.labels(service=SERVICE_NAME, mode=FAILURE_MODE).inc()
    if FAILURE_MODE == "high_latency":
        time.sleep(max(0, SLOW_MS) / 1000)
    elif FAILURE_MODE == "http_500_spike":
        return {"error": "simulated_failure"}
    elif FAILURE_MODE == "memory_leak":
        _mem_holder.extend(["x" * 1024 * 1024 for _ in range(2)])
    elif FAILURE_MODE == "deadlock":
        time.sleep(30)
    elif FAILURE_MODE == "slow_query":
        time.sleep(3)
    elif FAILURE_MODE == "conn_pool_exhaustion":
        holders = []
        if DB_URL:
            for _ in range(20):
                conn = psycopg2.connect(DB_URL, connect_timeout=2)
                holders.append(conn)
            time.sleep(5)
            for conn in holders:
                conn.close()
    return {}


@app.get("/health")
def health() -> Dict[str, str]:
    return {"status": "ok", "service": SERVICE_NAME}


@app.get("/ready")
def ready() -> JSONResponse:
    checks = {"db": _db_ping(), "redis": _redis_ping()}
    all_ready = all(checks.values())
    return JSONResponse(status_code=200 if all_ready else 503, content={"service": SERVICE_NAME, "checks": checks})


@app.get("/metrics")
def metrics() -> Response:
    return PlainTextResponse(generate_latest().decode("utf-8"), media_type=CONTENT_TYPE_LATEST)


@app.get("/api/healthz")
def api_health() -> Dict[str, str]:
    return {"service": SERVICE_NAME, "api": "ok"}


@app.get("/api/dependencies")
def dependencies() -> Dict[str, object]:
    states = {
        "postgres": _db_ping(),
        "redis": _redis_ping(),
    }
    for name, url in DOWNSTREAMS.items():
        try:
            response = requests.get(f"{url}/health", timeout=2)
            states[name] = response.status_code == 200
        except Exception:
            states[name] = False
            DEPENDENCY_ERRORS.labels(service=SERVICE_NAME, dependency=name, error_type="http").inc()
    return {"service": SERVICE_NAME, "dependencies": states}


@app.get("/api/catalog")
def catalog() -> Dict[str, object]:
    failure = _apply_failure_mode()
    if failure:
        return JSONResponse(status_code=500, content=failure)
    items = [{"sku": "sku-101", "name": "demo-keyboard", "qty": 12}]
    return {"service": SERVICE_NAME, "items": items}


@app.post("/api/order")
def create_order() -> Dict[str, object]:
    failure = _apply_failure_mode()
    if failure:
        return JSONResponse(status_code=500, content=failure)
    deps = {}
    for dep in EXPECTED_DEPS:
        if dep in DOWNSTREAMS:
            try:
                response = requests.get(f"{DOWNSTREAMS[dep]}/api/healthz", timeout=2)
                deps[dep] = response.status_code
            except Exception:
                deps[dep] = 503
                DEPENDENCY_ERRORS.labels(service=SERVICE_NAME, dependency=dep, error_type="timeout").inc()
    return {
        "service": SERVICE_NAME,
        "order_id": f"ord-{int(time.time())}",
        "dependency_status": deps,
    }


@app.get("/api/session/{sid}")
def session_get(sid: str) -> Dict[str, object]:
    if not REDIS_URL:
        return {"service": SERVICE_NAME, "session": None}
    try:
        client = _maybe_init_redis()
        value = client.get(f"session:{sid}")
        return {"service": SERVICE_NAME, "session": value.decode() if value else None}
    except Exception as exc:
        DEPENDENCY_ERRORS.labels(service=SERVICE_NAME, dependency="redis", error_type="read").inc()
        return JSONResponse(status_code=503, content={"error": "redis_unavailable", "detail": str(exc)})


@app.post("/api/session/{sid}")
def session_set(sid: str) -> Dict[str, str]:
    if not REDIS_URL:
        return {"status": "noop"}
    try:
        client = _maybe_init_redis()
        client.setex(f"session:{sid}", 600, f"user-{sid}")
        return {"status": "ok"}
    except Exception as exc:
        DEPENDENCY_ERRORS.labels(service=SERVICE_NAME, dependency="redis", error_type="write").inc()
        return JSONResponse(status_code=503, content={"error": "redis_unavailable", "detail": str(exc)})


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=SERVICE_PORT)
