---
description: "\"Manage scheduled workflow jobs (add via wizard, dashboard, list, remove, enable, disable, logs)\""
---

# Schedule

## MANDATORY COMPLIANCE — DO NOT SKIP

**When the user invokes `/octo:schedule`, you MUST use the scheduler CLI below. You are PROHIBITED from:**
- Managing cron jobs or schedules manually without the scheduler
- Skipping the scheduler subcommands and just editing files directly
- Substituting `crontab -e` or manual file edits for the scheduler interface

**The user chose `/octo:schedule` for the managed scheduler workflow.**

---

Manage scheduled workflow jobs for the Claude Octopus scheduler.

## Usage

```bash
${HOME}/.claude-octopus/plugin/scripts/scheduler/octopus-scheduler.sh [subcommand]
```

## Instructions for Claude

This command supports **natural language** and provides two primary experiences:
- **No args / "show jobs" / "what's scheduled"** → Dashboard table
- **"add a job" / "schedule X" / `add` with no file** → Guided wizard

---

### Step 0: Parse Intent First

| User says | Action |
|-----------|--------|
| No args, "show jobs", "status", "what's scheduled", "list" | **Dashboard** (Step 1A) |
| Describes a new job, "add", "create", "schedule a...", any time/frequency reference | **Wizard** (Step 1B) |
| "remove", "delete" + job name/id | Run `remove <id>` directly |
| "enable", "turn on" + job reference | Run `enable <id>` |
| "disable", "pause", "turn off" + job reference | Run `disable <id>` |
| "logs", "what happened", "last run" | Run `logs [id]` + summarize |
| Wants to change schedule/budget/prompt on existing job | **Modify** (Step 1C) |

If intent is ambiguous, show the dashboard first, then ask what they'd like to do.

---

### Step 1A: Dashboard (No-args / List)

Display the banner, then run:

```bash
${HOME}/.claude-octopus/plugin/scripts/scheduler/octopus-scheduler.sh dashboard
```

Present the output as-is. After showing it, offer quick actions:
```
What would you like to do?
• Add a new job
• Enable/disable a job
• View logs for a job
• Remove a job
```

---

### Step 1B: Wizard — Guided Job Creation (MANDATORY for new jobs without a file arg)

Display banner:
```
🐙 CLAUDE OCTOPUS ACTIVATED — Job Wizard
⏰ Schedule: Creating a new scheduled job

Providers:
🔵 Claude — Job configuration
```

**You MUST ask these questions via AskUserQuestion:**

```yaml
Question 1:
  question: "What should this job do?"
  header: "Task"
  multiSelect: false
  options:
    - label: "Security scan"
      description: "Nightly vulnerability and code quality audit (squeeze workflow)"
    - label: "Research digest"
      description: "Research a topic and summarize findings (probe workflow)"
    - label: "Full review"
      description: "Complete 4-phase Double Diamond analysis (embrace workflow)"
    - label: "Custom task"
      description: "Describe what you want in your own words"

Question 2:
  question: "How often should it run?"
  header: "Schedule"
  multiSelect: false
  options:
    - label: "Every night at 2am"
      description: "cron: 0 2 * * *"
    - label: "Every weekday morning"
      description: "cron: 0 9 * * 1-5"
    - label: "Weekly (Sunday night)"
      description: "cron: 0 22 * * 0"
    - label: "Custom schedule"
      description: "Describe the timing in natural language"

Question 3:
  question: "Which project/directory should it run in?"
  header: "Workspace"
  multiSelect: false
  options:
    - label: "Current directory"
      description: "Use the current working directory"
    - label: "Specify a path"
      description: "I'll enter the full path"
```

**WAIT for the user's answers before proceeding.**

**After answers, generate the JSON job definition:**

Map user answers:
| User says | workflow | cron |
|-----------|----------|------|
| Security scan | `squeeze` | `0 2 * * *` |
| Research digest | `probe` | user's choice |
| Full review | `embrace` | user's choice |
| Custom | infer from description | parse time expression |

**Cron translation (natural language → cron):**
| Phrase | Cron |
|--------|------|
| every night / nightly | `0 2 * * *` |
| every morning / daily | `0 9 * * *` |
| weekday mornings | `0 9 * * 1-5` |
| weekly / every week | `0 22 * * 0` |
| hourly | `@hourly` |
| every N minutes | `*/N * * * *` |
| every Monday at Xam | `0 X * * 1` |

**Generate job slug:** "Nightly Security Scan" → `nightly-security`

