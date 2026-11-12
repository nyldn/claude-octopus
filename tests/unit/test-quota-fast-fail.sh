#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Quota fast-fail + quota-dead cache (oco-2kw/48z/cbb)"

# Isolate the session cache to a tmp workspace.
FIXTURE="$(mktemp -d)"
export WORKSPACE_DIR="$FIXTURE"
trap 'rm -rf "$FIXTURE"' EXIT

# shellcheck disable=SC1091
source "$PROJECT_ROOT/scripts/lib/quota-watcher.sh"
# stub log so the watcher subshell doesn't error when log is undefined
log() { :; }

test_quota_dead_cache_roundtrip() {
    test_case "octo_quota_mark_dead / octo_quota_is_dead roundtrip"
    if octo_quota_is_dead perplexity; then test_fail "dead before mark"; return; fi
    octo_quota_mark_dead perplexity
    if octo_quota_is_dead perplexity && ! octo_quota_is_dead gemini; then test_pass
    else test_fail "mark/is_dead mismatch"; fi
}

test_quota_dead_cache_dedup() {
    test_case "marking the same provider twice does not duplicate"
    octo_quota_mark_dead codex; octo_quota_mark_dead codex
    local n
    n=$(grep -cxF codex "$(octo_quota_dead_file)" 2>/dev/null | tr -d ' ')
    [[ "$n" == "1" ]] && test_pass || test_fail "expected 1 codex entry, got $n"
}

test_pattern_matches_terminal_errors() {
    test_case "quota pattern matches 401 / insufficient_quota / exhausted"
    local tmp_ok="$FIXTURE/m.txt" tmp_no="$FIXTURE/n.txt"
    printf 'You exceeded your current quota insufficient_quota code 401\n' > "$tmp_ok"
    printf 'all good, normal output\n' > "$tmp_no"
    if quota_watcher_has_match "$tmp_ok" /dev/null && ! quota_watcher_has_match "$tmp_no" /dev/null; then
        test_pass
    else test_fail "pattern match incorrect"; fi
}

test_watcher_marks_dead_on_match() {
    test_case "watcher marks a provider quota-dead when it sees a terminal error"
    local errf="$FIXTURE/w-err.txt" outf="$FIXTURE/w-out.txt"
    : > "$errf"; : > "$outf"
    # Short-lived target we manage ourselves (no orphaned sleep, no self-kill race).
    # Quota line is written AFTER the watcher starts (it truncates temp files on entry).
    _noop_kill() { kill "$1" 2>/dev/null || true; }
    ( sleep 1; echo "exhausted your capacity (insufficient_quota)" >> "$errf"; sleep 4 ) &
    local target=$!
    local wpid
    wpid=$(start_quota_watcher "$target" "$errf" "$outf" _noop_kill "test" "fakeprov")
    # Poll up to ~6s for the watcher to detect + mark.
    local i marked=0
    for i in $(seq 1 12); do
        if octo_quota_is_dead fakeprov; then marked=1; break; fi
        sleep 0.5
    done
    kill "$target" 2>/dev/null || true
    wait "$target" 2>/dev/null || true
    stop_quota_watcher "$wpid"
    [[ "$marked" == "1" ]] && test_pass || test_fail "watcher did not mark fakeprov dead on quota match"
}

test_watcher_records_the_line_it_fast_failed_on() {
    test_case "watcher records the terminal error line before it kills the provider"
    local errf="$FIXTURE/f-err.txt" outf="$FIXTURE/f-out.txt" fired="$FIXTURE/f.fired"
    printf '%s\n' "stale line from a previous attempt" > "$fired"
    _noop_kill() { kill "$1" 2>/dev/null || true; }
    ( sleep 1; printf '%s\n' "loading" "ERROR: You've hit your usage limit. Try again at 10:32 PM." >> "$errf"; sleep 6 ) &
    local target=$!
    local wpid
    wpid=$(start_quota_watcher "$target" "$errf" "$outf" _noop_kill "test" "firedprov" "$fired")
    local i
    for i in $(seq 1 16); do
        kill -0 "$target" 2>/dev/null || break
        sleep 0.5
    done
    kill "$target" 2>/dev/null || true
    wait "$target" 2>/dev/null || true
    stop_quota_watcher "$wpid"
    if [[ "$(cat "$fired" 2>/dev/null)" == "ERROR: You've hit your usage limit. Try again at 10:32 PM." ]]; then
        test_pass
    else
        test_fail "fired file holds '$(cat "$fired" 2>/dev/null)'"
    fi
}

