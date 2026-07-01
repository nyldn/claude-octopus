#!/usr/bin/env bash
# #498: coverage for the review.finding + synthesis lifecycle events —
# event contract (emit shape) + HUD rendering (no write-only telemetry) +
# the jq extraction review.sh uses to derive per-finding attributes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
log() { :; }
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/events.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/event-monitor.sh"

test_suite "lifecycle events: review.finding + synthesis (#498)"

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT INT TERM

# ── review.finding event shape ────────────────────────────────────────────
test_review_finding_shape() {
    test_case "review.finding emits provider/severity/message/round attributes"
    export OCTO_EVENT_LOG="$FIXTURE/rf.jsonl"
    : > "$OCTO_EVENT_LOG"
    octo_event_emit "review.finding" provider=codex severity=normal message="null deref in auth" round=1
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$OCTO_EVENT_LOG" <<'PY' || { test_fail "review.finding JSON invalid"; return; }
import json, sys
row = json.loads(open(sys.argv[1]).readline())
a = row["attributes"]
assert row["event"] == "review.finding", row["event"]
assert a["provider"] == "codex"
assert a["severity"] == "normal"
assert a["message"] == "null deref in auth"
assert a["round"] == "1"
PY
    else
        grep -q '"event":"review.finding"' "$OCTO_EVENT_LOG" || { test_fail "event name missing"; return; }
    fi
    test_pass
}

# ── synthesis event shape ───────────────────────────────────────────────────
test_synthesis_shape() {
    test_case "synthesis emits phase/provider/count attributes"
    export OCTO_EVENT_LOG="$FIXTURE/syn.jsonl"
    : > "$OCTO_EVENT_LOG"
    octo_event_emit "synthesis" phase=review provider=claude-sonnet count=7
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$OCTO_EVENT_LOG" <<'PY' || { test_fail "synthesis JSON invalid"; return; }
import json, sys
row = json.loads(open(sys.argv[1]).readline())
a = row["attributes"]
assert row["event"] == "synthesis", row["event"]
assert a["phase"] == "review"
assert a["provider"] == "claude-sonnet"
assert a["count"] == "7"
PY
    else
        grep -q '"event":"synthesis"' "$OCTO_EVENT_LOG" || { test_fail "event name missing"; return; }
    fi
    test_pass
}

# ── HUD renders the new events (no write-only telemetry) ─────────────────────
test_hud_renders_review_finding() {
    test_case "HUD formatter surfaces review.finding severity + message"
    local line out
    line='{"timestamp":"2026-07-01T00:00:00Z","event":"review.finding","source":"octopus","pid":1,"session_id":"s","attributes":{"provider":"codex","severity":"normal","message":"boom","round":"1"}}'
    out="$(octo_hud_format_line "$line")" || { test_fail "formatter returned non-zero"; return; }
    assert_contains "$out" "review.finding"
    assert_contains "$out" "provider=codex"
    assert_contains "$out" "severity=normal"
    assert_contains "$out" "msg=boom"
    test_pass
}

test_hud_renders_synthesis() {
    test_case "HUD formatter surfaces synthesis count"
    local line out
    line='{"timestamp":"2026-07-01T00:00:00Z","event":"synthesis","source":"octopus","pid":1,"session_id":"s","attributes":{"phase":"parallel","provider":"agy","count":"5"}}'
    out="$(octo_hud_format_line "$line")" || { test_fail "formatter returned non-zero"; return; }
    assert_contains "$out" "synthesis"
    assert_contains "$out" "provider=agy"
    assert_contains "$out" "count=5"
    test_pass
}

# ── the jq extraction review.sh uses to derive per-finding attributes ────────
test_review_finding_extraction() {
    test_case "review.sh jq extraction yields severity<TAB>title per finding"
    local findings tsv
    findings='[{"severity":"normal","title":"A","file":"x"},{"title":"B"},{"severity":"nit"}]'
    tsv="$(printf '%s' "$findings" | jq -r '.[]? | [(.severity // "unknown"), (.title // .message // "")] | @tsv' 2>/dev/null)"
    # 3 findings → 3 lines; missing severity → "unknown"; missing title → ""
    assert_equals "3" "$(printf '%s\n' "$tsv" | grep -c .)"
    assert_contains "$tsv" "normal	A"
    assert_contains "$tsv" "unknown	B"
    assert_contains "$tsv" "nit	"
    test_pass
}

test_review_finding_shape
test_synthesis_shape
test_hud_renders_review_finding
test_hud_renders_synthesis
test_review_finding_extraction

test_summary