**Show the generated definition for user confirmation:**
```json
{
  "id": "<slug>",
  "name": "<Full Name>",
  "enabled": true,
  "backend": "<detected — see Step 2>",
  "schedule": { "cron": "<expression>" },
  "task": {
    "workflow": "<workflow>",
    "prompt": "<expanded description>"
  },
  "execution": {
    "workspace": "<path>",
    "timeout_seconds": 3600
  },
  "budget": {
    "max_cost_usd_per_run": 5.0,
    "max_cost_usd_per_day": 15.0
  },
  "security": {
    "sandbox": "workspace-write"
  }
}
```

Ask: "Does this look right? (yes to save / no to adjust)"

---

### Step 2: Backend Detection (MANDATORY — run before saving any job)

This step determines which execution backend to use and sets `"backend"` in the job JSON.

**Check 1 — User override wins:**
```bash
backend_pref="${OCTOPUS_SCHEDULER_BACKEND:-auto}"
```
- If `daemon` → set `backend: daemon`, skip further checks
- If `coworkd` → attempt detection; error loudly if unavailable (do NOT fall back)

**Check 2 — Detect CronCreate availability (inside CC session):**

Use ToolSearch to check if CronCreate is available:
```
ToolSearch("select:CronCreate")
```
- If CronCreate loads successfully → set `backend: coworkd`
- If ToolSearch returns nothing / errors → proceed to Check 3

**Check 3 — CC version threshold (bash fallback):**
```bash
if command -v claude &>/dev/null; then
    cc_version=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    # CronCreate available in CC v2.1.70+
    # Use version comparison from detect_claude_code_version() in orchestrate.sh
fi
```
- CC ≥ 2.1.70 → set `backend: coworkd`
- CC < 2.1.70 or not installed → set `backend: daemon`

**Display detection result:**
```
Backend detected: coworkd (CronCreate available)
  — Job will run in isolated coworkd VM with CC task visibility
```
or:
```
Backend detected: daemon (Claude Code not available / older version)
  — Job will run via bash daemon with file-based logging
```

---

### Step 3: Save and Register

**Write JSON to temp file:**
```bash
TMPFILE=$(mktemp /tmp/octo-job-XXXXXX.json)
# Write confirmed JSON with backend field set
```

**Register via detected backend:**

**If `backend: coworkd`:**
```
Use CronCreate tool with:
  - prompt: job's task.prompt
  - schedule: job's schedule.cron
  - workspace: job's execution.workspace
```
Then store the job JSON (with `backend: coworkd`) to `~/.claude-octopus/scheduler/jobs/<id>.json` for dashboard display and audit.

**If `backend: daemon`:**
```bash
${HOME}/.claude-octopus/plugin/scripts/scheduler/octopus-scheduler.sh add "$TMPFILE"
```
Ensure the daemon is running:
```bash
${HOME}/.claude-octopus/plugin/scripts/scheduler/octopus-scheduler.sh status | grep -q "RUNNING" || \
  ${HOME}/.claude-octopus/plugin/scripts/scheduler/octopus-scheduler.sh start
```

**Cleanup:**
```bash
rm -f "$TMPFILE"
```

---

### Step 1C: Modify Existing Job

When user wants to change schedule, budget, prompt, or timeout:

1. Read job file: `~/.claude-octopus/scheduler/jobs/<id>.json`
2. Apply requested changes
3. Show diff inline
4. Write via `store_atomic_write` pattern (temp → validate → mv)
5. If `backend: coworkd`, update CronCreate registration (remove old + create new)

---

### Step 4: Present Results

After any action:

- **add/wizard**: Show job summary with backend, next run, budget. Offer: "View dashboard" or "Add another job"
- **dashboard**: Show table output + quick actions
- **remove**: Confirm which job was removed, show updated count
- **logs**: Summarize last run (status, duration, cost, errors)
- **enable/disable**: Confirm state change

---

## Job File Format

```json
{
  "id": "nightly-security",
  "name": "Nightly Security Scan",
  "enabled": true,
  "backend": "daemon",
  "schedule": { "cron": "0 2 * * *" },
  "task": {
    "workflow": "squeeze",
    "prompt": "Run security review on current repo. Focus on OWASP top 10 and auth flows."
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

**`backend` field values:**
- `"daemon"` — executed by octopus-scheduler bash daemon via setsid + orchestrate.sh
- `"coworkd"` — registered with CronCreate; executed in coworkd VM (daemon ignores these jobs)

### Allowed Workflows

`probe` | `grasp` | `tangle` | `ink` | `embrace` | `squeeze` | `grapple`
