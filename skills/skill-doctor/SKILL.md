---
name: skill-doctor
version: 1.0.0
description: "Environment diagnostics — check providers, auth, config, hooks, scheduler, and more. Use when: AUTOMATICALLY ACTIVATE when user asks about:. \"doctor\" or \"run doctor\" or \"diagnostics\". \"check my setup\" or \"is everything working\""
---

# Environment Doctor

## Overview

Run environment diagnostics across 11 check categories. Identifies misconfigured providers, stale state, broken hooks, and other issues that prevent Claude Octopus from working correctly.

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
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor
```

This runs all 11 check categories and displays a formatted report.

### Step 2: Filter by Category (Optional)

If the user asks about a specific area, filter:

```bash
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor providers
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor auth
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor config
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor state
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor smoke
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor hooks
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor scheduler
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor skills
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor conflicts
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor agents
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor recurrence
```

### Step 3: Check & Install Dependencies

Run the dependency checker to find missing CLIs, statusline config, and recommended plugins:

```bash
bash "${HOME}/.claude-octopus/plugin/scripts/install-deps.sh" check
```

If the check reports missing deps, offer to install them:

```bash
bash "${HOME}/.claude-octopus/plugin/scripts/install-deps.sh" install
```

This auto-installs: Codex CLI, Gemini CLI, jq, and the statusline resolver. For plugins (claude-mem, document-skills), it prints `/plugin install` commands the user must run manually.

### Step 4: Verbose or JSON Output

```bash
# Detailed output for troubleshooting
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor --verbose

# Machine-readable output
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor --json

# Combine: specific category + verbose
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor auth --verbose
```

---

## Check Categories

| Category | What it checks |
|----------|---------------|
| `providers` | Claude Code version, Codex CLI installed, Gemini CLI installed, Perplexity API key, Ollama local LLM (server + models), circuit breaker status, provider fallback history |
| `auth` | Authentication status for each provider |
| `config` | Plugin version, install scope, feature flags |
| `state` | Project state.json, stale results, workspace writable |
| `smoke` | Smoke test cache, model configuration |
| `hooks` | hooks.json validity, hook scripts |
| `scheduler` | Scheduler daemon, jobs, budget gates, kill switches |
| `skills` | Skill files loaded and valid |
| `conflicts` | Conflicting plugins detection |
| `agents` | Agent definitions, worktree isolation, CLI registration, version compatibility |
| `recurrence` | Failure pattern detection — flags repeated quality gate failures, source hotspots, 48h trends |
| `deps` | Software dependencies — Node.js, jq, Codex/Gemini CLIs, RTK token compression, statusline resolver, recommended plugins |

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
| Circuit breaker OPEN | Provider had 3+ consecutive transient failures — wait for cooldown or check provider status |
| Stale state | Delete `.octo/state.json` and re-initialize |
| Invalid hooks.json | Check `hooks.json` syntax — must be valid JSON |
| RTK not installed | `brew install rtk && rtk init -g` (optional — saves 60-90% tokens on bash output) |
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

## Hook Profile

Claude Octopus hooks can run in different profiles to balance cost and coverage.

Current profile: `$OCTO_HOOK_PROFILE` (default: standard)

Available profiles:
- **minimal** — Only session lifecycle and cost tracking hooks (lowest overhead)
- **standard** — All hooks except expensive review/security gates (default)
- **strict** — All hooks enabled including quality and security gates

Override: Set `OCTO_PROFILE=budget|balanced|quality` or `OCTO_DISABLED_HOOKS=hook1,hook2` to fine-tune. Legacy `OCTO_HOOK_PROFILE` still works (minimal→budget, standard→balanced, strict→quality).

---

## Intensity Profile

The doctor reports the active intensity profile — a single knob controlling hook gating, model selection, phase skipping, and context verbosity.

### What the Doctor Checks

- **Current profile**: `OCTO_PROFILE` value (budget/balanced/quality, default: balanced)
- **Profile source**: env var, legacy `OCTO_HOOK_PROFILE`, or auto-selected from intent
- **Hook gating**: which hooks are enabled/disabled at this profile level
- **Model hints**: which model (sonnet/opus) is recommended for each phase
- **Context verbosity**: compressed/standard/full

### Profile Summary

| Dimension | budget | balanced | quality |
|-----------|--------|----------|---------|
| Hooks | essential only | standard (no quality gates) | all hooks |
| Models | Sonnet everywhere | Sonnet + Opus for synthesis | Opus for most phases |
| Phases | Skip discover if context given | Skip re-discovery | All phases run |
| Context | Compressed | Standard | Full inlining |

---

## Runtime Context

The doctor checks for project-level `RUNTIME.md` — a file that provides project-specific context (API endpoints, env vars, test commands, build steps) to orchestration prompts.

### What the Doctor Checks

- **RUNTIME.md exists** in the project root (also checks `.octopus/RUNTIME.md` and `.claude-octopus/RUNTIME.md`)
- If missing, suggest creating one from the template: `cp "${HOME}/.claude-octopus/plugin/config/templates/RUNTIME.md" ./RUNTIME.md`
- If present, confirm it contains at least one populated section (not just the template defaults)

### Why It Matters

Without a `RUNTIME.md`, orchestration prompts lack project-specific details — leading to generic advice about test commands, environment variables, and build steps. A populated `RUNTIME.md` makes every workflow more accurate.

---

## Quick Reference

| User Input | Action |
|------------|--------|
| `/octo:doctor` | Run all 11 categories |
| `/octo:doctor providers` | Check provider installation only |
| `/octo:doctor auth --verbose` | Detailed auth status |
| `/octo:doctor --json` | Machine-readable output |
