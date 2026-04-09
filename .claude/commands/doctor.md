---
command: doctor
description: Environment diagnostics with interactive fixes — providers, auth, RTK, hooks, token optimization
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
---

# Doctor - Environment Diagnostics

**Your first output line MUST be:** `🐙 Octopus Doctor`

Run environment diagnostics across 12 check categories. Identifies issues AND offers to fix them interactively.

## Step 1: Run Full Diagnostics

```bash
cd "${HOME}/.claude-octopus/plugin" && bash scripts/orchestrate.sh doctor --verbose
```

## Step 2: Run Dependency Check

```bash
bash "${HOME}/.claude-octopus/plugin/scripts/install-deps.sh" check
```

## Step 3: Interactive Remediation (MANDATORY)

After diagnostics complete, analyze the output for fixable issues. For EACH fixable issue found, use AskUserQuestion to offer the fix — do NOT just print instructions.

**Priority order for fixes:**

1. **Missing providers** — offer to install Codex/Gemini CLI
2. **Expired auth** — offer to run login commands
3. **RTK not installed** — offer brew/cargo install (saves 60-90% tokens)
4. **RTK hook not configured** — offer `rtk init -g`
5. **Missing deps** — offer `install-deps.sh install`
6. **Stale state** — offer cleanup

**Example: Multiple fixable issues found:**

```javascript
AskUserQuestion({
  questions: [{
    question: "Doctor found fixable issues. What should we fix?",
    header: "Fix Issues",
    multiSelect: true,
    options: [
      {label: "Install RTK", description: "brew install rtk — saves 60-90% tokens on bash output"},
      {label: "Configure RTK hook", description: "rtk init -g — auto-compress bash output"},
      {label: "Install missing deps", description: "Run install-deps.sh install"},
      {label: "Skip all", description: "I'll fix these manually"}
    ]
  }]
})
```

Execute each selected fix, verify it worked, report results.

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

## Step 5: Token Optimization Report

Always include at the end of doctor output:

```bash
echo "=== Token Optimization ==="
echo "RTK: $(command -v rtk >/dev/null 2>&1 && echo "installed $(rtk --version 2>&1 | head -1)" || echo "not installed")"
echo "RTK Hook: $(grep -q 'rtk' "${HOME}/.claude/settings.json" 2>/dev/null && echo "active" || echo "not configured")"
echo "Compressor: $(wc -l < "${HOME}/.claude-octopus/analytics/compression.jsonl" 2>/dev/null || echo 0) events"
echo "octo-compress: $(command -v octo-compress >/dev/null 2>&1 && echo "available" || echo "not in PATH")"
```

## Presenting Results

- Show a summary table with pass/warn/fail counts per category
- Highlight fixable issues with clear action items
- Use AskUserQuestion for any issue that can be fixed with a command
- End with token optimization status
