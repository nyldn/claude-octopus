#!/usr/bin/env bash
# council-wait.sh: efficient wait on the council completion beacon.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

WAIT="$PROJECT_ROOT/scripts/helpers/council-wait.sh"

test_suite "council-wait"

# Guarded runner: captures stdout in $out and exit code in $rc without tripping
# set -e on the helper's intentional non-zero exits (timeout=2, usage=64).
out=""; rc=0
_runwait() { rc=0; out="$(bash "$WAIT" "$@" 2>/dev/null)" || rc=$?; }

_mkrun() { # _mkrun <pool> <run_id> <state> [valid_summary]
    local pool="$1" rid="$2" state="$3" valid="${4:-yes}" rd="$1/$2"
    mkdir -p "$rd"
    printf '{"state":"%s","run_id":"%s"}\n' "$state" "$rid" > "$rd/run-status.json"
    if [[ "$state" == "finished" ]]; then
        if [[ "$valid" == "yes" ]]; then printf '{"status":"completed","quorum":{"met":true}}\n' > "$rd/summary.json"
        else printf '{bad json' > "$rd/summary.json"; fi
    fi
    printf '%s' "$rd"
}

test_case "finished run prints its summary.json path and exits 0"
pool="$(mktemp -d "$TEST_TMP_DIR/p1.XXXXXX")"
rd="$(_mkrun "$pool" 20260101-000000-00aaaa finished)"
_runwait --pool "$pool" --interval 1 --timeout 5
if [[ $rc -eq 0 && "$out" == "$rd/summary.json" ]]; then test_pass; else test_fail "rc=$rc out=$out want=$rd/summary.json"; fi

test_case "a running run times out with exit 2 (no false completion)"
pool="$(mktemp -d "$TEST_TMP_DIR/p2.XXXXXX")"
_mkrun "$pool" 20260101-000000-00bbbb running >/dev/null
_runwait --pool "$pool" --interval 1 --timeout 2
if [[ $rc -eq 2 ]]; then test_pass; else test_fail "rc=$rc want 2"; fi

test_case "awaits the NEWEST run in the pool, not a stale earlier one"
pool="$(mktemp -d "$TEST_TMP_DIR/p3.XXXXXX")"
_mkrun "$pool" 20260101-000000-00aaaa finished >/dev/null      # stale older, finished
_mkrun "$pool" 20260101-010000-00cccc running >/dev/null       # newest, still running
_runwait --pool "$pool" --interval 1 --timeout 2
if [[ $rc -eq 2 ]]; then test_pass; else test_fail "picked the stale finished run (rc=$rc, expected timeout on newest-running)"; fi

test_case "a finished beacon with torn/invalid summary.json is not reported complete"
pool="$(mktemp -d "$TEST_TMP_DIR/p4.XXXXXX")"
_mkrun "$pool" 20260101-000000-00dddd finished no >/dev/null   # finished state but bad summary
_runwait --pool "$pool" --interval 1 --timeout 2
if [[ $rc -eq 2 ]]; then test_pass; else test_fail "reported complete on invalid summary (rc=$rc)"; fi

test_case "returns promptly when the run flips to finished mid-wait"
pool="$(mktemp -d "$TEST_TMP_DIR/p5.XXXXXX")"
rd="$(_mkrun "$pool" 20260101-020000-00eeee running)"
( sleep 2; printf '{"status":"completed"}\n' > "$rd/summary.json"
  printf '{"state":"finished","run_id":"20260101-020000-00eeee"}\n' > "$rd/run-status.json" ) &
flip_pid=$!
start=$(date +%s)
_runwait --pool "$pool" --interval 1 --timeout 20
elapsed=$(( $(date +%s) - start ))
wait "$flip_pid" 2>/dev/null || true
if [[ $rc -eq 0 && "$out" == "$rd/summary.json" && $elapsed -lt 15 ]]; then test_pass; else test_fail "rc=$rc elapsed=${elapsed}s out=$out"; fi

test_case "--supersede-key resolves the pool's latest-<slug> pointer"
pool="$(mktemp -d "$TEST_TMP_DIR/p6.XXXXXX")"
source "$PROJECT_ROOT/scripts/lib/council.sh" 2>/dev/null || true
key="2947:CP2"
if declare -f council_supersede_key_slug >/dev/null 2>&1; then slug="$(council_supersede_key_slug "$key")"
else slug="$(printf '%s' "$key" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-64)-$(printf '%s' "$key" | cksum | cut -d' ' -f1)"; fi
cp2rd="$(_mkrun "$pool" 20260101-030000-00f111 finished)"      # the keyed round, finished
_mkrun "$pool" 20260101-040000-00f222 running >/dev/null       # a NEWER unrelated round, running
printf '%s\n' 20260101-030000-00f111 > "$pool/latest-$slug"
_runwait --pool "$pool" --supersede-key "$key" --interval 1 --timeout 5
if [[ $rc -eq 0 && "$out" == "$cp2rd/summary.json" ]]; then test_pass; else test_fail "key pointer not honored: rc=$rc out=$out want=$cp2rd/summary.json"; fi

test_case "--run-dir waits on a specific run dir"
pool="$(mktemp -d "$TEST_TMP_DIR/p7.XXXXXX")"
rd="$(_mkrun "$pool" 20260101-050000-00f333 finished)"
_runwait --run-dir "$rd" --interval 1 --timeout 5
if [[ $rc -eq 0 && "$out" == "$rd/summary.json" ]]; then test_pass; else test_fail "rc=$rc out=$out"; fi

test_case "argument errors exit 64"
r1=bad r2=bad r3=bad
_runwait --pool /x --run-dir /y; [[ $rc -eq 64 ]] && r1=ok
_runwait;                        [[ $rc -eq 64 ]] && r2=ok
_runwait --pool /x --interval abc; [[ $rc -eq 64 ]] && r3=ok
if [[ "$r1" == ok && "$r2" == ok && "$r3" == ok ]]; then test_pass; else test_fail "usage guards: $r1/$r2/$r3"; fi

test_summary
