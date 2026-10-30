#!/usr/bin/env bash
# Quote verification for council grounding (sail-cruisey #2997).
#
# A seat that cites a real `path:line` used to be valid-grounded even when the
# code it quoted beside that citation existed nowhere in the file. The runner
# now checks each specific quote (backtick span or fenced block near a resolving
# citation) against the cited files; when none verify, the seat is blind.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/council.sh"

test_suite "Council quote grounding verification"

ROOT="$(mktemp -d "${TEST_TMP_DIR:-/tmp}/quote-root.XXXXXX")"
mkdir -p "$ROOT/src"
{
    printf 'export function priceFor(cabin, sailing) {\n'
    printf '  const base = cabin.basePrice ?? sailing.defaultPrice;\n'
    printf '  if (!base) return null;\n'
    printf '  return applyTaxes(base, sailing.portFees);\n'
    printf '}\n'
    for i in $(seq 1 80); do printf '// filler line %s\n' "$i"; done
    printf 'export const DISCOUNT_RULES = Object.freeze({ loyaltyTier: 0.05, earlyBird: 0.1 });\n'
} > "$ROOT/src/pricing.ts"
REAL_NEAR='const base = cabin.basePrice ?? sailing.defaultPrice;'
REAL_FAR='export const DISCOUNT_RULES = Object.freeze({ loyaltyTier: 0.05, earlyBird: 0.1 });'
FAKE='const base = await fetchCabinPrice(cabin.id, { cache: true });'

_resp() { local f; f="$(mktemp "$TEST_TMP_DIR/resp.XXXXXX")"; printf '%s\n' "$1" > "$f"; printf '%s\n' "$f"; }
_report() { council_response_quote_verification_json "$1" "$ROOT"; }
_field() { jq -r ".$2" <<< "$(_report "$1")"; }

test_case "fabricated quote beside a real path:line is checked, unverified, and fabricated"
fab="$(_resp "In src/pricing.ts:2 the base price is \`$FAKE\` which caches correctly.
VERDICT: APPROVE")"
r="$(_report "$fab")"
if jq -e '.citations == 1 and .quotes_checked == 1 and .quotes_verified == 0 and .quotes_unverified == 1 and .fabricated == true' <<< "$r" >/dev/null &&
   jq -e '.unverified_samples == []' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "a seat whose only citation quotes are fabricated is blind and not substantive"
if council_response_is_blind "$fab" "$ROOT" && ! council_response_is_substantive "$fab" "$ROOT"; then test_pass; else test_fail "fabricated-quote seat still counted"; fi

test_case "contribution record marks the seat invalid-ungrounded with per-seat grounding counts"
record="$(council_contribution_record_json "$fab" "$ROOT" sha256:test)"
if jq -e '.validation_result == "invalid-ungrounded" and .access_state == "evidence-rejected" and .evidence_paths == []
          and .grounding.quotes_checked == 1 and .grounding.quotes_verified == 0 and .grounding.fabricated == true' <<< "$record" >/dev/null; then
    test_pass
else
    test_fail "record: $record"
fi

test_case "unavailable contribution records retain the grounding schema"
record="$(council_unavailable_contribution_record_json)"
if jq -e '.validation_result == "invalid-record" and (.grounding | type == "object") and .grounding.fabricated == false' <<< "$record" >/dev/null; then
    test_pass
else
    test_fail "fallback record lacks grounding: $record"
fi

# PR #1212 Actions follow-up: access guidance and diff metadata.
for quote_kind in real fabricated; do
    test_case "explicit access failure takes priority over $quote_kind quotes"
    access_quote="$REAL_NEAR"
    [[ "$quote_kind" == fabricated ]] && access_quote="$FAKE"
    access_response="$(_resp "I cannot read the file.
src/pricing.ts:2 contains \`$access_quote\`
VERDICT: APPROVE")"
    access_record="$(council_contribution_record_json "$access_response" "$ROOT" sha256:test)"
    if council_response_has_access_failure "$access_response" &&
       jq -e '.access_state == "failed" and .validation_result == "invalid-access"
               and .evidence_paths == []' <<< "$access_record" >/dev/null; then
        test_pass
    else
        test_fail "access failure lost its classification: $access_record"
    fi
    test_case "$quote_kind quote access failures preserve the grounding report"
    if jq -e --arg kind "$quote_kind" '.grounding.quotes_checked == 1
            and .grounding.fabricated == ($kind == "fabricated")' <<< "$access_record" >/dev/null; then
        test_pass
    else
        test_fail "grounding evidence lost: $access_record"
    fi
    test_case "$quote_kind quote access failures give file-access guidance"
    access_warnings="$(
        COUNCIL_BLIND_SEATS=fixture
        COUNCIL_SEAT_RECORDS_JSON="$(jq -cn --argjson record "$access_record" \
            '[{status:"blind",provider:"fixture",contribution:$record}]')"
        council_print_run_warnings
    )"
    if [[ "$access_warnings" == *"give it file-read tools"* &&
          "$access_warnings" != *"grounding verification failed"* ]]; then
        test_pass
    else
        test_fail "wrong access guidance: $access_warnings"
    fi
done

marker_root="$(mktemp -d "$TEST_TMP_DIR/diff-marker.XXXXXX")"
mkdir -p "$marker_root/src"
marker_old='const amount = calculateLegacyRate(pricing.base);'
marker_new='const amount = calculateCurrentRate(pricing.base);'
printf '%s' "$marker_old" > "$marker_root/src/pricing.ts"
git -C "$marker_root" init -q
git -C "$marker_root" add src/pricing.ts
git -C "$marker_root" -c user.name=Test -c user.email=test@example.invalid \
    -c core.hooksPath=/dev/null commit -qm initial
printf '%s' "$marker_new" > "$marker_root/src/pricing.ts"
for marker_ending in lf crlf; do
    marker_text='\ No newline at end of file'
    [[ "$marker_ending" == crlf ]] && marker_text="${marker_text}"$'\r'
    for marker_shape in added removed mixed hunk; do
        marker_body="+$marker_new
$marker_text"
        case "$marker_shape" in
            removed) marker_body="-$marker_old
$marker_text" ;;
            mixed|hunk) marker_body="-$marker_old
$marker_text
+$marker_new
$marker_text" ;;
        esac
        if [[ "$marker_shape" == hunk ]]; then
            marker_body="--- a/src/pricing.ts
+++ b/src/pricing.ts
@@ -1 +1 @@
$marker_body"
        fi
        test_case "$marker_ending no-newline markers are metadata in $marker_shape quotes"
        marker_response="$(_resp "src/pricing.ts:1 contains
\`\`\`diff
$marker_body
\`\`\`
VERDICT: APPROVE")"
        marker_report="$(council_response_quote_verification_json "$marker_response" "$marker_root")"
        if jq -e '.verification_failed == false and .diff_unavailable == false
                and .quotes_checked == 1 and .quotes_verified == 1
                and .quotes_unverified == 0 and .fabricated == false' <<< "$marker_report" >/dev/null; then
            test_pass
        else
            test_fail "diff metadata counted as source: $marker_report"
        fi
    done
done
for marker_side in added removed; do
    test_case "no-newline marker does not excuse invented $marker_side source"
    marker_body="+$FAKE"
    [[ "$marker_side" == removed ]] && marker_body="-$FAKE"
    marker_response="$(_resp "src/pricing.ts:1 contains
\`\`\`diff
$marker_body
\ No newline at end of file
\`\`\`
VERDICT: APPROVE")"
    marker_report="$(council_response_quote_verification_json "$marker_response" "$marker_root")"
    if jq -e '.quotes_checked == 1 and .quotes_verified == 0 and .fabricated == true' \
            <<< "$marker_report" >/dev/null; then
        test_pass
    else
        test_fail "invented source accepted: $marker_report"
    fi
done
# End PR #1212 Actions follow-up.

# Grounding report privacy: exercise both direct reports and the contribution
# object that is persisted in summary.json, without redaction prerequisites.
sample_root="$(mktemp -d "$TEST_TMP_DIR/quote-private.XXXXXX")"
mkdir -p "$sample_root/src"
cp "$ROOT/src/pricing.ts" "$sample_root/src/pricing.ts"
git -C "$sample_root" init -q
git -C "$sample_root" add src/pricing.ts
git -C "$sample_root" -c user.name=Test -c user.email=test@example.invalid -c core.hooksPath=/dev/null commit -qm initial
private_marker="sk-$(printf 'q%.0s' {1..48})"
private_quote="const credential = \"$private_marker\";"
for sample_kind in inline fenced mixed repeated; do
    sample_checked=1; sample_verified=0; sample_unverified=1
    case "$sample_kind" in
        inline) sample_body="src/pricing.ts:2 reads \`$private_quote\`" ;;
        fenced) sample_body="src/pricing.ts:2 reads
\`\`\`ts
$private_quote
\`\`\`" ;;
        mixed)
            sample_body="src/pricing.ts:2 reads \`$REAL_NEAR\`.

src/pricing.ts:2 reads \`$private_quote\`"
            sample_checked=2; sample_verified=1 ;;
        repeated)
            sample_body=""
            for sample_number in 1 2 3 4; do
                sample_body="${sample_body}src/pricing.ts:2 reads \`$private_quote\`

"
            done
            sample_checked=4; sample_unverified=4 ;;
    esac
    sample_response="$(_resp "$sample_body
VERDICT: APPROVE")"
    for sample_api in report contribution; do
        test_case "$sample_kind unverified quotes retain counts without provider excerpts in $sample_api"
        if [[ "$sample_api" == report ]]; then
            sample_result="$(unset -f sanitize_secrets; council_response_quote_verification_json "$sample_response" "$sample_root")"
        else
            sample_result="$(unset -f sanitize_secrets; council_contribution_record_json "$sample_response" "$sample_root" sha256:test)"
        fi
        if [[ "$sample_result" != *"$private_marker"* ]] &&
           jq -e --arg api "$sample_api" --argjson checked "$sample_checked" \
               --argjson verified "$sample_verified" --argjson unverified "$sample_unverified" '
               (if $api == "contribution" then select(.validation_result == "invalid-ungrounded") | .grounding else . end)
               | .verification_failed == false and .diff_unavailable == false and .quotes_checked == $checked
                 and .quotes_verified == $verified and .quotes_unverified == $unverified
                 and .quotes_attributed_unverified == $unverified and .fabricated == true
                 and .unverified_samples == []' <<< "$sample_result" >/dev/null; then
            test_pass
        else
            test_fail "provider excerpts escaped or grounding counts/rejection changed"
        fi
    done
done
# End grounding report privacy controls.

test_case "a real quote near the cited line verifies (near_line) and stays valid-grounded"
real="$(_resp "In src/pricing.ts:2 the fallback \`$REAL_NEAR\` is correct.
VERDICT: APPROVE")"
r="$(_report "$real")"
record="$(council_contribution_record_json "$real" "$ROOT" sha256:test)"
if jq -e '.quotes_checked == 1 and .quotes_verified == 1 and .quotes_near_line == 1 and .fabricated == false' <<< "$r" >/dev/null &&
   jq -e '.validation_result == "valid-grounded" and .grounding.quotes_verified == 1' <<< "$record" >/dev/null &&
   ! council_response_is_blind "$real" "$ROOT"; then test_pass; else test_fail "report: $r record: $record"; fi

test_case "a real quote far from the cited line still verifies (anywhere in file), not near_line"
farq="$(_resp "src/pricing.ts:2 references \`$REAL_FAR\` for discounts.
VERDICT: APPROVE")"
r="$(_report "$farq")"
if jq -e '.quotes_verified == 1 and .quotes_near_line == 0 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "one verified quote among fabricated ones keeps the seat grounded"
mixed="$(_resp "src/pricing.ts:2 has \`$REAL_NEAR\` and also \`$FAKE\`.
VERDICT: APPROVE")"
r="$(_report "$mixed")"
if jq -e '.quotes_checked == 2 and .quotes_verified == 1 and .quotes_unverified == 1 and .fabricated == false' <<< "$r" >/dev/null &&
   ! council_response_quotes_fabricated "$mixed" "$ROOT"; then test_pass; else test_fail "report: $r"; fi

test_case "short fragments below the token/char floor are not checked"
short="$(_resp "src/pricing.ts:3 does \`return nothing\` and \`x = y\` here.
VERDICT: APPROVE")"
if [[ "$(_field "$short" quotes_checked)" == 0 && "$(_field "$short" fabricated)" == false ]]; then test_pass; else test_fail "report: $(_report "$short")"; fi

test_case "a citation with no quote is unaffected (valid-grounded, nothing checked)"
noquote="$(_resp "The null guard at src/pricing.ts:3 handles a missing base price.
VERDICT: APPROVE")"
record="$(council_contribution_record_json "$noquote" "$ROOT" sha256:test)"
if jq -e '.validation_result == "valid-grounded" and .grounding.quotes_checked == 0 and .grounding.citations == 1' <<< "$record" >/dev/null; then test_pass; else test_fail "record: $record"; fi

test_case "fenced quotes are whitespace-normalized; line-number gutters and diff markers are stripped"
fenced="$(_resp "Reviewed src/pricing.ts:2:
\`\`\`ts
  2 |    const base   = cabin.basePrice
  2 |        ?? sailing.defaultPrice;
\`\`\`
and the change:
\`\`\`diff
@@ -2 +3 @@
-  const base = cabin.oldPrice || sailing.legacyPrice;
+  if (!base) return null;
\`\`\`
VERDICT: APPROVE")"
gutter_diff="$TEST_TMP_DIR/gutter-reviewed.diff"
printf '@@ -2 +3 @@\n-  const base = cabin.oldPrice || sailing.legacyPrice;\n+  if (!base) return null;\n' > "$gutter_diff"
r="$(COUNCIL_CONTEXT_FILES=("$gutter_diff"); _report "$fenced")"
if jq -e '.quotes_checked == 2 and .quotes_verified == 2 and .quotes_verified_in_diff_removed == 1
          and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "a current added line cannot verify an unsupported removal in the same fence"
r="$(_report "$fenced")"
if jq -e '.quotes_checked == 2 and .quotes_verified == 1 and .quotes_unverifiable_claimed_removed == 1
          and .quotes_verified_in_diff_removed == 0 and .fabricated == false' <<< "$r" >/dev/null; then
    test_pass
else
    test_fail "the source-only match vouched for removed code: $r"
fi

# A known empty diff makes these fabricated-source assertions independent of
# the host's temporary-directory Git configuration.
fence_root="$(mktemp -d "$TEST_TMP_DIR/fence-evidence.XXXXXX")"
mkdir -p "$fence_root/src"
cp "$ROOT/src/pricing.ts" "$fence_root/src/pricing.ts"
git -C "$fence_root" init -q
git -C "$fence_root" add src
git -C "$fence_root" -c user.name=Test -c user.email=test@example.invalid commit -qm baseline
for verb in defines declares define declare defined declared; do
    test_case "an invented quote after $verb rejects approval even beside a genuine quote"
    response="$(_resp "src/pricing.ts:2 $verb \`$FAKE\`

src/pricing.ts:2 reads \`$REAL_NEAR\`
VERDICT: APPROVE")"
    record="$(council_contribution_record_json "$response" "$fence_root" sha256:test)"
    if jq -e '.validation_result == "invalid-ungrounded" and .access_state == "evidence-rejected"
            and .evidence_paths == [] and .grounding.quotes_checked == 2
            and .grounding.quotes_verified == 1 and .grounding.quotes_attributed == 2
            and .grounding.quotes_attributed_unverified == 1 and .grounding.fabricated == true' <<< "$record" >/dev/null &&
       ! council_response_is_substantive "$response" "$fence_root"; then test_pass; else test_fail "record: $record"; fi
done

for verb in defines declares; do
    test_case "a genuine quote after $verb remains valid"
    response="$(_resp "src/pricing.ts:2 $verb \`$REAL_NEAR\`
VERDICT: APPROVE")"
    record="$(council_contribution_record_json "$response" "$fence_root" sha256:test)"
    if jq -e '.validation_result == "valid-grounded" and .verdict == "APPROVE"
            and .grounding.quotes_verified == 1 and .grounding.quotes_attributed == 1
            and .grounding.fabricated == false' <<< "$record" >/dev/null; then test_pass; else test_fail "record: $record"; fi

    test_case "a proposed quote before $verb is not a claim about current source"
    response="$(_resp "Proposal: src/pricing.ts:2 $verb \`$FAKE\`

src/pricing.ts:2 reads \`$REAL_NEAR\`
VERDICT: REVISE")"
    record="$(council_contribution_record_json "$response" "$fence_root" sha256:test)"
    if jq -e '.validation_result == "valid-grounded" and .verdict == "REVISE"
            and .grounding.quotes_verified == 1 and .grounding.quotes_unverifiable_proposed == 1
            and .grounding.quotes_attributed_unverified == 0 and .grounding.fabricated == false' <<< "$record" >/dev/null; then test_pass; else test_fail "record: $record"; fi

    test_case "an inline suggestion after the citation remains a proposal despite $verb"
    response="$(_resp "src/pricing.ts:2 should be rewritten so it $verb \`$FAKE\`

src/pricing.ts:2 reads \`$REAL_NEAR\`
VERDICT: REVISE")"
    record="$(council_contribution_record_json "$response" "$fence_root" sha256:test)"
    if jq -e '.validation_result == "valid-grounded" and .grounding.quotes_verified == 1
            and .grounding.quotes_unverifiable_proposed == 1
            and .grounding.quotes_attributed_unverified == 0 and .grounding.fabricated == false' <<< "$record" >/dev/null; then test_pass; else test_fail "record: $record"; fi

    test_case "a tilde-fenced invention after $verb rejects approval beside a genuine quote"
    response="$(_resp "src/pricing.ts:2 $verb:
~~~ts
$FAKE
~~~

src/pricing.ts:2 reads \`$REAL_NEAR\`
VERDICT: APPROVE")"
    record="$(council_contribution_record_json "$response" "$fence_root" sha256:test)"
    if jq -e '.validation_result == "invalid-ungrounded" and .access_state == "evidence-rejected"
            and .evidence_paths == [] and .grounding.quotes_verified == 1
            and .grounding.quotes_attributed_unverified == 1 and .grounding.fabricated == true' <<< "$record" >/dev/null; then test_pass; else test_fail "record: $record"; fi
done

for marker in '~~~' '~~~~' '````'; do
    test_case "invented source in a $marker fence rejects the contribution"
    fenced="$(_resp "src/pricing.ts:2 reads:
${marker}ts
$FAKE
$marker
VERDICT: APPROVE")"
    record="$(council_contribution_record_json "$fenced" "$fence_root" sha256:test)"
    if jq -e '.validation_result == "invalid-ungrounded" and .access_state == "evidence-rejected"
            and .evidence_paths == [] and .grounding.quotes_checked == 1
            and .grounding.quotes_attributed_unverified == 1 and .grounding.fabricated == true' <<< "$record" >/dev/null &&
       ! council_response_is_substantive "$fenced" "$fence_root"; then test_pass; else test_fail "record: $record"; fi
done

for marker in '```' '````'; do
    test_case "a $marker fence with backticks in its info cannot hide invented source"
    fenced="$(_resp "src/pricing.ts:2 reads:
