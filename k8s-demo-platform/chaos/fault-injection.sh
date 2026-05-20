#!/usr/bin/env bash
set -euo pipefail

APP_NS="${APP_NS:-app}"
CHAOS_NS="${CHAOS_NS:-chaos-testing}"
TARGET_DEPLOYMENT="${TARGET_DEPLOYMENT:-api-gateway}"

usage() {
  cat <<EOF
Usage: $0 <scenario> [target-deployment]

Scenarios:
  crashloop
  imagepullbackoff
  oomkilled
  pending
  affinity-failure
  resource-exhaustion
  dns-failure
  high-latency
  http-500-spike
  memory-leak
  cpu-spike
  deadlock
  conn-pool-exhaustion
  slow-query
  postgres-down
  redis-down
  network-partition
  service-unavailable
  packet-loss
  timeout-injection
  reset
EOF
}

scenario="${1:-}"
if [[ -z "${scenario}" ]]; then
  usage
  exit 1
fi

if [[ $# -ge 2 ]]; then
  TARGET_DEPLOYMENT="$2"
fi

patch_failure_mode() {
  local mode="$1"
  local rate="${2:-1.0}"
  local slow_ms="${3:-0}"
  kubectl -n "$APP_NS" set env deployment/"$TARGET_DEPLOYMENT" FAILURE_MODE="$mode" FAILURE_RATE="$rate" SLOW_MS="$slow_ms"
}

case "$scenario" in
  crashloop)
    kubectl -n "$APP_NS" patch deployment "$TARGET_DEPLOYMENT" --type='json' \
      -p='[{"op":"replace","path":"/spec/template/spec/containers/0/command","value":["/bin/sh","-c","exit 1"]}]'
    ;;
  imagepullbackoff)
    kubectl -n "$APP_NS" set image deployment/"$TARGET_DEPLOYMENT" "$TARGET_DEPLOYMENT"=doesnotexist.invalid/fail:latest
    ;;
  oomkilled)
    patch_failure_mode memory_leak 1.0 0
    kubectl -n "$APP_NS" patch deployment "$TARGET_DEPLOYMENT" --type='merge' \
      -p '{"spec":{"template":{"spec":{"containers":[{"name":"'"$TARGET_DEPLOYMENT"'","resources":{"limits":{"memory":"64Mi","cpu":"200m"},"requests":{"memory":"32Mi","cpu":"50m"}}}]}}}}'
    ;;
  pending)
    kubectl -n "$APP_NS" patch deployment "$TARGET_DEPLOYMENT" --type='merge' \
      -p '{"spec":{"template":{"spec":{"nodeSelector":{"demo-node-group":"does-not-exist"}}}}}'
    ;;
  affinity-failure)
    kubectl -n "$APP_NS" patch deployment "$TARGET_DEPLOYMENT" --type='merge' \
      -p '{"spec":{"template":{"spec":{"affinity":{"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"zone","operator":"In","values":["imaginary-zone"]}]}]}}}}}}}'
    ;;
  resource-exhaustion)
    kubectl apply -f "$(dirname "$0")/manifests/resource-exhaustion-job.yaml"
    ;;
  dns-failure)
    kubectl -n "$APP_NS" apply -f "$(dirname "$0")/manifests/dns-deny-policy.yaml"
    ;;
  high-latency)
    patch_failure_mode high_latency 0.9 1200
    ;;
  http-500-spike)
    patch_failure_mode http_500_spike 0.4 0
    ;;
  memory-leak)
    patch_failure_mode memory_leak 1.0 0
    ;;
  cpu-spike)
    patch_failure_mode cpu_spike 1.0 0
    ;;
  deadlock)
    patch_failure_mode deadlock 0.6 0
    ;;
  conn-pool-exhaustion)
    patch_failure_mode conn_pool_exhaustion 0.8 0
    ;;
  slow-query)
    patch_failure_mode slow_query 0.9 0
    ;;
  postgres-down)
    kubectl -n "$APP_NS" scale statefulset postgres --replicas=0
    ;;
  redis-down)
    kubectl -n "$APP_NS" scale deployment redis --replicas=0
    ;;
  network-partition)
    kubectl -n "$APP_NS" apply -f "$(dirname "$0")/manifests/network-partition-policy.yaml"
    ;;
  service-unavailable)
    kubectl -n "$APP_NS" scale deployment "$TARGET_DEPLOYMENT" --replicas=0
    ;;
  packet-loss)
    kubectl -n "$APP_NS" apply -f "$(dirname "$0")/manifests/packet-loss-policy.yaml"
    ;;
  timeout-injection)
    patch_failure_mode high_latency 1.0 3500
    ;;
  reset)
    kubectl -n "$APP_NS" set env deployment/"$TARGET_DEPLOYMENT" FAILURE_MODE=none FAILURE_RATE=0.0 SLOW_MS=0 --overwrite
    kubectl -n "$APP_NS" delete networkpolicy dns-deny-egress network-partition-order-to-payment packet-loss-api-gateway-to-redis --ignore-not-found
    kubectl -n "$APP_NS" patch deployment "$TARGET_DEPLOYMENT" --type='json' \
      -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]' || true
    kubectl -n "$APP_NS" patch deployment "$TARGET_DEPLOYMENT" --type='json' \
      -p='[{"op":"remove","path":"/spec/template/spec/affinity"}]' || true
    ;;
  *)
    usage
    exit 1
    ;;
esac

echo "Injected scenario: $scenario on deployment ${TARGET_DEPLOYMENT}"
