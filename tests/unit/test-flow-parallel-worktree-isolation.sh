#!/usr/bin/env bash
# flow-parallel renders one launch.sh per work package and runs them concurrently.
# The template used to reuse the session branch, so `git worktree add <dir>
# <current-branch>` succeeded for the first package and failed for every other
# one — git refuses to check a branch out in two worktrees, and the retry arm
# only covered an already-existing directory, so packages 2..N exited 1 before
# their agent ever started. It also ran under `set -e` with `EXIT_CODE=$?` after
# the agent call, so a non-zero `claude -p` aborted the script before exit-code
# and .done were written and the orchestrator's monitor waited out the whole
# wave timeout. Finally it force-removed the worktree unconditionally, on the
# claim that "changes are in output.md not the worktree", which destroyed the
# diff of every package that actually edited files.
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
# Hook-provided Git variables must not redirect operations into a real repo.
while IFS= read -r git_var; do unset "$git_var"; done < <(git rev-parse --local-env-vars)
test_suite "flow-parallel worktree isolation"

SKILL_FILES=(
    "$(resolve_claude_skill_path flow-parallel)"
    "$PROJECT_ROOT/skills/flow-parallel/SKILL.md"
)

# Run the shipped validation block in a fresh shell for each artifact.
for skill in "${SKILL_FILES[@]}" "$PROJECT_ROOT/codex-skills/flow-parallel/SKILL.md"; do
    gate="$TEST_TMP_DIR/wbs-gate.sh"
    awk '/^# Validate WBS was created$/{grab=1} grab && /^```$/{exit} grab' "$skill" > "$gate"
    fixture="$TEST_TMP_DIR/wbs"
    mkdir -p "$fixture/.octo/parallel"
    wbs="$fixture/.octo/parallel/wbs.json"
    rm -f "$wbs"

    for state in missing malformed valid; do
        test_case "${skill#"$PROJECT_ROOT"/} WBS validation with $state input"
        case "$state" in
            missing) expected=1; message='WBS validation: FAILED - file not found' ;;
            malformed)
                printf '{broken\n' > "$wbs"
                expected=1
                message='WBS validation: FAILED - could not read valid JSON'
                ;;
            valid)
                printf '%s\n' '{"work_packages":[{"id":"WP-1"}]}' > "$wbs"
                expected=0
                message='WBS validation: PASSED'
                ;;
        esac
        rc=0
        (cd "$fixture" && bash "$gate") > "$fixture/stdout" 2> "$fixture/stderr" || rc=$?
        actual_file="$fixture/stdout"
        empty_file="$fixture/stderr"
        if [[ "$expected" == 1 ]]; then
            actual_file="$fixture/stderr"
            empty_file="$fixture/stdout"
        fi
        if [[ "$rc" == "$expected" && "$(cat "$actual_file")" == "$message" && ! -s "$empty_file" ]]; then
            test_pass
        else
            test_fail "expected rc=$expected and $message, got rc=$rc: $(cat "$fixture/stdout" "$fixture/stderr")"
        fi
    done
done

# The launch template lives in a fenced heredoc inside the skill. Render it the
# way the orchestrator does rather than re-stating it here, so the test tracks
# the shipped text.
extract_launch_template() {
    # Read the authored heredoc so the test exercises the shipped launcher.
    awk '/^cat > "\.octo\/parallel\/WP-N\/launch\.sh" << .LAUNCHEOF.$/ {grab=1; next}
         grab && /^LAUNCHEOF$/ {exit}
         grab {print}' "$1"
}

render_launch() {
    # Substitute the package's explicit project, branch, and base ref.
    local skill="$1" root="$2" wp_id="$3" branch="$4" base="$5" out="$6"
    base="$(git -C "$root" rev-parse --verify "$base^{commit}")" || return 1
    extract_launch_template "$skill" \
        | sed -e "s|<absolute-project-root-path>|$root|g" \
              -e "s|WP_ID=\"WP-N\"|WP_ID=\"$wp_id\"|" \
              -e "s|<wp-branch-name>|$branch|g" \
              -e "s|<base-ref>|$base|g" > "$out"
    chmod +x "$out"
}

