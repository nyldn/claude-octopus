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

for quote_response in "$A1" "$A2"; do
    test_case "quote-only response has a direct content-grounding signal"
    if council_response_has_grounding "$quote_response" "$ROOT"; then test_pass
    else test_fail "quote-only response lost its content match below the blind threshold"; fi
done

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

# Full-length security claims must use the live grounding gate.
SECURITY_VOTE="$TEST_TMP_DIR/security-vote.md"
SECURITY_GROUNDED="$TEST_TMP_DIR/security-grounded.md"
PROCESS_VOTE="$TEST_TMP_DIR/process-vote.md"
for _ in {1..16}; do
    printf '%s\n' 'The new guard rejects unauthenticated requests. Authorization denies forbidden access before execution. The conditional branch returns early for unauthorized input.'
done > "$SECURITY_VOTE"
printf '\nVERDICT: APPROVE\n' >> "$SECURITY_VOTE"
test_case "full-length ungrounded security approval is blind and excluded"
record="$(council_contribution_record_json "$SECURITY_VOTE" "$ROOT" sha256:fixture)"
if council_response_makes_code_claims "$SECURITY_VOTE" &&
   council_response_is_blind "$SECURITY_VOTE" "$ROOT" &&
   ! council_response_is_substantive "$SECURITY_VOTE" "$ROOT" &&
   jq -e '.validation_result == "invalid-access" and .access_state == "failed" and .comprehension_verified == false' <<< "$record" >/dev/null; then test_pass
else test_fail "ungrounded security approval entered the substantive quorum"; fi
sed '/VERDICT: APPROVE/d' "$SECURITY_VOTE" > "$SECURITY_GROUNDED"
printf '\nThe guard follows `if (ports.length === 0)`.\nVERDICT: APPROVE\n' >> "$SECURITY_GROUNDED"
test_case "full-length source-backed security review remains substantive"
if council_response_has_grounding "$SECURITY_GROUNDED" "$ROOT" &&
   council_response_is_substantive "$SECURITY_GROUNDED" "$ROOT"; then test_pass
else test_fail "grounded security review was excluded"; fi
for _ in {1..16}; do
    printf '%s\n' 'The proposal describes a phased rollout. The schedule gives stakeholders time to discuss the timeline and nominate owners. The next milestone follows their written feedback.'
done > "$PROCESS_VOTE"
printf '\nVERDICT: APPROVE\n' >> "$PROCESS_VOTE"
test_case "full-length process prose retains its exemption"
if ! council_response_makes_code_claims "$PROCESS_VOTE" &&
   council_response_is_substantive "$PROCESS_VOTE" "$ROOT"; then test_pass
else test_fail "process prose was treated as an ungrounded code review"; fi

test_case "verified quote permits separate summary attribution of test results"
SUMMARY_QUOTE="$TEST_TMP_DIR/summary-quote.md"
printf '%s\n' 'The function contains `shipCode = r.rc_ship_code ?? r.class_code`. The summary confirms the tests pass.' 'VERDICT: APPROVE' > "$SUMMARY_QUOTE"
if council_response_has_grounding "$SUMMARY_QUOTE" "$ROOT" &&
   ! council_response_defers_without_reading "$SUMMARY_QUOTE" "$ROOT" &&
   council_response_is_substantive "$SUMMARY_QUOTE" "$ROOT"; then test_pass
else test_fail "verified source quote was rejected for summary attribution"; fi

test_case "an unverified quote cannot exempt summary deferral"
if ( council_response_content_match_count() { printf '0\n'; }
     council_response_is_blind "$SUMMARY_QUOTE" "$ROOT" ); then test_pass
else test_fail "unverified content was admitted by the deferral exemption"; fi

test_case "first-person access failure still overrides a quote and summary"
printf '%s\n' 'I cannot read the repository files.' >> "$SUMMARY_QUOTE"
if council_response_is_blind "$SUMMARY_QUOTE" "$ROOT" &&
   ! council_response_is_substantive "$SUMMARY_QUOTE" "$ROOT"; then test_pass
else test_fail "source quote overrode an explicit access failure"; fi

