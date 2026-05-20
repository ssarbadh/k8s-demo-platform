# Kubernetes SRE Demo Microservices Lab

Production-like, lightweight Kubernetes environment for testing and fine-tuning an AI-powered SRE agent.

This lab is intentionally designed for:
- failure injection
- dependency outages
- observability and troubleshooting
- incident simulation and root cause analysis
- Kubernetes operational debugging

## Folder Structure

```text
k8s-demo-platform/
├── apps/
│   ├── common/
│   ├── ingress.yaml
│   ├── networkpolicies.yaml
│   └── platform.yaml
├── infra/
│   ├── namespaces.yaml
│   ├── postgres.yaml
│   ├── rbac.yaml
│   └── redis.yaml
├── observability/
│   ├── helm-values/
│   │   ├── jaeger-values.yaml
│   │   └── kube-prometheus-stack-values.yaml
│   ├── efk.yaml
│   ├── grafana-dashboards.yaml
│   └── service-monitors.yaml
├── alerts/
│   └── sre-agent-rules.yaml
├── dashboards/
│   └── ecommerce-overview.json
├── chaos/
│   ├── manifests/
│   └── fault-injection.sh
├── load-testing/
│   ├── k6-cascade.js
│   ├── k6-job.yaml
│   ├── k6-normal.js
│   └── k6-spike.js
├── playbooks/
├── scripts/
│   ├── cleanup.sh
│   ├── deploy.sh
│   └── health-check.sh
├── Makefile
└── README.md
```

## Platform Components

### Application Namespace (`app`)
- `frontend`
- `api-gateway`
- `auth-service`
- `user-service`
- `order-service`
- `inventory-service`
- `payment-service`
- `notification-service`

All services expose:
- `/health`
- `/ready`
- `/metrics`
- `/api/*`

### Dependencies
- PostgreSQL (StatefulSet + PVC + seed data)
- PgBouncer (connection pooling)
- Redis

### Observability Namespace (`observability`)
- kube-prometheus-stack (Prometheus, Alertmanager, Grafana, kube-state-metrics, node-exporter)
- Jaeger (tracing)
- EFK stack (Elasticsearch, Fluent Bit, Kibana)
- ServiceMonitor/PodMonitor and custom alert rules

### Chaos Namespace (`chaos-testing`)
- k6 job support
- optional chaos helper workloads

## Prerequisites

- Kubernetes cluster (Minikube, Kind, K3s, Docker Desktop K8s, EKS, AKS, GKE, any CNCF-compliant cluster)
- `kubectl`
- `helm` v3
- `docker` (for local image build)
- `k6` (optional, for local load generation)
- Ingress controller (optional, needed only for ingress hosts)

## Deployment Order

From `k8s-demo-platform/`:

```bash
chmod +x scripts/*.sh chaos/fault-injection.sh
./scripts/deploy.sh
```

Or:

```bash
make deploy
```

`deploy.sh` performs:
1. Builds local image `sre-demo-service:latest`
2. Creates namespaces + RBAC
3. Deploys PostgreSQL, PgBouncer, Redis
4. Deploys all microservices
5. Installs kube-prometheus-stack
6. Installs Jaeger
7. Deploys EFK + monitors + dashboards + alerts
8. Applies ingress (if `INGRESS_ENABLED=true`)

## Access URLs

### Port-forward (works on all clusters)

```bash
kubectl -n app port-forward svc/api-gateway 8080:8080
kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80
kubectl -n observability port-forward svc/kibana 5601:5601
kubectl -n observability port-forward svc/kube-prometheus-stack-prometheus 9090:9090
kubectl -n observability port-forward svc/jaeger-query 16686:16686
```

- App API: http://localhost:8080
- Grafana: http://localhost:3000
- Kibana: http://localhost:5601
- Prometheus: http://localhost:9090
- Jaeger: http://localhost:16686

### Ingress Hosts (if enabled)
- `demo.local`
- `grafana.demo.local`
- `kibana.demo.local`

## Credentials

- Grafana username: `admin`
- Grafana password: `admin123`

Kibana and Elasticsearch are intentionally unsecured in this demo lab.

## Health and Verification

```bash
./scripts/health-check.sh
```

Key API checks:

```bash
curl http://localhost:8080/health
curl http://localhost:8080/api/dependencies
curl http://localhost:8080/metrics
```

## Load Testing

Local:
```bash
make load-normal
make load-spike
make load-cascade
```

In-cluster:
```bash
kubectl apply -f load-testing/k6-job.yaml
kubectl -n chaos-testing logs job/k6-normal-traffic -f
```

## Fault Injection

Examples:

```bash
./chaos/fault-injection.sh crashloop api-gateway
./chaos/fault-injection.sh imagepullbackoff order-service
./chaos/fault-injection.sh oomkilled order-service
./chaos/fault-injection.sh pending payment-service
./chaos/fault-injection.sh affinity-failure inventory-service
./chaos/fault-injection.sh resource-exhaustion
./chaos/fault-injection.sh dns-failure
./chaos/fault-injection.sh high-latency api-gateway
./chaos/fault-injection.sh http-500-spike api-gateway
./chaos/fault-injection.sh memory-leak order-service
./chaos/fault-injection.sh cpu-spike order-service
./chaos/fault-injection.sh deadlock order-service
./chaos/fault-injection.sh conn-pool-exhaustion auth-service
./chaos/fault-injection.sh slow-query user-service
./chaos/fault-injection.sh postgres-down
./chaos/fault-injection.sh redis-down
./chaos/fault-injection.sh network-partition
./chaos/fault-injection.sh service-unavailable notification-service
./chaos/fault-injection.sh packet-loss
./chaos/fault-injection.sh timeout-injection api-gateway
./chaos/fault-injection.sh reset api-gateway
```

## Prometheus Query Examples

- Error rate by service:
  `sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)`
- p95 latency:
  `histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service))`
- Dependency failures:
  `sum(rate(dependency_errors_total[5m])) by (service, dependency)`
- Restart spikes:
  `increase(kube_pod_container_status_restarts_total{namespace="app"}[10m])`

## Troubleshooting Commands

```bash
kubectl -n app get pods,svc,deploy,statefulset
kubectl -n app get events --sort-by=.lastTimestamp | tail -n 50
kubectl -n app logs deploy/api-gateway --tail=200
kubectl -n observability get pods
kubectl -n observability logs ds/fluent-bit --tail=200
```

Incident playbooks are available in `playbooks/`.

## Cleanup

```bash
./scripts/cleanup.sh
```

Or:

```bash
make cleanup
```
