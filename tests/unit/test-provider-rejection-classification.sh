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

# shellcheck source=/dev/null
source "$REPO_ROOT/scripts/lib/error-tracking.sh" 2>/dev/null || {
    echo "FAIL: could not source error-tracking.sh"
    exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

check() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  ok: $label"
        pass=$((pass + 1))
    else
        echo "  FAIL: $label"
        echo "        expected: $expected"
        echo "        actual:   $actual"
        fail=$((fail + 1))
    fi
}

status_of() { printf '%s' "${1%%:*}"; }

echo "test-provider-rejection-classification"

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

# 2. A genuine short stdout-only rejection is still caught.
short_rejection="$TMP/short-rejection.out"
printf '%s\n' "Error: Prompt is too long: 412000 tokens > maximum context length" > "$short_rejection"
result="$(classify_agent_output "$short_rejection" 0 codex-standard "$empty_err")"
check "short stdout-only oversize rejection is still failed" \
    "failed" "$(status_of "$result")"

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
check "ranking excludes long explicitly rejected artifacts" \
    "" "$(rank_results_by_signals "$TMP/results")"

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

echo
if ((fail > 0)); then
    echo "FAILED: $fail failing, $pass passing"
    exit 1
fi
echo "PASSED: $pass checks"
