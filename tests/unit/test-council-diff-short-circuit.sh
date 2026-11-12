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
import ast
import os
import sys

def count_sides(frame, event, arg):
    if event == "call" and frame.f_code.co_name == "in_diff_side":
        with open(os.environ["OCTO_TEST_TRACE"], "a") as trace:
            trace.write("side\n")

def trace_match_unit(verified, partial, path, bound_paths, *args, **kwargs):
    trace_path = os.environ.get("OCTO_TEST_REFINEMENT_TRACE")
    if trace_path and verified and partial and path not in bound_paths:
        with open(trace_path, "a") as trace:
            trace.write(str(len(args[2][0].encode("utf-8"))) + "\n")
    return match_unit(*args, **kwargs)


class TraceRefinement(ast.NodeTransformer):
    """Pass loop state explicitly instead of inspecting another frame's locals."""

    replacements = 0

    def visit_FunctionDef(self, node):
        return node

    def visit_Call(self, node):
        self.generic_visit(node)
        if isinstance(node.func, ast.Name) and node.func.id == "match_unit":
            self.replacements += 1
            node.func.id = "trace_match_unit"
            node.args[:0] = [ast.Name(id=name, ctx=ast.Load())
                            for name in ("verified", "partial", "path", "bound_paths")]
        return node

sys.argv[0] = "-"
tree = ast.parse(sys.stdin.read(), "<stdin>")
instrument = TraceRefinement()
tree = instrument.visit(tree)
if instrument.replacements != 1:
    raise RuntimeError("expected one source-file matching call to instrument")
sys.setprofile(count_sides)
exec(compile(ast.fix_missing_locations(tree), "<stdin>", "exec"))
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

# A partial fence already verifies. Searching unrelated large cited files only
# refines its report and must leave time for the remaining quotes.
test_case "partial fences keep later unbound-file refinement bounded"
python3 - "$TEST_TMP_DIR" <<'PY_PARTIAL_FILES'
import sys
from pathlib import Path

root = Path(sys.argv[1])
evidence = root / "evidence"
first = "const actualPrice = calculateActualPrice(input);"
last = "return applyActualTaxes(price, sailing);"
quotes = []
for index in range(100):
    padding = "x" * 1400000 if index else ""
    (evidence / f"file{index}.ts").write_text(first + "\n" + last + "\n" + padding)
    quotes.append(f"file{index}.ts:1 reads:\n```ts\n{first}\nreturn missing_{index};\n{last}\n```\n")
(root / "partial-files.md").write_text("\n".join(quotes) + "\nVERDICT: APPROVE\n")
PY_PARTIAL_FILES
report="$(export OCTO_TEST_PYTHON="$real_python" OCTO_TEST_PROFILE="$TEST_TMP_DIR/profile.py"
    export OCTO_TEST_TRACE="$TEST_TMP_DIR/sides.log" OCTO_TEST_REFINEMENT_TRACE="$TEST_TMP_DIR/refinement.log"
    PATH="$TEST_TMP_DIR/profile-bin:$PATH"
    council_response_quote_verification_json "$TEST_TMP_DIR/partial-files.md" "$evidence")"
refinement_bytes="$(awk '{total += $1} END {print total+0}' "$TEST_TMP_DIR/refinement.log" 2>/dev/null || printf 0)"
if jq -e '.verification_failed == false and .quotes_verified == 100
    and .quotes_partial == 100 and .fabricated == false' <<< "$report" >/dev/null &&
    [[ -s "$TEST_TMP_DIR/refinement.log" ]] &&
    (( refinement_bytes <= 100 * 65536 )); then
    test_pass
else
    test_fail "unbound partial refinement scanned $refinement_bytes bytes: $report"
fi

test_case "a complete small unbound file still refines a partial fence"
first='const actualPrice = calculateActualPrice(input);'
last='return applyActualTaxes(price, sailing);'
printf '%s\n' "$first" "$last" > "$evidence/src/partial.ts"
printf '%s\n' "$first" 'return actual;' "$last" 'const marker = loadMarker(input);' > "$evidence/src/complete.ts"
printf 'src/partial.ts:1 reads:\n```ts\n%s\nreturn actual;\n%s\n```\n\nsrc/complete.ts:4 reads `const marker = loadMarker(input);`.\n' \
    "$first" "$last" > "$TEST_TMP_DIR/partial-small.md"
