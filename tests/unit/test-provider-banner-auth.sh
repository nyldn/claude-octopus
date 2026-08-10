#!/usr/bin/env bash
# Regression coverage for #799: installed provider binaries are not usable
# seats until the banner path can also find authentication.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=tests/helpers/test-framework.sh
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Provider banner authentication"

FAKE_HOME="$TEST_TMP_DIR/home"
FAKE_BIN="$TEST_TMP_DIR/bin"
mkdir -p "$FAKE_HOME" "$FAKE_BIN"

for provider_bin in codex copilot; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_BIN/$provider_bin"
    chmod +x "$FAKE_BIN/$provider_bin"
done
cat > "$FAKE_BIN/opencode" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "auth" && "${2:-}" == "list" ]] || exit 64
case "${OCTO_TEST_OPENCODE_MODE:-success}" in
    success) exit 0 ;;
    failure) exit 1 ;;
    slow) exec sleep 5 ;;
    *) exit 65 ;;
esac
EOF
chmod +x "$FAKE_BIN/opencode"
printf '#!/usr/bin/env bash\nexit 1\n' > "$FAKE_BIN/gh"
chmod +x "$FAKE_BIN/gh"
cat > "$FAKE_BIN/timeout" <<'EOF'
#!/usr/bin/env bash
duration="${1:-}"
shift || exit 64
[[ "$duration" =~ ^[0-9]+$ ]] || exit 64

"$@" &
child_pid=$!
(
    sleep "$duration"
    kill -TERM "$child_pid" 2>/dev/null || true
) &
watchdog_pid=$!

while kill -0 "$child_pid" 2>/dev/null && kill -0 "$watchdog_pid" 2>/dev/null; do
    sleep 0.05
done

if kill -0 "$child_pid" 2>/dev/null; then
    kill -TERM "$child_pid" 2>/dev/null || true
    sleep 0.05
    kill -KILL "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    exit 124
fi

wait "$child_pid"
child_rc=$?
kill "$watchdog_pid" 2>/dev/null || true
wait "$watchdog_pid" 2>/dev/null || true
exit "$child_rc"
EOF
chmod +x "$FAKE_BIN/timeout"

provider_state() {
    local provider="$1"
    local opencode_mode="${2:-success}"
    (
        unset OPENAI_API_KEY COPILOT_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
        env \
            "HOME=$FAKE_HOME" \
            "PATH=$FAKE_BIN:$PATH" \
            "OCTO_ALLOWED_PROVIDERS=$provider" \
            "OCTO_TEST_OPENCODE_MODE=$opencode_mode" \
            bash "$PROJECT_ROOT/scripts/helpers/check-providers.sh" 2>/dev/null \
            | grep "^${provider}:" | tail -1
    )
}

test_case "installed Codex without auth is degraded"
if [[ "$(provider_state codex)" == "codex:degraded" ]]; then test_pass; else test_fail "Codex binary alone must not be available"; fi

mkdir -p "$FAKE_HOME/.codex"
printf '{}\n' > "$FAKE_HOME/.codex/auth.json"
test_case "Codex auth file makes the installed provider available"
if [[ "$(provider_state codex)" == "codex:available" ]]; then test_pass; else test_fail "Codex auth file was not recognized"; fi

test_case "installed OpenCode without auth is degraded"
if [[ "$(provider_state opencode)" == "opencode:degraded" ]]; then test_pass; else test_fail "OpenCode binary alone must not be available"; fi

mkdir -p "$FAKE_HOME/.local/share/opencode"
printf '{}\n' > "$FAKE_HOME/.local/share/opencode/auth.json"
test_case "OpenCode auth file plus successful auth check is available"
if [[ "$(provider_state opencode)" == "opencode:available" ]]; then test_pass; else test_fail "OpenCode auth was not recognized"; fi

test_case "OpenCode failed auth check remains degraded"
if [[ "$(provider_state opencode failure)" == "opencode:degraded" ]]; then test_pass; else test_fail "failed OpenCode auth was advertised as available"; fi

test_case "OpenCode slow auth check is bounded and degraded"
SECONDS=0
SLOW_OPENCODE_STATE="$(provider_state opencode slow)"
SLOW_OPENCODE_ELAPSED="$SECONDS"
if [[ "$SLOW_OPENCODE_STATE" == "opencode:degraded" && "$SLOW_OPENCODE_ELAPSED" -lt 5 ]]; then
    test_pass
else
    test_fail "slow OpenCode auth escaped the timeout (state=$SLOW_OPENCODE_STATE elapsed=${SLOW_OPENCODE_ELAPSED}s)"
fi

test_case "OpenCode stays degraded when no bounded auth command is usable"
mv "$FAKE_BIN/timeout" "$FAKE_BIN/timeout.disabled"
printf '#!/usr/bin/env bash\nexit 127\n' > "$FAKE_BIN/timeout"
chmod +x "$FAKE_BIN/timeout"
if [[ "$(provider_state opencode)" == "opencode:degraded" ]]; then test_pass; else test_fail "OpenCode auth file was trusted without a usable bounded check"; fi
mv "$FAKE_BIN/timeout.disabled" "$FAKE_BIN/timeout"

test_case "installed Copilot without auth is degraded"
if [[ "$(provider_state copilot)" == "copilot:degraded" ]]; then test_pass; else test_fail "Copilot binary alone must not be available"; fi

test_case "Copilot token makes the installed provider available"
COPILOT_STATE=$(
    env \
        "HOME=$FAKE_HOME" \
        "PATH=$FAKE_BIN:$PATH" \
        "OCTO_ALLOWED_PROVIDERS=copilot" \
        "COPILOT_GITHUB_TOKEN=test-token" \
        bash "$PROJECT_ROOT/scripts/helpers/check-providers.sh" 2>/dev/null \
        | grep '^copilot:' | tail -1
)
if [[ "$COPILOT_STATE" == "copilot:available" ]]; then test_pass; else test_fail "Copilot token was not recognized"; fi

test_summary