$marker \`evil\` marker
$FAKE
$marker
VERDICT: APPROVE")"
    record="$(council_contribution_record_json "$fenced" "$fence_root" sha256:test)"
    if jq -e '.validation_result == "invalid-ungrounded" and .access_state == "evidence-rejected"
            and .evidence_paths == [] and .grounding.quotes_checked == 1
            and .grounding.quotes_attributed_unverified == 1 and .grounding.fabricated == true' <<< "$record" >/dev/null &&
       ! council_response_is_substantive "$fenced" "$fence_root"; then test_pass; else test_fail "record: $record"; fi

    test_case "a genuine quote cannot mask invention inside a malformed $marker fence"
    fenced="$(_resp "src/pricing.ts:2 reads:
$marker \`evil\` marker
$FAKE
$marker

src/pricing.ts:2 reads \`$REAL_NEAR\`
VERDICT: APPROVE")"
    record="$(council_contribution_record_json "$fenced" "$fence_root" sha256:test)"
    if jq -e '.validation_result == "invalid-ungrounded" and .evidence_paths == []
            and .grounding.quotes_checked == 2 and .grounding.quotes_verified == 1
            and .grounding.quotes_attributed_unverified == 1 and .grounding.fabricated == true' <<< "$record" >/dev/null; then test_pass; else test_fail "record: $record"; fi

    test_case "a genuine quote inside a malformed $marker fence retains grounding"
    fenced="$(_resp "src/pricing.ts:2 reads:
$marker \`ts\` marker
$REAL_NEAR
$marker
VERDICT: APPROVE")"
    record="$(council_contribution_record_json "$fenced" "$fence_root" sha256:test)"
    if jq -e '.validation_result == "valid-grounded" and .verdict == "APPROVE"
            and .grounding.quotes_checked == 1 and .grounding.quotes_verified == 1
            and .grounding.fabricated == false' <<< "$record" >/dev/null; then test_pass; else test_fail "record: $record"; fi

    test_case "a proposal inside a malformed $marker fence is not fabricated source"
    fenced="$(_resp "src/pricing.ts:2 should become:
$marker \`ts\` marker
$FAKE
$marker
VERDICT: REVISE")"
    record="$(council_contribution_record_json "$fenced" "$fence_root" sha256:test)"
    if jq -e '.validation_result == "valid-grounded" and .verdict == "REVISE"
            and .grounding.quotes_unverifiable_proposed == 1
            and .grounding.quotes_attributed_unverified == 0 and .grounding.fabricated == false' <<< "$record" >/dev/null; then test_pass; else test_fail "record: $record"; fi
done

test_case "a real tilde-fenced quote with inline backticks is checked once"
printf '%s\n' 'const label = `cabin ${cabin.id}`;' > "$fence_root/src/template.ts"
fenced="$(_resp 'src/template.ts:1 reads:
~~~ts
const label = `cabin ${cabin.id}`;
~~~~
VERDICT: APPROVE')"
record="$(council_contribution_record_json "$fenced" "$fence_root" sha256:test)"
if jq -e '.validation_result == "valid-grounded" and .verdict == "APPROVE"
        and .grounding.quotes_checked == 1 and .grounding.quotes_verified == 1
        and .grounding.fabricated == false' <<< "$record" >/dev/null; then test_pass; else test_fail "record: $record"; fi

for false_close in '~~~' '````' '~~~~ts'; do
    test_case "$false_close cannot close a four-tilde fence before an invented quote"
    fenced="$(_resp "src/pricing.ts:2 reads:
~~~~ts
$false_close
$FAKE
~~~~
VERDICT: APPROVE")"
    r="$(council_response_quote_verification_json "$fenced" "$fence_root")"
    if jq -e '.quotes_checked == 1 and .quotes_attributed_unverified == 1 and .fabricated == true' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi
done

test_case "an unterminated tilde fence still checks its source quote"
fenced="$(_resp "src/pricing.ts:2 reads:
~~~ts
$FAKE")"
r="$(council_response_quote_verification_json "$fenced" "$fence_root")"
if jq -e '.quotes_checked == 1 and .quotes_attributed_unverified == 1 and .fabricated == true' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "an elided quote verifies when its specific pieces occur in source order"
elided="$(_resp "src/pricing.ts:1 \`export function priceFor(cabin, sailing) { ... return applyTaxes(base, sailing.portFees);\`
VERDICT: APPROVE")"
if [[ "$(_field "$elided" quotes_verified)" == 1 ]]; then test_pass; else test_fail "report: $(_report "$elided")"; fi

# Elided fragments must advance by character offsets, including within a line.
elision_root="$(mktemp -d "$TEST_TMP_DIR/elision-order.XXXXXX")"
mkdir -p "$elision_root/src"
elision_first='const firstValue = source.first ?? fallbackFirst;'
elision_second='const secondValue = source.second ?? fallbackSecond;'
elision_third='const thirdValue = source.third ?? fallbackThird;'
for elision_case in reversed same-line-reversed same-line-ordered reused-occurrence repeated-ordered three-piece-reversed; do
    printf '%s\n' "$elision_first" "$elision_second" "$elision_third" > "$elision_root/src/ordered.ts"
    elision_verified=0
    case "$elision_case" in
        reversed) elision_quote="$elision_second ... $elision_first" ;;
        same-line-reversed)
            printf '%s %s\n' "$elision_first" "$elision_second" > "$elision_root/src/ordered.ts"
            elision_quote="$elision_second … $elision_first" ;;
        same-line-ordered)
            printf '%s %s\n' "$elision_first" "$elision_second" > "$elision_root/src/ordered.ts"
            elision_quote="$elision_first … $elision_second"; elision_verified=1 ;;
        reused-occurrence) elision_quote="$elision_first ... $elision_first" ;;
        repeated-ordered)
            printf '%s\n' "$elision_second" "$elision_first" "$elision_second" > "$elision_root/src/ordered.ts"
            elision_quote="$elision_second ... $elision_first ... $elision_second"; elision_verified=1 ;;
        three-piece-reversed) elision_quote="$elision_first ... $elision_third ... $elision_second" ;;
    esac
    test_case "elided source order: $elision_case"
    elision_response="$(_resp "src/ordered.ts:1 reads \`$elision_quote\`.")"
    r="$(council_response_quote_verification_json "$elision_response" "$elision_root")"
    if jq -e --argjson verified "$elision_verified" '
        .quotes_checked == 1 and .quotes_verified == $verified
        and .quotes_unverified == (1 - $verified)
        and .quotes_attributed_unverified == (1 - $verified)
        and .fabricated == ($verified == 0)' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi
done
elision_diff="$TEST_TMP_DIR/elision-reviewed.diff"
elision_added_first='const addedFirst = revised.first ?? revisedFallback;'
elision_added_second='const addedSecond = revised.second ?? revisedFallback;'
printf '@@ -1,2 +1,2 @@\n-%s\n-%s\n+%s\n+%s\n' \
    "$elision_first" "$elision_second" "$elision_added_first" "$elision_added_second" > "$elision_diff"
printf 'export const currentValue = source.current;\n' > "$elision_root/src/ordered.ts"
for elision_side in removed added; do
    elision_a="$elision_first"; elision_b="$elision_second"
    if [[ "$elision_side" == added ]]; then
        elision_a="$elision_added_first"; elision_b="$elision_added_second"
    fi
    for elision_order in ordered reversed; do
        elision_quote="$elision_a ... $elision_b"
        if [[ "$elision_order" == reversed ]]; then
            elision_quote="$elision_b ... $elision_a"
        fi
        elision_verified=0
        [[ "$elision_order" != ordered ]] || elision_verified=1
        test_case "elided source order in $elision_side diff: $elision_order"
        elision_response="$(_resp "The $elision_side code in src/ordered.ts:1 reads \`$elision_quote\`.")"
        r="$(COUNCIL_CONTEXT_FILES=("$elision_diff"); council_response_quote_verification_json "$elision_response" "$elision_root")"
        if jq -e --argjson verified "$elision_verified" --arg side "$elision_side" '
            .quotes_checked == 1 and .quotes_verified == $verified
            and .quotes_unverified == (1 - $verified)
            and .["quotes_verified_in_diff_" + $side] == $verified
            and .fabricated == ($verified == 0)' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi
    done
done
# End elided source order controls.

test_case "a quote far beyond the proximity window of every citation is not checked"
pad="$(head -c 1700 /dev/zero | tr '\0' 'x')"
distant="$(_resp "src/pricing.ts:2 is fine. $pad \`$FAKE\`
VERDICT: APPROVE")"
if [[ "$(_field "$distant" quotes_checked)" == 0 ]]; then test_pass; else test_fail "report: $(_report "$distant")"; fi

test_case "a quoted citation is not treated as a code quote"
quotedcite="$(_resp "See \`src/pricing.ts:2 handles the missing price case\` for details.
VERDICT: APPROVE")"
if [[ "$(_field "$quotedcite" quotes_checked)" == 0 ]]; then test_pass; else test_fail "report: $(_report "$quotedcite")"; fi

test_case "a cited file too large to read is unverifiable, never fabricated"
python3 -c 'import sys; open(sys.argv[1], "w").write("// big\n" * 260000)' "$ROOT/src/huge.ts"
huge="$(_resp "src/huge.ts:2 contains \`$FAKE\` today.
VERDICT: APPROVE")"
r="$(_report "$huge")"
if jq -e '.quotes_checked == 1 and .quotes_unverifiable == 1 and .quotes_unverified == 0 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "a quote attributed to a too-large file stays unverifiable beside a readable citation"
# The readable src/pricing.ts must not make the unreadable bound file count as
# checked: the quote may well be real in src/huge.ts.
hugemix="$(_resp "src/pricing.ts:2 is the call site.

src/huge.ts:2 reads \`$FAKE\`.
VERDICT: APPROVE")"
r="$(_report "$hugemix")"
if jq -e '.citations == 2 and .quotes_checked == 1 and .quotes_unverifiable == 1 and .quotes_unverified == 0
          and .quotes_attributed_unverified == 0 and .fabricated == false' <<< "$r" >/dev/null &&
   ! council_response_is_blind "$hugemix" "$ROOT"; then test_pass; else test_fail "report: $r"; fi

test_case "an unreadable cited file is unverifiable and does not crash"
printf 'const secret = 1;\n' > "$ROOT/src/locked.ts"
chmod 000 "$ROOT/src/locked.ts"
locked="$(_resp "src/locked.ts:1 contains \`$FAKE\` today.
VERDICT: APPROVE")"
if [[ -r "$ROOT/src/locked.ts" ]]; then
    chmod 644 "$ROOT/src/locked.ts"
    test_skip "running with privileges that bypass file modes"
else
    r="$(_report "$locked")"
    chmod 644 "$ROOT/src/locked.ts"
    if jq -e '.quotes_unverifiable == 1 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi
fi

test_case "OCTOPUS_COUNCIL_QUOTE_VERIFY=0 disables the check"
if ! OCTOPUS_COUNCIL_QUOTE_VERIFY=0 council_response_quotes_fabricated "$fab" "$ROOT"; then test_pass; else test_fail "opt-out ignored"; fi

test_case "an overflowing citation cannot hide an invented quote behind a verifier crash"
overflow="$(_resp "src/pricing.ts:2 reads \`$FAKE\`.

Noise src/ghost.ts:$(printf '%05000d' 0 | tr 0 9)
VERDICT: APPROVE")"
record="$(council_contribution_record_json "$overflow" "$ROOT" sha256:overflow)"
if jq -e '.validation_result == "invalid-ungrounded"' <<< "$record" >/dev/null &&
   council_response_is_blind "$overflow" "$ROOT"; then test_pass; else test_fail "verifier crash granted grounding: $record"; fi

for failure_output in empty partial; do
    test_case "a verifier process failure with $failure_output stdout rejects a real citation"
    failure_response="$(_resp "src/pricing.ts:2 reads \`$REAL_NEAR\`.
VERDICT: APPROVE")"
    failure_record="$(
        python3() {
            if [[ "${1:-}" == -I ]]; then
                [[ "$failure_output" != partial ]] || printf '{"verification_failed":false'
                return 1
            fi
            command python3 "$@"
        }
        council_contribution_record_json "$failure_response" "$ROOT" sha256:process-failure
    )" || failure_record='{}'
    if jq -e '.validation_result == "invalid-ungrounded" and .grounding.verification_failed == true
            and .grounding.fabricated == false' <<< "$failure_record" >/dev/null; then
        test_pass
    else
        test_fail "failed verifier granted grounding or returned malformed JSON: $failure_record"
    fi
done

test_case "missing Python preserves the legacy unverified prose fallback"
missing_python="$(
    # Bash 3.2 can retain a cached command with a function-local PATH override.
    # Clear it in this subshell to simulate an actually unavailable executable.
    PATH=/nonexistent
    hash -r
    council_response_quote_verification_json "$fab" "$ROOT"
)"
missing_record="$(
    command() {
        [[ "$*" != '-v python3' ]] || return 1
        builtin command "$@"
    }
    council_contribution_record_json "$noquote" "$ROOT" sha256:missing-python
)"
if jq -e '(.verification_failed // false) == false and .citations == 0 and .fabricated == false' <<< "$missing_python" >/dev/null &&
   jq -e '.validation_result == "valid-unverified" and .evidence_paths == []' <<< "$missing_record" >/dev/null; then
    test_pass
else
    test_fail "missing Python changed availability or granted validated evidence: $missing_python $missing_record"
fi

for malformed_report in 'not-json' '{"fabricated":false} {"fabricated":false}' 'null'; do
    test_case "an invalid precomputed grounding report cannot grant approval"
    if council_response_quotes_fabricated "$fab" "$ROOT" "$malformed_report"; then
        test_pass
    else
        test_fail "invalid grounding report was accepted: $malformed_report"
    fi
done

test_case "the explicit quote-verification opt-out still bypasses failure reports"
if ! OCTOPUS_COUNCIL_QUOTE_VERIFY=0 council_response_quotes_fabricated "$fab" "$ROOT" '{"verification_failed":true}'; then
    test_pass
else
    test_fail "verification failure ignored the explicit opt-out"
fi

test_case "missing evidence root reports nothing and never fabricates"
if [[ "$(council_response_quote_verification_json "$fab" "$ROOT/does-not-exist" | jq -r '.fabricated')" == false ]] &&
   ! council_response_quotes_fabricated "$fab" ""; then test_pass; else test_fail "no-root path fabricated"; fi

# The #2997 shape: a full-length, confident APPROVE with several real path:line
# refs whose quoted "source" is invented. The old validator counted it.
test_case "#2997 replay: long APPROVE with real refs and invented quotes is not counted"
replay="$(_resp "## Review

The pricing path is correct and fully tested.

1. src/pricing.ts:2 — the price is resolved through \`const base = await fetchCabinPrice(cabin.id, { cache: true });\` which memoizes the lookup and prevents duplicate requests.
2. src/pricing.ts:4 — taxes are applied via \`return applyTaxes(base, sailing.portFees, { region: sailing.region });\` so regional fees propagate.
3. src/pricing.ts:86 — discounts come from \`DISCOUNT_RULES.loyaltyTier.multiplier * base\` and the contract is honored.

All tests pass, the behavior matches the plan, and the endpoint contract is unchanged. No regressions found in the component or schema.

VERDICT: APPROVE")"
r="$(_report "$replay")"
if jq -e '.citations == 3 and .quotes_checked == 3 and .quotes_verified == 0 and .fabricated == true' <<< "$r" >/dev/null &&
   ! council_response_is_substantive "$replay" "$ROOT" &&
   [[ "$(council_contribution_record_json "$replay" "$ROOT" sha256:t | jq -r '.validation_result')" == invalid-ungrounded ]]; then
    test_pass
else
    test_fail "report: $r"
fi

# ── Removed-code quotes (reviewers quote deleted lines: "this guard was removed").
# That code exists in no working-tree file, so it is checked against the removed
# (and added) side of the reviewed diff before being called fabricated.
GROOT="$(mktemp -d "${TEST_TMP_DIR:-/tmp}/quote-git.XXXXXX")"
mkdir -p "$GROOT/src"
GUARD='if (!sailing.isBookable) throw new BookingClosedError(sailing.id);'
printf 'export function book(sailing, cabin) {\n  %s\n  return reserve(sailing, cabin);\n}\n' "$GUARD" > "$GROOT/src/book.ts"
git -C "$GROOT" init -q
git -C "$GROOT" add src/book.ts
git -C "$GROOT" -c user.email=t@example.invalid -c user.name=t commit -q -m base
printf 'export function book(sailing, cabin) {\n  return reserve(sailing, cabin);\n}\n' > "$GROOT/src/book.ts"
_greport() { council_response_quote_verification_json "$1" "$GROOT"; }

test_case "removed-line quote (git diff HEAD) verifies via the diff's removed side and is not blind"
removed_only="$(_resp "At src/book.ts:2 the guard \`$GUARD\` was removed, so closed sailings can be booked.
VERDICT: REVISE")"
r="$(_greport "$removed_only")"
if jq -e '.quotes_checked == 1 and .quotes_verified == 1 and .quotes_verified_in_diff_removed == 1 and .fabricated == false
          and (.diff_sources | index("git-diff:HEAD"))' <<< "$r" >/dev/null &&
   ! council_response_is_blind "$removed_only" "$GROOT"; then test_pass; else test_fail "report: $r"; fi

test_case "fabricated quote in the same diff-bearing repo is still blind"
git_fab="$(_resp "At src/book.ts:2 the code \`if (sailing.status === 'closed') return refundAll(cabin);\` handles closures.
VERDICT: APPROVE")"
r="$(_greport "$git_fab")"
if jq -e '.quotes_checked == 1 and .quotes_verified == 0 and .quotes_unverified == 1 and .fabricated == true' <<< "$r" >/dev/null &&
   council_response_is_blind "$git_fab" "$GROOT"; then test_pass; else test_fail "report: $r"; fi

test_case "mixed: a removed-line quote plus a fabricated quote keeps the seat grounded"
git_mixed="$(_resp "src/book.ts:2 dropped \`$GUARD\` and now calls \`if (sailing.status === 'closed') return refundAll(cabin);\`.
VERDICT: REVISE")"
r="$(_greport "$git_mixed")"
if jq -e '.quotes_checked == 2 and .quotes_verified_in_diff_removed == 1 and .quotes_unverified == 1 and .fabricated == false' <<< "$r" >/dev/null &&
   ! council_response_is_blind "$git_mixed" "$GROOT"; then test_pass; else test_fail "report: $r"; fi

# One real diff line must not verify an otherwise invented multi-line quote.
for diff_side in removed added; do
    reviewed="$TEST_TMP_DIR/threshold-$diff_side.diff"
    sign=-
    [[ "$diff_side" != added ]] || sign=+
    printf 'diff --git a/src/book.ts b/src/book.ts\n--- a/src/book.ts\n+++ b/src/book.ts\n@@ -1,3 +1,3 @@\n%s%s\n%s%s\n' \
        "$sign" "$GUARD" "$sign" 'const closedBookings = sailing.closedBookings ?? [];' > "$reviewed"
    for quote_kind in ts diff; do
        [[ "$quote_kind" != diff || "$diff_side" == removed ]] || continue
        prefix=""
        [[ "$quote_kind" != diff ]] || prefix=-
        for genuine_lines in 1 2; do
            test_case "a $quote_kind quote with $genuine_lines real $diff_side lines out of three"
            second='const inventedReservations = fetchUnknownReservations(sailing);'
            [[ "$genuine_lines" != 2 ]] || second='const closedBookings = sailing.closedBookings ?? [];'
            f="$(_resp "src/book.ts:2 reads:
\`\`\`$quote_kind
$prefix$GUARD
$prefix$second
${prefix}return approveImaginaryRefund(sailing, cabin);
\`\`\`
VERDICT: APPROVE")"
            # The citation must resolve in the selected evidence root.
            r="$(COUNCIL_CONTEXT_FILES=("$reviewed"); _greport "$f")"
            if [[ "$genuine_lines" == 1 ]]; then
                if ! jq -e '.quotes_verified == 0 and .quotes_unverified == 1 and .fabricated == true' <<< "$r" >/dev/null; then
                    test_fail "one real $diff_side line verified a $quote_kind block: $r"
                    continue
                fi
            elif ! jq -e --arg field "quotes_verified_in_diff_$diff_side" '.quotes_verified == 1 and .[$field] == 1 and .quotes_partial == 1 and .fabricated == false' <<< "$r" >/dev/null; then
                test_fail "two real $diff_side lines failed to verify a $quote_kind block: $r"
                continue
            fi
            test_pass
        done
    done
done

# A fence partial on the removed side but exact on the added side is not
# partial; the removed side still decides where it verified.
test_case "#3247: a fence exact on the added side is not partial"
both_sides="$TEST_TMP_DIR/both-sides.diff"
window='const refundWindow = sailing.refundWindowDays ?? 14;'
printf 'diff --git a/src/book.ts b/src/book.ts\n--- a/src/book.ts\n+++ b/src/book.ts\n@@ -1,2 +1,3 @@\n-%s\n-%s\n+%s\n+%s\n+%s\n' \
    "$GUARD" 'const closedBookings = sailing.closedBookings ?? [];' \
    "$GUARD" 'const closedBookings = sailing.closedBookings ?? [];' "$window" > "$both_sides"
f="$(_resp "src/book.ts:2 reads:
\`\`\`ts
$GUARD
const closedBookings = sailing.closedBookings ?? [];
$window
\`\`\`
VERDICT: APPROVE")"
r="$(COUNCIL_CONTEXT_FILES=("$both_sides"); _greport "$f")"
if jq -e '.quotes_verified == 1 and .quotes_verified_in_diff_removed == 1 and .quotes_partial == 0' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "an oversized response reports the limit and cannot count as grounded"
oversized="$TEST_TMP_DIR/oversized-response.md"
python3 - "$oversized" "$FAKE" <<'PY_OVERSIZED'
import sys
with open(sys.argv[1], "w") as handle:
    handle.write("src/pricing.ts:2 reads `%s`.\n" % sys.argv[2])
    handle.write("Padding " * 150000)
    handle.write("\nVERDICT: APPROVE\n")
PY_OVERSIZED
r="$(_report "$oversized")"
record="$(council_contribution_record_json "$oversized" "$ROOT" sha256:oversized)"
if jq -e '.response_oversized == true and .fabricated == false and .quotes_verified == 0' <<< "$r" >/dev/null &&
   jq -e '.validation_result == "invalid-ungrounded" and .evidence_paths == [] and .grounding.response_oversized == true' <<< "$record" >/dev/null &&
   ! council_response_is_substantive "$oversized" "$ROOT"; then
    test_pass
else
    test_fail "oversized report: $r record: $record"
fi

test_case "OCTOPUS_COUNCIL_DIFF_BASE selects a committed base (removal already committed)"
git -C "$GROOT" -c user.email=t@example.invalid -c user.name=t commit -q -am remove-guard
r_head="$(_greport "$removed_only")"
r_base="$(OCTOPUS_COUNCIL_DIFF_BASE=HEAD~1 _greport "$removed_only")"
if jq -e '.quotes_verified == 0' <<< "$r_head" >/dev/null &&
   jq -e '.quotes_verified_in_diff_removed == 1 and .fabricated == false and (.diff_sources | index("git-diff:HEAD~1"))' <<< "$r_base" >/dev/null; then
    test_pass
else
    test_fail "head: $r_head base: $r_base"
fi

for unavailable_base in missing-review-revision --invalid-option; do
    test_case "an unavailable diff base preserves uncertainty: $unavailable_base"
    f="$(_resp "src/book.ts:2 reads \`$GUARD\`.
VERDICT: REVISE")"
    r="$(OCTOPUS_COUNCIL_DIFF_BASE="$unavailable_base" _greport "$f")"
    if jq -e '.diff_unavailable == true and .diff_truncated == false and .quotes_unverifiable_diff_incomplete == 1
              and .quotes_attributed_unverified == 0 and .quotes_unverified == 0 and .fabricated == false' <<< "$r" >/dev/null &&
       ! OCTOPUS_COUNCIL_DIFF_BASE="$unavailable_base" council_response_quotes_fabricated "$f" "$GROOT"; then
        test_pass
    else
        test_fail "failed diff became definitive negative evidence: $r"
    fi
done

test_case "a --context-file diff supplies the removed side (non-git root, fenced '-' lines)"
ctx_diff="$TEST_TMP_DIR/reviewed.diff"
printf 'diff --git a/src/pricing.ts b/src/pricing.ts\n--- a/src/pricing.ts\n+++ b/src/pricing.ts\n@@ -2,2 +2,1 @@\n-  if (cabin.soldOut) return { price: null, reason: "sold-out" };\n+  const base = cabin.basePrice ?? sailing.defaultPrice;\n' > "$ctx_diff"
ctx_resp="$(_resp "src/pricing.ts:2 lost its sold-out guard:
\`\`\`diff
-  if (cabin.soldOut) return { price: null, reason: \"sold-out\" };
\`\`\`
VERDICT: REVISE")"
r="$(COUNCIL_CONTEXT_FILES=("$ctx_diff"); _report "$ctx_resp")"
if jq -e '.quotes_checked == 1 and .quotes_verified_in_diff_removed == 1 and .fabricated == false and (.diff_sources | index("context-file"))' <<< "$r" >/dev/null; then
    test_pass
else
    test_fail "report: $r"
fi

test_case "invented all-removed diff fences are fabricated when real diff evidence exists"
invented_removed="$(_resp "src/pricing.ts:2 reads:
\`\`\`diff
- $FAKE
\`\`\`
VERDICT: APPROVE")"
r="$(COUNCIL_CONTEXT_FILES=("$ctx_diff"); _report "$invented_removed")"
if jq -e '.quotes_checked == 1 and .quotes_unverified == 1 and .quotes_attributed_unverified == 1
          and .quotes_unverifiable_command == 0 and .fabricated == true' <<< "$r" >/dev/null; then
    test_pass
else
    test_fail "report: $r"
fi

test_case "a source quote present in another cited file follows the grounding contract"
cross_root="$(mktemp -d "$TEST_TMP_DIR/cross-cited.XXXXXX")"
mkdir -p "$cross_root/src"
cp "$ROOT/src/pricing.ts" "$cross_root/src/pricing.ts"
printf '%s\n' "$FAKE" > "$cross_root/src/elsewhere.ts"
cross_cited="$(_resp "src/pricing.ts:2 reads \`$FAKE\`.

See src/elsewhere.ts:1 for related evidence.
VERDICT: APPROVE")"
r="$(council_response_quote_verification_json "$cross_cited" "$cross_root")"
if jq -e '.citations == 2 and .quotes_verified == 1 and .quotes_attributed_unverified == 0
          and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "a quote found only on the diff's added side verifies (working tree vs cited file timing)"
printf 'diff --git a/src/pricing.ts b/src/pricing.ts\n@@ -4,1 +4,1 @@\n-  return applyTaxes(base, sailing.portFees);\n+  return applyTaxes(base, sailing.portFees, sailing.region);\n' > "$ctx_diff"
added_resp="$(_resp "src/pricing.ts:4 now does \`return applyTaxes(base, sailing.portFees, sailing.region);\` correctly.
VERDICT: APPROVE")"
r="$(COUNCIL_CONTEXT_FILES=("$ctx_diff"); _report "$added_resp")"
if jq -e '.quotes_verified == 1 and .quotes_verified_in_diff_added == 1 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "a non-diff context file's '- ' bullets are not treated as removed code"
ctx_plan="$TEST_TMP_DIR/plan.md"
printf '# Plan\n\n- const base = await fetchCabinPrice(cabin.id, { cache: true });\n' > "$ctx_plan"
r="$(COUNCIL_CONTEXT_FILES=("$ctx_plan"); _report "$fab")"
if jq -e '.fabricated == true and .diff_sources == []' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

# sail-cruisey #3247 chunk A: a seat describing a test input it built is not
# quoting the file it cites. Its only checked quote failed, so the seat was
# fabricated and blind despite eight real citations.
test_case "#3247: an input the seat constructed is its own, not a quote"
r="$(_report "$(_resp 'At src/pricing.ts:2, a 360-character row constructed as `"Order total $5.00".padEnd(80, " ") + "invalid".repeat(40)` becomes a valid total.
VERDICT: REVISE')")"
if jq -e '.quotes_unverifiable_proposed == 1 and .quotes_unverified == 0 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "#3247: an invented quote the citation reads is still fabricated"
r="$(_report "$(_resp "src/pricing.ts:2 reads \`$FAKE\` and the row is constructed later.
VERDICT: REVISE")")"
if jq -e '.quotes_attributed_unverified == 1 and .fabricated == true' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

# sail-cruisey #3247 chunk C: a fence of mostly real lines verifies at the
# two-thirds threshold even when one line is invented. The report now counts
# such a fence as partial, without changing the verdict.
test_case "#3247: a fence that verifies with an invented line is counted as partial"
r="$(_report "$(_resp "src/pricing.ts:1 reads:

\`\`\`ts
export function priceFor(cabin, sailing) {
  const base = cabin.basePrice ?? sailing.defaultPrice;
  if (!base) return null;
  $FAKE
  return applyTaxes(base, sailing.portFees);
\`\`\`

VERDICT: APPROVE")")"
if jq -e '.quotes_verified == 1 and .quotes_partial == 1 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "#3247: an exact fence is not partial"
r="$(_report "$(_resp "src/pricing.ts:1 reads:

\`\`\`ts
export function priceFor(cabin, sailing) {
  const base = cabin.basePrice ?? sailing.defaultPrice;
  if (!base) return null;
  return applyTaxes(base, sailing.portFees);
\`\`\`

VERDICT: APPROVE")")"
if jq -e '.quotes_verified == 1 and .quotes_partial == 0' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

# A content verb before the proposal wording keeps the citation's claim: the
# seat says the file holds this code. A first-person subject between them
# still marks the seat's own input.
test_case "#3247: a citation that contains code built as an invented quote is fabricated"
r="$(_report "$(_resp "src/pricing.ts:2 contains the code built as \`$FAKE\` today.
VERDICT: REVISE")")"
if jq -e '.quotes_attributed_unverified == 1 and .quotes_unverifiable_proposed == 0 and .fabricated == true' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "#3247: an input the seat itself built after a content verb stays its own"
r="$(_report "$(_resp 'src/pricing.ts:2 reads the base price from a row I constructed as `"Order total $5.00".padEnd(80, " ") + "invalid".repeat(40)` for this test.
VERDICT: REVISE')")"
if jq -e '.quotes_unverifiable_proposed == 1 and .quotes_unverified == 0 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "#3247: an invented short line in a fence that verifies is counted as partial"
r="$(_report "$(_resp "src/pricing.ts:1 reads:

\`\`\`ts
  const base = cabin.basePrice ?? sailing.defaultPrice;
  return true;
  return applyTaxes(base, sailing.portFees);
\`\`\`

VERDICT: APPROVE")")"
if jq -e '.quotes_verified == 1 and .quotes_partial == 1 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "#3247: a real short line in a fence that verifies is not partial"
r="$(_report "$(_resp "src/pricing.ts:1 reads:

\`\`\`ts
  const base = cabin.basePrice ?? sailing.defaultPrice;
  return applyTaxes(base, sailing.portFees);
}
\`\`\`

VERDICT: APPROVE")")"
if jq -e '.quotes_verified == 1 and .quotes_partial == 0' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "#3247: an invented short line between elision markers is counted as partial"
r="$(_report "$(_resp "src/pricing.ts:1 reads:

\`\`\`ts
  const base = cabin.basePrice ?? sailing.defaultPrice;
  ...
  return true;
  ...
  return applyTaxes(base, sailing.portFees);
\`\`\`

VERDICT: APPROVE")")"
if jq -e '.quotes_verified == 1 and .quotes_partial == 1 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "#3247: an elided fence of real lines is not partial"
r="$(_report "$(_resp "src/pricing.ts:1 reads:

\`\`\`ts
  const base = cabin.basePrice ?? sailing.defaultPrice;
  ...
  return applyTaxes(base, sailing.portFees);
}
\`\`\`

VERDICT: APPROVE")")"
if jq -e '.quotes_verified == 1 and .quotes_partial == 0' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "#3247: a blockquote with an unmatched line is not a partial fence"
r="$(_report "$(_resp "src/pricing.ts:1 reads:

> const base = cabin.basePrice ?? sailing.defaultPrice;
> const invented = fetchUnknownReservations(sailing);
> return applyTaxes(base, sailing.portFees);

VERDICT: APPROVE")")"
if jq -e '.quotes_verified == 1 and .quotes_partial == 0' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "#3247: a fence complete in a later cited file is not partial"
PROOT="$(mktemp -d "${TEST_TMP_DIR:-/tmp}/quote-partial.XXXXXX")"
mkdir -p "$PROOT/src"
printf '%s\n' 'export function priceFor(cabin, sailing) {' '  const base = cabin.basePrice ?? sailing.defaultPrice;' \
    '  return applyTaxes(base, sailing.portFees);' '}' > "$PROOT/src/a.ts"
printf '%s\n' 'export function priceFor(cabin, sailing) {' '  const base = cabin.basePrice ?? sailing.defaultPrice;' \
    '  const fees = sailing.portFees.filter(Boolean);' '  return applyTaxes(base, sailing.portFees);' '}' > "$PROOT/src/b.ts"
r="$(council_response_quote_verification_json "$(_resp "src/a.ts:1 and src/b.ts:1 read:

\`\`\`ts
  const base = cabin.basePrice ?? sailing.defaultPrice;
  const fees = sailing.portFees.filter(Boolean);
  return applyTaxes(base, sailing.portFees);
\`\`\`

VERDICT: APPROVE")" "$PROOT")"
if jq -e '.quotes_verified == 1 and .quotes_partial == 0' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "no diff available: a quote the seat says was removed is unverifiable, not fabricated"
claimed="$(_resp "At src/pricing.ts:2 the check \`if (cabin.soldOut) return { price: null };\` was deleted in this change.
VERDICT: REVISE")"
r="$(_report "$claimed")"
if jq -e '.quotes_unverifiable == 1 and .quotes_unverifiable_claimed_removed == 1 and .quotes_unverified == 0 and .fabricated == false' <<< "$r" >/dev/null &&
   ! council_response_is_blind "$claimed" "$ROOT"; then test_pass; else test_fail "report: $r"; fi

test_case "summary grounding carries the new diff counters"
record="$(council_contribution_record_json "$removed_only" "$GROOT" sha256:t)"
if jq -e '.grounding | has("quotes_verified_in_diff_removed") and has("quotes_verified_in_diff_added") and has("quotes_unverifiable_claimed_removed") and has("diff_sources")' <<< "$record" >/dev/null &&
   jq -e 'has("quotes_verified_in_diff_removed")' <<< "$COUNCIL_EMPTY_GROUNDING_JSON" >/dev/null; then test_pass; else test_fail "record: $record"; fi

# ── sail-cruisey #3005: quotes the seat attributes to a citation must be in the
# cited file. Real quotes elsewhere in the body no longer excuse invented ones.
RROOT="$(mktemp -d "${TEST_TMP_DIR:-/tmp}/quote-3005.XXXXXX")"
mkdir -p "$RROOT/functions-v2/_lib"
{
    printf 'sync AS (\n  UPDATE cruises c\n'
    printf '  SET royalup_price = (mut.bid_amount * 2)::numeric(14,2),\n'
    printf '      royalup_cabin_type = mut.target_category\n  FROM mut\n)\n'
} > "$RROOT/functions-v2/_lib/upgrade-bid-royalup-sql.ts"
{
    printf 'export function acceptedRoyalupBidSql(cruiseAlias: string): string {\n'
    printf '  return `EXISTS (\n    SELECT 1 FROM upgrade_bids ub\n'
    printf '    WHERE ub.cruise_id = ${cruiseAlias}.id\n'
    printf '      AND ub.household_id = ${cruiseAlias}.household_id\n'
    printf "      AND ub.program_type = 'royalup'\n"
    printf "      AND ub.status = 'accepted'\n  )\`;\n}\n"
} > "$RROOT/functions-v2/_lib/payment-plan.ts"
_rreport() { council_response_quote_verification_json "$1" "$RROOT"; }

