---
event: TaskCompleted
description: Triggers phase transitions and dependent task scheduling when workflow tasks complete
---

# TaskCompleted Hook (Claude Code v2.1.33+)

This hook enables automatic phase transitions in Claude Octopus Double Diamond workflows.

## Purpose

When a task completes during an active workflow, this hook:

1. Records task completion metrics (duration, tokens, tool uses)
2. Checks if all tasks in the current phase are complete
3. Triggers the next phase if completion threshold is met
4. Updates the workflow state machine

## Trigger Conditions

- Event: `TaskCompleted` (v2.1.33+)
- Active claude-octopus workflow detected (session file exists)
- Task belongs to a tracked workflow phase

## Behavior

```bash
# Read workflow state
SESSION_FILE="${HOME}/.claude-octopus/session.json"
if [[ -f "$SESSION_FILE" ]]; then
    CURRENT_PHASE=$(jq -r '.phase // empty' "$SESSION_FILE")
    TOTAL_TASKS=$(jq -r '.phase_tasks.total // 0' "$SESSION_FILE")
    COMPLETED_TASKS=$(jq -r '.phase_tasks.completed // 0' "$SESSION_FILE")

    # Increment completed count
    COMPLETED_TASKS=$((COMPLETED_TASKS + 1))
    jq ".phase_tasks.completed = $COMPLETED_TASKS" "$SESSION_FILE" > "${SESSION_FILE}.tmp" \
        && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

    # Check phase completion
    if [[ "$COMPLETED_TASKS" -ge "$TOTAL_TASKS" ]]; then
        # All phase tasks done - signal phase transition
        NEXT_PHASE=$(get_next_phase "$CURRENT_PHASE")
        jq ".phase = \"$NEXT_PHASE\" | .phase_tasks = {\"total\": 0, \"completed\": 0}" \
            "$SESSION_FILE" > "${SESSION_FILE}.tmp" \
            && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
    fi
fi
```

## Phase Transition Map

| Current Phase | Completion Signal | Next Phase |
|---------------|-------------------|------------|
| probe | All research agents done | grasp |
| grasp | Consensus reached (75%+) | tangle |
| tangle | Quality gate passed | ink |
| ink | All reviews complete | (workflow done) |

## additionalContext Return

When a task completes within an active phase:

```json
{
  "octopus_task_completed": {
    "phase": "probe",
    "task_subject": "Research OAuth patterns",
    "completed": 2,
    "total": 3,
    "phase_progress_pct": 67,
    "phase_complete": false,
    "metrics": {
      "duration_ms": 45200,
      "tokens_used": 12500,
      "tool_calls": 8
    }
  }
}
```

When the final task completes, triggering phase transition:

```json
{
  "octopus_task_completed": {
    "phase": "probe",
    "phase_complete": true,
    "transition_to": "grasp",
    "phase_summary": {
      "total_tasks": 3,
      "total_duration_ms": 125000,
      "total_tokens": 38000,
      "synthesis_file": "~/.claude-octopus/results/probe-synthesis-20260207.md"
    }
  }
}
```

## Integration with Autonomy Modes

| Mode | TaskCompleted Behavior |
|------|----------------------|
| Supervised | Signal phase complete, pause for user approval |
| Semi-autonomous | Auto-transition unless quality gate fails |
| Autonomous | Auto-transition to next phase immediately |

## Embrace Workflow Integration

For the full embrace workflow (`/octo:embrace`), this hook chains all four phases:

```
probe TaskCompleted → grasp starts
grasp TaskCompleted → tangle starts
tangle TaskCompleted → ink starts
ink TaskCompleted → workflow complete
```

## Metrics Collection

Each TaskCompleted event records to `~/.claude-octopus/metrics/`:

- Agent type that completed the task
- Wall-clock duration
- Token count (from v2.1.30 Task tool metrics)
- Tool use count
- Phase and workflow context

This data feeds the smart routing optimizer for future task assignment.

## Requirements

- Claude Code v2.1.33+ (TaskCompleted event support)
- `SUPPORTS_HOOK_EVENTS=true` in orchestrate.sh
- Active workflow session

## Related Files

- `~/.claude-octopus/session.json` - Workflow state machine
- `~/.claude-octopus/metrics/` - Per-task metrics for routing optimization
- `scripts/orchestrate.sh` - Phase transition logic
- `hooks/teammate-idle-hook.md` - Companion hook for agent scheduling