# Boundary fixtures use inert code markers, never credentials or provider calls.
BOUNDARY_ROOT="$TEST_TMP_DIR/boundary-root"
OUTSIDE="$TEST_TMP_DIR/outside.ts"
BOUNDARY_RESPONSE="$TEST_TMP_DIR/boundary-response.md"
FRAGMENT='const boundedEvidenceMarker = sourceValue ?? fallbackValue;'
mkdir -p "$BOUNDARY_ROOT"
printf '%s\n' "$FRAGMENT" > "$OUTSIDE"
printf 'The function contains `%s`.\n' "$FRAGMENT" > "$BOUNDARY_RESPONSE"

_count_is() {
    local expected="$1" response="$2" root="$3" actual
    actual="$(council_response_content_match_count "$response" "$root")"
    if [[ "$actual" == "$expected" ]]; then test_pass
    else test_fail "expected $expected matched fragments, got $actual"; fi
}

test_case "external source symlink cannot ground a response"
ln -s "$OUTSIDE" "$BOUNDARY_ROOT/alias.ts"
_count_is 0 "$BOUNDARY_RESPONSE" "$BOUNDARY_ROOT"
rm "$BOUNDARY_ROOT/alias.ts"

test_case "external directory alias cannot ground a response"
mkdir -p "$TEST_TMP_DIR/outside-directory"
cp "$OUTSIDE" "$TEST_TMP_DIR/outside-directory/source.ts"
ln -s "$TEST_TMP_DIR/outside-directory" "$BOUNDARY_ROOT/alias"
_count_is 0 "$BOUNDARY_RESPONSE" "$BOUNDARY_ROOT"
rm "$BOUNDARY_ROOT/alias"

test_case "private agent state cannot ground a response"
mkdir -p "$BOUNDARY_ROOT/.claude"
cp "$OUTSIDE" "$BOUNDARY_ROOT/.claude/private.md"
_count_is 0 "$BOUNDARY_RESPONSE" "$BOUNDARY_ROOT"
rm "$BOUNDARY_ROOT/.claude/private.md"

test_case "environment configuration cannot ground a response"
cp "$OUTSIDE" "$BOUNDARY_ROOT/production.env"
_count_is 0 "$BOUNDARY_RESPONSE" "$BOUNDARY_ROOT"
rm "$BOUNDARY_ROOT/production.env"

test_case "credential-named configuration cannot ground a response"
cp "$OUTSIDE" "$BOUNDARY_ROOT/credentials.json"
_count_is 0 "$BOUNDARY_RESPONSE" "$BOUNDARY_ROOT"
rm "$BOUNDARY_ROOT/credentials.json"

test_case "the response itself cannot ground its own quotes"
cp "$BOUNDARY_RESPONSE" "$BOUNDARY_ROOT/response.md"
_count_is 0 "$BOUNDARY_ROOT/response.md" "$BOUNDARY_ROOT"
rm "$BOUNDARY_ROOT/response.md"

test_case "hard-linked response aliases cannot ground its own quotes"
ln "$BOUNDARY_RESPONSE" "$BOUNDARY_ROOT/alias.ts"
_count_is 0 "$BOUNDARY_RESPONSE" "$BOUNDARY_ROOT"
rm "$BOUNDARY_ROOT/alias.ts"

ACTIVE_RUN="$BOUNDARY_ROOT/council output/current"
mkdir -p "$ACTIVE_RUN/responses" "$ACTIVE_RUN/revisions"
cp "$OUTSIDE" "$ACTIVE_RUN/responses/01-earlier.md"
cp "$OUTSIDE" "$ACTIVE_RUN/revisions/01-revised.md"
cp "$OUTSIDE" "$ACTIVE_RUN/implementation-plan.md"

test_case "active run responses and generated artifacts cannot supply source quotes"
COUNCIL_RUN_DIR="$ACTIVE_RUN" _count_is 0 "$BOUNDARY_RESPONSE" "$BOUNDARY_ROOT"

test_case "an explicitly symlinked active run is excluded by physical identity"
ln -s "$ACTIVE_RUN" "$TEST_TMP_DIR/active-run-alias"
COUNCIL_RUN_DIR="$TEST_TMP_DIR/active-run-alias" _count_is 0 "$BOUNDARY_RESPONSE" "$BOUNDARY_ROOT"

test_case "an evidence root inside the active run cannot supply source quotes"
COUNCIL_RUN_DIR="$ACTIVE_RUN" _count_is 0 "$BOUNDARY_RESPONSE" "$ACTIVE_RUN/responses"

