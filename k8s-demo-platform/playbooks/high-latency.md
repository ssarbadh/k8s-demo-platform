# High Latency Playbook

## Symptoms
- `HighLatencyP95` alert firing.
- Slow responses from `/api/order`.
- Elevated `http_request_duration_seconds` p95 in Grafana.

## Triage
1. `kubectl -n app get hpa`
2. `kubectl -n app top pods`
3. `kubectl -n app logs deploy/api-gateway --tail=200 | rg latency_ms`
4. Jaeger trace search for slow spans.

## Likely Root Causes
- Injected `high_latency` failure mode.
- CPU saturation on api-gateway/order-service.
- Slow query or dependency timeout.

## Remediation
1. Disable fault:
   `./chaos/fault-injection.sh reset api-gateway`
2. Scale hot service:
   `kubectl -n app scale deploy/api-gateway --replicas=2`
3. If DB-related: restart `postgres` and `pgbouncer`.

## Validation
- p95 < 800ms over 5 minutes.
- Error rate remains below 5%.