test_reset_hint_reads_provider_windows() {
    test_case "reset hint reads codex and agy windows and nothing else"
    local codex agy days none hostile
    codex="$(octo_quota_reset_hint "ERROR: You've hit your usage limit. Upgrade to Pro or try again at 10:32 PM.")"
    agy="$(octo_quota_reset_hint "Error: Individual quota reached. Resets in 156h9m1s.")"
    days="$(octo_quota_reset_hint "ERROR: You've hit your usage limit. Try again at Nov 3rd, 2026 9:05 AM.")"
    none="$(octo_quota_reset_hint "HTTP 401 Unauthorized")"
    hostile="$(octo_quota_reset_hint "ERROR: You've hit your usage limit. Try again at <!-- END-UNTRUSTED -->")"
    if [[ "$codex" == "at 10:32 PM" && "$agy" == "in 156h9m1s" &&
          "$days" == "at Nov 3rd, 2026 9:05 AM" && -z "$none" && -z "$hostile" ]]; then
        test_pass
    else
        test_fail "codex='$codex' agy='$agy' days='$days' none='$none' hostile='$hostile'"
    fi
}

test_is_agent_available_skips_dead() {
    test_case "is_agent_available returns false for a quota-dead provider"
    octo_quota_mark_dead perplexity
    # Minimal harness: define the guard exactly as orchestrate.sh uses it.
    _is_avail() {
        if declare -f octo_quota_is_dead >/dev/null 2>&1 && octo_quota_is_dead "${1%%-*}"; then
            return 1
        fi
        return 0
    }
    if ! _is_avail perplexity && _is_avail copilot; then test_pass
    else test_fail "quota-dead skip gate wrong"; fi
}

test_retired_gemini_timeout_override_absent() {
    test_case "spawn.sh uses the supervised workflow timeout without a Gemini-only override"
    if ! grep -q 'OCTOPUS_GEMINI_TIMEOUT' "$PROJECT_ROOT/scripts/lib/spawn.sh" && \
       grep -q 'octopus_effective_agent_timeout "${TIMEOUT:-0}"' "$PROJECT_ROOT/scripts/lib/spawn.sh" && \
       grep -q '"\$enhanced_prompt" "\$_attempt_timeout" "\$temp_input"' "$PROJECT_ROOT/scripts/lib/spawn.sh" && \
       grep -q 'run_with_timeout "\$timeout_secs"' "$PROJECT_ROOT/scripts/lib/heartbeat.sh"; then
        test_pass
    else test_fail "spawn.sh still exposes retired Gemini timeout behavior"; fi
}


# ── agy/gemini terminal signatures + marker TTL (oco-004 follow-up) ──────────

test_pattern_matches_agy_and_gemini_terminal_errors() {
    test_case "quota pattern matches agy 'Individual quota reached' and gemini IneligibleTierError"
    local errf="$FIXTURE/agy-gemini.err" outf="$FIXTURE/agy-gemini.out"
    : > "$outf"
    printf 'Error: Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 156h9m1s.\n' > "$errf"
    if ! quota_watcher_has_match "$errf" "$outf"; then
        test_fail "agy 'Individual quota reached' not matched by OCTOPUS_QUOTA_PATTERN"
        return
    fi
    printf 'An unexpected critical error occurred:IneligibleTierError: This client is no longer supported for Gemini Code Assist for individuals.\n' > "$errf"
    if ! quota_watcher_has_match "$errf" "$outf"; then
        test_fail "gemini IneligibleTierError not matched by OCTOPUS_QUOTA_PATTERN"
        return
    fi
    test_pass
}

test_quota_dead_mark_expires() {
    test_case "quota-dead mark expires after TTL so a recovered provider is not retired forever"
    local f
    f="$(octo_quota_dead_file)"
    mkdir -p "$(dirname "$f")"
    : > "$f"
    octo_quota_mark_dead "ttl-probe"
    if ! octo_quota_is_dead "ttl-probe"; then
        test_fail "fresh mark should read as dead"
        return
    fi
    # Age the marker well past the default TTL.
    touch -t 202001010000 "$f"
    if octo_quota_is_dead "ttl-probe"; then
        test_fail "stale mark still reads as dead — provider would never recover"
        return
    fi
    # TTL=0 preserves the previous permanent behaviour for operators who want it.
    if ! OCTOPUS_QUOTA_DEAD_TTL=0 octo_quota_is_dead "ttl-probe"; then
        test_fail "OCTOPUS_QUOTA_DEAD_TTL=0 should disable expiry"
        return
    fi
    test_pass
}

