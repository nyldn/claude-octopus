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
    jq -n --arg state "$state" --arg rid "$rid" --arg key "${5:-}" --argjson order "${6:-0}" \
        '{state:$state,run_id:$rid,supersede_key:$key,created_order:$order,superseded:false}' > "$rd/run-status.json"
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
if ! declare -f council_supersede_key_slug >/dev/null 2>&1; then
    test_fail "council_supersede_key_slug unavailable; cannot verify producer parity"
    # Later independent fixtures still need their pointer setup to reach summary.
    slug="$(printf '%s' "$key" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-64)-$(printf '%s' "$key" | cksum | cut -d' ' -f1)"
else
    slug="$(council_supersede_key_slug "$key")"
    cp2rd="$(_mkrun "$pool" 20260101-030000-00f111 finished yes "$key")"
    _mkrun "$pool" 20260101-040000-00f222 running yes "$key" >/dev/null  # Fallback sees this newer same-key round.
    printf '%s\n' 20260101-030000-00f111 > "$pool/latest-$slug"
    _runwait --pool "$pool" --supersede-key "$key" --interval 1 --timeout 5
    if [[ $rc -eq 0 && "$out" == "$cp2rd/summary.json" ]]; then test_pass; else test_fail "key pointer not honored: rc=$rc out=$out want=$cp2rd/summary.json"; fi
fi

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

