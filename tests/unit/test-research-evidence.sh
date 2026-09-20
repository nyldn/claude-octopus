#!/usr/bin/env bash
# Focused regression tests for durable, evidence-backed research runs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/research-evidence.sh"

test_suite "research evidence pipeline"

tmp_root="$TEST_TMP_DIR/research-evidence"
mkdir -p "$tmp_root"
RESULTS_DIR="$tmp_root/results"
mkdir -p "$RESULTS_DIR"

probe_result_file_is_usable() { return 0; }
research_resolve_ipv4() {
    case "$1" in
        127.0.0.1|localhost) printf '127.0.0.1\n' ;;
        *) printf '%s\n' "${MOCK_RESOLVED_IP:-93.184.216.34}" ;;
    esac
}

test_case "research CLI options normalize legacy breadth and resume state"
OCTOPUS_RESEARCH_INTENSITY=standard
OCTOPUS_RESEARCH_RUN_ID=""
OCTOPUS_RESEARCH_RESUME=false
research_parse_global_option --intensity=quick
equals_shift="$RESEARCH_OPTION_SHIFT"
research_parse_global_option --breadth exhaustive
breadth_shift="$RESEARCH_OPTION_SHIFT"
research_parse_global_option --resume-research saved-run
resume_shift="$RESEARCH_OPTION_SHIFT"
missing_status=0
research_parse_global_option --research-run || missing_status=$?
if [[ "$OCTOPUS_RESEARCH_INTENSITY" == "deep" ]] \
   && [[ "$OCTOPUS_RESEARCH_RUN_ID" == "saved-run" ]] \
   && [[ "$OCTOPUS_RESEARCH_RESUME" == "true" ]] \
   && [[ "$equals_shift" -eq 1 && "$breadth_shift" -eq 2 && "$resume_shift" -eq 2 ]] \
   && [[ "$missing_status" -eq 2 ]]; then
    test_pass
else
    test_fail "research option parser did not preserve its CLI contract"
fi

test_case "manifest and append-only events survive resume"
OCTOPUS_RESEARCH_RUN_ID="run-1"
OCTOPUS_RESEARCH_RESUME=false
research_run_begin "1700000000" $'quoted "prompt"\nsecond line' "quick"
research_run_update "providers_complete" "running" "usable=2"
run_dir="$RESEARCH_RUN_DIR"
before_events=$(wc -l < "$run_dir/events.jsonl" | tr -d ' ')
unset RESEARCH_RUN_DIR RESEARCH_RUN_ID RESEARCH_TASK_GROUP RESEARCH_PROMPT RESEARCH_INTENSITY
OCTOPUS_RESEARCH_RESUME=true
research_run_begin "ignored" "ignored" "standard"
after_events=$(wc -l < "$run_dir/events.jsonl" | tr -d ' ')
if [[ "$RESEARCH_PROMPT" == $'quoted "prompt"\nsecond line' ]] \
   && [[ "$RESEARCH_TASK_GROUP" == "1700000000" ]] \
   && [[ "$after_events" -eq $((before_events + 1)) ]] \
   && jq -e '.schema_version == 1 and .stage == "providers_complete"' "$run_dir/manifest.json" >/dev/null; then
    test_pass
else
    test_fail "resume did not preserve prompt, task group, manifest state, and event history"
fi

test_case "manifest JSON escapes control bytes without changing caller umask"
saved_umask=$(umask)
umask 0022
expected_umask=$(umask)
OCTOPUS_RESEARCH_RUN_ID="control-json"
OCTOPUS_RESEARCH_RESUME=false
research_run_begin "1700000004" $'control\001byte' "quick"
actual_umask=$(umask)
manifest_mode=""
if manifest_mode=$(stat -c '%a' "$RESEARCH_RUN_DIR/manifest.json" 2>/dev/null) \
   && [[ "$manifest_mode" =~ ^[0-7]{3,4}$ ]]; then
    : # GNU stat
else
    manifest_mode=$(stat -f '%Lp' "$RESEARCH_RUN_DIR/manifest.json" 2>/dev/null)
fi
umask "$saved_umask"
if [[ "$actual_umask" == "$expected_umask" && "$manifest_mode" == "600" ]] \
   && jq -e '.prompt == "control\u0001byte"' "$RESEARCH_RUN_DIR/manifest.json" >/dev/null; then
    test_pass
else
    test_fail "manifest serialization leaked umask state or emitted invalid JSON"
fi

