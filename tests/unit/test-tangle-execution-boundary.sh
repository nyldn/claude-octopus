#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/spawn.sh"
log() { :; }

test_suite "tangle execution boundary"

BOUNDARY_ROOT="$TEST_TMP_DIR/tangle-boundary"
BOUNDARY_WORKTREE="$BOUNDARY_ROOT/worktree"
BOUNDARY_RESULTS="$BOUNDARY_ROOT/results"
BOUNDARY_OUTSIDE="$BOUNDARY_ROOT/outside.txt"
mkdir -p "$BOUNDARY_WORKTREE" "$BOUNDARY_RESULTS"

phase="tangle"
role="implementer"
OCTOPUS_TANGLE_EXECUTION_BOUNDARY=true
OCTOPUS_TANGLE_WORKTREE="$BOUNDARY_WORKTREE"
OCTOPUS_TANGLE_RESULTS_DIR="$BOUNDARY_RESULTS"
export OCTOPUS_TANGLE_EXECUTION_BOUNDARY OCTOPUS_TANGLE_WORKTREE OCTOPUS_TANGLE_RESULTS_DIR

test_case "coding dispatch has no unconfined fallback"
cmd_array=(bash -c ':')
if octopus_tangle_execution_boundary_probe; then
    test_pass
else
    if octopus_tangle_apply_execution_boundary; then
        test_fail "boundary wrapper accepted a host without an enforceable sandbox"
    else
        test_pass
    fi
fi

test_case "adaptive coding dispatch cannot opt out of the boundary"
saved_probe="$(declare -f octopus_tangle_execution_boundary_probe)"
boundary_probe_calls=0
octopus_tangle_execution_boundary_probe() {
    boundary_probe_calls=$((boundary_probe_calls + 1))
    return 1
}
unset OCTOPUS_TANGLE_EXECUTION_BOUNDARY
export OCTOPUS_TANGLE_WRITE_SCOPE_MODE=adaptive
if ! octopus_tangle_apply_execution_boundary && [[ "$boundary_probe_calls" -eq 1 ]] && [[ -z "${OCTOPUS_TANGLE_EXECUTION_BOUNDARY:-}" ]]; then
    test_pass
else
    test_fail "adaptive dispatch accepted an unset boundary or skipped the boundary probe"
fi
eval "$saved_probe"

test_case "adaptive mode requires supervised dispatch before Agent Teams selection"
if OCTOPUS_TANGLE_EXECUTION_BOUNDARY=false \
   OCTOPUS_TANGLE_WRITE_SCOPE_MODE=adaptive \
   octopus_tangle_execution_boundary_required; then
    test_pass
else
    test_fail "adaptive mode did not require the supervised execution boundary at dispatch selection"
fi
unset OCTOPUS_TANGLE_WRITE_SCOPE_MODE
OCTOPUS_TANGLE_EXECUTION_BOUNDARY=true

test_case "parent-owned result channel cannot overlap the worktree"
if ! octopus_tangle_boundary_paths_are_disjoint \
    "$BOUNDARY_WORKTREE" "$BOUNDARY_WORKTREE/results" && \
   ! octopus_tangle_boundary_paths_are_disjoint \
    "$BOUNDARY_WORKTREE" "$BOUNDARY_ROOT" && \
   octopus_tangle_boundary_paths_are_disjoint \
    "$BOUNDARY_WORKTREE" "$BOUNDARY_RESULTS"; then
    test_pass
else
    test_fail "overlapping worktree/result authority paths were accepted"
fi

if octopus_tangle_execution_boundary_probe; then
    test_case "boundary leaves only the worktree writable"
    cmd_array=(bash -c 'touch "$1" 2>/dev/null || true; touch "$2/inside.txt"; touch "$3/forged.txt" 2>/dev/null || true' _ "$BOUNDARY_OUTSIDE" "$BOUNDARY_WORKTREE" "$BOUNDARY_RESULTS")
    if octopus_tangle_apply_execution_boundary && "${cmd_array[@]}" &&
       [[ ! -e "$BOUNDARY_OUTSIDE" ]] &&
       [[ -e "$BOUNDARY_WORKTREE/inside.txt" ]] &&
       [[ ! -e "$BOUNDARY_RESULTS/forged.txt" ]]; then
        test_pass
    else
        test_fail "provider could write outside the worktree or forge the result channel"
    fi
fi

# Codex writes its own state while it runs: CODEX_HOME, and the sandbox TMPDIR
# that its config.toml sets for the commands it runs. The argv cases below stub
# the probe, so they run on hosts without bwrap too.
CODEX_STATE_HOME="$BOUNDARY_ROOT/codex-home"
CODEX_STATE_TMP="$BOUNDARY_ROOT/codex-tmp"
mkdir -p "$CODEX_STATE_HOME" "$CODEX_STATE_TMP"
printf '[shell_environment_policy]\nset = { TMPDIR = "%s" }\n' "$CODEX_STATE_TMP" \
    > "$CODEX_STATE_HOME/config.toml"
