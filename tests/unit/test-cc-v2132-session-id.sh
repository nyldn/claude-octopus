#!/usr/bin/env bash
# Tests for Claude Code v2.1.132 Bash session ID propagation.
# v2.1.132 exposes CLAUDE_CODE_SESSION_ID to Bash tool subprocesses; Octopus
# should prefer it for Claude-specific session-scoped state while preserving
# Codex/Gemini host fallbacks.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Claude Code v2.1.132 Bash session ID support"

ORCH="$PROJECT_ROOT/scripts/orchestrate.sh"
PROVIDERS="$PROJECT_ROOT/scripts/lib/providers.sh"
DOCTOR="$PROJECT_ROOT/scripts/lib/doctor.sh"
SESSION_LIB="$PROJECT_ROOT/scripts/lib/session-id.sh"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

assert_contains() {
    local file="$1"
    local pattern="$2"
    local label="$3"
    if grep -qE "$pattern" "$file"; then
        pass "$label"
    else
        fail "$label" "missing pattern '$pattern' in $file"
    fi
}

echo "=== 1. Feature flag wiring ==="
assert_contains "$ORCH" '^SUPPORTS_BASH_SESSION_ID_ENV=false' \
    "SUPPORTS_BASH_SESSION_ID_ENV declared"

if grep -A 8 'version_compare.*CLAUDE_CODE_VERSION.*"2.1.132"' "$PROVIDERS" \
    | grep -q 'SUPPORTS_BASH_SESSION_ID_ENV=true'; then
    pass "v2.1.132 block sets SUPPORTS_BASH_SESSION_ID_ENV"
else
    fail "v2.1.132 block sets SUPPORTS_BASH_SESSION_ID_ENV" \
        "missing feature flag assignment in providers.sh"
fi

assert_contains "$PROVIDERS" 'Bash Session ID Env' \
    "providers logging includes Bash Session ID Env"
assert_contains "$DOCTOR" '"bash-session-id-env"' \
    "doctor reports Bash session ID env support"

echo ""
echo "=== 2. Shared session resolver ==="
if [[ -f "$SESSION_LIB" ]]; then
    pass "session-id helper exists"
else
    fail "session-id helper exists" "missing scripts/lib/session-id.sh"
fi

assert_contains "$SESSION_LIB" 'octo_resolve_session_id' \
    "session helper defines octo_resolve_session_id"
assert_contains "$SESSION_LIB" 'CLAUDE_CODE_SESSION_ID' \
    "session helper prefers CLAUDE_CODE_SESSION_ID"

if bash -lc 'source scripts/lib/session-id.sh; CLAUDE_CODE_SESSION_ID=cc132; CLAUDE_SESSION_ID=legacy; OCTOPUS_HOST=claude; [[ "$(octo_resolve_session_id fallback)" == "cc132" ]]'; then
    pass "Claude host prefers CLAUDE_CODE_SESSION_ID over legacy env"
else
    fail "Claude host prefers CLAUDE_CODE_SESSION_ID over legacy env"
fi

if bash -lc 'source scripts/lib/session-id.sh; unset CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID; OCTOPUS_HOST=claude; payload='\''{"session_id":"hook-json"}'\''; [[ "$(octo_resolve_session_id fallback "$payload")" == "hook-json" ]]'; then
    pass "session helper falls back to hook JSON session_id"
else
    fail "session helper falls back to hook JSON session_id"
fi

if bash -lc 'source scripts/lib/session-id.sh; CLAUDE_CODE_SESSION_ID=cc132; CODEX_SESSION_ID=codex-77; OCTOPUS_HOST=codex; [[ "$(octo_resolve_session_id fallback)" == "codex-77" ]]'; then
    pass "Codex host keeps CODEX_SESSION_ID precedence"
else
    fail "Codex host keeps CODEX_SESSION_ID precedence"
fi

echo ""
echo "=== 3. Runtime state wiring ==="
assert_contains "$ORCH" 'CLAUDE_CODE_SESSION_ID:-\$\{CLAUDE_SESSION_ID' \
    "orchestrate Claude host uses CLAUDE_CODE_SESSION_ID before CLAUDE_SESSION_ID"

for hook in careful-check.sh freeze-check.sh; do
    assert_contains "$PROJECT_ROOT/hooks/$hook" 'octo_session_state_file' \
        "$hook uses shared session resolver"
done

assert_contains "$PROJECT_ROOT/hooks/strategy-rotation.sh" 'octo_resolve_session_id' \
    "strategy-rotation.sh uses shared session resolver"

for cmd in .cursor-plugin/commands/octo-careful.md .cursor-plugin/commands/octo-freeze.md .cursor-plugin/commands/octo-guard.md .cursor-plugin/commands/octo-unfreeze.md \
           commands/careful.md commands/freeze.md commands/guard.md commands/unfreeze.md; do
    assert_contains "$PROJECT_ROOT/$cmd" 'CLAUDE_CODE_SESSION_ID' \
        "$cmd writes state with Claude Code Bash session id"
done

assert_contains "$PROJECT_ROOT/scripts/session-manager.sh" 'CLAUDE_CODE_SESSION_ID' \
    "session-manager uses CLAUDE_CODE_SESSION_ID"
assert_contains "$PROJECT_ROOT/scripts/lib/proof-packet.sh" 'CLAUDE_CODE_SESSION_ID' \
    "proof packets use CLAUDE_CODE_SESSION_ID"
assert_contains "$PROJECT_ROOT/scripts/lib/cost.sh" 'CLAUDE_CODE_SESSION_ID' \
    "cost tracking uses CLAUDE_CODE_SESSION_ID"
assert_contains "$PROJECT_ROOT/hooks/octopus-hud.mjs" 'CLAUDE_CODE_SESSION_ID' \
    "HUD analytics filters with CLAUDE_CODE_SESSION_ID"

test_summary
