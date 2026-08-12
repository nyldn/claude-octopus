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

FIXTURE="$TEST_TMP_DIR/atomic-lock"
mkdir -p "$FIXTURE"

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
    mkdir -p "$f.lock"; echo "$live" > "$f.lock/pid"
    echo $(( $(date +%s) - 120 )) > "$f.lock/ts"
    # reclaim helper must leave a live holder's lock intact
    _atomic_reclaim_stale_lock "$f.lock" 30
    local intact="no"; [[ -d "$f.lock" && "$(cat "$f.lock/pid" 2>/dev/null)" == "$live" ]] && intact="yes"
    kill "$live" 2>/dev/null || true
    rm -rf "$f.lock"
    if [[ "$intact" == "yes" ]]; then test_pass; else test_fail "live holder's lock was reclaimed"; fi
}

test_reclaims_hard_aged_live_pid_lock() {
    test_case "a hard-aged lock is reclaimed when its PID was recycled"
    local f="$FIXTURE/e.json"; echo '{"n":1}' > "$f"
    sleep 20 & local recycled=$!
    mkdir -p "$f.lock"; echo "$recycled" > "$f.lock/pid"
    echo $(( $(date +%s) - 301 )) > "$f.lock/ts"
    _atomic_reclaim_stale_lock "$f.lock" 30
    local reclaimed="no"; [[ ! -e "$f.lock" ]] && reclaimed="yes"
    kill "$recycled" 2>/dev/null || true
    rm -rf "$f.lock"
    if [[ "$reclaimed" == "yes" ]]; then test_pass; else test_fail "hard-aged recycled-PID lock was preserved"; fi
}

test_reclaims_aged_out_lock() {
    test_case "a lock older than the age threshold is reclaimed even if PID unknown"
    local f="$FIXTURE/d.json"; echo '{"n":1}' > "$f"
    mkdir -p "$f.lock"   # no pid/ts recorded, but force an old ts
    echo $(( $(date +%s) - 120 )) > "$f.lock/ts"
    _atomic_reclaim_stale_lock "$f.lock" 30
    if [[ ! -e "$f.lock" ]]; then test_pass; else test_fail "aged lock not reclaimed"; fi
}

test_reclaims_aged_empty_lock() {
    test_case "an aged lock with no initialized metadata is reclaimed"
    local f="$FIXTURE/i.json"; echo '{"n":1}' > "$f"
    mkdir -p "$f.lock"
    touch -t 202001010000 "$f.lock"
    _atomic_reclaim_stale_lock "$f.lock" 30
    if [[ ! -e "$f.lock" ]]; then test_pass; else test_fail "aged empty lock not reclaimed"; fi
}

test_release_requires_matching_owner_token() {
    test_case "an old writer cannot release a successor's lock"
    local f="$FIXTURE/f.json"; echo '{"n":1}' > "$f"
    mkdir -p "$f.lock"; echo "successor-token" > "$f.lock/token"
    _atomic_release_owned_lock "$f.lock" "old-token"
    local preserved="no"; [[ -d "$f.lock" ]] && preserved="yes"
    _atomic_release_owned_lock "$f.lock" "successor-token"
    if [[ "$preserved" == "yes" && ! -e "$f.lock" ]]; then test_pass
    else test_fail "release removed the wrong owner or retained the matching owner"; fi
}

test_signal_cleanup_terminates_operation() {
    test_case "TERM cleans the lock and terminates the interrupted update"
    local f="$FIXTURE/g.json"; echo '{"n":1}' > "$f"
    local fake_bin="$FIXTURE/signal-bin"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/jq" <<'EOF'
#!/usr/bin/env bash
last=""
for arg in "$@"; do last="$arg"; done
kill -TERM "$PPID"
sleep 0.1
/bin/cat "$last"
EOF
    chmod +x "$fake_bin/jq"

    local prior_term_trap
    prior_term_trap=$(trap -p TERM)
    trap ':' TERM
    local trap_before trap_after
    trap_before=$(trap -p TERM)
    local rc=0
    (
        PATH="$fake_bin:$PATH"
        atomic_json_update "$f" '.n=2' 2>/dev/null
    ) || rc=$?
    trap_after=$(trap -p TERM)
    if [[ -n "$prior_term_trap" ]]; then eval "$prior_term_trap"; else trap - TERM; fi
    if [[ "$rc" -ne 0 && ! -e "$f.lock" && "$trap_after" == "$trap_before" ]]; then test_pass
    else test_fail "interrupted update returned rc=$rc lock=$([[ -e "$f.lock" ]] && echo left || echo clean) caller_trap_preserved=$([[ "$trap_after" == "$trap_before" ]] && echo yes || echo no)"; fi
}

test_signal_during_lock_initialization() {
    test_case "TERM during post-mkdir initialization does not leak an empty lock"
    local f="$FIXTURE/h.json"; echo '{"n":1}' > "$f"
    local pid_marker="$FIXTURE/init-owner.pid" release_marker="$FIXTURE/init-release"

    local rc=0
    (
        # Pause the successful lock mkdir after the directory exists but before
        # atomic_json_update can initialize pid/ts/token. Intercepting the
        # Bash-3-only owner-PID fallback misses this window on Bash 4+, where
        # BASHPID is available (and made this regression test fail on Ubuntu).
        mkdir() {
            command mkdir "$@"
            local mkdir_rc=$?
            if [[ "$mkdir_rc" -eq 0 && "$1" == "$f.lock" ]]; then
                /bin/sh -c 'printf "%s\n" "$PPID"' > "$pid_marker"
                local i=0
                while [[ ! -f "$release_marker" && "$i" -lt 100 ]]; do
                    sleep 0.1
                    i=$((i + 1))
                done
            fi
            return "$mkdir_rc"
        }
        atomic_json_update "$f" '.n=2' 2>/dev/null
    ) &
    local worker=$!
    local i=0
    while [[ ! -s "$pid_marker" && "$i" -lt 100 ]]; do sleep 0.1; i=$((i + 1)); done
    local target=""; target=$(cat "$pid_marker" 2>/dev/null || true)
    if [[ "$target" =~ ^[0-9]+$ ]]; then kill -TERM "$target" 2>/dev/null || true; fi
    : > "$release_marker"
    wait "$worker" || rc=$?
    if [[ "$target" =~ ^[0-9]+$ && "$rc" -ne 0 && ! -e "$f.lock" ]]; then test_pass
    else test_fail "initialization signal target=${target:-missing} returned rc=$rc lock=$([[ -e "$f.lock" ]] && echo left || echo clean)"; fi
}

test_empty_path_guard
test_normal_update_no_lock_left
test_reclaims_dead_holder_lock
test_respects_live_holder
test_reclaims_hard_aged_live_pid_lock
test_reclaims_aged_out_lock
test_reclaims_aged_empty_lock
test_release_requires_matching_owner_token
test_signal_cleanup_terminates_operation
test_signal_during_lock_initialization

test_summary