test_case "stale lock recovery cannot remove a successor's lock"
lock_path="$tmp_root/ownership.lock"
lock_token=$(research_lock_acquire "$lock_path")
mv "$lock_path" "$lock_path.previous"
mkdir "$lock_path"
printf '%s\n' "replacement-owner" > "$lock_path/owner"
research_lock_release "$lock_path" "$lock_token"
successor_owner=""
IFS= read -r successor_owner < "$lock_path/owner"
rm -f "$lock_path/owner" "$lock_path.previous/owner"
rmdir "$lock_path" "$lock_path.previous"

stale_lock="$tmp_root/stale.lock"
mkdir "$stale_lock"
printf '%s\n' "abandoned-owner" > "$stale_lock/owner"
touch -t 200001010000 "$stale_lock"
recovered_token=$(research_lock_acquire "$stale_lock")
recovered_owner=""
IFS= read -r recovered_owner < "$stale_lock/owner"
research_lock_release "$stale_lock" "$recovered_token"
if [[ "$successor_owner" == "replacement-owner" ]] \
   && [[ "$recovered_owner" == "$recovered_token" ]] \
   && [[ ! -e "$stale_lock" ]]; then
    test_pass
else
    test_fail "lock recovery deleted a successor or failed to reclaim a stale lock"
fi

test_case "probe-single state is stable across session result directories"
WORKSPACE_DIR="$tmp_root/stable-workspace"
RESULTS_DIR="$tmp_root/session-results"
mkdir -p "$RESULTS_DIR"
OCTOPUS_RESEARCH_RUN_ID="flow-1700000002-0123456789abcdef0123456789abcdef"
OCTOPUS_RESEARCH_RESUME=false
OCTOPUS_RESEARCH_EVIDENCE=true OCTOPUS_RESEARCH_INTENSITY=standard
research_probe_single_begin "probe-1700000002-0123456789abcdef0123456789abcdef-0" "persistent topic"
stable_dir="$RESEARCH_RUN_DIR"
research_probe_single_record "probe-1700000002-0123456789abcdef0123456789abcdef-0" "codex" "completed"
if [[ "$stable_dir" == "$WORKSPACE_DIR/research-runs/$OCTOPUS_RESEARCH_RUN_ID" ]] \
   && jq -e '.task_group == "1700000002-0123456789abcdef0123456789abcdef"' "$stable_dir/manifest.json" >/dev/null \
   && jq -e --arg path "$RESULTS_DIR" '.provider_results_dir == $path' "$stable_dir/manifest.json" >/dev/null \
   && grep -q 'provider.completed' "$stable_dir/events.jsonl"; then
    test_pass
else
    test_fail "probe-single did not persist state independently of session result paths"
fi
unset RESEARCH_RUN_DIR RESEARCH_RUN_ID RESEARCH_TASK_GROUP RESEARCH_PROMPT RESEARCH_INTENSITY RESEARCH_PROVIDER_RESULTS_DIR

test_case "standalone synthesis preparation does not manufacture a durable run"
WORKSPACE_DIR="$tmp_root/standalone-workspace"
RESULTS_DIR="$tmp_root/standalone-results"
mkdir -p "$RESULTS_DIR"
unset RESEARCH_RUN_DIR RESEARCH_RUN_ID RESEARCH_TASK_GROUP RESEARCH_PROMPT RESEARCH_INTENSITY RESEARCH_PROVIDER_RESULTS_DIR
OCTOPUS_RESEARCH_RUN_ID=""
OCTOPUS_RESEARCH_RESUME=false
research_synthesis_prepare "1700000005" "legacy recovery"
if [[ -z "${RESEARCH_RUN_DIR:-}" ]] \
   && [[ ! -e "$WORKSPACE_DIR/research-runs/1700000005/manifest.json" ]]; then
    test_pass
else
    test_fail "standalone recovery unexpectedly created a fail-closed durable run"
fi

test_case "parallel probe children share one run manifest"
parallel_workspace="$tmp_root/parallel-workspace"
parallel_results="$tmp_root/parallel-results"
mkdir -p "$parallel_workspace" "$parallel_results"
parallel_status=0
for parallel_index in 0 1 2; do
    (
        source "$PROJECT_ROOT/scripts/lib/research-evidence.sh"
        WORKSPACE_DIR="$parallel_workspace" RESULTS_DIR="$parallel_results"
        OCTOPUS_RESEARCH_EVIDENCE=true OCTOPUS_RESEARCH_INTENSITY=standard
        research_probe_single_begin "probe-1700000003-$parallel_index" "parallel topic"
        research_probe_single_record "probe-1700000003-$parallel_index" "codex" "completed"
    ) &
