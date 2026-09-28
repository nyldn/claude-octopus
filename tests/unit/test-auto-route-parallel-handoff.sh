#!/usr/bin/env bash
# /octo:auto parallel intent hands off to the /octo:parallel command.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Automatic routing hands parallel work to /octo:parallel"

PARALLEL_PROMPT="decompose the auth refactor into parallel work packages"
PARALLEL_HANDOFF="Native workflow requested: /octo:parallel. No external provider was started."

WORK_DIR="$TEST_TMP_DIR/work"
mkdir -p "$WORK_DIR"
git -C "$WORK_DIR" init -q

# env -i drops ambient Octopus settings and the workspace overrides that take
# precedence over HOME, so routing and run state stay inside this test.
run_auto() {
    (
        cd "$WORK_DIR" &&
            env -i "HOME=$TEST_TMP_DIR/home" "PATH=$PATH" "OCTOPUS_SKIP_PROVIDER_PROBES=true" \
                bash "$PROJECT_ROOT/scripts/orchestrate.sh" -n auto "$@" </dev/null 2>&1
    )
}

handoff_lines() {
    grep -F -A1 'Native workflow requested:' <<< "$1" || true
}

test_case "a classified parallel request hands off instead of reading the prompt as a tasks file"
classified_rc=0
classified_output="$(run_auto "$PARALLEL_PROMPT")" || classified_rc=$?
if [[ "$classified_rc" -eq 0 ]] &&
   grep -Fq "$PARALLEL_HANDOFF" <<< "$classified_output" &&
   ! grep -Fq 'Tasks file not found' <<< "$classified_output"; then
    test_pass
else
    test_fail "expected the /octo:parallel handoff and exit 0 (rc=$classified_rc): $(tail -n 3 <<< "$classified_output")"
fi

test_case "the classified route matches a confirmed --workflow parallel choice"
confirmed_rc=0
confirmed_output="$(run_auto --workflow parallel "$PARALLEL_PROMPT")" || confirmed_rc=$?
confirmed_handoff="$(handoff_lines "$confirmed_output")"
if [[ "$confirmed_rc" -eq 0 && -n "$confirmed_handoff" &&
      "$(handoff_lines "$classified_output")" == "$confirmed_handoff" ]]; then
    test_pass
else
    test_fail "classified and confirmed parallel routes diverged (rc=$confirmed_rc)"
fi

test_summary
