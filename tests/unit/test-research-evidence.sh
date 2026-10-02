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

test_case "invalid research intensity is rejected before command dispatch"
OCTOPUS_RESEARCH_INTENSITY=standard
invalid_equals_status=0
research_parse_global_option --intensity=turbo || invalid_equals_status=$?
invalid_separate_status=0
research_parse_global_option --breadth --dry-run || invalid_separate_status=$?
late_error="$tmp_root/invalid-intensity.log"
late_status=0
"$PROJECT_ROOT/scripts/orchestrate.sh" probe "fixture" --intensity --dry-run \
    >"$late_error" 2>&1 || late_status=$?
if [[ "$invalid_equals_status" -eq 2 ]] \
   && [[ "$invalid_separate_status" -eq 2 ]] \
   && [[ "$late_status" -eq 2 ]] \
   && [[ "$OCTOPUS_RESEARCH_INTENSITY" == "standard" ]] \
   && grep -q 'Invalid or missing value for --intensity' "$late_error"; then
    test_pass
else
    test_fail "invalid research intensity reached dispatch or changed parser state"
fi

test_case "disabling research evidence skips durable run initialization"
evidence_disabled_result=$(
    (
        # shellcheck source=/dev/null
        source "$PROJECT_ROOT/scripts/lib/workflows.sh"
        log() { :; }
        octopus_phase_banner() { :; }
        preflight_check() { return 0; }
        display_workflow_cost_estimate() { return 1; }
        research_run_begin() {
            durable_begin_called=true
            RESEARCH_TASK_GROUP="$1"
            RESEARCH_PROMPT="$2"
            RESEARCH_INTENSITY="$3"
        }
        research_run_update() { :; }
        durable_begin_called=false
        OCTOPUS_RESEARCH_EVIDENCE=false
        OCTOPUS_RESEARCH_RESUME=false
        DRY_RUN=false
        MAGENTA=""
        probe_status=0
        probe_discover "fixture" >/dev/null 2>&1 || probe_status=$?
        printf '%s:%s\n' "$durable_begin_called" "$probe_status"
    )
)
if [[ "$evidence_disabled_result" == "false:1" ]]; then
    test_pass
else
    test_fail "evidence opt-out still initialized a durable research run"
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

test_case "in-cap response is accepted when wc pads its byte count (BSD/macOS)"
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
printf 'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n' > "$headers"
if [[ "$out" == "-" ]]; then
  printf '0123456789ABCDEF'
else
  printf '0123456789ABCDEF' > "$out"
fi
EOF
cat > "$mock_bin/wc" <<'EOF'
#!/usr/bin/env bash
count=$(/usr/bin/env -i PATH=/usr/bin:/bin wc "$@" | tr -d '[:space:]')
printf '%8s\n' "$count"
EOF
chmod +x "$mock_bin/curl" "$mock_bin/wc"
padded_status=0
PATH="$mock_bin:$PATH" research_fetch_url "https://example.com/ok" "$tmp_root/padded-body" 64 || padded_status=$?
rm -f "$mock_bin/wc"
if [[ "$padded_status" -eq 0 && "$(cat "$tmp_root/padded-body" 2>/dev/null)" == "0123456789ABCDEF" ]]; then
    test_pass
else
    test_fail "in-cap response rejected with status $padded_status when wc output is space-padded"
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

