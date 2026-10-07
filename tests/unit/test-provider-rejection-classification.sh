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

echo
if ((fail > 0)); then
    echo "FAILED: $fail failing, $pass passing"
    exit 1
fi
echo "PASSED: $pass checks"
