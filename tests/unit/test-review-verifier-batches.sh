#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
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
    jq -e '.reviewVerification == "incomplete"' "$RESULTS_DIR/.tangle-fixture-git.json" >/dev/null || exit 1
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

test_case "retry without a new artifact preserves the earlier recovery findings path"
if (
    source "$ROOT/scripts/lib/testing.sh"
    source "$ROOT/scripts/lib/workflows.sh"
    log() { :; }
    RESULTS_DIR="$TEST_TMP_DIR/retry-without-artifact"; mkdir -p "$RESULTS_DIR"
    metadata="$RESULTS_DIR/.tangle-fixture-git.json"
    previous="$RESULTS_DIR/earlier-findings.json"
    printf '%s\n' '{"verification_status":"incomplete","findings":[]}' > "$previous"
    jq -n --arg findings "$previous" '{reviewVerification:"incomplete",reviewFindings:$findings,reviewOutcome:"incomplete"}' > "$metadata"
    tangle_build_develop_review_context() { echo context; }
    tangle_run_context_code_review() { TANGLE_REVIEW_FINDINGS_FILE=""; return 73; }
    tangle_apply_review_corrections() { touch "$RESULTS_DIR/corrections-called"; }
    rc=0
    tangle_contextual_review_gate fixture prompt context subtasks validation before || rc=$?
    [[ "$rc" -ne 0 && ! -e "$RESULTS_DIR/corrections-called" && -f "$previous" ]] || exit 1
    jq -e --arg findings "$previous" '.reviewVerification == "incomplete" and .reviewOutcome == "incomplete" and .reviewFindings == $findings' "$metadata" >/dev/null || exit 1
    replacement="$RESULTS_DIR/new-findings.json"
    printf '%s\n' '{"verification_status":"incomplete","findings":[]}' > "$replacement"
    tangle_record_review_verification fixture "$replacement" incomplete || exit 1
    jq -e --arg findings "$replacement" '.reviewFindings == $findings' "$metadata" >/dev/null || exit 1
    tangle_record_review_verification fixture "" incomplete || exit 1
    jq -e --arg findings "$replacement" '.reviewFindings == $findings' "$metadata" >/dev/null || exit 1
    printf '%s\n' '{"findings":[]}' > "$replacement"
    tangle_run_context_code_review() { TANGLE_REVIEW_FINDINGS_FILE="$replacement"; }
    tangle_contextual_review_gate fixture prompt context subtasks validation before || exit 1
    jq -e --arg findings "$replacement" '.reviewVerification == "complete" and .reviewFindings == $findings and .reviewOutcome == "complete"' "$metadata" >/dev/null
); then test_pass; else test_fail "failed retry erased recovery evidence or prevented a complete retry"; fi

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

test_case "verifier responses preserve original fields and allow only verification additions"
if (
    source "$ROOT/scripts/lib/review.sh"
    originals="$TEST_TMP_DIR/original-findings.json"
    printf '%s\n' '[{"file":"app.py","line":1,"title":"bug","detail":"bad","category":"logic","severity":"normal","confidence":0.2,"extra":{"b":2,"a":1}}]' > "$originals"
    valid='{"findings":[{"extra":{"a":1,"b":2},"confidence":0.2,"severity":"normal","category":"logic","detail":"bad","title":"bug","line":1,"file":"app.py","verdict":"confirmed","pre_existing_newly_reachable":true}]}'
    printf '%s' "$valid" | review_validate_verdicts "$originals" >/dev/null || exit 1
    for mutation in '.findings[0].confidence = 0.99' 'del(.findings[0].extra)' '.findings[0].extra.a = 9' '.findings[0].invented = true'; do
        if printf '%s' "$valid" | jq "$mutation" | review_validate_verdicts "$originals" >/dev/null 2>&1; then exit 1; fi
    done
); then test_pass; else test_fail "verifier changed original fields or rejected equivalent JSON"; fi