test_case "source extraction drops JSON-escaped whitespace from URLs"
WORKSPACE_DIR="$tmp_root/escaped-workspace"
RESULTS_DIR="$tmp_root/escaped-results"
mkdir -p "$RESULTS_DIR"
unset RESEARCH_RUN_DIR RESEARCH_RUN_ID RESEARCH_TASK_GROUP RESEARCH_PROMPT RESEARCH_INTENSITY RESEARCH_PROVIDER_RESULTS_DIR
OCTOPUS_RESEARCH_RUN_ID="escaped-urls"
OCTOPUS_RESEARCH_RESUME=false
OCTOPUS_RESEARCH_FETCH_MAX=0
research_run_begin "1700000007" "escaped URL topic" "standard"
cat > "$RESULTS_DIR/codex-probe-1700000007-0.md" <<'EOF'
## Output
{"message":"alert\nRunbook: https://example.com/runbook.md#error-tracking\n","next":"https://example.org/page\tTabbed"}
{"escaped":"https://example.net/doc\\nNext","quoted":"https://example.net/quoted\""}
Runbook: https://example.com/runbook.md#error-tracking
## Status: SUCCESS
EOF
research_collect_sources "1700000007"
escaped_urls=$(jq -r '.url, .canonical_url' "$RESEARCH_RUN_DIR/sources.jsonl")
escaped_canonical=$(jq -r '.canonical_url' "$RESEARCH_RUN_DIR/sources.jsonl" | sort | tr '\n' ' ')
if [[ "$escaped_urls" != *'\'* ]] \
   && [[ "$escaped_canonical" == "https://example.com/runbook.md https://example.net/doc https://example.net/quoted https://example.org/page " ]]; then
    test_pass
else
    test_fail "escaped whitespace leaked into extracted URLs: $(tr '\n' ' ' <<< "$escaped_urls")"
fi

test_case "workspace file:line citations verify as local evidence"
local_root="$tmp_root/local-project"
elsewhere_root="$tmp_root/elsewhere-project"
mkdir -p "$local_root/src" "$elsewhere_root/src"
printf '%s\n' \
    'import { log } from "./log.js";' \
    'export function handle(err) {' \
    '  log.error("unhandled error", { err });' \
    '  return { status: 500 };' \
    '}' > "$local_root/src/handler.ts"
WORKSPACE_DIR="$tmp_root/local-workspace"
RESULTS_DIR="$tmp_root/local-results"
mkdir -p "$RESULTS_DIR"
unset RESEARCH_RUN_DIR RESEARCH_RUN_ID RESEARCH_TASK_GROUP RESEARCH_PROMPT RESEARCH_INTENSITY RESEARCH_PROVIDER_RESULTS_DIR RESEARCH_PROJECT_ROOT
OCTOPUS_RESEARCH_RUN_ID="local-citations"
OCTOPUS_RESEARCH_RESUME=false
OCTOPUS_RESEARCH_FETCH_MAX=0
PROJECT_ROOT="$local_root" research_run_begin "1700000008" "Audit the handler" "standard"
unset RESEARCH_RUN_DIR RESEARCH_RUN_ID RESEARCH_TASK_GROUP RESEARCH_PROMPT RESEARCH_INTENSITY RESEARCH_PROVIDER_RESULTS_DIR RESEARCH_PROJECT_ROOT
OCTOPUS_RESEARCH_RESUME=true
PROJECT_ROOT="$elsewhere_root" research_run_begin "1700000008" "" "standard"
OCTOPUS_RESEARCH_RESUME=false
local_draft="$RESEARCH_RUN_DIR/local-pass.md"
{
    printf '%s\n' '# Findings'
    printf '%s\n' '- Unexpected errors return 500 (`src/handler.ts:4`).'
    printf '%s\n' '- The handler logs "unhandled error" with the error attached (src/handler.ts:2-4).'
    printf -- '- The same handler, cited by absolute path, returns 500 (`%s/src/handler.ts:4`).\n' "$local_root"
} > "$local_draft"
local_status=0
(cd "$elsewhere_root" && research_verify_synthesis "$local_draft") || local_status=$?
if [[ "$local_status" -eq 0 ]] \
   && jq -e '.status == "passed" and .failures == 0 and .claims_checked == 3' \
        "$RESEARCH_RUN_DIR/verification.json" >/dev/null \
   && jq -se '.[0].local_citations == ["src/handler.ts:4"]
              and .[0].independence_groups == ["local:src/handler.ts"]
              and .[1].local_citations == ["src/handler.ts:2-4"]
              and .[2].local_citations == ["src/handler.ts:4"]' \
        "$RESEARCH_RUN_DIR/claims.jsonl" >/dev/null; then
    test_pass
else
    test_fail "resolvable workspace citations were rejected: $(jq -c '.checks' "$RESEARCH_RUN_DIR/verification.json" 2>/dev/null)"
fi

test_case "workspace citations fail closed outside the root, past EOF, or on mismatched numbers"
printf '%s\n' 'outside the workspace' > "$tmp_root/outside.ts"
ln -sf "../../outside.ts" "$local_root/src/escape.ts"
local_bad_draft="$RESEARCH_RUN_DIR/local-fail.md"
{
    printf '%s\n' '- Unexpected errors return 503 (`src/handler.ts:4`).'
    printf '%s\n' '- A line past the end of the file (`src/handler.ts:40`).'
    printf '%s\n' '- A relative path that leaves the workspace (`../outside.ts:1`).'
    printf '%s\n' '- A symlink that leaves the workspace (`src/escape.ts:1`).'
    printf '%s\n' '- A file that does not exist (`src/missing.ts:1`).'
    printf -- '- An absolute path outside the workspace (`%s/outside.ts:1`).\n' "$tmp_root"
    printf '%s\n' '- A basename that is not a workspace path (`handler.ts:4`).'
} > "$local_bad_draft"
local_bad_status=0
research_verify_synthesis "$local_bad_draft" || local_bad_status=$?
local_bad_kinds=$(jq -r '.checks[] | "\(.line):\(.kind)"' "$RESEARCH_RUN_DIR/verification.json" | tr '\n' ' ')
if [[ "$local_bad_status" -ne 0 ]] \
   && [[ "$local_bad_kinds" == "1:number_mismatch 2:unresolved_local_citation 3:unresolved_local_citation 4:unresolved_local_citation 5:unresolved_local_citation 6:unresolved_local_citation 7:unresolved_local_citation " ]]; then
    test_pass
else
    test_fail "unresolvable workspace citations were accepted: $local_bad_kinds"
fi

test_case "emphasized ordered-list markers are not checked as cited numbers"
marker_draft="$RESEARCH_RUN_DIR/local-markers.md"
{
    printf '%s\n' '**4. Unexpected errors return 500** (`src/handler.ts:4`).'
    printf '%s\n' '__2. Unexpected errors return 500__ (`src/handler.ts:4`).'
    printf '%s\n' '- **3.** Unexpected errors return 500 (`src/handler.ts:4`).'
    printf '%s\n' '- Unexpected errors return **503** (`src/handler.ts:4`).'
} > "$marker_draft"
marker_status=0
research_verify_synthesis "$marker_draft" || marker_status=$?
marker_kinds=$(jq -r '.checks[] | "\(.line):\(.kind):\(.detail)"' "$RESEARCH_RUN_DIR/verification.json" | tr '\n' ' ')
if [[ "$marker_status" -ne 0 && "$marker_kinds" == "4:number_mismatch:503 " ]]; then
    test_pass
else
    test_fail "emphasized list markers were checked as numbers, or an emphasized value escaped: $marker_kinds"
fi

test_case "an emphasized decimal remains a complete numeric claim"
printf 'Availability is 5%%.\n' > "$local_root/src/availability.txt"
printf '%s\n' '**503.5%** availability (`src/availability.txt:1`).' > "$marker_draft"
marker_status=0
research_verify_synthesis "$marker_draft" || marker_status=$?
if [[ "$marker_status" -ne 0 ]] \
   && jq -e '.checks | any(.kind == "number_mismatch" and .detail == "503.5%")' \
       "$RESEARCH_RUN_DIR/verification.json" >/dev/null; then
    test_pass
else
    test_fail "an emphasized decimal escaped evidence verification"
fi

test_case "workspace citations to files over the size cap fail closed"
big_line='  return { status: 500 };'
{ printf '%s\n' "$big_line"; head -c 400 /dev/zero | tr '\0' 'x'; printf '\n'; } > "$local_root/src/big.ts"
printf '%s\n' "$big_line" > "$local_root/src/small.ts"
cap_draft="$RESEARCH_RUN_DIR/local-cap.md"
{
    printf '%s\n' '- The oversized file returns 500 (`src/big.ts:1`).'
    printf '%s\n' '- The small file returns 500 (`src/small.ts:1`).'
} > "$cap_draft"
cap_status=0
OCTOPUS_RESEARCH_MAX_RESPONSE_BYTES=256 research_verify_synthesis "$cap_draft" || cap_status=$?
cap_kinds=$(jq -r '.checks[] | "\(.line):\(.kind)"' "$RESEARCH_RUN_DIR/verification.json" | tr '\n' ' ')
if [[ "$cap_status" -ne 0 ]] && [[ "$cap_kinds" == "1:unresolved_local_citation " ]]; then
    test_pass
else
    test_fail "size cap not enforced: status=$cap_status checks=[$cap_kinds]"
fi

test_case "each cited workspace file is normalized once per verification"
cache_draft="$RESEARCH_RUN_DIR/local-cache.md"
printf '%s\n' \
    '- The handler logs "unhandled error" and returns "status: 500" (`src/handler.ts:2-4`).' \
    '- The handler returns "status: 500" (`src/handler.ts:4`).' > "$cache_draft"
normalization_calls="$RESEARCH_RUN_DIR/normalization-calls"
: > "$normalization_calls"
cache_status=0
(
    original_normalizer=$(declare -f research_normalize_local_file)
    eval "${original_normalizer/research_normalize_local_file/research_normalize_local_file_original}"
    research_normalize_local_file() {
        printf 'called\n' >> "$normalization_calls"
        research_normalize_local_file_original "$1"
    }
    research_verify_synthesis "$cache_draft"
) || cache_status=$?
call_count=$(wc -l < "$normalization_calls" | tr -d '[:space:]')
if [[ "$cache_status" -eq 0 && "$call_count" -eq 1 ]]; then
    test_pass
else
    test_fail "workspace file normalized $call_count times; verification status=$cache_status"
fi

test_case "workspace cache budget fails verification and cleans normalized files"
printf 'alpha evidence %0170d\n' 0 > "$local_root/src/cache-a.ts"
printf 'beta evidence %0170d\n' 0 > "$local_root/src/cache-b.ts"
budget_draft="$RESEARCH_RUN_DIR/local-budget.md"
printf '%s\n' \
    '- The first file has "alpha evidence" (`src/cache-a.ts:1`).' \
    '- The second file has "beta evidence" (`src/cache-b.ts:1`).' > "$budget_draft"
budget_status=0
OCTOPUS_RESEARCH_MAX_LOCAL_CACHE_BYTES=256 research_verify_synthesis "$budget_draft" || budget_status=$?
budget_kind=$(jq -r '.checks[].kind' "$RESEARCH_RUN_DIR/verification.json")
if [[ "$budget_status" -ne 0 && "$budget_kind" == "local_cache_limit" ]] \
   && ! ls "$RESEARCH_RUN_DIR"/.normalized-local.* >/dev/null 2>&1; then
    test_pass
else
    test_fail "cache budget did not fail cleanly: status=$budget_status checks=[$budget_kind]"
fi

test_case "zero-padded cache budget is read as decimal"
padded_status=0
OCTOPUS_RESEARCH_MAX_LOCAL_CACHE_BYTES=000512 research_verify_synthesis "$budget_draft" || padded_status=$?
if [[ "$padded_status" -eq 0 ]] \
   && jq -e '.status == "passed"' "$RESEARCH_RUN_DIR/verification.json" >/dev/null; then
    test_pass
else
    test_fail "zero-padded 512-byte cache budget rejected two in-budget files"
fi

test_case "local response cap handles padded and overlong values without arithmetic errors"
cap_error="$RESEARCH_RUN_DIR/local-cap-error.log"
physical_local_root=$(cd "$local_root" && pwd -P)
local_cap_status=0
OCTOPUS_RESEARCH_MAX_RESPONSE_BYTES=999999999999999999999 \
    research_resolve_local_citation "$physical_local_root" 'src/small.ts:1' \
    >/dev/null 2> "$cap_error" || local_cap_status=$?
padded_local_status=0
OCTOPUS_RESEARCH_MAX_RESPONSE_BYTES=000256 \
    research_resolve_local_citation "$physical_local_root" 'src/small.ts:1' \
    >/dev/null 2>> "$cap_error" || padded_local_status=$?
if [[ "$local_cap_status" -eq 0 && "$padded_local_status" -eq 0 && ! -s "$cap_error" ]]; then
    test_pass
else
    test_fail "overlong response cap caused a local citation error"
fi

test_case "normalization failure removes earlier cache files"
normalization_status=0
(
    original_normalizer=$(declare -f research_normalize_local_file)
    eval "${original_normalizer/research_normalize_local_file/research_normalize_local_file_original}"
    research_normalize_local_file() {
        [[ "$1" == */cache-b.ts ]] && return 1
        research_normalize_local_file_original "$1"
    }
    research_verify_synthesis "$budget_draft"
) || normalization_status=$?
normalization_kind=$(jq -r '.checks[].kind' "$RESEARCH_RUN_DIR/verification.json")
if [[ "$normalization_status" -ne 0 && "$normalization_kind" == "local_cache_error" ]] \
   && ! ls "$RESEARCH_RUN_DIR"/.normalized-local.* >/dev/null 2>&1; then
    test_pass
else
    test_fail "normalization failure left cache files: status=$normalization_status checks=[$normalization_kind]"
fi

test_case "digits inside identifiers and git SHAs are not extracted as numbers"
identifier_numbers=""
while IFS= read -r identifier_line; do
    identifier_numbers="${identifier_numbers}$(research_extract_numbers "$identifier_line")"
done <<'EOF'
| **T-1 (ALR-R1, R2; DoD-1)** | | | |
- **The groundwork is on `main` at `89a941fda`.** That covers:
  - p50/p95 latency pages;
- Both `a6538e52e` pins contain `d34478150`; PLAT-1181, #1728 and DoD-2 track them.
- abc123-456-789 is an identifier.
- ALR-R4(c) and §4.2-4.3 cover the k8s c3po_fleet monitors in us-east-1 on claude-opus-5-5 (v11.9.6).
EOF
claim_numbers=$(research_extract_numbers \
    '1. Pages fire after 15m or 30s on 5xx, 5 s apart, on 10-13 routes, 20m-45m and 7s-9s windows, 42% and 3.5 per 1,024 at 2026-09-28 across 1234567 rows.' \
    | LC_ALL=C sort | tr '\n' ' ')
if [[ -z "$identifier_numbers" \
      && "$claim_numbers" == "09 1,024 10 1234567 13 15 20 2026 28 3.5 30 42% 45 5 7 9 " ]]; then
    test_pass
else
    test_fail "identifiers leaked [$identifier_numbers] or claims were lost [$claim_numbers]"
fi

test_case "identifier-only lines need no citation while numbers beside identifiers still do"
identifier_draft="$RESEARCH_RUN_DIR/local-identifiers.md"
{
    printf '%s\n' '| **T-1 (ALR-R1, R2; DoD-1)** | | | |'
    printf '%s\n' '- **The groundwork is on `main` at `89a941fda`.** That covers:'
    printf '%s\n' '  - p50/p95 latency pages;'
    printf '%s\n' '- PLAT-1181 tracks #1728 and DoD-2.'
    printf '%s\n' '- Commit `d34478150` makes unexpected errors return 500 (`src/handler.ts:4`).'
    printf '%s\n' '- T-5 pages after 15m on 5xx.'
    printf '%s\n' '- DoD-3 leaves 16 routes without a probe.'
    printf '%s\n' '- Commit `0e03ef56a` makes unexpected errors return 503 (`src/handler.ts:4`).'
    printf '%s\n' '- Unexpected errors return 500 after a 500ms-900ms backoff (`src/handler.ts:4`).'
} > "$identifier_draft"
identifier_status=0
research_verify_synthesis "$identifier_draft" || identifier_status=$?
identifier_kinds=$(jq -r '.checks[] | "\(.line):\(.kind):\(.detail)"' "$RESEARCH_RUN_DIR/verification.json" \
    | sed -E 's/^([0-9]+:missing_citation):.*/\1/' | tr '\n' ' ')
if [[ "$identifier_status" -ne 0 \
      && "$identifier_kinds" == "6:missing_citation 7:missing_citation 8:number_mismatch:503 9:number_mismatch:900 " ]]; then
    test_pass
else
    test_fail "identifier digits were checked as claims, or real numbers escaped: $identifier_kinds"
fi

test_case "an unresolved workspace citation is reported by name and its line numbers are not claims"
unresolved_draft="$RESEARCH_RUN_DIR/local-unresolved.md"
{
    printf '%s\n' '- Unexpected errors return 500 (`src/handler.ts:4`; `main.tf:144-155`).'
    printf '%s\n' '- Unexpected errors return 503 (`handler.ts:4`).'
    printf '%s\n' '- A 4.5:1 contrast ratio is served from https://example.com:8443 [inference].'
    printf '%s\n' '- The job API at https://example.com:443/api/jobs:42 answers slowly [inference].'
} > "$unresolved_draft"
unresolved_status=0
research_verify_synthesis "$unresolved_draft" || unresolved_status=$?
unresolved_kinds=$(jq -r '.checks[] | "\(.line):\(.kind):\(.detail)"' "$RESEARCH_RUN_DIR/verification.json" | tr '\n' ' ')
if [[ "$unresolved_status" -ne 0 \
      && "$unresolved_kinds" == "1:unresolved_local_citation:main.tf:144-155 2:unresolved_local_citation:handler.ts:4 " ]]; then
    test_pass
else
    test_fail "unresolved citations were misreported: $unresolved_kinds"
fi

test_case "an annotated [inference ...] marker exempts a claim the way [opinion ...] does"
annotated_draft="$RESEARCH_RUN_DIR/annotated-inference.md"
{
    printf '%s\n' '- There are 21 templates to edit [inference — counted by glob].'
    printf '%s\n' '- Regeneration rewrites 60 deployments [inference: counted by glob].'
    printf '%s\n' '- 17 monitor files would need the filter [inference].'
    printf '%s\n' '- The 9 pods restart on every rollout [inferences are cheap].'
    printf '%s\n' '- Regeneration touches 5 more files.'
} > "$annotated_draft"
annotated_status=0
research_verify_synthesis "$annotated_draft" || annotated_status=$?
annotated_kinds=$(jq -r '.checks[] | "\(.line):\(.kind)"' "$RESEARCH_RUN_DIR/verification.json" | tr '\n' ' ')
if [[ "$annotated_status" -ne 0 && "$annotated_kinds" == "4:missing_citation 5:missing_citation " ]]; then
    test_pass
else
    test_fail "annotated inference markers were not honoured, or unmarked numbers escaped: $annotated_kinds"
fi

# Check the actual verifier, including the marker's effect on missing citations.
marker_fixture="$tmp_root/marker-boundaries"
mkdir -p "$marker_fixture/project/src"
printf '%s\n' 'There are 21 templates. "verified source fragment"' > "$marker_fixture/project/src/counts.txt"
_marker_verification_case() {
    local name="$1" text="$2" expected_status="$3" expected_kind="${4:-}"
    local case_dir="$marker_fixture/$name" status=0 kinds
    mkdir -p "$case_dir/snapshots"
    : > "$case_dir/sources.jsonl"
    printf '%s\n' "$text" > "$case_dir/draft.md"
    test_case "inference marker boundary: $name"
    ( RESEARCH_RUN_DIR="$case_dir" RESEARCH_PROJECT_ROOT="$marker_fixture/project"
      research_verify_synthesis "$case_dir/draft.md" ) || status=$?
    kinds=$(jq -r '.checks[].kind' "$case_dir/verification.json" | sort -u | tr '\n' ' ')
    if [[ "$status" == "$expected_status" && "$kinds" == "$expected_kind" ]]; then test_pass
    else test_fail "status=$status checks=$kinds expected=$expected_status/$expected_kind"; fi
}
_marker_verification_case comma '- There are 21 templates [inference, counted by glob].' 0
_marker_verification_case colon '- There are 21 templates [inference: counted by glob].' 0
_marker_verification_case unicode '- There are 21 templates [inference — comptées par glob].' 0
_marker_verification_case unicode-possessive "José's 21 templates [inference: counted by glob]." 0
_marker_verification_case unicode-annotation-possessive "There are 21 templates [inference: José's count by glob]." 0
_marker_verification_case quoted-unicode-possessive "There are 901 templates containing 'José's [inference: counted by glob]' as a literal value." 1 'missing_citation '
_marker_verification_case quoted-ascii-possessive "There are 901 templates containing 'Jose's [inference: counted by glob]' as a literal value." 1 'missing_citation '
_marker_verification_case ascii-adjacent-quote "There are 901 templates in value'[inference: estimated]' as a literal value." 1 'missing_citation '
_marker_verification_case numeric-adjacent-quote "There are 901 templates in 7'[inference: estimated]' as a literal value." 1 'missing_citation '
_marker_verification_case possessive-then-marker "The value's 21 templates [inference: estimated]." 0
_marker_verification_case adjacent-quote-then-marker "There are 21 templates in value'[inference: literal]' [inference: estimated]." 0
_marker_verification_case unicode-adjacent-quote "There are 901 templates containing é'[inference: counted by glob]' as a literal value." 1 'missing_citation '
_marker_verification_case unicode-punctuation-quote "There are 901 templates containing —'count [inference: counted by glob]' as a literal value." 1 'missing_citation '
_marker_verification_case adjacent-punctuation '- There are 21 templates [inference,counted by glob].' 0
_marker_verification_case nonletter-delimiter '- There are 21 templates [inference2 passes of glob].' 0
_marker_verification_case prefix '[inference: counted by glob] There are 21 templates.' 0
_marker_verification_case middle '- There are [inference: counted by glob] 21 templates.' 0
_marker_verification_case quoted-annotation '- There are 21 templates [inference: counted "template" entries].' 0
_marker_verification_case bare '- There are 21 templates [inference].' 0
_marker_verification_case legacy-bare-literal '- There are 21 templates containing "[inference]" as a literal value.' 0
_marker_verification_case unclosed '- There are 901 templates [inference' 1 'missing_citation '
_marker_verification_case unclosed-annotation '- There are 901 templates [inference, counted by glob.' 1 'missing_citation '
_marker_verification_case nested '- There are 901 templates [inference: unfinished [other note].' 1 'missing_citation '
_marker_verification_case nested-label '- There are 901 templates [label: [inference: counted by glob]].' 1 'missing_citation '
_marker_verification_case quote-is-not-a-close '- There are 901 templates [inference: the string "]" is not a close.' 1 'missing_citation '
_marker_verification_case double-quoted '- There are 901 templates containing "[inference: counted by glob]" as a literal value.' 1 'missing_citation '
_marker_verification_case single-quoted "- There are 901 templates containing '[inference: counted by glob]' as a literal value." 1 'missing_citation '
_marker_verification_case inline-code '- There are 901 templates containing `[inference: counted by glob]` as a literal value.' 1 'missing_citation '
_marker_verification_case double-tick-code '- There are 901 templates containing ``[inference: counted by glob]`` as a literal value.' 1 'missing_citation '
_marker_verification_case escaped '- There are 901 templates containing \[inference: counted by glob] as a literal value.' 1 'missing_citation '
_marker_verification_case unclosed-literal '- There are 901 templates containing "[inference: counted by glob] as a literal value.' 1 'missing_citation '
_marker_verification_case quoted-then-marker '- There are 21 templates containing "[inference: an example]" [inference, counted by glob].' 0
_marker_verification_case lookalike '- There are 901 templates [inferences are cheap].' 1 'missing_citation '
_marker_verification_case unmarked '- There are 901 templates.' 1 'missing_citation '
_marker_verification_case next-line $'[inference: counted by glob]\n- There are 901 templates.' 1 'missing_citation '
_marker_verification_case split-marker $'- There are 901 templates [inference:\ncounted by glob].' 1 'missing_citation '
_marker_verification_case citation-number '- There are 901 templates (`src/counts.txt:1`) [inference, counted by glob].' 1 'number_mismatch '
_marker_verification_case citation-quote '- The phrase "invented source fragment" appears (`src/counts.txt:1`) [inference, counted by glob].' 1 'quote_mismatch '
_marker_verification_case unresolved-local '- There are 21 templates (`src/missing.txt:1`) [inference, counted by glob].' 1 'unresolved_local_citation '
_marker_verification_case false-consensus '- Multiple independent sources confirm 21 templates (`src/counts.txt:1`) [inference, counted by glob].' 1 'false_consensus '

# Compare the existing unknown-source diagnostic without changing its status gate.
test_case "annotation does not suppress an unknown-source diagnostic"
unknown_case="$marker_fixture/unknown-source"
mkdir -p "$unknown_case/snapshots"
: > "$unknown_case/sources.jsonl"
printf '%s\n' '- There are 21 templates [source:S999].' > "$unknown_case/draft.md"
unknown_plain_status=0
( RESEARCH_RUN_DIR="$unknown_case" RESEARCH_PROJECT_ROOT="$marker_fixture/project"
  research_verify_synthesis "$unknown_case/draft.md" ) || unknown_plain_status=$?
unknown_plain_checks=$(jq -c '.checks | map(.kind)' "$unknown_case/verification.json")
printf '%s\n' '- There are 21 templates [source:S999] [inference, counted by glob].' > "$unknown_case/draft.md"
unknown_annotated_status=0
( RESEARCH_RUN_DIR="$unknown_case" RESEARCH_PROJECT_ROOT="$marker_fixture/project"
  research_verify_synthesis "$unknown_case/draft.md" ) || unknown_annotated_status=$?
if [[ "$unknown_plain_status" == "$unknown_annotated_status" && "$unknown_plain_checks" == '["unknown_source"]' ]] &&
   jq -e '.checks | map(.kind) == ["unknown_source"]' "$unknown_case/verification.json" >/dev/null; then test_pass
else test_fail "annotation changed the unknown-source citation gate"; fi

_source_verification_case() {
    local name="$1" catalog="$2" text="$3" expected_status="$4" expected_failures="$5" expected_kinds="$6"
    local case_dir="$marker_fixture/source-$name" status=0 kinds
    mkdir -p "$case_dir/snapshots"
    : > "$case_dir/sources.jsonl"
    if [[ "$catalog" != empty ]]; then
        printf '%s\n' '{"source_id":"S001","independence_key":"content:fixture"}' > "$case_dir/sources.jsonl"
        [[ "$catalog" == unfetched ]] || printf '%s\n' 'There are 21 templates.' > "$case_dir/snapshots/S001.body"
    fi
    printf '%s\n' "$text" > "$case_dir/draft.md"
    test_case "source identity verification: $name"
    ( RESEARCH_RUN_DIR="$case_dir" RESEARCH_PROJECT_ROOT="$marker_fixture/project"
      research_verify_synthesis "$case_dir/draft.md" ) || status=$?
    kinds=$(jq -r '.checks[].kind' "$case_dir/verification.json" | sort | tr '\n' ' ')
    if [[ "$status" == "$expected_status" && "$kinds" == "$expected_kinds" ]] &&
       jq -e --argjson failures "$expected_failures" --argjson status "$expected_status" \
           '.claims_checked == 1 and .failures == $failures and .status == (if $status == 0 then "passed" else "failed" end)' \
           "$case_dir/verification.json" >/dev/null; then test_pass
    else test_fail "status=$status checks=$kinds report=$(cat "$case_dir/verification.json")"; fi
}
_source_verification_case empty-number empty '- There are 21 templates [source:S999].' 1 1 'unknown_source '
_source_verification_case empty-annotated empty '- There are 21 templates [source:S999] [inference, counted by glob].' 1 1 'unknown_source '
_source_verification_case empty-prose empty '- A supported statement [source:S999].' 1 1 'unknown_source '
_source_verification_case populated-unknown populated '- There are 21 templates [source:S999].' 1 1 'unknown_source '
_source_verification_case populated-mixed populated '- There are 21 templates [source:S001] [source:S999].' 1 1 'unknown_source '
_source_verification_case two-unknown populated '- There are 21 templates [source:S998] [source:S999].' 1 2 'unknown_source unknown_source '
_source_verification_case known-match populated '- There are 21 templates [source:S001] [inference, counted by glob].' 0 0 ''
_source_verification_case known-mismatch populated '- There are 901 templates [source:S001] [inference, counted by glob].' 1 1 'number_mismatch '
_source_verification_case known-unfetched unfetched '- There are 21 templates [source:S001].' 0 0 'number_unverified '

test_summary
