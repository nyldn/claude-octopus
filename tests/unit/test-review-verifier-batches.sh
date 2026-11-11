#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/helpers/test-framework.sh"
test_suite "lossless verifier inputs"

test_case "large diffs retain every finding in complete byte-bounded requests"
if python3 - "$ROOT/scripts/helpers/review-verification-batches.py" <<'PY'
import json, runpy, sys
build = runpy.run_path(sys.argv[1])["build_batches"]
diff = "diff --git a/src/app.ts b/src/app.ts\n--- a/src/app.ts\n+++ b/src/app.ts\n@@ -1,5000 +1,5000 @@\n" + "\n".join("+const x%d = '%s';" % (i, "x" * 90) for i in range(5000))
findings = [dict(file="src/app.ts", line=50*i+1, title="finding-%d"%i, detail="detail "+"λ"*80) for i in range(90)]
batches = build(diff, findings, "Read the actual code", 18000)
assert len(batches) > 1
assert [f for rows, _ in batches for f in rows] == findings
for rows, prompt in batches:
    assert len(prompt.encode()) <= 18000
    assert json.loads(prompt.split("Findings to verify:\n",1)[1].split("\nReturn ONLY",1)[0]) == rows
    assert "Diff evidence" in prompt and "new=" in prompt
    for row in rows: assert "new=%d "%row["line"] in prompt
try:
    build(diff, [dict(file="src/app.ts", line=1, detail="x"*20000)], "context", 2048)
except ValueError: pass
else: raise AssertionError("An oversized complete finding was silently clipped")
PY
then test_pass; else test_fail "findings or relevant evidence were lost"; fi

test_case "incomplete verification preserves progress without dispatching corrections"
if (
    source "$ROOT/scripts/lib/testing.sh"
    source "$ROOT/scripts/lib/workflows.sh"
    RESULTS_DIR="$TEST_TMP_DIR/review-incomplete"; mkdir -p "$RESULTS_DIR"
    printf '%s\n' '{"sourceRepository":"fixture","runWorktree":"fixture"}' > "$RESULTS_DIR/.tangle-fixture-git.json"
    printf '%s\n' '{"verification_status":"incomplete","findings":[{"file":"src/app.ts","line":1,"severity":"normal","verdict":"unverified"}]}' > "$RESULTS_DIR/findings.json"
    log() { :; }
    tangle_build_develop_review_context() { echo fixture; }
    tangle_run_context_code_review() { TANGLE_REVIEW_FINDINGS_FILE="$RESULTS_DIR/findings.json"; }
    tangle_apply_review_corrections() { touch "$RESULTS_DIR/corrections-called"; }
    rc=0
    tangle_contextual_review_gate fixture prompt context subtasks validation before || rc=$?
    [[ "$rc" -eq 2 && ! -e "$RESULTS_DIR/corrections-called" ]]
    jq -e '.reviewVerification == "incomplete"' "$RESULTS_DIR/.tangle-fixture-git.json" >/dev/null
); then test_pass; else test_fail "invalid review caused speculative corrections or lost recovery metadata"; fi

test_case "mandatory verifier input is never prefix-truncated by final admission"
if (
    log() { :; }
    source "$ROOT/scripts/lib/models.sh"
    source "$ROOT/scripts/lib/dispatch.sh"
    get_provider_context_limit() { echo 512; }
    get_role_budget_proportion() { echo 100; }
    payload=$(python3 -c 'print("Diff:"+"x"*6000+"\nFindings to verify: [{\"title\":\"tail\"}]")')
    rc=0
    OCTOPUS_OVERSIZE_STRATEGY=fail enforce_context_budget "$payload" implementation-verifier fixture review > "$TEST_TMP_DIR/admitted" || rc=$?
    [[ "$rc" -eq 78 && ! -s "$TEST_TMP_DIR/admitted" ]]
); then test_pass; else test_fail "admission clipped mandatory findings instead of rejecting before dispatch"; fi

test_summary
