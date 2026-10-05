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
# physical path: a configured path that goes through a symlink is also checked
# inside a real boundary, and that needs bwrap.
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
    if ! HOME="$CODEX_ROOT/userhome/u" octopus_tangle_apply_execution_boundary; then
        unsafe_failures+=" refused:$unsafe_home"
    elif boundary_binds_rw "$(cd "$unsafe_home" && pwd -P)"; then
        unsafe_failures+=" bound:$unsafe_home"
    fi
done
CODEX_HOME="$CODEX_ROOT/codex-home-2"
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

test_case "codex state holding a linked worktree's Git metadata stays read-only"
agent_type="codex"
OCTOPUS_TANGLE_WORKTREE="$GIT_FIXTURE/linked"
git_failures=""
# objects/ overlaps only the common directory, not the worktree's Git directory.
for git_home in "$GIT_FIXTURE/state-parent" "$physical_git_common" \
                "$physical_git_common/objects" "$physical_git_dir"; do
    CODEX_HOME="$git_home"
    cmd_array=(true)
    if ! octopus_tangle_apply_execution_boundary; then
        git_failures+=" refused:$git_home"
    elif boundary_binds_rw "$(cd "$git_home" && pwd -P)"; then
        git_failures+=" bound:$git_home"
    fi
done
# A state directory beside the repository is still bound.
CODEX_HOME="$CODEX_STATE_HOME"
cmd_array=(true)
if ! octopus_tangle_apply_execution_boundary || ! boundary_binds_rw "$physical_codex_home"; then
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
if octopus_tangle_apply_execution_boundary && ! boundary_binds_rw "$physical_codex_home"; then
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
   GIT_WORK_TREE="$CODEX_ROOT/git-decoy" octopus_tangle_apply_execution_boundary && \
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
if octopus_tangle_apply_execution_boundary && \
   boundary_binds_rw "$CODEX_HOME" && ! boundary_binds_rw "$BOUNDARY_RESULTS"; then
    test_pass
else
    test_fail "malformed TOML expanded writable state or prevented the safe state bind"
fi

test_case "without tomllib, a configured sandbox TMPDIR stays read-only with a warning"
real_python3="$(command -v python3 || true)"
if [[ -z "$real_python3" ]]; then
    test_skip "python3 is not installed"
else
    # python3 without tomllib, as on Python 3.10 and older.
    no_tomllib_bin="$CODEX_ROOT/no-tomllib-bin"
    mkdir -p "$no_tomllib_bin"
    cat > "$no_tomllib_bin/python3" <<EOF
#!/usr/bin/env bash
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
    log() { if [[ "$1" == "WARN" ]]; then printf '%s\n' "$*" >> "$BOUNDARY_WARNINGS"; fi; }
    saved_path="$PATH"
    PATH="$no_tomllib_bin:$PATH"
    agent_type="codex"
    tomllib_failures=""
    : > "$BOUNDARY_WARNINGS"
    CODEX_HOME="$CODEX_STATE_HOME"
    cmd_array=(true)
    if ! octopus_tangle_apply_execution_boundary; then
        tomllib_failures+=" refused"
    else
        boundary_binds_rw "$physical_codex_home" || tomllib_failures+=" CODEX_HOME-unbound"
        ! boundary_binds_rw "$physical_codex_tmp" || tomllib_failures+=" TMPDIR-bound"
        grep -q 'tomllib' "$BOUNDARY_WARNINGS" || tomllib_failures+=" no-warning"
    fi
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

    test_case "a symlinked codex state directory is bound and writable through its configured path"
    agent_type="codex"
    # A link outside /tmp stays visible on the read-only root; a link inside the
    # worktree comes back with the worktree bind, even when the worktree is
    # below /tmp.
    reachable_links=("$BOUNDARY_WORKTREE/codex-link")
    ln -sfn "$CODEX_STATE_HOME" "$BOUNDARY_WORKTREE/codex-link"
    if [[ -n "$OUTSIDE_TMP_ROOT" ]]; then
        ln -sfn "$CODEX_STATE_HOME" "$OUTSIDE_TMP_ROOT/codex-link"
        reachable_links+=("$OUTSIDE_TMP_ROOT/codex-link")
    fi
    reachable_failures=""
    for codex_link in "${reachable_links[@]}"; do
        CODEX_HOME="$codex_link"
        rm -f "$CODEX_STATE_HOME/via-link"
        cmd_array=(bash -c 'touch "$1/via-link"' _ "$codex_link")
        if ! octopus_tangle_apply_execution_boundary; then
            reachable_failures+=" refused:$codex_link"
        elif ! boundary_binds_rw "$physical_codex_home"; then
            reachable_failures+=" unbound:$codex_link"
        elif ! "${cmd_array[@]}" || [[ ! -e "$CODEX_STATE_HOME/via-link" ]]; then
            reachable_failures+=" unwritable:$codex_link"
        fi
    done
    rm -f "$BOUNDARY_WORKTREE/codex-link" "$CODEX_STATE_HOME/via-link"
    if [[ -z "$reachable_failures" ]]; then
        test_pass
    else
        test_fail "symlinked codex state:$reachable_failures"
    fi
    CODEX_HOME="$CODEX_STATE_HOME"

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
        if ! octopus_tangle_apply_execution_boundary; then
            hidden_failures+=" refused:$codex_link"
        elif boundary_binds_rw "$physical_codex_home"; then
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
        if octopus_tangle_apply_execution_boundary && "${cmd_array[@]}" &&
           [[ -e "$OUTSIDE_TMP_ROOT/git/linked/inside.txt" ]] &&
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
unset agent_type CODEX_HOME

test_summary
