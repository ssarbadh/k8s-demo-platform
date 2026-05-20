# Memory Leak Playbook

## Symptoms
- `MemorySaturation` or `OOMKilledPod` alert firing.
- Increased pod memory with eventual restarts.

## Triage
1. `kubectl -n app top pods`
2. `kubectl -n app describe pod <pod-name> | rg -n "OOMKilled|Reason"`
3. `kubectl -n app logs deploy/<deployment> --tail=100`

## Likely Root Causes
- Injected `memory_leak` failure mode.
- Limits too low for sustained load.

## Remediation
1. Disable fault:
   `./chaos/fault-injection.sh reset <deployment>`
2. Restore sane limits from `apps/platform.yaml`.
3. Restart deployment:
   `kubectl -n app rollout restart deploy/<deployment>`

## Validation
- Memory usage stabilizes below 70% of limit.
- No new OOM kills for 10 minutes.
