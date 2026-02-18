# Scheduled Workflow Runner

> **Version:** 8.15.0 | **Module:** `scripts/scheduler/` | **Dependencies:** `bash`, `jq`, `flock`, `setsid`, `mkfifo`

The Scheduled Workflow Runner adds daemon mode to Claude Octopus, enabling recurring multi-AI workflows like nightly security scans, morning research summaries, and periodic code reviews — all without a user at the terminal.

## Quick Start

```bash
# 1. Create a job definition
cat > nightly-security.json << 'EOF'
{
  "id": "nightly-security",
  "name": "Nightly Security Scan",
  "enabled": true,
  "schedule": { "cron": "0 2 * * *" },
  "task": {
    "workflow": "squeeze",
    "prompt": "Run security review on current repo and summarize critical risks."
  },
  "execution": {
    "workspace": "/Users/chris/git/my-project",
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
EOF

# 2. Add the job
octopus-scheduler.sh add nightly-security.json

# 3. Start the daemon
octopus-scheduler.sh start

# 4. Check status
octopus-scheduler.sh status

# 5. View logs
octopus-scheduler.sh logs nightly-security
```

Or through Claude Code:

```
/octo:schedule add nightly-security.json
/octo:scheduler start
/octo:scheduler status
```

---

## Architecture

```
scripts/scheduler/
  octopus-scheduler.sh   CLI entry point (start/stop/status/add/list/remove/...)
  daemon.sh              Main tick loop, PID management, heartbeat, FIFO IPC
  cron.sh                Pure Bash 5-field cron expression parser
  runner.sh              Job executor with lock, timeout, cost monitoring
  policy.sh              Pre-dispatch admission checks (budget, security, allowlist)
  store.sh               Atomic JSON state read/write, ledger, event log

hooks/
  scheduler-security-gate.sh   PreToolUse hook restricting scheduled job capabilities
```

The scheduler is a standalone module — it does not modify `orchestrate.sh`. It wraps `orchestrate.sh` calls with locking, monitoring, and cost controls.

---

## How It Works

### Daemon Lifecycle

1. **Start** (`octopus-scheduler.sh start`)
   - Writes PID to `~/.claude-octopus/scheduler/runtime/daemon.pid`
   - Creates a named pipe (FIFO) at `runtime/control.fifo` for CLI-to-daemon communication
   - Registers signal handlers: SIGTERM for graceful shutdown, SIGINT for immediate stop
   - Enters the main tick loop

2. **Tick Loop** (every 30 seconds, drift-corrected)
   - Touches `runtime/heartbeat` to prove liveness
   - Reads any pending commands from the FIFO (status, pause, resume, stop)
   - Checks kill switches (`switches/KILL_ALL`, `switches/PAUSE_ALL`)
   - Iterates over enabled jobs in `jobs/*.json`
   - For each job whose cron expression matches the current time:
     - Runs all policy checks (budget, security, workspace, workflow allowlist)
     - Dispatches to `runner.sh` if the orchestrate lock is available
   - Only one job dispatches per tick (non-reentrant lock prevents parallel orchestrate.sh runs)

3. **Stop** (`octopus-scheduler.sh stop`)
   - Sends SIGTERM to the daemon PID
   - Waits up to 30 seconds for the current job to finish
   - Force-kills with SIGKILL if graceful shutdown times out
   - Cleans up PID file

### Job Execution

When the daemon dispatches a job, `runner.sh` handles execution:

1. **Lock acquisition** — Takes an exclusive `flock` on `runtime/orchestrate.lock`. If another job holds the lock, the run is skipped with status `lock_failed`.

2. **Environment setup** — Sets `OCTOPUS_JOB_ID`, `OCTOPUS_RUN_ID`, and `OCTOPUS_MAX_COST_USD` for the job. These environment variables activate the security gate hook.

3. **Process isolation** — Spawns `orchestrate.sh <workflow> "<prompt>"` via `setsid` in its own process group, `cd`'d into the job's workspace.

4. **Monitoring loop** — Every second while the job runs:
   - **Timeout**: If elapsed time exceeds `timeout_seconds`, kills the entire process group
   - **Cost**: Every 15 seconds, reads `metrics-session.json` in the workspace. If cost exceeds `max_cost_usd_per_run`, kills the process group
   - **Kill switch**: If `switches/KILL_ALL` appears, kills the process group immediately

