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

test_case "spawn arm exits with spawn_agent's real failure code, not the cleanup unset's success"
# Drive the exact case arm from orchestrate.sh in an isolated interpreter,
# with a stubbed spawn_agent that fails the way a lost PID-ledger
# registration does (spawn.sh returns 74 for this class of failure).
harness="$TEST_TMP_DIR/spawn-exit-harness.sh"
{
    echo '#!/usr/bin/env bash'
    echo 'set -eo pipefail'
    echo 'log() { :; }'
    echo 'resolve_persona_spawn_target() { return 1; }'
    echo 'spawn_agent() { return 74; }'
    echo 'DRY_RUN=false'
    echo 'COMMAND="spawn"'
    echo 'set -- claude "hello"'
    echo 'case "$COMMAND" in'
    sed -n '/^    spawn)$/,/^    auto)$/p' "$ORCH" | sed '$d'
    echo 'esac'
} > "$harness"
chmod +x "$harness"

bash "$harness" >"$TEST_TMP_DIR/spawn-exit.out" 2>&1 && rc=0 || rc=$?
if [[ "$rc" -eq 74 ]]; then
    test_pass
else
    test_fail "expected exit 74 from a failed spawn_agent dispatch, got exit=$rc (output: $(cat "$TEST_TMP_DIR/spawn-exit.out"))"
fi

test_case "spawn arm still exits 0 when spawn_agent actually succeeds"
harness_ok="$TEST_TMP_DIR/spawn-exit-harness-ok.sh"
{
    echo '#!/usr/bin/env bash'
    echo 'set -eo pipefail'
    echo 'log() { :; }'
    echo 'resolve_persona_spawn_target() { return 1; }'
    echo 'spawn_agent() { echo 4242; return 0; }'
    echo 'DRY_RUN=false'
    echo 'COMMAND="spawn"'
    echo 'set -- claude "hello"'
    echo 'case "$COMMAND" in'
    sed -n '/^    spawn)$/,/^    auto)$/p' "$ORCH" | sed '$d'
    echo 'esac'
} > "$harness_ok"
chmod +x "$harness_ok"

out="$(bash "$harness_ok")" && rc=0 || rc=$?
if [[ "$rc" -eq 0 && "$out" == "4242" ]]; then
    test_pass
else
    test_fail "expected exit 0 and PID output 4242 on success, got exit=$rc, output: $out"
fi

test_summary
