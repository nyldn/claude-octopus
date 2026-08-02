#!/usr/bin/env bash
set -uo pipefail

# tests/unit/test-gemini-via-agy-consent.sh
#
# gemini-via-agy is the migration path off Google's sunset Gemini Code Assist
# free tier (issue #715). It is now a `decision: required` progressive-disclosure
# feature, so the recorded answer — not just the env var — has to reach dispatch.
#
# The pre-existing coverage in test-agy-provider.sh greps the three source files
# for the literal string OCTOPUS_GEMINI_VIA_AGY. That passes even when the
# routing is broken, and it passed unchanged while the sites were switched from
# reading the env var to reading the ledger. These cases execute the path.

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "gemini-via-agy consent routing (issue #715)"

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

# Resolve the gemini dispatch command under a given ledger/env state. Sources in
# orchestrate.sh's order so the accessor in agent-utils.sh is present exactly as
# it is at runtime.
resolve_gemini_cmd() {
    env -i \
        PATH="$PATH" \
        HOME="$FIXTURE/home" \
        OCTOPUS_STATE_DIR="$FIXTURE/state" \
        PLUGIN_DIR="$PROJECT_ROOT" \
        ${1:+OCTOPUS_GEMINI_VIA_AGY="$1"} \
        bash -c '
            cd "$0" || exit 1
            log() { :; }
            source scripts/lib/validation.sh          2>/dev/null
            source scripts/lib/model-cache-path.sh    2>/dev/null
            source scripts/lib/model-resolver.sh      2>/dev/null
            source scripts/lib/provider-routing.sh    2>/dev/null
            source scripts/lib/features.sh            2>/dev/null
            source scripts/lib/dispatch.sh            2>/dev/null
            source scripts/lib/agent-utils.sh         2>/dev/null
            get_agent_command gemini probe researcher 2>/dev/null
        ' "$PROJECT_ROOT"
}

record_choice() {
    env -i PATH="$PATH" HOME="$FIXTURE/home" OCTOPUS_STATE_DIR="$FIXTURE/state" \
        bash -c '
            cd "$0" || exit 1
            source scripts/lib/features.sh 2>/dev/null
            octo_features_record gemini-via-agy "$1" 9.57.1 >/dev/null 2>&1
        ' "$PROJECT_ROOT" "$1"
}

reset_ledger() { rm -rf "$FIXTURE/state" "$FIXTURE/home"; mkdir -p "$FIXTURE/state" "$FIXTURE/home"; }

# ── default (no answer recorded, no override) ────────────────────────────────
reset_ledger
test_case "with no recorded answer the direct gemini path is kept"
out="$(resolve_gemini_cmd "")"
if [[ -n "$out" && "$out" != *"agy-exec.sh"* ]]; then
    test_pass
else
    test_fail "default should resolve a non-empty gemini command; got: $out"
fi

# ── recorded answer drives routing, with no env var set ──────────────────────
reset_ledger
record_choice 1
test_case "a recorded 'through Antigravity' answer reroutes gemini to agy-exec"
out="$(resolve_gemini_cmd "")"
if [[ "$out" == *"agy-exec.sh"* ]]; then
    test_pass
else
    test_fail "recorded choice was ignored — the answer must reach dispatch; got: $out"
fi

reset_ledger
record_choice 0
test_case "a recorded 'keep the direct path' answer leaves gemini on gemini-cli"
out="$(resolve_gemini_cmd "")"
if [[ -n "$out" && "$out" != *"agy-exec.sh"* ]]; then
    test_pass
else
    test_fail "recorded 0 should keep a non-empty direct gemini command; got: $out"
fi

# ── env override still wins in both directions ───────────────────────────────
reset_ledger
record_choice 0
test_case "OCTOPUS_GEMINI_VIA_AGY=1 overrides a recorded 0"
out="$(resolve_gemini_cmd 1)"
if [[ "$out" == *"agy-exec.sh"* ]]; then
    test_pass
else
    test_fail "session override should win over the ledger; got: $out"
fi

reset_ledger
record_choice 1
test_case "OCTOPUS_GEMINI_VIA_AGY=0 overrides a recorded 1"
out="$(resolve_gemini_cmd 0)"
if [[ -n "$out" && "$out" != *"agy-exec.sh"* ]]; then
    test_pass
else
    test_fail "session override should win over the ledger; got: $out"
fi

# ── the feature is actually raised to an existing user ───────────────────────
test_case "gemini-via-agy is offered to a user upgrading from an older version"
offered="$(env -i PATH="$PATH" HOME="$FIXTURE/home2" OCTOPUS_STATE_DIR="$FIXTURE/state2" \
    bash -c '
        cd "$0" || exit 1
        mkdir -p "$1/bin"
        printf "#!/bin/sh\nexit 0\n" > "$1/bin/gemini"; chmod +x "$1/bin/gemini"
        PATH="$1/bin:$PATH"
        source scripts/lib/features.sh 2>/dev/null
        octo_features_seed_watermark "9.56.1" >/dev/null 2>&1
        octo_features_is_offerable gemini-via-agy && echo yes || echo no
    ' "$PROJECT_ROOT" "$FIXTURE")"
