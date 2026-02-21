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

## How It Works

TeammateIdle hooks use exit codes and stderr to control agent behavior:

- **Exit 0** (default): Let the teammate go idle (no more work)
- **Exit 2**: Keep the teammate working — stderr is fed back as feedback/instructions

When work is available, the hook:
1. Dequeues the next task from `session.json`
2. Writes the task description to **stderr** (fed back to the teammate as context)
3. Exits with code **2** (tells Claude Code to keep the teammate active)

When no work remains, the hook exits with code 0 (teammate goes idle).

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