test_case "the active run itself cannot be selected as implicit source evidence"
COUNCIL_RUN_DIR="$ACTIVE_RUN" _count_is 0 "$BOUNDARY_RESPONSE" "$ACTIVE_RUN"

test_case "genuine source outside the active run still grounds a response"
cp "$OUTSIDE" "$BOUNDARY_ROOT/source.ts"
COUNCIL_RUN_DIR="$ACTIVE_RUN" _count_is 1 "$BOUNDARY_RESPONSE" "$BOUNDARY_ROOT"

test_case "an explicit run that cannot be identified fails closed"
COUNCIL_RUN_DIR="$ACTIVE_RUN/nonexistent" _count_is 0 "$BOUNDARY_RESPONSE" "$BOUNDARY_ROOT"
rm "$BOUNDARY_ROOT/source.ts"

test_case "a full approval grounded only in the active run is blind and excluded"
ACTIVE_VOTE="$TEST_TMP_DIR/active-run-vote.md"
{
    printf 'The function contains `%s`.\n' "$FRAGMENT"
    for _ in {1..20}; do printf 'The guards preserve the control-flow branch and reject unauthorized inputs.\n'; done
    printf 'VERDICT: APPROVE\n'
} > "$ACTIVE_VOTE"
record="$(COUNCIL_RUN_DIR="$ACTIVE_RUN" council_contribution_record_json "$ACTIVE_VOTE" "$BOUNDARY_ROOT" sha256:fixture)"
if ! COUNCIL_RUN_DIR="$ACTIVE_RUN" council_response_has_grounding "$ACTIVE_VOTE" "$BOUNDARY_ROOT" &&
   COUNCIL_RUN_DIR="$ACTIVE_RUN" council_response_is_blind "$ACTIVE_VOTE" "$BOUNDARY_ROOT" &&
   ! COUNCIL_RUN_DIR="$ACTIVE_RUN" council_response_is_substantive "$ACTIVE_VOTE" "$BOUNDARY_ROOT" &&
   jq -e '.validation_result == "invalid-access" and .access_state == "failed" and .evidence_paths == []' <<< "$record" >/dev/null; then test_pass
else test_fail "active-run quotes admitted an unsupported approval"; fi

rm -r "$ACTIVE_RUN" "$TEST_TMP_DIR/active-run-alias"
rmdir "$BOUNDARY_ROOT/council output"

test_case "an explicitly selected symlinked evidence root remains valid"
cp "$OUTSIDE" "$BOUNDARY_ROOT/source.ts"
ln -s "$BOUNDARY_ROOT" "$TEST_TMP_DIR/selected-root"
_count_is 1 "$BOUNDARY_RESPONSE" "$TEST_TMP_DIR/selected-root"
rm "$BOUNDARY_ROOT/source.ts"

# Instrument the actual inline helper at its read/open boundary. This avoids a
# timing-dependent race fixture and records real traversal/read work.
INSTRUMENT="$TEST_TMP_DIR/instrument-grounding.py"
cat > "$INSTRUMENT" <<'PYTEST'
import atexit
import json
import os
import sys
from pathlib import Path

mode = os.environ["GROUNDING_TEST_MODE"]
target = Path(os.environ["GROUNDING_TEST_TARGET"]).resolve()
outside = os.environ["GROUNDING_TEST_OUTSIDE"]
original_read_text = Path.read_text
original_open = os.open
original_read = os.read
original_scandir = os.scandir
response = Path(sys.argv[2]).resolve()
source_fds = set()
metrics = {"source_bytes": 0, "source_opens": 0, "entries": 0}
replaced = False

@atexit.register
def save_metrics():
    Path(os.environ["GROUNDING_TEST_METRICS"]).write_text(json.dumps(metrics))

def grow():
    global replaced
    if not replaced:
        target.write_bytes(b"x" * 1_600_000 + Path(outside).read_bytes())
        replaced = True

def replace():
    global replaced
    if not replaced:
        if target.is_dir():
            target.rename(str(target) + ".saved")
        else:
            target.unlink()
        target.symlink_to(outside)
        replaced = True

