---
command: schedule
description: "Manage scheduled workflow jobs (add/list/remove/enable/disable/logs)"
aliases:
  - jobs
  - cron
---

# Schedule

Manage scheduled workflow jobs for the Claude Octopus scheduler.

## Usage

```bash
# Add a job from a JSON file
${CLAUDE_PLUGIN_ROOT}/scripts/scheduler/octopus-scheduler.sh add <file.json>

# List all jobs
${CLAUDE_PLUGIN_ROOT}/scripts/scheduler/octopus-scheduler.sh list

# Remove a job
${CLAUDE_PLUGIN_ROOT}/scripts/scheduler/octopus-scheduler.sh remove <job-id>

# Enable/disable a job
${CLAUDE_PLUGIN_ROOT}/scripts/scheduler/octopus-scheduler.sh enable <job-id>
${CLAUDE_PLUGIN_ROOT}/scripts/scheduler/octopus-scheduler.sh disable <job-id>

# View logs
${CLAUDE_PLUGIN_ROOT}/scripts/scheduler/octopus-scheduler.sh logs [job-id]
```

## Instructions for Claude

When user invokes `/octo:schedule`:

1. Parse the subcommand from user arguments (add, list, remove, enable, disable, logs)
2. Display the visual indicator banner:

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Job Management
⏰ Schedule: [action description]

Providers:
🔵 Claude - Job configuration
```

3. Execute the appropriate `octopus-scheduler.sh` subcommand
4. Format and present results

## Job File Format

Jobs are JSON files with this structure:

```json
{
  "id": "nightly-security",
  "name": "Nightly Security Scan",
  "enabled": true,
  "schedule": { "cron": "0 2 * * *" },
  "task": {
    "workflow": "squeeze",
    "prompt": "Run security review on current repo."
  },
  "execution": {
    "workspace": "/path/to/project",
    "timeout_seconds": 3600
  },
  "budget": {
    "max_cost_usd_per_run": 5.0,
    "max_cost_usd_per_day": 15.0
  },
  "security": {
    "sandbox": "workspace-write",
    "deny_flags": ["--dangerously-skip-permissions"]
  }
}
```