test_case "#3005: an invented block under a 'Checked Source Citations' entry is fabricated despite real quotes elsewhere"
r3005="$(_resp "The sync writes \`SET royalup_price = (mut.bid_amount * 2)::numeric(14,2),\` per functions-v2/_lib/upgrade-bid-royalup-sql.ts:3 and scopes by \`WHERE ub.cruise_id = \${cruiseAlias}.id\` in functions-v2/_lib/payment-plan.ts:4.

### Checked Source Citations

1. [functions-v2/_lib/upgrade-bid-royalup-sql.ts:3](file:///tmp/ws/functions-v2/_lib/upgrade-bid-royalup-sql.ts#L3)
   \`\`\`typescript
   c.royalup_price = ub.bid_amount * 2,
   \`\`\`

VERDICT: APPROVE")"
r="$(_rreport "$r3005")"
if jq -e '.quotes_verified >= 2 and .quotes_attributed == 1 and .quotes_attributed_unverified == 1 and .fabricated == true' <<< "$r" >/dev/null &&
   jq -e '.unverified_samples == []' <<< "$r" >/dev/null &&
   council_response_is_blind "$r3005" "$RROOT"; then test_pass; else test_fail "report: $r"; fi

test_case "#3005: a reconstructed block where only generic lines are real does not verify"
recon="$(_resp "Checked:
functions-v2/_lib/payment-plan.ts:1
\`\`\`typescript
export function acceptedRoyalupBidSql(alias: string = \"c\"): string {
  return \`EXISTS (
    SELECT 1 FROM upgrade_bids ub
    WHERE ub.cruise_id = \${alias}.id
      AND ub.household_id = \${alias}.household_id
      AND ub.status = 'accepted'
\`\`\`
VERDICT: APPROVE")"
r="$(_rreport "$recon")"
if jq -e '.quotes_checked == 1 and .quotes_verified == 0 and .quotes_attributed_unverified == 1 and .fabricated == true' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "#3005: a verbatim multi-line block under its citation verifies"
verbatim="$(_resp "functions-v2/_lib/payment-plan.ts:3
\`\`\`typescript
    SELECT 1 FROM upgrade_bids ub
    WHERE ub.cruise_id = \${cruiseAlias}.id
      AND ub.household_id = \${cruiseAlias}.household_id
\`\`\`
VERDICT: APPROVE")"
r="$(_rreport "$verbatim")"
if jq -e '.quotes_verified == 1 and .quotes_attributed == 1 and .quotes_attributed_unverified == 0 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "#3005: a proposed replacement under a citation is not held to the file's current text"
proposal="$(_resp "Real today: \`SET royalup_price = (mut.bid_amount * 2)::numeric(14,2),\` at functions-v2/_lib/upgrade-bid-royalup-sql.ts:3.
This should become, at functions-v2/_lib/upgrade-bid-royalup-sql.ts:3:
\`\`\`typescript
SET royalup_price = (mut.bid_amount * mut.guest_count)::numeric(14,2),
\`\`\`
VERDICT: REVISE")"
r="$(_rreport "$proposal")"
if jq -e '.quotes_attributed_unverified == 0 and .quotes_unverifiable_proposed == 1 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

# ── sail-cruisey #3032: grounded seats flagged blind.
HROOT="$(mktemp -d "${TEST_TMP_DIR:-/tmp}/quote-3032.XXXXXX")"
mkdir -p "$HROOT/.todo/claude-octopus/3032" "$HROOT/.todo/claude-octopus/3005" "$HROOT/functions-v2/_lib" "$HROOT/scripts"
{
    printf '# Plan\n\n'
    printf -- '- Scrub with `span.attributes = redact(span.attributes)` SEPARATELY.\n'
    printf -- '- Resolver: `new NodeClient({ ...captured, integrations: [], transport: makeTransport })`.\n'
} > "$HROOT/.todo/claude-octopus/3032/phase-3-plan.md"
printf '# Other plan\n' > "$HROOT/.todo/claude-octopus/3005/phase-3-plan.md"
printf 'export function handler(request) {\n  const extra = { url: request.url, method: request.method };\n  return send(extra);\n}\n' > "$HROOT/functions-v2/_lib/handler.ts"
printf 'const ALLOWED_ADVISORIES = [\n  "GHSA-xxxx",\n];\nconst out = execSync("npm audit --omit=dev --audit-level=high --json 2>/dev/null");\n' > "$HROOT/scripts/audit-check.mjs"
_hreport() { council_response_quote_verification_json "$1" "$HROOT"; }
PLAN32="$HROOT/.todo/claude-octopus/3032/phase-3-plan.md"

test_case "#3032: a bare plan citation resolves to the attached context file under hidden .todo/"
plancite="$(_resp "### Checked Citations

phase-3-plan.md:3
\`span.attributes = redact(span.attributes)\` SEPARATELY — never the whole span.

functions-v2/_lib/handler.ts:2 is the URL attachment.

VERDICT: APPROVE")"
r="$(COUNCIL_CONTEXT_FILES=("$PLAN32"); _hreport "$plancite")"
blind=no; (COUNCIL_CONTEXT_FILES=("$PLAN32"); council_response_is_blind "$plancite" "$HROOT") && blind=yes
if jq -e '.citations == 2 and .quotes_verified == 1 and .quotes_attributed == 1 and .fabricated == false' <<< "$r" >/dev/null && [[ "$blind" == no ]]; then
    test_pass
else
    test_fail "blind=$blind report: $r"
fi

test_case "#3032: without the context file the ambiguous bare plan name stays unresolved, never fabricated"
r="$(_hreport "$plancite")"
if jq -e '.citations == 1 and .citations_unresolved == 1 and .quotes_unverifiable_unresolved_citation == 1 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "#3032: a path suffix under a hidden directory resolves uniquely"
hidden="$(_resp "claude-octopus/3032/phase-3-plan.md:4 reads \`new NodeClient({ ...captured, integrations: [], transport: makeTransport })\`.
VERDICT: APPROVE")"
r="$(_hreport "$hidden")"
if jq -e '.citations == 1 and .quotes_verified == 1 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "#3032: HTML-escaped '&gt;' blockquotes under a citation are decoded and verified"
escaped="$(_resp "- \`functions-v2/_lib/handler.ts:2\`:
  &gt; const extra = { url: request.url, method: request.method };

VERDICT: APPROVE")"
r="$(_hreport "$escaped")"
if jq -e '.quotes_checked == 1 and .quotes_verified == 1 and .quotes_attributed == 1 and .fabricated == false' <<< "$r" >/dev/null &&
   ! council_response_is_blind "$escaped" "$HROOT"; then test_pass; else test_fail "report: $r"; fi

for block_style in single escaped multiline; do
    test_case "a real $block_style blockquote with inline formatting stays grounded"
    prefix='>'
    [[ "$block_style" != escaped ]] || prefix='&gt;'
    quoted="$prefix \`$REAL_NEAR\`"
    [[ "$block_style" != multiline ]] || quoted="$quoted
> \`return applyTaxes(base, sailing.portFees);\`"
    formatted="$(_resp "src/pricing.ts:2 reads:
$quoted

VERDICT: APPROVE")"
    r="$(_report "$formatted")"
    record="$(council_contribution_record_json "$formatted" "$ROOT" sha256:blockquote)"
    if jq -e '.quotes_checked == 1 and .quotes_verified == 1 and .quotes_attributed_unverified == 0 and .fabricated == false' <<< "$r" >/dev/null &&
       jq -e '.validation_result == "valid-grounded"' <<< "$record" >/dev/null &&
       ! council_response_is_blind "$formatted" "$ROOT"; then
        test_pass
    else
        test_fail "real formatted blockquote rejected: $r $record"
    fi
done

test_case "an invented formatted blockquote remains fabricated beside a real quote"
formatted_fake="$(_resp "src/pricing.ts:2 reads \`$REAL_NEAR\`.

src/pricing.ts:2 reads:
> \`$FAKE\`

VERDICT: APPROVE")"
r="$(_report "$formatted_fake")"
if jq -e '.quotes_verified > 0 and .quotes_attributed_unverified > 0 and .fabricated == true' <<< "$r" >/dev/null &&
   council_response_is_blind "$formatted_fake" "$ROOT"; then
    test_pass
else
    test_fail "invented formatted blockquote gained grounding: $r"
fi

test_case "literal source backticks inside a blockquote remain source content"
printf 'export const message = `hello from source`;\n' > "$ROOT/src/literal.ts"
literal="$(_resp 'src/literal.ts:1 reads:
> export const message = `hello from source`;

VERDICT: APPROVE')"
r="$(_report "$literal")"
if jq -e '.quotes_checked == 1 and .quotes_verified == 1 and .quotes_attributed_unverified == 0 and .fabricated == false' <<< "$r" >/dev/null &&
   ! council_response_is_blind "$literal" "$ROOT"; then
    test_pass
else
    test_fail "literal source backticks were changed: $r"
fi

test_case "nested inline formatting does not exhaust the quote-unit budget"
formatted_budget="$(_resp "$(for i in $(seq 1 130); do
    printf 'src/pricing.ts:2 reads:\n> `%s`\n\n' "$REAL_NEAR"
done)
VERDICT: APPROVE")"
r="$(_report "$formatted_budget")"
if jq -e '.quotes_checked == 130 and .quotes_verified == 130 and .quotes_omitted == 0 and .fabricated == false' <<< "$r" >/dev/null &&
   ! council_response_is_blind "$formatted_budget" "$ROOT"; then
    test_pass
else
    test_fail "nested formatting consumed duplicate quote units: $r"
fi

for proposal_gap in $'\n\n' $'\n \t\n\n'; do
    test_case "blank lines preserve the nearest proposal lead-in"
    spaced_proposal="$(_resp "src/pricing.ts:2 should become:${proposal_gap}\`\`\`ts
$FAKE
\`\`\`
VERDICT: REVISE")"
    r="$(_report "$spaced_proposal")"
    if jq -e '.quotes_unverifiable_proposed == 1 and .quotes_unverified == 0 and .fabricated == false' <<< "$r" >/dev/null &&
       ! council_response_is_blind "$spaced_proposal" "$ROOT"; then
        test_pass
    else
        test_fail "proposed code was labeled fabricated: $r"
    fi
done

test_case "an earlier proposal cannot excuse a later current-source claim"
later_claim="$(_resp "We should revise this path.

src/pricing.ts:2 reads:


\`\`\`ts
$FAKE
\`\`\`
VERDICT: APPROVE")"
r="$(_report "$later_claim")"
if jq -e '.quotes_unverifiable_proposed == 0 and .quotes_unverified == 1 and .fabricated == true' <<< "$r" >/dev/null &&
   council_response_is_blind "$later_claim" "$ROOT"; then
    test_pass
else
    test_fail "earlier proposal excused invented current source: $r"
fi

test_case "#3032: a blockquote attributed to an upstream file outside the root is unverifiable, not checked against local files"
upstream="$(_resp "- \`functions-v2/_lib/handler.ts:2\`:
  > const extra = { url: request.url, method: request.method };

- The checked \`@sentry/core/build/cjs/attributes.js:9\`:
  > const { value, unit } = isAttributeObject(rawValue) ? rawValue : { value: rawValue, unit: void 0 };

- Cover wrapped URL attributes such as \`{ value: \"https://h/x?bookingRef=ABC1234\" }\` in the tests.

VERDICT: APPROVE")"
r="$(_hreport "$upstream")"
if jq -e '.quotes_verified == 1 and .quotes_unverifiable_unresolved_citation == 1 and .quotes_unverifiable_proposed == 1
          and .quotes_unverified == 0 and .fabricated == false' <<< "$r" >/dev/null &&
   ! council_response_is_blind "$upstream" "$HROOT"; then test_pass; else test_fail "report: $r"; fi

test_case "#3032: a command the seat ran is not a source quote"
cmd="$(_resp "- The gate at scripts/audit-check.mjs:4 passed; \`npm ci --dry-run --ignore-scripts --no-audit --no-fund --json\` exited 0.
VERDICT: APPROVE")"
r="$(_hreport "$cmd")"
if jq -e '.quotes_checked == 1 and .quotes_unverifiable_command == 1 and .quotes_unverified == 0 and .fabricated == false' <<< "$r" >/dev/null &&
   ! council_response_is_blind "$cmd" "$HROOT"; then test_pass; else test_fail "report: $r"; fi

test_case "#3032: a bare source line under a citation-only line counts as verified evidence"
bare="$(_resp "Existing exceptions are out of scope.

scripts/audit-check.mjs:1
const ALLOWED_ADVISORIES = [

scripts/audit-check.mjs:4
This line is my own summary, not a quote from the file at all.

VERDICT: APPROVE")"
r="$(_hreport "$bare")"
if jq -e '.quotes_checked == 1 and .quotes_verified == 1 and .quotes_unverified == 0 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

# ── Absolute and ".." citation paths (CodeRabbit on #1207).
test_case "an upstream quote beside an absolute path outside the root is unverifiable, not fabricated"
absup="$(_resp "src/pricing.ts:2 is the call site. The upstream \`/home/u/proj/node_modules/x/y.js:9\` has \`const { value, unit } = isAttributeObject(raw) ? raw : { value: raw };\`.
VERDICT: APPROVE")"
r="$(_report "$absup")"
if jq -e '.citations == 1 and .citations_unresolved == 1 and .quotes_unverifiable_unresolved_citation == 1
          and .quotes_unverified == 0 and .fabricated == false' <<< "$r" >/dev/null &&
   ! council_response_is_blind "$absup" "$ROOT"; then test_pass; else test_fail "report: $r"; fi

test_case "an absolute path inside the root resolves and its quote verifies"
absin="$(_resp "$ROOT/src/pricing.ts:2 reads \`$REAL_NEAR\`.
VERDICT: APPROVE")"
r="$(_report "$absin")"
if jq -e '.citations == 1 and .quotes_verified == 1 and .quotes_attributed == 1 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "an absolute path into a deleted disposable workspace maps back to the same root-relative file"
absws="$(_resp "/private/var/folders/xx/T/octopus-consultative.1.2.Ab3dE9/workspace/src/pricing.ts:2 reads \`$FAKE\`.
VERDICT: APPROVE")"
r="$(_report "$absws")"
if jq -e '.citations == 1 and .quotes_attributed_unverified == 1 and .fabricated == true' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "an existing file outside the root is not mapped onto a same-suffix file inside it"
OTHER="$(mktemp -d "${TEST_TMP_DIR:-/tmp}/quote-other.XXXXXX")"
mkdir -p "$OTHER/src"
printf '%s\n' "$FAKE" > "$OTHER/src/pricing.ts"
absother="$(_resp "src/pricing.ts:2 is the call site. $OTHER/src/pricing.ts:1 reads \`$FAKE\`.
VERDICT: APPROVE")"
r="$(_report "$absother")"
if jq -e '.citations_unresolved == 1 and .quotes_unverifiable_unresolved_citation == 1
          and .quotes_attributed_unverified == 0 and .fabricated == false' <<< "$r" >/dev/null &&
   ! council_response_is_blind "$absother" "$ROOT"; then test_pass; else test_fail "report: $r"; fi

test_case "a deleted absolute path outside a disposable workspace stays unresolved"
absgone="$(_resp "src/pricing.ts:2 is the call site. /home/u/elsewhere/src/pricing.ts:2 reads \`$FAKE\`.
VERDICT: APPROVE")"
r="$(_report "$absgone")"
if jq -e '.citations_unresolved == 1 and .quotes_unverifiable_unresolved_citation == 1 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "a '..' path that escapes the root stays an unresolved token"
dotdot="$(_resp "src/pricing.ts:2 is fine. ../other-repo/lib/util.ts:4 reads \`const merged = Object.assign({}, defaults, overrides);\`.
VERDICT: APPROVE")"
r="$(_report "$dotdot")"
if jq -e '.citations_unresolved == 1 and .quotes_unverifiable_unresolved_citation == 1 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

# Preliminary checks share a report; contribution records always reverify.
test_case "preliminary checks share one verifier run and each contribution record runs afresh"
count_file="$TEST_TMP_DIR/qv-count"; : > "$count_file"
shim_dir="$TEST_TMP_DIR/qv-shim"; mkdir -p "$shim_dir"
real_python="$(command -v python3)"
# Count only the quote verifier (its script names this counter); pass every
# python3 call through unchanged.
cat > "$shim_dir/python3" <<SHIM
#!/usr/bin/env bash
if [[ "\$1" == "-I" && "\$2" == "-" ]]; then
    script="\$(cat)"
    [[ "\$script" == *quotes_unverifiable_proposed* ]] && printf 'x\\n' >> "$count_file"
    printf '%s' "\$script" | exec "$real_python" "\$@"
fi
exec "$real_python" "\$@"
SHIM
chmod 755 "$shim_dir/python3"
saved_path="$PATH"; PATH="$shim_dir:$PATH"
COUNCIL_QUOTE_REPORT_KEY=""; COUNCIL_QUOTE_REPORT=""
cached="$(_resp "In src/pricing.ts:2 the base price is \`$FAKE\` which caches correctly.
VERDICT: APPROVE")"
council_response_is_substantive "$cached" "$ROOT" || true
council_response_is_blind "$cached" "$ROOT" || true
preliminary="$(wc -l < "$count_file" | tr -d ' ')"
council_contribution_record_json "$cached" "$ROOT" sha256:t >/dev/null
first="$(wc -l < "$count_file" | tr -d ' ')"
printf 'In src/pricing.ts:2 the fallback `%s` is correct.\nVERDICT: APPROVE\n' "$REAL_NEAR" > "$cached"
record="$(council_contribution_record_json "$cached" "$ROOT" sha256:t)"
second="$(wc -l < "$count_file" | tr -d ' ')"
PATH="$saved_path"
if [[ "$preliminary" == 1 && "$first" == 2 && "$second" == 3 ]] && jq -e '.validation_result == "valid-grounded"' <<< "$record" >/dev/null; then
    test_pass
else
    test_fail "runs: preliminary=$preliminary first=$first second=$second record=$record"
fi

test_case "contribution records reverify a changed ignored cited file"
cache_root="$TEST_TMP_DIR/cache-evidence"; mkdir -p "$cache_root/src"
git -C "$cache_root" init -q
printf 'src/\n' > "$cache_root/.gitignore"
git -C "$cache_root" add .gitignore
git -C "$cache_root" -c user.name=Test -c user.email=test@example.invalid commit -qm initial
printf '%s\n' "$REAL_NEAR" > "$cache_root/src/pricing.ts"
cache_response="$(_resp "src/pricing.ts:1 reads \`$REAL_NEAR\`.
VERDICT: APPROVE")"
record="$(
    council_response_quote_report_cached "$cache_response" "$cache_root"
    jq -e '.quotes_verified == 1' <<< "$COUNCIL_QUOTE_REPORT" >/dev/null || exit 1
    printf '%s\n' "$FAKE" > "$cache_root/src/pricing.ts"
    council_contribution_record_json "$cache_response" "$cache_root" sha256:t
)"
if jq -e '.validation_result == "invalid-ungrounded" and .grounding.fabricated == true
          and .grounding.quotes_verified == 0' <<< "$record" >/dev/null; then
    test_pass
else
    test_fail "changed ignored evidence reused grounding: $record"
fi

test_case "contribution records reverify context contents when the configured path is unchanged"
cache_context="$TEST_TMP_DIR/cache-context.md"
printf '%s\n' "$REAL_NEAR" > "$cache_context"
cache_response="$(_resp "cache-context.md:1 reads \`$REAL_NEAR\`.
VERDICT: APPROVE")"
record="$(
    COUNCIL_CONTEXT_FILES=("$cache_context")
    council_response_quote_report_cached "$cache_response" "$cache_root"
    jq -e '.quotes_verified == 1' <<< "$COUNCIL_QUOTE_REPORT" >/dev/null || exit 1
    printf '%s\n' "$FAKE" > "$cache_context"
    council_contribution_record_json "$cache_response" "$cache_root" sha256:t
)"
if jq -e '.validation_result == "invalid-ungrounded" and .grounding.fabricated == true
          and .grounding.quotes_verified == 0' <<< "$record" >/dev/null; then
    test_pass
else
    test_fail "changed context reused grounding: $record"
fi

test_case "contribution records reverify resolved diffs when the configured base is unchanged"
cache_diff_root="$TEST_TMP_DIR/cache-diff"; mkdir -p "$cache_diff_root/src"
git -C "$cache_diff_root" init -q
printf '%s\n' "$REAL_NEAR" > "$cache_diff_root/src/pricing.ts"
git -C "$cache_diff_root" add src/pricing.ts
git -C "$cache_diff_root" -c user.name=Test -c user.email=test@example.invalid commit -qm original
printf '%s\n' "$FAKE" > "$cache_diff_root/src/pricing.ts"
cache_response="$(_resp "src/pricing.ts:1 reads \`$REAL_NEAR\` in the reviewed diff.
VERDICT: APPROVE")"
record="$(
    OCTOPUS_COUNCIL_DIFF_BASE=HEAD
    council_response_quote_report_cached "$cache_response" "$cache_diff_root"
    jq -e '.quotes_verified_in_diff_removed == 1' <<< "$COUNCIL_QUOTE_REPORT" >/dev/null || exit 1
    git -C "$cache_diff_root" add src/pricing.ts
    git -C "$cache_diff_root" -c user.name=Test -c user.email=test@example.invalid commit -qm replacement
    council_contribution_record_json "$cache_response" "$cache_diff_root" sha256:t
)"
if jq -e '.validation_result == "invalid-ungrounded" and .grounding.fabricated == true
          and .grounding.quotes_verified == 0' <<< "$record" >/dev/null; then
    test_pass
else
    test_fail "changed diff reused grounding: $record"
fi

_advice_with_refreshed_evidence() (
    # Mutate evidence exactly when the contribution is serialized. The response
    # has already passed the old advice-phase checks at this boundary.
    local mutation="$1" d
    d="$(mktemp -d "$TEST_TMP_DIR/quorum-refresh.XXXXXX")"
    mkdir -p "$d/evidence/src" "$d/run/responses"
    printf '%s\n' "$REAL_NEAR" > "$d/evidence/src/changing.ts"
    printf '%s\n' "$REAL_FAR" > "$d/evidence/src/stable.ts"
    OCTOPUS_PROJECT_DIR="$d/evidence"
    COUNCIL_RUN_DIR="$d/run"; COUNCIL_DEPTH="standard"; COUNCIL_FIXTURE=""
    COUNCIL_TASK="Review the source"; COUNCIL_RUN_START_EPOCH=""
    COUNCIL_CONTEXT_FILES=()
    COUNCIL_ROSTER_JSON='[
      {"persona":"code-reviewer","provider":"codex","seat":"member","model_family":"gpt"},
      {"persona":"backend-architect","provider":"agy","seat":"member","model_family":"gemini"}
    ]'
    [[ "$mutation" != chair ]] || COUNCIL_ROSTER_JSON="$(jq -c '.[0].seat = "chair"' <<< "$COUNCIL_ROSTER_JSON")"
    local citation="src/changing.ts:1"
    if [[ "$mutation" == context ]]; then
        printf '%s\n' "$REAL_NEAR" > "$d/context.md"
        COUNCIL_CONTEXT_FILES=("$d/context.md")
        citation="context.md:1"
    elif [[ "$mutation" == diff ]]; then
        git -C "$d/evidence" init -q
        git -C "$d/evidence" add src
        git -C "$d/evidence" -c user.name=Test -c user.email=test@example.invalid commit -qm original
        printf '%s\n' "$FAKE" > "$d/evidence/src/changing.ts"
        OCTOPUS_COUNCIL_DIFF_BASE=HEAD
    fi
    council_dispatch_member_detached() {
        if [[ "$(jq -r '.provider' <<< "$1")" == codex ]]; then
            printf 'Reviewed %s: `%s` handles the fallback.\nVERDICT: APPROVE\n' "$citation" "$REAL_NEAR" > "$3"
        else
            printf 'Reviewed src/stable.ts:1: `%s` defines the discount rules.\nVERDICT: APPROVE\n' "$REAL_FAR" > "$3"
        fi
    }
    council_run_chair_fallback() { :; }
    eval "$(declare -f council_contribution_record_json | sed '1s/council_contribution_record_json/_contribution_before_mutation/')"
    council_contribution_record_json() {
        if [[ "$1" == *00-code-reviewer.md ]]; then
            case "$mutation" in
                source|chair) printf '%s\n' "$FAKE" > "$d/evidence/src/changing.ts" ;;
                context) printf '%s\n' "$FAKE" > "$d/context.md" ;;
                diff)
                    git -C "$d/evidence" add src/changing.ts
                    git -C "$d/evidence" -c user.name=Test -c user.email=test@example.invalid commit -qm replacement
                    ;;
                verdict) sed 's/VERDICT: APPROVE/VERDICT: REVISE/' "$1" > "$d/revised.md"; cp "$d/revised.md" "$1" ;;
                failure) return 1 ;;
            esac
        fi
        _contribution_before_mutation "$@"
    }
    council_run_advice_phase >/dev/null 2>&1 || return 1
    jq -cn --argjson seats "$COUNCIL_SEAT_RECORDS_JSON" \
        --argjson received "$COUNCIL_RESPONSES_RECEIVED" --argjson met "$COUNCIL_QUORUM_MET" \
        --argjson chair "$COUNCIL_CHAIR_RESPONSE_RECEIVED" \
        --arg providers "$COUNCIL_RESPONDING_PROVIDERS" --arg approving "$COUNCIL_APPROVING_PROVIDERS" \
        --arg families "$COUNCIL_RESPONDING_MODEL_FAMILIES" --arg approving_families "$COUNCIL_APPROVING_MODEL_FAMILIES" \
        --argjson distinct "$COUNCIL_DISTINCT_APPROVING_PROVIDERS" \
        --argjson distinct_families "$COUNCIL_DISTINCT_APPROVING_MODEL_FAMILIES" \
        '{seats:$seats, received:$received, met:$met, chair:$chair, providers:$providers, approving:$approving,
          families:$families, approving_families:$approving_families,
          distinct:$distinct, distinct_families:$distinct_families}'
)

for mutation in source context diff failure chair; do
    test_case "advice quorum excludes a contribution rejected after $mutation changes"
    record="$(_advice_with_refreshed_evidence "$mutation")"
    if jq -e '.received == 1 and .met == false and .chair == false and .distinct == 1 and .distinct_families == 1
            and (.providers | contains("codex") | not) and (.families | contains("gpt") | not)
            and (.approving | contains("codex") | not) and (.approving_families | contains("gpt") | not)
            and .seats[0].status != "responded" and .seats[0].counted_as_approver == false
            and (.seats[0].contribution.validation_result | startswith("invalid-"))
            and .seats[1].status == "responded" and .seats[1].counted_as_approver == true' <<< "$record" >/dev/null; then
        test_pass
    else
        test_fail "rejected contribution still affected quorum: $record"
    fi
done

test_case "advice quorum uses the verdict serialized in the refreshed contribution"
record="$(_advice_with_refreshed_evidence verdict)"
if jq -e '.received == 2 and .met == false and .distinct == 1 and .distinct_families == 1
        and .seats[0].verdict == "REVISE" and .seats[0].contribution.verdict == "REVISE"
        and .seats[0].status == "responded" and .seats[0].counted_as_approver == false' <<< "$record" >/dev/null; then
    test_pass
else
    test_fail "preliminary verdict overrode refreshed contribution: $record"
fi

test_case "unchanged grounded contributions still reach advice quorum"
record="$(_advice_with_refreshed_evidence unchanged)"
if jq -e '.received == 2 and .met == true and .distinct == 2 and .distinct_families == 2
        and all(.seats[]; .status == "responded" and .counted_as_approver == true
            and .contribution.validation_result == "valid-grounded")' <<< "$record" >/dev/null; then
    test_pass
else
    test_fail "stable grounded votes were lost: $record"
fi

test_case "a path cited many times is resolved once"
resolve_count="$TEST_TMP_DIR/qv-resolve-count"; : > "$resolve_count"
# Wrap both resolvers with a call counter just before the citation loop.
# Keep source rewriting in Python. Bash 3.2 string substitution over the full
# verifier can consume its process-group budget on native macOS.
resolve_loader="$TEST_TMP_DIR/qv-resolve-loader.py"
cat > "$resolve_loader" <<'PY_RESOLVE_LOADER'
import sys

counter_path = sys.argv.pop(1)
sys.argv[0] = "-"
script = sys.stdin.read()
hook = f'''def _counted(f):
    def g(*a):
        with open({counter_path!r}, "a") as h:
            h.write("r\\n")
        return f(*a)
    return g
resolve_citation = _counted(resolve_citation)
resolve_outside_form = _counted(resolve_outside_form)
for match in CITATION.finditer(resp):'''
assert script.count("for match in CITATION.finditer(resp):") == 1
script = script.replace("for match in CITATION.finditer(resp):", hook, 1)
exec(compile(script, "<stdin>", "exec"))
PY_RESOLVE_LOADER
cat > "$shim_dir/python3" <<SHIM
#!/usr/bin/env bash
if [[ "\$1" == "-I" && "\$2" == "-" ]]; then
    exec "$real_python" -I "$resolve_loader" "$resolve_count" "\${@:3}"
fi
exec "$real_python" "\$@"
SHIM
chmod 755 "$shim_dir/python3"
repeat="$(_resp "src/pricing.ts:2 and src/pricing.ts:3 and src/pricing.ts:2 again.
lib/missing/util.ts:1, lib/missing/util.ts:4, lib/missing/util.ts:9, lib/missing/util.ts:9.
/home/u/elsewhere/a.ts:1 and /home/u/elsewhere/a.ts:2.
VERDICT: APPROVE")"
PATH="$shim_dir:$saved_path"
r="$(_report "$repeat")"
PATH="$saved_path"
calls="$(wc -l < "$resolve_count" | tr -d ' ')"
if [[ "$calls" == 3 ]] && jq -e '.citations == 3 and .citations_unresolved == 6' <<< "$r" >/dev/null; then
    test_pass
else
    test_fail "resolver calls: $calls report: $r"
fi

test_case "many fences and inline spans do not stall the verifier"
# 40k fences plus 40k spans took ~26s when every span rescanned every fence;
# the bounded run must finish well inside 10s and still check the real quote.
many="$TEST_TMP_DIR/many-fences.md"
python3 - "$many" "$REAL_NEAR" <<'PY_MANY'
import sys
n = 40000
parts = ["src/pricing.ts:2 reads `%s`.\n" % sys.argv[2]]
parts += ["```\nx\n```\n"] * n + ["`a` "] * n + ["\nVERDICT: APPROVE\n"]
open(sys.argv[1], "w").write("".join(parts))
PY_MANY
# Run in its own process group and kill the whole group at the bound, so the
# verifier's python child cannot outlive the alarm while holding stdout open.
bounded() {
    perl -e '$t = shift; $pid = fork; if (!$pid) { setpgrp(0, 0); exec @ARGV }
             $SIG{ALRM} = sub { kill "KILL", -$pid; exit 124 }; alarm $t;
             waitpid($pid, 0); exit($? >> 8)' "$@"
}
r="$(bounded 10 bash -c 'source "$1"; council_response_quote_verification_json "$2" "$3"' _ \
    "$PROJECT_ROOT/scripts/lib/council.sh" "$many" "$ROOT" 2>/dev/null || true)"
if jq -e '.citations == 1 and .quotes_verified == 1 and .quotes_omitted == 0 and .fabricated == false' <<< "$r" >/dev/null 2>&1; then
    test_pass
else
    test_fail "verifier did not finish inside 10s or misreported: ${r:0:200}"
fi

test_case "quote supervision preserves provider dispatch accounting"
verification_events="$TEST_TMP_DIR/verification-events.jsonl"
verification_peer_marker="$TEST_TMP_DIR/verification-peer-started"
r="$(OCTO_EVENT_LOG="$verification_events" OCTOPUS_AUTO_PEER_DISPATCH_MARKER="$verification_peer_marker" \
    council_response_quote_verification_json "$real" "$ROOT")"
if jq -e '.verification_failed == false and .quotes_verified == 1' <<< "$r" >/dev/null &&
   [[ ! -e "$verification_events" && ! -e "$verification_peer_marker" ]]; then
    test_pass
else
    test_fail "verification changed dispatch accounting or lost grounding: ${r:0:200}"
fi

test_case "a verifier that stalls after valid partial output is contained and rejects the report"
stalled_pid="$TEST_TMP_DIR/stalled-verifier.pid"
r="$(bounded 20 bash -c '
    source "$1"
    # Keep the marker outside the worker argv contract.
    worker_marker="$4"
    python3() {
        trap "" TERM
        /bin/sh -c '\''printf "%s\n" "$PPID"'\'' > "$worker_marker"
        printf "%s\n" "$COUNCIL_EMPTY_GROUNDING_JSON"
        while :; do sleep 1; done
    }
    council_response_quote_verification_json "$2" "$3"
' _ "$PROJECT_ROOT/scripts/lib/council.sh" "$real" "$ROOT" "$stalled_pid" 2>/dev/null || true)"
if jq -e '.verification_failed == true and .quotes_verified == 0 and .fabricated == false' <<< "$r" >/dev/null 2>&1 &&
   [[ -s "$stalled_pid" ]] && ! kill -0 "$(cat "$stalled_pid")" 2>/dev/null &&
   council_response_quotes_fabricated "$real" "$ROOT" "$r"; then
    test_pass
else
    test_fail "stalled worker survived or partial output gained grounding: ${r:0:200}"
fi

test_case "unavailable verifier supervision fails closed"
r="$(
    _council_registry_dir="$TEST_TMP_DIR/missing-verifier-libs"
    unset -f _octo_run_bare_probe_with_timeout
    council_response_quote_verification_json "$real" "$ROOT"
)"
if jq -e '.verification_failed == true and .quotes_verified == 0 and .fabricated == false' <<< "$r" >/dev/null 2>&1; then
    test_pass
else
    test_fail "missing supervisor granted grounding: ${r:0:200}"
fi

test_case "a sub-megabyte adversarial response returns a correct report or fails closed within the deadline"
adversarial="$TEST_TMP_DIR/adversarial-fence-markers.md"
python3 - "$adversarial" "$REAL_NEAR" <<'PY_ADVERSARIAL'
import sys
with open(sys.argv[1], "w") as out:
    out.write("src/pricing.ts:2 reads `%s`.\nVERDICT: APPROVE\n" % sys.argv[2])
    out.write("`" * 300000)
