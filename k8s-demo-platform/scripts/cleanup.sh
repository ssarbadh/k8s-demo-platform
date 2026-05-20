#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

kubectl delete -f "${ROOT_DIR}/chaos/manifests/resource-exhaustion-job.yaml" --ignore-not-found
kubectl -n app delete networkpolicy dns-deny-egress network-partition-order-to-payment packet-loss-api-gateway-to-redis --ignore-not-found

kubectl delete -f "${ROOT_DIR}/alerts/sre-agent-rules.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/observability/grafana-dashboards.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/observability/service-monitors.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/observability/efk.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/apps/ingress.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/apps/networkpolicies.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/apps/platform.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/infra/redis.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/infra/postgres.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/infra/rbac.yaml" --ignore-not-found

helm uninstall jaeger -n observability || true
helm uninstall kube-prometheus-stack -n observability || true

kubectl delete namespace chaos-testing app observability --ignore-not-found
echo "Cleanup complete."
