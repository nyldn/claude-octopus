#!/usr/bin/env bash
# Unit tests for Cursor Agent provider wiring.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Cursor Agent provider"

CURSOR_LIB="$PROJECT_ROOT/scripts/lib/cursor-agent.sh"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

test_case "cursor-agent library has valid bash syntax"
if bash -n "$CURSOR_LIB" 2>/dev/null; then
    test_pass
else
    test_fail "syntax error in cursor-agent.sh"
fi

source "$CURSOR_LIB"

reset_mocks() {
    rm -rf "$MOCK_BIN_DIR"
    mkdir -p "$MOCK_BIN_DIR"
}

test_case "identity probe stays bounded without external timeout support"
reset_mocks
cat > "$MOCK_BIN_DIR/agent" <<'EOF'
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    /bin/sleep 5
    echo "2026.04.17-test"
    exit 0
fi
exit 2
EOF
chmod +x "$MOCK_BIN_DIR/agent"

SECONDS=0
if PATH="$MOCK_BIN_DIR" OCTOPUS_CURSOR_AGENT_PROBE_TIMEOUT=1 _is_cursor_agent_binary >/dev/null 2>&1; then
    test_fail "identity probe succeeded after a timed-out version probe"
elif [[ $SECONDS -le 3 ]]; then
    test_pass
else
    test_fail "identity probe was not bounded (elapsed ${SECONDS}s)"
fi

test_case "identity probe accepts CalVer Cursor Agent behind timeout wrapper"
reset_mocks
cat > "$MOCK_BIN_DIR/timeout" <<'EOF'
#!/bin/bash
shift
exec "$@"
EOF
cat > "$MOCK_BIN_DIR/agent" <<'EOF'
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "2026.04.17-test"
    exit 0
fi
echo "unexpected args: $*" >&2
exit 2
EOF
chmod +x "$MOCK_BIN_DIR/timeout" "$MOCK_BIN_DIR/agent"

if PATH="$MOCK_BIN_DIR:/usr/bin:/bin" _is_cursor_agent_binary >/dev/null 2>&1; then
    test_pass
else
    test_fail "identity probe rejected valid Cursor Agent CalVer output"
fi

test_case "cursor_agent_execute sends prompt on stdin, not argv"
reset_mocks
ARGV_FILE="$TEST_TMP_DIR/cursor-argv.txt"
STDIN_FILE="$TEST_TMP_DIR/cursor-stdin.txt"
OUTPUT_FILE="$TEST_TMP_DIR/cursor-output.txt"
cat > "$MOCK_BIN_DIR/timeout" <<'EOF'
#!/bin/bash
shift
exec "$@"
EOF
cat > "$MOCK_BIN_DIR/agent" <<'EOF'
#!/bin/bash
if [[ "$1" == "--version" ]]; then
    echo "2026.04.17-test"
    exit 0
fi
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p)
            printf '%s' "${2:-}" > "$ARGV_FILE"
            shift 2
            ;;
        --trust|--output-format)
            shift
            [[ "${1:-}" == "text" ]] && shift
            ;;
        *)
            shift
            ;;
    esac
done
cat > "$STDIN_FILE"
echo "cursor response"
EOF
chmod +x "$MOCK_BIN_DIR/timeout" "$MOCK_BIN_DIR/agent"

if PATH="$MOCK_BIN_DIR:/usr/bin:/bin" CURSOR_API_KEY=test ARGV_FILE="$ARGV_FILE" STDIN_FILE="$STDIN_FILE" \
    cursor_agent_execute cursor-agent "sensitive prompt" "$OUTPUT_FILE" >/dev/null 2>&1; then
    if [[ "$(cat "$ARGV_FILE" 2>/dev/null || true)" == "" ]] && \
       [[ "$(cat "$STDIN_FILE" 2>/dev/null || true)" == "sensitive prompt" ]] && \
       grep -q "cursor response" "$OUTPUT_FILE"; then
        test_pass
    else
        test_fail "prompt was not captured through stdin-only execution"
    fi
else
    test_fail "cursor_agent_execute failed with mocked Cursor Agent"
fi

test_case "Cursor Agent probes are timeout-guarded outside the helper"
offenders=$(grep -R "agent --version" "$PROJECT_ROOT/scripts/helpers" "$PROJECT_ROOT/scripts/lib" "$PROJECT_ROOT/scripts/install-deps.sh" 2>/dev/null | grep -v 'scripts/lib/cursor-agent.sh:.*_cursor_agent_run_with_timeout' || true)
if [[ -z "$offenders" ]]; then
    test_pass
else
    test_fail "unbounded agent --version probe remains: $offenders"
fi

test_case "smoke test sends Cursor Agent prompt through stdin"
if awk '
    /\[\[ "\$provider" == "cursor-agent" \]\]/ { in_cursor=1 }
    in_cursor && /echo "Reply with exactly: ok" \| run_with_timeout/ { saw_stdin=1 }
    in_cursor && /\$cmd_str -p "Reply with exactly: ok"/ { saw_argv=1 }
    in_cursor && /^    else$/ { in_cursor=0 }
    END { exit (saw_stdin && !saw_argv) ? 0 : 1 }
' "$PROJECT_ROOT/scripts/lib/smoke.sh"; then
    test_pass
else
    test_fail "Cursor Agent smoke path still passes prompt as argv"
fi

test_case "model config surfaces Cursor Agent override"
if grep -q "OCTOPUS_CURSOR_AGENT_MODEL" "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh"; then
    test_pass
else
    test_fail "OCTOPUS_CURSOR_AGENT_MODEL missing from model config helper"
fi

test_case "E009 recovery text keeps four-field parser shape"
if grep -q 'E009:Invalid agent type:Use:' "$PROJECT_ROOT/scripts/lib/interactive.sh" "$PROJECT_ROOT/scripts/orchestrate.sh"; then
    test_fail "E009 still contains extra colon in fix field"
else
    test_pass
fi

test_summary