5. **Cleanup** — Records run metadata (status, duration, cost, exit code) to `runs/<run-id>.json`, updates the daily cost ledger, and appends to the event log.

### Exit Codes

| Code | Status | Meaning |
|------|--------|---------|
| 0 | `completed` | Job finished successfully |
| 1 | `failed` | Job exited with an error |
| 1 | `lock_failed` | Could not acquire orchestrate lock |
| 124 | `timeout` | Job exceeded `timeout_seconds` |
| 125 | `cost_limit` | Job exceeded `max_cost_usd_per_run` |
| 130 | `killed` | Job terminated by KILL_ALL switch |

---

## Job Definition Format

Jobs are JSON files stored in `~/.claude-octopus/scheduler/jobs/`. Each file defines one recurring workflow.

```json
{
  "id": "nightly-security",
  "name": "Nightly Security Scan",
  "enabled": true,
  "schedule": {
    "cron": "0 2 * * *"
  },
  "task": {
    "workflow": "squeeze",
    "prompt": "Run security review on current repo and summarize critical risks."
  },
  "execution": {
    "workspace": "/Users/chris/git/my-project",
    "timeout_seconds": 3600,
    "resume_on_restart": false
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

### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes | Unique identifier (used as filename, referenced in logs) |
| `name` | string | no | Human-readable name for display |
| `enabled` | boolean | yes | Whether the job is active |
| `schedule.cron` | string | yes | 5-field cron expression or shortcut |
| `task.workflow` | string | yes | Octopus workflow to run (see allowed list below) |
| `task.prompt` | string | yes | Prompt passed to `orchestrate.sh` |
| `execution.workspace` | string | yes | Absolute path to the project directory |
| `execution.timeout_seconds` | number | no | Max runtime before kill (default: 3600) |
| `budget.max_cost_usd_per_run` | number | no | Per-run cost ceiling (0 = unlimited) |
| `budget.max_cost_usd_per_day` | number | no | Daily cost ceiling across all jobs (0 = unlimited) |
| `security.sandbox` | string | no | Sandbox mode passed to Codex CLI |
| `security.deny_flags` | array | no | Flags that must not appear anywhere in execution |

### Allowed Workflows

Only these `orchestrate.sh` subcommands are permitted in scheduled jobs:

| Workflow | Phase | Description |
|----------|-------|-------------|
| `probe` | Discover | Multi-AI research and exploration |
| `grasp` | Define | Requirements clarification and scoping |
| `tangle` | Develop | Implementation with quality gates |
| `ink` | Deliver | Validation and review |
| `embrace` | All 4 | Full Double Diamond cycle |
| `squeeze` | Review | Security and quality audit |
| `grapple` | Debate | Multi-AI deliberation |

---

## Cron Expressions

The scheduler includes a pure Bash cron parser supporting standard 5-field expressions.

### Format

```
 .---------------- minute (0-59)
 |  .------------- hour (0-23)
 |  |  .---------- day of month (1-31)
 |  |  |  .------- month (1-12)
 |  |  |  |  .---- day of week (0-6, 0=Sunday)
 |  |  |  |  |
 *  *  *  *  *