done
for parallel_pid in $(jobs -p); do
    wait "$parallel_pid" || parallel_status=1
done
parallel_run="$parallel_workspace/research-runs/flow-1700000003"
parallel_events=$(wc -l < "$parallel_run/events.jsonl" | tr -d ' ')
if [[ "$parallel_status" -eq 0 ]] \
   && [[ -r "$parallel_run/manifest.json" ]] \
   && [[ "$parallel_events" -ge 4 ]]; then
    test_pass
else
    test_fail "parallel probe children did not converge on one durable run"
fi

test_case "source collection deduplicates URLs and records independence"
OCTOPUS_RESEARCH_RUN_ID="run-2" OCTOPUS_RESEARCH_RESUME=false OCTOPUS_RESEARCH_FETCH_MAX=0
research_run_begin "1700000001" "topic" "standard"
cat > "$RESULTS_DIR/codex-probe-1700000001-0.md" <<'EOF'
## Output
See https://example.com/report and https://example.com/report plus https://news.example.net/story.
## Status: SUCCESS
EOF
research_collect_sources "1700000001"
source_count=$(wc -l < "$RESEARCH_RUN_DIR/sources.jsonl" | tr -d ' ')
if [[ "$source_count" -eq 2 ]] \
   && grep -q '"independence_key":"host:example.com"' "$RESEARCH_RUN_DIR/sources.jsonl" \
   && grep -q '"source_id":"S002"' "$RESEARCH_RUN_DIR/sources.jsonl"; then
    test_pass
else
    test_fail "source ledger did not deduplicate and group sources as expected"
fi

test_case "snapshot verification accepts cited numbers that are present"
mkdir -p "$RESEARCH_RUN_DIR/snapshots"
printf '%s\n' '<p>Adoption reached 42% across 1,200 teams.</p>' > "$RESEARCH_RUN_DIR/snapshots/S001.body"
draft="$RESEARCH_RUN_DIR/number-pass.md"
printf '%s\n' 'Adoption reached 42% across 1,200 teams [source:S001].' > "$draft"
number_verify_status=0
research_verify_synthesis "$draft" || number_verify_status=$?
rm -f "$RESEARCH_RUN_DIR/snapshots/S001.body"
if [[ "$number_verify_status" -eq 0 ]] \
   && jq -e '.status == "passed" and .warnings == 0 and .failures == 0' \
        "$RESEARCH_RUN_DIR/verification.json" >/dev/null; then
    test_pass
else
    test_fail "a number present in the cited snapshot was rejected"
fi

test_case "snapshot verification decodes ampersand entities in cited quotes"
mkdir -p "$RESEARCH_RUN_DIR/snapshots"
printf '%s\n' '<p>Foo &amp; Bar</p>' > "$RESEARCH_RUN_DIR/snapshots/S001.body"
draft="$RESEARCH_RUN_DIR/quote-pass.md"
printf '%s\n' 'The report says "Foo & Bar" [source:S001].' > "$draft"
quote_verify_status=0
research_verify_synthesis "$draft" || quote_verify_status=$?
rm -f "$RESEARCH_RUN_DIR/snapshots/S001.body"
if [[ "$quote_verify_status" -eq 0 ]] \
   && jq -e '.status == "passed" and .failures == 0' \
        "$RESEARCH_RUN_DIR/verification.json" >/dev/null; then
    test_pass
else
    test_fail "a rendered ampersand in a cited quote was rejected"
fi

test_case "research evidence library has no quiet grep checks"
quiet_grep_sites=$(grep -nE 'grep[[:space:]]+-[^[:space:]]*q' \
    "$PROJECT_ROOT/scripts/lib/research-evidence.sh" || true)
if [[ -z "$quiet_grep_sites" ]]; then
    test_pass
else
    test_fail "quiet grep can fail early under inherited pipefail: $quiet_grep_sites"
fi

