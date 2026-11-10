#!/usr/bin/env bash
# Later sentences need their own source subject before a quote is attributed.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "${COUNCIL_LIB_ROOT:-$PROJECT_ROOT}/scripts/lib/council.sh"
test_suite "Council later source subjects"
evidence="$TEST_TMP_DIR/evidence"
mkdir -p "$evidence/src"
real='const actualPrice = calculateActualPrice(input);'
fake='const inventedPrice = calculateInventedPrice(input);'
printf '%s\n' "$real" > "$evidence/src/pricing.ts"
git -C "$evidence" init -q
git -C "$evidence" add src/pricing.ts
git -C "$evidence" -c user.name=Test -c user.email=test@example.invalid -c core.hooksPath=/dev/null commit -qm fixture
for boundary in '.' ';' '?'; do
    for owner in 'My calculated estimate is' 'My repro has' 'The file contains' 'The source itself computes'; do
        for content in arithmetic code; do
            test_case "$boundary $owner preserves $content ownership"
            quote="$fake"
            [[ "$content" == arithmetic ]] && quote='1_000 * 2_000 = 2_000_000'
            response="$TEST_TMP_DIR/response.md"
            printf 'src/pricing.ts:1%s %s `%s`.\nsrc/pricing.ts:1 reads `%s`.\nVERDICT: REVISE\n' \
                "$boundary" "$owner" "$quote" "$real" > "$response"
            report="$(council_response_quote_verification_json "$response" "$evidence")"
            assertion='.quotes_attributed_unverified == 0 and .fabricated == false'
            [[ "$owner" == The* ]] && assertion='.quotes_attributed_unverified == 1 and .fabricated == true'
            if jq -e ".verification_failed == false and ($assertion)" <<< "$report" >/dev/null; then
                test_pass
            else
                test_fail "later subject misattributed: $report"
            fi
        done
    done
done
test_summary
