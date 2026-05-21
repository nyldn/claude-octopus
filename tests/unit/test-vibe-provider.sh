#!/usr/bin/env bash
# Tests for Mistral Vibe provider shim behavior.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Mistral Vibe provider"

HELPER="$PROJECT_ROOT/scripts/helpers/vibe-exec.sh"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

if [[ -x "$HELPER" ]]; then
    pass "vibe-exec helper exists and is executable"
else
    fail "vibe-exec helper exists and is executable" "missing or not executable: $HELPER"
fi

if bash -n "$HELPER"; then
    pass "vibe-exec helper has valid bash syntax"
else
    fail "vibe-exec helper has valid bash syntax" "syntax error"
fi

cat > "$MOCK_BIN_DIR/vibe" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*"
EOF
chmod +x "$MOCK_BIN_DIR/vibe"

test_case "vibe-exec forwards stdin prompt as -p argument"
if output=$(printf 'Reply ACK' | PATH="$MOCK_BIN_DIR:$PATH" "$HELPER" --output text 2>&1); then
    if [[ "$output" == *"--output text -p Reply ACK"* ]]; then
        test_pass
    else
        test_fail "expected prompt to be forwarded; got: $output"
    fi
else
    test_fail "helper failed unexpectedly: $output"
fi

test_case "vibe-exec fails clearly on empty stdin prompt"
set +e
empty_output=$(printf '' | PATH="$MOCK_BIN_DIR:$PATH" "$HELPER" --output text 2>&1)
empty_status=$?
set -e
if [[ "$empty_status" -eq 64 && "$empty_output" == *"no prompt provided on stdin"* ]]; then
    test_pass
else
    test_fail "expected exit 64 with clear no-prompt error; status=$empty_status output=$empty_output"
fi

test_case "vibe-exec fails clearly on whitespace-only stdin prompt"
set +e
whitespace_output=$(printf ' \t\n ' | PATH="$MOCK_BIN_DIR:$PATH" "$HELPER" --output text 2>&1)
whitespace_status=$?
set -e
if [[ "$whitespace_status" -eq 64 && "$whitespace_output" == *"no prompt provided on stdin"* ]]; then
    test_pass
else
    test_fail "expected exit 64 with clear whitespace-only prompt error; status=$whitespace_status output=$whitespace_output"
fi

test_summary
