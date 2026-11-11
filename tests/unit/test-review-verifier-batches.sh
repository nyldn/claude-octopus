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
excerpt = runpy.run_path(sys.argv[1])["excerpts"]
headers_in_hunks = "diff --git a/app.sql b/app.sql\n--- a/app.sql\n+++ b/app.sql\n@@ -1,70 +1,1000 @@\n" + "\n".join(["--- comment"]*70 + ["+++counter%d;"%i for i in range(1000)])
assert "old=71 new=30 +++counter29;" in excerpt(headers_in_hunks, dict(file="app.sql", line=30), 6000)
assert "do not confirm without code evidence" in excerpt(headers_in_hunks, dict(file="app.sql",line=100000),6000)
no_prefix = "diff --git app.py app.py\n--- app.py\n+++ app.py\n@@ -1 +1 @@\n-old\n+TARGET_OPERATION\n" + diff
assert "TARGET_OPERATION" in build(no_prefix, [dict(file="app.py", line=1, title="target")], "context", 6000)[0][1]
repeated = "diff --git a/app.py b/app.py\n--- a/app.py\n+++ /dev/null\n@@ -1 +0,0 @@\n-REMOVED_VERSION\n" + no_prefix
both = build(repeated, [dict(file="app.py",line=1,title="target")], "context", 6000)[0][1]
assert "REMOVED_VERSION" in both and "TARGET_OPERATION" in both
try:
    build(diff, [dict(file="src/app.ts", line=1, detail="x"*20000)], "context", 2048)
except ValueError: pass
else: raise AssertionError("An oversized complete finding was silently clipped")
PY
then test_pass; else test_fail "findings or relevant evidence were lost"; fi

test_case "batch files retain Unicode in an ASCII locale and tolerate source byte decoding"
if python3 - "$ROOT/scripts/helpers/review-verification-batches.py" <<'PY'
import json, os, subprocess, sys, tempfile
from pathlib import Path
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    (root/"diff").write_bytes(b"diff --git a/app.py b/app.py\n--- a/app.py\n+++ b/app.py\n@@ -1 +1 @@\n-old\n+caf\xe9\n")
    (root/"findings").write_text(json.dumps([dict(file="app.py",line=1,title="λ")],ensure_ascii=False),encoding="utf-8")
    (root/"context").write_text("review",encoding="utf-8")
    subprocess.run([sys.executable,"-X","utf8=0","-I",sys.argv[1],"--diff",str(root/"diff"),"--findings",str(root/"findings"),"--context",str(root/"context"),"--output",directory,"--max-bytes","6000"],env={**os.environ,"LC_ALL":"C","PYTHONCOERCECLOCALE":"0"},check=True)
    assert json.loads((root/"batch-00000.json").read_text(encoding="utf-8"))[0]["title"] == "λ"
    assert "caf�" in (root/"batch-00000.prompt").read_text(encoding="utf-8")
PY
then test_pass; else test_fail "locale corrupted a complete batch"; fi

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
    [[ "$rc" -eq 2 && ! -e "$RESULTS_DIR/corrections-called" ]] || exit 1
    jq -e '.reviewVerification == "incomplete"' "$RESULTS_DIR/.tangle-fixture-git.json" >/dev/null
    printf '%s\n' '{"findings":[],"warning":"No providers returned a review"}' > "$RESULTS_DIR/findings.json"
    tangle_run_context_code_review() { TANGLE_REVIEW_FINDINGS_FILE="$RESULTS_DIR/findings.json"; return 1; }
    rc=0
    tangle_contextual_review_gate fixture prompt context subtasks validation before || rc=$?
    [[ "$rc" -eq 1 && ! -e "$RESULTS_DIR/corrections-called" ]] || exit 1
    jq -e '.reviewVerification == "incomplete"' "$RESULTS_DIR/.tangle-fixture-git.json" >/dev/null || exit 1
    printf '%s\n' '{"findings":[]}' > "$RESULTS_DIR/findings.json"
    tangle_run_context_code_review() { TANGLE_REVIEW_FINDINGS_FILE="$RESULTS_DIR/findings.json"; }
    tangle_contextual_review_gate fixture prompt context subtasks validation before || exit 1
    jq -e '.reviewVerification == "complete"' "$RESULTS_DIR/.tangle-fixture-git.json" >/dev/null
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