test_case "flow discovery keeps one run ID and stops when verification fails"
skill_gate_status=0
for skill_file in \
    "$PROJECT_ROOT/.claude/skills/flow-discover/SKILL.md" \
    "$PROJECT_ROOT/.claude/skills/flow-discover/flow-discover.tmpl" \
    "$PROJECT_ROOT/skills/flow-discover/SKILL.md"; do
    skill_content=$(<"$skill_file")
    skill_gate_block=$(sed -n '/Before presenting the synthesis/,/If verification reports/p' "$skill_file")
    if [[ "$skill_content" != *'RUN_TIMESTAMP="$(date +%s)"'* \
       || "$skill_content" != *'RUN_NONCE="$(od -An -N16 -tx1 /dev/urandom | tr -d '\''[:space:]'\'')"'* \
       || "$skill_content" != *'RUN_ID="flow-${RUN_TIMESTAMP}-${RUN_NONCE}"'* \
       || "$skill_content" != *'probe-${RUN_TIMESTAMP}-${RUN_NONCE}-<index>'* \
       || "$skill_content" != *"--research-run '<run_id>'"* \
       || "$skill_content" == *"RUN_ID='<run_id>'"* \
       || "$skill_content" != *'probe-synthesis-${RUN_ID}.md'* \
       || "$skill_gate_block" != *'"$RUN_ID" "$SYNTHESIS_FILE"'* \
       || "$skill_gate_block" != *'if ! '* \
       || "$skill_gate_block" != *'exit 1'* ]]; then
        skill_gate_status=1
    fi
done
if [[ "$skill_gate_status" -eq 0 ]]; then
    test_pass
else
    test_fail "flow discovery does not preserve one executable run ID through verification"
fi

test_case "generated synthesis footer is explicitly non-evidentiary"
heuristics_content=$(<"$PROJECT_ROOT/scripts/lib/heuristics.sh")
if [[ "$heuristics_content" == *'*Synthesized from $result_count research threads (task group: $task_group)* [inference]'* ]]; then
    test_pass
else
    test_fail "generated synthesis footer can be rejected as an uncited numeric claim"
fi

test_case "fenced examples are excluded from claim verification"
draft="$RESEARCH_RUN_DIR/fenced-example.md"
cat > "$draft" <<'EOF'
# Example
```text
Uncited example output includes 64 files and "sample text".
```
The example above is illustrative. [inference]
EOF
if research_verify_synthesis "$draft" \
   && jq -e '.status == "passed" and .failures == 0' \
        "$RESEARCH_RUN_DIR/verification.json" >/dev/null; then
    test_pass
else
    test_fail "non-claim fenced content was treated as a factual claim"
fi

test_case "valid citations pass while unfetched numbers remain explicit warnings"
draft="$RESEARCH_RUN_DIR/pass.md"
printf '%s\n' '# Draft' '- Adoption reached 42% [source:S001].' > "$draft"
if research_verify_synthesis "$draft" \
   && jq -e '.status == "passed" and .warnings == 1 and .failures == 0' "$RESEARCH_RUN_DIR/verification.json" >/dev/null \
   && jq -e '.source_ids == ["S001"]' "$RESEARCH_RUN_DIR/claims.jsonl" >/dev/null; then
    test_pass
else
    test_fail "valid source IDs should pass with an explicit no-snapshot warning"
fi

test_case "duplicate sources cannot manufacture consensus"
cp "$RESEARCH_RUN_DIR/sources.jsonl" "$RESEARCH_RUN_DIR/sources.saved"
cat > "$RESEARCH_RUN_DIR/sources.jsonl" <<'EOF'
{"source_id":"S001","url":"https://a.example/report","canonical_url":"https://a.example/report","publisher":"a.example","provider_artifact":"one.md","retrieved_at":"now","fetch_status":"not_fetched","reason":"budget","content_sha256":"same","independence_key":"content:same"}
{"source_id":"S002","url":"https://b.example/report","canonical_url":"https://b.example/report","publisher":"b.example","provider_artifact":"two.md","retrieved_at":"now","fetch_status":"not_fetched","reason":"budget","content_sha256":"same","independence_key":"content:same"}
EOF
printf '%s\n' 'Multiple independent sources agree [source:S001] [source:S002].' > "$draft"
verify_status=0
research_verify_synthesis "$draft" || verify_status=$?
if [[ "$verify_status" -ne 0 ]] && jq -e '.status == "failed" and (.checks[] | select(.kind == "false_consensus"))' "$RESEARCH_RUN_DIR/verification.json" >/dev/null; then
    test_pass
else
    test_fail "same-content sources were incorrectly counted as independent consensus"
fi

test_case "quote and number verification rejects snapshot mismatches"
mkdir -p "$RESEARCH_RUN_DIR/snapshots"
printf '%s\n' '<p>Adoption reached 41 percent. The measured result was stable.</p>' > "$RESEARCH_RUN_DIR/snapshots/S001.body"
printf '%s\n' 'Adoption reached 42% and was "dramatically higher" [source:S001].' > "$draft"
verify_status=0
research_verify_synthesis "$draft" || verify_status=$?
if [[ "$verify_status" -ne 0 ]] \
   && jq -e '[.checks[].kind] | index("number_mismatch") and index("quote_mismatch")' "$RESEARCH_RUN_DIR/verification.json" >/dev/null; then
    test_pass
else
    test_fail "snapshot mismatches were not rejected"
fi
mv "$RESEARCH_RUN_DIR/sources.saved" "$RESEARCH_RUN_DIR/sources.jsonl"

test_case "fetch boundary rejects HTTP, private targets, and non-443 ports"
leading_zero_status=0
/bin/bash -c 'source "$1"; research_resolve_ipv4 "$2" >/dev/null' \
    _ "$PROJECT_ROOT/scripts/lib/research-evidence.sh" "0177.0.0.1" || leading_zero_status=$?
MOCK_RESOLVED_IP="127.0.0.1"
private_status=0; research_validate_fetch_target "https://example.com/private" || private_status=$?
MOCK_RESOLVED_IP="93.184.216.34"
http_status=0; research_validate_fetch_target "http://example.com" || http_status=$?
port_status=0; research_validate_fetch_target "https://example.com:8443/path" || port_status=$?
if [[ "$private_status" -ne 0 && "$leading_zero_status" -ne 0 ]] \
   && [[ "$http_status" -ne 0 && "$port_status" -ne 0 ]] \
   && research_validate_fetch_target "https://example.com/path"; then
    test_pass
else
    test_fail "URL policy did not fail closed"
fi

test_case "fetch boundary enforces response-size cap without following curl redirects"
mock_bin="$tmp_root/mock-bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/curl" <<'EOF'
#!/usr/bin/env bash
out="" headers=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) out="$2"; shift 2 ;;
    --dump-header) headers="$2"; shift 2 ;;
    --write-out|--proto|--proto-redir|--max-redirs|--connect-timeout|--max-time|--max-filesize|--noproxy|--resolve|--request) shift 2 ;;
    --silent|--show-error) shift ;;
    *) shift ;;
  esac