def read_text(self, *args, **kwargs):
    if self == target:
        if mode == "replace":
            replace()
        elif mode == "grow":
            grow()
    result = original_read_text(self, *args, **kwargs)
    if self != response:
        metrics["source_bytes"] += len(result.encode("utf-8"))
        metrics["source_opens"] += 1
    return result

def open_file(path, flags, *args, **kwargs):
    if mode in ("replace", "root-replace") and path == target.name and "dir_fd" in kwargs:
        replace()
    descriptor = original_open(path, flags, *args, **kwargs)
    if not flags & os.O_DIRECTORY and path != sys.argv[1]:
        source_fds.add(descriptor)
        metrics["source_opens"] += 1
    return descriptor

def read_file(descriptor, size):
    if descriptor in source_fds and mode == "grow":
        grow()
    result = original_read(descriptor, size)
    if descriptor in source_fds:
        metrics["source_bytes"] += len(result)
    return result

class Listing:
    def __init__(self, path):
        # For the pruning case, fail if the helper enters the excluded subtree.
        same = os.fstat(path).st_ino == target.stat().st_ino if isinstance(path, int) else Path(path).resolve() == target
        if mode == "prune" and same:
            raise AssertionError("excluded tree was enumerated")
        if mode == "root-replace" and same:
            replace()
        self.listing = original_scandir(path)
        self.iterator = iter(self.listing)
        self.repeated = None
        self.count = 0
    def __enter__(self):
        return self
    def __exit__(self, *args):
        self.close()
    def close(self):
        self.listing.close()
    def __iter__(self):
        return self
    def __next__(self):
        if mode in ("entries", "files"):
            if self.count >= 25_000:
                raise StopIteration
            if self.repeated is None:
                self.repeated = next(entry for entry in self.iterator if entry.name == target.name)
            self.count += 1
            entry = self.repeated
        else:
            entry = next(self.iterator)
        metrics["entries"] += 1
        return entry

Path.read_text = read_text
os.open = open_file
os.read = read_file
os.scandir = Listing
if mode == "unsupported":
    del os.O_NOFOLLOW
sys.argv = sys.argv[1:]
exec(compile(sys.stdin.read(), "council-content-match", "exec"))
PYTEST

_instrumented_count() (
    export GROUNDING_TEST_MODE="$1" GROUNDING_TEST_TARGET="$2" GROUNDING_TEST_OUTSIDE="${3:-$OUTSIDE}"
    export GROUNDING_TEST_METRICS="$TEST_TMP_DIR/grounding-metrics.json"
    python3() { command python3 "$INSTRUMENT" "$@"; }
    council_response_content_match_count "$BOUNDARY_RESPONSE" "$BOUNDARY_ROOT"
)

test_case "a leaf replaced after metadata validation cannot supply evidence"
printf 'const initialValue = unrelatedValue;\n' > "$BOUNDARY_ROOT/race.ts"
actual="$(_instrumented_count replace "$BOUNDARY_ROOT/race.ts")"
if [[ "$actual" == 0 ]]; then test_pass
else test_fail "replacement symlink supplied $actual matched fragments"; fi
rm "$BOUNDARY_ROOT/race.ts"

test_case "file growth after its size check cannot supply evidence"
printf 'const initialValue = unrelatedValue;\n' > "$BOUNDARY_ROOT/race.ts"
actual="$(_instrumented_count grow "$BOUNDARY_ROOT/race.ts")"
if [[ "$actual" == 0 ]] && jq -e '.source_bytes <= 1500000' "$TEST_TMP_DIR/grounding-metrics.json" >/dev/null; then test_pass
else test_fail "a growing file supplied evidence or exceeded its read budget"; fi
rm "$BOUNDARY_ROOT/race.ts"

test_case "excluded trees are pruned before enumeration"
mkdir -p "$BOUNDARY_ROOT/node_modules"
cp "$OUTSIDE" "$BOUNDARY_ROOT/node_modules/source.ts"
if actual="$(_instrumented_count prune "$BOUNDARY_ROOT/node_modules")" && [[ "$actual" == 0 ]]; then test_pass
else test_fail "the scan entered an excluded dependency tree"; fi
rm "$BOUNDARY_ROOT/node_modules/source.ts"
rmdir "$BOUNDARY_ROOT/node_modules"

