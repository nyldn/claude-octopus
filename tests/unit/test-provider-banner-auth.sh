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

printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_BIN/codex"
chmod +x "$FAKE_BIN/codex"
cat > "$FAKE_BIN/copilot" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--help" ]]; then
    printf '%s\n' '--prompt --model --silent --no-ask-user --disable-builtin-mcps'
fi
exit 0
EOF
chmod +x "$FAKE_BIN/copilot"
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
    local command_path="${3:-$FAKE_BIN:$PATH}"
    (
        unset OPENAI_API_KEY COPILOT_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
        env \
            "HOME=$FAKE_HOME" \
            "PATH=$command_path" \
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

test_case "OpenCode static readiness does not invoke its interactive auth command"
SECONDS=0
SLOW_OPENCODE_STATE="$(provider_state opencode slow)"
SLOW_OPENCODE_ELAPSED="$SECONDS"
if [[ "$SLOW_OPENCODE_STATE" == "opencode:available" && "$SLOW_OPENCODE_ELAPSED" -lt 5 ]]; then
    test_pass
else
    test_fail "static OpenCode readiness invoked a live auth command (state=$SLOW_OPENCODE_STATE elapsed=${SLOW_OPENCODE_ELAPSED}s)"
fi

test_case "OpenCode static readiness uses safe config metadata without a timeout utility"
mv "$FAKE_BIN/timeout" "$FAKE_BIN/timeout.disabled"
printf '#!/usr/bin/env bash\nexit 127\n' > "$FAKE_BIN/timeout"
chmod +x "$FAKE_BIN/timeout"
if [[ "$(provider_state opencode)" == "opencode:available" ]]; then test_pass; else test_fail "OpenCode safe auth metadata required a live timeout utility"; fi
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
