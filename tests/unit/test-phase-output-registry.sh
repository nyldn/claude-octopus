#!/usr/bin/env bash
# Phase-output registry round-trip (issue #724).
#
# save_session_checkpoint() records .phases[<name>] = {status, output, timestamp}
# and get_phase_output() reads the output path back. That registry is the
# structured phase handoff #724 asked for — it already existed — but the reader
# was broken for any phase name jq cannot parse as a bare field path.
#
# workflows.sh:3300 writes `save_session_checkpoint "debate-${gate_slug}"`. The
# reader's filter was `jq -r ".phases.$phase.output"`, which parses
# `debate-probe` as subtraction and fails with `probe/0 is not defined`. Every
# debate-gate checkpoint was therefore write-only, and splicing a phase name into
# a jq program is an injection vector besides.
set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Phase output registry round-trip (#724)"

SESSION_LIB="$PROJECT_ROOT/scripts/lib/session.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

# Extract only the reader. Sourcing session.sh wholesale executes top-level code
# (check_resume_session carries a `read -p`), which hangs a test run.
READER="$FIXTURE/reader.sh"
sed -n '/^get_phase_output()/,/^}/p' "$SESSION_LIB" > "$READER"

# A session file in exactly the shape save_session_checkpoint writes, including
# the hyphenated debate-gate key from workflows.sh:3300.
cat > "$FIXTURE/session.json" <<'JSON'
{
  "workflow": "embrace",
  "status": "in_progress",
  "phases": {
    "probe":        { "status": "completed", "output": "/tmp/probe-1.md" },
    "debate-probe": { "status": "completed", "output": "/tmp/gate-probe.md" },
    "probe\"] | keys": { "status": "completed", "output": "/tmp/inj.md" }
  }
}
JSON

# Always returns 0: the framework sources `set -euo pipefail`, so a probing call
# that legitimately fails (which is the point of the hyphenated case) would
# otherwise abort the whole suite before it could be reported.
read_phase() {
    { bash -c '
        SESSION_FILE="$1"
        source "$2"
        get_phase_output "$3" 2>/dev/null
    ' _ "$FIXTURE/session.json" "$READER" "$1" 2>/dev/null || true; } | tail -1
}

test_case "a plain phase name reads back"
got="$(read_phase probe)"
if [[ "$got" == "/tmp/probe-1.md" ]]; then test_pass; else test_fail "expected /tmp/probe-1.md, got '$got'"; fi

# The bug. workflows.sh writes this shape for every debate gate.
test_case "a hyphenated phase name reads back"
got="$(read_phase debate-probe)"
if [[ "$got" == "/tmp/gate-probe.md" ]]; then
    test_pass
else
    test_fail "expected /tmp/gate-probe.md, got '$got' — jq parses 'debate-probe' as subtraction unless bound via --arg"
fi

test_case "an unrecorded phase yields empty, not an error string"
got="$(read_phase never-ran)"
if [[ -z "$got" ]]; then test_pass; else test_fail "expected empty, got '$got'"; fi

# Phase names come from workflow code and gate slugs, so this input is reachable.
test_case "a phase name containing jq syntax is looked up, not evaluated"
got="$(read_phase 'probe"] | keys')"
if [[ "$got" == "/tmp/inj.md" ]]; then
    test_pass
else
    test_fail "expected /tmp/inj.md via key lookup, got '$got'"
fi

# Static guards, so a later refactor cannot quietly reintroduce the splice.
test_case "get_phase_output binds the phase with --arg"
fn="$(cat "$READER")"
if grep -q -- '--arg' <<< "$fn"; then test_pass; else test_fail "reader must bind the phase with --arg"; fi

test_case "get_phase_output does not interpolate the phase into the jq program"
# Strip comments first: the fix documents the old broken form, and that prose
# would otherwise trip this guard.
code="$(grep -v '^[[:space:]]*#' <<< "$fn")"
if grep -q 'phases\.\$' <<< "$code"; then
    test_fail "reader still splices the phase name into the filter"
else
    test_pass
fi

test_case "save_session_checkpoint writes with --arg phase (unchanged)"
writer="$(sed -n '/^save_session_checkpoint()/,/^}/p' "$SESSION_LIB")"
if grep -q -- '--arg phase' <<< "$writer"; then test_pass; else test_fail "writer should bind phase with --arg"; fi

test_summary