test_case "missing and invalid final verdicts cannot authorize Tangle corrections"
if (
    source "$ROOT/scripts/lib/testing.sh"
    source "$ROOT/scripts/lib/workflows.sh"
    log() { :; }
    RESULTS_DIR="$TEST_TMP_DIR/missing-verdict"; mkdir -p "$RESULTS_DIR"
    printf '%s\n' '{}' > "$RESULTS_DIR/.tangle-fixture-git.json"
    tangle_build_develop_review_context() { echo fixture; }
    tangle_run_context_code_review() { TANGLE_REVIEW_FINDINGS_FILE="$RESULTS_DIR/findings.json"; }
    tangle_apply_review_corrections() { touch "$RESULTS_DIR/corrections-called"; return 77; }
    for verdict in null '""' '"unverified"' '"invented"'; do
        jq -n --argjson verdict "$verdict" '{findings:[{file:"app.py",line:1,title:"bug",severity:"normal",verdict:$verdict}]}' > "$RESULTS_DIR/findings.json"
        rc=0
        tangle_contextual_review_gate fixture prompt context subtasks validation before || rc=$?
        [[ "$rc" -eq 2 && ! -e "$RESULTS_DIR/corrections-called" ]] || exit 1
        jq -e '.reviewVerification == "incomplete"' "$RESULTS_DIR/.tangle-fixture-git.json" >/dev/null || exit 1
    done
    for verdict in confirmed needs-debate false-positive; do
        jq -n --arg verdict "$verdict" '{findings:[{verdict:$verdict}]}' > "$RESULTS_DIR/findings.json"
        tangle_review_verification_complete "$RESULTS_DIR/findings.json" || exit 1
    done
); then test_pass; else test_fail "an absent or invalid verdict authorized corrections"; fi

test_case "manifest rename failure is reported and its temporary file is removed"
if (
    source "$ROOT/scripts/lib/workflows.sh"
    log() { :; }
    RESULTS_DIR="$TEST_TMP_DIR/manifest-rename"; mkdir -p "$RESULTS_DIR"
    metadata="$RESULTS_DIR/.tangle-fixture-git.json"
    printf '%s\n' '{"reviewVerification":"complete"}' > "$metadata"
    mv() { return 73; }
    rc=0
    tangle_record_review_verification fixture findings incomplete || rc=$?
    [[ "$rc" -ne 0 ]] || exit 1
    jq -e '.reviewVerification == "complete"' "$metadata" >/dev/null || exit 1
    [[ "$(find "$RESULTS_DIR" -type f | wc -l)" -eq 1 ]]
); then test_pass; else test_fail "failed manifest replacement returned success or retained temporary state"; fi

test_case "patch windows keep adjacent removals and shrink before rejecting complete findings"
if python3 - "$ROOT/scripts/helpers/review-verification-batches.py" <<'PY'
import runpy, sys
module = runpy.run_path(sys.argv[1])
diff = "diff --git a/app.py b/app.py\n--- a/app.py\n+++ b/app.py\n@@ -1,101 +501,101 @@\n-OLD_GUARD\n+NEW_GUARD\n" + "".join(" context " + "x" * 180 + "\n" for _ in range(100))
finding = dict(file="app.py", line=501, title="guard", detail="Retain the original guard")
prompt = module["build_batches"](diff, [finding], "Required context", 6000)[0][1]
assert "OLD_GUARD" in prompt and "NEW_GUARD" in prompt
finding["line"] = 551
rows, prompt = module["build_batches"](diff, [finding], "Required context", 6000)[0]
assert len(prompt.encode()) <= 6000 and rows == [finding]
assert "new=551 " in prompt and "Required context" in prompt
PY
then test_pass; else test_fail "patch admission lost adjacent code or refused a reducible window"; fi