PY_ADVERSARIAL
r="$(bounded 20 bash -c 'source "$1"; council_response_quote_verification_json "$2" "$3"' _ \
    "$PROJECT_ROOT/scripts/lib/council.sh" "$adversarial" "$ROOT" 2>/dev/null || true)"
# The marker scan can finish this formerly pathological input. A complete
# report must verify the real quote; a timed-out run must discard partial output.
if jq -e '.verification_failed == false and .quotes_checked == 1 and .quotes_verified == 1
        and .quotes_unverified == 0 and .quotes_omitted == 0 and .fabricated == false' <<< "$r" >/dev/null 2>&1; then
    test_pass
elif jq -e '.verification_failed == true and .quotes_verified == 0 and .fabricated == false' <<< "$r" >/dev/null 2>&1 &&
     council_response_quotes_fabricated "$adversarial" "$ROOT" "$r"; then
    test_pass
else
    test_fail "adversarial response exceeded the deadline or returned an incorrect report: ${r:0:200}"
fi

test_case "short inline identifiers do not consume the checkable quote budget"
identifiers="$(_resp "$(for i in $(seq 1 100); do printf '\140id\140 \140null\140 \140value\140 '; done)
src/pricing.ts:2 reads \`$REAL_NEAR\`.
VERDICT: APPROVE")"
r="$(_report "$identifiers")"
record="$(council_contribution_record_json "$identifiers" "$ROOT" sha256:short-identifiers)"
if jq -e '.quotes_checked == 1 and .quotes_verified == 1 and .quotes_omitted == 0 and .fabricated == false' <<< "$r" >/dev/null &&
   jq -e '.validation_result == "valid-grounded"' <<< "$record" >/dev/null &&
   ! council_response_is_blind "$identifiers" "$ROOT"; then
    test_pass
else
    test_fail "short identifiers exhausted the quote budget: $r $record"
fi

for distant_case in before after boundary overflow unresolved; do
    test_case "uncited spans do not consume the citation-bound quote budget: $distant_case"
    distant="$TEST_TMP_DIR/distant-$distant_case.md"
    python3 - "$distant" "$distant_case" "$REAL_NEAR" "$FAKE" <<'PY_DISTANT_UNITS'
from pathlib import Path
import sys
path, case, real, fake = sys.argv[1:]
quote = lambda text: '\nsrc/pricing.ts:2 reads `%s`.\n' % text
spans = '\n'.join('`const distant_%d = inventedValue + 99;`' % i for i in range(300))
padding = '\n\n' + ' ' * 2000 + '\n\n'
if case == 'after':
    response = quote(real) + padding + spans
elif case == 'unresolved':
    response = ('\nmissing/upstream.ts:1 reads `%s`.\n' % fake) * 300 + padding + quote(real)
else:
    response = spans + padding + quote(real) * (256 if case in ('boundary', 'overflow') else 1)
    if case == 'overflow':
        response += quote(fake)
Path(path).write_text(response + '\nVERDICT: APPROVE\n')
PY_DISTANT_UNITS
    record="$(council_contribution_record_json "$distant" "$ROOT" sha256:distant-quotes)"
    if [[ "$distant_case" == overflow ]]; then
        if jq -e '.validation_result == "invalid-ungrounded" and .evidence_paths == []
                and .grounding.quotes_checked == 256 and .grounding.quotes_verified == 256
                and .grounding.quotes_omitted == 1 and .grounding.fabricated == false' <<< "$record" >/dev/null; then
            test_pass
        else test_fail "bound overflow was not rejected: $record"; fi
    else
        expected_verified=1
        [[ "$distant_case" != boundary ]] || expected_verified=256
        expected_unresolved=0
        [[ "$distant_case" != unresolved ]] || expected_unresolved=300
        if jq -e --argjson verified "$expected_verified" --argjson unresolved "$expected_unresolved" \
            '.validation_result == "valid-grounded" and .grounding.quotes_omitted == 0
             and .grounding.quotes_verified == $verified
             and .grounding.quotes_unverifiable_unresolved_citation == $unresolved
             and .grounding.fabricated == false' <<< "$record" >/dev/null; then
            test_pass
        else test_fail "unbound spans exhausted matching capacity: $record"; fi
    fi
done

for quote_limit_case in boundary overflow mixed; do
    test_case "$quote_limit_case quote units cannot bypass the grounding gate"
    limited="$TEST_TMP_DIR/quote-limit-$quote_limit_case.md"
    python3 - "$limited" "$quote_limit_case" "$REAL_NEAR" "$FAKE" <<'PY_QUOTE_LIMIT'
import sys
path, case, real, fake = sys.argv[1:]
quote = lambda text: "\nsrc/pricing.ts:2 reads `%s`.\n" % text
if case == "boundary":
    parts = [quote(real)] * 256
elif case == "overflow":
    parts = [quote(fake)] * 257
else:
    parts = [quote(real)] * 256 + [quote(fake)]
open(path, "w").write("".join(parts) + "\nVERDICT: APPROVE\n")
PY_QUOTE_LIMIT
    r="$(_report "$limited")"
    record="$(council_contribution_record_json "$limited" "$ROOT" sha256:quote-limit)"
    if [[ "$quote_limit_case" == boundary ]]; then
        if jq -e '.quotes_omitted == 0 and .quotes_checked == 256 and .quotes_verified == 256 and .fabricated == false' <<< "$r" >/dev/null &&
           jq -e '.validation_result == "valid-grounded"' <<< "$record" >/dev/null &&
           ! council_response_is_blind "$limited" "$ROOT"; then
            test_pass
        else
            test_fail "exact quote boundary lost grounding: $r $record"
        fi
    elif jq -e --arg case "$quote_limit_case" '.quotes_omitted == 1 and .quotes_checked == 256
             and .fabricated == ($case == "overflow")' <<< "$r" >/dev/null &&
         jq -e '.validation_result == "invalid-ungrounded" and .evidence_paths == [] and .grounding.quotes_omitted == 1' <<< "$record" >/dev/null &&
         council_response_is_blind "$limited" "$ROOT" &&
         ! council_response_is_substantive "$limited" "$ROOT"; then
        test_pass
    else
        test_fail "omitted quotes retained grounding: $r $record"
    fi
done

test_case "citation filenames cannot label fabricated source as proposed code"
proposal_names_passed=true
for basename in example expected cover; do
    cp "$ROOT/src/pricing.ts" "$ROOT/src/${basename}.ts"
    f="$(_resp "src/${basename}.ts:2 reads \`$FAKE\`.
VERDICT: APPROVE")"
    r="$(_report "$f")"
    if ! jq -e '.quotes_checked == 1 and .quotes_unverified == 1 and .quotes_unverifiable_proposed == 0 and .fabricated == true' <<< "$r" >/dev/null; then
        proposal_names_passed=false
        test_fail "citation filename was mistaken for proposal prose: ${basename}.ts report: $r"
        break
    fi
done
[[ "$proposal_names_passed" != true ]] || test_pass

test_case "quote verification never executes repository textconv or fsmonitor commands"
diff_root="$TEST_TMP_DIR/textconv-root"
mkdir -p "$diff_root/src"
git -C "$diff_root" init -q
printf '*.ts diff=fixture\n' > "$diff_root/.gitattributes"
printf 'export const originalValue = 1;\n' > "$diff_root/src/service.ts"
git -C "$diff_root" add .
git -C "$diff_root" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm baseline
textconv="$TEST_TMP_DIR/fixture-textconv"
textconv_marker="$TEST_TMP_DIR/textconv-ran"
printf '#!/bin/sh\nprintf ran > "%s"\ncat "$1"\n' "$textconv_marker" > "$textconv"
chmod 755 "$textconv"
git -C "$diff_root" config diff.fixture.textconv "$textconv"
fsmonitor="$TEST_TMP_DIR/fixture-fsmonitor"
fsmonitor_marker="$TEST_TMP_DIR/fsmonitor-ran"
printf '#!/bin/sh\nprintf ran > "%s"\nexit 1\n' "$fsmonitor_marker" > "$fsmonitor"
chmod 755 "$fsmonitor"
git -C "$diff_root" config core.fsmonitor "$fsmonitor"
printf 'export const updatedValue = 2;\n' > "$diff_root/src/service.ts"
# Prove this Git actually executes the fixture before testing its suppression.
GIT_OPTIONAL_LOCKS=0 git -C "$diff_root" diff --no-ext-diff --no-textconv HEAD -- >/dev/null
fsmonitor_control=false
[[ ! -e "$fsmonitor_marker" ]] || fsmonitor_control=true
rm -f "$fsmonitor_marker"
f="$(_resp 'src/service.ts:1 reads `export const inventedValue = 3;`.
VERDICT: APPROVE')"
r="$(council_response_quote_verification_json "$f" "$diff_root")"
if [[ "$fsmonitor_control" == true && ! -e "$textconv_marker" && ! -e "$fsmonitor_marker" ]] &&
   jq -e '.quotes_checked == 1 and .fabricated == true' <<< "$r" >/dev/null; then
    test_pass
else
    test_fail "fsmonitor control failed, a repository command ran, or the quote result was lost"
fi

for attribute_source in tracked info configured; do
    for filter_spec in clean:fixture.with.dots process:fixture.with.dots clean:fixture=x process:fixture=x; do
        filter_kind="${filter_spec%%:*}"
        filter_name="${filter_spec#*:}"
        test_case "$attribute_source attributes cannot execute a repository $filter_kind filter named $filter_name"
        filter_root="$TEST_TMP_DIR/filter-$attribute_source-$filter_kind-$filter_name"
        mkdir -p "$filter_root/src"
        git -C "$filter_root" init -q
        printf 'export const originalValue = 1;\n' > "$filter_root/src/service.ts"
        git -C "$filter_root" add .
        git -C "$filter_root" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm baseline
        attributes="$filter_root/.gitattributes"
        if [[ "$attribute_source" == info ]]; then
            attributes="$filter_root/.git/info/attributes"
        elif [[ "$attribute_source" == configured ]]; then
            attributes="$TEST_TMP_DIR/configured-$filter_kind-$filter_name.attributes"
            git -C "$filter_root" config core.attributesFile "$attributes"
        fi
        printf '*.ts filter=%s\n' "$filter_name" > "$attributes"
        filter_script="$TEST_TMP_DIR/filter-$attribute_source-$filter_kind-$filter_name.sh"
        filter_marker="$TEST_TMP_DIR/filter-$attribute_source-$filter_kind-$filter_name-ran"
        printf '#!/bin/sh\nprintf ran > "%s"\n' "$filter_marker" > "$filter_script"
        if [[ "$filter_kind" == clean ]]; then
            printf 'cat\n' >> "$filter_script"
        else
            # A process filter starts a protocol exchange; exit after the marker
            # instead of implementing a fake Git filter protocol.
            printf 'exit 1\n' >> "$filter_script"
        fi
        chmod 755 "$filter_script"
        git -C "$filter_root" config "filter.$filter_name.$filter_kind" "$filter_script"
        printf 'export const updatedValue = 2;\n' > "$filter_root/src/service.ts"
        GIT_OPTIONAL_LOCKS=0 git -C "$filter_root" -c core.fsmonitor=false diff --no-ext-diff --no-textconv HEAD -- >/dev/null 2>&1 || true
        filter_control=false
        [[ ! -e "$filter_marker" ]] || filter_control=true
        rm -f "$filter_marker"
        f="$(_resp 'src/service.ts:1 reads `export const inventedValue = 3;`.
VERDICT: APPROVE')"
        r="$(council_response_quote_verification_json "$f" "$filter_root")"
        real_removed="$(_resp 'src/service.ts:1 reads `export const originalValue = 1;` in the reviewed diff.
VERDICT: REVISE')"
        removed_r="$(council_response_quote_verification_json "$real_removed" "$filter_root")"
        if [[ "$filter_control" != true || -e "$filter_marker" ]]; then
            test_fail "repository $filter_kind filter ran or control failed: $filter_name"
        elif [[ "$filter_name" == fixture=x ]]; then
            if jq -e '.quotes_checked == 1 and .fabricated == false and .diff_unavailable == true and .quotes_unverifiable_diff_incomplete == 1' <<< "$r" >/dev/null &&
               jq -e '.fabricated == false and .diff_unavailable == true and .quotes_unverifiable_diff_incomplete == 1' <<< "$removed_r" >/dev/null; then
                test_pass
            else
                test_fail "unsafe driver name lost diff uncertainty: $r $removed_r"
            fi
        elif jq -e '.quotes_checked == 1 and .fabricated == true and .diff_unavailable == false' <<< "$r" >/dev/null &&
           jq -e '.quotes_verified_in_diff_removed == 1 and .diff_unavailable == false' <<< "$removed_r" >/dev/null; then
            test_pass
        else
            test_fail "repository $filter_kind filter ran, control failed or evidence was lost: $r $removed_r"
        fi
    done
done

# Prose blockquote admission controls.
prose_root="$(mktemp -d "$TEST_TMP_DIR/prose-blockquote.XXXXXX")"
mkdir -p "$prose_root/src"
cp "$ROOT/src/pricing.ts" "$prose_root/src/pricing.ts"
git -C "$prose_root" init -q
git -C "$prose_root" add src
git -C "$prose_root" -c user.name=Test -c user.email=test@example.invalid -c core.hooksPath=/dev/null commit -qm initial
for prose_mode in plain html attributed code; do
    test_case "blockquote prose admission preserves source checks: $prose_mode"
    prose_quote='The reviewer must confirm the refresh path is covered.'
    prose_lead='At src/pricing.ts:2 the review requirement was'
    prose_marker='>'
    case "$prose_mode" in
        html) prose_marker='&gt;' ;;
        attributed) prose_lead='src/pricing.ts:2 reads' ;;
        code) prose_quote='const status = await fetchCabinPrice(cabin.id);' ;;
    esac
    prose_response="$(_resp "$prose_lead
$prose_marker $prose_quote
VERDICT: APPROVE")"
    r="$(council_response_quote_verification_json "$prose_response" "$prose_root")"
    record="$(council_contribution_record_json "$prose_response" "$prose_root" sha256:test)"
    if jq -e --arg mode "$prose_mode" --argjson record "$record" '
        .verification_failed == false and .diff_unavailable == false and .quotes_checked == 1
        and (if $mode == "plain" or $mode == "html" then
            .quotes_unverifiable_prose == 1 and .quotes_unverified == 0 and .fabricated == false
            and $record.validation_result == "valid-grounded"
        else
            .quotes_unverifiable_prose == 0 and .quotes_unverified == 1 and .fabricated == true
            and $record.validation_result == "invalid-ungrounded"
        end)' <<< "$r" >/dev/null; then
        test_pass
    else
        test_fail "blockquote admission: $r $record"
    fi
done
# End prose blockquote admission controls.

for prose in \
    'the response counted as blind' \
    'the response counted as blind!' \
    'the response counted as blind?' \
    'the response counted as blind:' \
    'the response counted as blind;' \
    'outcome: the response counted as blind' \
    'the response counted as blind (after review)' \
    '(the response counted as blind)' \
    '[the response counted as blind]' \
    'the response counted as blind; no seat voted' \
    'the summary.json record remains valid' \
    'the cabin.soldOut value remains false' \
    'the version 1.2.3 remains supported' \
    'summary.json remains valid' \
    'the e.g. wording remains ordinary prose'; do
    test_case "unattributed prose in backticks is unverifiable: $prose"
    f="$(_resp "At src/pricing.ts:2 the outcome was \`$prose\`, which describes the review result.
VERDICT: APPROVE")"
    r="$(_report "$f")"
    if jq -e '.quotes_checked == 1 and .quotes_unverifiable_prose == 1 and .quotes_unverified == 0 and .fabricated == false' <<< "$r" >/dev/null &&
       ! council_response_is_blind "$f" "$ROOT"; then test_pass; else test_fail "report: $r"; fi
done

for source_quote in 'return await fetchCabinPrice(cabin)' 'return available ? cabin : sailing' \
    'return cabin.soldOut and sailing.isBookable'; do
    test_case "unattributed fabricated code remains checkable: $source_quote"
    f="$(_resp "At src/pricing.ts:2 the outcome was \`$source_quote\`, which describes the review result.
VERDICT: APPROVE")"
    r="$(_report "$f")"
    if jq -e '.quotes_unverified == 1 and .quotes_unverifiable_prose == 0 and .fabricated == true' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi
done

test_case "a long question-filled prose span finishes inside the verifier budget"
punctuated="$(mktemp "$TEST_TMP_DIR/punctuated.XXXXXX")"
python3 - "$punctuated" <<'PY_PUNCTUATED'
import sys
from pathlib import Path
Path(sys.argv[1]).write_text('At src/pricing.ts:2 the outcome was `' + 'word ? value ' * 60_000 + '`, which describes the review result.\nVERDICT: APPROVE\n')
PY_PUNCTUATED
r="$(bounded 10 bash -c 'source "$1"; council_response_quote_verification_json "$2" "$3"' _ \
    "$PROJECT_ROOT/scripts/lib/council.sh" "$punctuated" "$ROOT" 2>/dev/null || true)"
if jq -e '.quotes_checked == 1 and .quotes_unverifiable_prose == 1 and .fabricated == false' <<< "$r" >/dev/null 2>&1; then
    test_pass
else
    test_fail "punctuated prose exceeded 10s or was rejected: ${r:0:200}"
fi

test_case "an explicit source attribution still checks a plain-text quotation"
f="$(_resp 'src/pricing.ts:2 reads `the response counted as blind`.
VERDICT: APPROVE')"
r="$(_report "$f")"
if jq -e '.quotes_attributed_unverified == 1 and .fabricated == true' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "a quote beyond the attached diff byte limit is unverifiable"
large_context="$TEST_TMP_DIR/large-context.diff"
python3 - "$large_context" "$FAKE" <<'PY_DIFF'
import sys
from pathlib import Path
Path(sys.argv[1]).write_text('diff --git a/pad.ts b/pad.ts\n--- a/pad.ts\n+++ b/pad.ts\n@@ -1 +1 @@\n+const visibleCounter = count + 1;\n+' + 'x' * 8_388_608 + '\n-' + sys.argv[2] + '\n')
PY_DIFF
f="$(_resp "src/pricing.ts:2 reads \`$FAKE\` in the reviewed diff.
VERDICT: APPROVE")"
r="$(COUNCIL_CONTEXT_FILES=("$large_context"); _report "$f")"
if jq -e '.diff_truncated == true and .quotes_unverifiable_diff_incomplete == 1 and .quotes_unverified == 0 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "a matching quote in a truncated diff prefix remains verified"
f="$(_resp 'src/pricing.ts:2 reads `const visibleCounter = count + 1;` in the reviewed diff.
VERDICT: APPROVE')"
r="$(COUNCIL_CONTEXT_FILES=("$large_context"); _report "$f")"
if jq -e '.diff_truncated == true and .quotes_verified_in_diff_added == 1 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "a real removal beyond the git diff byte limit is unverifiable"
large_root="$TEST_TMP_DIR/large-diff-root"
mkdir -p "$large_root"
git -C "$large_root" init -q
python3 - "$large_root/a-padding.ts" old <<'PY_PAD'
import sys
from pathlib import Path
Path(sys.argv[1]).write_text(sys.argv[2] + 'x' * 8_388_608 + '\n')
PY_PAD
printf '%s\n' "$FAKE" > "$large_root/z-service.ts"
git -C "$large_root" add .
git -C "$large_root" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm baseline
python3 - "$large_root/a-padding.ts" new <<'PY_PAD'
import sys
from pathlib import Path
Path(sys.argv[1]).write_text(sys.argv[2] + 'x' * 8_388_608 + '\n')
PY_PAD
printf 'export const updatedValue = 2;\n' > "$large_root/z-service.ts"
f="$(_resp "z-service.ts:1 reads \`$FAKE\` in the reviewed diff.
VERDICT: APPROVE")"
r="$(council_response_quote_verification_json "$f" "$large_root")"
if jq -e '.diff_truncated == true and .quotes_unverifiable_diff_incomplete == 1 and .quotes_attributed_unverified == 0 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "distinct unresolved citations finish within the lookup budget in a large root"
indexed_root="$TEST_TMP_DIR/indexed-root"
indexed_response="$TEST_TMP_DIR/indexed-response.md"
python3 - "$indexed_root" "$indexed_response" "$REAL_NEAR" <<'PY_INDEX'
import sys
from pathlib import Path
root, response = map(Path, sys.argv[1:3])
root.mkdir()
for i in range(20_000):
    (root / ('file-%05d.ts' % i)).touch()
(root / '.hidden' / 'src').mkdir(parents=True)
(root / '.hidden' / 'src' / 'target.ts').write_text(sys.argv[3] + '\n')
response.write_text('\n'.join('Unresolved: missing/path-%d.ts:1 not read' % i for i in range(8_000)) +
                    '\n\nsrc/target.ts:1 reads `' + sys.argv[3] + '`.\nVERDICT: APPROVE\n')
PY_INDEX
r="$(bounded 10 bash -c 'source "$1"; council_response_quote_verification_json "$2" "$3"' _ \
    "$PROJECT_ROOT/scripts/lib/council.sh" "$indexed_response" "$indexed_root" 2>/dev/null || true)"
if jq -e '.citations == 1 and .citations_unresolved == 8000 and .quotes_verified == 1 and .fabricated == false' <<< "$r" >/dev/null 2>&1; then
    test_pass
else
    test_fail "citation lookup exceeded 10s or lost evidence: ${r:0:200}"
fi

test_case "suffix lookup preserves ambiguity and requires a path-component boundary"
mkdir -p "$indexed_root/.other/src" "$indexed_root/.hidden/othersrc"
printf '%s\n' "$REAL_NEAR" > "$indexed_root/.other/src/target.ts"
printf '%s\n' "$REAL_NEAR" > "$indexed_root/.hidden/src/unique.ts"
printf '%s\n' "$REAL_NEAR" > "$indexed_root/.hidden/othersrc/unique.ts"
f="$(_resp "src/target.ts:1 reads \`$FAKE\`.
src/unique.ts:1 reads \`$REAL_NEAR\`.
VERDICT: APPROVE")"
r="$(council_response_quote_verification_json "$f" "$indexed_root")"
if jq -e '.citations == 1 and .citations_unresolved == 1 and .quotes_verified == 1 and .quotes_unverifiable_unresolved_citation == 1 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

# Execute the real embedded verifier with a deterministic directory stream.
# Duplicate suffixes live on disk; synthetic skipped entries exercise the real
# 50,000-entry budget without creating a large filesystem fixture.
index_runner="$TEST_TMP_DIR/index-limits.py"
cat > "$index_runner" <<'PY_INDEX_LIMITS'
import contextlib
import io
import json
import os
import sys
from pathlib import Path
from unittest.mock import patch

source, fixture, mode = sys.argv[1], Path(sys.argv[2]), sys.argv[3]
root = fixture / mode
root.mkdir(parents=True)
real_quote = 'const verifiedPrice = cabin.basePrice ?? sailing.defaultPrice;'
direct_quote = 'const directControl = verifiedPrice + portFees;'
(root / 'direct.ts').write_text(direct_quote + '\n')
visible = root / 'z-visible' / 'src'
visible.mkdir(parents=True)
(visible / 'target.ts').write_text('const unrelatedValue = 17;\n')
hidden = root / 'a-hidden'
if mode == 'depth':
    hidden = hidden.joinpath(*(['nested'] * 32))
(hidden / 'src').mkdir(parents=True)
(hidden / 'src' / 'target.ts').write_text(real_quote + '\n')
response = fixture / (mode + '.md')
response.write_text('src/target.ts:1 reads `' + real_quote + '`.\n\n'
                    'direct.ts:1 reads `' + direct_quote + '`.\nVERDICT: APPROVE\n')
function = Path(source).read_text().split('council_response_quote_verification_json() {', 1)[1]
script = function.split("<<'PY'", 1)[1].split('\n', 1)[1].split('\nPY\n', 1)[0]
native_scandir = os.scandir
consumed = 0

class SkippedEntry:
    def is_symlink(self):
        return True

class Scan:
    def __init__(self, entries):
        self.entries = iter(entries)

    def __iter__(self):
        return self

    def __next__(self):
        global consumed
        entry = next(self.entries)
        consumed += 1
        if mode == 'stream' and consumed > 50_000:
            raise AssertionError('directory stream consumed beyond the entry budget')
        return entry

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.entries.close() if hasattr(self.entries, 'close') else None

def directory_entries(directory):
    with native_scandir(directory) as entries:
        # Only this small root needs deterministic traversal order, so the
        # misleading match is visited before the genuine duplicate.
        if directory == root:
            yield from sorted(entries, key=lambda entry: entry.name)
        else:
            yield from entries
    if mode in ('cap', 'stream') and directory == visible:
        yield from (SkippedEntry() for _ in range(60_000))

def scandir(directory):
    directory = Path(directory)
    if mode == 'unreadable' and directory == hidden:
        raise PermissionError('fixture directory cannot be scanned')
    return Scan(directory_entries(directory))

output = io.StringIO()
sys.argv = ['-', str(response), str(root)]
with patch('os.scandir', scandir), contextlib.redirect_stdout(output):
    try:
        exec(compile(script, source, 'exec'), {'__name__': '__main__'})
    except SystemExit as error:
        assert error.code == 0, error.code
report = json.loads(output.getvalue())
assert report['citations'] == 1 and report['citations_unresolved'] == 1, report
assert report['quotes_verified'] == 1, report
assert report['quotes_unverifiable_unresolved_citation'] == 1, report
assert report['quotes_attributed_unverified'] == 0 and not report['fabricated'], report
if mode == 'stream':
    assert consumed <= 50_000, consumed
print(json.dumps({'mode': mode, 'consumed': consumed, 'report': report}))
PY_INDEX_LIMITS

for index_mode in cap stream depth unreadable; do
    test_case "incomplete suffix scan stays unresolved: $index_mode"
    if index_output="$(python3 "$index_runner" "$PROJECT_ROOT/scripts/lib/council.sh" \
        "$TEST_TMP_DIR/index-limits" "$index_mode" 2>&1)"; then
        test_pass
    else
        test_fail "index limit $index_mode: ${index_output:0:1200}"
    fi
done

test_case "an oversized git diff producer is stopped while its retained prefix verifies"
fake_git_bin="$TEST_TMP_DIR/streaming-git-bin"
mkdir -p "$fake_git_bin"
printf '%s\n' "$FAKE" > "$ROOT/removed-quote.txt"
cat > "$fake_git_bin/git" <<'PY_GIT'
#!/usr/bin/env python3
import os
import sys
import time
from pathlib import Path
root = Path(sys.argv[sys.argv.index('-C') + 1])
if 'config' in sys.argv:
    failure = root / 'filter-config-failure'
    if failure.exists():
        if failure.read_text() == 'oversized':
            sys.stdout.buffer.write(b'x' * 65537)
            sys.exit(0)
        sys.exit(1)
    sys.exit(0)
if (root / 'filter-config-failure').exists():
    (root / 'unsafe-diff-ran').touch()
if (root / 'stall-diff').exists():
    (root / 'diff-producer-pid').write_text(str(os.getpid()))
    time.sleep(30)
prefix = ('diff --git a/service.ts b/service.ts\n--- a/service.ts\n+++ b/service.ts\n@@ -1 +0,0 @@\n-' +
          (root / 'removed-quote.txt').read_text() + '\n').encode()
sys.stdout.buffer.write(prefix)
chunk = b'+' + b'x' * 65534 + b'\n'
for _ in range(1024):
    sys.stdout.buffer.write(chunk)
sys.stdout.buffer.flush()
(root / 'diff-producer-completed').write_text('unbounded output consumed\n')
PY_GIT
chmod 755 "$fake_git_bin/git"
f="$(_resp "src/pricing.ts:2 reads \`$FAKE\` in the reviewed diff.
VERDICT: APPROVE")"
r="$(PATH="$fake_git_bin:$PATH" _report "$f")"
if [[ ! -e "$ROOT/diff-producer-completed" ]] &&
   jq -e '.diff_truncated == true and .quotes_verified_in_diff_removed == 1 and .fabricated == false' <<< "$r" >/dev/null; then
    test_pass
else
    test_fail "producer completed or retained evidence was lost: $r"
fi

test_case "a stalled git diff producer reaches its deadline and is reaped"
touch "$ROOT/stall-diff"
r="$(PATH="$fake_git_bin:$PATH" bounded 15 bash -c \
    'source "$1"; council_response_quote_verification_json "$2" "$3"' _ \
    "$PROJECT_ROOT/scripts/lib/council.sh" "$f" "$ROOT" 2>/dev/null || true)"
producer_pid="$(cat "$ROOT/diff-producer-pid" 2>/dev/null || true)"
if [[ "$producer_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$producer_pid" 2>/dev/null &&
   jq -e '.quotes_checked == 1 and .diff_unavailable == true and .quotes_unverifiable_diff_incomplete == 1
          and .quotes_unverified == 0 and .fabricated == false and .diff_sources == []' <<< "$r" >/dev/null 2>&1; then
    test_pass
else
    test_fail "diff deadline failed or left the producer alive: ${r:0:200}"
fi
rm -f "$ROOT/stall-diff"

for config_failure in unavailable oversized; do
    test_case "an $config_failure filter configuration prevents the worktree diff"
    printf '%s' "$config_failure" > "$ROOT/filter-config-failure"
    rm -f "$ROOT/unsafe-diff-ran"
    r="$(PATH="$fake_git_bin:$PATH" _report "$f")"
    if [[ ! -e "$ROOT/unsafe-diff-ran" ]] &&
       jq -e '.diff_unavailable == true and .quotes_verified == 0 and .fabricated == false' <<< "$r" >/dev/null; then
        test_pass
    else
        test_fail "unknown filter configuration allowed a diff or lost uncertainty: $r"
    fi
    rm -f "$ROOT/filter-config-failure"
done

test_case "a chair-fallback seat record carries grounding like an advice seat"
fbdir="$(mktemp -d "$TEST_TMP_DIR/fallback-grounding.XXXXXX")"; mkdir -p "$fbdir/responses"
COUNCIL_RUN_DIR="$fbdir"; COUNCIL_FIXTURE=""; COUNCIL_SEAT_RECORDS_JSON='[]'
council_pick_provider() { printf 'claude\n'; }
council_provider_is_available() { return 0; }
council_dispatch_member_detached() {
    printf 'Reviewed src/pricing.ts:2: `%s` handles the fallback, and the null guard on the next line returns early.\n\nVERDICT: APPROVE\n' "$REAL_NEAR" > "$3"
    return 0
}
OCTOPUS_PROJECT_DIR="$ROOT" council_run_chair_fallback sha256:t >/dev/null 2>&1 || true
unset -f council_pick_provider council_provider_is_available council_dispatch_member_detached
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/council.sh"
rec="$(jq -c '[.[] | select(.seat == "chair")][0] // {}' <<< "$COUNCIL_SEAT_RECORDS_JSON")"
if jq -e '.grounding.quotes_verified == 1 and .grounding == .contribution.grounding' <<< "$rec" >/dev/null; then test_pass; else test_fail "record: $rec"; fi

# Chair fallback rejection retention controls.
for fallback_access in available failed; do
for fallback_scenario in quiet failure retry missing; do
test_case "chair fallback retains $fallback_access access rejected evidence and $fallback_scenario diagnostics without admission"
record="$(
    d="$(mktemp -d "$TEST_TMP_DIR/fallback-refresh.XXXXXX")"
    mkdir -p "$d/evidence/src" "$d/run/responses" "$d/run/stderr"
    # A known empty diff must not preserve uncertainty about the removed quote.
    printf '%s\n' "$FAKE" > "$d/evidence/src/pricing.ts"
    git -C "$d/evidence" init -q
    git -C "$d/evidence" add src
    git -C "$d/evidence" -c user.name=Test -c user.email=test@example.invalid commit -qm baseline
    printf '%s\n' "$REAL_NEAR" > "$d/evidence/src/pricing.ts"
    OCTOPUS_COUNCIL_DIFF_BASE=HEAD
    OCTOPUS_PROJECT_DIR="$d/evidence"; COUNCIL_RUN_DIR="$d/run"; COUNCIL_FIXTURE=""
    COUNCIL_RESPONSES_RECEIVED=0; COUNCIL_CHAIR_RESPONSE_RECEIVED=false
    COUNCIL_CHAIR_FALLBACK_USED=false; COUNCIL_SEAT_RECORDS_JSON='[]'
    COUNCIL_TIMEOUT_WARNINGS=""
    COUNCIL_RUN_START_EPOCH=""; COUNCIL_CONTEXT_FILES=()
    council_synthesis_capable_persona() { [[ "$1" == strategy-analyst ]]; }
    council_persona_should_fail() { return 1; }
    council_pick_provider() { printf 'claude\n'; }
    council_provider_is_available() { return 0; }
    council_dispatch_member_detached() {
        if [[ "$fallback_access" == failed ]]; then
            printf 'I cannot read the file.\n' > "$3"
        else
            : > "$3"
        fi
        printf 'Reviewed src/pricing.ts:1: `%s` handles the fallback.\nVERDICT: APPROVE\n' "$REAL_NEAR" >> "$3"
        if [[ "$fallback_scenario" == failure || "$fallback_scenario" == retry ]]; then
            printf '== 2026-10-21T20:00:00Z claude exited 17: transport failure\n-- stderr --\nError: fixture transport failure\n' > "$_OCTOPUS_SEAT_STDERR_FILE"
        fi
        [[ "$fallback_scenario" != failure && "$fallback_scenario" != missing ]] || return 17
    }
    eval "$(declare -f council_contribution_record_json | sed '1s/council_contribution_record_json/_fallback_contribution_before_mutation/')"
    council_contribution_record_json() {
        printf '%s\n' "$FAKE" > "$d/evidence/src/pricing.ts"
        _fallback_contribution_before_mutation "$@"
    }
    rc=0
    council_run_chair_fallback sha256:t >/dev/null 2>&1 || rc=$?
    jq -cn --argjson rc "$rc" --argjson seats "$COUNCIL_SEAT_RECORDS_JSON" \
        --argjson received "$COUNCIL_RESPONSES_RECEIVED" --argjson chair "$COUNCIL_CHAIR_RESPONSE_RECEIVED" \
        --argjson used "$COUNCIL_CHAIR_FALLBACK_USED" \
        --arg warnings "$COUNCIL_TIMEOUT_WARNINGS" \
        --argjson responses "$(find "$d/run/responses" -type f | wc -l | tr -d '[:space:]')" \
        --argjson captures "$(find "$d/run/stderr" -type f | wc -l | tr -d '[:space:]')" \
        '{rc:$rc, seats:$seats, received:$received, chair:$chair, used:$used,
          warnings:$warnings, responses:$responses, captures:$captures}'
)"
if jq -e --arg scenario "$fallback_scenario" --arg access "$fallback_access" '.rc != 0 and .received == 0 and .chair == false and .used == false
        and .responses == 1 and (.seats | length == 1)
        and (.seats[0] | .seat == "chair" and .status == "no-response"
            and .counted_as_approver == false
            and .contribution.access_state == (if $access == "failed" then "failed" else "evidence-rejected" end)
            and .grounding.fabricated == true and .grounding == .contribution.grounding)
        and (if $scenario == "quiet" then .warnings == "" and .captures == 0
             elif $scenario == "missing" then .captures == 1 and (.warnings | contains("exited 17: no provider diagnostics were retained;"))
             else .captures == 1 and (.warnings | contains("exited 17: Error: fixture transport failure;")) end)' <<< "$record" >/dev/null; then
    test_pass
else
    test_fail "invalid contribution became a recovered chair: $record"
fi
done
done
# End chair fallback rejection retention controls.

# Retained chair response admission controls.
for reuse_mode in grounded unverified invalid-verdict record-failure malformed-record; do
    test_case "retained chair response requires current contribution admission: $reuse_mode"
    record="$(
        d="$(mktemp -d "$TEST_TMP_DIR/retained-chair.XXXXXX")"
        mkdir -p "$d/evidence" "$d/run/responses" "$d/run/stderr"
        response="$d/run/responses/00-chair-fallback-strategy-analyst.md"
        if [[ "$reuse_mode" == unverified ]]; then
            printf 'The review recommends checking the refresh behavior before publishing.\nVERDICT: APPROVE\n' > "$response"
        else
            mkdir -p "$d/evidence/src"
            cp "$ROOT/src/pricing.ts" "$d/evidence/src/pricing.ts"
            printf 'Reviewed src/pricing.ts:2: `%s` handles the fallback.\n' "$REAL_NEAR" > "$response"
            [[ "$reuse_mode" == invalid-verdict ]] || printf 'VERDICT: APPROVE\n' >> "$response"
        fi
        git -C "$d/evidence" init -q
        git -C "$d/evidence" add .
        git -C "$d/evidence" -c user.name=Test -c user.email=test@example.invalid -c core.hooksPath=/dev/null commit --allow-empty -qm initial
        OCTOPUS_PROJECT_DIR="$d/evidence"; COUNCIL_RUN_DIR="$d/run"
        COUNCIL_CONTEXT_FILES=(); COUNCIL_RUN_START_EPOCH=""; COUNCIL_FIXTURE=""
        COUNCIL_RESPONSES_RECEIVED=1; COUNCIL_CHAIR_RESPONSE_RECEIVED=false
        COUNCIL_CHAIR_FALLBACK_USED=false; COUNCIL_CHAIR_FALLBACK_PERSONA=""
        COUNCIL_SEAT_RECORDS_JSON='[{"persona":"strategy-analyst","seat":"adviser","status":"responded","contribution":{"validation_result":"valid-grounded"}}]'
        council_synthesis_capable_persona() { [[ "$1" == strategy-analyst ]]; }
        council_persona_should_fail() { return 1; }
        council_pick_provider() { printf 'claude\n'; }
        council_provider_is_available() { return 1; }
        if [[ "$reuse_mode" == record-failure ]]; then
            council_contribution_record_json() { return 1; }
        elif [[ "$reuse_mode" == malformed-record ]]; then
            council_contribution_record_json() { printf '{'; }
        fi
        rc=0
        council_run_chair_fallback sha256:test >/dev/null 2>&1 || rc=$?
        jq -cn --argjson rc "$rc" --argjson chair "$COUNCIL_CHAIR_RESPONSE_RECEIVED" \
            --argjson used "$COUNCIL_CHAIR_FALLBACK_USED" --arg persona "$COUNCIL_CHAIR_FALLBACK_PERSONA" \
            --argjson received "$COUNCIL_RESPONSES_RECEIVED" --argjson seats "$COUNCIL_SEAT_RECORDS_JSON" \
            --argjson retained "$([[ -s "$response" ]] && printf true || printf false)" \
            '{rc:$rc,chair:$chair,used:$used,persona:$persona,received:$received,seats:$seats,retained:$retained}'
    )"
    if jq -e --arg mode "$reuse_mode" '.received == 1 and (.seats | length == 1) and .retained
        and (if $mode == "grounded" or $mode == "unverified" then
            .rc == 0 and .chair and .used and .persona == "strategy-analyst"
        else .rc != 0 and .chair == false and .used == false and .persona == "" end)' <<< "$record" >/dev/null; then
        test_pass
    else
        test_fail "retained response bypassed current admission: $record"
    fi
done
# End retained chair response admission controls.

# Begin mixed-diff and context-structure regression controls.
struct_root="$(mktemp -d "$TEST_TMP_DIR/structured-diff.XXXXXX")"
mkdir -p "$struct_root/src"
old_a='const previousValue = loadPreviousValue(input);'
old_b='const previousState = loadPreviousState(input);'
new_a='const actualValue = loadCurrentValue(input);'
new_b='const actualState = loadCurrentState(input);'
not_source='const inventedValue = fabricateResult(input);'
printf '%s\n' "$new_a" "$new_b" > "$struct_root/src/demo.ts"
git -C "$struct_root" init -q
git -C "$struct_root" add src/demo.ts
git -C "$struct_root" -c user.name=Test -c user.email=test@example.invalid -c core.hooksPath=/dev/null commit -qm baseline
struct_diff="$TEST_TMP_DIR/structured.diff"
printf 'diff --git a/src/demo.ts b/src/demo.ts\n--- a/src/demo.ts\n+++ b/src/demo.ts\n@@ -1,2 +1,2 @@\n-%s\n-%s\n+%s\n+%s\n' \
    "$old_a" "$old_b" "$new_a" "$new_b" > "$struct_diff"
for mixed_case in fake-added fake-removed minority-added minority-removed genuine majority-added majority-removed diff-only; do
    test_case "mixed diff quote verifies both portions: $mixed_case"
    removed_text="$old_a"; added_text="$new_a"; expected=valid-grounded
    case "$mixed_case" in
        fake-added) added_text="$not_source
+const inventedState = fabricateState(input);
+return approveImaginaryResult(input);"; expected=invalid-ungrounded ;;
        fake-removed) removed_text="$not_source"; expected=invalid-ungrounded ;;
        minority-added) added_text="$new_a
+$not_source
+return approveImaginaryResult(input);"; expected=invalid-ungrounded ;;
        minority-removed) removed_text="$old_a
-$not_source
-return approveImaginaryResult(input);"; expected=invalid-ungrounded ;;
        majority-added) added_text="$new_a
+$new_b
+$not_source" ;;
        majority-removed) removed_text="$old_a
-$old_b
-$not_source" ;;
        diff-only) added_text='const futureValue = loadFutureValue(input);' ;;
    esac
    selected_diff="$struct_diff"
    if [[ "$mixed_case" == diff-only ]]; then
        selected_diff="$TEST_TMP_DIR/future.diff"
        printf '@@ -1 +1 @@\n-%s\n+%s\n' "$old_a" "$added_text" > "$selected_diff"
    fi
    mixed_response="$(_resp "src/demo.ts:1 reads:
\`\`\`diff
-$removed_text
+$added_text
\`\`\`
VERDICT: APPROVE")"
    record="$(COUNCIL_CONTEXT_FILES=("$selected_diff"); council_contribution_record_json "$mixed_response" "$struct_root" sha256:test)"
    if jq -e --arg expected "$expected" '.validation_result == $expected and .grounding.verification_failed == false
        and .grounding.diff_unavailable == false and .grounding.quotes_checked == 1
        and (if $expected == "invalid-ungrounded" then .evidence_paths == []
            and .grounding.quotes_verified == 0 and .grounding.quotes_attributed_unverified == 1 and .grounding.fabricated
        else .grounding.quotes_verified == 1 and .grounding.quotes_verified_in_diff_removed == 1
            and .grounding.fabricated == false end)' <<< "$record" >/dev/null; then
        test_pass
    else
        test_fail "mixed diff was admitted or rejected incorrectly: $record"
    fi
done
for structure_case in rule file-header git-header malformed-hunk after-hunk unified hunk-only markdown-diff crlf; do
    test_case "attached context imports only unified hunk lines: $structure_case"
    plan_file="$TEST_TMP_DIR/structure-$structure_case.md"
    expected=invalid-ungrounded
    case "$structure_case" in
        rule) printf '# Plan\n\n--- \n- %s\n' "$not_source" > "$plan_file" ;;
        file-header) printf '%s\n' '+++ Plan' "- $not_source" > "$plan_file" ;;
        git-header) printf 'diff --git a/plan b/plan\n- %s\n' "$not_source" > "$plan_file" ;;
        malformed-hunk) printf '@@ summary @@\n- %s\n' "$not_source" > "$plan_file" ;;
        after-hunk) cat "$struct_diff" > "$plan_file"; printf -- '- %s\n' "$not_source" >> "$plan_file" ;;
        unified) cp "$struct_diff" "$plan_file"; not_source_selected="$old_a"; expected=valid-grounded ;;
        hunk-only) printf '@@ -1 +1 @@\n-%s\n+%s\n' "$old_a" "$new_a" > "$plan_file"; not_source_selected="$old_a"; expected=valid-grounded ;;
        markdown-diff) printf '# Review\n```diff\n' > "$plan_file"; cat "$struct_diff" >> "$plan_file"; printf '```\n- %s\n' "$not_source" >> "$plan_file"; not_source_selected="$old_a"; expected=valid-grounded ;;
        crlf) python3 -c 'import sys; sys.stdout.buffer.write(open(sys.argv[1], "rb").read().replace(b"\n", b"\r\n"))' "$struct_diff" > "$plan_file"; not_source_selected="$old_a"; expected=valid-grounded ;;
    esac
    [[ "$expected" != invalid-ungrounded ]] || not_source_selected="$not_source"
    structure_response="$(_resp "src/demo.ts:1 reads \`$not_source_selected\`.
VERDICT: APPROVE")"
    record="$(COUNCIL_CONTEXT_FILES=("$plan_file"); council_contribution_record_json "$structure_response" "$struct_root" sha256:test)"
    if jq -e --arg expected "$expected" '.validation_result == $expected and .grounding.verification_failed == false
        and .grounding.diff_unavailable == false and .grounding.quotes_checked == 1
        and (if $expected == "invalid-ungrounded" then .evidence_paths == []
            and .grounding.quotes_verified_in_diff_removed == 0 and .grounding.fabricated
        else .grounding.quotes_verified_in_diff_removed == 1 and .grounding.fabricated == false end)' <<< "$record" >/dev/null; then
        test_pass
    else
        test_fail "non-source context became diff evidence or a real hunk was lost: $record"
    fi
done
# A source prefix operator gains a third sign in a unified diff. It remains
# source inside a hunk or a headerless excerpt, even when the side is too short
# to meet the standalone specificity floor.
for prefix_layout in excerpt hunk headers; do
    for prefix_case in fake-added-short fake-removed-short fake-added-specific fake-removed-specific genuine-added-short genuine-removed-short genuine-added-specific genuine-removed-specific fake-both-added-short fake-both-removed-short genuine-both-short; do
        test_case "mixed diff preserves prefix operators: $prefix_layout/$prefix_case"
        removed_truth="$old_a"; added_truth="$new_a"
        case "$prefix_case" in
            *both*) removed_truth='-- previousCounter;'; added_truth='++ actualCounter;' ;;
            *added*) added_truth='++ actualCounter;' ;;
            *removed*) removed_truth='-- previousCounter;' ;;
        esac
        if [[ "$prefix_case" == *specific ]]; then
            [[ "$prefix_case" != *added* ]] || added_truth="$added_truth // actual added source"
            [[ "$prefix_case" != *removed* ]] || removed_truth="$removed_truth // actual removed source"
        fi
        removed_text="$removed_truth"; added_text="$added_truth"; expected=valid-grounded
        case "$prefix_case" in
            fake-added*|fake-both-added*) added_text="${added_truth/actualCounter/inventedCounter}"; expected=invalid-ungrounded ;;
            fake-removed*|fake-both-removed*) removed_text="${removed_truth/previousCounter/inventedCounter}"; expected=invalid-ungrounded ;;
        esac
        prefix_diff="$TEST_TMP_DIR/prefix.diff"
        printf '@@ -1 +1 @@\n-%s\n+%s\n' "$removed_truth" "$added_truth" > "$prefix_diff"
        prefix_body="$(printf -- '-%s\n+%s\n' "$removed_text" "$added_text")"
        case "$prefix_layout" in
            hunk) prefix_body="$(printf '@@ -1 +1 @@\n%s\n' "$prefix_body")" ;;
            headers) prefix_body="$(printf -- '--- a/src/demo.ts\n+++ b/src/demo.ts\n@@ -1 +1 @@\n%s\n' "$prefix_body")" ;;
        esac
        prefix_response="$(_resp "src/demo.ts:1 reads:
\`\`\`diff
$prefix_body
\`\`\`
VERDICT: APPROVE")"
        record="$(COUNCIL_CONTEXT_FILES=("$prefix_diff"); council_contribution_record_json "$prefix_response" "$struct_root" sha256:test)"
        if jq -e --arg expected "$expected" '.validation_result == $expected and .grounding.verification_failed == false
            and .grounding.diff_unavailable == false and .grounding.quotes_checked == 1
            and (if $expected == "invalid-ungrounded" then .evidence_paths == []
                and .grounding.quotes_verified == 0 and .grounding.quotes_attributed_unverified == 1 and .grounding.fabricated
            else .grounding.quotes_verified == 1 and .grounding.quotes_verified_in_diff_removed == 1
                and .grounding.fabricated == false end)' <<< "$record" >/dev/null; then
            test_pass
        else
            test_fail "prefix source was discarded or invented source admitted: $record"
        fi
    done
done
for short_kept in "$new_a" '++ actualCounter;'; do
    test_case "short removed portion without diff evidence remains uncertain: $short_kept"
    prefix_response="$(_resp "src/demo.ts:1 reads:
\`\`\`diff
--- previousCounter;
+$short_kept
\`\`\`
VERDICT: APPROVE")"
    record="$(COUNCIL_CONTEXT_FILES=(); council_contribution_record_json "$prefix_response" "$struct_root" sha256:test)"
    if jq -e '.grounding.quotes_checked == 1 and .grounding.quotes_verified == 0
        and .grounding.quotes_unverifiable_claimed_removed == 1 and .grounding.quotes_unverified == 0
        and .grounding.verification_failed == false and .grounding.diff_unavailable == false
        and .grounding.fabricated == false' <<< "$record" >/dev/null; then
        test_pass
    else
        test_fail "short removal lost missing-diff uncertainty: $record"
    fi
done
# Git can omit the marker on empty context lines. Generate both real Git
# formats in a separate repository so the evidence root's own diff cannot
# accidentally verify a removal that the attached patch parser discarded.
blank_patch_root="$(mktemp -d "$TEST_TMP_DIR/blank-context-git.XXXXXX")"
mkdir -p "$blank_patch_root/src"
blank_old_head='const previousMode = readPreviousMode(input);'
blank_new_head='const currentMode = readCurrentMode(input);'
blank_tail='const retainedTail = readRetainedTail(input);'
printf '%s\n\n%s\n%s\n' "$blank_old_head" "$old_a" "$blank_tail" > "$blank_patch_root/src/demo.ts"
git -C "$blank_patch_root" init -q
git -C "$blank_patch_root" add src/demo.ts
git -C "$blank_patch_root" -c user.name=Test -c user.email=test@example.invalid -c core.hooksPath=/dev/null commit -qm baseline
printf '%s\n\n%s\n%s\n' "$blank_new_head" "$new_a" "$blank_tail" > "$blank_patch_root/src/demo.ts"
for blank_case in canonical suppressed crlf clipped-canonical clipped-suppressed unbalanced; do
    test_case "attached patch bounds empty context lines: $blank_case"
    blank_patch="$TEST_TMP_DIR/blank-context-$blank_case.diff"
    suppress_blank=true; expected=valid-grounded
    case "$blank_case" in canonical|clipped-canonical) suppress_blank=false ;; esac
    git -C "$blank_patch_root" -c diff.suppressBlankEmpty="$suppress_blank" diff --no-ext-diff --no-textconv HEAD > "$blank_patch"
    python3 - "$blank_patch" "$blank_case" <<'PY'
from pathlib import Path
import sys
path, kind = Path(sys.argv[1]), sys.argv[2]
raw = path.read_bytes()
if kind == "crlf":
    raw = raw.replace(b"\n", b"\r\n")
elif kind.startswith("clipped-"):
    raw = raw.replace(b"@@ -1,4 +1,4 @@", b"@@ -1 +1 @@")
elif kind == "unbalanced":
    raw = raw.replace(b"@@ -1,4 +1,4 @@", b"@@ -1,2 +1 @@")
path.write_bytes(raw)
PY
    case "$blank_case" in clipped-*|unbalanced) expected=invalid-ungrounded ;; esac
    blank_response="$(_resp "src/demo.ts:1 reads \`$old_a\`.
VERDICT: APPROVE")"
    record="$(COUNCIL_CONTEXT_FILES=("$blank_patch"); council_contribution_record_json "$blank_response" "$struct_root" sha256:test)"
    if jq -e --arg expected "$expected" '.validation_result == $expected and .grounding.verification_failed == false
        and .grounding.diff_unavailable == false and .grounding.quotes_checked == 1
        and (if $expected == "invalid-ungrounded" then .grounding.quotes_verified == 0
            and .grounding.fabricated and .evidence_paths == []
        else .grounding.quotes_verified_in_diff_removed == 1 and .grounding.fabricated == false end)' <<< "$record" >/dev/null; then
        test_pass
    else
        test_fail "empty context lost source or exceeded a hunk boundary: $record"
    fi
done
for blank_endings in lf crlf; do
    for blank_prefix_case in genuine invented; do
        test_case "empty context preserves prefix source inside a quoted hunk: $blank_endings/$blank_prefix_case"
        blank_prefix_old='-- previousCounter; // actual previous source'
        blank_prefix_new='++ actualCounter; // actual current source'
        blank_prefix_patch="$TEST_TMP_DIR/blank-prefix.diff"
        printf '@@ -1,2 +1,2 @@\n\n-%s\n+%s\n@@ -3 +3 @@\n-%s\n+%s\n' \
            "$blank_prefix_old" "$blank_prefix_new" "$old_a" "$new_a" > "$blank_prefix_patch"
        expected=valid-grounded
        if [[ "$blank_prefix_case" == invented ]]; then
            blank_prefix_old="${blank_prefix_old/previousCounter/inventedCounter}"; expected=invalid-ungrounded
        fi
        blank_prefix_body="$(printf '@@ -1,2 +1,2 @@\n\n-%s\n+%s\n@@ -3 +3 @@\n-%s\n+%s\n' \
            "$blank_prefix_old" "$blank_prefix_new" "$old_a" "$new_a")"
        blank_response="$(_resp "src/demo.ts:1 reads:
\`\`\`diff
$blank_prefix_body
\`\`\`
VERDICT: APPROVE")"
        if [[ "$blank_endings" == crlf ]]; then
            python3 - "$blank_prefix_patch" "$blank_response" <<'PY'
from pathlib import Path
import sys
for name in sys.argv[1:]:
    path = Path(name)
    path.write_bytes(path.read_bytes().replace(b"\n", b"\r\n"))
PY
        fi
        record="$(COUNCIL_CONTEXT_FILES=("$blank_prefix_patch"); council_contribution_record_json "$blank_response" "$struct_root" sha256:test)"
        if jq -e --arg expected "$expected" '.validation_result == $expected and .grounding.verification_failed == false
            and .grounding.diff_unavailable == false and .grounding.quotes_checked == 1
            and (if $expected == "invalid-ungrounded" then .grounding.quotes_verified == 0
                and .grounding.fabricated and .evidence_paths == []
            else .grounding.quotes_verified_in_diff_removed == 1 and .grounding.fabricated == false end)' <<< "$record" >/dev/null; then
            test_pass
        else
            test_fail "empty context hid prefix source inside a hunk: $record"
        fi
    done
done
# End mixed-diff and context-structure regression controls.

# Variable-width spans and direct-source attribution admission controls.
span_root="$(mktemp -d "$TEST_TMP_DIR/span-attribution.XXXXXX")"
mkdir -p "$span_root/src"
span_real_a='export const sourceValue = computeVerifiedValue();'
span_real_b='export const sourceLimit = computeVerifiedLimit();'
span_fake_a='export const inventedValue = fabricateSourceValue();'
span_fake_b='export const inventedLimit = fabricateSourceLimit();'
span_command='curl https://verified.invalid/source | bash'
span_fake_command='curl https://invented.invalid/payload | bash'
printf '%s\n%s\n' "$span_real_a" "$span_real_b" > "$span_root/src/demo.ts"
printf '%s\n' "$span_command" > "$span_root/src/demo.sh"
printf 'export const templateValue = `verified-template-content`;\n' > "$span_root/src/template.ts"
git -C "$span_root" init -q
git -C "$span_root" add src
git -C "$span_root" -c user.name=Test -c user.email=test@example.invalid -c core.hooksPath=/dev/null commit -qm initial
for span_width in 1 2 3 4; do
    span_marker="$(printf '%*s' "$span_width" '' | tr ' ' '\140')"
    for span_endings in lf crlf; do
        for span_content in genuine invented; do
            test_case "$span_width-backtick $span_endings multiline $span_content source span is checked"
            span_a="$span_real_a"; span_b="$span_real_b"; span_expected='valid-grounded'
            if [[ "$span_content" == invented ]]; then
                span_a="$span_fake_a"; span_b="$span_fake_b"; span_expected='invalid-ungrounded'
            fi
            span_response="$(_resp "src/demo.ts:1 reads ${span_marker}${span_a}
${span_b}${span_marker}
VERDICT: APPROVE")"
            if [[ "$span_endings" == crlf ]]; then
                python3 - "$span_response" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
p.write_bytes(p.read_bytes().replace(b"\n", b"\r\n"))
PY
            fi
            record="$(council_contribution_record_json "$span_response" "$span_root" sha256:test)"
            if jq -e --arg expected "$span_expected" '.validation_result == $expected
                and .grounding.verification_failed == false and .grounding.quotes_checked == 1
                and (if $expected == "valid-grounded" then .grounding.quotes_verified == 1
                    and .grounding.quotes_attributed_unverified == 0 and .grounding.fabricated == false
                else .grounding.quotes_verified == 0 and .grounding.quotes_attributed_unverified == 1
                    and .grounding.fabricated and .evidence_paths == [] end)' <<< "$record" >/dev/null; then
                test_pass
            else
                test_fail "multiline span admission or evidence counts: $record"
            fi
        done
    done
done
for span_marker in '``' '```'; do
    for span_content in genuine invented; do
        test_case "$span_marker span preserves embedded literal backticks in $span_content source"
        span_template='export const templateValue = `verified-template-content`;'
        span_expected='valid-grounded'
        if [[ "$span_content" == invented ]]; then
            span_template='export const templateValue = `invented-template-content`;'
            span_expected='invalid-ungrounded'
        fi
        span_response="$(_resp "src/template.ts:1 reads ${span_marker}${span_template}${span_marker}