test_case "the launch template is extractable from both skill copies"
missing=""
for f in "${SKILL_FILES[@]}"; do
    [[ -s "$f" ]] || { missing="$missing ${f#"$PROJECT_ROOT"/}"; continue; }
    [[ -n "$(extract_launch_template "$f")" ]] || missing="$missing ${f#"$PROJECT_ROOT"/}"
done
if [[ -z "$missing" ]]; then test_pass; else test_fail "no launch template in:$missing"; fi

test_case "neither copy pins work packages to the session branch"
bad=""
for f in "${SKILL_FILES[@]}"; do
    tpl="$(extract_launch_template "$f")"
    grep -q 'CURRENT_BRANCH' <<< "$tpl" && bad="$bad ${f#"$PROJECT_ROOT"/}(CURRENT_BRANCH)"
    grep -q 'WP_BRANCH' <<< "$tpl" || bad="$bad ${f#"$PROJECT_ROOT"/}(no WP_BRANCH)"
done
if [[ -z "$bad" ]]; then test_pass; else test_fail "session-branch reuse:$bad"; fi

test_case "neither copy aborts before recording exit-code and .done"
bad=""
for f in "${SKILL_FILES[@]}"; do
    tpl="$(extract_launch_template "$f")"
    grep -qE '^set -e' <<< "$tpl" && bad="$bad ${f#"$PROJECT_ROOT"/}(set -e)"
done
if [[ -z "$bad" ]]; then test_pass; else test_fail "agent failure can skip the markers:$bad"; fi

# --- behavioural cases, against a throwaway repo and a stub agent -------------

FIXTURE="$TEST_TMP_DIR/repo"
STUB_BIN="$TEST_TMP_DIR/bin"
mkdir -p "$FIXTURE" "$STUB_BIN"

git -C "$FIXTURE" init --quiet -b main
git -C "$FIXTURE" config user.email octo@example.com
git -C "$FIXTURE" config user.name "Octo Test"
printf 'seed\n' > "$FIXTURE/seed.txt"
git -C "$FIXTURE" add seed.txt
git -C "$FIXTURE" commit --quiet -m "seed"
# The session branch is checked out, exactly as it is when the skill runs.
git -C "$FIXTURE" checkout --quiet -b session/in-progress

make_stub() {
    # Replace the billed agent with deterministic fixture behavior.
    cat > "$STUB_BIN/claude" <<SH
#!/usr/bin/env bash
cat > /dev/null
$1
SH
    chmod +x "$STUB_BIN/claude"
}

run_package() {
    # Render and run a package without a live provider or user registry.
    local wp_id="$1" branch="$2" dir="$TEST_TMP_DIR/$1" root="${3:-$FIXTURE}" base="${4:-main}"
    local skill="${5:-${SKILL_FILES[0]}}"
    mkdir -p "$dir"
    printf 'do the thing\n' > "$dir/instructions.md"
    render_launch "$skill" "$root" "$wp_id" "$branch" "$base" "$dir/launch.sh"
    ( PATH="$STUB_BIN:$PATH" HOME="$TEST_TMP_DIR/home" bash "$dir/launch.sh" ) >/dev/null 2>&1 || true
}

