#!/usr/bin/env bash
# Unit tests for durable Octopus proof packets.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROOF_LIB="$PROJECT_ROOT/scripts/lib/proof-packet.sh"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "proof packet"

if [[ -f "$PROOF_LIB" ]]; then
    # shellcheck source=/dev/null
    source "$PROOF_LIB"
fi

assert_function_exists() {
    local fn="$1"
    test_case "function exists: $fn"
    if declare -F "$fn" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "missing function: $fn"
    fi
}

test_case "proof-packet.sh has valid bash syntax"
if [[ -f "$PROOF_LIB" ]] && bash -n "$PROOF_LIB" 2>/dev/null; then
    test_pass
else
    test_fail "missing or invalid $PROOF_LIB"
fi

for fn in \
    octo_parse_provider_status_record \
    octo_proof_enabled \
    octo_proof_sanitize_id \
    octo_proof_init \
    octo_proof_event \
    octo_proof_artifact \
    octo_proof_command \
    octo_proof_claim \
    octo_proof_capture_provider_status \
    octo_proof_finalize
do
    assert_function_exists "$fn"
done

test_case "shared provider-status parser preserves v2 legacy and failure contracts"
if declare -F octo_parse_provider_status_record >/dev/null 2>&1; then
    parser_ok=true
    octo_parse_provider_status_record 'v2|commandcode|model-one.v1|fallback|detail|with|pipes' || parser_ok=false
    [[ "${OCTO_PROVIDER_STATUS_PROVIDER:-}" == commandcode && \
       "${OCTO_PROVIDER_STATUS_MODEL:-}" == model-one.v1 && \
       "${OCTO_PROVIDER_STATUS_VALUE:-}" == fallback && \
       "${OCTO_PROVIDER_STATUS_DETAIL:-}" == 'detail|with|pipes' ]] || parser_ok=false

    octo_parse_provider_status_record 'codex|auth-failed|legacy|detail|with|pipes' || parser_ok=false
    [[ "${OCTO_PROVIDER_STATUS_PROVIDER:-}" == codex && \
       -z "${OCTO_PROVIDER_STATUS_MODEL:-}" && \
       "${OCTO_PROVIDER_STATUS_VALUE:-}" == auth-failed && \
       "${OCTO_PROVIDER_STATUS_DETAIL:-}" == 'legacy|detail|with|pipes' ]] || parser_ok=false

    OCTO_PROVIDER_STATUS_PROVIDER=stale
    OCTO_PROVIDER_STATUS_MODEL=stale
    OCTO_PROVIDER_STATUS_VALUE=stale
    OCTO_PROVIDER_STATUS_DETAIL=stale
    empty_rc=0
    octo_parse_provider_status_record '' || empty_rc=$?
    [[ "$empty_rc" -eq 1 && \
       -z "${OCTO_PROVIDER_STATUS_PROVIDER:-}" && \
       -z "${OCTO_PROVIDER_STATUS_MODEL:-}" && \
       -z "${OCTO_PROVIDER_STATUS_VALUE:-}" && \
       -z "${OCTO_PROVIDER_STATUS_DETAIL:-}" ]] || parser_ok=false

    if [[ "$parser_ok" == true ]]; then
        test_pass
    else
        test_fail "shared provider-status parser changed field or failure semantics"
    fi
else
    test_fail "shared provider-status parser is unavailable"
fi

test_case "OCTOPUS_PROOF_PACKET=0 disables proof packets"
if declare -F octo_proof_enabled >/dev/null 2>&1; then
    if OCTOPUS_PROOF_PACKET=0 octo_proof_enabled; then
        test_fail "expected proof packets to be disabled"
    else
        test_pass
    fi
else
    test_fail "octo_proof_enabled is not defined"
fi

test_case "init creates sanitized run directory and state"
if declare -F octo_proof_init >/dev/null 2>&1; then
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    OCTOPUS_PROOF_ROOT="$tmp_home/proofs"
    OCTOPUS_PROOF_RUN_ID="review run / 123"
    run_dir=$(octo_proof_init "review" "review staged changes" '{"target":"staged"}')
    if [[ "$run_dir" == "$tmp_home/proofs/review-run-123" ]] \
       && [[ -f "$run_dir/proof.jsonl" ]] \
       && [[ -f "$run_dir/state.json" ]] \
       && jq -e '.schema == 1 and .workflow == "review" and .status == "running"' "$run_dir/state.json" >/dev/null; then
        test_pass
    else
        test_fail "proof packet directory or state was not initialized correctly"
    fi
    rm -rf "$tmp_home"
