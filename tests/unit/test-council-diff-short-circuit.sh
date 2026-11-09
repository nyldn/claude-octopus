#!/usr/bin/env bash
# Report-only diff refinement must not exhaust an already verified quote's budget.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/council.sh"

test_suite "Council diff-side short circuit"

evidence="$TEST_TMP_DIR/evidence"
mkdir -p "$evidence/src"
printf 'export const currentValue = 1;\n' > "$evidence/src/pricing.ts"
# Keep source lookup independent of any ancestor repository on the test host.
git -C "$evidence" init -q
git -C "$evidence" add src/pricing.ts
git -C "$evidence" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm baseline

python3 - "$TEST_TMP_DIR" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
lines = [f"const quotedValue{i:05d} = 1;" for i in range(30000)]
header = "diff --git a/src/pricing.ts b/src/pricing.ts\n--- a/src/pricing.ts\n+++ b/src/pricing.ts\n"
(root / "large.diff").write_text(header + "@@ -1,30000 +1 @@\n" +
    "".join("-" + line + "\n" for line in lines) + "+" + "unrelated " * 140000 + "\n")
(root / "large.md").write_text("src/pricing.ts:1 reads:\n```ts\n" + "\n".join(lines) + "\n```\nVERDICT: REVISE\n")
controls = ["const firstValue = computeFirstValue(input);",
            "const secondValue = computeSecondValue(input);",
            "const thirdValue = computeThirdValue(input);"]
(root / "control.md").write_text("src/pricing.ts:1 reads:\n```ts\n" + "\n".join(controls) + "\n```\nVERDICT: REVISE\n")
for name, removed in [("added-only", []), ("partial-removed", controls[:2])]:
    (root / (name + ".diff")).write_text(header + "@@ -1,2 +1,3 @@\n" +
        "".join("-" + line + "\n" for line in removed) +
        "".join("+" + line + "\n" for line in controls))
PY

# Count production diff-side calls as well as exercising the real deadline.
# Fast hosts can finish the unnecessary scan before the deadline expires.
mkdir -p "$TEST_TMP_DIR/profile-bin"
real_python="$(command -v python3)"
cat > "$TEST_TMP_DIR/profile-bin/python3" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == -I && "${2:-}" == - ]]; then
    exec "$OCTO_TEST_PYTHON" -I "$OCTO_TEST_PROFILE" "${@:3}"
fi
exec "$OCTO_TEST_PYTHON" "$@"
SH
chmod +x "$TEST_TMP_DIR/profile-bin/python3"
cat > "$TEST_TMP_DIR/profile.py" <<'PY'
import os
import sys

def count_sides(frame, event, arg):
    if event == "call" and frame.f_code.co_name == "in_diff_side":
        with open(os.environ["OCTO_TEST_TRACE"], "a") as trace:
            trace.write("side\n")

sys.argv[0] = "-"
sys.setprofile(count_sides)
exec(compile(sys.stdin.read(), "<stdin>", "exec"))
PY

test_case "a complete large removed-side quote verifies within the production deadline"
report="$(export OCTO_TEST_PYTHON="$real_python" OCTO_TEST_PROFILE="$TEST_TMP_DIR/profile.py"
    export OCTO_TEST_TRACE="$TEST_TMP_DIR/sides.log"
    PATH="$TEST_TMP_DIR/profile-bin:$PATH"
    COUNCIL_CONTEXT_FILES=("$TEST_TMP_DIR/large.diff")
    council_response_quote_verification_json "$TEST_TMP_DIR/large.md" "$evidence")"
if jq -e '.verification_failed == false and .quotes_checked == 1 and .quotes_verified == 1
    and .quotes_verified_in_diff_removed == 1 and .quotes_verified_in_diff_added == 0
    and .quotes_partial == 0 and .fabricated == false' <<< "$report" >/dev/null &&
    [[ "$(wc -l < "$TEST_TMP_DIR/sides.log" | tr -d '[:space:]')" == 1 ]]; then
    test_pass
else
    test_fail "complete removed-side quote lost verification: $report"
fi

for control in added-only partial-removed; do
    test_case "$control still checks the added side and preserves removed precedence"
    report="$(COUNCIL_CONTEXT_FILES=("$TEST_TMP_DIR/$control.diff");
        council_response_quote_verification_json "$TEST_TMP_DIR/control.md" "$evidence")"
    expected=added
    [[ "$control" != partial-removed ]] || expected=removed
    if jq -e --arg field "quotes_verified_in_diff_$expected" '.verification_failed == false
        and .quotes_verified == 1 and .[$field] == 1 and .quotes_partial == 0
        and .fabricated == false' <<< "$report" >/dev/null; then
        test_pass
    else
        test_fail "added-side control changed verification or partial reporting: $report"
    fi
done

# A mixed fence has real kept lines in the source and a separate removal.
# Instrument the actual wrapper so fast hosts still detect redundant scans.
python3 - "$TEST_TMP_DIR" "$evidence/src/kept.ts" <<'PY_MIXED'
import sys
from pathlib import Path
root = Path(sys.argv[1])
kept = [f"const keptValue{i:05d} = 1;" for i in range(30000)]
old = "const oldValue = loadPreviousValue(input);"
Path(sys.argv[2]).write_text("\n".join(kept) + "\n")
header = "diff --git a/src/kept.ts b/src/kept.ts\n--- a/src/kept.ts\n+++ b/src/kept.ts\n"
(root / "mixed.diff").write_text(header + "@@ -1 +1 @@\n-" + old + "\n+" + "unrelated " * 140000 + "\n")
(root / "mixed.md").write_text("src/kept.ts:1 reads:\n```diff\n-" + old + "\n" +
    "\n".join(" " + line for line in kept) + "\n```\nVERDICT: REVISE\n")
PY_MIXED

test_case "complete kept code in a mixed fence skips added-side refinement"
rm -f "$TEST_TMP_DIR/sides.log"
report="$(export OCTO_TEST_PYTHON="$real_python" OCTO_TEST_PROFILE="$TEST_TMP_DIR/profile.py"
    export OCTO_TEST_TRACE="$TEST_TMP_DIR/sides.log"
    PATH="$TEST_TMP_DIR/profile-bin:$PATH"
    COUNCIL_CONTEXT_FILES=("$TEST_TMP_DIR/mixed.diff")
    council_response_quote_verification_json "$TEST_TMP_DIR/mixed.md" "$evidence")"
if jq -e '.verification_failed == false and .quotes_verified == 1
    and .quotes_verified_in_diff_removed == 1 and .quotes_partial == 0
    and .fabricated == false' <<< "$report" >/dev/null &&
    [[ "$(wc -l < "$TEST_TMP_DIR/sides.log" | tr -d '[:space:]')" == 1 ]]; then
    test_pass
else
    test_fail "complete kept code triggered redundant diff matching: $report"
fi

test_summary