test_case "workers refuse a mutable base before starting an agent"
make_stub 'echo AGENT_RAN'
for skill in "${SKILL_FILES[@]}"; do
    dir="$TEST_TMP_DIR/mutable-base"
    mkdir -p "$dir"
    printf 'inert instructions\n' > "$dir/instructions.md"
    render_launch "$skill" "$FIXTURE" WP-MUTABLE octo/wp-mutable main "$dir/launch.sh"
    frozen="$(git -C "$FIXTURE" rev-parse main)"
    sed "s/$frozen/main/g" "$dir/launch.sh" > "$dir/mutable.sh"
    code=0
    ( HOME="$TEST_TMP_DIR/home" PATH="$STUB_BIN:$PATH" bash "$dir/mutable.sh" ) > "$dir/result" 2>&1 || code=$?
    if [[ "$code" == 1 && "$(cat "$dir/exit-code" 2>/dev/null)" == 1 && -e "$dir/.done" ]] &&
       ! grep -q AGENT_RAN "$dir/result" && ! git -C "$FIXTURE" show-ref --verify --quiet refs/heads/octo/wp-mutable; then
        test_pass
    else
        test_fail "mutable base ran an agent or created a worker branch: $skill"
    fi
done

test_case "one frozen base survives ref advancement between worker launches"
for index in "${!SKILL_FILES[@]}"; do
    skill="${SKILL_FILES[$index]}"
    freeze="$(awk '/^# Freeze the selected base once/ {grab=1} grab && /^```$/ {exit} grab {print}' "$skill")"
    frozen="$(cd "$FIXTURE" && BASE_REF=main bash -eu -c "$freeze")"
    frozen="${frozen#BASE_COMMIT=}"
    if [[ "$frozen" != "$(git -C "$FIXTURE" rev-parse main)" ]]; then
        test_fail "setup did not resolve the selected ref: $skill"
        continue
    fi
    make_stub 'git rev-parse HEAD'
    run_package "WP-FROZEN-$index-A" "octo/frozen-$index-a" "$FIXTURE" "$frozen" "$skill"
    git -C "$FIXTURE" commit --quiet --allow-empty -m "advance selected base"
    git -C "$FIXTURE" update-ref refs/heads/main HEAD
    run_package "WP-FROZEN-$index-B" "octo/frozen-$index-b" "$FIXTURE" "$frozen" "$skill"
    if [[ "$(cat "$TEST_TMP_DIR/WP-FROZEN-$index-A/output.md")" == "$frozen" &&
          "$(cat "$TEST_TMP_DIR/WP-FROZEN-$index-B/output.md")" == "$frozen" ]]; then
        test_pass
    else
        test_fail "workers started from different commits: $skill"
    fi
    git -C "$FIXTURE" update-ref refs/heads/main "$frozen"
done

test_case "a retry refuses a worktree that predates its frozen base"
stale_dir="$TEST_TMP_DIR/.octo-worktree-repo-WP-STALEBASE"
git -C "$FIXTURE" worktree add --quiet -b octo/stale-base "$stale_dir" main
make_stub 'echo AGENT_RAN'
run_package WP-STALEBASE octo/stale-base "$FIXTURE" session/in-progress
if [[ "$(cat "$TEST_TMP_DIR/WP-STALEBASE/exit-code")" == 1 &&
      -e "$TEST_TMP_DIR/WP-STALEBASE/.done" && ! -e "$TEST_TMP_DIR/WP-STALEBASE/output.md" ]] &&
   [[ "$(git -C "$stale_dir" rev-parse HEAD)" == "$(git -C "$FIXTURE" rev-parse main)" ]]; then
    test_pass
else
    test_fail "an incompatible retry ran an agent or changed the retained worktree"
fi

test_case "two packages each get their own worktree and branch"
make_stub 'printf "committed\n" > wp.txt; git add wp.txt; git commit --quiet -m "wp work"; echo done'
run_package WP-1 octo/wp-1
run_package WP-2 octo/wp-2
both_done=1
for wp in WP-1 WP-2; do
    [[ -f "$TEST_TMP_DIR/$wp/.done" ]] || both_done=0
    [[ "$(cat "$TEST_TMP_DIR/$wp/exit-code" 2>/dev/null)" == "0" ]] || both_done=0
done
branches="$(git -C "$FIXTURE" branch --list 'octo/wp-*' --format '%(refname:short)' | sort | tr '\n' ' ')"
if [[ "$both_done" -eq 1 && "$branches" == "octo/wp-1 octo/wp-2 " ]]; then
    test_pass
