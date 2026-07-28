#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=tests/helpers/test-framework.sh
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "README Release Sync"

SYNC_SCRIPT="$PROJECT_ROOT/scripts/sync-readme.py"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/octo-readme-sync-test.XXXXXX")"
CURRENT_VERSION="$(jq -r '.version' "$PROJECT_ROOT/.claude-plugin/plugin.json")"
SMOKE_SUITE_COUNT="$(find "$PROJECT_ROOT/tests/smoke" -maxdepth 1 -name 'test-*.sh' | wc -l | tr -d ' ')"
UNIT_SUITE_COUNT="$(find "$PROJECT_ROOT/tests/unit" -maxdepth 1 -name 'test-*.sh' | wc -l | tr -d ' ')"
INTEGRATION_SUITE_COUNT="$(find "$PROJECT_ROOT/tests/integration" -maxdepth 1 -name 'test-*.sh' | wc -l | tr -d ' ')"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

make_fixture() {
    local root="$1"

    mkdir -p \
        "$root/.claude-plugin" \
        "$root/agents/personas" \
        "$root/scripts/lib" \
        "$root/tests/smoke" \
        "$root/tests/unit" \
        "$root/tests/integration"

    cp "$PROJECT_ROOT/README.md" "$root/README.md"
    cp "$PROJECT_ROOT/PRODUCT.md" "$root/PRODUCT.md"
    cp "$PROJECT_ROOT/CHANGELOG.md" "$root/CHANGELOG.md"
    cp "$PROJECT_ROOT/.claude-plugin/plugin.json" "$root/.claude-plugin/plugin.json"
    cp "$PROJECT_ROOT/.claude-plugin/README.md" "$root/.claude-plugin/README.md"
    cp "$PROJECT_ROOT/scripts/orchestrate.sh" "$root/scripts/orchestrate.sh"
    cp "$PROJECT_ROOT/scripts/lib/model-resolver.sh" "$root/scripts/lib/model-resolver.sh"
    cp "$PROJECT_ROOT/scripts/lib/providers.sh" "$root/scripts/lib/providers.sh"
    cp "$PROJECT_ROOT/agents/personas/"*.md "$root/agents/personas/"
    local category test_file
    for category in smoke unit integration; do
        for test_file in "$PROJECT_ROOT/tests/$category"/test-*.sh; do
            : > "$root/tests/$category/$(basename "$test_file")"
        done
    done
}

if [[ -x "$SYNC_SCRIPT" ]]; then
    test_case "sync-readme.py exists and is executable"
    test_pass
else
    test_case "sync-readme.py exists and is executable"
    test_fail "missing executable README sync helper"
fi

test_case "tracked README surfaces are synchronized"
if "$SYNC_SCRIPT" --check >/tmp/octo-readme-sync-check.out 2>&1; then
    test_pass
else
    test_fail "README sync check failed: $(cat /tmp/octo-readme-sync-check.out 2>/dev/null)"
fi

fixture="$TMP_DIR/fixture"
make_fixture "$fixture"

python3 - "$fixture" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
readme = root / "README.md"
text = readme.read_text()
text = re.sub(r"Version-\d+\.\d+\.\d+-blue", "Version-0.0.0-blue", text)
text = re.sub(r"Version \d+\.\d+\.\d+", "Version 0.0.0", text)
text = text.replace(
    "supports ten external provider integrations",
    "supports nine external provider integrations",
    1,
)
text = text.replace(
    "<!-- BEGIN CURRENT RELEASE -->",
    "<!-- BEGIN CURRENT RELEASE -->\n> stale release copy",
    1,
)
text = re.sub(
    r"current plugin tracks \d+ Claude Code capability flags through "
    r"\*\*Claude Code v\d+\.\d+\.\d+\*\*",
    "current plugin tracks feature flags through **Claude Code v2.1.157**",
    text,
)
readme.write_text(text)

