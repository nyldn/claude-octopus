---
description: "Environment diagnostics — check providers, auth, config, hooks, scheduler, and more"
---

# Doctor - Environment Diagnostics

**Your first output line MUST be:** `🐙 Octopus Doctor`

Run environment diagnostics across 12 check categories. Identifies misconfigured providers, stale state, broken hooks, missing dependencies, and other issues.

## Step 1: Run Full Diagnostics

```bash
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor --verbose
```

## Step 2: Run Dependency Check

```bash
bash "${HOME}/.claude-octopus/plugin/scripts/install-deps.sh" check
```

## Step 3: If dependencies are missing, install them

```bash
bash "${HOME}/.claude-octopus/plugin/scripts/install-deps.sh" install
```

## Step 4: Filter by Category (Optional)

If the user asks about a specific area:

```bash
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor providers
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor auth
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor config
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor hooks
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor scheduler
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor skills
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor agents
```

## Interpreting Results

| Issue | Fix |
|-------|-----|
| Codex CLI not found | `npm install -g @openai/codex` |
| Gemini CLI not found | `npm install -g @google/gemini-cli` |
| Auth expired | Re-run `codex login` or `gemini` |
| Legacy install detected | Remove old cache dir, reinstall plugin |
| Stale state | Delete `.octo/state.json` and re-initialize |
| Missing deps | Run `install-deps.sh install` |

Present results as a summary table with pass/warn/fail counts.
