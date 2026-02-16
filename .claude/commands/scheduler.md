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
# Start the daemon (runs in background)
${CLAUDE_PLUGIN_ROOT}/scripts/scheduler/octopus-scheduler.sh start

# Check daemon status
${CLAUDE_PLUGIN_ROOT}/scripts/scheduler/octopus-scheduler.sh status

# Stop gracefully (waits for current job)
${CLAUDE_PLUGIN_ROOT}/scripts/scheduler/octopus-scheduler.sh stop

# Emergency stop (kills all, creates KILL_ALL switch)
${CLAUDE_PLUGIN_ROOT}/scripts/scheduler/octopus-scheduler.sh emergency-stop
```

## Instructions for Claude

When user invokes `/octo:scheduler`:

1. Parse the subcommand from user arguments (start, stop, status, emergency-stop)
2. Display the visual indicator banner:

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Scheduler Management
⏰ Scheduler: [action description]

Providers:
🔵 Claude - Daemon management
```

3. Execute the appropriate `octopus-scheduler.sh` subcommand
4. Format and present results
