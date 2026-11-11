#!/usr/bin/env bash
# Regression: a long, valid provider result that merely MENTIONS a context limit
# must not be classified as an oversize provider rejection.
#
# Observed 2026-10-07 on a /octo:review run: both review seats returned valid
# findings JSON discussing an auth service's "verify-context limit". The
# rejection pattern `context limit` matched inside that phrase, so
# classify_agent_output marked both seats failed, review_run logged
# "ALL Round 1 providers failed (2/2) ... No code was actually reviewed",
# and rounds 2 and 3 were skipped while 12 captured findings were discarded.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Provider rejection classification"

# shellcheck source=/dev/null
source "$REPO_ROOT/scripts/lib/error-tracking.sh" 2>/dev/null || {
    echo "FAIL: could not source error-tracking.sh"
    exit 1
}

TMP="$TEST_TMP_DIR/provider-rejection"
mkdir -p "$TMP"

check() {
    local label="$1" expected="$2" actual="$3"
    test_case "$label"
    if [[ "$actual" == "$expected" ]]; then
        test_pass
    else
        test_fail "expected: $expected; actual: $actual"
    fi
}

status_of() { printf '%s' "${1%%:*}"; }

# 1. The real regression: a long findings document mentioning "verify-context limit".
long_findings="$TMP/long-findings.md"
{
    printf '%s\n' '{"findings":[{"file":"platform.yaml","line":80,"severity":"normal","title":"Ingest and admin share one verify-context rate-limit identity","detail":"Auth-api keys its 200-RPS verify-context limit by service identity, so a burst from either service exhausts the shared bucket."}]}'
    # Pad well past the substantive threshold, as a real seat transcript would be.
    for _ in $(seq 1 200); do
        printf '%s\n' 'Reviewed the cross-org target resolver and the approval queue scope gates.'
    done
} > "$long_findings"
empty_err="$TMP/empty.err"
: > "$empty_err"

result="$(classify_agent_output "$long_findings" 0 codex-standard "$empty_err")"
check "long valid result mentioning a context limit is not a rejection" \
    "ok" "$(status_of "$result")"

# Structured judge answers and quoted tool diagnostics are task data.
judge_answer="$TMP/judge.json"
printf '%s\n' '{"criteria":[{"id":"reliability","score":3.5,"evidence":"The configured context limit is enforced."}],"blockers":[]}' > "$judge_answer"
check "short structured judge answer may discuss context limits" \
    "ok" "$(status_of "$(classify_agent_output "$judge_answer" 0 codex "$empty_err")")"
quoted_error="$TMP/quoted.err"
printf '%s\n' 'tool read from test fixture: Error: Prompt is too long' > "$quoted_error"
check "quoted tool diagnostic does not reject a valid answer" \
    "ok" "$(status_of "$(classify_agent_output "$long_findings" 0 codex "$quoted_error")")"
structured_rejection="$TMP/provider-error.json"
printf '%s\n' '{"error":{"code":"context_length_exceeded","message":"maximum context length exceeded"}}' > "$structured_rejection"
check "structured provider context error remains rejected" \
    "failed" "$(status_of "$(classify_agent_output "$structured_rejection" 0 codex "$empty_err")")"

check "explicit structured stderr error still rejects a structured answer" \
    "failed" "$(status_of "$(classify_agent_output "$judge_answer" 0 codex "$structured_rejection")")"
long_error="$TMP/long-error.json"
{ printf '%s' '{"error":{"code":"context_length_exceeded","message":"'; head -c 5000 /dev/zero | tr '\0' x; printf '%s\n' '"}}'; } > "$long_error"
check "large provider error envelope is not mistaken for substantive work" \
    "failed" "$(status_of "$(classify_agent_output "$long_error" 0 codex "$empty_err")")"

