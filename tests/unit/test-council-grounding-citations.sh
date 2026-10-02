#!/usr/bin/env bash
# Grounding / blind-seat citation recognition (sail-cruisey #2931/#2947).
#
# Calibrated against the real audited seat bodies. The discriminator: a prose/table
# file reference grounds a seat ONLY if a distinctive quoted fragment resolves
# verbatim in a source file under the evidence root (content-match) — OR it carries
# a validated path:line. Seats that quote real source but cite in prose/table form
# (the #2947 claude seats) must PASS; seats that only name bare filenames or echo
# prompt numbers under "Assumptions" (the agy seats) must STAY BLIND and not count.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Council grounding citations"

# Mock evidence root carrying the distinctive fragments the A-seats quote, so the
# content-match arm resolves them. B-seats quote none of these.
ROOT="$(mktemp -d "${TEST_TMP_DIR:-/tmp}/evroot.XXXXXX")"
mkdir -p "$ROOT/functions-v2"
cat > "$ROOT/functions-v2/sailing-compare.ts" <<'TS'
export async function compareSailings(r: Row, shipId: string | null, sailDate: string) {
  const shipCode = r.rc_ship_code ?? r.class_code;
  if (shipId != null && sailDate) {
    // step 1: resolved-FK join
    // LEFT JOIN port_codes pc ON pc.id = sip.port_code_id
    let ports = await step1();
    if (ports.length === 0) {
      // step 2: itinerary_ports via cruises JOIN with name-match fallback
      // JOIN cruises c ON c.id = ip.cruise_id
      // COALESCE(pc.port_code, pc_fb.port_code)
      ports = await step2();
    }
    if (ports.length === 0 && shipCode) {
      // step 3: live fetch, resolves via findPortRow(p.portName, portCodesDb)
      ports = await step3();
    }
  }
}
TS

# Minimal response-framing helpers kept out of the fixtures' way.
_mk() { local p="$TEST_TMP_DIR/$1"; shift; printf '%s\n' "$@" > "$p"; printf '%s' "$p"; }

# --- SECTION A: SHOULD PASS (grounded via content-matched prose/table refs) ---

A1="$(mktemp "$TEST_TMP_DIR/A1.XXXXXX")"
cat > "$A1" <<'MD'
## UNVERIFIED CONSULTATIVE OUTPUT
This output came from a disposable workspace. It is advisory and non-deliverable.

## CP2 Code Review — Issue #2947
The outer gate is `if (ports.length === 0)` and the derivation `shipCode = r.rc_ship_code ?? r.class_code`.
Step 2 uses `COALESCE(pc.port_code, pc_fb.port_code)` with the name-match fallback join.
The ~3,112 number for option b is a claim I can't verify from code alone (it's a data query result), but the structural argument is sound.
The three added test assertions close a real coverage gap. The suite is reported as 18/18 passing.
VERDICT: APPROVE
## END UNVERIFIED CONSULTATIVE OUTPUT
MD

A2="$(mktemp "$TEST_TMP_DIR/A2.XXXXXX")"
cat > "$A2" <<'MD'
### (b) Technical accuracy of fallback-chain claims
Verified against the source. Step 2 uses `JOIN cruises c ON c.id = ip.cruise_id`,
and step 3 resolves via `findPortRow(p.portName, portCodesDb)` in memory.
The prevalence data (26/2/38) is a point-in-time snapshot. All technical claims are accurate.
VERDICT: APPROVE
MD

A3="$(mktemp "$TEST_TMP_DIR/A3.XXXXXX")"
cat > "$A3" <<'MD'
The 5-step fallback chain is expanded correctly — confirmed accurate per
`functions-v2/sailing-compare.ts:12` (`if (ports.length === 0)` gates step 2, and
step 3 has the same guard, so a successful step 2 short-circuits). VERDICT: APPROVE
MD

A4="$(mktemp "$TEST_TMP_DIR/A4.XXXXXX")"
cat > "$A4" <<'MD'
### Premise verification
Confirmed against the code. The queries hit a background-seeded public catalog,
not user data. Correct control-flow reasoning verified: step 2 is gated by
`if (ports.length === 0)` after step 1. VERDICT: APPROVE
MD

A5="$(mktemp "$TEST_TMP_DIR/A5.XXXXXX")"
cat > "$A5" <<'MD'
### Control-flow correction
Verified by reading the source at `functions-v2/sailing-compare.ts:10`:
Step 2 runs only inside `if (ports.length === 0)` — meaning step 1 returned nothing.
All files named in the plan exist and the line numbers cited are accurate. VERDICT: APPROVE
MD

