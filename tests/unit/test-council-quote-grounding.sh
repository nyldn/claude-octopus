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
   jq -e '.unverified_samples[0] | contains("fetchCabinPrice")' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

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
@@ -1,4 +1,4 @@
-  const base = cabin.oldPrice || sailing.legacyPrice;
+  if (!base) return null;
\`\`\`
VERDICT: APPROVE")"
r="$(_report "$fenced")"
if jq -e '.quotes_checked == 2 and .quotes_verified == 2 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "an elided quote verifies when each specific piece is in the file"
elided="$(_resp "src/pricing.ts:1 \`export function priceFor(cabin, sailing) { ... return applyTaxes(base, sailing.portFees);\`
VERDICT: APPROVE")"
if [[ "$(_field "$elided" quotes_verified)" == 1 ]]; then test_pass; else test_fail "report: $(_report "$elided")"; fi

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
            elif ! jq -e --arg field "quotes_verified_in_diff_$diff_side" '.quotes_verified == 1 and .[$field] == 1 and .fabricated == false' <<< "$r" >/dev/null; then
                test_fail "two real $diff_side lines failed to verify a $quote_kind block: $r"
                continue
            fi
            test_pass
        done
    done
done

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
   jq -e '.unverified_samples | index("c.royalup_price = ub.bid_amount * 2,")' <<< "$r" >/dev/null &&
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

# ── One verifier run per response (CodeRabbit on #1207).
test_case "the verifier runs once per response across the blind check and the contribution record"
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
council_contribution_record_json "$cached" "$ROOT" sha256:t >/dev/null
first="$(wc -l < "$count_file" | tr -d ' ')"
printf 'In src/pricing.ts:2 the fallback `%s` is correct.\nVERDICT: APPROVE\n' "$REAL_NEAR" > "$cached"
record="$(council_contribution_record_json "$cached" "$ROOT" sha256:t)"
second="$(wc -l < "$count_file" | tr -d ' ')"
PATH="$saved_path"
if [[ "$first" == 1 && "$second" == 2 ]] && jq -e '.validation_result == "valid-grounded"' <<< "$record" >/dev/null; then
    test_pass
else
    test_fail "runs: first=$first second=$second record=$record"
fi

test_case "a path cited many times is resolved once"
resolve_count="$TEST_TMP_DIR/qv-resolve-count"; : > "$resolve_count"
# Wrap both resolvers with a call counter just before the citation loop.
cat > "$shim_dir/python3" <<SHIM
#!/usr/bin/env bash
if [[ "\$1" == "-I" && "\$2" == "-" ]]; then
    script="\$(cat)"
    if [[ "\$script" == *quotes_unverifiable_proposed* ]]; then
        hook='def _counted(f):
    def g(*a):
        with open("$resolve_count", "a") as h:
            h.write("r\\n")
        return f(*a)
    return g
resolve_citation = _counted(resolve_citation)
resolve_outside_form = _counted(resolve_outside_form)
for match in CITATION.finditer(resp):'
        script="\${script/for match in CITATION.finditer(resp):/\$hook}"
    fi
    printf '%s' "\$script" | exec "$real_python" "\$@"
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
if jq -e '.citations == 1 and .quotes_verified == 1 and .quotes_omitted > 0 and .fabricated == false' <<< "$r" >/dev/null 2>&1; then
    test_pass
else
    test_fail "verifier did not finish inside 10s or misreported: ${r:0:200}"
fi

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

test_summary