test_case "conditional callers stop on initial and retry context failures"
if (
    source "$ROOT/scripts/lib/testing.sh"
    source "$ROOT/scripts/lib/workflows.sh"
    log() { :; }
    export OCTOPUS_TANGLE_REVIEW_CORRECTION_MODE=bounded
    export OCTOPUS_TANGLE_REVIEW_CORRECTION_ROUNDS=2
    for failed_round in initial correction-1; do
        RESULTS_DIR="$TEST_TMP_DIR/conditional-context-$failed_round"; mkdir -p "$RESULTS_DIR"
        printf '%s\n' '{}' > "$RESULTS_DIR/.tangle-fixture-git.json"
        tangle_build_develop_review_context() { [[ "$7" != "$failed_round" ]] || return 73; echo context; }
        tangle_run_context_code_review() {
            printf '%s\n' "$3" >> "$RESULTS_DIR/review-calls"
            TANGLE_REVIEW_FINDINGS_FILE="$RESULTS_DIR/findings.json"
            printf '%s\n' '{"findings":[{"file":"app.py","line":1,"title":"blocker","severity":"normal","verdict":"confirmed"}]}' > "$TANGLE_REVIEW_FINDINGS_FILE"
        }
        tangle_apply_review_corrections() { TANGLE_CORRECTION_STATUS="done" TANGLE_CORRECTION_CHANGED=1; }
        tangle_validate_results_with_scope_contract() { return 0; }
        rc=0
        if tangle_contextual_review_gate fixture prompt context subtasks validation before; then rc=0; else rc=$?; fi
        [[ "$rc" -eq 73 ]] || exit 1
        jq -e '.reviewVerification == "pending"' "$RESULTS_DIR/.tangle-fixture-git.json" >/dev/null || exit 1
        if [[ "$failed_round" == initial ]]; then
            [[ ! -e "$RESULTS_DIR/review-calls" ]] || exit 1
        else
            [[ "$(cat "$RESULTS_DIR/review-calls")" == initial ]] || exit 1
        fi
    done
); then test_pass; else test_fail "conditional gate reviewed without its context or cleared pending state"; fi

test_case "partial verified findings permit correction without claiming a complete review"
if (
    source "$ROOT/scripts/lib/testing.sh"
    source "$ROOT/scripts/lib/workflows.sh"
    log() { :; }
    RESULTS_DIR="$TEST_TMP_DIR/partial-verification"; mkdir -p "$RESULTS_DIR"
    printf '%s\n' '{}' > "$RESULTS_DIR/.tangle-fixture-git.json"
    export OCTOPUS_TANGLE_REVIEW_CORRECTION_MODE=bounded
    export OCTOPUS_TANGLE_REVIEW_CORRECTION_ROUNDS=2
    tangle_build_develop_review_context() { echo context; }
    tangle_run_context_code_review() {
        TANGLE_REVIEW_FINDINGS_FILE="$RESULTS_DIR/findings.json"
        printf '%s\n' '{"warning":"Partial reviewer fleet","findings":[{"file":"app.py","line":1,"title":"blocker","severity":"normal","verdict":"confirmed"}]}' > "$TANGLE_REVIEW_FINDINGS_FILE"
        return 3
    }
    tangle_apply_review_corrections() { touch "$RESULTS_DIR/correction-called"; return 77; }
    rc=0
    tangle_contextual_review_gate fixture prompt context subtasks validation before || rc=$?
    [[ "$rc" -eq 77 && -f "$RESULTS_DIR/correction-called" ]] || exit 1
    jq -e '.reviewVerification == "incomplete" and .reviewOutcome == "partial-verified"' "$RESULTS_DIR/.tangle-fixture-git.json" >/dev/null || exit 1
    tangle_run_context_code_review() {
        TANGLE_REVIEW_FINDINGS_FILE="$RESULTS_DIR/findings.json"
        printf '%s\n' '{"warning":"Partial reviewer fleet","findings":[{"file":"app.py","line":1,"title":"note","severity":"nit","verdict":"confirmed"}]}' > "$TANGLE_REVIEW_FINDINGS_FILE"
        return 3
    }
    rm -f "$RESULTS_DIR/correction-called"
    rc=0
    tangle_contextual_review_gate fixture prompt context subtasks validation before || rc=$?
    [[ "$rc" -eq 3 && ! -e "$RESULTS_DIR/correction-called" ]] || exit 1
    jq -e '.reviewVerification == "incomplete"' "$RESULTS_DIR/.tangle-fixture-git.json" >/dev/null
); then test_pass; else test_fail "partial findings blocked verified correction or recorded a complete review"; fi

