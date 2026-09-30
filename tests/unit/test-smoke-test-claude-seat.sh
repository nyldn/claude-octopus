#!/usr/bin/env bash
# Claude seats run as `claude --print` subprocesses with the CLI's own
# credentials. The provider smoke test never exercised that CLI, so an expired
# OAuth session passed preflight and every Claude researcher and the Claude
# synthesizer then exited 1 after the other providers had finished a phase.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "provider smoke test exercises the Claude seat CLI"

log() { :; }

WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
HOME="$TEST_TMP_DIR/home"
FAKE_BIN_DIR="$TEST_TMP_DIR/bin"
mkdir -p "$WORKSPACE_DIR" "$HOME" "$FAKE_BIN_DIR"
CLAUDE_CALLS="$TEST_TMP_DIR/claude-calls"
PREFLIGHT_CACHE_TTL=3600

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/quota-watcher.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/provider-allowlist.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/smoke.sh"

secure_tempfile() { mktemp "$TEST_TMP_DIR/${1:-tmp}.XXXXXX"; }
run_with_timeout() { shift; "$@"; }
cache_status() { sed -n '3p' "$SMOKE_TEST_CACHE_FILE" 2>/dev/null; }
get_agent_model() { echo "claude-test"; }
get_agent_command() {
    case "$1" in
        claude-sonnet) echo "$FAKE_BIN_DIR/claude --print" ;;
        codex) echo "$FAKE_BIN_DIR/codex exec -" ;;
    esac
}

cat > "$FAKE_BIN_DIR/codex" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
echo ok
EOF
chmod +x "$FAKE_BIN_DIR/codex"

write_fake_claude() {
    local body="$1"
    cat > "$FAKE_BIN_DIR/claude" <<EOF
#!/usr/bin/env bash
cat >/dev/null
echo called >> "$CLAUDE_CALLS"
$body
EOF
    chmod +x "$FAKE_BIN_DIR/claude"
}

run_smoke() {
    rm -f "$SMOKE_TEST_CACHE_FILE"
    run_smoke_with_cache true
}

run_smoke_with_cache() {
    rm -f "$CLAUDE_CALLS"
    rm -f "$(octo_quota_dead_file)" 2>/dev/null || true
    smoke_status=0
    smoke_output="$(PATH="$FAKE_BIN_DIR:/usr/bin:/bin" provider_smoke_test "${1:-false}" 2>&1)" || smoke_status=$?
}

SKIP_SMOKE_TEST=false
VERBOSE=false
RED="" GREEN="" YELLOW="" CYAN="" DIM="" NC=""
unset OCTO_ALLOWED_PROVIDERS OCTOPUS_CLAUDE_BIN CLAUDE_CODE_REMOTE OCTOPUS_REMOTE_SESSION OCTOPUS_SKIP_PROVIDER_PROBES

write_fake_claude 'echo "Failed to authenticate: OAuth session expired and could not be refreshed"; exit 1'
run_smoke

test_case "a logged-out Claude CLI fails the smoke test even when codex passes"
if [[ "$smoke_status" -ne 0 ]] && [[ -s "$CLAUDE_CALLS" ]] && [[ "$(cache_status)" == "1" ]]; then
    test_pass
else
    test_fail "expected a failing smoke test after the Claude CLI call (status=$smoke_status)"
fi

test_case "the Claude auth failure names the login fix"
if [[ "$smoke_output" == *"Claude: Authentication failed"* ]] && [[ "$smoke_output" == *"claude auth login"* ]]; then
    test_pass
else
    test_fail "smoke output did not report the Claude auth failure: $smoke_output"
fi

write_fake_claude 'echo ok'
run_smoke

test_case "an authenticated Claude CLI passes alongside codex"
if [[ "$smoke_status" -eq 0 ]] && [[ -s "$CLAUDE_CALLS" ]] && [[ "$(cache_status)" == "0" ]]; then
    test_pass
else
    test_fail "expected a passing smoke test (status=$smoke_status): $smoke_output"
fi

write_fake_claude 'exit 124'
run_smoke

test_case "a Claude CLI timeout stays degraded instead of failing the run"
if [[ "$smoke_status" -eq 0 ]] && [[ -s "$CLAUDE_CALLS" ]]; then
    test_pass
else
    test_fail "a Claude timeout aborted the smoke test (status=$smoke_status): $smoke_output"
fi

write_fake_claude 'echo "Failed to authenticate"; exit 1'
OCTO_ALLOWED_PROVIDERS="codex"
run_smoke
unset OCTO_ALLOWED_PROVIDERS

test_case "the Claude CLI is not called when the allowlist excludes Claude"
if [[ "$smoke_status" -eq 0 ]] && [[ ! -e "$CLAUDE_CALLS" ]]; then
    test_pass
else
    test_fail "Claude was smoke tested despite OCTO_ALLOWED_PROVIDERS=codex (status=$smoke_status)"
fi

rm -f "$SMOKE_TEST_CACHE_FILE"
OCTO_ALLOWED_PROVIDERS="codex"
run_smoke_with_cache
unset OCTO_ALLOWED_PROVIDERS
cached_without_claude="$(cache_status)"
run_smoke_with_cache

test_case "a success cached without Claude does not skip the Claude check once Claude is allowed"
if [[ "$cached_without_claude" == "0" ]] && [[ "$smoke_status" -ne 0 ]] && [[ -s "$CLAUDE_CALLS" ]]; then
    test_pass
else
    test_fail "the cached codex-only success was reused for a Claude-enabled run (cached=$cached_without_claude status=$smoke_status)"
fi

write_fake_claude 'exit 124'
mv "$FAKE_BIN_DIR/codex" "$TEST_TMP_DIR/codex.off"
run_smoke
mv "$TEST_TMP_DIR/codex.off" "$FAKE_BIN_DIR/codex"

test_case "a Claude CLI timeout stays degraded when Claude is the only provider"
if [[ "$smoke_status" -eq 0 ]] && [[ -s "$CLAUDE_CALLS" ]] && [[ "$(cache_status)" == "0" ]]; then
    test_pass
else
    test_fail "a Claude-only timeout failed the smoke test (status=$smoke_status cache=$(cache_status)): $smoke_output"
fi

test_summary