test_check_providers_applies_dead_marker_to_every_provider() {
    test_case "shared readiness routes every available provider through the quota-dead downgrade"
    # The downgrade used to be opt-in per renderer. It now belongs to the
    # registry-backed readiness evaluator consumed by check-providers.sh.
    local checker="$PROJECT_ROOT/scripts/helpers/check-providers.sh"
    local readiness="$PROJECT_ROOT/scripts/lib/preflight.sh"
    if grep -Fq 'octo_provider_readiness_legacy' "$checker" &&
       grep -Fq 'octo_quota_is_dead "$provider"' "$readiness" &&
       ! grep -Eq '^(_octo_provider_state|provider_status)\(\)' "$checker"; then
        test_pass
    else
        test_fail "quota-dead policy is not centralized in shared readiness"
    fi
}

# A dead-mark written by a shim running under `env -i` must be visible to the
# reader. agy-exec.sh marks dead from inside the isolated
# environment; if WORKSPACE_DIR is not forwarded they write to the
# $HOME/.claude-octopus fallback while check-providers.sh reads
# $CLAUDE_PLUGIN_DATA, so the provider keeps advertising `available` and is
# reseated every session.
test_provider_env_forwards_workspace_dir() {
    test_case "build_provider_env forwards WORKSPACE_DIR into every isolated env"
    local out missing=""
    for p in agy codex; do
        out="$(WORKSPACE_DIR=/tmp/octo-wsdir-probe bash -c '
            cd "$1" || exit 1
            source scripts/lib/validation.sh 2>/dev/null
            source scripts/lib/provider-routing.sh
            build_provider_env "$2"
            printf "%s\n" "${PROVIDER_ENV_ARRAY[@]}"
        ' _ "$PROJECT_ROOT" "$p" 2>/dev/null)"
        printf '%s\n' "$out" | grep -q '^WORKSPACE_DIR=/tmp/octo-wsdir-probe$' || missing="$missing $p"
    done
    if [[ -z "$missing" ]]; then
        test_pass
    else
        test_fail "WORKSPACE_DIR not forwarded for:$missing"
    fi
}

test_dead_mark_survives_isolated_env() {
    test_case "a dead-mark written under the isolated env is visible to the reader"
    local th pd res
    th="$(mktemp -d)"; pd="$(mktemp -d)"
    res="$(HOME="$th" WORKSPACE_DIR="$pd" bash -c '
        cd "$1" || exit 1
        source scripts/lib/validation.sh 2>/dev/null
        source scripts/lib/provider-routing.sh
        build_provider_env agy
        "${PROVIDER_ENV_ARRAY[@]}" bash -c "cd \"$1\"; source scripts/lib/quota-watcher.sh; octo_quota_mark_dead agy 0" _ "$1"
        source scripts/lib/quota-watcher.sh
        octo_quota_is_dead agy && echo DEAD || echo ALIVE
    ' _ "$PROJECT_ROOT" 2>/dev/null)"
    rm -rf "$th" "$pd"
    if [[ "$res" == "DEAD" ]]; then
        test_pass
    else
        test_fail "mark written under env -i was invisible to the reader (got '$res')"
    fi
}