else
    test_fail "done=$both_done branches='$branches' (second package used to fail on the shared branch)"
fi

test_case "a committed package lands its commit and its worktree is reclaimed"
run_package WP-CLEAN octo/wp-clean
commits="$(git -C "$FIXTURE" rev-list --count main..octo/wp-clean 2>/dev/null || echo 0)"
registered="$(git -C "$FIXTURE" worktree list --porcelain)"
if [[ "$commits" == "1" && ! -d "$FIXTURE/../.octo-worktree-repo-WP-CLEAN" ]] &&
    ! grep -q '^branch refs/heads/octo/wp-clean$' <<< "$registered"; then
    test_pass
else
    test_fail "commits=$commits; committed package worktree or registration was not reclaimed"
fi

test_case "a retry retains an existing descendant branch instead of resetting it"
descendant="$(git -C "$FIXTURE" rev-parse octo/wp-clean)"
make_stub 'git rev-parse HEAD'
run_package WP-CLEAN octo/wp-clean
if [[ "$(cat "$TEST_TMP_DIR/WP-CLEAN/output.md")" == "$descendant" &&
      "$(git -C "$FIXTURE" rev-parse octo/wp-clean)" == "$descendant" &&
      "$(cat "$TEST_TMP_DIR/WP-CLEAN/exit-code")" == 0 ]]; then
    test_pass
else
    test_fail "retry discarded or rejected existing work after the shared base"
fi

test_case "uncommitted work is kept, not force-removed"
make_stub 'printf "unsaved\n" > stranded.txt; echo done'
run_package WP-3 octo/wp-3
kept_dir="$FIXTURE/../.octo-worktree-repo-WP-3"
if [[ -f "$kept_dir/stranded.txt" ]]; then
    test_pass
else
    test_fail "the worktree was discarded with uncommitted work in it"
fi
git -C "$FIXTURE" worktree remove "$kept_dir" --force 2>/dev/null || true

test_case "a failing agent still records exit-code and .done"
make_stub 'exit 42'
run_package WP-4 octo/wp-4
code="$(cat "$TEST_TMP_DIR/WP-4/exit-code" 2>/dev/null || echo missing)"
if [[ -f "$TEST_TMP_DIR/WP-4/.done" && "$code" == "42" ]]; then
    test_pass
else
    test_fail "exit-code=$code done=$([[ -f "$TEST_TMP_DIR/WP-4/.done" ]] && echo yes || echo no)"
fi
git -C "$FIXTURE" worktree remove "$FIXTURE/../.octo-worktree-repo-WP-4" --force 2>/dev/null || true

test_case "sibling projects keep separate worktrees for the same package ID"
OTHER_FIXTURE="$TEST_TMP_DIR/other-repo"
git clone --quiet "$FIXTURE" "$OTHER_FIXTURE"
git -C "$OTHER_FIXTURE" checkout --quiet main
make_stub 'printf "retained\n" > retained.txt; echo done'
run_package WP-SIB octo/wp-sibling
run_package WP-SIB octo/wp-sibling "$OTHER_FIXTURE"
if [[ -f "$TEST_TMP_DIR/.octo-worktree-repo-WP-SIB/retained.txt" &&
      -f "$TEST_TMP_DIR/.octo-worktree-other-repo-WP-SIB/retained.txt" ]]; then
    test_pass
else
    test_fail "sibling projects shared or lost their worktree"
fi

test_case "an existing worktree from another repository is rejected"
foreign_dir="$TEST_TMP_DIR/.octo-worktree-repo-WP-FOREIGN"
git -C "$OTHER_FIXTURE" worktree add --quiet -b octo/wp-foreign "$foreign_dir" main
run_package WP-FOREIGN octo/wp-foreign
if [[ "$(cat "$TEST_TMP_DIR/WP-FOREIGN/exit-code")" == "1" &&
      -f "$TEST_TMP_DIR/WP-FOREIGN/.done" && ! -e "$foreign_dir/retained.txt" &&
      ! -e "$TEST_TMP_DIR/WP-FOREIGN/output.md" ]]; then
    test_pass