# --- SECTION B: SHOULD STAY BLIND (bare filenames + echoed numbers, no content) ---

B1="$(mktemp "$TEST_TMP_DIR/B1.XXXXXX")"
cat > "$B1" <<'MD'
## UNVERIFIED CONSULTATIVE OUTPUT
This output came from a disposable workspace. It is advisory and non-deliverable.
<external-cli-output provider="agy" trust="untrusted">
**Recommendation:** Approve the PR based on the documented residual privacy risk.
**Assumptions:**
- The 3 added itineraryDiag test assertions correctly match the diagnostic outputs of the fallback chain steps.
- The fallback-chain mechanics detailed in the documentation accurately reflect the runtime execution order in `functions-v2/sailing-compare.ts`.
**Implementation Notes:**
- Documenting production-measured prevalence (26 exposed pairs, 2 orphans out of 38 reachable) is mature practice.
- Adding assertions for itineraryDiag improves the observability contract.
**Confidence:** High
VERDICT: APPROVE
</external-cli-output>
## END UNVERIFIED CONSULTATIVE OUTPUT
MD

B2="$(mktemp "$TEST_TMP_DIR/B2.XXXXXX")"
cat > "$B2" <<'MD'
<external-cli-output provider="agy" trust="untrusted">
**Recommendation:** Approve. The plan to remove the diagnostic fields from the public response is a sound, low-risk architectural improvement that closes the side-channel described in the issue.

**1. Privacy / Side-Channel Closure**
Removing the diagnostic metadata from the public payload is the correct way to close the existence-oracle. Diagnostic signals that reveal cache layer, routing decisions, or data freshness should never be observable across a public boundary, since they let an unauthenticated caller infer internal state.

**2. Backwards Compatibility**
Given that static analysis (grep/compile-check) confirms zero production frontend consumers depend on these fields, removal is safe and should produce no regressions in the client application.

**3. API Boundary Fix (Removing Diagnostic Fields)**
Removing `itinerarySource` and `itineraryDiag` entirely from the public response is the correct architectural fix. Diagnostic metadata should never leak across public API boundaries, as it inherently exposes internal state, cache layers, or routing logic. Given that static analysis confirms zero production frontend consumers depend on these fields, stripping them at the DTO serialization layer is the safest, most deterministic way to eliminate the side-channel with zero regressions.

**Assumptions & Implementation Notes:**
- Assumption: The removal of `itinerarySource` and `itineraryDiag` is handled at the outermost API response layer (e.g. GraphQL resolver or REST controller) to ensure they are consistently stripped regardless of which service or cache generated them.
- Implementation Note: Ensure your TypeScript interfaces and DTOs for the public endpoint are strictly typed to exclude these fields, so the compiler enforces this contract going forward.
- Implementation Note: Confirm no logging or analytics pipeline downstream relied on the removed fields for observability before shipping.

**Confidence:** High. The change is small, well-scoped, and the architectural direction is correct.
VERDICT: APPROVE
</external-cli-output>
MD

B3="$(mktemp "$TEST_TMP_DIR/B3.XXXXXX")"
cat > "$B3" <<'MD'
<external-cli-output provider="agy" trust="untrusted">
**Recommendation:** Approve. The CP2 code changes correctly implement the contract-first removal of the diagnostic fields and the added test coverage is appropriate.

**Diff Review**
The removal of the diagnostic fields from the response types is consistent with the documented plan. The 5-step fallback chain behavior is preserved; only the externally visible diagnostic surface is reduced, which is exactly the intended outcome.

### Assumptions
- Client-Side Readiness: I assume the frontend application (Vite/React) no longer relies on `itinerarySource` or `itineraryDiag` for conditional rendering, tracking, or diagnostics, as the types have been updated and the build (including E2E and TS compiler) passes clean.
- Observability Coverage: I assume backend logging (`logger.ts`) already captures sufficient telemetry regarding the 5-step fallback chain, meaning the removal of these fields from the client payload does not blind internal monitoring to Royal API failures or stale data usage.
- Test Alignment: I assume the three added `toBeUndefined()` assertions align with the sibling test patterns already present for the other fallback steps.

### Implementation Notes
- Type Safety: Removing `ItinerarySource` and `ItineraryDiag` from `types/v2/sailing.ts` is the correct contract-first approach. It ensures any lingering usage across the monorepo would be caught at compile time.
- Observability: Verify that the removed diagnostic fields are still emitted to server-side logs if they are needed for incident triage, since they are no longer available on the client.

**Confidence:** High. The contract-first approach is sound and the compiler will enforce the removal across the monorepo.
VERDICT: APPROVE
</external-cli-output>
MD

