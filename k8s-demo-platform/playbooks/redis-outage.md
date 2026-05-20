# Redis Outage Playbook

## Symptoms
- `RedisUnavailable` alert firing.
- `api-gateway` and `auth-service` readiness checks return `503`.
- Elevated `dependency_errors_total{dependency="redis"}`.

## Triage
1. `kubectl -n app get deploy redis`
2. `kubectl -n app get pods -l app=redis`
3. `kubectl -n app logs deploy/api-gateway --tail=100 | rg redis_unavailable`
4. `kubectl -n app exec deploy/api-gateway -- wget -qO- http://localhost:8080/ready`

## Likely Root Causes
- Redis deployment scaled to `0`.
- Crash due to memory limits.
- Network policy blocks TCP 6379.

## Remediation
1. `kubectl -n app scale deploy redis --replicas=1`
2. Remove fault policy: `kubectl -n app delete networkpolicy packet-loss-api-gateway-to-redis --ignore-not-found`
3. Verify: `kubectl -n app get pods -l app=redis -w`

## Validation
- `kubectl -n app get --raw /api/v1/namespaces/app/services/http:api-gateway:8080/proxy/ready`
- Alert resolves in Prometheus.