test_quota_cleanup_preserves_supervisor_owned_groups() {
    test_case "quota cleanup stops owned groups when supervisor cleanup is delayed"
    if (
        source "$PROJECT_ROOT/scripts/lib/heartbeat.sh"
        source "$PROJECT_ROOT/scripts/lib/spawn.sh"
        export QUOTA_SUPERVISION_FIXTURE="$FIXTURE/supervision"
        mkdir -p "$QUOTA_SUPERVISION_FIXTURE"
        eval "$(declare -f _octo_timeout_supervisor_handle_signal |
            sed '1s/_octo_timeout_supervisor_handle_signal/real_supervisor_handle_signal/')"
        _octo_timeout_supervisor_handle_signal() {
            # Model a handler scheduled after the old one-second KILL grace.
            sleep 3
            real_supervisor_handle_signal "$@"
        }
        cat > "$QUOTA_SUPERVISION_FIXTURE/provider" <<'PROVIDER'
#!/usr/bin/env bash
cat >/dev/null
printf '%s\n' "$$" > "$QUOTA_SUPERVISION_FIXTURE/provider.pid"
printf '%s\n' 'ERROR: Individual quota reached.' >&2
exec sleep 30
PROVIDER
        chmod +x "$QUOTA_SUPERVISION_FIXTURE/provider"
        quota_start=$SECONDS
        # The outer substitution must finish, not just the worker's capture.
        # A stranded 60-second timer otherwise retains its output descriptor.
        worker=$(
            set -m
            (
                octo_capture_current_shell_pid || exit 1
                PID_FILE="$QUOTA_SUPERVISION_FIXTURE/pids"
                worker_identity=$(octopus_pid_register "$OCTO_CAPTURED_SHELL_PID" fixture quota) || exit 1
                watcher=$(start_quota_watcher "$OCTO_CAPTURED_SHELL_PID" \
                    "$QUOTA_SUPERVISION_FIXTURE/err" "$QUOTA_SUPERVISION_FIXTURE/out" \
                    quota_watcher_kill_spawn_children quota supervision-fixture \
                    "$QUOTA_SUPERVISION_FIXTURE/fired" "$worker_identity")
                capture_rc=0
                octopus_capture_provider_output question 60 "$QUOTA_SUPERVISION_FIXTURE/in" \
                    "$QUOTA_SUPERVISION_FIXTURE/out" "$QUOTA_SUPERVISION_FIXTURE/err" \
                    "$QUOTA_SUPERVISION_FIXTURE/provider" || capture_rc=$?
                printf '%s\n' "$capture_rc" > "$QUOTA_SUPERVISION_FIXTURE/status"
                stop_quota_watcher "$watcher"
            ) &
            printf '%s\n' "$!"
        )
        elapsed=$((SECONDS - quota_start))
        [[ "$worker" =~ ^[0-9]+$ && "$elapsed" -lt 15 && \
           -s "$QUOTA_SUPERVISION_FIXTURE/fired" ]] || exit 1
        [[ "$(cat "$QUOTA_SUPERVISION_FIXTURE/status")" =~ ^(137|143)$ ]] || exit 1
        provider_pid=$(cat "$QUOTA_SUPERVISION_FIXTURE/provider.pid")
        provider_state=$(ps -o stat= -p "$provider_pid" 2>/dev/null || true)
        [[ -z "$provider_state" || "$provider_state" == *Z* ]]
    ); then test_pass
    else test_fail "quota cleanup orphaned a provider/timer or lost termination status"; fi
}