```

### Syntax

| Syntax | Meaning | Example |
|--------|---------|---------|
| `*` | Every value | `* * * * *` = every minute |
| `N` | Exact value | `30 * * * *` = at minute 30 |
| `N-M` | Range | `0 9-17 * * *` = hours 9 through 17 |
| `*/S` | Step | `*/15 * * * *` = every 15 minutes |
| `N-M/S` | Range with step | `0-30/10 * * * *` = minutes 0, 10, 20, 30 |
| `N,M,O` | List | `0 2,14 * * *` = at 2:00 and 14:00 |

### Shortcuts

| Shortcut | Equivalent | Meaning |
|----------|------------|---------|
| `@yearly` | `0 0 1 1 *` | Once a year (Jan 1, midnight) |
| `@monthly` | `0 0 1 * *` | First of each month, midnight |
| `@weekly` | `0 0 * * 0` | Every Sunday, midnight |
| `@daily` | `0 0 * * *` | Every day, midnight |
| `@hourly` | `0 * * * *` | Top of every hour |

### Day-of-Month + Day-of-Week

When both day-of-month and day-of-week are specified (not `*`), the scheduler uses **OR logic** — matching either field triggers the job. This follows standard cron behavior.

```
0 0 15 * 1    # Runs on the 15th of every month OR every Monday
```

### Common Patterns

```bash
0 2 * * *       # Every night at 2:00 AM
0 9 * * 1-5     # Weekdays at 9:00 AM
*/15 * * * *    # Every 15 minutes
0 0 1 * *       # First of every month
0 */6 * * *     # Every 6 hours
30 8 * * 1      # Every Monday at 8:30 AM
```

---

## CLI Reference

All commands are available through `octopus-scheduler.sh` directly or via Claude Code commands (`/octo:scheduler`, `/octo:schedule`).

### Daemon Management

| Command | Description |
|---------|-------------|
| `start` | Start the daemon in the foreground (logs to `daemon.log`) |
| `stop` | Graceful shutdown — sends SIGTERM, waits for current job to finish |
| `status` | Show daemon state, heartbeat age, job count, daily spend |
| `emergency-stop` | Kill everything and create the KILL_ALL switch file |

### Job Management

| Command | Description |
|---------|-------------|
| `add <file.json>` | Validate and copy a job definition to the jobs directory |
| `list` | Show all jobs with ID, name, enabled status, schedule, next run |
| `remove <id>` | Delete a job by its ID |
| `enable <id>` | Set a job's `enabled` field to `true` |
| `disable <id>` | Set a job's `enabled` field to `false` |
| `logs [id]` | Tail the daemon log, or a specific job's latest log |

### Examples

```bash
# Start daemon in background
nohup octopus-scheduler.sh start &

# Add a morning research job
octopus-scheduler.sh add morning-research.json

# List all jobs with next run times
octopus-scheduler.sh list

# Disable a job temporarily
octopus-scheduler.sh disable nightly-security

# Check what's happening
octopus-scheduler.sh status

# View the last run's log for a job
octopus-scheduler.sh logs nightly-security

# Something went wrong — stop everything
octopus-scheduler.sh emergency-stop
```

---

## Security Model

The scheduler enforces security at three layers: **admission** (before a job starts), **runtime** (while a job runs), and **emergency** (manual override).

### Admission Layer (`policy.sh`)

Every job must pass these checks before it can run:

| Check | What it prevents |
|-------|-----------------|
| **Workflow allowlist** | Only `probe`, `grasp`, `tangle`, `ink`, `embrace`, `squeeze`, `grapple` are permitted. Arbitrary commands cannot run. |
| **Workspace validation** | Path must be absolute, must exist, cannot be `/`, cannot contain `..`. Prevents path traversal. |
| **Deny-flags check** | `--dangerously-skip-permissions`, `--no-verify`, `--force-delete` are rejected if found anywhere in the job definition or prompt. |
| **Budget admission** | Compares daily spend (from `ledger/daily.json`) against the job's `max_cost_usd_per_day`. Blocks if exceeded. |
| **Kill switches** | Checks for `KILL_ALL` or `PAUSE_ALL` files in the switches directory. |

### Runtime Layer (`runner.sh` + `scheduler-security-gate.sh`)

While a job is running:

| Mechanism | What it prevents |
|-----------|-----------------|
| **Cost polling** | Reads `metrics-session.json` every 15 seconds. Kills the process group if `max_cost_usd_per_run` is exceeded. |
| **Timeout enforcement** | Kills the process group if `timeout_seconds` is exceeded. |
| **Security gate hook** | A PreToolUse hook (active when `OCTOPUS_JOB_ID` is set) that blocks `--dangerously-skip-permissions` in Bash commands, blocks destructive `rm -rf` on sensitive paths, and restricts Read/Write/Edit tools to within the job's workspace directory. |
| **Non-reentrant lock** | `flock` on `orchestrate.lock` ensures only one workflow runs at a time. |
| **Process group isolation** | `setsid` puts orchestrate.sh and all its children (Codex CLI, Gemini CLI) in a separate process group. `kill -- -$PGID` terminates the entire tree. |

### Emergency Layer

| Switch | Effect |
|--------|--------|
| `touch ~/.claude-octopus/scheduler/switches/KILL_ALL` | Daemon stops. All running jobs are killed. No new jobs can start until the file is removed. |
| `touch ~/.claude-octopus/scheduler/switches/PAUSE_ALL` | No new jobs dispatch. Running jobs continue to completion. Remove the file to resume. |
| `octopus-scheduler.sh emergency-stop` | Creates `KILL_ALL` and stops the daemon in one command. |

---

## Runtime State

All scheduler state lives under `~/.claude-octopus/scheduler/`:

```
~/.claude-octopus/scheduler/
  jobs/                          Job definitions (JSON files)
    nightly-security.json
    morning-research.json

  runs/                          Run history (one JSON per execution)
    run-20260216-020000-nightly-security.json

  runtime/
    daemon.pid                   Daemon PID (flock-protected)
    heartbeat                    Touch file (mtime = last tick)
    orchestrate.lock             Global non-reentrant lock
    control.fifo                 Named pipe for CLI -> daemon IPC

  logs/
    daemon.log                   Daemon stdout/stderr
    nightly-security/            Per-job log directories
      2026-02-16T02:00:00.log

  ledger/
    daily.json                   Daily cost tracking (auto-resets at midnight)
    events.jsonl                 Append-only event log

  switches/
    KILL_ALL                     Touch file = emergency stop
    PAUSE_ALL                    Touch file = pause new dispatches
