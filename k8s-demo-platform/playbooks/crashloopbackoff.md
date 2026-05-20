# CrashLoopBackOff Playbook

## Symptoms
- `PodCrashLooping` alert firing.
- Pod status `CrashLoopBackOff`.
- Frequent restart count increment.

## Triage
1. `kubectl -n app get pods`
2. `kubectl -n app describe pod <pod-name>`
3. `kubectl -n app logs <pod-name> --previous`
4. `kubectl -n app get events --sort-by=.lastTimestamp | tail`

## Likely Root Causes
- Injected crash command (`exit 1`).
- Invalid image/entrypoint.
- Readiness/liveness failures.

## Remediation
1. Restore deployment:
   `kubectl -n app rollout undo deploy/<deployment>`
2. Reapply baseline:
   `kubectl apply -f apps/platform.yaml`
3. Validate probes:
   `kubectl -n app describe deploy/<deployment>`

## Validation
- Pod transitions to `Running`.
- Restart count stabilizes.