test_case "the active run is pruned before its artifacts are enumerated"
mkdir -p "$ACTIVE_RUN"
cp "$OUTSIDE" "$ACTIVE_RUN/generated.md"
if actual="$(COUNCIL_RUN_DIR="$ACTIVE_RUN" _instrumented_count prune "$ACTIVE_RUN")" && [[ "$actual" == 0 ]] &&
   jq -e '.source_bytes == 0 and .source_opens == 0' "$TEST_TMP_DIR/grounding-metrics.json" >/dev/null; then test_pass
else test_fail "the scan enumerated or read active-run artifacts"; fi
rm -r "$BOUNDARY_ROOT/council output"

test_case "non-source entries count toward the traversal budget"
printf 'unrelated\n' > "$BOUNDARY_ROOT/ignored.txt"
actual="$(_instrumented_count entries "$BOUNDARY_ROOT/ignored.txt")"
if [[ "$actual" == 0 ]] && jq -e '.entries <= 20000 and .source_bytes == 0' "$TEST_TMP_DIR/grounding-metrics.json" >/dev/null; then test_pass
else test_fail "non-source entries bypassed the traversal budget"; fi
rm "$BOUNDARY_ROOT/ignored.txt"

test_case "entry-budget exhaustion cannot admit an unverified approval"
printf 'unrelated\n' > "$BOUNDARY_ROOT/ignored.txt"
if ( export GROUNDING_TEST_MODE=entries GROUNDING_TEST_TARGET="$BOUNDARY_ROOT/ignored.txt" GROUNDING_TEST_OUTSIDE="$OUTSIDE" GROUNDING_TEST_METRICS="$TEST_TMP_DIR/grounding-metrics.json"
     python3() { command python3 "$INSTRUMENT" "$@"; }
     ! council_response_has_grounding "$ACTIVE_VOTE" "$BOUNDARY_ROOT" &&
     council_response_is_blind "$ACTIVE_VOTE" "$BOUNDARY_ROOT" &&
     ! council_response_is_substantive "$ACTIVE_VOTE" "$BOUNDARY_ROOT" ) &&
   jq -e '.entries == 20000 and .source_bytes == 0' "$TEST_TMP_DIR/grounding-metrics.json" >/dev/null; then test_pass
else test_fail "scan exhaustion admitted an unsupported approval"; fi
rm "$BOUNDARY_ROOT/ignored.txt"

test_case "source file attempts are capped even when files are oversized"
command python3 - "$BOUNDARY_ROOT/oversized.ts" <<'PYTEST'
from pathlib import Path
import sys
Path(sys.argv[1]).write_bytes(b"x" * 1_500_001)
PYTEST
actual="$(_instrumented_count files "$BOUNDARY_ROOT/oversized.ts")"
if [[ "$actual" == 0 ]] && jq -e '.source_opens <= 4000 and .entries <= 4000 and .source_bytes == 0' "$TEST_TMP_DIR/grounding-metrics.json" >/dev/null; then test_pass
else test_fail "oversized source files bypassed the attempt budget"; fi
rm "$BOUNDARY_ROOT/oversized.ts"

test_case "aggregate source reads stay within sixteen MiB"
command python3 - "$BOUNDARY_ROOT" <<'PYTEST'
from pathlib import Path
import sys
for index in range(18):
    (Path(sys.argv[1]) / f"large-{index}.ts").write_bytes(b"x" * 1_048_576)
PYTEST
actual="$(_instrumented_count measure "$BOUNDARY_ROOT/large-0.ts")"
if [[ "$actual" == 0 ]] && jq -e '.source_bytes > 0 and .source_bytes <= 16777216' "$TEST_TMP_DIR/grounding-metrics.json" >/dev/null; then test_pass
else test_fail "aggregate source reads exceeded sixteen MiB"; fi
rm "$BOUNDARY_ROOT"/large-*.ts

test_case "oversized responses cannot trigger a source scan"
cp "$OUTSIDE" "$BOUNDARY_ROOT/source.ts"
command python3 - "$BOUNDARY_RESPONSE" <<'PYTEST'
from pathlib import Path
import sys
with Path(sys.argv[1]).open("ab") as handle:
    handle.write(b"x" * 1_048_576)