else
    test_fail "the agent ran in another repository's worktree"
fi

test_case "an existing worktree on the wrong branch is rejected"
wrong_dir="$TEST_TMP_DIR/.octo-worktree-repo-WP-WRONG"
git -C "$FIXTURE" worktree add --quiet -b octo/wrong-branch "$wrong_dir" main
run_package WP-WRONG octo/expected-branch
if [[ "$(cat "$TEST_TMP_DIR/WP-WRONG/exit-code")" == "1" &&
      -f "$TEST_TMP_DIR/WP-WRONG/.done" && ! -e "$wrong_dir/retained.txt" &&
      "$(git -C "$wrong_dir" branch --show-current)" == "octo/wrong-branch" ]]; then
    test_pass
else
    test_fail "the agent ran on or changed an unrelated branch"
fi

test_case "a retry clears old completion markers before calling the agent"
make_stub 'echo first run'
run_package WP-RETRY octo/wp-retry
MARKER_DIR="$TEST_TMP_DIR/WP-RETRY"
export MARKER_DIR
# The generated stub expands MARKER_DIR when the package invokes it.
# shellcheck disable=SC2016
make_stub '[[ ! -e "$MARKER_DIR/.done" && ! -e "$MARKER_DIR/exit-code" ]] || exit 91; echo fresh retry'
run_package WP-RETRY octo/wp-retry
if [[ "$(cat "$MARKER_DIR/exit-code")" == "0" && -f "$MARKER_DIR/.done" ]] &&
    grep -q 'fresh retry' "$MARKER_DIR/output.md"; then
    test_pass
else
    test_fail "the retry's agent observed old completion markers"
fi

test_case "a clean worktree with no commits reports its actual retention reason"
if grep -q "no commits beyond $(git -C "$FIXTURE" rev-parse main)" "$MARKER_DIR/agent.log" &&
    ! grep -q 'uncommitted work present' "$MARKER_DIR/agent.log"; then
    test_pass
else
    test_fail "the clean retry was described as containing uncommitted work"
fi

# Execute the actual cleanup after a worker commits, then hides a local change.
for index in "${!SKILL_FILES[@]}"; do
    for flag in assume-unchanged skip-worktree; do
        for change in edit delete; do
            test_case "cleanup retains $flag $change in host $index"
            wp="WP-HIDDEN-$index-$flag-$change"
            action='printf "hidden local work\n" > wp.txt'
            [[ "$change" != delete ]] || action='rm wp.txt'
            make_stub "printf 'committed\\n' > wp.txt; git add wp.txt; git commit --quiet -m 'worker commit'; git update-index --$flag wp.txt; $action"
            run_package "$wp" "octo/$wp" "$FIXTURE" main "${SKILL_FILES[$index]}"
            retained="$TEST_TMP_DIR/.octo-worktree-repo-$wp"
            if [[ -d "$retained" ]] &&
               [[ "$(git -C "$retained" rev-list --count main..HEAD)" == 1 ]] &&
               [[ "$(cat "$TEST_TMP_DIR/$wp/exit-code")" == 0 && -f "$TEST_TMP_DIR/$wp/.done" ]] &&
               { [[ "$change" == delete && ! -e "$retained/wp.txt" ]] ||
                 [[ "$change" == edit && "$(cat "$retained/wp.txt")" == 'hidden local work' ]]; }; then
                test_pass
            else
                test_fail "retained=$([[ -d $retained ]] && echo yes || echo no) code=$(cat "$TEST_TMP_DIR/$wp/exit-code" 2>/dev/null) hidden $change"
            fi
        done
    done
done