else
    test_fail "octo_proof_init is not defined"
fi

test_case "parallel runs in one Claude session get their own run directories"
if declare -F octo_proof_init >/dev/null 2>&1; then
    tmp_home=$(mktemp -d)
    run_in_session() {
        env -u OCTOPUS_PROOF_RUN_ID -u OCTOPUS_PROOF_PACKET -u CLAUDE_CODE_SESSION -u CLAUDE_SESSION_ID \
            HOME="$tmp_home" OCTOPUS_PROOF_ROOT="$tmp_home/proofs" CLAUDE_CODE_SESSION_ID="sess-parallel" \
            bash -c '
                source "$1"
                run_dir=$(octo_proof_init "review" "$2" "{}") || exit 1
                sleep 1
                octo_proof_finalize "$run_dir" "pass" "$2"
                printf "%s\n" "$run_dir"
            ' _ "$PROOF_LIB" "$1" > "$tmp_home/$2"
    }
    run_in_session "target=2141" out-a &
    pid_a=$!
    run_in_session "target=2142" out-b &
    pid_b=$!
    wait "$pid_a" "$pid_b" || true
    dir_a=$(cat "$tmp_home/out-a" 2>/dev/null || true)
    dir_b=$(cat "$tmp_home/out-b" 2>/dev/null || true)
    if [[ -n "$dir_a" && -n "$dir_b" && "$dir_a" != "$dir_b" ]] \
       && [[ "${dir_a##*/}" == sess-parallel-* && "${dir_b##*/}" == sess-parallel-* ]] \
       && jq -e '.goal == "target=2141"' "$dir_a/state.json" >/dev/null \
       && jq -e '.goal == "target=2142"' "$dir_b/state.json" >/dev/null \
       && grep -qx "Goal: target=2141" "$dir_a/summary.md" \
       && grep -qx "Goal: target=2142" "$dir_b/summary.md" \
       && [[ "$(jq -s '[.[] | select(.type == "started")] | length' "$dir_a/proof.jsonl")" == 1 ]] \
       && [[ "$(jq -s '[.[] | select(.type == "started")] | length' "$dir_b/proof.jsonl")" == 1 ]]; then
        test_pass
    else
        test_fail "parallel runs shared a proof packet: a=${dir_a:-<none>} b=${dir_b:-<none>}"
    fi
    unset -f run_in_session
    rm -rf "$tmp_home"
else
    test_fail "octo_proof_init is not defined"
fi

test_case "events, claims, commands, and artifacts append valid JSONL"
if declare -F octo_proof_event >/dev/null 2>&1; then
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    OCTOPUS_PROOF_ROOT="$tmp_home/proofs"
    OCTOPUS_PROOF_RUN_ID="events"
    run_dir=$(octo_proof_init "review" "goal" '{}')
    octo_proof_event "$run_dir" "custom" '{"hello":"world"}'
    octo_proof_claim "$run_dir" "all tests passed" "verified" "tests/unit/test-proof-packet.sh"
    octo_proof_command "$run_dir" "npm test" "0" "logs/test.txt"
    octo_proof_artifact "$run_dir" "review-findings" "$run_dir/findings.json" "final review findings"
    if jq -s -e '
        length == 5
        and .[1].type == "custom"
        and .[2].type == "claim"
        and .[2].data.status == "verified"
        and .[3].type == "command"
        and .[3].data.exit_code == 0
        and .[4].type == "artifact"
      ' "$run_dir/proof.jsonl" >/dev/null; then
        test_pass
    else
        test_fail "proof.jsonl did not contain valid expected events"
    fi
    rm -rf "$tmp_home"
else
    test_fail "octo_proof_event is not defined"
fi

