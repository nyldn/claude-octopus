#!/usr/bin/env bash
# Tests for Claude Code web/remote session defaults.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Remote session defaults"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

ORCHESTRATE="$PROJECT_ROOT/scripts/orchestrate.sh"
SMOKE="$PROJECT_ROOT/scripts/lib/smoke.sh"
STATUSLINE="$PROJECT_ROOT/hooks/octopus-statusline.sh"
HUD="$PROJECT_ROOT/hooks/octopus-hud.mjs"
SESSION_START="$PROJECT_ROOT/hooks/session-start-memory.sh"
README="$PROJECT_ROOT/README.md"

if grep -q 'CLAUDE_CODE_REMOTE' "$ORCHESTRATE" && grep -q 'OCTOPUS_REMOTE_SESSION' "$ORCHESTRATE"; then
    pass "orchestrate.sh detects Claude Code remote sessions"
else
    fail "orchestrate.sh detects Claude Code remote sessions" "remote env guard missing"
fi

if grep -q 'OCTOPUS_SKIP_PROVIDER_PROBES' "$ORCHESTRATE" && grep -q 'CLAUDE_OCTOPUS_AUTONOMY.*autonomous' "$ORCHESTRATE"; then
    pass "remote sessions default to autonomous mode and skip probes"
else
    fail "remote sessions default to autonomous mode and skip probes" "missing remote defaults"
fi

if grep -q 'OCTOPUS_SKIP_PROVIDER_PROBES' "$SMOKE" && grep -q 'Smoke test: skipped for remote session' "$SMOKE"; then
    pass "provider smoke tests are skipped in remote sessions"
else
    fail "provider smoke tests are skipped in remote sessions" "smoke skip guard missing"
fi

if grep -q 'Codex tier probe skipped for remote session' "$SMOKE"; then
    pass "Codex tier probe is skipped in remote sessions"
else
    fail "Codex tier probe is skipped in remote sessions" "tier probe guard missing"
fi

if grep -q 'OCTOPUS_REMOTE_STATUSLINE' "$STATUSLINE" && grep -q '\[Octopus\] remote' "$STATUSLINE"; then
    pass "bash statusline has lightweight remote mode"
else
    fail "bash statusline has lightweight remote mode" "remote statusline fallback missing"
fi

remote_output=$(printf '{"used_percentage":42.9}\n' | CLAUDE_CODE_REMOTE=true "$STATUSLINE")
if [[ "$remote_output" == "[Octopus] remote 42% context" ]]; then
    pass "bash statusline emits lightweight remote context percentage"
else
    fail "bash statusline emits lightweight remote context percentage" "unexpected output: $remote_output"
fi

off_output=$(printf '{"used_percentage":42.9}\n' | CLAUDE_CODE_REMOTE=true OCTOPUS_REMOTE_STATUSLINE=off "$STATUSLINE")
if [[ -z "$off_output" ]]; then
    pass "remote statusline can be disabled"
else
    fail "remote statusline can be disabled" "unexpected output: $off_output"
fi

if grep -q 'full)' "$STATUSLINE"; then
    pass "remote statusline full mode falls through to local HUD"
else
    fail "remote statusline full mode falls through to local HUD" "full opt-in missing"
fi

if grep -q 'OCTOPUS_REMOTE_STATUSLINE' "$HUD" && grep -q 'process.exit(0)' "$HUD"; then
    pass "Node HUD exits early in remote sessions"
else
    fail "Node HUD exits early in remote sessions" "HUD remote early exit missing"
fi

if grep -q 'remote_session.*true' "$SESSION_START" && grep -q 'setup-complete' "$SESSION_START"; then
    pass "SessionStart records remote sessions without first-run setup"
else
    fail "SessionStart records remote sessions without first-run setup" "remote session state missing"
fi

tmp_home=$(mktemp -d)
session_output=$(HOME="$tmp_home" CLAUDE_CODE_REMOTE=true "$SESSION_START" 2>/dev/null || true)
session_file="$tmp_home/.claude-octopus/session.json"
if [[ -f "$tmp_home/.claude-octopus/.setup-complete" && -f "$session_file" && -z "$session_output" ]] &&
   jq -e '.remote_session == true and .autonomy == "autonomous"' "$session_file" >/dev/null 2>&1; then
    pass "SessionStart remote mode records state and suppresses first-run prompt"
else
    fail "SessionStart remote mode records state and suppresses first-run prompt" "remote state was not recorded correctly"
fi

tmp_home=$(mktemp -d)
HOME="$tmp_home" CLAUDE_CODE_REMOTE=true OCTOPUS_AUTONOMY=supervised "$SESSION_START" >/dev/null 2>&1 || true
if jq -e '.remote_session == true and .autonomy == "supervised"' "$tmp_home/.claude-octopus/session.json" >/dev/null 2>&1; then
    pass "SessionStart preserves explicit remote autonomy"
else
    fail "SessionStart preserves explicit remote autonomy" "explicit autonomy was not preserved"
fi

if grep -q '## Claude Code Web and Remote Sessions' "$README" && grep -q 'OCTOPUS_REMOTE_SESSION=true' "$README"; then
    pass "README documents Claude Code web and remote workflow"
else
    fail "README documents Claude Code web and remote workflow" "remote docs missing"
fi

if ! grep -R -q 'claude --remote\|claude --teleport' "$README" "$PROJECT_ROOT/commands" "$PROJECT_ROOT/.claude/commands"; then
    pass "remote docs avoid unsupported Claude CLI flags"
else
    fail "remote docs avoid unsupported Claude CLI flags" "unsupported CLI flag documented"
fi

test_summary