done
: > "$headers"
printf 'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n' > "$headers"
if [[ "$out" == "-" ]]; then
  printf '0123456789ABCDEF'
else
  printf '0123456789ABCDEF' > "$out"
fi
EOF
chmod +x "$mock_bin/curl"
fetch_status=0
PATH="$mock_bin:$PATH" research_fetch_url "https://example.com/data" "$tmp_root/body" 8 || fetch_status=$?
if [[ "$fetch_status" -eq 63 && ! -e "$tmp_root/body" ]]; then
    test_pass
else
    test_fail "oversized response was not removed and rejected"
fi

test_case "redirects are revalidated before fetching"
cat > "$mock_bin/curl" <<'EOF'
#!/usr/bin/env bash
out="" headers=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) out="$2"; shift 2 ;;
    --dump-header) headers="$2"; shift 2 ;;
    --write-out|--proto|--proto-redir|--max-redirs|--connect-timeout|--max-time|--max-filesize|--noproxy|--resolve|--request) shift 2 ;;
    --silent|--show-error) shift ;;
    *) shift ;;
  esac
done
: > "$headers"
printf 'HTTP/1.1 302 Found\r\nLocation: https://127.0.0.1/private\r\n\r\n' > "$headers"
[[ "$out" == "-" ]] || : > "$out"
EOF
chmod +x "$mock_bin/curl"
redirect_status=0
PATH="$mock_bin:$PATH" research_fetch_url "https://example.com/start" "$tmp_root/redirect-body" 64 || redirect_status=$?
if [[ "$redirect_status" -ne 0 && ! -e "$tmp_root/redirect-body" ]]; then
    test_pass
else
    test_fail "redirect target was fetched without a fresh network-boundary check"
fi

test_case "verification publishes to the nonce-bearing run path"
WORKSPACE_DIR="$tmp_root/verify-workspace"
RESULTS_DIR="$tmp_root/verify-results"
mkdir -p "$RESULTS_DIR"
verify_run_id="flow-1700000006-fedcba9876543210fedcba9876543210"
OCTOPUS_RESEARCH_RUN_ID="$verify_run_id"
OCTOPUS_RESEARCH_RESUME=false
OCTOPUS_RESEARCH_FETCH_MAX=0
research_run_begin "1700000006" "verification topic" "quick"
verify_draft="$tmp_root/verification-draft.md"
printf '%s\n' '# Verified synthesis' 'No external claims.' > "$verify_draft"
verify_output=$(research_verify_run "$verify_run_id" "$verify_draft")
if [[ "$verify_output" == "$RESULTS_DIR/probe-synthesis-${verify_run_id}.md" ]] \
   && [[ -r "$verify_output" ]]; then
    test_pass
else
    test_fail "verification published outside the unique run path: $verify_output"
fi

test_summary
