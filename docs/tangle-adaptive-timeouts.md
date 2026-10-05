# Tangle adaptive coding supervision

Tangle coding agents are supervised by observable progress rather than a fixed wall-clock timeout by default. A coding agent may therefore run longer than the general Octopus task timeout while it continues to produce provider output, error output, or worktree changes.

Configuration:

- `OCTOPUS_TANGLE_TIMEOUT`: optional absolute wall-clock timeout in seconds for Tangle coding agents. When unset, Tangle coding uses `0` (unbounded wall-clock time). `0` may also be set explicitly. An explicit CLI `--timeout SECS` is honored when no Tangle-specific override is set.
- `OCTOPUS_TANGLE_STALL_WINDOW`: maximum seconds without observable provider/worktree progress before a coding agent is classified as stalled. Default: `900` for implementers and `1500` for implementer-heavy. Must be a positive integer.
- `OCTOPUS_TANGLE_STALL_POLL_SECS`: progress-check interval in seconds. Default: `30`. Must be a positive integer.

A stalled provider is terminated through the supervised process-group path and recorded as `STALLED - PARTIAL RESULTS` instead of `TIMEOUT`. Tangle's optional workflow-wide deadline remains separate from per-agent stall supervision.

The initial subtask pass and quality-gate retry passes use the same completion
watcher. `OCTOPUS_TANGLE_DEADLINE` sets an optional wall-clock wait budget in
seconds for each pass, with `0` or an unset value leaving the wait unbounded
while provider stall supervision remains active. Deadline cleanup verifies worker
ownership against the PID ledger before terminating the worker and its descendants.

An exited or zombie worker without a completion marker receives
`OCTOPUS_TANGLE_MISSING_MARKER_GRACE` seconds for a late marker or result, default
`180`. After that grace period the watcher records a missing-marker failure and
reconciles any completed successful artifact before quality-gate reevaluation.
Completed siblings and partial output remain available after cancellation.