test_quota_cleanup_stops_reparented_group_member() {
    local admission_mode="${1:-stable}"
    test_case "quota cleanup stops a reparented helper with $admission_mode leader admission"
    if (
        source "$PROJECT_ROOT/scripts/lib/heartbeat.sh"
        source "$PROJECT_ROOT/scripts/lib/spawn.sh"
        export QUOTA_ORPHAN_FIXTURE="$FIXTURE/orphan-$admission_mode"
        export QUOTA_ADMISSION_MODE="$admission_mode"
        mkdir -p "$QUOTA_ORPHAN_FIXTURE"
        cat > "$QUOTA_ORPHAN_FIXTURE/provider.py" <<'PROVIDER'
import os
from pathlib import Path
import signal
import sys
import time

root = Path(os.environ["QUOTA_ORPHAN_FIXTURE"])
sys.stdin.read()
(root / "provider.pid").write_text(str(os.getpid()))
intermediate = os.fork()
if intermediate == 0:
    if os.fork() != 0:
        os._exit(0)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    (root / "helper.pid").write_text(str(os.getpid()))
    while True:
        time.sleep(1)
os.waitpid(intermediate, 0)
while not (root / "helper.pid").exists():
    time.sleep(0.01)
print("ERROR: Individual quota reached.", file=sys.stderr, flush=True)
time.sleep(30)
PROVIDER
        if [[ "$admission_mode" == reaped ]]; then
            eval "$(declare -f _octo_timeout_job_is_running |
                sed '1s/_octo_timeout_job_is_running/real_job_is_running/')"
            _octo_timeout_job_is_running() {
                local status=0
                real_job_is_running "$@" || status=$?
                if [[ "$1" == "${provider_pid:-}" && "$status" == 0 &&
                      -e "$QUOTA_ORPHAN_FIXTURE/helper.pid" &&
                      ! -e "$QUOTA_ORPHAN_FIXTURE/reaped" ]]; then
                    # The supervisor owns this unreaped job. Reap it after the
                    # real running check, then hold its pending group cleanup.
                    kill -KILL "$provider_pid"
                    wait "$provider_pid" 2>/dev/null || true
                    touch "$QUOTA_ORPHAN_FIXTURE/reaped"
                    while :; do /bin/sleep 0.02; done
                fi
                return "$status"
            }
        elif [[ "$admission_mode" == churn ]]; then
            cat > "$QUOTA_ORPHAN_FIXTURE/churn.py" <<'CHURN'
from contextlib import contextmanager
import importlib.util
import os
from pathlib import Path
import subprocess
import sys

spec = importlib.util.spec_from_file_location("process_control", sys.argv.pop(1))
control = importlib.util.module_from_spec(spec)
spec.loader.exec_module(control)
root = Path(os.environ["QUOTA_ORPHAN_FIXTURE"])
original_scandir = os.scandir
original_read = Path.read_bytes
pending = {}

@contextmanager
def scandir(path):
    if str(path) != "/proc":
        with original_scandir(path) as entries:
            yield entries
        return
    # Each real procfs snapshot contains an unrelated process that exits just
    # before its stat read. Complete global scans therefore never stabilize.
    with subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"]) as child:
        pending[str(Path("/proc", str(child.pid), "stat"))] = child
        try:
            with original_scandir(path) as entries:
                yield iter(list(entries))
        finally:
            child.kill()
            child.wait()
            pending.clear()

def read(path):
    child = pending.get(str(path))
    if child is not None:
        child.kill()
        child.wait()
        with (root / "churn").open("a") as record:
            record.write("exit\n")
    return original_read(path)

os.scandir = scandir
Path.read_bytes = read
sys.exit(control.main())
CHURN
            eval "$(declare -f _octo_pid_python_run | sed '1s/_octo_pid_python_run/real_pid_python_run/')"
            _octo_pid_python_run() {
                if [[ "$1" == */process_control.py ]]; then
                    real_pid_python_run "$QUOTA_ORPHAN_FIXTURE/churn.py" "$@"
                else
                    real_pid_python_run "$@"
                fi
            }
        fi
        quota_start=$SECONDS
        worker=$(
            set -m
            (
                octo_capture_current_shell_pid || exit 1
                PID_FILE="$QUOTA_ORPHAN_FIXTURE/pids"
                worker_identity=$(octopus_pid_register "$OCTO_CAPTURED_SHELL_PID" fixture quota) || exit 1
                watcher=$(start_quota_watcher "$OCTO_CAPTURED_SHELL_PID" \
                    "$QUOTA_ORPHAN_FIXTURE/err" "$QUOTA_ORPHAN_FIXTURE/out" \
                    quota_watcher_kill_spawn_children quota orphan-fixture \
                    "$QUOTA_ORPHAN_FIXTURE/fired" "$worker_identity")
                capture_rc=0
                octopus_capture_provider_output question 16 "$QUOTA_ORPHAN_FIXTURE/in" \
                    "$QUOTA_ORPHAN_FIXTURE/out" "$QUOTA_ORPHAN_FIXTURE/err" \
                    python3 "$QUOTA_ORPHAN_FIXTURE/provider.py" || capture_rc=$?
                printf '%s\n' "$capture_rc" > "$QUOTA_ORPHAN_FIXTURE/status"
                stop_quota_watcher "$watcher"
            ) &
            printf '%s\n' "$!"
        )
        elapsed=$((SECONDS - quota_start))
        helper_pid=$(cat "$QUOTA_ORPHAN_FIXTURE/helper.pid")
        helper_state=$(ps -o stat= -p "$helper_pid" 2>/dev/null || true)
        # Always clean the inert helper, even when the regression fails.
        _octo_pid_python_run "${PROJECT_ROOT}/scripts/helpers/process_control.py" \
            "$helper_pid" --frozen >/dev/null 2>&1 || true
        [[ "$worker" =~ ^[0-9]+$ && "$elapsed" -lt 15 && \
           -s "$QUOTA_ORPHAN_FIXTURE/fired" ]] || exit 1
        [[ "$(cat "$QUOTA_ORPHAN_FIXTURE/status")" =~ ^(137|143)$ ]] || exit 1
        if [[ "$admission_mode" == reaped ]]; then
            [[ -e "$QUOTA_ORPHAN_FIXTURE/reaped" ]] || exit 1
        fi
        [[ -z "$helper_state" || "$helper_state" == *Z* ]]
    ); then test_pass
    else test_fail "quota cleanup left an already-reparented group member alive"; fi
}

