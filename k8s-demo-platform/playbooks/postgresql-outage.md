# PostgreSQL Outage Playbook

## Symptoms
- `PostgreSQLUnavailable` alert firing.
- `auth-service`, `user-service`, or `order-service` not ready.
- Database-related errors in logs.

## Triage
1. `kubectl -n app get statefulset postgres`
2. `kubectl -n app get pvc postgres-pvc`
3. `kubectl -n app logs statefulset/postgres --tail=100`
4. `kubectl -n app logs deploy/order-service --tail=100 | rg postgres`

## Likely Root Causes
- StatefulSet scaled down.
- PVC not bound.
- PgBouncer cannot reach PostgreSQL.

## Remediation
1. `kubectl -n app scale statefulset postgres --replicas=1`
2. `kubectl -n app rollout restart deploy/pgbouncer`
3. Check connectivity:
   `kubectl -n app run pg-client --rm -it --image=postgres:16-alpine -- psql postgresql://demo:demo123@pgbouncer:6432/ecommerce -c "select 1;"`

## Validation
- `/ready` on dependent services returns 200.
- `dependency_errors_total{dependency="postgres"}` drops.
