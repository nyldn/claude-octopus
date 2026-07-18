#!/usr/bin/env bash
# Tests for scripts/helpers/contrast-check.py (WCAG AA validator).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "WCAG contrast checker"

CHECKER="$PROJECT_ROOT/scripts/helpers/contrast-check.py"

test_case "black on white is 21:1 and passes"
if output=$(python3 "$CHECKER" '#000000:#FFFFFF') && [[ "$output" == *"21.0:1"* ]]; then
    test_pass
else
    test_fail "expected 21.0:1 pass, got: $output"
fi

test_case "known AA boundary color #767676 passes normal text"
if python3 "$CHECKER" '#767676:#FFFFFF' >/dev/null; then
    test_pass
else
    test_fail "#767676 on white (4.54:1) should pass 4.5:1"
fi

test_case "AI-purple #667EEA fails on white and exits 1"
if python3 "$CHECKER" '#667EEA:#FFFFFF' >/dev/null 2>&1; then
    test_fail "expected exit 1 for 3.66:1 normal text"
else
    [[ $? -eq 1 ]] && test_pass || test_fail "expected exit code 1"
fi

test_case "large-text suffix lowers threshold to 3:1"
if python3 "$CHECKER" '#949494:#FFFFFF:large' >/dev/null; then
    test_pass
else
    test_fail "#949494 on white (3.03:1) should pass large-text 3:1"
fi

test_case "3-digit hex shorthand accepted"
if output=$(python3 "$CHECKER" '#000:#FFF') && [[ "$output" == *"21.0:1"* ]]; then
    test_pass
else
    test_fail "shorthand hex failed: $output"
fi

test_case "invalid hex exits 2"
set +e
python3 "$CHECKER" 'zzz:#FFF' >/dev/null 2>&1
code=$?
set -e
if [[ $code -eq 2 ]]; then
    test_pass
else
    test_fail "expected exit 2 on invalid hex, got $code"
fi

test_case "json output reports ratio and failed count"
if output=$(python3 "$CHECKER" '#000:#FFF' --json) && echo "$output" | python3 -c "
import json,sys
d = json.load(sys.stdin)
assert d['failed'] == 0 and d['results'][0]['ratio'] == 21.0
"; then
    test_pass
else
    test_fail "json shape wrong: $output"
fi

test_case "pairs file skips comments and blank lines"
tmpfile="$TEST_TMP_DIR/pairs.txt"
cat > "$tmpfile" <<'EOF'
# comment line

#000000:#FFFFFF
#1D4ED8:#FFFFFF
EOF
if output=$(python3 "$CHECKER" --pairs-file "$tmpfile") && [[ "$output" == *"2/2 pairs pass"* ]]; then
    test_pass
else
    test_fail "pairs file parse wrong: $output"
fi

test_summary