test_quota_cleanup_retries_refusal() {
    test_case "quota cleanup retries transient refusal and bounds persistent refusal"
    if (
        source "${QUOTA_RETRY_LIB_ROOT:-$PROJECT_ROOT}/scripts/lib/quota-watcher.sh"
        sleep() { command sleep 0.02; }
        for mode in recover refuse; do
            retry_dir="$FIXTURE/retry-$mode"
            mkdir -p "$retry_dir"
            _retry_stop() {
                [[ "${2:-}" == registered-worker ]] || return 1
                printf 'attempt\n' >> "$retry_dir/attempts"
                [[ "$mode" == recover && "$(wc -l < "$retry_dir/attempts")" -ge 3 ]] || return 1
                kill "$1"
            }
            octo_quota_mark_dead() { printf 'dead\n' >> "$retry_dir/dead"; }
            log() { printf '%s\n' "$1" >> "$retry_dir/log"; }
            command sleep 30 &
            target=$!
            watcher=$(start_quota_watcher "$target" "$retry_dir/err" "$retry_dir/out" \
                _retry_stop retry retry-fixture "$retry_dir/fired" registered-worker)
            printf 'ERROR: Individual quota reached.\n' > "$retry_dir/err"
            for attempt in {1..250}; do
                count=$(wc -l < "$retry_dir/attempts" 2>/dev/null || printf 0)
                if [[ "$mode" == recover && "$count" -ge 3 ]] || \
                   { [[ "$mode" == refuse ]] && grep -q ERROR "$retry_dir/log" 2>/dev/null; }; then break; fi
                sleep 0.02
            done
            sleep 0.02
            count=$(wc -l < "$retry_dir/attempts" 2>/dev/null || printf 0)
            kill "$target" 2>/dev/null || true
            wait "$target" 2>/dev/null || true
            stop_quota_watcher "$watcher"
            expected=3
            [[ "$mode" != refuse ]] || expected=5
            [[ "$count" -eq "$expected" && -s "$retry_dir/fired" ]] || exit 1
            [[ "$(wc -l < "$retry_dir/dead")" -eq 1 ]] || exit 1
            [[ "$(grep -c WARN "$retry_dir/log")" -eq 1 ]] || exit 1
            [[ "$mode" != refuse ]] || grep -q ERROR "$retry_dir/log" || exit 1
        done
    ); then test_pass
    else test_fail "cleanup was not retried safely or exceeded its retry bound"; fi
}

test_quota_cleanup_refuses_unverified_processes() {
    test_case "refused native quota cleanup never falls back to numeric signals"
    if (
        source "$PROJECT_ROOT/scripts/lib/spawn.sh"
        _octo_pid_python_run() { touch "$FIXTURE/native-refusal-reached"; return 1; }
        kill() { touch "$FIXTURE/unsafe-signal"; }
        pkill() { touch "$FIXTURE/unsafe-signal"; }
        log() { printf '%s\n' "$2" > "$FIXTURE/cleanup-refusal"; }
        cleanup_rc=0
        quota_watcher_kill_spawn_children 999999 fixture-identity || cleanup_rc=$?
        [[ "$cleanup_rc" != 0 && ! -e "$FIXTURE/unsafe-signal" &&
           -e "$FIXTURE/native-refusal-reached" ]] &&
            grep -Fq 'owned descendants could not be verified' "$FIXTURE/cleanup-refusal"
    ); then test_pass
    else test_fail "unverified cleanup signalled a numeric PID or claimed success"; fi
}

test_quota_dead_cache_roundtrip
test_quota_dead_cache_dedup
test_provider_env_forwards_workspace_dir
test_dead_mark_survives_isolated_env
test_pattern_matches_terminal_errors
test_watcher_marks_dead_on_match
test_watcher_records_the_line_it_fast_failed_on
test_reset_hint_reads_provider_windows
test_is_agent_available_skips_dead
test_retired_gemini_timeout_override_absent
test_pattern_matches_agy_and_gemini_terminal_errors
test_quota_dead_mark_expires
test_check_providers_applies_dead_marker_to_every_provider
test_quota_cleanup_preserves_supervisor_owned_groups
test_quota_cleanup_stops_reparented_group_member
test_quota_cleanup_stops_reparented_group_member reaped
test_quota_cleanup_stops_reparented_group_member churn
test_quota_cleanup_retries_refusal
test_quota_cleanup_refuses_unverified_processes

test_summary