test_case "large deleted-file findings use old-file coordinates"
if python3 - "$ROOT/scripts/helpers/review-verification-batches.py" <<'PYTEST'
import runpy, sys
excerpts = runpy.run_path(sys.argv[1])["excerpts"]
diff = "diff --git a/gone.py b/gone.py\n--- a/gone.py\n+++ /dev/null\n@@ -1,500 +0,0 @@\n" + "".join(f"-removed_{i}\n" for i in range(1,501))
evidence = excerpts(diff, dict(file="gone.py", line=250), 6000)
assert "old=250 new=0 -removed_250" in evidence, evidence
assert "No patch lines" not in evidence
PYTEST
then test_pass; else test_fail "deleted-file evidence was missing at the cited old line"; fi


test_case "failed review infrastructure cannot authorize correction or completion"
if (
    source "$ROOT/scripts/lib/testing.sh"
    source "$ROOT/scripts/lib/workflows.sh"
    log() { :; }
    export OCTOPUS_TANGLE_REVIEW_CORRECTION_MODE=bounded
    export OCTOPUS_TANGLE_REVIEW_CORRECTION_ROUNDS=2
    tangle_build_develop_review_context() { echo context; }
    tangle_validate_results_with_scope_contract() { return 0; }
    for failed_round in 1 2; do
        RESULTS_DIR="$TEST_TMP_DIR/failed-proof-$failed_round"; mkdir -p "$RESULTS_DIR"
        printf '%s\n' '{}' > "$RESULTS_DIR/.tangle-fixture-git.json"
        review_calls=0 correction_calls=0
        tangle_run_context_code_review() {
            review_calls=$((review_calls + 1))
            TANGLE_REVIEW_FINDINGS_FILE="$RESULTS_DIR/findings.json"
            printf '%s\n' '{"findings":[{"file":"app.py","line":1,"severity":"normal","verdict":"confirmed"}]}' > "$TANGLE_REVIEW_FINDINGS_FILE"
            [[ "$review_calls" -ne "$failed_round" ]]
        }
        tangle_apply_review_corrections() { correction_calls=$((correction_calls + 1)); TANGLE_CORRECTION_STATUS=done; TANGLE_CORRECTION_CHANGED=1; }
        rc=0
        tangle_contextual_review_gate fixture prompt context subtasks validation before || rc=$?
        [[ "$rc" -eq 1 && "$correction_calls" -eq $((failed_round - 1)) ]] || exit 1
        jq -e '.reviewVerification == "incomplete"' "$RESULTS_DIR/.tangle-fixture-git.json" >/dev/null || exit 1
    done
); then test_pass; else test_fail "a failed review with saved verdicts authorized corrections"; fi

test_case "long removal runs shrink while retaining the cited new line"
if python3 - "$ROOT/scripts/helpers/review-verification-batches.py" <<'PYTEST'
import runpy, sys
m = runpy.run_path(sys.argv[1])
diff = "diff --git a/app.py b/app.py\n--- a/app.py\n+++ b/app.py\n@@ -1,500 +1 @@\n" + "".join("-removed_%d %s\n" % (i, "x"*180) for i in range(500)) + "+TARGET_OPERATION\n"
finding = dict(file="app.py", line=1, title="target")
rows, prompt = m["build_batches"](diff, [finding], "Required context", 6000)[0]
assert rows == [finding] and len(prompt.encode()) <= 6000
assert "TARGET_OPERATION" in prompt and "removed_499" in prompt
PYTEST
then test_pass; else test_fail "adjacent removal context prevented a bounded verifier request"; fi

test_case "unmatched short patches carry an explicit inspection warning"
if python3 - "$ROOT/scripts/helpers/review-verification-batches.py" <<'PYTEST'
import runpy, sys
excerpts = runpy.run_path(sys.argv[1])["excerpts"]
diff = "diff --git a/other.py b/other.py\n--- a/other.py\n+++ b/other.py\n@@ -1 +1 @@\n-old\n+UNRELATED_CODE\n"
evidence = excerpts(diff, dict(file="app.py", line=1), 6000)
assert "No matching patch block" in evidence and "do not confirm without code evidence" in evidence
assert "UNRELATED_CODE" in evidence
PYTEST
then test_pass; else test_fail "unrelated short patch was presented as matching evidence"; fi


