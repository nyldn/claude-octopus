---
name: skill-doctor
description: "Environment diagnostics — check providers, auth, config, hooks, scheduler, and more"
trigger: |
  AUTOMATICALLY ACTIVATE when user asks about:
  - "doctor" or "run doctor" or "diagnostics"
  - "check my setup" or "is everything working"
  - "health check" or "environment check"
  - "what's wrong with my setup" or "why isn't octopus working"
  - "check providers" or "check auth" or "check hooks"

  DO NOT activate for:
  - Initial setup (use /octo:setup)
  - Project status or workflow progress (use /octo:status)
  - Debugging application code (use /octo:debug)
---

# Environment Doctor

## Overview

Run environment diagnostics across 10 check categories. Identifies misconfigured providers, stale state, broken hooks, and other issues that prevent Claude Octopus from working correctly.

**Core principle:** Detect problems before they surface in workflows.

---

## When to Use

**Use this skill when:**
- Something isn't working and you're not sure why
- After installing or updating the plugin
- Before a demo or important workflow run
- Checking if providers are properly authenticated
- Verifying scheduler, hooks, or skills are correctly configured

**Do NOT use for:**
- First-time setup (use `/octo:setup` — it guides configuration)
- Project workflow status (use `/octo:status`)
- Debugging application code (use `/octo:debug`)

---

## The Process

### Step 1: Run Full Diagnostics

```bash
cd "${CLAUDE_PLUGIN_ROOT}" && bash scripts/orchestrate.sh doctor
```

This runs all 10 check categories and displays a formatted report.

### Step 2: Filter by Category (Optional)

If the user asks about a specific area, filter:

```bash
cd "${CLAUDE_PLUGIN_ROOT}" && bash scripts/orchestrate.sh doctor providers
cd "${CLAUDE_PLUGIN_ROOT}" && bash scripts/orchestrate.sh doctor auth
cd "${CLAUDE_PLUGIN_ROOT}" && bash scripts/orchestrate.sh doctor config
cd "${CLAUDE_PLUGIN_ROOT}" && bash scripts/orchestrate.sh doctor state
cd "${CLAUDE_PLUGIN_ROOT}" && bash scripts/orchestrate.sh doctor smoke
cd "${CLAUDE_PLUGIN_ROOT}" && bash scripts/orchestrate.sh doctor hooks
cd "${CLAUDE_PLUGIN_ROOT}" && bash scripts/orchestrate.sh doctor scheduler
cd "${CLAUDE_PLUGIN_ROOT}" && bash scripts/orchestrate.sh doctor skills
cd "${CLAUDE_PLUGIN_ROOT}" && bash scripts/orchestrate.sh doctor conflicts
cd "${CLAUDE_PLUGIN_ROOT}" && bash scripts/orchestrate.sh doctor agents
```

### Step 3: Verbose or JSON Output

```bash
# Detailed output for troubleshooting
cd "${CLAUDE_PLUGIN_ROOT}" && bash scripts/orchestrate.sh doctor --verbose

# Machine-readable output
cd "${CLAUDE_PLUGIN_ROOT}" && bash scripts/orchestrate.sh doctor --json

# Combine: specific category + verbose
cd "${CLAUDE_PLUGIN_ROOT}" && bash scripts/orchestrate.sh doctor auth --verbose
```

---

## Check Categories

| Category | What it checks |
|----------|---------------|
| `providers` | Claude Code version, Codex CLI installed, Gemini CLI installed, Perplexity API key |
| `auth` | Authentication status for each provider |
| `config` | Plugin version, install scope, feature flags |
| `state` | Project state.json, stale results, workspace writable |
| `smoke` | Smoke test cache, model configuration |
| `hooks` | hooks.json validity, hook scripts |
| `scheduler` | Scheduler daemon, jobs, budget gates, kill switches |
| `skills` | Skill files loaded and valid |
| `conflicts` | Conflicting plugins detection |
| `agents` | Agent definitions, worktree isolation, CLI registration, version compatibility |

---

## Interpreting Results

### Healthy Output

All checks pass — no action needed.

### Common Issues and Fixes

| Issue | Fix |
|-------|-----|
| Codex CLI not found | `npm install -g @openai/codex` or install via `codex login` |
| Gemini CLI not found | Install Gemini CLI from Google |
| Perplexity not configured | `export PERPLEXITY_API_KEY="pplx-..."` (optional) |
| Auth expired | Re-run `codex login` or `gemini login` |
| Stale state | Delete `.octo/state.json` and re-initialize |
| Invalid hooks.json | Check `hooks.json` syntax — must be valid JSON |
| Conflicting plugins | Uninstall conflicting plugins or adjust scope |

---

## Integration with Other Skills

| Scenario | Route |
|----------|-------|
| Doctor finds missing provider | Suggest `/octo:setup` to configure |
| Doctor finds stale project state | Suggest `/octo:status` to review |
| Doctor finds hook errors | Guide user to fix hooks.json |
| All checks pass, user still has issues | Suggest `/octo:debug` for deeper investigation |

---

## Quick Reference

| User Input | Action |
|------------|--------|
| `/octo:doctor` | Run all 10 categories |
| `/octo:doctor providers` | Check provider installation only |
| `/octo:doctor auth --verbose` | Detailed auth status |
| `/octo:doctor --json` | Machine-readable output |
