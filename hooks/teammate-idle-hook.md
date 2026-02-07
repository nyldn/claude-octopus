---
event: TeammateIdle
description: Auto-assigns queued work when a spawned agent completes and goes idle during multi-agent workflows
---

# TeammateIdle Hook (Claude Code v2.1.33+)

This hook enables event-driven agent scheduling for Claude Octopus workflows.

## Purpose

When a teammate agent finishes its current work and enters an idle state, this hook:

1. Checks for an active claude-octopus workflow phase
2. Reads the phase's agent queue from session state
3. Assigns the next queued task to the idle agent
4. Updates session state with agent utilization metrics

## Trigger Conditions

- Event: `TeammateIdle` (v2.1.33+)
- Active claude-octopus workflow detected (session file exists)
- Agent queue has remaining work items

## Behavior

```bash
# Read current workflow state
SESSION_FILE="${HOME}/.claude-octopus/session.json"
if [[ -f "$SESSION_FILE" ]]; then
    CURRENT_PHASE=$(jq -r '.phase // empty' "$SESSION_FILE")
    AGENT_QUEUE=$(jq -r '.agent_queue // [] | length' "$SESSION_FILE")

    if [[ "$AGENT_QUEUE" -gt 0 ]]; then
        # Dequeue next task and assign to idle agent
        NEXT_TASK=$(jq -r '.agent_queue[0]' "$SESSION_FILE")
        jq '.agent_queue = .agent_queue[1:]' "$SESSION_FILE" > "${SESSION_FILE}.tmp" \
            && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
    fi
fi
```

## additionalContext Return

When an idle teammate is detected and work is available:

```json
{
  "octopus_idle_agent": {
    "phase": "probe|grasp|tangle|ink",
    "queued_tasks_remaining": 3,
    "next_task": "Research OAuth authentication patterns",
    "agent_role": "ai-engineer",
    "utilization": {
      "agents_active": 1,
      "agents_idle": 2,
      "agents_total": 3
    }
  }
}
```

When no work is available (phase agents all complete):

```json
{
  "octopus_idle_agent": {
    "phase": "probe",
    "queued_tasks_remaining": 0,
    "phase_complete": true,
    "ready_for_transition": true
  }
}
```

## Integration with Workflow Phases

| Phase | TeammateIdle Behavior |
|-------|----------------------|
| Probe | Assign next research question to idle agent |
| Grasp | Assign next definition task to idle agent |
| Tangle | Assign next implementation unit to idle agent |
| Ink | Assign next review scope to idle agent |

## Performance Benefits

- **No polling**: Agents are scheduled reactively on idle events
- **Maximum utilization**: Idle agents immediately pick up queued work
- **Dynamic load balancing**: Faster agents process more tasks
- **Reduced latency**: Phase completes as soon as all work is dispatched

## Requirements

- Claude Code v2.1.33+ (TeammateIdle event support)
- `SUPPORTS_HOOK_EVENTS=true` in orchestrate.sh
- Active workflow session with agent queue

## Related Files

- `~/.claude-octopus/session.json` - Workflow session state with agent queue
- `scripts/orchestrate.sh` - Main orchestration (populates agent queue)
- `hooks/task-completed-hook.md` - Companion hook for phase transitions
