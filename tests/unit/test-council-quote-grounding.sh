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
if jq -e '.citations == 1 and .quotes_verified == 1 and .fabricated == false' <<< "$r" >/dev/null 2>&1; then
    test_pass
else
    test_fail "verifier did not finish inside 10s or misreported: ${r:0:200}"
fi

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