test_case "unmanaged fallback replans complete findings for its own smaller window"
if (
    source "$ROOT/scripts/lib/review.sh"
    log() { :; }
    inputs="$TEST_TMP_DIR/fallback"; mkdir -p "$inputs"
    printf '%s\n' 'diff --git a/app.py b/app.py' '--- a/app.py' '+++ b/app.py' '@@ -1 +1 @@' '-old' '+new' > "$inputs/diff"
    printf 'context' > "$inputs/context"
    printf '[]' > "$inputs/statuses"
    python3 - "$inputs/findings" <<'PY'
import json, sys
with open(sys.argv[1],"w") as stream:
    json.dump([dict(file="app.py",line=1,title="finding-%d"%i,detail="x"*140) for i in range(90)],stream)
PY
    get_provider_context_limit() { echo 3000; }
    get_role_budget_proportion() { echo 100; }
    review_run_agent_sync_progress() {
        printf 'call\n' >> "$inputs/calls"
        printf '%s' "$2" | python3 -c '
import json,sys
prompt=sys.stdin.read()
assert len(prompt.encode()) <= 6000
rows=json.JSONDecoder().raw_decode(prompt.split("Findings to verify:\n",1)[1])[0]
print(json.dumps({"findings":[dict(row,verdict="confirmed") for row in rows]}))'
    }
    response=$(review_verifier_fallback "$inputs" "$inputs/findings" claude-sonnet "$inputs/statuses") || exit 1
    [[ "$(wc -l < "$inputs/calls")" -gt 1 ]] || exit 1
    printf '%s' "$response" | jq -e '.findings | length == 90' >/dev/null || exit 1
    printf '%s' "$response" | jq -e 'all(.findings[]; .verdict == "confirmed")' >/dev/null || exit 1
    printf '%s' "$response" | jq -e '[.findings[].title] | unique | length == 90' >/dev/null || exit 1
    : > "$inputs/calls"
    python3 - "$inputs/findings" <<'PY'
import json,sys
with open(sys.argv[1],"w") as stream:
    json.dump([dict(file="app.py",line=1,title="too big",detail="x"*10000)],stream)
PY
    rc=0
    review_verifier_fallback "$inputs" "$inputs/findings" claude-sonnet "$inputs/statuses" >/dev/null 2>&1 || rc=$?
    [[ "$rc" -ne 0 && ! -s "$inputs/calls" ]]
); then test_pass; else test_fail "fallback clipped inputs, lost findings or skipped its own limit"; fi

test_case "scope recovery cannot turn a failed fleet into a completed review"
if (
    source "$ROOT/scripts/lib/testing.sh"
    source "$ROOT/scripts/lib/workflows.sh"
    log() { :; }
    tangle_build_develop_review_context() { echo fixture; }
    tangle_validate_results_with_scope_contract() { return 0; }
    export OCTOPUS_TANGLE_REVIEW_CORRECTION_MODE=bounded
    export OCTOPUS_TANGLE_REVIEW_CORRECTION_ROUNDS=2
    for failed_round in 1 2; do
        RESULTS_DIR="$TEST_TMP_DIR/scope-fleet-$failed_round"
        mkdir -p "$RESULTS_DIR"
        printf '%s\n' '{}' > "$RESULTS_DIR/.tangle-fixture-git.json"
        TANGLE_SCOPE_CONTRACT_VIOLATIONS=src/outside.ts
        review_calls=0 correction_calls=0
        tangle_run_context_code_review() {
            review_calls=$((review_calls + 1))
            TANGLE_REVIEW_FINDINGS_FILE="$RESULTS_DIR/findings-$review_calls.json"
            if [[ "$review_calls" -eq "$failed_round" ]]; then
                printf '%s\n' '{"findings":[],"warning":"No providers returned a review"}' > "$TANGLE_REVIEW_FINDINGS_FILE"
                return 1
            fi
            printf '%s\n' '{"findings":[{"file":"app.ts","line":1,"title":"real blocker","severity":"normal","verdict":"confirmed"}]}' > "$TANGLE_REVIEW_FINDINGS_FILE"
        }
        tangle_apply_review_corrections() {
            correction_calls=$((correction_calls + 1))
            TANGLE_CORRECTION_STATUS="done" TANGLE_CORRECTION_CHANGED=1
        }
        rc=0
        tangle_contextual_review_gate fixture prompt context subtasks validation before || rc=$?
        [[ "$rc" -eq 1 && "$correction_calls" -eq $((failed_round - 1)) ]] || exit 1
        jq -e '.reviewVerification == "incomplete"' "$RESULTS_DIR/.tangle-fixture-git.json" >/dev/null || exit 1
        # Keep the failed evidence intact for a subsequent retry.
        jq -e '.warning == "No providers returned a review" and (.findings | length == 0)' "$TANGLE_REVIEW_FINDINGS_FILE" >/dev/null || exit 1
    done
); then test_pass; else test_fail "scope findings hid fleet failure or dispatched speculative corrections"; fi

test_case "a direct retry marks verification pending before context setup"
retry_results="$TEST_TMP_DIR/context-setup-failure"
mkdir -p "$retry_results"
printf '%s\n' '{"reviewVerification":"complete"}' > "$retry_results/.tangle-fixture-git.json"
rc=0
OCTOPUS_TANGLE_CODE_REVIEW=true bash -e -c '
    source "$1/scripts/lib/testing.sh"
    source "$1/scripts/lib/workflows.sh"
    RESULTS_DIR="$2"
    log() { :; }
    tangle_build_develop_review_context() { return 73; }
    tangle_run_context_code_review() { touch "$RESULTS_DIR/review-called"; }
    tangle_contextual_review_gate fixture prompt context subtasks validation before
' _ "$ROOT" "$retry_results" || rc=$?
if [[ "$rc" -eq 73 && ! -e "$retry_results/review-called" ]] &&
   jq -e '.reviewVerification == "pending" and .reviewFindings == ""' "$retry_results/.tangle-fixture-git.json" >/dev/null; then
    test_pass
else test_fail "context setup failure preserved an earlier completed review"; fi

test_summary
