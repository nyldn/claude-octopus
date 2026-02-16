---
command: scheduler
description: "Manage the scheduled workflow runner daemon (start/stop/status)"
aliases:
  - sched
---

# Scheduler

Manage the Claude Octopus scheduled workflow runner daemon.

## Usage

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/scheduler/octopus-scheduler.sh start
${CLAUDE_PLUGIN_ROOT}/scripts/scheduler/octopus-scheduler.sh stop
${CLAUDE_PLUGIN_ROOT}/scripts/scheduler/octopus-scheduler.sh status
${CLAUDE_PLUGIN_ROOT}/scripts/scheduler/octopus-scheduler.sh emergency-stop
```

## Instructions for Claude

This command supports **natural language**. The user may invoke it with explicit subcommands OR with conversational requests. You MUST interpret intent and map to the correct action.

### Step 1: Parse Intent

Map the user's input to one of these actions:

| Intent patterns | Action |
|----------------|--------|
| "start", "run", "launch", "boot up", "turn on" | `start` |
| "stop", "shut down", "turn off", "kill", "halt" | `stop` |
| "status", "how is it", "what's running", "check", "is it running", no args | `status` |
| "emergency", "panic", "abort", "kill everything", "stop all" | `emergency-stop` |

If the intent is ambiguous, use AskUserQuestion to clarify.

### Step 2: Display Banner

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Scheduler Management
⏰ Scheduler: [action description]

Providers:
🔵 Claude - Daemon management
```

### Step 3: Execute and Present

Run the appropriate `octopus-scheduler.sh` subcommand and present results.

After `status`, give a human-readable summary:
- Whether the daemon is running and for how long
- How many jobs are active
- Current daily spend
- If any kill switches are active, explain what they mean and how to clear them

After `start`, confirm it's running and remind the user to add jobs if none exist.

After `emergency-stop`, explain what happened and how to recover:
- "Remove `~/.claude-octopus/scheduler/switches/KILL_ALL` to allow restart"

### Natural Language Examples

- "is the scheduler running?" → `status`
- "start the scheduler" → `start`
- "shut it down" → `stop`
- "something's wrong, stop everything" → `emergency-stop`
- "what's the scheduler doing?" → `status`