test_case "a poll interval larger than the deadline cannot extend the wait"
pool="$(mktemp -d "$TEST_TMP_DIR/deadline.XXXXXX")"
rd="$(_mkrun "$pool" 20260101-000000-00aaaa running)"
if python3 - "$WAIT" "$rd" <<'PY'
import os, signal, subprocess, sys, time
started = time.monotonic()
child = subprocess.Popen(["/bin/bash",sys.argv[1],"--run-dir",sys.argv[2],"--interval","6","--timeout","1"],stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
try:
    child.communicate(timeout=5)
except subprocess.TimeoutExpired:
    os.killpg(child.pid,signal.SIGKILL)
    child.communicate()
    sys.exit(1)
sys.exit(0 if child.returncode == 2 and time.monotonic()-started < 4 else 1)
PY
then test_pass; else test_fail "interval extended the one-second deadline"; fi

test_case "leading zeros remain decimal and oversized integers reject"
pool="$(mktemp -d "$TEST_TMP_DIR/decimal.XXXXXX")"
rd="$(_mkrun "$pool" 20260101-000000-00aaaa finished)"
_runwait --run-dir "$rd" --timeout 08 --interval 09
decimal_rc="$rc"
_runwait --run-dir "$rd" --timeout 999999999999999999999999
if [[ "$decimal_rc" == 0 && "$rc" == 64 ]]; then test_pass; else test_fail "decimal=$decimal_rc oversized=$rc"; fi

test_case "since uses immutable UTC run creation time, not directory mtime"
pool="$(mktemp -d "$TEST_TMP_DIR/since.XXXXXX")"
_mkrun "$pool" 20260101-000000-00aaaa finished >/dev/null
_runwait --pool "$pool" --since 1767312000 --timeout 0
if [[ "$rc" == 2 ]]; then test_pass; else test_fail "selected a stale run with fresh directory mtime"; fi

test_case "since also filters a stale keyed pointer"
pool="$(mktemp -d "$TEST_TMP_DIR/key-since.XXXXXX")"
_mkrun "$pool" 20260101-000000-00aaaa finished yes "$key" >/dev/null
printf '%s\n' 20260101-000000-00aaaa > "$pool/latest-$slug"
_runwait --pool "$pool" --supersede-key "$key" --since 1767312000 --timeout 0
if [[ "$rc" == 2 ]]; then test_pass; else test_fail "key pointer bypassed since"; fi

test_case "same-second creation order beats a reversed PID suffix"
pool="$(mktemp -d "$TEST_TMP_DIR/order.XXXXXX")"
_mkrun "$pool" 20260101-000000-ffffff finished yes '' 1 >/dev/null
_mkrun "$pool" 20260101-000000-000001 running yes '' 2 >/dev/null
_runwait --pool "$pool" --timeout 0
if [[ "$rc" == 2 ]]; then test_pass; else test_fail "selected the older finished PID"; fi

test_case "an absent supersede key cannot select an unrelated finished round"
pool="$(mktemp -d "$TEST_TMP_DIR/key-missing.XXXXXX")"
_mkrun "$pool" 20260101-000000-00aaaa finished yes unrelated >/dev/null
_runwait --pool "$pool" --supersede-key "$key" --timeout 0
if [[ "$rc" == 2 ]]; then test_pass; else test_fail "selected an unrelated key"; fi

test_case "a stale pointer can resolve the newest matching nonsuperseded beacon"
pool="$(mktemp -d "$TEST_TMP_DIR/key-fallback.XXXXXX")"
rd="$(_mkrun "$pool" 20260101-000000-00aaaa finished yes "$key" 2)"
printf '%s\n' nonexistent > "$pool/latest-$slug"
_runwait --pool "$pool" --supersede-key "$key" --timeout 0
if [[ "$rc" == 0 && "$out" == "$rd/summary.json" ]]; then test_pass; else test_fail "matching fallback failed"; fi

test_case "keyed waiting follows a newer matching pointer during the wait"
pool="$(mktemp -d "$TEST_TMP_DIR/key-flip.XXXXXX")"
_mkrun "$pool" 20260101-000000-00aaaa running yes "$key" 1 >/dev/null
rd="$(_mkrun "$pool" 20260101-000001-00bbbb finished yes "$key" 2)"
printf '%s\n' 20260101-000000-00aaaa > "$pool/latest-$slug"
( sleep 1; printf '%s\n' 20260101-000001-00bbbb > "$pool/latest-$slug" ) &
flip_pid=$!
_runwait --pool "$pool" --supersede-key "$key" --interval 1 --timeout 4
wait "$flip_pid" || true
if [[ "$rc" == 0 && "$out" == "$rd/summary.json" ]]; then test_pass; else test_fail "remained latched on older keyed run"; fi

test_case "a key pointer cannot leave its pool or accept a symlinked run"
parent="$(mktemp -d "$TEST_TMP_DIR/outside.XXXXXX")"
pool="$parent/pool"; mkdir -p "$pool"
rd="$(_mkrun "$parent" 20260101-000000-00aaaa finished yes "$key")"
printf '%s\n' ../20260101-000000-00aaaa > "$pool/latest-$slug"
_runwait --pool "$pool" --supersede-key "$key" --timeout 0
outside_rc="$rc"
ln -s "$rd" "$pool/20260101-000000-00aaaa"
printf '%s\n' 20260101-000000-00aaaa > "$pool/latest-$slug"
_runwait --pool "$pool" --supersede-key "$key" --timeout 0
if [[ "$outside_rc" == 2 && "$rc" == 2 ]]; then test_pass; else test_fail "outside=$outside_rc symlink=$rc"; fi

test_case "superseded keyed beacons do not advertise current completion"
pool="$(mktemp -d "$TEST_TMP_DIR/superseded.XXXXXX")"
rd="$(_mkrun "$pool" 20260101-000000-00aaaa finished yes "$key")"
jq '.superseded=true' "$rd/run-status.json" > "$rd/status-next.json"
mv "$rd/status-next.json" "$rd/run-status.json"
printf '%s\n' 20260101-000000-00aaaa > "$pool/latest-$slug"
_runwait --pool "$pool" --supersede-key "$key" --timeout 0
if [[ "$rc" == 2 ]]; then test_pass; else test_fail "selected a superseded run"; fi

test_case "summary must be one object with matching optional run identity"
pool="$(mktemp -d "$TEST_TMP_DIR/summary.XXXXXX")"
rd="$(_mkrun "$pool" 20260101-000000-00aaaa finished)"
bad=0
for record in '[{"status":"completed"}]' '{"status":"completed"} {"status":"completed"}' '{"status":"completed","run_id":"wrong"}' '{}'; do
    printf '%s\n' "$record" > "$rd/summary.json"
    _runwait --run-dir "$rd" --timeout 0
    [[ "$rc" == 2 ]] || bad=$((bad+1))
done
if [[ "$bad" == 0 ]]; then test_pass; else test_fail "$bad invalid summaries admitted"; fi

test_case "a beacon from another run cannot complete this directory"
pool="$(mktemp -d "$TEST_TMP_DIR/beacon.XXXXXX")"
rd="$(_mkrun "$pool" 20260101-000000-00aaaa finished)"
printf '%s\n' '{"state":"finished","run_id":"wrong"}' > "$rd/run-status.json"
_runwait --run-dir "$rd" --timeout 0
if [[ "$rc" == 2 ]]; then test_pass; else test_fail "foreign beacon admitted"; fi

test_case "pool-only filters cannot silently apply to an explicit run directory"
_runwait --run-dir /x --since 1
since_rc="$rc"
_runwait --run-dir /x --supersede-key x
if [[ "$since_rc" == 64 && "$rc" == 64 ]]; then test_pass; else test_fail "ignored pool-only filter"; fi

test_case "actual atomic writer and supersession select the current same-second round"
pool="$(mktemp -d "$TEST_TMP_DIR/writer.XXXXXX")"
old="$pool/20260101-000000-ffffff"; current="$pool/20260101-000000-000001"
mkdir -p "$old" "$current"
writer="$PROJECT_ROOT/scripts/helpers/council-run-state.py"
printf '%s\n' '{"status":"completed","run_id":"20260101-000000-ffffff"}' > "$old/summary.json"
jq -n --arg key "$key" '{state:"finished",run_id:"20260101-000000-ffffff",supersede_key:$key}' | python3 "$writer" write "$old"
jq -n --arg key "$key" '{state:"running",run_id:"20260101-000000-000001",supersede_key:$key}' | python3 "$writer" write "$current"
python3 "$writer" supersede "$pool" "$current" "$key" "latest-$slug"
_runwait --pool "$pool" --supersede-key "$key" --timeout 0
running_rc="$rc"
printf '%s\n' '{"status":"partial","run_id":"20260101-000000-000001"}' > "$current/summary.json"
jq -n --arg key "$key" '{state:"finished",run_id:"20260101-000000-000001",supersede_key:$key}' | python3 "$writer" write "$current"
# This checks artifact identity, not a zero-second deadline boundary.
_runwait --pool "$pool" --supersede-key "$key" --timeout 3
if [[ "$running_rc" == 2 && "$rc" == 0 && "$out" == "$current/summary.json" ]]; then test_pass; else test_fail "running=$running_rc finished=$rc output=$out"; fi

test_case "an expired partial scan cannot return an older finished summary"
pool="$(mktemp -d "$TEST_TMP_DIR/large-pool.XXXXXX")"
if python3 - "$WAIT" "$pool" <<'PY'
import json, os, signal, subprocess, sys
from pathlib import Path
pool=Path(sys.argv[2])
for index in range(1,1501):
    rid="20260101-000000-"+format(index,"06x")
    directory=pool/rid
    directory.mkdir()
    (directory/"run-status.json").write_text(json.dumps({"state":"running" if index==1500 else "finished","run_id":rid,"created_order":index}))
    (directory/"summary.json").write_text(json.dumps({"status":"completed","run_id":rid}))
child=subprocess.Popen(["/bin/bash",sys.argv[1],"--pool",str(pool),"--timeout","1"],stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
try:
    output,_=child.communicate(timeout=5)
except subprocess.TimeoutExpired:
    os.killpg(child.pid,signal.SIGKILL)
    child.communicate()
    sys.exit(1)
sys.exit(0 if child.returncode==2 and not output else 1)
PY
then test_pass; else test_fail "partial scan reported a stale completion"; fi

test_case "explicit trailing-slash run directories preserve their valid identity"
pool="$(mktemp -d "$TEST_TMP_DIR/trailing.XXXXXX")"
rd="$(_mkrun "$pool" 20260101-000000-00aaaa finished)"
_runwait --run-dir "$rd/" --timeout 0
if [[ "$rc" == 0 && "$out" == "$rd//summary.json" ]]; then test_pass; else test_fail "trailing slash lost run identity"; fi

test_case "an explicit relative run directory resolves identity without changing the output path"
pool="$(mktemp -d "$TEST_TMP_DIR/relative.XXXXXX")"
rd="$(_mkrun "$pool" 20260101-000000-00aaaa finished)"
rc=0
out="$(cd -- "$rd" && /bin/bash "$WAIT" --run-dir . --timeout 0 2>/dev/null)" || rc=$?
if [[ "$rc" == 0 && "$out" == './summary.json' ]]; then test_pass; else test_fail "relative directory lost run identity"; fi

test_summary
