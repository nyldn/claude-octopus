#!/usr/bin/env bash
# #559: stale-lock recovery for atomic_json_update. A holder killed before its
# release trap runs leaves the mkdir lock dir behind, blocking every later
# caller until timeout. These tests cover the reclaim (dead holder) vs respect
# (live holder) behavior, plus the empty-path guard.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
log() { :; }
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/validation.sh"

test_suite "atomic_json_update stale-lock recovery (#559)"

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT INT TERM

# a PID that is guaranteed not running: spawn a trivial child and reap it
dead_pid() { ( : ) & local p=$!; wait "$p" 2>/dev/null; echo "$p"; }

test_empty_path_guard() {
    test_case "atomic_json_update rejects an empty json_file"
    if atomic_json_update "" '.x=1' 2>/dev/null; then
        test_fail "empty path should return non-zero"
    else
        test_pass
    fi
}

test_normal_update_no_lock_left() {
    test_case "normal update applies jq and leaves no lock behind"
    local f="$FIXTURE/a.json"; echo '{"n":1}' > "$f"
    atomic_json_update "$f" '.n=2' && local ok=1 || local ok=0
    local n; n=$(jq -r '.n' "$f" 2>/dev/null)
    if [[ "$ok" == "1" && "$n" == "2" && ! -e "$f.lock" ]]; then test_pass
    else test_fail "ok=$ok n=$n lock_exists=$([[ -e "$f.lock" ]] && echo yes || echo no)"; fi
}

test_reclaims_dead_holder_lock() {
    test_case "a leaked lock from a dead holder is reclaimed (no timeout)"
    local f="$FIXTURE/b.json"; echo '{"n":1}' > "$f"
    # simulate a crashed holder: lock dir with a dead PID and fresh timestamp
    mkdir -p "$f.lock"; echo "$(dead_pid)" > "$f.lock/pid"; date +%s > "$f.lock/ts"
    local start end
    start=$(date +%s)
    atomic_json_update "$f" '.n=9' && local ok=1 || local ok=0
    end=$(date +%s)
    local n; n=$(jq -r '.n' "$f" 2>/dev/null)
    # must succeed AND fast (well under the 5s timeout) — proves it reclaimed
    if [[ "$ok" == "1" && "$n" == "9" && $((end - start)) -lt 4 && ! -e "$f.lock" ]]; then test_pass
    else test_fail "ok=$ok n=$n elapsed=$((end-start))s lock=$([[ -e "$f.lock" ]] && echo left || echo clean)"; fi
}

test_respects_live_holder() {
    test_case "a live holder's lock is NOT reclaimed"
    local f="$FIXTURE/c.json"; echo '{"n":1}' > "$f"
    sleep 20 & local live=$!
    mkdir -p "$f.lock"; echo "$live" > "$f.lock/pid"; date +%s > "$f.lock/ts"
    # reclaim helper must leave a live holder's lock intact
    _atomic_reclaim_stale_lock "$f.lock" 30
    local intact="no"; [[ -d "$f.lock" && "$(cat "$f.lock/pid" 2>/dev/null)" == "$live" ]] && intact="yes"
    kill "$live" 2>/dev/null || true
    rm -rf "$f.lock"
    if [[ "$intact" == "yes" ]]; then test_pass; else test_fail "live holder's lock was reclaimed"; fi
}

test_reclaims_aged_out_lock() {
    test_case "a lock older than the age threshold is reclaimed even if PID unknown"
    local f="$FIXTURE/d.json"; echo '{"n":1}' > "$f"
    mkdir -p "$f.lock"   # no pid/ts recorded, but force an old ts
    echo $(( $(date +%s) - 120 )) > "$f.lock/ts"
    _atomic_reclaim_stale_lock "$f.lock" 30
    if [[ ! -e "$f.lock" ]]; then test_pass; else test_fail "aged lock not reclaimed"; fi
}

test_empty_path_guard
test_normal_update_no_lock_left
test_reclaims_dead_holder_lock
test_respects_live_holder
test_reclaims_aged_out_lock

test_summary