plugin_readme = root / ".claude-plugin/README.md"
plugin_text = plugin_readme.read_text()
plugin_text = re.sub(
    r"^- Optional: .*$",
    "- Optional: Codex CLI and Gemini CLI",
    plugin_text,
    count=1,
    flags=re.MULTILINE,
)
plugin_readme.write_text(plugin_text)

product = root / "PRODUCT.md"
product_text = product.read_text()
product_text = product_text.replace(
    "up to 10 external AI integrations",
    "up to 9 AI CLIs",
)
product_text = re.sub(
    r"Local CI parity: \d+ smoke, \d+ unit, and \d+ integration suites",
    "Local CI parity: 1 smoke, 1 unit, and 1 integration suites",
    product_text,
)
product.write_text(product_text)
PY

test_case "--check rejects deliberately stale README facts"
if "$SYNC_SCRIPT" --root "$fixture" --check >/tmp/octo-readme-sync-stale.out 2>&1; then
    test_fail "stale fixture unexpectedly passed"
else
    test_pass
fi

test_case "sync repairs release, model, count, and capability facts"
if "$SYNC_SCRIPT" --root "$fixture" >/tmp/octo-readme-sync-update.out 2>&1 &&
   "$SYNC_SCRIPT" --root "$fixture" --check >/tmp/octo-readme-sync-recheck.out 2>&1 &&
   grep -q "Version-${CURRENT_VERSION}-blue" "$fixture/README.md" &&
   grep -q "v${CURRENT_VERSION}.*(new)" "$fixture/README.md" &&
   grep -q 'supports ten external provider integrations.*Grok' "$fixture/README.md" &&
   grep -q 'GPT-5.6 Sol' "$fixture/README.md" &&
   grep -q 'Claude Opus 5' "$fixture/README.md" &&
   grep -q 'Claude Sonnet 5' "$fixture/README.md" &&
   grep -qE '[0-9]+ Claude Code capability flags through.*v[0-9]+\.[0-9]+\.[0-9]+' "$fixture/README.md" &&
   grep -q 'OpenCode CLI, and xAI API key (Grok)' "$fixture/.claude-plugin/README.md" &&
   grep -q 'up to 10 external AI integrations' "$fixture/PRODUCT.md" &&
   grep -q "Local CI parity: ${SMOKE_SUITE_COUNT} smoke, ${UNIT_SUITE_COUNT} unit, and ${INTEGRATION_SUITE_COUNT} integration suites" "$fixture/PRODUCT.md" &&
   ! grep -qE 'Version-0\.0\.0-blue|stale release copy|v2\.1\.157' "$fixture/README.md"; then
    test_pass
else
    test_fail "sync did not restore the expected README facts"
fi

test_case "release workflow regenerates and stages synchronized docs"
release_commit_block="$(sed -n '/^echo "2\/8 Committing\.\.\."/,/^git commit /p' "$PROJECT_ROOT/scripts/release.sh")"
changelog_line="$(grep -n '^octo_release_update_changelog ' "$PROJECT_ROOT/scripts/release.sh" | cut -d: -f1)"
sync_line="$(grep -n '^make sync$' "$PROJECT_ROOT/scripts/release.sh" | cut -d: -f1)"
if grep -q 'scripts/sync-readme.py' "$PROJECT_ROOT/Makefile" &&
   grep -q 'scripts/sync-readme.py --check' "$PROJECT_ROOT/Makefile" &&
   grep -q 'PRODUCT.md' <<<"$release_commit_block" &&
   grep -q '\.claude-plugin/README.md' <<<"$release_commit_block" &&
   [[ -n "$changelog_line" && -n "$sync_line" && "$changelog_line" -lt "$sync_line" ]]; then
    test_pass
else
    test_fail "release workflow does not regenerate and stage every synchronized doc surface"
fi