PYTEST
actual="$(_instrumented_count measure "$BOUNDARY_ROOT/source.ts")"
if [[ "$actual" == 0 ]] && jq -e '.entries == 0 and .source_bytes == 0' "$TEST_TMP_DIR/grounding-metrics.json" >/dev/null; then test_pass
else test_fail "an oversized response triggered source reads"; fi
printf 'The function contains `%s`.\n' "$FRAGMENT" > "$BOUNDARY_RESPONSE"
rm "$BOUNDARY_ROOT/source.ts"

test_case "a root replaced after resolution cannot become new authority"
actual="$(_instrumented_count root-replace "$BOUNDARY_ROOT" "$TEST_TMP_DIR/outside-directory")"
if [[ "$actual" == 0 ]]; then test_pass
else test_fail "a replacement root supplied evidence"; fi
rm "$BOUNDARY_ROOT"
mv "$BOUNDARY_ROOT.saved" "$BOUNDARY_ROOT"

test_case "source special files cannot block or supply evidence"
mkfifo "$BOUNDARY_ROOT/special.ts"
_count_is 0 "$BOUNDARY_RESPONSE" "$BOUNDARY_ROOT"
rm "$BOUNDARY_ROOT/special.ts"

test_case "fenced and table quotes resolve with normalized whitespace"
printf '%s\n' "$FRAGMENT" 'return sourceValue + fallbackValue;' > "$BOUNDARY_ROOT/source.ts"
MULTIFORM="$TEST_TMP_DIR/multiform.md"
cat > "$MULTIFORM" <<'MD'
| Source | Finding |
| source.ts | `const boundedEvidenceMarker = sourceValue ?? fallbackValue;` |
```ts
return   sourceValue  + fallbackValue;
```
MD
_count_is 2 "$MULTIFORM" "$BOUNDARY_ROOT"
rm "$BOUNDARY_ROOT/source.ts"

test_case "candidate fragments have a fixed count budget"
command python3 - "$BOUNDARY_RESPONSE" "$BOUNDARY_ROOT/source.ts" <<'PYTEST'
from pathlib import Path
import sys
fragments = [f"const numberedEvidence{index} = sourceValue ?? fallbackValue;" for index in range(257)]
Path(sys.argv[1]).write_text("\n".join(f"`{fragment}`" for fragment in fragments))
Path(sys.argv[2]).write_text(fragments[-1])
PYTEST
_count_is 0 "$BOUNDARY_RESPONSE" "$BOUNDARY_ROOT"
rm "$BOUNDARY_ROOT/source.ts"

test_case "a single fragment cannot exceed its size budget"
command python3 - "$BOUNDARY_RESPONSE" "$BOUNDARY_ROOT/source.ts" <<'PYTEST'
from pathlib import Path
import sys
fragment = "const largeEvidence = sourceValue ?? '" + "x" * 4096 + "';"
Path(sys.argv[1]).write_text(f"`{fragment}`")
Path(sys.argv[2]).write_text(fragment)
PYTEST
_count_is 0 "$BOUNDARY_RESPONSE" "$BOUNDARY_ROOT"
rm "$BOUNDARY_ROOT/source.ts"
printf 'The function contains `%s`.\n' "$FRAGMENT" > "$BOUNDARY_RESPONSE"

test_case "directory nesting cannot exceed its depth budget"
command python3 - "$BOUNDARY_ROOT" "$FRAGMENT" <<'PYTEST'
from pathlib import Path
import sys
path = Path(sys.argv[1])
for _ in range(65):
    path /= "nested"
path.mkdir(parents=True)
(path / "source.ts").write_text(sys.argv[2])
PYTEST
_count_is 0 "$BOUNDARY_RESPONSE" "$BOUNDARY_ROOT"

# Exercise the live positive gate independently of response size and formatting.
test_case "live prose quote is substantive without inventing citation evidence"
PROSE_VOTE="$TEST_TMP_DIR/prose-vote.md"
sed 's/ VERDICT: APPROVE//' "$A4" > "$PROSE_VOTE"
printf '\nVERDICT: APPROVE\n' >> "$PROSE_VOTE"
record="$(OCTOPUS_COUNCIL_GROUNDING_MIN_CHARS=1 council_contribution_record_json "$PROSE_VOTE" "$ROOT" sha256:fixture)"
if ( OCTOPUS_COUNCIL_GROUNDING_MIN_CHARS=1; council_response_is_substantive "$PROSE_VOTE" "$ROOT" ) &&
   jq -e '.validation_result == "valid-unverified" and .access_state == "unverified" and .evidence_paths == [] and .comprehension_verified == false' <<< "$record" >/dev/null; then test_pass