VERDICT: APPROVE")"
        record="$(council_contribution_record_json "$span_response" "$span_root" sha256:test)"
        if jq -e --arg expected "$span_expected" '.validation_result == $expected
            and .grounding.quotes_checked == 1 and .grounding.verification_failed == false
            and (if $expected == "valid-grounded" then .grounding.quotes_verified == 1
                else .grounding.quotes_attributed_unverified == 1 and .grounding.fabricated end)' <<< "$record" >/dev/null; then
            test_pass
        else
            test_fail "embedded backticks changed source meaning: $record"
        fi
    done
done
for span_marker in '`' '``'; do
    test_case "multiline $span_marker formatting of reviewer prose remains unverifiable"
    span_response="$(_resp "At src/demo.ts:1 the outcome was ${span_marker}the response counted
as blind after review${span_marker}.
VERDICT: APPROVE")"
    record="$(council_contribution_record_json "$span_response" "$span_root" sha256:test)"
    if jq -e '.validation_result == "valid-grounded" and .grounding.quotes_checked == 1
        and .grounding.quotes_unverifiable_prose == 1 and .grounding.quotes_unverified == 0
        and .grounding.fabricated == false' <<< "$record" >/dev/null; then test_pass; else test_fail "multiline prose: $record"; fi
done

test_case "an unmatched delimiter does not hide a later valid source span"
span_response="$(_resp "An unmatched \` marker precedes the citation.

src/demo.ts:1 reads \`\`$span_fake_a\`\`
VERDICT: APPROVE")"
record="$(council_contribution_record_json "$span_response" "$span_root" sha256:test)"
if jq -e '.validation_result == "invalid-ungrounded" and .grounding.quotes_checked == 1
    and .grounding.quotes_attributed_unverified == 1 and .grounding.fabricated' <<< "$record" >/dev/null; then test_pass; else test_fail "unmatched delimiter: $record"; fi

for span_shape in inline fence; do
    for span_content in genuine invented; do
        test_case "$span_shape attributed $span_content command is a source claim"
        span_quote="$span_command"; span_expected='valid-grounded'
        if [[ "$span_content" == invented ]]; then span_quote="$span_fake_command"; span_expected='invalid-ungrounded'; fi
        if [[ "$span_shape" == inline ]]; then
            span_body="src/demo.sh:1 reads \`$span_quote\`"
        else
            span_body="src/demo.sh:1 reads:
\`\`\`bash
$span_quote
\`\`\`"
        fi
        span_response="$(_resp "$span_body
VERDICT: APPROVE")"
        record="$(council_contribution_record_json "$span_response" "$span_root" sha256:test)"
        if jq -e --arg expected "$span_expected" '.validation_result == $expected
            and .grounding.quotes_checked == 1 and .grounding.quotes_attributed == 1
            and .grounding.quotes_unverifiable_command == 0 and .grounding.verification_failed == false
            and (if $expected == "valid-grounded" then .grounding.quotes_verified == 1
                else .grounding.quotes_attributed_unverified == 1 and .grounding.fabricated end)' <<< "$record" >/dev/null; then
            test_pass
        else
            test_fail "command exemption overrode direct source attribution: $record"
        fi
    done
    for span_intent in executed proposed; do
        test_case "$span_shape $span_intent command retains its non-source exemption"
        span_lead='For src/demo.sh:1 I ran'
        if [[ "$span_intent" == proposed ]]; then span_lead='For src/demo.sh:1 I suggest'; fi
        if [[ "$span_shape" == inline ]]; then span_body="$span_lead \`$span_fake_command\`"; else
            span_body="$span_lead:
\`\`\`bash
$span_fake_command
\`\`\`"
        fi
        span_response="$(_resp "$span_body
VERDICT: APPROVE")"
        record="$(council_contribution_record_json "$span_response" "$span_root" sha256:test)"
        if jq -e '.validation_result == "valid-grounded" and .grounding.quotes_checked == 1
            and .grounding.quotes_attributed == 0 and .grounding.quotes_unverifiable_command == 1
            and .grounding.quotes_unverified == 0 and .grounding.fabricated == false' <<< "$record" >/dev/null; then
            test_pass
        else
            test_fail "reviewer command became a source claim: $record"
        fi
    done
done
for span_modifier in 'exactly' 'literally' 'clearly' 'as follows' 'currently and exactly' \
    'precisely as written' 'without alteration' 'in its entirety'; do
    for span_content in genuine invented; do
        test_case "reads $span_modifier retains $span_content attribution beside a genuine quote"
        span_quote="$span_real_b"; span_expected='valid-grounded'
        if [[ "$span_content" == invented ]]; then span_quote="$span_fake_b"; span_expected='invalid-ungrounded'; fi
        span_response="$(_resp "src/demo.ts:1 reads \`$span_real_a\`.

src/demo.ts:2 reads $span_modifier \`$span_quote\`.
VERDICT: APPROVE")"
        record="$(council_contribution_record_json "$span_response" "$span_root" sha256:test)"
        if jq -e --arg expected "$span_expected" '.validation_result == $expected
            and .grounding.quotes_checked == 2 and .grounding.quotes_attributed == 2
            and .grounding.verification_failed == false
            and (if $expected == "valid-grounded" then .grounding.quotes_verified == 2
                and .grounding.fabricated == false
            else .grounding.quotes_verified == 1 and .grounding.quotes_attributed_unverified == 1
                and .grounding.fabricated and .evidence_paths == [] end)' <<< "$record" >/dev/null; then
            test_pass
        else
            test_fail "modifier removed direct source attribution: $record"
        fi
    done
done
for span_proposal in 'should read exactly' 'could instead read exactly'; do
    test_case "$span_proposal remains a proposal beside genuine source"
    span_response="$(_resp "src/demo.ts:1 reads \`$span_real_a\`.

src/demo.ts:2 $span_proposal \`$span_fake_b\`.
VERDICT: APPROVE")"
    record="$(council_contribution_record_json "$span_response" "$span_root" sha256:test)"
    if jq -e '.validation_result == "valid-grounded" and .grounding.quotes_verified == 1
        and .grounding.quotes_attributed == 1 and .grounding.quotes_unverifiable_proposed == 1
        and .grounding.fabricated == false' <<< "$record" >/dev/null; then test_pass; else test_fail "proposal attributed: $record"; fi
done

test_case "a source verb in an earlier sentence does not attribute a command the reviewer ran"
span_response="$(_resp "src/demo.sh:1 shows a problem. I ran \`$span_fake_command\`.
VERDICT: APPROVE")"
record="$(council_contribution_record_json "$span_response" "$span_root" sha256:test)"
if jq -e '.validation_result == "valid-grounded" and .grounding.quotes_attributed == 0
    and .grounding.quotes_unverifiable_command == 1 and .grounding.fabricated == false' <<< "$record" >/dev/null; then test_pass; else test_fail "sentence boundary: $record"; fi
# End variable-width spans and direct-source attribution controls.

# Negative source claims describe absence, not quoted source evidence.
absence_root="$(mktemp -d "$TEST_TMP_DIR/negative-source.XXXXXX")"
mkdir -p "$absence_root/src"
absence_real='export const fallbackValue = cabin.defaultPrice;'
absence_fake='const legacyValue = fallbackValue ?? cachedPrice;'
printf '%s\n' "$absence_real" > "$absence_root/src/pricing.ts"
git -C "$absence_root" init -q
git -C "$absence_root" add src/pricing.ts
git -C "$absence_root" -c user.name=Test -c user.email=test@example.invalid -c core.hooksPath=/dev/null commit -qm initial
for absence_lead in 'does not contain' "doesn't define" 'does not currently contain' \
    'does not contain a class and does not define' 'does not define a class and does not contain'; do
    for absence_shape in inline fenced; do
        test_case "$absence_shape negative source claim stays unverifiable: $absence_lead"
        if [[ "$absence_shape" == inline ]]; then
            absence_quote="\`$absence_fake\`"
        else
            absence_quote="
\`\`\`ts
$absence_fake
\`\`\`"
        fi
        response="$(_resp "src/pricing.ts:1 $absence_lead $absence_quote
VERDICT: APPROVE")"
        record="$(council_contribution_record_json "$response" "$absence_root" sha256:test)"
        if jq -e '.validation_result == "valid-grounded" and .grounding.quotes_checked == 1
            and .grounding.quotes_verified == 0 and .grounding.quotes_unverifiable == 1
            and .grounding.quotes_attributed == 0 and .grounding.fabricated == false' <<< "$record" >/dev/null; then
            test_pass
        else
            test_fail "absence was treated as positive source evidence: $record"
        fi
    done
done

for absence_lead in 'does not contain' 'does not contain a class and does not define'; do
    test_case "a negative claim cannot verify quoted text that happens to exist: $absence_lead"
    response="$(_resp "src/pricing.ts:1 $absence_lead \`$absence_real\`
VERDICT: APPROVE")"
    record="$(council_contribution_record_json "$response" "$absence_root" sha256:test)"
    if jq -e '.grounding.quotes_checked == 1 and .grounding.quotes_verified == 0
        and .grounding.quotes_unverifiable == 1 and .grounding.quotes_attributed == 0
        and .grounding.fabricated == false' <<< "$record" >/dev/null; then test_pass; else test_fail "negative claim verified: $record"; fi
done

for absence_positive in "does not contain a class but defines" \
    "does not contain a class and does not define a function but contains" "does not contain a class.
src/pricing.ts:1 reads"; do
    test_case "a negative clause cannot excuse a subsequent positive source claim"
    response="$(_resp "src/pricing.ts:1 reads \`$absence_real\`.

src/pricing.ts:1 does not contain \`$absence_fake\`.

src/pricing.ts:1 $absence_positive \`$absence_fake\`
VERDICT: APPROVE")"
    record="$(council_contribution_record_json "$response" "$absence_root" sha256:test)"
    if jq -e '.validation_result == "invalid-ungrounded" and .grounding.quotes_verified == 1
        and .grounding.quotes_unverifiable == 1 and .grounding.quotes_attributed_unverified == 1
        and .grounding.fabricated == true' <<< "$record" >/dev/null; then test_pass; else test_fail "negative clause excused positive source: $record"; fi
done
# End negative source claim controls.

# Begin contribution report admission controls.
source "$PROJECT_ROOT/scripts/lib/council.sh"
# Bash 5.2 cannot reparse declare -f output for this grouped heredoc. Load the
# verifier from source so instrumentation leaves its shell structure intact.
admission_verifier="$TEST_TMP_DIR/admission-real-verifier.sh"
sed -n '/^council_response_quote_verification_json() {$/,/^}$/p' \
    "$PROJECT_ROOT/scripts/lib/council.sh" | sed '1s/council_response_quote_verification_json/_admission_real_verifier/' > "$admission_verifier"
source "$admission_verifier"
# Each fixture runs in its own subshell. The real verifier supplies the first
# report; a later failure models the bounded verifier's existing timeout path.
_admission_report_case() (
    local admission_case_flow="$1" admission_case_failure="$2" d response admission_case_calls rc=0 warnings
    d="$(mktemp -d "$TEST_TMP_DIR/admission-report.XXXXXX")"
    mkdir -p "$d/evidence/src" "$d/run/responses" "$d/run/stderr"
    printf '%s\n' 'const originalValue = loadOriginalValue(input);' > "$d/evidence/src/demo.ts"
    git -C "$d/evidence" init -q
    git -C "$d/evidence" add src/demo.ts
    git -C "$d/evidence" -c user.name=Test -c user.email=test@example.invalid -c core.hooksPath=/dev/null commit -qm original
    OCTOPUS_PROJECT_DIR="$d/evidence"; COUNCIL_RUN_DIR="$d/run"
    COUNCIL_DEPTH=quick; COUNCIL_TASK='Review source'; COUNCIL_FIXTURE=''
    COUNCIL_CONTEXT_FILES=(); COUNCIL_RUN_START_EPOCH=''
    COUNCIL_RESPONSES_RECEIVED=0; COUNCIL_CHAIR_RESPONSE_RECEIVED=false
    COUNCIL_CHAIR_FALLBACK_USED=false; COUNCIL_TIMEOUT_WARNINGS=''
    COUNCIL_BLIND_SEATS=''; COUNCIL_SEAT_RECORDS_JSON='[]'
    COUNCIL_QUOTE_REPORT_KEY=''; COUNCIL_QUOTE_REPORT=''
    admission_case_calls="$d/verifier-calls"; : > "$admission_case_calls"
    council_response_quote_verification_json() {
        local count
        printf 'call\n' >> "$admission_case_calls"
        count="$(wc -l < "$admission_case_calls" | tr -d '[:space:]')"
        if { [[ "$admission_case_failure" == second-failure || "$admission_case_failure" == fresh-failure ]] && (( count > 1 )); } \
                || { [[ "$admission_case_failure" == first-failure || "$admission_case_failure" == preliminary-failed ]] && (( count == 1 )); }; then
            printf '%s\n' "$COUNCIL_FAILED_GROUNDING_JSON"
        else
            _admission_real_verifier "$@"
        fi
    }
    council_dispatch_member_detached() {
        printf 'src/demo.ts:1 reads `const originalValue = loadOriginalValue(input);`.\nVERDICT: APPROVE\n' > "$3"
        if [[ "$admission_case_failure" == preliminary-failed || "$admission_case_failure" == fresh-failure ]]; then
            council_response_quote_report_cached "$3" "$d/evidence"
        fi
    }
    if [[ "$admission_case_flow" == advice ]]; then
        COUNCIL_ROSTER_JSON='[{"persona":"code-reviewer","provider":"codex","seat":"member","model_family":"gpt"}]'
        council_run_chair_fallback() { :; }
        council_run_advice_phase >/dev/null 2>&1 || rc=$?
    else
        council_synthesis_capable_persona() { [[ "$1" == strategy-analyst ]]; }
        council_persona_should_fail() { return 1; }
        council_pick_provider() { printf 'claude\n'; }
        council_provider_is_available() { [[ "$admission_case_flow" != retained-chair ]]; }
        if [[ "$admission_case_flow" == retained-chair ]]; then
            response="$d/run/responses/00-chair-fallback-strategy-analyst.md"
            council_dispatch_member_detached '' '' "$response"
            COUNCIL_RESPONSES_RECEIVED=1
            COUNCIL_SEAT_RECORDS_JSON='[{"persona":"strategy-analyst","seat":"adviser","status":"responded","contribution":{"validation_result":"valid-grounded"}}]'
        fi
        council_run_chair_fallback sha256:test >/dev/null 2>&1 || rc=$?
    fi
    warnings="$(council_print_run_warnings)"
    jq -cn --arg flow "$admission_case_flow" --argjson rc "$rc" \
        --argjson calls "$(wc -l < "$admission_case_calls" | tr -d '[:space:]')" \
        --argjson seats "$COUNCIL_SEAT_RECORDS_JSON" --argjson received "$COUNCIL_RESPONSES_RECEIVED" \
        --argjson chair "$COUNCIL_CHAIR_RESPONSE_RECEIVED" --arg warnings "$warnings" \
        '{flow:$flow,rc:$rc,calls:$calls,seats:$seats,received:$received,chair:$chair,warnings:$warnings}'
)

for admission_flow in advice fresh-chair retained-chair; do
    for admission_failure in stable second-failure first-failure preliminary-failed fresh-failure; do
        test_case "$admission_flow uses one fresh report: $admission_failure"
        record="$(_admission_report_case "$admission_flow" "$admission_failure")"
        if jq -e --arg failure "$admission_failure" '.calls ==
                (if $failure == "preliminary-failed" or $failure == "fresh-failure" then 2 else 1 end)
            and (if $failure == "first-failure" or $failure == "fresh-failure" then
                if .flow == "retained-chair" then .rc != 0 and .chair == false
                else .received == 0 and .chair == false
                    and .seats[0].contribution.access_state == "evidence-rejected"
                    and .seats[0].contribution.validation_result == "invalid-ungrounded"
                    and .seats[0].contribution.grounding.verification_failed
                    and (.seats[0].counted_as_approver == false)
                    and (if .flow == "advice" then
                        (.warnings | contains("grounding verification failed"))
                        and (.warnings | contains("switch that provider") | not)
                        else true end)
                end
            elif .flow == "retained-chair" then .rc == 0 and .chair and .received == 1
            else .rc == 0 and .received == 1
                and .seats[0].status == "responded"
                and .seats[0].contribution.validation_result == "valid-grounded"
                and .seats[0].grounding.quotes_verified == 1
                and .seats[0].grounding == .seats[0].contribution.grounding
                and (if .flow == "advice" then .seats[0].counted_as_approver else .chair end)
            end)' <<< "$record" >/dev/null; then
            test_pass
        else
            test_fail "record and admission did not share a fresh report: $record"
        fi
    done
done
# End contribution report admission controls.

test_summary
