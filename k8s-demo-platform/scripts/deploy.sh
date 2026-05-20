#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="${IMAGE_NAME:-sre-demo-service:latest}"
INGRESS_ENABLED="${INGRESS_ENABLED:-false}"

echo "[1/8] Building service image: ${IMAGE_NAME}"
docker build -t "${IMAGE_NAME}" "${ROOT_DIR}/apps/common"

if command -v kind >/dev/null 2>&1 && kind get clusters >/dev/null 2>&1; then
  if [[ -n "$(kind get clusters | head -n 1)" ]]; then
    echo "[kind] Loading image into kind cluster"
    kind load docker-image "${IMAGE_NAME}" || true
  fi
fi

if command -v minikube >/dev/null 2>&1; then
  if minikube status >/dev/null 2>&1; then
    echo "[minikube] Loading image into minikube"
    minikube image load "${IMAGE_NAME}" || true
  fi
fi

echo "[2/8] Creating namespaces and RBAC"
kubectl apply -f "${ROOT_DIR}/infra/namespaces.yaml"
kubectl apply -f "${ROOT_DIR}/infra/rbac.yaml"

echo "[3/8] Deploying infra dependencies"
kubectl apply -f "${ROOT_DIR}/infra/postgres.yaml"
kubectl apply -f "${ROOT_DIR}/infra/redis.yaml"

echo "[4/8] Deploying microservices"
kubectl apply -f "${ROOT_DIR}/apps/platform.yaml"
kubectl apply -f "${ROOT_DIR}/apps/networkpolicies.yaml"

echo "[5/8] Installing kube-prometheus-stack"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update >/dev/null
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n observability --create-namespace \
  -f "${ROOT_DIR}/observability/helm-values/kube-prometheus-stack-values.yaml"

echo "[6/8] Installing Jaeger"
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts >/dev/null
helm repo update >/dev/null
helm upgrade --install jaeger jaegertracing/jaeger \
  -n observability \
  -f "${ROOT_DIR}/observability/helm-values/jaeger-values.yaml"

echo "[7/8] Deploying logging, monitors, dashboards, alerts"
kubectl apply -f "${ROOT_DIR}/observability/efk.yaml"
kubectl apply -f "${ROOT_DIR}/observability/service-monitors.yaml"
kubectl apply -f "${ROOT_DIR}/observability/grafana-dashboards.yaml"
kubectl apply -f "${ROOT_DIR}/alerts/sre-agent-rules.yaml"

if [[ "${INGRESS_ENABLED}" == "true" ]]; then
  echo "[8/8] Applying ingress resources"
  kubectl apply -f "${ROOT_DIR}/apps/ingress.yaml"
else
  echo "[8/8] Skipping ingress (set INGRESS_ENABLED=true to enable)"
fi

echo "Deployment complete."