test_case "context wrapper distinguishes completed partial reviews from infrastructure failure"
if (
    source "$ROOT/scripts/lib/workflows.sh"
    source "$ROOT/scripts/lib/review.sh"
    log() { :; }
    RESULTS_DIR="$TEST_TMP_DIR/wrapper-partial"; mkdir -p "$RESULTS_DIR"
    export OCTOPUS_TANGLE_REVIEW_TARGET="$RESULTS_DIR/input.diff"
    printf 'diff --git a/app.py b/app.py\n' > "$OCTOPUS_TANGLE_REVIEW_TARGET"
    for underlying_rc in 0 1 3 42; do
        review_run() {
            local id
            id=$(printf '%s' "$1" | jq -r .artifactId)
            printf '%s\n' '{"warning":"Partial reviewer fleet","findings":[{"file":"app.py","line":1,"severity":"normal","verdict":"confirmed"}]}' > "$RESULTS_DIR/review-findings-fixture-${id}.json"
            return "$underlying_rc"
        }
        rc=0
        tangle_run_context_code_review fixture context initial || rc=$?
        if [[ "$underlying_rc" -eq 0 ]]; then
            [[ "$rc" -eq 3 ]] || exit 1
            tangle_review_verification_complete "$TANGLE_REVIEW_FINDINGS_FILE" "$rc" || exit 1
        else
            if tangle_review_verification_complete "$TANGLE_REVIEW_FINDINGS_FILE" "$rc"; then exit 1; fi
        fi
    done
); then test_pass; else test_fail "saved findings hid a failed underlying review"; fi


test_case "unmatched findings can shed unrelated patch context before refusal"
if python3 - "$ROOT/scripts/helpers/review-verification-batches.py" <<'PYTEST'
import runpy, sys
build = runpy.run_path(sys.argv[1])["build_batches"]
diff = "diff --git a/other.py b/other.py\n--- a/other.py\n+++ b/other.py\n@@ -1 +1 @@\n-old\n+UNRELATED_OPERATION" + "x"*1200 + "\n"
finding = dict(file="app.py",line=1,title="missing patch")
rows, prompt = build(diff,[finding],"c"*4000,6000)[0]
assert rows == [finding] and len(prompt.encode()) <= 6000
assert "No matching patch block" in prompt and "UNRELATED_OPERATION" not in prompt
PYTEST
then test_pass; else test_fail "unrelated evidence prevented complete finding admission"; fi