else test_fail "content match lost its vote or invented validated citation evidence"; fi

test_case "a grounded review may state a data-verification limit"
if ( OCTOPUS_COUNCIL_GROUNDING_MIN_CHARS=1; council_response_is_substantive "$A1" "$ROOT" ); then test_pass
else test_fail "a source-backed review lost its truthful data caveat"; fi

test_case "an explicit access failure remains blind even with a matching quote"
printf 'I cannot read the repository files. `%s`\nVERDICT: APPROVE\n' "$FRAGMENT" > "$BOUNDARY_RESPONSE"
printf '%s\n' "$FRAGMENT" > "$BOUNDARY_ROOT/source.ts"
if council_response_is_blind "$BOUNDARY_RESPONSE" "$BOUNDARY_ROOT"; then test_pass
else test_fail "a quote overrode an explicit first-person access failure"; fi
rm "$BOUNDARY_ROOT/source.ts"

test_case "the positive gate respects fixture and missing-root modes"
if ( COUNCIL_FIXTURE=true; council_response_is_substantive "$B2" "$ROOT" ) &&
   council_response_is_substantive "$B2" "$TEST_TMP_DIR/nonexistent"; then test_pass
else test_fail "the positive gate changed fixture or missing-root behavior"; fi

test_case "Python unavailability retains the prior prose fallback"
if ( command() { if [[ "$*" == '-v python3' ]]; then return 1; fi; builtin command "$@"; }
     council_response_is_substantive "$B2" "$ROOT" ) &&
   [[ "$( command() { if [[ "$*" == '-v python3' ]]; then return 1; fi; builtin command "$@"; }
         council_response_content_match_count "$A4" "$ROOT" )" == 0 ]]; then test_pass
else test_fail "Python unavailability changed fallback behavior"; fi

test_case "validated citation path and line semantics remain intact"
ln -s "$ROOT/functions-v2/sailing-compare.ts" "$ROOT/inside-alias.ts"
ln -s "$OUTSIDE" "$ROOT/outside-alias.ts"
CITATIONS="$TEST_TMP_DIR/citations.md"
printf '%s\n' 'Inside inside-alias.ts:1; outside outside-alias.ts:1; traversal ../outside.ts:1; missing made-up.ts:1; range functions-v2/sailing-compare.ts:1-2; excessive functions-v2/sailing-compare.ts:99999.' > "$CITATIONS"
citations="$(council_response_evidence_paths_json "$CITATIONS" "$ROOT")"
if jq -e 'length == 2 and .[0].path == "inside-alias.ts" and .[1].path == "functions-v2/sailing-compare.ts" and all(.[]; .line == 1 and (.content_digest | startswith("sha256:")))' <<< "$citations" >/dev/null; then test_pass
else test_fail "validated path/line semantics changed: $citations"; fi

test_case "unsupported descriptor APIs retain the prose fallback without scanning"
if ( export GROUNDING_TEST_MODE=unsupported GROUNDING_TEST_TARGET="$ROOT/functions-v2/sailing-compare.ts" GROUNDING_TEST_OUTSIDE="$OUTSIDE" GROUNDING_TEST_METRICS="$TEST_TMP_DIR/grounding-metrics.json"
     python3() { command python3 "$INSTRUMENT" "$@"; }
     OCTOPUS_COUNCIL_GROUNDING_MIN_CHARS=1 council_response_is_substantive "$A4" "$ROOT" ) &&
   jq -e '.source_bytes == 0 and .source_opens == 0 and .entries == 0' "$TEST_TMP_DIR/grounding-metrics.json" >/dev/null; then test_pass
else test_fail "unsupported confinement read sources or created a false blind vote"; fi

test_case "ungrounded confident approval cannot produce a valid contribution"
record="$(council_contribution_record_json "$B2" "$ROOT" sha256:fixture)"
if ! council_response_is_substantive "$B2" "$ROOT" &&
   jq -e '.validation_result == "invalid-access" and .access_state == "failed" and .verdict == "APPROVE" and .evidence_paths == []' <<< "$record" >/dev/null; then test_pass
else test_fail "an ungrounded confident approval remained a valid contribution"; fi

test_summary
