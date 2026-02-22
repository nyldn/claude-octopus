---
command: sentinel
description: GitHub-aware work monitor - triages issues, PRs, and CI failures
version: 1.0.0
category: monitoring
tags: [sentinel, github, triage, issues, ci, monitoring]
created: 2026-02-21
updated: 2026-02-21
---

# Sentinel (/octo:sentinel)

GitHub-aware work monitor that triages issues, PRs, and CI failures. Sentinel observes and recommends workflows but never auto-executes them.

## Usage

```bash
/octo:sentinel              # One-time triage scan
/octo:sentinel --watch       # Continuous monitoring
```

## What Sentinel Monitors

| Source | Filter | Recommended Action |
|--------|--------|--------------------|
| Issues | `octopus` label | Classified via task type → workflow recommendation |
| PRs | Review requested | `/octo:ink` for code review |
| CI Runs | Failed status | `/octo:debug` for investigation |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OCTOPUS_SENTINEL_ENABLED` | `false` | Must be `true` to activate |
| `OCTOPUS_SENTINEL_INTERVAL` | `600` | Poll interval for --watch mode (seconds) |

## Safety

Sentinel is **triage-only**. It:
- Reads GitHub state (issues, PRs, CI runs)
- Classifies and recommends workflows
- Writes findings to `.octo/sentinel/triage-log.md`
- **Never** auto-executes any workflow

## Requirements

- GitHub CLI (`gh`) must be installed and authenticated
- Repository must be a GitHub repository

## EXECUTION CONTRACT (Mandatory)

When the user invokes `/octo:sentinel`, you MUST:

### 1. Check Prerequisites
- Verify `OCTOPUS_SENTINEL_ENABLED=true` is set
- Verify `gh` CLI is available

### 2. Execute Sentinel
```bash
OCTOPUS_SENTINEL_ENABLED=true bash scripts/orchestrate.sh sentinel $ARGUMENTS
```

### 3. Present Results
- Show triaged items with recommended workflows
- Display path to triage log
- If --watch mode, explain how to stop (Ctrl+C)