if [[ "$offered" == "yes" ]]; then
    test_pass
else
    test_fail "feature must be raised to existing users, else the migration is never surfaced"
fi

# ── documented env aliases keep working in both directions ───────────────────
# octo_features_choice only passes an env value through when it is a declared
# choice, and this feature's choices are the literal "1"/"0". Routing the sites
# at the ledger without normalising the env first silently dropped `=true`,
# returning already-migrated users to the failing direct path.
reset_ledger
for alias_on in true on yes; do
    test_case "OCTOPUS_GEMINI_VIA_AGY=$alias_on still routes through agy"
    out="$(resolve_gemini_cmd "$alias_on")"
    if [[ "$out" == *"agy-exec.sh"* ]]; then
        test_pass
    else
        test_fail "documented truthy alias '$alias_on' was dropped; got: $out"
    fi
done

reset_ledger
record_choice 1
for alias_off in false off no; do
    test_case "OCTOPUS_GEMINI_VIA_AGY=$alias_off overrides a recorded 1"
    out="$(resolve_gemini_cmd "$alias_off")"
    if [[ -n "$out" && "$out" != *"agy-exec.sh"* ]]; then
        test_pass
    else
        test_fail "documented falsy alias '$alias_off' lost to the ledger; got: $out"
    fi
done

# ── the question actually reaches the picker ─────────────────────────────────
# octo_features_is_offerable never consults prereq; prereq is enforced in
# octo_features_prompt_manifest and octo_features_actionable_count, which are
# what decide whether a user is asked. Reverting prereq to agy-cli, or typoing
# it into an unknown check (which fails closed), would silently drop the
# question for every gemini-only user — the original shipping bug — while an
# is_offerable-only assertion stayed green.
test_case "the question is emitted for a gemini-only user with no agy installed"
manifest_out="$(env -i PATH="/usr/bin:/bin" HOME="$FIXTURE/home3" OCTOPUS_STATE_DIR="$FIXTURE/state3" \
    bash -c '
        cd "$0" || exit 1
        mkdir -p "$1/bin3"
        printf "#!/bin/sh\nexit 0\n" > "$1/bin3/gemini"; chmod +x "$1/bin3/gemini"
        export PATH="$1/bin3:/usr/bin:/bin"
        command -v agy >/dev/null 2>&1 && { echo "PRECONDITION-FAILED: agy on PATH"; exit 0; }
        source scripts/lib/features.sh 2>/dev/null
        octo_features_seed_watermark "9.56.1" >/dev/null 2>&1
        octo_features_prompt_manifest 2>/dev/null
    ' "$PROJECT_ROOT" "$FIXTURE")"
if [[ "$manifest_out" == *"PRECONDITION-FAILED"* ]]; then
    test_fail "test precondition broken: agy is on PATH, so this cannot prove the gemini-only case"
elif printf '%s' "$manifest_out" | grep -q "^Q.*gemini-via-agy"; then
    test_pass
else
    test_fail "no question row for a gemini-only user — the migration would never be surfaced"
fi

test_case "answering the question stops it being asked again"
answered="$(env -i PATH="$PATH" HOME="$FIXTURE/home4" OCTOPUS_STATE_DIR="$FIXTURE/state4" \
    bash -c '
        cd "$0" || exit 1
        source scripts/lib/features.sh 2>/dev/null
        octo_features_seed_watermark "9.56.1" >/dev/null 2>&1
        octo_features_record gemini-via-agy 0 9.57.1 >/dev/null 2>&1
        octo_features_is_offerable gemini-via-agy && echo yes || echo no
    ' "$PROJECT_ROOT")"
if [[ "$answered" == "no" ]]; then
    test_pass
else
    test_fail "a recorded answer must be sticky, including the 'keep current behaviour' answer"
fi

# ── the accessor is the single read point ────────────────────────────────────
# Matches ${OCTOPUS_GEMINI_VIA_AGY... in any brace form, so a reintroduced read
# written as ${OCTOPUS_GEMINI_VIA_AGY} is caught too. The bare name would be too
# broad: comments in spawn.sh and agent-sync.sh still mention the variable.
test_case "no dispatch site reads OCTOPUS_GEMINI_VIA_AGY directly"
stray="$(grep -rln '\${OCTOPUS_GEMINI_VIA_AGY' \
    "$PROJECT_ROOT/scripts/lib/dispatch.sh" \
    "$PROJECT_ROOT/scripts/lib/spawn.sh" \
    "$PROJECT_ROOT/scripts/lib/agent-sync.sh" 2>/dev/null || true)"
if [[ -z "$stray" ]]; then
    test_pass
else
    test_fail "these still bypass octo_gemini_via_agy_active: $stray"
fi

test_summary
