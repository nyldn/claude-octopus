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
# the probe, so they run on hosts without bwrap too. Their fixtures use the
# physical path: configured CODEX_HOME aliases are refused even when reachable.
# Actual worker retargeting controls below additionally require bwrap.
CODEX_ROOT="$(cd "$BOUNDARY_ROOT" && pwd -P)"
CODEX_STATE_HOME="$CODEX_ROOT/codex-home"
CODEX_STATE_TMP="$CODEX_ROOT/codex-tmp"
mkdir -p "$CODEX_STATE_HOME" "$CODEX_STATE_TMP"
printf '[shell_environment_policy]\nset = { TMPDIR = "%s" }\n' "$CODEX_STATE_TMP" \
    > "$CODEX_STATE_HOME/config.toml"
physical_codex_home="$(cd "$CODEX_STATE_HOME" && pwd -P)"
physical_codex_tmp="$(cd "$CODEX_STATE_TMP" && pwd -P)"
codex_toml_readable=false
if python3 -c 'import tomllib' >/dev/null 2>&1; then
    codex_toml_readable=true
fi

# The boundary replaces /tmp, so some fixtures must live outside it (a symlink
# that stays visible, Git metadata that stays visible) and one inside it.
OUTSIDE_TMP_ROOT=""
if [[ -d /var/tmp && -w /var/tmp ]]; then
    OUTSIDE_TMP_ROOT="$(mktemp -d /var/tmp/octopus-boundary-test.XXXXXX)"
    OUTSIDE_TMP_ROOT="$(cd "$OUTSIDE_TMP_ROOT" && pwd -P)"
fi
TMP_LINK_ROOT="$(mktemp -d /tmp/octopus-boundary-test.XXXXXX)"
trap 'rm -rf "$TMP_LINK_ROOT" ${OUTSIDE_TMP_ROOT:+"$OUTSIDE_TMP_ROOT"}; cleanup_test_environment' EXIT

# Create a main repository below $1/state-parent and a linked worktree at $1/linked.
# A linked worktree keeps its Git directory and the common directory outside
# itself, so a codex state directory holding the main repository would unseal
# both if it were bound writable.
make_linked_worktree() {
    git init -q "$1/state-parent/main"
    git -C "$1/state-parent/main" -c user.name=octopus-test \
        -c user.email=octopus-test@example.invalid -c commit.gpgsign=false \
        commit -q --allow-empty -m init
    git -C "$1/state-parent/main" worktree add -q --detach "$1/linked"
}
GIT_FIXTURE="$CODEX_ROOT/git-fixture"
make_linked_worktree "$GIT_FIXTURE"
physical_git_dir="$(cd "$(git -C "$GIT_FIXTURE/linked" rev-parse --absolute-git-dir)" && pwd -P)"
physical_git_common="$(cd "$GIT_FIXTURE/state-parent/main/.git" && pwd -P)"

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