physical_codex_home="$(cd "$CODEX_STATE_HOME" && pwd -P)"
physical_codex_tmp="$(cd "$CODEX_STATE_TMP" && pwd -P)"
codex_toml_readable=false
if python3 -c 'import tomllib' >/dev/null 2>&1; then
    codex_toml_readable=true
fi

# True when the boundary part of cmd_array binds $1 read-write.
boundary_binds_rw() {
    local i
    for ((i = 0; i + 2 < ${#cmd_array[@]}; i++)); do
        [[ "${cmd_array[i]}" == "--" ]] && return 1
        if [[ "${cmd_array[i]}" == "--bind" && "${cmd_array[i+1]}" == "$1" && \
              "${cmd_array[i+2]}" == "$1" ]]; then
            return 0
        fi
    done
    return 1
}

saved_probe="$(declare -f octopus_tangle_execution_boundary_probe)"
octopus_tangle_execution_boundary_probe() { return 0; }

test_case "codex dispatch binds CODEX_HOME and its configured sandbox TMPDIR"
agent_type="codex"
CODEX_HOME="$CODEX_STATE_HOME"
cmd_array=(true)
if ! octopus_tangle_apply_execution_boundary; then
    test_fail "boundary refused a codex dispatch"
elif ! boundary_binds_rw "$physical_codex_home"; then
    test_fail "codex dispatch left CODEX_HOME read-only"
elif [[ "$codex_toml_readable" == "true" ]] && ! boundary_binds_rw "$physical_codex_tmp"; then
    test_fail "codex dispatch left the sandbox TMPDIR from config.toml read-only"
else
    test_pass
fi

test_case "non-codex dispatch leaves the codex state read-only"
agent_type="claude"
cmd_array=(true)
if octopus_tangle_apply_execution_boundary && \
   ! boundary_binds_rw "$physical_codex_home" && \
   ! boundary_binds_rw "$physical_codex_tmp"; then
    test_pass
else
    test_fail "a non-codex dispatch could write the codex state directories"
fi

test_case "codex state overlapping the worktree, results or HOME, or behind a symlink, stays read-only"
agent_type="codex"
mkdir -p "$BOUNDARY_WORKTREE/.codex" "$BOUNDARY_ROOT/userhome/u" "$BOUNDARY_ROOT/codex-home-2"
ln -sfn "$CODEX_STATE_HOME" "$BOUNDARY_ROOT/codex-link"
printf '[shell_environment_policy]\nset = { TMPDIR = "%s" }\n' "$BOUNDARY_RESULTS" \
    > "$BOUNDARY_ROOT/codex-home-2/config.toml"
unsafe_failures=""
for unsafe_home in "$BOUNDARY_WORKTREE/.codex" "$BOUNDARY_RESULTS" \
                   "$BOUNDARY_ROOT/userhome" "$BOUNDARY_ROOT/codex-link"; do
    CODEX_HOME="$unsafe_home"
    cmd_array=(true)
    if ! HOME="$BOUNDARY_ROOT/userhome/u" octopus_tangle_apply_execution_boundary; then
        unsafe_failures+=" refused:$unsafe_home"
    elif boundary_binds_rw "$(cd "$unsafe_home" && pwd -P)"; then
        unsafe_failures+=" bound:$unsafe_home"
    fi
done
CODEX_HOME="$BOUNDARY_ROOT/codex-home-2"
cmd_array=(true)
if ! octopus_tangle_apply_execution_boundary; then
    unsafe_failures+=" refused:tmpdir-in-results"
elif boundary_binds_rw "$(cd "$BOUNDARY_RESULTS" && pwd -P)"; then
    unsafe_failures+=" bound:tmpdir-in-results"
fi
if [[ -z "$unsafe_failures" ]]; then
    test_pass
else
    test_fail "unsafe codex state handling:$unsafe_failures"
fi

eval "$saved_probe"
CODEX_HOME="$CODEX_STATE_HOME"

if octopus_tangle_execution_boundary_probe; then
    test_case "codex dispatch can write its own state but nothing else outside the worktree"
    agent_type="codex"
    rm -f "$BOUNDARY_OUTSIDE"
    cmd_array=(bash -c 'touch "$1/state" || exit 1
                        touch "$2/lock" 2>/dev/null || true
                        touch "$3" 2>/dev/null || true
                        touch "$4/forged.txt" 2>/dev/null || true' \
               _ "$CODEX_STATE_HOME" "$CODEX_STATE_TMP" "$BOUNDARY_OUTSIDE" "$BOUNDARY_RESULTS")
    if octopus_tangle_apply_execution_boundary && "${cmd_array[@]}" &&
       [[ -e "$CODEX_STATE_HOME/state" ]] &&
       { [[ "$codex_toml_readable" != "true" ]] || [[ -e "$CODEX_STATE_TMP/lock" ]]; } &&
       [[ ! -e "$BOUNDARY_OUTSIDE" ]] &&
       [[ ! -e "$BOUNDARY_RESULTS/forged.txt" ]]; then
        test_pass
    else
        test_fail "codex could not write its state, or could write outside it and the worktree"
    fi
fi
unset agent_type CODEX_HOME

test_summary