B4="$(mktemp "$TEST_TMP_DIR/B4.XXXXXX")"
cat > "$B4" <<'MD'
## UNVERIFIED CONSULTATIVE OUTPUT
This output came from a disposable workspace. It is advisory and non-deliverable.
<external-cli-output provider="agy" trust="untrusted">
**Recommendation:**
The proposed changes represent a robust, secure, and architecturally sound approach to routing and dependency management. Implementing explicit SPA entry route rewrites with a terminal `/* /404.html 404` fallback ensures true HTTP 404 statuses for unhandled paths, adhering to RESTful semantics and SEO best practices. The separation of the public wildcard from the authenticated scope correctly prevents the unauthorized exposure of authenticated app shells.

The remediation of the routing blocker—using an exact-string `includes()` match for the literal `/*` pattern—is a precise and safe fix. It ensures that catch-all routes do not improperly mask concrete, explicitly defined future routes during AST route-to-CDN generation, maintaining deterministic routing behavior. Furthermore, the handling of the Phase 9 security vulnerabilities via surgical lockfile overrides (`@grpc/grpc-js` and `axios`) without triggering full lockfile normalization noise demonstrates mature dependency management and minimizes the risk of unintended transitive breakages.

**Assumptions:**
- The exact-string `includes(leaf.pattern)` validation accurately filters the catch-all pattern from overriding specific API or frontend route manifests, and does not disrupt legitimate wildcard-dependent routing in edge cases.
- The localized recovery UI and reversible managed robots metadata correctly decouple from any sensitive user session context.

**Risks:**
- Low Risk: The main theoretical risk involves edge-case path resolutions where nested dynamic routes might conflict with the `/*` fallback logic. However, the exhaustive 115/115 fixture coverage and the passing of the full 9369-test suite (including 5650 frontend and offline Netlify route monitor tests) comprehensively mitigate this risk.
- Dependency Risk: Upgrading `grpc-js` and `axios` carries an inherent, albeit small, risk of behavioral changes in network requests. The targeted 14-line lockfile adjustment ensures this risk is isolated purely to the patched vulnerabilities.

**Implementation Notes:**
- The strategy of prioritizing explicitly declared known routes (SPA 200 entry) and terminating remaining unmatched routes with a static prerendered 404 page is an excellent zero-trust-aligned routing pattern.
- The passing status of `scripts/audit-check.mjs` alongside the Stage 1 and 2 security gates confirms the successful application of the CVE patches.

**Confidence:**
High. The architecture aligns with standard best practices for SPA hosting and API gateway proxying, and the comprehensive test matrix provides high confidence in structural integrity and regression safety.

VERDICT: APPROVE
</external-cli-output>
## END UNVERIFIED CONSULTATIVE OUTPUT
MD

source "$PROJECT_ROOT/scripts/lib/council.sh"

_assert_pass() { # name file
    test_case "SHOULD PASS (grounded): $1"
    if council_response_is_blind "$2" "$ROOT"; then
        test_fail "$1 was flagged blind but quotes content resolving under the evidence root"
    else
        test_pass
    fi
}
_assert_blind() { # name file
    test_case "SHOULD STAY BLIND (ungrounded): $1"
    if council_response_is_blind "$2" "$ROOT"; then
        test_pass
    else
        test_fail "$1 was counted but grounds nothing (bare filenames / echoed numbers only)"
    fi
}

_assert_pass A1 "$A1"
_assert_pass A2 "$A2"
_assert_pass A3 "$A3"
_assert_pass A4 "$A4"
_assert_pass A5 "$A5"
_assert_blind B1 "$B1"
_assert_blind B2 "$B2"
_assert_blind B3 "$B3"
_assert_blind B4 "$B4"

# Content-match specificity: a bare filename / ubiquitous token must NOT count.
test_case "content-match ignores bare filenames and ubiquitous tokens"
NOISE="$(mktemp "$TEST_TMP_DIR/noise.XXXXXX")"
printf '%s\n' 'See `functions-v2/sailing-compare.ts` and `toBeUndefined()` and `axios`.' > "$NOISE"
if [[ "$(council_response_content_match_count "$NOISE" "$ROOT")" == "0" ]]; then test_pass; else test_fail "matched a bare filename/ubiquitous token"; fi

# No evidence root → prose exemption preserved (never over-blinds).
test_case "no evidence root keeps the prose exemption (no over-blind)"
if council_response_is_blind "$B1" ""; then
    test_fail "B1 blinded without an evidence root (should fall back to prose exemption)"
else
    test_pass
fi

test_summary