test_case "provider status capture records fallback substitutions"
if declare -F octo_proof_capture_provider_status >/dev/null 2>&1; then
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    OCTOPUS_PROOF_ROOT="$tmp_home/proofs"
    OCTOPUS_PROOF_RUN_ID="providers"
    run_dir=$(octo_proof_init "review" "goal" '{}')
    status_file="$tmp_home/provider-status.txt"
    {
        echo "codex|fallback|Round 2 -> claude-sonnet"
        echo "gemini|ok|Round 1 findings"
        echo "perplexity|auth-failed|PERPLEXITY_API_KEY missing"
    } > "$status_file"
    octo_proof_capture_provider_status "$run_dir" "$status_file"
    if jq -s -e '
        [.[].type] | index("provider_substitution")
      ' "$run_dir/proof.jsonl" >/dev/null \
       && jq -s -e '
        [.[] | select(.type == "provider_status" and .data.provider == "gemini" and .data.status == "ok")] | length == 1
      ' "$run_dir/proof.jsonl" >/dev/null \
       && jq -s -e '
        [.[] | select(.type == "provider_substitution" and .data.provider == "codex" and .data.status == "fallback")] | length == 1
      ' "$run_dir/proof.jsonl" >/dev/null; then
        test_pass
    else
        test_fail "provider status capture did not record fallback substitutions"
    fi
    rm -rf "$tmp_home"
else
    test_fail "octo_proof_capture_provider_status is not defined"
fi

test_case "provider status capture preserves distinct model identities"
if declare -F octo_proof_capture_provider_status >/dev/null 2>&1; then
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    OCTOPUS_PROOF_ROOT="$tmp_home/proofs"
    OCTOPUS_PROOF_RUN_ID="provider-models"
    run_dir=$(octo_proof_init "review" "goal" '{}')
    status_file="$tmp_home/provider-model-status.txt"
    {
        echo "v2|commandcode|model-one.v1|ok|Round 1 findings"
        echo "v2|commandcode|model-two.v2|fallback|Round 1 failed"
    } > "$status_file"
    octo_proof_capture_provider_status "$run_dir" "$status_file"
    if jq -s -e '
        [.[] | select(.type == "provider_status" and .data.provider == "commandcode") | .data.model]
        | sort == ["model-one.v1", "model-two.v2"]
      ' "$run_dir/proof.jsonl" >/dev/null \
       && jq -s -e '
        [.[] | select(.type == "provider_substitution" and .data.provider == "commandcode" and .data.model == "model-two.v2")]
        | length == 1
      ' "$run_dir/proof.jsonl" >/dev/null; then
        test_pass
    else
        test_fail "proof packet collapsed or misparsed model-qualified provider status"
    fi
    rm -rf "$tmp_home"
else
    test_fail "octo_proof_capture_provider_status is not defined"
fi

test_case "provider status capture delegates malformed-record handling to the shared parser"
if declare -F octo_proof_capture_provider_status >/dev/null 2>&1; then
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    OCTOPUS_PROOF_ROOT="$tmp_home/proofs"
    OCTOPUS_PROOF_RUN_ID="provider-parser-delegation"
    run_dir=$(octo_proof_init "review" "goal" '{}')
    status_file="$tmp_home/provider-status-delegation.txt"
    printf '%s\n' 'v2|commandcode|model-one.v1|ok|completed' > "$status_file"
    octo_parse_provider_status_record() { return 1; }
    octo_proof_capture_provider_status "$run_dir" "$status_file"
    provider_event_count=$(jq -s '[.[] | select(.type == "provider_status")] | length' "$run_dir/proof.jsonl")
    unset -f octo_parse_provider_status_record
    if [[ "$provider_event_count" -eq 0 ]]; then
        test_pass
    else
        test_fail "proof packet bypassed the shared provider-status parser"
    fi
    rm -rf "$tmp_home"
else
    test_fail "octo_proof_capture_provider_status is not defined"
fi

test_case "finalize updates state and writes markdown summary"
if declare -F octo_proof_finalize >/dev/null 2>&1; then
    tmp_home=$(mktemp -d)
    HOME="$tmp_home"
    OCTOPUS_PROOF_ROOT="$tmp_home/proofs"
    OCTOPUS_PROOF_RUN_ID="finalize"
    run_dir=$(octo_proof_init "review" "goal" '{}')
    octo_proof_artifact "$run_dir" "findings" "$run_dir/findings.json" "review output"
    octo_proof_finalize "$run_dir" "pass" "No issues found."
    if jq -e '.status == "pass" and .summary == "No issues found."' "$run_dir/state.json" >/dev/null \
       && grep -q "Proof Packet" "$run_dir/summary.md" \
       && grep -q "Verdict: pass" "$run_dir/summary.md" \
       && grep -q "review output" "$run_dir/summary.md"; then
        test_pass
    else
        test_fail "finalized state or markdown summary was incorrect"
    fi
    rm -rf "$tmp_home"
else
    test_fail "octo_proof_finalize is not defined"
fi

test_summary
