#!/usr/bin/env bash
# Hook declarations must fit what the Codex host actually supports (#766).
#
# Codex CLI does not support async hooks and caps every SessionEnd hook at
# three seconds. Declaring more than it honours does not buy a longer budget —
# it buys a warning on every fresh Codex process and a manifest that lies about
# the budget its hooks actually get:
#
#   warning: skipping async hook in .../hooks.json: async hooks are not supported yet
#   warning: clamping SessionEnd hook timeout to 3s in .../hooks.json
#   warning: clamping SessionEnd hook timeout to 3s in .../hooks.json
#
# #767 removed the async declaration after measuring that telemetry-webhook.sh
# already backgrounds its own curl (37ms against a deliberately 5s endpoint),
# so the flag was redundant with the script's design rather than load-bearing.
#
# The two SessionEnd clamps were deliberately left open at that point, on the
# argument that lowering a declared timeout could truncate work that genuinely
# needs longer under Claude Code. Measurement did not support that argument:
#
#   session-end.sh             142 ms average, 350 ms cold
#   workflow-verification.sh    20 ms average
#   session-end.sh (stressed)  360 ms — 2.7 MB session.json, 6000 errors,
#                                       3000 phases, 300 memory dirs
#
# Neither hook makes a network call, sleeps, or loops unboundedly; the work is
# a handful of jq reads over one session file plus a glob over memory dirs. The
# declared 15s and 10s were 40x the worst measured case, so three seconds keeps
# roughly 8x headroom over a stressed run while matching what Codex enforces.
#
# This suite pins that: the manifest may not promise a budget the host will not
# honour, and no async hook may reappear.
set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Codex hook-manifest compatibility (#766)"

MANIFEST="$PROJECT_ROOT/hooks/hooks.json"

# Codex's limits, named rather than sprinkled as bare numbers.
CODEX_SESSION_END_CAP=3

test_case "the hook manifest exists and is valid JSON"
if [[ -f "$MANIFEST" ]] && jq empty "$MANIFEST" 2>/dev/null; then
    test_pass
else
    test_fail "missing or malformed $MANIFEST"
fi

# Guards a vacuous pass: if the query below stops finding hooks because the
# manifest shape changed, every assertion after it would trivially succeed.
test_case "SessionEnd hooks are discoverable in the manifest"
session_end_count="$(jq '[.hooks.SessionEnd[]?.hooks[]?] | length' "$MANIFEST" 2>/dev/null || echo 0)"
if [[ "${session_end_count:-0}" -ge 2 ]]; then
    test_pass
else
    test_fail "found ${session_end_count} SessionEnd hooks; expected at least 2 — the manifest shape changed and the assertions below would be vacuous"
fi

test_case "no SessionEnd hook declares a timeout above Codex's ${CODEX_SESSION_END_CAP}s cap"
over="$(jq -r --argjson cap "$CODEX_SESSION_END_CAP" '
    [.hooks.SessionEnd[]?.hooks[]? | select((.timeout // 0) > $cap)
     | "\(.command | split("/") | last)=\(.timeout)s"] | join(" ")
' "$MANIFEST" 2>/dev/null)"
if [[ -z "$over" ]]; then
    test_pass
else
    test_fail "declares a budget Codex will not honour: ${over} — Codex clamps SessionEnd to ${CODEX_SESSION_END_CAP}s and warns on every fresh process"
fi

# Codex skips async hooks outright, so the behaviour is lost rather than
# degraded. Any hook needing off-thread work should background it itself, the
# way telemetry-webhook.sh does.
test_case "no hook declares async, which Codex skips rather than degrades"
async="$(jq -r '[.hooks | to_entries[] | .value[]?.hooks[]? | select(.async == true)
                 | (.command | split("/") | last)] | join(" ")' "$MANIFEST" 2>/dev/null)"
if [[ -z "$async" ]]; then
    test_pass
else
    test_fail "async hooks are skipped entirely by Codex: ${async} — background the work inside the script instead"
fi

# The cap applies to SessionEnd specifically. Other events keep their own
# budgets, so this must not silently become a global assertion.
test_case "non-SessionEnd hooks are not forced to the SessionEnd cap"
other_max="$(jq '[.hooks | to_entries[] | select(.key != "SessionEnd")
                  | .value[]?.hooks[]?.timeout // 0] | max // 0' "$MANIFEST" 2>/dev/null)"
if [[ "${other_max:-0}" -gt 0 ]]; then
    test_pass
else
    test_fail "no non-SessionEnd timeouts found — this suite would not notice if the cap were applied globally by mistake"
fi

# The measured basis for choosing 3s. If either script grows work that pushes it
# near the cap, that is a real problem and should be caught here rather than as
# truncated output in production.
test_case "both SessionEnd hooks complete well inside the cap"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/data"
slowest=0
slow_name=""
for hook in session-end workflow-verification; do
    script="$PROJECT_ROOT/hooks/${hook}.sh"
    [[ -f "$script" ]] || continue
    start="$(python3 -c 'import time;print(int(time.time()*1000))')"
    env HOME="$sandbox" \
        CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" \
        CLAUDE_PLUGIN_DATA="$sandbox/data" \
        bash "$script" </dev/null >/dev/null 2>&1
    end="$(python3 -c 'import time;print(int(time.time()*1000))')"
    elapsed=$(( end - start ))
    if [[ "$elapsed" -gt "$slowest" ]]; then
        slowest="$elapsed"
        slow_name="${hook}.sh"
    fi
done
# Half the cap: comfortably above the ~360ms stressed measurement, low enough
# that real growth trips it before Codex starts truncating.
budget_ms=$(( CODEX_SESSION_END_CAP * 1000 / 2 ))
if [[ "$slowest" -gt 0 && "$slowest" -lt "$budget_ms" ]]; then
    test_pass
elif [[ "$slowest" -eq 0 ]]; then
    test_fail "no SessionEnd hook ran, so this measured nothing"
else
    test_fail "${slow_name} took ${slowest}ms, past the ${budget_ms}ms warning line and approaching Codex's ${CODEX_SESSION_END_CAP}s cap"
fi

test_summary
