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