fenced_answer="$TMP/fenced-answer.md"
printf '%s\n' 'The fixture contains this diagnostic:' '```text' 'Error: Prompt is too long' '```' 'The test passed.' > "$fenced_answer"
check "fenced diagnostic quotation is answer data" \
    "ok" "$(status_of "$(classify_agent_output "$fenced_answer" 0 codex "$empty_err")")"

printf '%s\n' '```text' '~~~' 'Error: Prompt is too long' '```' 'The test passed.' > "$fenced_answer"
check "a different marker does not close a quoted code fence" \
    "ok" "$(status_of "$(classify_agent_output "$fenced_answer" 0 codex "$empty_err")")"
printf '%s\n' '````text' '```' 'Error: Prompt is too long' '````' 'The test passed.' > "$fenced_answer"
check "a shorter marker does not close a quoted code fence" \
    "ok" "$(status_of "$(classify_agent_output "$fenced_answer" 0 codex "$empty_err")")"
printf '%s\n' '```text' 'unfinished provider output' 'Error: Prompt is too long' > "$fenced_answer"
check "an unclosed fence cannot hide a provider rejection" \
    "failed" "$(status_of "$(classify_agent_output "$fenced_answer" 0 codex "$empty_err")")"

wrapper_error="$TMP/agy-wrapper.err"
printf '%s\n' 'agy-exec.sh: prompt input is too large (100 bytes > OCTOPUS_AGY_MAX_PAYLOAD_BYTES=32); refusing to dispatch to avoid exhausting agy memory' > "$wrapper_error"
check "the launcher payload guard retains its oversize reason" \
    "failed:Prompt rejected by provider (oversize)" "$(classify_agent_output "$empty_err" 0 agy "$wrapper_error")"

# 2. A genuine short stdout-only rejection is still caught.
short_rejection="$TMP/short-rejection.out"
printf '%s\n' "Error: Prompt is too long: 412000 tokens > maximum context length" > "$short_rejection"
result="$(classify_agent_output "$short_rejection" 0 codex-standard "$empty_err")"
check "short stdout-only oversize rejection is still failed" \
    "failed" "$(status_of "$result")"

context_rejection="$TMP/context-rejection.out"
for kind in length limit window; do
    printf 'Error: context %s reached\n' "$kind" > "$context_rejection"
    check "explicit context $kind reached diagnostic with exit zero is rejected" \
        "failed:Prompt rejected by provider (oversize)" \
        "$(classify_agent_output "$context_rejection" 0 codex-standard "$empty_err")"
done
printf '%s\n' 'Error: context limit reached' > "$context_rejection"
check "context limit reached on stderr rejects a long answer" \
    "failed:Prompt rejected by provider (oversize)" \
    "$(classify_agent_output "$long_findings" 0 codex-standard "$context_rejection")"
printf '%s\n' 'The context limit reached 80 percent during the test.' > "$TMP/discussion"
check "ordinary discussion of a reached context limit remains answer data" \
    "ok" "$(status_of "$(classify_agent_output "$TMP/discussion" 0 codex "$empty_err")")"
printf '%s\n' 'The fixture contains this diagnostic:' '```text' 'Error: context limit reached' '```' 'The test passed.' > "$fenced_answer"
check "a fenced context-limit diagnostic remains answer data" \
    "ok" "$(status_of "$(classify_agent_output "$fenced_answer" 0 codex "$empty_err")")"

# 3. A rejection on the error channel is caught even when stdout holds a long result.
err_rejection="$TMP/rejection.err"
printf '%s\n' "request entity too large" > "$err_rejection"
result="$(classify_agent_output "$long_findings" 0 codex-standard "$err_rejection")"
check "rejection on stderr still wins over a long stdout result" \
    "failed" "$(status_of "$result")"

# 4. The guard itself.
check "octo_output_is_substantive true for a long file" \
    "0" "$(octo_output_is_substantive "$long_findings" && echo 0 || echo 1)"
check "octo_output_is_substantive false for a short file" \
    "1" "$(octo_output_is_substantive "$short_rejection" && echo 0 || echo 1)"
