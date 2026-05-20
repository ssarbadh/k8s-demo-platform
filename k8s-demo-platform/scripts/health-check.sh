#!/usr/bin/env bash
set -euo pipefail

APP_NS="${APP_NS:-app}"
OBS_NS="${OBS_NS:-observability}"

echo "== Namespace health =="
kubectl get ns "${APP_NS}" "${OBS_NS}" chaos-testing

echo "== App workloads =="
kubectl -n "${APP_NS}" get deploy,statefulset,pods,svc

echo "== App readiness =="
for svc in frontend api-gateway auth-service user-service order-service inventory-service payment-service notification-service; do
  kubectl -n "${APP_NS}" get --raw "/api/v1/namespaces/${APP_NS}/services/http:${svc}:8080/proxy/ready" || true
  echo
done

echo "== Dependency chain =="
kubectl -n "${APP_NS}" get --raw "/api/v1/namespaces/${APP_NS}/services/http:api-gateway:8080/proxy/api/dependencies" || true
echo

echo "== Observability workloads =="
kubectl -n "${OBS_NS}" get pods,svc

echo "== Current alerts (if any) =="
kubectl -n "${OBS_NS}" get prometheusrules,servicemonitors,podmonitors