boundary_private_tmpfs() {
    local i
    for ((i = 0; i + 1 < ${#cmd_array[@]}; i++)); do
        [[ "${cmd_array[i]}" == "--" ]] && return 1
        [[ "${cmd_array[i]}" == "--tmpfs" && "${cmd_array[i+1]}" == "$1" ]] && return 0
    done
    return 1
}

boundary_refuses_codex() {
    local status
    if octopus_tangle_apply_execution_boundary; then
        return 1
    else
        status=$?
        [[ "$status" -eq 125 ]]
    fi
}

saved_probe="$(declare -f octopus_tangle_execution_boundary_probe)"
octopus_tangle_execution_boundary_probe() { return 0; }

test_case "codex dispatch projects private runtime state and sandbox TMPDIR"
agent_type="codex"
CODEX_HOME="$CODEX_STATE_HOME"
cmd_array=(true)
if ! octopus_tangle_apply_execution_boundary; then
    test_fail "boundary refused a codex dispatch"
elif ! boundary_private_tmpfs "$physical_codex_home"; then
    test_fail "codex dispatch omitted its private CODEX_HOME projection"
elif [[ "$codex_toml_readable" == "true" ]] && ! boundary_private_tmpfs "$physical_codex_tmp"; then
    test_fail "codex dispatch omitted its private configured TMPDIR"
else
    test_pass
fi

test_case "codex lock and plugin-sync directories get private tmpfs, config and extensions stay read-only"
LOCKS_HOME="$CODEX_ROOT/codex-home-locks"
mkdir -p "$LOCKS_HOME/thread-writer-locks" "$LOCKS_HOME/.tmp" "$LOCKS_HOME/sessions" "$LOCKS_HOME/skills"
: > "$LOCKS_HOME/config.toml"
physical_locks_home="$(cd "$LOCKS_HOME" && pwd -P)"
boundary_ro_binds() {
    local i
    for ((i = 0; i + 2 < ${#cmd_array[@]}; i++)); do
        [[ "${cmd_array[i]}" == "--" ]] && return 1
        if [[ "${cmd_array[i]}" == "--ro-bind" && "${cmd_array[i+1]}" == "$1" && \
              "${cmd_array[i+2]}" == "$1" ]]; then
            return 0
        fi
    done
    return 1
}
agent_type="codex"
CODEX_HOME="$LOCKS_HOME"
cmd_array=(true)
if ! octopus_tangle_apply_execution_boundary; then
    test_fail "boundary refused a codex dispatch"
elif ! boundary_private_tmpfs "$physical_locks_home/thread-writer-locks" || \
     ! boundary_private_tmpfs "$physical_locks_home/.tmp"; then
    test_fail "codex lock or plugin-sync directory was not made a private tmpfs"
elif boundary_ro_binds "$physical_locks_home/thread-writer-locks" || \
     boundary_ro_binds "$physical_locks_home/.tmp"; then
    test_fail "codex lock or plugin-sync directory was also bound read-only"
elif ! boundary_ro_binds "$physical_locks_home/skills" || \
     ! boundary_ro_binds "$physical_locks_home/config.toml"; then
    test_fail "codex extension inputs or config lost their read-only bind"
else
    test_pass
fi

test_case "a fresh codex home without lock directories still gets their private tmpfs"
FRESH_HOME="$CODEX_ROOT/codex-home-fresh"
mkdir -p "$FRESH_HOME"
: > "$FRESH_HOME/config.toml"
physical_fresh_home="$(cd "$FRESH_HOME" && pwd -P)"
agent_type="codex"
CODEX_HOME="$FRESH_HOME"
cmd_array=(true)
if octopus_tangle_apply_execution_boundary && \
   boundary_private_tmpfs "$physical_fresh_home/thread-writer-locks" && \
   boundary_private_tmpfs "$physical_fresh_home/.tmp"; then
    test_pass
else
    test_fail "a home that has not yet created its lock directories stayed read-only"
fi
CODEX_HOME="$CODEX_STATE_HOME"

test_case "codex config discovery ignores repository Python startup hooks"
startup_poison="$CODEX_ROOT/python-startup-poison"
startup_marker="$CODEX_ROOT/python-startup-fired"
mkdir -p "$startup_poison"
cat > "$startup_poison/sitecustomize.py" <<'PY'
import os
with open(os.environ["OCTOPUS_BOUNDARY_STARTUP_MARKER"], "w") as marker:
    marker.write("unexpected Python startup hook")
PY
CODEX_HOME="$CODEX_STATE_HOME"
cmd_array=(true)
if PYTHONPATH="$startup_poison" OCTOPUS_BOUNDARY_STARTUP_MARKER="$startup_marker" \
   octopus_tangle_apply_execution_boundary && \
   [[ ! -e "$startup_marker" ]] && boundary_private_tmpfs "$physical_codex_home" && \
   { [[ "$codex_toml_readable" != true ]] || boundary_private_tmpfs "$physical_codex_tmp"; }; then
    test_pass
else
    test_fail "pre-boundary config discovery executed a Python startup hook or lost safe state mounts"
fi

# Even a pre-existing configured TMPDIR must not add mounts in unrelated HOME
# directories or reopen configuration and extension inputs.
POLICY_HOME="${OUTSIDE_TMP_ROOT:-$CODEX_ROOT}/tmpdir-policy-home"
POLICY_CODEX_HOME="$POLICY_HOME/.codex"
mkdir -p "$POLICY_CODEX_HOME/tmp" "$POLICY_HOME/.ssh" "$POLICY_HOME/.claude" \
         "$POLICY_HOME/.local/bin" "$POLICY_HOME/rejected-codex/tmp" \
         "$POLICY_HOME/rejected-codex/results"
physical_policy_home="$(cd "$POLICY_HOME" && pwd -P)"
physical_policy_codex="$(cd "$POLICY_CODEX_HOME" && pwd -P)"

test_case "canonical absolute CODEX_HOME permits one trailing slash and outside-HOME TMPDIR"
if (
    agent_type="codex"
    for state_path in "$CODEX_STATE_HOME" "$CODEX_STATE_HOME/"; do
        cmd_array=(true)
        CODEX_HOME="$state_path" octopus_tangle_apply_execution_boundary || exit 1
        boundary_private_tmpfs "$physical_codex_home" || exit 1
        [[ "$codex_toml_readable" != true ]] || boundary_private_tmpfs "$physical_codex_tmp" || exit 1
    done
); then
    test_pass
else
    test_fail "canonical state paths lost their safe state or temporary mounts"
fi

test_case "raw CODEX_HOME aliases and noncanonical paths cannot authorize state or HOME TMPDIR"
if (
    agent_type="codex"
    mkdir -p "$CODEX_ROOT/alias-parent" "$POLICY_CODEX_HOME/ordinary-child"
    ln -s "$POLICY_CODEX_HOME" "$BOUNDARY_WORKTREE/state-alias"
    ln -s "$POLICY_CODEX_HOME" "$BOUNDARY_RESULTS/state-alias"
    ln -s "$POLICY_CODEX_HOME" "$POLICY_CODEX_HOME/state-alias"
    ln -s "$POLICY_HOME" "$CODEX_ROOT/alias-parent/home"
    ln -s "$POLICY_CODEX_HOME" "$POLICY_HOME/canceled-alias"
    printf '[shell_environment_policy]\nset = { TMPDIR = "%s" }\n' "$POLICY_CODEX_HOME/tmp" \
        > "$POLICY_CODEX_HOME/config.toml"
    # The raw comparison also rejects an alias canceled by .., which pwd -L
    # alone would erase before checking mount authority.
    rejected_paths=("$BOUNDARY_WORKTREE/state-alias" "$BOUNDARY_RESULTS/state-alias"
                    "$POLICY_CODEX_HOME/state-alias" "$CODEX_ROOT/alias-parent/home/.codex"
                    "$POLICY_CODEX_HOME/." "$POLICY_CODEX_HOME/ordinary-child/.."
                    "$POLICY_HOME/canceled-alias/../.codex" "$POLICY_CODEX_HOME//")
    cd "$POLICY_HOME"
    rejected_paths+=(".codex")
    for state_path in "${rejected_paths[@]}"; do
        cmd_array=(true)
        HOME="$POLICY_HOME" CODEX_HOME="$state_path" boundary_refuses_codex || exit 1
        ! boundary_private_tmpfs "$physical_policy_codex" || exit 1
        ! boundary_private_tmpfs "$physical_policy_codex/tmp" || exit 1
    done
); then
    test_pass
else
    test_fail "a configured alias or normalized spelling became trusted state authority"
fi

test_case "worker-edited TMPDIR cannot expose protected HOME directories on later dispatch"
if [[ "$codex_toml_readable" != true ]]; then
    test_skip "configured TMPDIR discovery requires tomllib"
elif (
    agent_type="codex"
    printf '[shell_environment_policy]\nset = { TMPDIR = "%s" }\n' "$CODEX_STATE_TMP" \
        > "$POLICY_CODEX_HOME/config.toml"
    cmd_array=(true)
    HOME="$POLICY_HOME" CODEX_HOME="$POLICY_CODEX_HOME" octopus_tangle_apply_execution_boundary || exit 1
    boundary_private_tmpfs "$physical_policy_codex" && boundary_private_tmpfs "$physical_codex_tmp" || exit 1
    for protected in .ssh .claude .local/bin; do
        printf '[shell_environment_policy]\nset = { TMPDIR = "%s" }\n' "$POLICY_HOME/$protected" \
            > "$POLICY_CODEX_HOME/config.toml"
        cmd_array=(true)
        HOME="$POLICY_HOME" CODEX_HOME="$POLICY_CODEX_HOME" boundary_refuses_codex || exit 1
        ! boundary_binds_rw "$physical_policy_home/$protected" || exit 1
    done
); then
    test_pass
else
    test_fail "a worker-edited config added a writable protected HOME mount"
fi

test_case "sandbox TMPDIR below an accepted physical CODEX_HOME stays writable"
if [[ "$codex_toml_readable" != true ]]; then
    test_skip "configured TMPDIR discovery requires tomllib"
elif (
    agent_type="codex"
    printf '[shell_environment_policy]\nset = { TMPDIR = "%s" }\n' "$POLICY_CODEX_HOME/tmp" \
        > "$POLICY_CODEX_HOME/config.toml"
    cmd_array=(true)
    HOME="$POLICY_HOME" CODEX_HOME="$POLICY_CODEX_HOME" octopus_tangle_apply_execution_boundary || exit 1
    boundary_private_tmpfs "$physical_policy_codex" && boundary_private_tmpfs "$physical_policy_codex/tmp"
); then
    test_pass
else
    test_fail "valid HOME state or its configured TMPDIR lost private runtime storage"
fi

test_case "a sandbox TMPDIR symlink cannot expose a protected physical HOME target"
if [[ "$codex_toml_readable" != true ]]; then
    test_skip "configured TMPDIR discovery requires tomllib"
elif (
    agent_type="codex"
    ln -s "$POLICY_HOME/.ssh" "$POLICY_CODEX_HOME/escaping-tmp"
    printf '[shell_environment_policy]\nset = { TMPDIR = "%s" }\n' "$POLICY_CODEX_HOME/escaping-tmp" \
        > "$POLICY_CODEX_HOME/config.toml"
    cmd_array=(true)
    HOME="$POLICY_HOME" CODEX_HOME="$POLICY_CODEX_HOME" boundary_refuses_codex || exit 1
    ! boundary_binds_rw "$physical_policy_home/.ssh"
); then
    test_pass
else
    test_fail "a configured symlink granted a writable mount outside physical CODEX_HOME"
fi

test_case "rejected CODEX_HOME cannot authorize a configured HOME TMPDIR"
if [[ "$codex_toml_readable" != true ]]; then
    test_skip "configured TMPDIR discovery requires tomllib"
elif (
    agent_type="codex"
    OCTOPUS_TANGLE_RESULTS_DIR="$POLICY_HOME/rejected-codex/results"
    # The first state holds HOME; the second holds the result channel. Their
    # existing TMPDIR descendants must not inherit authorization from either.
    for rejected_home in "$POLICY_HOME" "$POLICY_HOME/rejected-codex"; do
        if [[ "$rejected_home" == "$POLICY_HOME" ]]; then configured_tmp="$POLICY_HOME/.ssh"
        else configured_tmp="$rejected_home/tmp"; fi
        printf '[shell_environment_policy]\nset = { TMPDIR = "%s" }\n' "$configured_tmp" \
            > "$rejected_home/config.toml"
        cmd_array=(true)
        HOME="$POLICY_HOME" CODEX_HOME="$rejected_home" boundary_refuses_codex || exit 1
        ! boundary_binds_rw "$(cd "$rejected_home" && pwd -P)" || exit 1
        ! boundary_binds_rw "$(cd "$configured_tmp" && pwd -P)" || exit 1
    done
    # This otherwise-safe state is rejected only because its configured
    # symlink is hidden by the private /tmp. Its physical child needs no link.
    ln -s "$POLICY_CODEX_HOME" "$TMP_LINK_ROOT/policy-hidden"
    printf '[shell_environment_policy]\nset = { TMPDIR = "%s" }\n' "$POLICY_CODEX_HOME/tmp" \
        > "$POLICY_CODEX_HOME/config.toml"
    cmd_array=(true)
    HOME="$POLICY_HOME" CODEX_HOME="$TMP_LINK_ROOT/policy-hidden" boundary_refuses_codex || exit 1
    ! boundary_private_tmpfs "$physical_policy_codex" || exit 1
    ! boundary_private_tmpfs "$physical_policy_codex/tmp"
); then
    test_pass
else
    test_fail "a rejected CODEX_HOME still authorized writable HOME descendants"
fi

test_case "non-codex dispatch leaves the codex state read-only"
agent_type="claude"
cmd_array=(true)
if octopus_tangle_apply_execution_boundary && \
   ! boundary_private_tmpfs "$physical_codex_home" && \
   ! boundary_private_tmpfs "$physical_codex_tmp"; then
    test_pass
else
    test_fail "a non-codex dispatch could write the codex state directories"
fi

test_case "codex state overlapping the worktree, results or HOME stays read-only, even behind a symlink"
agent_type="codex"
link_root="${OUTSIDE_TMP_ROOT:-$BOUNDARY_ROOT}"
mkdir -p "$BOUNDARY_WORKTREE/.codex" "$CODEX_ROOT/userhome/u" "$CODEX_ROOT/codex-home-2"
ln -sfn "$BOUNDARY_WORKTREE/.codex" "$link_root/codex-link-into-worktree"
printf '[shell_environment_policy]\nset = { TMPDIR = "%s" }\n' "$BOUNDARY_RESULTS" \
    > "$CODEX_ROOT/codex-home-2/config.toml"
unsafe_failures=""
for unsafe_home in "$BOUNDARY_WORKTREE/.codex" "$BOUNDARY_RESULTS" \
                   "$CODEX_ROOT/userhome" "$link_root/codex-link-into-worktree"; do
    CODEX_HOME="$unsafe_home"
    cmd_array=(true)
    if ! HOME="$CODEX_ROOT/userhome/u" boundary_refuses_codex; then
        unsafe_failures+=" refused:$unsafe_home"
    elif boundary_private_tmpfs "$(cd "$unsafe_home" && pwd -P)"; then
        unsafe_failures+=" bound:$unsafe_home"
    fi
done
CODEX_HOME="$CODEX_ROOT/codex-home-2"
cmd_array=(true)
if ! boundary_refuses_codex; then
    unsafe_failures+=" admitted:tmpdir-in-results"
elif boundary_binds_rw "$(cd "$BOUNDARY_RESULTS" && pwd -P)"; then
    unsafe_failures+=" bound:tmpdir-in-results"
fi
if [[ -z "$unsafe_failures" ]]; then
    test_pass
else
    test_fail "unsafe codex state handling:$unsafe_failures"
fi

test_case "codex state holding a linked worktree's Git metadata stays read-only"
agent_type="codex"
OCTOPUS_TANGLE_WORKTREE="$GIT_FIXTURE/linked"
git_failures=""
# objects/ overlaps only the common directory, not the worktree's Git directory.
for git_home in "$GIT_FIXTURE/state-parent" "$physical_git_common" \
                "$physical_git_common/objects" "$physical_git_dir"; do
    CODEX_HOME="$git_home"
    cmd_array=(true)
    if ! boundary_refuses_codex; then
        git_failures+=" refused:$git_home"
    elif boundary_private_tmpfs "$(cd "$git_home" && pwd -P)"; then
        git_failures+=" bound:$git_home"
    fi
done
# A state directory beside the repository is still bound.
CODEX_HOME="$CODEX_STATE_HOME"
cmd_array=(true)
if ! octopus_tangle_apply_execution_boundary || ! boundary_private_tmpfs "$physical_codex_home"; then
    git_failures+=" unbound:$CODEX_STATE_HOME"
fi
OCTOPUS_TANGLE_WORKTREE="$BOUNDARY_WORKTREE"
if [[ -z "$git_failures" ]]; then
    test_pass
else
    test_fail "codex state and Git metadata:$git_failures"
fi

test_case "codex state stays read-only when the worktree's Git metadata cannot be resolved"
agent_type="codex"
mkdir -p "$CODEX_ROOT/git-broken-worktree"
printf 'gitdir: %s\n' "$CODEX_ROOT/no-such-gitdir" > "$CODEX_ROOT/git-broken-worktree/.git"
OCTOPUS_TANGLE_WORKTREE="$CODEX_ROOT/git-broken-worktree"
CODEX_HOME="$CODEX_STATE_HOME"
cmd_array=(true)
if boundary_refuses_codex && ! boundary_private_tmpfs "$physical_codex_home"; then
    test_pass
else
    test_fail "codex state was bound although the worktree's Git metadata could not be located"
fi
OCTOPUS_TANGLE_WORKTREE="$BOUNDARY_WORKTREE"

test_case "inherited Git overrides cannot unseal a linked worktree's metadata"
git init -q "$CODEX_ROOT/git-decoy"
agent_type="codex"
OCTOPUS_TANGLE_WORKTREE="$GIT_FIXTURE/linked"
CODEX_HOME="$physical_git_common/objects"
cmd_array=(true)
if GIT_DIR="$CODEX_ROOT/git-decoy/.git" GIT_COMMON_DIR="$CODEX_ROOT/git-decoy/.git" \
   GIT_WORK_TREE="$CODEX_ROOT/git-decoy" boundary_refuses_codex && \
   ! boundary_binds_rw "$CODEX_HOME"; then
    test_pass
else
    test_fail "inherited Git metadata paths allowed the linked repository's objects to be bound writable"
fi
OCTOPUS_TANGLE_WORKTREE="$BOUNDARY_WORKTREE"

test_case "malformed TOML cannot add a writable sandbox TMPDIR"
mkdir -p "$CODEX_ROOT/codex-home-malformed"
CODEX_HOME="$CODEX_ROOT/codex-home-malformed"
printf '[shell_environment_policy\nset = { TMPDIR = "%s" }\n' "$BOUNDARY_RESULTS" \
    > "$CODEX_HOME/config.toml"
cmd_array=(true)
if boundary_refuses_codex && ! boundary_private_tmpfs "$BOUNDARY_RESULTS"; then
    test_pass
else
    test_fail "malformed TOML expanded writable state or prevented the safe state bind"
fi

test_case "without tomllib, a configured sandbox TMPDIR refuses dispatch"
real_python3="$(command -v python3 || true)"
if [[ -z "$real_python3" ]]; then
    test_skip "python3 is not installed"
else
    # python3 without tomllib, as on Python 3.10 and older.
    no_tomllib_bin="$CODEX_ROOT/no-tomllib-bin"
    mkdir -p "$no_tomllib_bin"
    cat > "$no_tomllib_bin/python3" <<EOF
#!/usr/bin/env bash
[[ "\${1:-}" != "-I" ]] || shift
[[ "\${1:-}" == "-c" ]] || exec "$real_python3" "\$@"
code="\$2"
shift 2
exec "$real_python3" -c 'import sys
sys.modules["tomllib"] = None
code = sys.argv[1]
sys.argv = ["-c"] + sys.argv[2:]
exec(compile(code, "<string>", "exec"), {"__name__": "__main__"})' "\$code" "\$@"
EOF
    chmod +x "$no_tomllib_bin/python3"
    mkdir -p "$CODEX_ROOT/codex-home-plain"
    printf '[features]\nweb_search = false\n' > "$CODEX_ROOT/codex-home-plain/config.toml"
    BOUNDARY_WARNINGS="$CODEX_ROOT/warnings.log"
    log() { if [[ "$1" == "WARN" || "$1" == "ERROR" ]]; then printf '%s\n' "$*" >> "$BOUNDARY_WARNINGS"; fi; }
    saved_path="$PATH"
    PATH="$no_tomllib_bin:$PATH"
    agent_type="codex"
    tomllib_failures=""
    : > "$BOUNDARY_WARNINGS"
    CODEX_HOME="$CODEX_STATE_HOME"
    cmd_array=(true)
    boundary_refuses_codex || tomllib_failures+=" TMPDIR-admitted"
    grep -qF 'Tangle boundary refused: cannot inspect configured TMPDIR without Python 3.11+ (tomllib)' "$BOUNDARY_WARNINGS" || tomllib_failures+=" TMPDIR-silent"
    # A config.toml without a TMPDIR setting needs no warning.
    : > "$BOUNDARY_WARNINGS"
    CODEX_HOME="$CODEX_ROOT/codex-home-plain"
    cmd_array=(true)
    octopus_tangle_apply_execution_boundary || tomllib_failures+=" refused-plain"
    [[ ! -s "$BOUNDARY_WARNINGS" ]] || tomllib_failures+=" warned-plain"
    PATH="$saved_path"
    log() { :; }
    if [[ -z "$tomllib_failures" ]]; then
        test_pass
    else
        test_fail "codex state without tomllib:$tomllib_failures"
    fi
fi

PNPM_ROOT="${OUTSIDE_TMP_ROOT:-$CODEX_ROOT}"
if [[ "$PNPM_ROOT/" == /tmp/* ]]; then
    PNPM_ROOT=""
fi
if [[ -n "$PNPM_ROOT" ]]; then
    PNPM_TEST_HOME="$PNPM_ROOT/pnpm-home"
    PNPM_STORE="$PNPM_TEST_HOME/.local/share/pnpm/store"
    PNPM_WORKTREE="$PNPM_ROOT/pnpm-worktree"
    mkdir -p "$PNPM_WORKTREE" "$PNPM_ROOT/pnpm-bin" "$PNPM_STORE/v10/files" "$PNPM_STORE/v10/projects" "$PNPM_STORE/v10/tmp"
    cat > "$PNPM_ROOT/pnpm-bin/pnpm" <<EOF
#!/bin/sh
printf 'called\n' > "$PNPM_ROOT/pnpm-called"
printf '%s\n' "$PNPM_STORE/v10"
EOF
    chmod 755 "$PNPM_ROOT/pnpm-bin/pnpm"
    printf '#!/bin/sh\nexit 1\n' > "$PNPM_ROOT/pnpm-bin/node"
    chmod 755 "$PNPM_ROOT/pnpm-bin/node"
fi
pnpm_tmpfs_count() {
    local count=0
    boundary_private_tmpfs "$PNPM_STORE/v10/projects" && count=$((count + 1))
    boundary_private_tmpfs "$PNPM_STORE/v10/tmp" && count=$((count + 1))
    printf '%s\n' "$count"
}

with_pnpm_test_config() {
    HOME="$PNPM_TEST_HOME" XDG_CONFIG_HOME="$PNPM_TEST_HOME/.config" \
        npm_config_store_dir= NPM_CONFIG_STORE_DIR= pnpm_config_store_dir= PNPM_CONFIG_STORE_DIR= \
        npm_config_userconfig= NPM_CONFIG_USERCONFIG= pnpm_config_userconfig= PNPM_CONFIG_USERCONFIG= \
        npm_config_globalconfig= NPM_CONFIG_GLOBALCONFIG= pnpm_config_globalconfig= PNPM_CONFIG_GLOBALCONFIG= \
        npm_config_prefix= NPM_CONFIG_PREFIX= pnpm_config_prefix= PNPM_CONFIG_PREFIX= PREFIX= DESTDIR= "$@"
}

pnpm_boundary() {
    PNPM_HOME= XDG_DATA_HOME= PATH="$PNPM_ROOT/pnpm-bin:$PATH" \
        OCTOPUS_TANGLE_WORKTREE="${pnpm_worktree:-$PNPM_WORKTREE}" \
        with_pnpm_test_config octopus_tangle_apply_execution_boundary
}

pnpm_store_is_pinned() {
    local i
    for ((i = 0; i + 2 < ${#cmd_array[@]}; i++)); do
        if [[ "${cmd_array[i]}" == --setenv && "${cmd_array[i+1]}" == npm_config_store_dir ]]; then
            [[ "${cmd_array[i+2]}" == "$PNPM_STORE" ]]
            return
        fi
    done
    return 1
}

test_case "a pnpm implementer gets private runtime mounts and a pinned default store without invoking pnpm"
if [[ -z "$PNPM_ROOT" ]]; then
    test_skip "no fixture directory outside /tmp"
else
    agent_type="claude"
    role="implementer"
    touch "$PNPM_WORKTREE/pnpm-lock.yaml"
    cmd_array=(true)
    pnpm_status=0
    set -f
    pnpm_boundary || pnpm_status=$?
    set +f
    if [[ "$pnpm_status" -eq 0 && "$(pnpm_tmpfs_count)" == 2 && ! -e "$PNPM_ROOT/pnpm-called" ]] &&
       pnpm_store_is_pinned && ! boundary_binds_rw "$PNPM_STORE/v10/files"; then
        test_pass
    else
        test_fail "expected two private mounts, a pinned store, and no pre-boundary pnpm invocation"
    fi
fi

test_case "pnpm store mounts cannot overlap the sealed result channel"
if [[ -z "$PNPM_ROOT" ]]; then
    test_skip "no fixture directory outside /tmp"
else
    mkdir -p "$PNPM_STORE/v10/projects/results"
    cmd_array=(true)
    pnpm_status=0
    OCTOPUS_TANGLE_RESULTS_DIR="$PNPM_STORE/v10/projects/results" pnpm_boundary || pnpm_status=$?
    if [[ "$pnpm_status" -eq 0 && "$(pnpm_tmpfs_count)" == 0 ]] && ! pnpm_store_is_pinned; then
        test_pass
    else
        test_fail "overlapping store was mounted or pinned: status=$pnpm_status mounts=$(pnpm_tmpfs_count)"
    fi
    rmdir "$PNPM_STORE/v10/projects/results"
fi

test_case "pnpm store selection survives the provider credential filter"
if [[ -z "$PNPM_ROOT" ]]; then
    test_skip "no fixture directory outside /tmp"
else
    cmd_array=(env -i "PATH=$PATH" true)
    if pnpm_boundary && [[ "$(pnpm_tmpfs_count)" == 2 ]] &&
       [[ " ${cmd_array[*]} " == *" -- env -i npm_config_store_dir=$PNPM_STORE PATH="* ]]; then
        test_pass
    else
        test_fail "the isolated provider did not receive the pinned store"
    fi
fi

test_case "pnpm store selection survives both credential-removal options from the Codex env builder"
if [[ -z "$PNPM_ROOT" ]]; then
    test_skip "no fixture directory outside /tmp"
elif (
    source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
    CODEX_HOME="$PNPM_TEST_HOME/codex" OPENAI_API_KEY=fixture OCTOPUS_SECURITY_V870=true \
        KEENABLE_API_KEY=fixture MISTRAL_API_KEY=fixture build_provider_env codex &&
        cmd_array=("${PROVIDER_ENV_ARRAY[@]}" true) &&
        pnpm_boundary && [[ "$(pnpm_tmpfs_count)" == 2 ]] &&
        [[ " ${cmd_array[*]} " == *" -- env -u MISTRAL_API_KEY -u KEENABLE_API_KEY -i npm_config_store_dir=$PNPM_STORE "* ]]
); then
    test_pass
else
    test_fail "the Codex credential-removal prefix stripped the pinned store"
fi

test_case "pnpm skips the default store when the Node prefix selects or redirects a global store"
if [[ -z "$PNPM_ROOT" ]]; then
    test_skip "no fixture directory outside /tmp"
elif (
    umask 077
    mkdir -p "$PNPM_ROOT/etc"
    trap 'rm -f "$PNPM_ROOT/etc/npmrc"' EXIT
    for setting in 'store-dir=/custom/pnpm/store' 'globalconfig=/custom/npmrc'; do
        printf '%s\n' "$setting" > "$PNPM_ROOT/etc/npmrc"
        cmd_array=(true)
        pnpm_boundary && [[ "$(pnpm_tmpfs_count)" == 0 ]] && ! pnpm_store_is_pinned || exit 1
    done
); then
    test_pass
else
    test_fail "a global store or redirected config was overridden"
fi

test_case "pnpm does not pin the home store for a worktree on another filesystem"
if [[ -z "$PNPM_ROOT" ]] || ! stat -c %d -- "$PNPM_STORE" >/dev/null 2>&1 ||
   [[ "$(stat -c %d -- "$TMP_LINK_ROOT")" == "$(stat -c %d -- "$PNPM_STORE")" ]]; then
    test_skip "requires Linux fixtures on two filesystems"
elif (
    agent_type="claude"
    role="implementer"
    cross_device_worktree="$TMP_LINK_ROOT/pnpm-worktree"
    mkdir -p "$cross_device_worktree"
    touch "$cross_device_worktree/pnpm-lock.yaml"
    cmd_array=(true)
    pnpm_worktree="$cross_device_worktree" pnpm_boundary &&
        [[ "$(pnpm_tmpfs_count)" == 0 ]] && ! pnpm_store_is_pinned
); then
    test_pass
else
    test_fail "a worktree on another device received the home store pin"
fi

test_case "Codex workspace-write grants only the two private pnpm directories"
if [[ -z "$PNPM_ROOT" ]]; then
    test_skip "no fixture directory outside /tmp"
elif (
    agent_type="codex"
    role="implementer"
    CODEX_HOME="$PNPM_TEST_HOME/codex"
    mkdir -p "$CODEX_HOME"
    for wrapper in "" "$PROJECT_ROOT/scripts/helpers/codex-run.sh"; do
        for mode in workspace-write read-only danger-full-access; do
            cmd_array=(env -u MISTRAL_API_KEY -i "PATH=$PATH" ${wrapper:+"$wrapper"}
                       codex exec --skip-git-repo-check --model mock --sandbox "$mode" -)
            pnpm_boundary && [[ "$(pnpm_tmpfs_count)" == 2 ]] || exit 1
            writable_dirs=()
            for ((i = 0; i + 1 < ${#cmd_array[@]}; i++)); do
                if [[ "${cmd_array[i]}" == --add-dir ]]; then
                    writable_dirs+=("${cmd_array[i+1]}")
                fi
            done
            if [[ "$mode" == workspace-write ]]; then
                [[ "${#writable_dirs[@]}" == 2 &&
                   "${writable_dirs[0]}" == "$PNPM_STORE/v10/projects" &&
                   "${writable_dirs[1]}" == "$PNPM_STORE/v10/tmp" ]] || exit 1
            else
                [[ "${#writable_dirs[@]}" == 0 ]] || exit 1
            fi
        done
    done
); then
    test_pass
else
    test_fail "Codex sandbox roots did not match the private mounts and sandbox mode"
fi

test_case "reviewers, projects that name their own pnpm store, and projects without a pnpm lockfile get no pnpm tmpfs"
if [[ -z "$PNPM_ROOT" ]]; then
    test_skip "no fixture directory outside /tmp"
else
    pnpm_mounts=""
    role="reviewer"
    cmd_array=(true)
    pnpm_boundary && pnpm_mounts+="reviewer=$(pnpm_tmpfs_count) "
    role="implementer"
    printf 'store-dir=.pnpm-store\n' > "$PNPM_WORKTREE/.npmrc"
    cmd_array=(true)
    pnpm_boundary && pnpm_mounts+="named=$(pnpm_tmpfs_count) "
    rm -f "$PNPM_WORKTREE/.npmrc" "$PNPM_WORKTREE/pnpm-lock.yaml"
    cmd_array=(true)
    pnpm_boundary && pnpm_mounts+="unlocked=$(pnpm_tmpfs_count)"
    if [[ "$pnpm_mounts" == "reviewer=0 named=0 unlocked=0" ]]; then
        test_pass
    else
        test_fail "unexpected pnpm mounts: $pnpm_mounts"
    fi
fi

eval "$saved_probe"
CODEX_HOME="$CODEX_STATE_HOME"

if octopus_tangle_execution_boundary_probe; then
    test_case "codex runtime writes succeed privately without persisting host state"
    agent_type="codex"
    rm -f "$BOUNDARY_OUTSIDE"
    cmd_array=(bash -c 'touch "$1/tmp/state" || exit 1
                        [[ -e "$1/tmp/state" ]] || exit 2
                        touch "$2/lock" 2>/dev/null || true
                        touch "$3" 2>/dev/null || true
                        touch "$4/forged.txt" 2>/dev/null || true' \
               _ "$CODEX_STATE_HOME" "$CODEX_STATE_TMP" "$BOUNDARY_OUTSIDE" "$BOUNDARY_RESULTS")
    if octopus_tangle_apply_execution_boundary && "${cmd_array[@]}" &&
       [[ ! -e "$CODEX_STATE_HOME/tmp/state" && ! -e "$CODEX_STATE_TMP/lock" ]] &&
       [[ ! -e "$BOUNDARY_OUTSIDE" && ! -e "$BOUNDARY_RESULTS/forged.txt" ]]; then
        test_pass
    else
        test_fail "runtime storage failed or a worker write persisted outside the worktree"
    fi

    test_case "codex lock directories accept writes inside the boundary and persist nothing"
    if [[ -z "$OUTSIDE_TMP_ROOT" ]]; then
        test_skip "needs a writable /var/tmp: the boundary replaces /tmp"
    elif (
        agent_type="codex"
        LOCK_REAL_HOME="$OUTSIDE_TMP_ROOT/codex-lock-home"
        mkdir -p "$LOCK_REAL_HOME/thread-writer-locks" "$LOCK_REAL_HOME/skills"
        : > "$LOCK_REAL_HOME/config.toml"
        cmd_array=(bash -c 'touch "$1/thread-writer-locks/.coordination.lock" || exit 1
                            mkdir -p "$1/.tmp" && touch "$1/.tmp/plugins.sync.lock" || exit 2
                            if touch "$1/skills/forged" 2>/dev/null; then exit 3; fi
                            if touch "$1/config.toml.new" 2>/dev/null; then exit 4; fi' \
                   _ "$LOCK_REAL_HOME")
        CODEX_HOME="$LOCK_REAL_HOME" octopus_tangle_apply_execution_boundary || exit 1
        "${cmd_array[@]}" || exit 1
        [[ ! -e "$LOCK_REAL_HOME/thread-writer-locks/.coordination.lock" && \
           ! -e "$LOCK_REAL_HOME/.tmp" && ! -e "$LOCK_REAL_HOME/skills/forged" ]]
    ); then
        test_pass
    else
        test_fail "codex locks were not writable in the boundary, or a write reached the host or the read-only inputs"
    fi

    test_case "a real worker cannot edit config or expose HOME on its next dispatch"
    if [[ "$codex_toml_readable" != true ]]; then
        test_skip "configured TMPDIR discovery requires tomllib"
    elif (
        agent_type="codex"
        printf '[shell_environment_policy]\nset = { TMPDIR = "%s" }\n' "$CODEX_STATE_TMP" \
            > "$POLICY_CODEX_HOME/config.toml"
        config_before="$(cat "$POLICY_CODEX_HOME/config.toml")"
        cmd_array=(bash -c 'if printf "poison" > "$1/config.toml" 2>/dev/null; then exit 3; fi
                            if mv "$1/config.toml" "$1/config.saved" 2>/dev/null; then exit 4; fi
                            touch "$1/tmp/first-dispatch"' _ "$POLICY_CODEX_HOME")
        HOME="$POLICY_HOME" CODEX_HOME="$POLICY_CODEX_HOME" octopus_tangle_apply_execution_boundary || exit 1
        "${cmd_array[@]}" || exit 1
        [[ "$(cat "$POLICY_CODEX_HOME/config.toml")" == "$config_before" ]] || exit 1
        cmd_array=(bash -c 'touch "$1/tmp/second-dispatch" || exit 1
                            [[ ! -e "$1/tmp/first-dispatch" ]] || exit 2
                            if touch "$2/forged" 2>/dev/null; then exit 3; fi' \
                   _ "$POLICY_CODEX_HOME" "$POLICY_HOME/.ssh")
        HOME="$POLICY_HOME" CODEX_HOME="$POLICY_CODEX_HOME" octopus_tangle_apply_execution_boundary || exit 1
        "${cmd_array[@]}" || exit 1
        [[ ! -e "$POLICY_CODEX_HOME/tmp/second-dispatch" && ! -e "$POLICY_HOME/.ssh/forged" ]]
    ); then
        test_pass
    else
        test_fail "a worker changed persistent configuration or made HOME writable"
    fi

    test_case "mutable CODEX_HOME aliases refuse dispatch before a worker runs"
    if [[ -z "$OUTSIDE_TMP_ROOT" || "$codex_toml_readable" != true ]]; then
        test_skip "two-dispatch state alias controls require /var/tmp and tomllib"
    elif (
        agent_type="codex"
        # Aliases in the worktree, external TMPDIR or original state cannot
        # authorize a dispatch. Only owned synthetic directories are used.
        for layout in worktree external-tmp own-state; do
            fixture="$OUTSIDE_TMP_ROOT/retarget-$layout"
            mkdir -p "$fixture/home/.ssh" "$fixture/state" "$fixture/tmp" "$fixture/worktree" "$fixture/results"
            fixture="$(cd "$fixture" && pwd -P)"
            case "$layout" in
                worktree) alias_path="$fixture/worktree/codex-home"; tmp_path="$fixture/tmp" ;;
                external-tmp) alias_path="$fixture/tmp/codex-home"; tmp_path="$fixture/tmp" ;;
                own-state) alias_path="$fixture/state/codex-home"; tmp_path="$fixture/state" ;;
            esac
            ln -s "$fixture/state" "$alias_path"
            printf '[shell_environment_policy]\nset = { TMPDIR = "%s" }\n' "$tmp_path" > "$fixture/state/config.toml"
            export OCTOPUS_TANGLE_WORKTREE="$fixture/worktree" OCTOPUS_TANGLE_RESULTS_DIR="$fixture/results"
            cmd_array=(bash -c 'touch "$1/ran"' _ "$fixture/worktree")
            HOME="$fixture/home" CODEX_HOME="$alias_path" boundary_refuses_codex || exit 1
            [[ ! -e "$fixture/worktree/ran" && "$(readlink "$alias_path")" == "$fixture/state" ]] || exit 1
        done
    ); then
        test_pass
    else
        test_fail "a retargeted state alias granted writable protected HOME on a later dispatch"
    fi

    test_case "codex state behind a symlink hidden below /tmp stays read-only"
    agent_type="codex"
    # The private /tmp hides these links, so codex could not reach its state
    # by the configured path even with the target bound.
    hidden_links=("$TMP_LINK_ROOT/codex-link")
    ln -sfn "$CODEX_STATE_HOME" "$TMP_LINK_ROOT/codex-link"
    if [[ -n "$OUTSIDE_TMP_ROOT" ]]; then
        ln -sfn "$TMP_LINK_ROOT/codex-link" "$OUTSIDE_TMP_ROOT/codex-chain"
        hidden_links+=("$OUTSIDE_TMP_ROOT/codex-chain")
    fi
    hidden_failures=""
    for codex_link in "${hidden_links[@]}"; do
        CODEX_HOME="$codex_link"
        cmd_array=(true)
        if ! boundary_refuses_codex; then
            hidden_failures+=" refused:$codex_link"
        elif boundary_private_tmpfs "$physical_codex_home"; then
            hidden_failures+=" bound:$codex_link"
        fi
    done
    if [[ -z "$hidden_failures" ]]; then
        test_pass
    else
        test_fail "codex state behind a hidden symlink:$hidden_failures"
    fi
    CODEX_HOME="$CODEX_STATE_HOME"

    test_case "codex state holding the Git metadata cannot unseal it under bwrap"
    if [[ -z "$OUTSIDE_TMP_ROOT" ]]; then
        test_skip "no writable /var/tmp; below /tmp the private /tmp would hide the Git metadata"
    else
        agent_type="codex"
        # Outside /tmp, so the Git metadata is visible inside the boundary and
        # the writes below test the seal, not a missing directory.
        make_linked_worktree "$OUTSIDE_TMP_ROOT/git"
        seal_git_dir="$(cd "$(git -C "$OUTSIDE_TMP_ROOT/git/linked" rev-parse --absolute-git-dir)" && pwd -P)"
        seal_git_common="$(cd "$OUTSIDE_TMP_ROOT/git/state-parent/main/.git" && pwd -P)"
        OCTOPUS_TANGLE_WORKTREE="$OUTSIDE_TMP_ROOT/git/linked"
        CODEX_HOME="$OUTSIDE_TMP_ROOT/git/state-parent"
        cmd_array=(bash -c '[[ -d "$1" && -d "$2" ]] || exit 3
                            touch "$1/forged" 2>/dev/null || true
                            touch "$2/forged" 2>/dev/null || true
                            touch "$3/inside.txt"' \
                   _ "$seal_git_dir" "$seal_git_common" "$OUTSIDE_TMP_ROOT/git/linked")
        if boundary_refuses_codex &&
           [[ ! -e "$OUTSIDE_TMP_ROOT/git/linked/inside.txt" ]] &&
           [[ ! -e "$seal_git_dir/forged" ]] &&
           [[ ! -e "$seal_git_common/forged" ]]; then
            test_pass
        else
            test_fail "a codex state directory holding the main repository made its Git metadata writable"
        fi
        OCTOPUS_TANGLE_WORKTREE="$BOUNDARY_WORKTREE"
        CODEX_HOME="$CODEX_STATE_HOME"
    fi
fi
if octopus_tangle_execution_boundary_probe; then
    test_case "a real boundary retains the provider's pinned pnpm store and isolates runtime writes"
    if [[ -z "$PNPM_ROOT" ]]; then
        test_skip "no fixture directory outside /tmp"
    else
        agent_type="claude"
        role="implementer"
        touch "$PNPM_WORKTREE/pnpm-lock.yaml"
        cmd_array=(env -u MISTRAL_API_KEY -u KEENABLE_API_KEY -i "PATH=$PATH" bash -c '
            [[ "${npm_config_store_dir:-}" == "$1" ]] &&
            touch "$1/v10/projects/private" "$1/v10/tmp/private" &&
            ! touch "$1/v10/files/read-only" 2>/dev/null
        ' _ "$PNPM_STORE")
        if pnpm_boundary && "${cmd_array[@]}" &&
           [[ ! -e "$PNPM_STORE/v10/projects/private" &&
              ! -e "$PNPM_STORE/v10/tmp/private" &&
              ! -e "$PNPM_STORE/v10/files/read-only" ]]; then
            test_pass
        else
            test_fail "store pin or filesystem permissions did not survive sandbox launch"
        fi
        rm -f "$PNPM_WORKTREE/pnpm-lock.yaml"
    fi

    test_case "pnpm install --frozen-lockfile --offline runs for a worktree pnpm has never registered"
    if [[ -z "$PNPM_ROOT" ]] || ! real_pnpm="$(command -v pnpm)"; then
        test_skip "pnpm or a fixture directory outside /tmp is unavailable"
    elif [[ "$(cd "$PNPM_ROOT" && env -i "HOME=$PNPM_TEST_HOME" "PATH=$PATH" "$real_pnpm" --version)" != 10.* ]]; then
        test_skip "requires pnpm 10 to exercise its v10 store"
    else
        pnpm_seed="$PNPM_ROOT/pnpm-seed"
        pnpm_ws="$PNPM_ROOT/pnpm-ws"
        pnpm_home="$PNPM_ROOT/pnpm-live-home"
        pnpm_host_store="$pnpm_home/store"
        mkdir -p "$pnpm_home" "$PNPM_ROOT/archive/package"
        printf '{"name":"octo-store-fixture","version":"1.0.0"}\n' > "$PNPM_ROOT/archive/package/package.json"
        printf 'cached package content\n' > "$PNPM_ROOT/archive/package/content.txt"
        tar -czf "$PNPM_ROOT/fixture.tgz" -C "$PNPM_ROOT/archive" package
        for pnpm_dir in "$pnpm_seed" "$pnpm_ws"; do
            mkdir -p "$pnpm_dir/packages/a"
            printf '{"name":"root","version":"0.0.0","private":true,"dependencies":{"octo-store-fixture":"file:../fixture.tgz"}}\n' \
                > "$pnpm_dir/package.json"
            printf 'packages:\n  - "packages/*"\n' > "$pnpm_dir/pnpm-workspace.yaml"
            printf '{"name":"a","version":"0.0.0"}\n' > "$pnpm_dir/packages/a/package.json"
        done
        if ! (cd "$pnpm_seed" && env -i "HOME=$PNPM_TEST_HOME" "PATH=$PATH" "PNPM_HOME=$pnpm_home" \
                 CI=true "$real_pnpm" install --no-frozen-lockfile --offline --ignore-scripts >"$PNPM_ROOT/pnpm-seed.log" 2>&1) ||
           ! cp "$pnpm_seed/pnpm-lock.yaml" "$pnpm_ws/pnpm-lock.yaml"; then
            cat "$PNPM_ROOT/pnpm-seed.log"
            test_fail "pnpm could not seed the fixture store outside the boundary"
        else
            # pnpm checks the file: archive even with a frozen lockfile.
            # Keep it read-only outside the sandboxed worktree.
            mkdir -p "$pnpm_host_store/v10/projects" "$pnpm_host_store/v10/tmp"
            registered_before="$(ls -A "$pnpm_host_store/v10/projects" | wc -l | tr -d ' ')"
            agent_type="claude"
            role="implementer"
            install_status=0
            cmd_array=(env -i "HOME=$PNPM_TEST_HOME" "PATH=$PATH" "CI=true"
                       bash -c '[[ "${npm_config_store_dir:-}" == "$2" ]] &&
                                cd "$1" && pnpm install --frozen-lockfile --offline' _ "$pnpm_ws" "$pnpm_host_store")
            if PNPM_HOME="$pnpm_home" OCTOPUS_TANGLE_WORKTREE="$pnpm_ws" \
                with_pnpm_test_config octopus_tangle_apply_execution_boundary; then
                "${cmd_array[@]}" >"$PNPM_ROOT/pnpm-install.log" 2>&1 || install_status=$?
            else
                install_status=125
            fi
            if [[ "$install_status" -eq 0 ]] &&
               grep -qx 'cached package content' "$pnpm_ws/node_modules/octo-store-fixture/content.txt" &&
               [[ "$(ls -A "$pnpm_host_store/v10/projects" | wc -l | tr -d ' ')" == "$registered_before" ]]; then
                test_pass
            else
                cat "$PNPM_ROOT/pnpm-install.log" 2>/dev/null || true
                test_fail "status=$install_status"
            fi
        fi
    fi
fi
unset agent_type CODEX_HOME

test_summary