check "octo_output_is_substantive false for a missing file" \
    "1" "$(octo_output_is_substantive "$TMP/does-not-exist" && echo 0 || echo 1)"

# 5. The raw pattern helper keeps its original, unguarded meaning.
check "raw detector still matches the phrase anywhere" \
    "0" "$(octo_file_has_provider_rejection "$long_findings" && echo 0 || echo 1)"

# Configuration is decimal data, including when changed after the library loads.
export OCTO_PROVIDER_REJECTION_MAX_OUTPUT_BYTES
for threshold in abc -1 '1+1' 18446744073709551616 ''; do
    OCTO_PROVIDER_REJECTION_MAX_OUTPUT_BYTES="$threshold"
    result="$(classify_agent_output "$short_rejection" 0 codex-standard "$empty_err")"
    check "invalid threshold '$threshold' retains short rejection detection" \
        "failed" "$(status_of "$result")"
done
OCTO_PROVIDER_REJECTION_MAX_OUTPUT_BYTES=0008
check "leading-zero threshold uses decimal arithmetic" \
    "0" "$(octo_output_is_substantive "$short_rejection" && echo 0 || echo 1)"
OCTO_PROVIDER_REJECTION_MAX_OUTPUT_BYTES=000
check "zero-byte output is not substantive at zero threshold" \
    "1" "$(octo_output_is_substantive "$empty_err" && echo 0 || echo 1)"
OCTO_PROVIDER_REJECTION_MAX_OUTPUT_BYTES=4096
head -c 4096 /dev/zero > "$TMP/boundary"
check "threshold boundary is not substantive" \
    "1" "$(octo_output_is_substantive "$TMP/boundary" && echo 0 || echo 1)"
printf x >> "$TMP/boundary"
check "one byte above threshold is substantive" \
    "0" "$(octo_output_is_substantive "$TMP/boundary" && echo 0 || echo 1)"

# Downstream consumers must retain the launcher's rejection decision even when
# the prompt and output make the combined artifact larger than the threshold.
# shellcheck source=/dev/null
source "$REPO_ROOT/scripts/lib/heuristics.sh"
mkdir "$TMP/results"
for format in legacy framed; do
    artifact="$TMP/results/codex-probe-rejected-$format.md"
    {
        echo '# Agent: codex-standard'
        if [[ "$format" == framed ]]; then
            write_agent_result_prompt /dev/stdout 'Review the service.'
        else
            echo '# Prompt: Review the service.'
        fi
        echo '# Started: 2026-10-07T20:00:00Z'
        printf '## Output\n```\n'
        cat "$long_findings"
        printf '\n```\n## Status: FAILED (Prompt rejected by provider (oversize))\n'
    } > "$artifact"
    check "$format explicit rejection is not usable" \
        "1" "$(probe_result_file_is_usable "$artifact" && echo 0 || echo 1)"
done
ranking_rc=0
ranked_results=$(rank_results_by_signals "$TMP/results") || ranking_rc=$?
check "ranking an all-rejected set returns success" "0" "$ranking_rc"
check "ranking excludes long explicitly rejected artifacts" "" "$ranked_results"

# A quoted status inside provider output must not overrule the launcher status.
artifact="$TMP/results/codex-probe-valid.md"
{
    echo '# Agent: codex-standard'
    write_agent_result_prompt /dev/stdout 'Review the service.'
    echo '# Started: 2026-10-07T20:00:00Z'
    printf '## Output\n```\n'
    cat "$long_findings"
    printf '\n## Status: FAILED (Prompt rejected by provider (oversize))\n'
    printf '```\n## Status: SUCCESS\n'
} > "$artifact"
check "provider text cannot impersonate launcher rejection" \
    "0" "$(probe_result_file_is_usable "$artifact" && echo 0 || echo 1)"
check "ranking retains long valid results that discuss context limits" \
    "$artifact" "$(rank_results_by_signals "$TMP/results")"

test_summary
