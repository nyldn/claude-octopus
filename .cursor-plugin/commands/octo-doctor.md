---
description: "Environment diagnostics with interactive fixes — providers, auth, RTK, hooks, token optimization"
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
---

# Doctor - Environment Diagnostics

**Your first output line MUST be:** `🐙 Octopus Doctor`

Run environment diagnostics across 12 check categories. Identifies issues AND offers to fix them interactively.

## Step 1: Resolve Plugin Root and Run Full Diagnostics

Use this resolver before running any Octopus script. It avoids relying on the
`~/.claude-octopus/plugin` symlink, which may be unavailable on Windows Git
Bash installs. Run this as a single Bash call.

```bash
set -euo pipefail

OCTO_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [[ -z "$OCTO_PLUGIN_ROOT" || ! -x "$OCTO_PLUGIN_ROOT/scripts/orchestrate.sh" ]]; then
  OCTO_PLUGIN_ROOT="${HOME}/.claude-octopus/plugin"
fi
if [[ ! -x "$OCTO_PLUGIN_ROOT/scripts/orchestrate.sh" ]] && command -v octopus >/dev/null 2>&1; then
  OCTO_BIN="$(command -v octopus)"
  OCTO_PLUGIN_ROOT="$(cd "$(dirname "$OCTO_BIN")/.." && pwd)"
fi
if [[ ! -x "$OCTO_PLUGIN_ROOT/scripts/orchestrate.sh" ]]; then
  OCTO_PLUGIN_ROOT="$(
    find "${HOME}/.claude/plugins" -type f -path "*/scripts/orchestrate.sh" -print 2>/dev/null \
      | sed 's#/scripts/orchestrate.sh$##' \
      | { grep -E '(nyldn-plugins|claude-octopus|/octo(/[0-9]|$))' || true; } \
      | sort \
      | tail -1
  )"
fi
if [[ -z "$OCTO_PLUGIN_ROOT" || ! -x "$OCTO_PLUGIN_ROOT/scripts/orchestrate.sh" ]]; then
  echo "Claude Octopus plugin root not found. Reinstall the octo plugin, then retry /octo:doctor."
  exit 1
fi
mkdir -p "${HOME}/.claude-octopus"
_octo_stable="${HOME}/.claude-octopus/plugin"
if [[ ! -L "$_octo_stable" ]] || [[ "$(cd "$OCTO_PLUGIN_ROOT" 2>/dev/null && pwd -P)" != "$(cd "$_octo_stable" 2>/dev/null && pwd -P)" ]]; then
  [[ -L "$_octo_stable" || -f "$_octo_stable" ]] && rm -f "$_octo_stable" 2>/dev/null || true
  ln -s "$OCTO_PLUGIN_ROOT" "$_octo_stable" 2>/dev/null || true
fi
unset _octo_stable
export OCTO_PLUGIN_ROOT
bash "$OCTO_PLUGIN_ROOT/scripts/orchestrate.sh" doctor --verbose
```

## Step 2: Run Dependency Check

```bash
bash "${OCTO_PLUGIN_ROOT}/scripts/install-deps.sh" check
```

## Step 3: Interactive Remediation (MANDATORY)

After diagnostics complete, analyze the output for fixable issues. For EACH fixable issue found, use AskUserQuestion to offer the fix — do NOT just print instructions.

**Priority order for fixes:**

1. **Missing providers** — offer to install available external provider CLIs such as Codex, Gemini, or Antigravity
2. **Expired auth** — offer to run login commands
3. **RTK not installed** — offer brew/cargo install (saves 60-90% tokens)
4. **RTK hook not configured on macOS/Linux** — offer `rtk init -g`
5. **Missing deps** — offer `install-deps.sh install`
6. **Stale state** — offer cleanup

On Windows Git Bash, do not offer `rtk init -g` for hook remediation. RTK uses
CLAUDE.md injection mode there, so treat the hook check as skipped.

**Example: Multiple fixable issues found:**

```javascript
AskUserQuestion({
  questions: [{
    question: "Doctor found fixable issues. What should we fix?",
    header: "Fix Issues",
    multiSelect: true,
    options: [
      {label: "Install RTK", description: "brew install rtk — saves 60-90% tokens on bash output"},
      {label: "Configure RTK hook", description: "rtk init -g — auto-compress bash output on macOS/Linux"},
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
cd "${OCTO_PLUGIN_ROOT}" && bash scripts/orchestrate.sh doctor providers
cd "${OCTO_PLUGIN_ROOT}" && bash scripts/orchestrate.sh doctor auth
cd "${OCTO_PLUGIN_ROOT}" && bash scripts/orchestrate.sh doctor config
cd "${OCTO_PLUGIN_ROOT}" && bash scripts/orchestrate.sh doctor hooks
cd "${OCTO_PLUGIN_ROOT}" && bash scripts/orchestrate.sh doctor scheduler
cd "${OCTO_PLUGIN_ROOT}" && bash scripts/orchestrate.sh doctor skills
cd "${OCTO_PLUGIN_ROOT}" && bash scripts/orchestrate.sh doctor agents
```

## Step 5: Token Optimization Report

Always include at the end of doctor output:

```bash
echo "=== Token Optimization ==="
echo "RTK: $(command -v rtk >/dev/null 2>&1 && echo "installed $(rtk --version 2>&1 | head -1)" || echo "not installed")"
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) rtk_hook_status="skipped (Windows Git Bash uses RTK CLAUDE.md injection mode)" ;;
  *) rtk_hook_status="$(grep -q 'rtk' "${HOME}/.claude/settings.json" 2>/dev/null && echo "active" || echo "not configured")" ;;
esac
echo "RTK Hook: $rtk_hook_status"
echo "Compressor: $(wc -l < "${HOME}/.claude-octopus/analytics/compression.jsonl" 2>/dev/null || echo 0) events"
echo "octo-compress: $(command -v octo-compress >/dev/null 2>&1 && echo "available" || echo "not in PATH")"
```

## Presenting Results

- Show a summary table with pass/warn/fail counts per category
- Highlight fixable issues with clear action items
- Use AskUserQuestion for any issue that can be fixed with a command
- End with token optimization status