test_case "cross-harness controller preserves the README sync contract"
handoff_git_line="$(awk '/^## Start Here$/{section=1; next} section && /^## /{exit} section && /git status --short --branch/{print NR; exit}' "$PROJECT_ROOT/AI_AGENT_HANDOFF.md")"
handoff_commits_line="$(awk '/^## Start Here$/{section=1; next} section && /^## /{exit} section && /latest commits/{print NR; exit}' "$PROJECT_ROOT/AI_AGENT_HANDOFF.md")"
handoff_bd_line="$(awk '/^## Start Here$/{section=1; next} section && /^## /{exit} section && /relevant `bd` issue/{print NR; exit}' "$PROJECT_ROOT/AI_AGENT_HANDOFF.md")"
rtk_git_line="$(awk '/^## Start a Session$/{section=1; next} section && /^## /{exit} section && /git status --short --branch/{print NR; exit}' "$PROJECT_ROOT/RTK.md")"
rtk_commits_line="$(awk '/^## Start a Session$/{section=1; next} section && /^## /{exit} section && /latest commits/{print NR; exit}' "$PROJECT_ROOT/RTK.md")"
rtk_bd_line="$(awk '/^## Start a Session$/{section=1; next} section && /^## /{exit} section && /relevant `bd` issue/{print NR; exit}' "$PROJECT_ROOT/RTK.md")"
if [[ -f "$PROJECT_ROOT/RTK.md" ]] &&
   [[ -n "$handoff_git_line" && -n "$handoff_commits_line" && -n "$handoff_bd_line" ]] &&
   [[ "$handoff_git_line" -lt "$handoff_bd_line" && "$handoff_commits_line" -lt "$handoff_bd_line" ]] &&
   [[ -n "$rtk_git_line" && -n "$rtk_commits_line" && -n "$rtk_bd_line" ]] &&
   [[ "$rtk_git_line" -lt "$rtk_bd_line" && "$rtk_commits_line" -lt "$rtk_bd_line" ]] &&
   grep -q 'scripts/sync-readme.py.*owns' "$PROJECT_ROOT/RTK.md" &&
   grep -q 'scripts/sync-readme.py.*owns' "$PROJECT_ROOT/AGENTS.md" &&
   grep -q 'scripts/sync-readme.py' "$PROJECT_ROOT/CLAUDE.md" &&
   grep -Eq 'make[[:space:]]+sync([^[:alnum:]_-]|$)' "$PROJECT_ROOT/AGENTS.md" &&
   grep -Eq 'make[[:space:]]+sync([^[:alnum:]_-]|$)' "$PROJECT_ROOT/CLAUDE.md" &&
   grep -Eq 'make[[:space:]]+sync([^[:alnum:]_-]|$)' "$PROJECT_ROOT/RTK.md" &&
   grep -q 'make sync-check' "$PROJECT_ROOT/RTK.md" &&
   grep -q 'every remaining item' "$PROJECT_ROOT/RTK.md" &&
   grep -q 'Clean up stashes' "$PROJECT_ROOT/RTK.md" &&
   grep -q 'AI_AGENT_HANDOFF.md' "$PROJECT_ROOT/RTK.md"; then
    test_pass
else
    test_fail "RTK/agent guidance does not preserve the generated README contract"
fi

test_case "current model configuration guidance uses the frontier roster"
if grep -q 'gpt-5.6-sol' "$PROJECT_ROOT/commands/model-config.md" &&
   grep -q 'gpt-5.6-terra' "$PROJECT_ROOT/commands/model-config.md" &&
   grep -q 'gpt-5.6-luna' "$PROJECT_ROOT/commands/model-config.md" &&
   ! grep -qE 'GPT-5\.4|gpt-5\.4' "$PROJECT_ROOT/commands/model-config.md"; then
    test_pass
else
    test_fail "model-config command still presents pre-GPT-5.6 defaults"
fi

test_case "public documentation names all ten external integrations"
if grep -q 'ten external provider integrations' "$PROJECT_ROOT/README.md" &&
   grep -q 'Up to ten external AI integrations' "$PROJECT_ROOT/.claude-plugin/README.md" &&
   grep -q 'Grok' "$PROJECT_ROOT/.claude-plugin/README.md" &&
   grep -q 'ten external AI integrations' "$PROJECT_ROOT/docs/ARCHITECTURE.md"; then
    test_pass
else
    test_fail "provider count/list differs across public documentation"
fi

test_summary