```

### Daily Ledger (`ledger/daily.json`)

```json
{
  "date": "2026-02-16",
  "total_cost_usd": 3.75,
  "runs": 2,
  "last_job": "nightly-security",
  "last_updated": "2026-02-16T02:45:00Z"
}
```

Automatically resets when the date changes. Used by the budget admission check to enforce `max_cost_usd_per_day`.

### Run Record (`runs/run-*.json`)

```json
{
  "run_id": "run-20260216-020000-nightly-security",
  "job_id": "nightly-security",
  "status": "completed",
  "started_at": "2026-02-16T02:00:00Z",
  "ended_at": "2026-02-16T02:23:17Z",
  "exit_code": 0,
  "cost_usd": 1.85
}
```

### Event Log (`ledger/events.jsonl`)

Append-only, one JSON object per line:

```jsonl
{"event":"run_started","run_id":"run-20260216-020000-nightly-security","job_id":"nightly-security","timestamp":"2026-02-16T02:00:00Z"}
{"event":"run_finished","run_id":"run-20260216-020000-nightly-security","job_id":"nightly-security","status":"completed","exit_code":0,"cost_usd":1.85,"timestamp":"2026-02-16T02:23:17Z"}
{"event":"job_blocked","job_id":"morning-research","reason":"Daily budget exhausted","timestamp":"2026-02-16T09:00:00Z"}
```

---

## Cost Control

The scheduler provides three independent layers of cost protection:

### 1. Budget Admission (pre-dispatch)

Before a job starts, `policy.sh` reads `ledger/daily.json` and compares total daily spend against the job's `max_cost_usd_per_day`. If the daily limit is already reached, the job is blocked and logged as `job_blocked`.

### 2. Runtime Cost Polling (during execution)

While a job runs, `runner.sh` reads `metrics-session.json` from the workspace every 15 seconds. If cost exceeds `max_cost_usd_per_run`, the entire process group is killed (exit code 125, status `cost_limit`).

### 3. Emergency Kill Switch (manual override)

Creating `~/.claude-octopus/scheduler/switches/KILL_ALL` immediately terminates all running jobs and stops the daemon. This is the "big red button" for when something goes wrong.

### Cost Estimates per Provider

| Provider | Cost per Query | Notes |
|----------|---------------|-------|
| Codex CLI | ~$0.01-0.15 | Depends on model (GPT-5.3-Codex, Spark, Mini) |
| Gemini CLI | ~$0.01-0.03 | Gemini Pro |
| Claude (Sonnet 4.6) | Included | Part of Claude Code subscription |
| Claude (Opus 4.6) | $5/$25 per MTok | Input/output pricing |

A typical `squeeze` (security review) job using all three providers costs roughly $0.10-0.50 per run.

---

## Data Integrity

All JSON writes use the atomic write pattern from `state-manager.sh`:

1. Write content to a temporary file (`target.tmp.$$`)
2. Validate JSON with `jq empty` — if invalid, delete the temp file and abort
3. Back up the existing file to `target.bak`
4. Atomically move (`mv`) the temp file to the target path

This prevents corruption from partial writes, crashes, or concurrent access.

---

## Troubleshooting

### Daemon won't start

```
Daemon already running (PID 12345)
```

A previous daemon is still running or left a stale PID file. Check with `kill -0 12345`. If the process doesn't exist, remove the stale PID file:

```bash
rm ~/.claude-octopus/scheduler/runtime/daemon.pid
```

### Job won't dispatch

Check the daemon log:

```bash
octopus-scheduler.sh logs
```

Common reasons:
- **Policy blocked**: Budget exceeded, invalid workflow, workspace doesn't exist
- **Lock held**: Another job is currently running (only one at a time)
- **Kill switch active**: Check for `KILL_ALL` or `PAUSE_ALL` files
- **Job disabled**: Run `octopus-scheduler.sh enable <id>`
- **Cron mismatch**: The daemon checks every 30 seconds. If a cron expression matches a specific minute, the 30-second tick window should catch it, but verify with `octopus-scheduler.sh list` to see computed next run times.

### Job starts but fails immediately

Check the job-specific log:

```bash
octopus-scheduler.sh logs <job-id>
```

Common causes:
- `orchestrate.sh` not found (check plugin directory structure)
- Workspace directory doesn't exist or has permission issues
- Missing API keys (`OPENAI_API_KEY`, `GEMINI_API_KEY`)

### Emergency recovery

```bash
# Stop everything immediately
octopus-scheduler.sh emergency-stop

