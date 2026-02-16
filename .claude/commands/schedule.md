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
${CLAUDE_PLUGIN_ROOT}/scripts/scheduler/octopus-scheduler.sh add <file.json>
${CLAUDE_PLUGIN_ROOT}/scripts/scheduler/octopus-scheduler.sh list
${CLAUDE_PLUGIN_ROOT}/scripts/scheduler/octopus-scheduler.sh remove <job-id>
${CLAUDE_PLUGIN_ROOT}/scripts/scheduler/octopus-scheduler.sh enable <job-id>
${CLAUDE_PLUGIN_ROOT}/scripts/scheduler/octopus-scheduler.sh disable <job-id>
${CLAUDE_PLUGIN_ROOT}/scripts/scheduler/octopus-scheduler.sh logs [job-id]
```

## Instructions for Claude

This command supports **natural language**. Users can describe jobs conversationally and you MUST translate their intent into the correct CLI actions, generating JSON job files as needed.

### Step 1: Parse Intent

Map the user's input to an action:

| Intent patterns | Action |
|----------------|--------|
| Describes a new job, mentions a schedule/time/frequency, "add", "create", "set up", "schedule a..." | **Create job** (generate JSON + `add`) |
| "list", "show", "what jobs", "what's scheduled" | `list` |
| "remove", "delete", "get rid of", mentions a job by name/id | `remove <id>` |
| "enable", "turn on", "activate", "resume" + job reference | `enable <id>` |
| "disable", "pause", "turn off", "skip" + job reference | `disable <id>` |
| "logs", "what happened", "show output", "last run" | `logs [id]` |
| Wants to change schedule, budget, prompt, or timeout of existing job | **Modify job** (read, edit, rewrite JSON) |

If the intent is ambiguous, use AskUserQuestion to clarify.

### Step 2: Display Banner

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Job Management
⏰ Schedule: [action description]

Providers:
🔵 Claude - Job configuration
```

### Step 3: For Natural Language Job Creation

When the user describes a job in natural language (e.g., "run a security scan every night at 2am on my-project"):

1. **Extract these fields from their description:**

   | Field | How to infer |
   |-------|-------------|
   | `id` | Slug from name: "Nightly Security Scan" → `nightly-security` |
   | `name` | From their description or ask |
   | `schedule.cron` | Parse time references (see Cron Translation below) |
   | `task.workflow` | Map task type to workflow (see Workflow Mapping below) |
   | `task.prompt` | Use their description, expand if too terse |
   | `execution.workspace` | Current working directory if not specified, or ask |
   | `execution.timeout_seconds` | Default 3600; use 1800 for research, 7200 for embrace |
   | `budget.max_cost_usd_per_run` | Default 5.0; ask if the user seems cost-conscious |
   | `budget.max_cost_usd_per_day` | Default 15.0 |

2. **Show the user the generated job definition** before saving. Confirm they're happy with it.

3. **Write the JSON to a temp file** and run `octopus-scheduler.sh add <file>`.

### Cron Translation

Map natural language time expressions to cron:

| User says | Cron expression |
|-----------|----------------|
| "every night at 2am" | `0 2 * * *` |
| "every morning at 9" | `0 9 * * *` |
| "weekdays at 8:30am" | `30 8 * * 1-5` |
| "every hour" | `@hourly` |
| "daily", "every day" | `@daily` |
| "weekly", "every week" | `@weekly` |
| "every Monday at 10am" | `0 10 * * 1` |
| "every 15 minutes" | `*/15 * * * *` |
| "twice a day at 9am and 5pm" | `0 9,17 * * *` |
| "first of the month" | `0 0 1 * *` |
| "every 6 hours" | `0 */6 * * *` |
| "Sunday nights" | `0 22 * * 0` |
| "end of business weekdays" | `0 17 * * 1-5` |

If the time is ambiguous (e.g., "every morning"), pick a sensible default and confirm with the user.

### Workflow Mapping

Map task descriptions to orchestrate.sh workflows:

| User describes | Workflow | Rationale |
|---------------|----------|-----------|
| security scan, vulnerability check, audit | `squeeze` | Security-focused review |
| research, explore, investigate, what's new | `probe` | Discovery/research phase |
| code review, quality check | `squeeze` | Quality audit |
| full review, complete analysis | `embrace` | All 4 Diamond phases |
| define requirements, scope, plan | `grasp` | Definition phase |
| build, implement, develop | `tangle` | Development phase |
| test, validate, verify | `ink` | Delivery/validation phase |
| compare, debate, evaluate options | `grapple` | Multi-AI deliberation |

If the task doesn't clearly map, ask the user which workflow they want.

### Step 4: For Modifying Existing Jobs

When the user wants to change an existing job:

1. Read the job file from `~/.claude-octopus/scheduler/jobs/<id>.json`
2. Apply the requested changes (new schedule, budget, prompt, etc.)
3. Show the user the diff
4. Write the updated JSON using `store_atomic_write` pattern (write to temp, validate, move)

### Step 5: Present Results

After any action, present human-readable output:
- After **add**: Show job summary with next run time
- After **list**: Format as a clean table, highlight disabled jobs, show next run times
- After **remove**: Confirm which job was removed
- After **modify**: Show what changed
- After **logs**: Summarize the log (last run status, duration, cost, any errors)

### Natural Language Examples

**Creating jobs:**
- "schedule a security scan every night at 2am" → generate JSON, `add`
- "run research on our tech stack every Monday morning" → generate JSON with `probe` workflow, `0 9 * * 1`
- "set up a weekly code review on Fridays at 5pm" → generate JSON with `squeeze` workflow, `0 17 * * 5`
- "add a daily research digest at 8am on weekdays" → generate JSON with `probe`, `0 8 * * 1-5`

**Managing jobs:**
- "what's scheduled?" → `list`
- "show me the nightly security logs" → `logs nightly-security`
- "pause the morning research" → `disable morning-research`
- "turn the morning research back on" → `enable morning-research`
- "delete the weekly review" → `remove weekly-review`
- "change the security scan to run at 3am instead" → read JSON, update cron, rewrite
- "increase the budget on nightly-security to $10 per run" → read JSON, update budget, rewrite
- "what happened on the last security scan?" → `logs nightly-security` + summarize

## Job File Format

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

### Allowed Workflows

`probe` | `grasp` | `tangle` | `ink` | `embrace` | `squeeze` | `grapple`