test_case "a failed Git index check retains the worktree and reports failure"
TEST_REAL_GIT="$(command -v git)"
export TEST_REAL_GIT
cat > "$STUB_BIN/git" <<'GITSTUB'
#!/usr/bin/env bash
if [[ "${3:-}" == ls-files ]]; then exit 77; fi
exec "$TEST_REAL_GIT" "$@"
GITSTUB
chmod +x "$STUB_BIN/git"
make_stub 'printf "committed\n" > wp.txt; git add wp.txt; git commit --quiet -m "worker commit"'
run_package WP-INDEXFAIL octo/wp-indexfail
if [[ -f "$TEST_TMP_DIR/.octo-worktree-repo-WP-INDEXFAIL/wp.txt" &&
      "$(cat "$TEST_TMP_DIR/WP-INDEXFAIL/exit-code")" == 1 &&
      -f "$TEST_TMP_DIR/WP-INDEXFAIL/.done" ]]; then
    test_pass
else
    test_fail "failed index inspection discarded work or reported success"
fi
rm "$STUB_BIN/git"

test_case "a failed Git status check retains committed and uncommitted work"
TEST_REAL_GIT="$(command -v git)"
export TEST_REAL_GIT
cat > "$STUB_BIN/git" <<'GITSTUB'
#!/usr/bin/env bash
if [[ "${3:-}" == "status" ]]; then exit 77; fi
exec "$TEST_REAL_GIT" "$@"
GITSTUB
chmod +x "$STUB_BIN/git"
make_stub 'printf "committed\n" > wp.txt; git add wp.txt; git commit --quiet -m "committed work"; printf "retained\n" >> wp.txt; echo done'
run_package WP-STATUSFAIL octo/wp-statusfail
failed_dir="$TEST_TMP_DIR/.octo-worktree-repo-WP-STATUSFAIL"
if [[ "$(cat "$TEST_TMP_DIR/WP-STATUSFAIL/exit-code")" == "1" &&
      -f "$TEST_TMP_DIR/WP-STATUSFAIL/.done" && -f "$failed_dir/wp.txt" ]] &&
    grep -q 'retained' "$failed_dir/wp.txt"; then
    test_pass
else
    test_fail "a failed status check was treated as a clean worktree"
fi
rm "$STUB_BIN/git"

for index in "${!SKILL_FILES[@]}"; do
    for change in branch detached ancestry repository; do
        test_case "completion retains and rejects changed $change in host $index"
        wp="WP-IDENTITY-$index-$change"
        branch="octo/$wp"
        action="git checkout --quiet -b octo/escaped-$index"
        case "$change" in
            detached) action='git checkout --quiet --detach HEAD' ;;
            ancestry) action="git checkout --quiet --orphan octo/orphan-$index; git rm -q -rf .; git commit --quiet --allow-empty -m 'unrelated root'; git branch -M '$branch'" ;;
            repository) action="rm .git; git init --quiet .; git config user.email octo@example.com; git config user.name 'Octo Test'; git fetch --quiet '$FIXTURE' main; git reset --quiet --mixed FETCH_HEAD; git add .; git commit --quiet -m 'nested replacement'; git branch -M '$branch'" ;;
        esac
        make_stub "printf 'package work\\n' > wp.txt; git add wp.txt; git commit --quiet -m 'worker commit'; $action"
        run_package "$wp" "$branch" "$FIXTURE" main "${SKILL_FILES[$index]}"
        retained="$TEST_TMP_DIR/.octo-worktree-repo-$wp"
        if [[ -f "$retained/wp.txt" || "$change" == ancestry && -d "$retained" ]] &&
           [[ "$(cat "$TEST_TMP_DIR/$wp/exit-code")" == 1 && -f "$TEST_TMP_DIR/$wp/.done" ]] &&
           [[ ! -e "$TEST_TMP_DIR/$wp/commit-count" ]] &&
           git -C "$FIXTURE" show-ref --verify --quiet "refs/heads/$branch"; then
            test_pass
        else
            test_fail "changed $change was accepted or discarded: host $index"
        fi
    done
done

test_summary