test_case "verifier interruption removes primary and fallback inputs without changing caller traps"
if python3 - "$ROOT/scripts/lib/review.sh" "$TEST_TMP_DIR" <<'PYTEST'
import os, subprocess, sys, tempfile
from pathlib import Path
program = r'''
source "$REVIEW_LIB"
log() { :; }
review_verifier_input_budget() { echo 6000; }
inputs="$CASE_DIR/inputs"; mkdir -p "$inputs"
printf 'diff' > "$inputs/diff"; printf 'context' > "$inputs/context"
printf '[{"file":"a","line":1,"title":"bug"}]' > "$inputs/findings"
trap 'touch "$CASE_DIR/parent-exit"' EXIT
trap 'touch "$CASE_DIR/parent-term"' TERM
trap 'touch "$CASE_DIR/parent-int"' INT
before=$(trap -p EXIT INT TERM)
python3() {
    local previous='' argument dir='' verifier_dir=''
    for argument in "$@"; do
        if [[ "$previous" == --output ]]; then printf '%s' "$argument" > "$CASE_DIR/created"; fi
        previous="$argument"
    done
    local owner
    owner=$(exec sh -c 'echo "$PPID"')
    printf '%s' "$owner" > "$CASE_DIR/owner"
    if [[ "$INTERRUPT_POINT" == build ]]; then
        kill -s "$TEST_SIGNAL" "$owner"
        return 99
    fi
    command python3 "$@"
}
review_run_agent_sync_progress() {
    local dir='' verifier_dir=''
    kill -s "$TEST_SIGNAL" "$(cat "$CASE_DIR/owner")"
    return 99
}
rc=0
if [[ "$MODE" == fallback ]]; then
    review_verifier_fallback "$inputs" "$inputs/findings" claude-sonnet "$inputs/statuses" >/dev/null || rc=$?
else
    review_verify_findings diff "$(cat "$inputs/findings")" context "$inputs/statuses" >/dev/null || rc=$?
fi
[[ "$before" == "$(trap -p EXIT INT TERM)" ]] || exit 98
[[ ! -e "$CASE_DIR/parent-term" && ! -e "$CASE_DIR/parent-int" ]] || exit 97
exit "$rc"
'''
for mode, point in [('fallback', 'build'), ('primary', 'build'), ('fallback', 'dispatch'), ('primary', 'dispatch')]:
    for signal, expected in [('TERM', 143), ('INT', 130)]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            run = subprocess.run(['bash', '-c', program], env={**os.environ, 'REVIEW_LIB':sys.argv[1], 'CASE_DIR':directory, 'TMPDIR':directory, 'MODE':mode, 'TEST_SIGNAL':signal, 'INTERRUPT_POINT':point}, capture_output=True, text=True, timeout=10)
            assert run.returncode == expected, (mode, point, signal, run.returncode, run.stderr)
            assert (root/'created').is_file(), (mode, 'builder not reached')
            created = Path((root/'created').read_text())
            assert not created.exists(), (mode, signal, 'private inputs survived', str(created))
            assert (root/'parent-exit').exists(), (mode, 'caller EXIT trap lost')
            assert not (root/'parent-term').exists() and not (root/'parent-int').exists(), (mode, 'caller signal trap invoked')
PYTEST
then test_pass; else test_fail "interrupted verification leaked inputs or replaced caller traps"; fi

test_case "failed empty verifier admission retains its incomplete status"
if (
    source "$ROOT/scripts/lib/review.sh"
    log() { :; }
    review_verifier_input_budget() { return 1; }
    result=$(review_verify_findings diff '[]' context "$TEST_TMP_DIR/statuses") || exit 1
    printf '%s' "$result" | jq -e '.verification_status == "incomplete" and .findings == []' >/dev/null
); then test_pass; else test_fail "empty findings hid failed verifier admission"; fi

test_case "failed fallback verification cannot complete an empty or populated review"
if (
    source "$ROOT/scripts/lib/review.sh"
    log() { :; }
    mkdir -p "$TEST_TMP_DIR"
    unset OCTOPUS_REVIEW_SINGLE_PROVIDER OCTOPUS_REVIEW_VERIFIER_AGENT
    review_verifier_input_budget() { echo 6000; }
    review_run_agent_sync_progress() {
        printf '%s\n' "$1" >> "$TEST_TMP_DIR/failed-fallback-calls"
        if [[ "$failure" == malformed && "$1" == claude-sonnet ]]; then
            printf '%s\n' '{"findings":"invalid"}'
        else
            return 75
        fi
    }
    for failure in transport malformed; do
        for originals in '[]' '[{"file":"app.py","line":1,"title":"bug"}]'; do
            : > "$TEST_TMP_DIR/failed-fallback-calls"
            result=$(review_verify_findings diff "$originals" context "$TEST_TMP_DIR/fallback-statuses") || exit 1
            [[ "$(cat "$TEST_TMP_DIR/failed-fallback-calls")" == $'codex\nclaude-sonnet' ]] || exit 1
            printf '%s' "$result" | jq -e --argjson originals "$originals" '
                .verification_status == "incomplete" and
                .findings == ($originals | map(. + {verdict:"unverified"}))
            ' >/dev/null || exit 1
        done
    done
); then test_pass; else test_fail "fallback failure was accepted as complete verification"; fi

test_summary