rm -f "$TEST_TMP_DIR/refinement.log"
report="$(export OCTO_TEST_PYTHON="$real_python" OCTO_TEST_PROFILE="$TEST_TMP_DIR/profile.py"
    export OCTO_TEST_TRACE="$TEST_TMP_DIR/sides.log" OCTO_TEST_REFINEMENT_TRACE="$TEST_TMP_DIR/refinement.log"
    PATH="$TEST_TMP_DIR/profile-bin:$PATH"
    council_response_quote_verification_json "$TEST_TMP_DIR/partial-small.md" "$evidence")"
if jq -e '.verification_failed == false and .quotes_verified == 2
    and .quotes_partial == 0 and .fabricated == false' <<< "$report" >/dev/null &&
    [[ -s "$TEST_TMP_DIR/refinement.log" ]]; then
    test_pass
else
    test_fail "bounded refinement lost a small complete source match: $report"
fi

test_case "large optional diff scans preserve an already verified partial fence"
python3 - "$TEST_TMP_DIR" "$evidence" <<'PY_OPTIONAL_DIFF'
import sys
from pathlib import Path
root, evidence = map(Path, sys.argv[1:])
lines = [f"const actualValue{i:05d} = 1;" for i in range(18000)]
(evidence / "src/optional.ts").write_text("\n".join(lines) + "\n")
(root / "optional.md").write_text("src/optional.ts:1 reads:\n```ts\n" +
    "\n".join(lines) + "\nreturn fake;\n```\nVERDICT: APPROVE\n")
(root / "optional.diff").write_text(
    "diff --git a/src/optional.ts b/src/optional.ts\n--- a/src/optional.ts\n"
    "+++ b/src/optional.ts\n@@ -1,2 +1 @@\n-" + "unrelated " * 700000 +
    "\n-const previousPrice = loadPreviousPrice(input);\n+changed\n")
for name, quote in [("removed", "const previousPrice = loadPreviousPrice(input);"),
                    ("invented", "const inventedPrice = fetchInventedPrice(input);")]:
    prefix = (root / "optional.md").read_text().replace("VERDICT: APPROVE\n", "")
    (root / f"required-{name}.md").write_text(prefix +
        f"\nsrc/optional.ts:1 reads `{quote}`.\nVERDICT: APPROVE\n")
PY_OPTIONAL_DIFF
report="$(COUNCIL_CONTEXT_FILES=("$TEST_TMP_DIR/optional.diff");
    council_response_quote_verification_json "$TEST_TMP_DIR/optional.md" "$evidence")"
if jq -e '.verification_failed == false and .quotes_verified == 1
    and .quotes_partial == 1 and .fabricated == false' <<< "$report" >/dev/null; then
    test_pass
else
    test_fail "optional diff matching discarded verified evidence: $report"
fi

for claim in removed invented; do
    test_case "exhausted optional work preserves required $claim matching"
    report="$(COUNCIL_CONTEXT_FILES=("$TEST_TMP_DIR/optional.diff");
        council_response_quote_verification_json "$TEST_TMP_DIR/required-$claim.md" "$evidence")"
    if jq -e --arg claim "$claim" '.verification_failed == false and .diff_unavailable == false
        and .quotes_partial == 1
        and (if $claim == "removed" then .quotes_verified == 2
            and .quotes_verified_in_diff_removed == 1 and .fabricated == false
            else .quotes_verified == 1 and .quotes_attributed_unverified == 1
            and .fabricated == true end)' <<< "$report" >/dev/null; then
        test_pass
    else
        test_fail "optional budget changed required evidence matching: $report"
    fi
done

test_case "distinct short elisions cannot exhaust source verification"
python3 - "$TEST_TMP_DIR" "$evidence" <<'PY_SHORT_ELISIONS'
import sys
from pathlib import Path
root, evidence = map(Path, sys.argv[1:])
first = "const firstValue = loadActualPrice(input);"
last = "return applyActualTaxes(price, sailing);"
source = first + "\n" + "".join(f"r{i:05d} retained;\n" for i in range(60000)) + last + "\n"
(evidence / "src/elisions.ts").write_text(source + "x" * (1350085 - len(source)))
(root / "elisions.md").write_text("src/elisions.ts:1 reads:\n```ts\n" + first + "\n" +
    "".join(f"r{i:05d}...;\n" for i in reversed(range(60000))) + last + "\n```\nVERDICT: APPROVE\n")
PY_SHORT_ELISIONS
report="$(council_response_quote_verification_json "$TEST_TMP_DIR/elisions.md" "$evidence")"
if jq -e '.verification_failed == false and .quotes_verified == 1
    and .quotes_partial == 1 and .fabricated == false' <<< "$report" >/dev/null; then
    test_pass
else
    test_fail "report-only elision matching discarded verified evidence: $report"
fi

test_summary
