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
    local wp_id="$1" branch="$2" dir="$TEST_TMP_DIR/$1" root="${3:-$FIXTURE}"
    mkdir -p "$dir"
    printf 'do the thing\n' > "$dir/instructions.md"
    render_launch "${SKILL_FILES[0]}" "$root" "$wp_id" "$branch" main "$dir/launch.sh"
    ( PATH="$STUB_BIN:$PATH" HOME="$TEST_TMP_DIR/home" bash "$dir/launch.sh" ) >/dev/null 2>&1 || true
}

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
if grep -q 'no commits beyond main' "$MARKER_DIR/agent.log" &&
    ! grep -q 'uncommitted work present' "$MARKER_DIR/agent.log"; then
    test_pass
else
    test_fail "the clean retry was described as containing uncommitted work"
fi

test_summary
