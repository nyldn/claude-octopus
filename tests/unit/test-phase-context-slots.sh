#!/usr/bin/env bash
# Phases can hand off named findings, not just interpolated prose (#724).
#
# research.sh built phase 2's prompt as "Based on this research synthesis:
# $synthesis". Anything the sending phase knew but did not write into that
# string was gone at the boundary, and nothing recorded that it was lost.
#
# The .phases registry already existed (status/output/timestamp per phase); what
# was missing was a place for a phase to deposit *content* a later phase reads
# by key. save_phase_slot/get_phase_slot add that alongside the registry rather
# than replacing it.
#
# The hyphenated-phase and injection cases below are not hypothetical: the same
# registry's reader spliced the phase name into a jq filter, so `debate-probe`
# parsed as subtraction and every debate-gate checkpoint was write-only (#743).
# Slots take a phase AND a key, so both are bound with --arg here.
set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Phase context slots (#724)"

SESSION_LIB="$PROJECT_ROOT/scripts/lib/session.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

# Extract only the slot functions. Sourcing session.sh wholesale runs top-level
# code (check_resume_session carries a `read -p`), which hangs a test run.
SLOTS="$FIXTURE/slots.sh"
for fn in save_phase_slot get_phase_slot list_phase_slots; do
    sed -n "/^${fn}()/,/^}/p" "$SESSION_LIB" >> "$SLOTS"
done

printf '{"workflow":"research","phases":{}}\n' > "$FIXTURE/session.json"

# Always returns 0: the framework sources `set -euo pipefail`, so a probing call
# that legitimately fails would abort the suite before it could be reported.
slot() {
    { bash -c '
        SESSION_FILE="$1"
        source "$2"
        case "$3" in
            set)  save_phase_slot "$4" "$5" "$6" ;;
            get)  get_phase_slot "$4" "$5" ;;
            list) list_phase_slots "$4" | tr "\n" " " ;;
        esac
    ' _ "$FIXTURE/session.json" "$SLOTS" "$@" 2>/dev/null || true; }
}

test_case "the slot helpers were extracted"
if [[ -s "$SLOTS" ]] && grep -q 'save_phase_slot' "$SLOTS" && grep -q 'get_phase_slot' "$SLOTS"; then
    test_pass
else
    test_fail "could not extract the slot functions from session.sh — nothing below is meaningful"
fi

test_case "a slot round-trips"
slot set empathize synthesis "pain points and unmet needs" >/dev/null
got="$(slot get empathize synthesis)"
if [[ "$got" == "pain points and unmet needs" ]]; then test_pass; else test_fail "got '$got'"; fi

test_case "a hyphenated phase name round-trips"
slot set debate-probe verdict "codex dissented" >/dev/null
got="$(slot get debate-probe verdict)"
if [[ "$got" == "codex dissented" ]]; then
    test_pass
else
    test_fail "got '$got' — a hyphenated phase parses as subtraction unless bound with --arg (#743)"
fi

test_case "an unfilled slot reads empty rather than failing"
got="$(slot get empathize never-written)"
if [[ -z "$got" ]]; then
    test_pass
else
    test_fail "expected empty, got '$got' — a missing handoff must degrade, not abort a run"
fi

test_case "an unknown phase reads empty"
got="$(slot get no-such-phase synthesis)"
if [[ -z "$got" ]]; then test_pass; else test_fail "got '$got'"; fi

test_case "slots are additive within a phase"
slot set empathize themes "three behavioural clusters" >/dev/null
a="$(slot get empathize synthesis)"
b="$(slot get empathize themes)"
if [[ "$a" == "pain points and unmet needs" && "$b" == "three behavioural clusters" ]]; then
    test_pass
else
    test_fail "writing a second key disturbed the first: synthesis='$a' themes='$b'"
fi

test_case "re-running a phase overwrites its own key, not another phase's"
slot set empathize synthesis "revised synthesis" >/dev/null
a="$(slot get empathize synthesis)"
b="$(slot get debate-probe verdict)"
if [[ "$a" == "revised synthesis" && "$b" == "codex dissented" ]]; then
    test_pass
else
    test_fail "overwrite leaked across phases: empathize='$a' debate-probe='$b'"
fi

# Distinguishes "not recorded" from "recorded empty" without guessing key names.
test_case "list_phase_slots names what a phase filled"
got="$(slot list empathize)"
if grep -q 'synthesis' <<< "$got" && grep -q 'themes' <<< "$got"; then
    test_pass
else
    test_fail "expected synthesis and themes, got '$got'"
fi

# Slot keys and phase names come from workflow code, so this input is reachable.
test_case "a key containing jq syntax is looked up, not evaluated"
slot set empathize 'x"] | keys' "injected" >/dev/null
got="$(slot get empathize 'x"] | keys')"
if [[ "$got" == "injected" ]]; then
    test_pass
else
    test_fail "expected 'injected' via key lookup, got '$got'"
fi

# Static guards, so a later refactor cannot reintroduce the splice.
test_case "both slot helpers bind phase and key with --arg"
body="$(cat "$SLOTS")"
if [[ "$(grep -c -- '--arg key' <<< "$body")" -ge 2 ]] && [[ "$(grep -c -- '--arg phase' <<< "$body")" -ge 2 ]]; then
    test_pass
else
    test_fail "slot helpers must bind both phase and key as data"
fi

# The consumer. A slot API nothing uses proves nothing about the handoff.
test_case "research.sh writes and reads the empathize synthesis slot"
r="$PROJECT_ROOT/scripts/lib/research.sh"
if grep -q 'save_phase_slot "empathize" "synthesis"' "$r" && grep -q 'get_phase_slot "empathize" "synthesis"' "$r"; then
    test_pass
else
    test_fail "research.sh must both record and consume the slot, or the contract is unexercised"
fi

# The handoff must still work where jq is missing or the session file is absent,
# because that is the state most CI and first-run environments are in.
test_case "research.sh falls back to the interpolated prose when no slot exists"
if grep -q '_handoff_synthesis="$synthesis"' "$r"; then
    test_pass
else
    test_fail "research.sh must default to the prior free-text value so a missing slot degrades instead of emptying the prompt"
fi

test_summary
