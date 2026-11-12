#!/usr/bin/env bash
# Later source claims retain ownership even when the subject says "itself".
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "${COUNCIL_LIB_ROOT:-$PROJECT_ROOT}/scripts/lib/council.sh"
test_suite "Council source claim modifiers"

evidence="$TEST_TMP_DIR/evidence"
mkdir -p "$evidence/src"
real='const actualPrice = calculateActualPrice(input);'
fake='const inventedPrice = calculateInventedPrice(input);'
printf '%s\n' "$real" > "$evidence/src/pricing.ts"
git -C "$evidence" init -q
git -C "$evidence" add src/pricing.ts
git -C "$evidence" -c user.name=Test -c user.email=test@example.invalid \
    -c core.hooksPath=/dev/null commit -qm fixture
for conjunction in but however whereas and; do
    for subject in file source code; do
        for ownership in source-real source-invented reviewer-input; do
            test_case "$conjunction the $subject itself retains $ownership ownership"
            introduction="a fixture I built as a test, $conjunction the $subject itself reads"
            quote="$fake"
            assertion='.quotes_attributed_unverified == 1 and .quotes_unverifiable_proposed == 0 and .fabricated == true'
            if [[ "$ownership" == source-real ]]; then
                quote="$real"
                assertion='.quotes_verified == 2 and .quotes_unverifiable_proposed == 0 and .fabricated == false'
            elif [[ "$ownership" == reviewer-input ]]; then
                introduction="$introduction a row I carefully built as"
                assertion='.quotes_unverifiable_proposed == 1 and .quotes_attributed_unverified == 0 and .fabricated == false'
            fi
            response="$TEST_TMP_DIR/response.md"
            printf 'src/pricing.ts:1 contains %s `%s`.\nsrc/pricing.ts:1 reads `%s`.\nVERDICT: REVISE\n' \
                "$introduction" "$quote" "$real" > "$response"
            report="$(council_response_quote_verification_json "$response" "$evidence")"
            if jq -e ".verification_failed == false and ($assertion)" <<< "$report" >/dev/null; then
                test_pass
            else
                test_fail "source-claim ownership changed: $report"
            fi
        done
    done
done
test_summary
