#!/usr/bin/env bash
# Regression for #1075: `orchestrate.sh spawn` must exit with spawn_agent's
# real dispatch status, not 0. The `spawn)` case arm's last statement used to
# be `unset _spawn_target _spawn_role _spawn_provider`, and `unset` always
# succeeds — so if the enclosing script were ever entered without the
# top-level `set -eo pipefail` catching the earlier failure first (a
# subshell, a sourced dispatcher, a future refactor), a failed dispatch would
# report success. The fix captures spawn_agent's exit status before the
# cleanup `unset` and exits with it explicitly, so propagation no longer
# depends on `errexit` firing before `unset` runs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "orchestrate.sh spawn exit-code propagation (#1075)"

ORCH="$PROJECT_ROOT/scripts/orchestrate.sh"

test_case "the spawn case arm no longer ends on a bare cleanup unset"
# The historical bug shape: `esac` immediately followed by the cleanup unset
# with nothing capturing spawn_agent's exit status in between.
if awk '
    /^    spawn\)$/ { in_arm = 1 }
    in_arm && /^        esac$/ { seen_esac = 1; next }
    seen_esac && /_spawn_exit/ { found_capture = 1 }
    in_arm && /^    auto\)$/ { exit }
    END { exit !(found_capture) }
' "$ORCH"; then
    test_pass
else
    test_fail "expected the spawn arm to capture \$? into _spawn_exit right after esac, before the cleanup unset"
fi

# Drive the exact case arm from orchestrate.sh in an isolated interpreter. The
# harness's own top-level `set -eo pipefail` (mirroring orchestrate.sh's) would
# otherwise abort on spawn_agent's failure *before* the arm's own cleanup/exit
# ever runs — masking exactly the bug this test exists to catch, since a
# pre-fix arm ending on a bare `unset` would then "pass" too (see #1076
# review). Wrapping the arm in a function invoked as `run_spawn_arm || rc=$?`
# disables -e for commands inside that function body (a documented bash
# exemption for a function called as part of an `||` list), so a failing
# spawn_agent no longer aborts early — the arm's own control flow is what's
# under test. An explicit `exit N` inside the arm (the fix) still terminates
# the whole process immediately regardless of that exemption, exactly as it
# would in the real script.
build_harness() {
    local out="$1" spawn_agent_stub="$2"
    {
        echo '#!/usr/bin/env bash'
        echo 'set -eo pipefail'
        echo 'log() { :; }'
        echo 'resolve_persona_spawn_target() { return 1; }'
        printf 'spawn_agent() { %s; }\n' "$spawn_agent_stub"
        echo 'DRY_RUN=false'
        echo 'COMMAND="spawn"'
        echo 'set -- claude "hello"'
        echo 'run_spawn_arm() {'
        echo 'case "$COMMAND" in'
        sed -n '/^    spawn)$/,/^    auto)$/p' "$ORCH" | sed '$d'
        echo 'esac'
        echo '}'
        echo 'rc=0'
        # A function gets its own $1/$2/$# separate from the script's — forward
        # the already-set positional parameters explicitly.
        echo 'run_spawn_arm "$@" || rc=$?'
        echo 'exit "$rc"'
    } > "$out"
    chmod +x "$out"
}

test_case "spawn arm exits with spawn_agent's real failure code, not the cleanup unset's success"
harness="$TEST_TMP_DIR/spawn-exit-harness.sh"
build_harness "$harness" 'return 74'

bash "$harness" >"$TEST_TMP_DIR/spawn-exit.out" 2>&1 && rc=0 || rc=$?
if [[ "$rc" -eq 74 ]]; then
    test_pass
else
    test_fail "expected exit 74 from a failed spawn_agent dispatch, got exit=$rc (output: $(cat "$TEST_TMP_DIR/spawn-exit.out"))"
fi

test_case "this harness actually catches the pre-fix bug shape (masked exit 0)"
# Proves the harness above can fail: replay it against the historical bug
# shape (esac followed directly by the cleanup unset, nothing else) and
# confirm THAT exits 0 despite spawn_agent failing — same setup, buggy arm.
harness_buggy="$TEST_TMP_DIR/spawn-exit-harness-buggy.sh"
{
    echo '#!/usr/bin/env bash'
    echo 'set -eo pipefail'
    echo 'log() { :; }'
    echo 'resolve_persona_spawn_target() { return 1; }'
    echo 'spawn_agent() { return 74; }'
    echo 'DRY_RUN=false'
    echo 'COMMAND="spawn"'
    echo 'set -- claude "hello"'
    echo 'run_spawn_arm() {'
    echo 'case "$COMMAND" in'
    # Reconstruct the pre-#1076 arm shape directly, rather than depending on
    # git history: same dispatch logic, but ending on the bare cleanup unset
    # instead of capturing/propagating spawn_agent's exit status.
    sed -n '/^    spawn)$/,/^        esac$/p' "$ORCH"
    echo '        unset _spawn_target _spawn_role _spawn_provider'
    echo '        ;;'
    echo 'esac'
    echo '}'
    echo 'rc=0'
    echo 'run_spawn_arm "$@" || rc=$?'
    echo 'exit "$rc"'
} > "$harness_buggy"
chmod +x "$harness_buggy"

bash "$harness_buggy" >"$TEST_TMP_DIR/spawn-exit-buggy.out" 2>&1 && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then
    test_pass
else
    test_fail "expected the reconstructed pre-fix arm shape to mask the failure as exit 0 (proving the harness can fail); got exit=$rc — the harness may not actually be exercising the fix (output: $(cat "$TEST_TMP_DIR/spawn-exit-buggy.out"))"
fi

test_case "spawn arm still exits 0 when spawn_agent actually succeeds"
harness_ok="$TEST_TMP_DIR/spawn-exit-harness-ok.sh"
build_harness "$harness_ok" 'echo 4242; return 0'

out="$(bash "$harness_ok")" && rc=0 || rc=$?
if [[ "$rc" -eq 0 && "$out" == "4242" ]]; then
    test_pass
else
    test_fail "expected exit 0 and PID output 4242 on success, got exit=$rc, output: $out"
fi

test_summary