# Check what happened
cat ~/.claude-octopus/scheduler/logs/daemon.log
cat ~/.claude-octopus/scheduler/ledger/events.jsonl

# Clear the kill switch when ready to resume
rm ~/.claude-octopus/scheduler/switches/KILL_ALL

# Restart
octopus-scheduler.sh start
```

---

## Example Job Definitions

### Nightly Security Scan

```json
{
  "id": "nightly-security",
  "name": "Nightly Security Scan",
  "enabled": true,
  "schedule": { "cron": "0 2 * * *" },
  "task": {
    "workflow": "squeeze",
    "prompt": "Run security review on current repo. Check for dependency vulnerabilities, exposed secrets, and OWASP top 10 issues. Summarize critical risks."
  },
  "execution": {
    "workspace": "/Users/chris/git/my-app",
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

### Morning Research Summary

```json
{
  "id": "morning-research",
  "name": "Morning Research Summary",
  "enabled": true,
  "schedule": { "cron": "0 8 * * 1-5" },
  "task": {
    "workflow": "probe",
    "prompt": "Research latest developments in our tech stack (React, Node.js, PostgreSQL). Focus on security advisories, major releases, and deprecations from the past week."
  },
  "execution": {
    "workspace": "/Users/chris/git/my-app",
    "timeout_seconds": 1800
  },
  "budget": {
    "max_cost_usd_per_run": 2.0,
    "max_cost_usd_per_day": 10.0
  },
  "security": {
    "sandbox": "workspace-write",
    "deny_flags": ["--dangerously-skip-permissions"]
  }
}
```

### Weekly Architecture Review

```json
{
  "id": "weekly-architecture",
  "name": "Weekly Architecture Review",
  "enabled": true,
  "schedule": { "cron": "0 10 * * 1" },
  "task": {
    "workflow": "embrace",
    "prompt": "Full architecture review of the codebase. Identify technical debt, suggest refactoring opportunities, and flag any patterns that deviate from our conventions."
  },
  "execution": {
    "workspace": "/Users/chris/git/my-app",
    "timeout_seconds": 7200
  },
  "budget": {
    "max_cost_usd_per_run": 10.0,
    "max_cost_usd_per_day": 20.0
  },
  "security": {
    "sandbox": "workspace-write",
    "deny_flags": ["--dangerously-skip-permissions"]
  }
}
```
