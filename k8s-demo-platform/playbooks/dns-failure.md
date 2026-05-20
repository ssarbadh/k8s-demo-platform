# DNS Failure Playbook

## Symptoms
- Services fail dependency calls by hostname.
- Timeouts/errors increase while pods remain healthy.
- `dependency_errors_total` rises across multiple services.

## Triage
1. `kubectl -n app get networkpolicy`
2. `kubectl -n app exec deploy/api-gateway -- nslookup redis.app.svc.cluster.local`
3. `kubectl -n app exec deploy/api-gateway -- wget -qO- http://localhost:8080/api/dependencies`

## Likely Root Causes
- DNS egress blocked by fault network policy.
- CoreDNS unreachable from app namespace.

## Remediation
1. Remove policy:
   `kubectl -n app delete networkpolicy dns-deny-egress --ignore-not-found`
2. Verify DNS:
   `kubectl -n app exec deploy/api-gateway -- nslookup kubernetes.default.svc.cluster.local`
3. Re-check readiness endpoints.

## Validation
- Dependency checks return healthy.
- Error spikes in Grafana/Prometheus subside.
