---
name: skill-finish-branch
disable-model-invocation: true
description: "Wrap up a branch — run tests, create PR, merge or discard — use when implementation is done"
trigger: |
  EXPLICITLY USE when user requests task completion with git operations:
  - "commit and push" or "git commit and push"
  - "complete all tasks and commit and push"
  - "proceed with all todos in sequence and push"
  - "save and commit" or "wrap this up and push"
  - "I'm done with this feature" or "ready to merge"
  - "create PR for this work"

  DO NOT activate for:
  - Individual file commits (use built-in git tools)
  - Work in progress without tests passing
  - Exploratory commits
  - Simple "git status" or "git diff" commands
execution_mode: enforced
pre_execution_contract:
  - visual_indicators_displayed
validation_gates:
  - orchestrate_sh_executed
  - output_artifact_exists
paths:
  - ".git/**"
---

# Finishing a development branch

**Your first output line MUST be:** `🐙 **CLAUDE OCTOPUS ACTIVATED** - Branch Completion`

Run the project's checks, review the committed changes, then carry out the user's chosen Git operation. Reuse an explicit choice already made in this conversation. Ask only for a missing decision.

## The process

### Prepare an explicitly authorized commit

When the user asks to commit and push uncommitted changes, prepare that commit
before Step 1. Inspect staged, unstaged and untracked changes. Record the exact
authorized paths in `COMMIT_PATHS` and the message in `COMMIT_MESSAGE`. If an
unrelated hunk shares a selected file, separate it for review or stop and report
the overlap. Do not stage every file or commit the whole index.

Run this block only for that explicit commit request, after recording the
selected paths. Restore the recorded array and message in this shell call:

```bash
: "${COMMIT_MESSAGE:?Restore the approved commit message}"
if ! declare -p COMMIT_PATHS >/dev/null 2>&1 || [[ ${#COMMIT_PATHS[@]} -eq 0 ]]; then
  echo "Restore the reviewed list of authorized commit paths." >&2
  return 1 2>/dev/null || exit 1
fi
for commit_path in "${COMMIT_PATHS[@]}"; do
  if [[ ! -e "$commit_path" && ! -L "$commit_path" ]]; then
    deletion_status=0
    git --literal-pathspecs diff --cached --quiet --diff-filter=D -- "$commit_path" || deletion_status=$?
    if [[ "$deletion_status" == 1 ]]; then
      continue  # The authorized deletion is already staged.
    elif [[ "$deletion_status" != 0 ]]; then
      echo "Could not inspect the selected deletion; no commit was created." >&2
      exit "$deletion_status"
    fi
  fi
  git --literal-pathspecs add -- "$commit_path" || exit 1
done
git --literal-pathspecs commit --only -m "$COMMIT_MESSAGE" -- "${COMMIT_PATHS[@]}" || exit 1
```

The scoped commit preserves unrelated staged work. If any unrelated changes
remain, preserve them outside the validation checkout before Step 1, or stop
with their locations recorded. Run tests and review on the resulting clean
commit before push. A failed commit stops this workflow.

### Step 1: Record the branch, base and test command

Read the project's `AGENTS.md`, delivery contract and CI configuration. Identify the intended changes and commit only their reviewed paths when the user has authorized committing. Preserve unrelated changes and stop if they prevent a clean test or review.

Resolve the base before reading the diff. Use the user's requested base when supplied. Otherwise use the remote's recorded default branch; do not silently assume `main`.

```bash
if ! FEATURE_ROOT=$(git rev-parse --show-toplevel) ||
   ! FEATURE_BRANCH=$(git branch --show-current) || [[ -z "$FEATURE_BRANCH" ]]; then
  echo "A named feature branch is required." >&2
  return 1 2>/dev/null || exit 1
fi
if [[ -z "${BASE_BRANCH:-}" ]]; then
  if ! BASE_REF=$(git symbolic-ref --quiet refs/remotes/origin/HEAD); then
    echo "Select the intended base branch before continuing." >&2
    return 1 2>/dev/null || exit 1
  fi
  BASE_BRANCH=${BASE_REF#refs/remotes/origin/}
fi
if ! git check-ref-format --branch "$BASE_BRANCH" >/dev/null ||
   [[ "$FEATURE_BRANCH" == "$BASE_BRANCH" ]]; then
  echo "Select a valid base different from the feature branch." >&2
  return 1 2>/dev/null || exit 1
fi
if git show-ref --verify --quiet "refs/remotes/origin/$BASE_BRANCH"; then
  BASE_REF="refs/remotes/origin/$BASE_BRANCH"
elif git show-ref --verify --quiet "refs/heads/$BASE_BRANCH"; then
  BASE_REF="refs/heads/$BASE_BRANCH"
else
  echo "Base branch is unavailable locally; fetch the intended base first." >&2
  return 1 2>/dev/null || exit 1
fi
if ! WORKTREE_STATUS=$(git status --porcelain) || [[ -n "$WORKTREE_STATUS" ]]; then
  echo "Preserve or commit the intended changes before testing and review." >&2
  return 1 2>/dev/null || exit 1
fi
```

Use the documented project test command. Store its arguments in a Bash array, for example `TEST_COMMAND=(make ci-quick)` or `TEST_COMMAND=(python3 -m pytest)`. Do not execute a command string with `eval`. If the project has no documented command, determine the appropriate checks from its build and CI files. If no applicable check can be identified, stop and report that tests have not run.

```bash
if [[ ${#TEST_COMMAND[@]} -eq 0 ]] || ! "${TEST_COMMAND[@]}"; then
  echo "Project tests did not pass; stop before push, merge or cleanup." >&2
  return 1 2>/dev/null || exit 1
fi
if ! REVIEWED_HEAD=$(git rev-parse HEAD); then
  return 1 2>/dev/null || exit 1
fi
```

Record `FEATURE_ROOT`, `FEATURE_BRANCH`, `BASE_BRANCH`, `BASE_REF`, `REVIEWED_HEAD`, the test arguments and the actual results in the task context. Shell variables do not survive separate tool calls. Restore these recorded values in each later shell call; do not infer the feature branch after switching to the base checkout.

### Step 2: Review the committed diff

```bash
if ! DIFF_BASE=$(git merge-base "$REVIEWED_HEAD" "$BASE_REF") ||
   ! git diff --stat "$DIFF_BASE..$REVIEWED_HEAD" ||
   ! git diff --name-only "$DIFF_BASE..$REVIEWED_HEAD"; then
  return 1 2>/dev/null || exit 1
fi
```

Read the complete `skills/skill-code-review/SKILL.md` from the installed plugin root and apply its provider-backed review contract in this conversation. Pass the recorded base and commit. Its required `scripts/orchestrate.sh` dispatch must run, and its review artifact must exist and be read before reporting success. An existing independent review may satisfy this step when its evidence covers this exact revision and scope.

Give the reviewer the complete changed-file list and access to the diff. A truncated diff or a successful dispatch alone does not prove a clean review. Read the review output, verify findings and repair confirmed problems. After a repair, repeat the relevant checks and review for the new revision.

For a public PR merge, inspect required hosted checks, independent approval and unresolved threads on the current commit. Local tests do not replace those gates.

### Step 3: Determine version files

```bash
VERSION_FILE=""
for f in VERSION version.txt package.json; do
  if [[ -f "$f" ]]; then VERSION_FILE="$f"; break; fi
done
```

### Step 4: Update the version and changelog when requested

Apply the user's requested version change. If a release is requested and the version policy leaves a material choice unresolved, ask for that choice. Use the repository's release tooling and update its required version files together.

Summarize the changes relative to the recorded base:

```bash
git log --oneline "$DIFF_BASE..HEAD"
```

Review and commit the approved version and changelog paths. Repeat the affected checks and review, then record the new `REVIEWED_HEAD`. Do not push an older commit while leaving the release edits uncommitted.

### Step 5: Select the action

If the user already asked for one of these actions, carry it out after verification. Otherwise present these choices:

1. **Create PR** (Recommended) - Push and create a Pull Request for review
2. **Merge locally** - Merge back to the selected base on this machine
3. **Keep as-is** - Preserve the branch and checkout for later
4. **Discard** - Delete the specifically confirmed work
5. **Push only** - Push the verified branch and keep its checkout

### Step 6: Execute the selected action

Restore the recorded values from Step 1 before running a recipe. Stop if the branch, commit or worktree has changed since verification. Preserve the evidence and recovery branch on every failure.

#### Option 1: Create PR

```bash
: "${FEATURE_ROOT:?Restore the recorded feature checkout}"
: "${FEATURE_BRANCH:?Restore the recorded feature branch}"
: "${BASE_BRANCH:?Restore the selected base branch}"
: "${REVIEWED_HEAD:?Restore the verified commit}"
if ! CURRENT_BRANCH=$(git -C "$FEATURE_ROOT" branch --show-current) ||
   ! CURRENT_HEAD=$(git -C "$FEATURE_ROOT" rev-parse HEAD) ||
   ! WORKTREE_STATUS=$(git -C "$FEATURE_ROOT" status --porcelain) ||
   [[ "$CURRENT_BRANCH" != "$FEATURE_BRANCH" || "$CURRENT_HEAD" != "$REVIEWED_HEAD" || -n "$WORKTREE_STATUS" ]]; then
  echo "The feature checkout changed; repeat checks and review before pushing." >&2
  return 1 2>/dev/null || exit 1
fi
if ! cd "$FEATURE_ROOT"; then
  return 1 2>/dev/null || exit 1
fi
OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}"
SAFE_GH_HELPER="$OCTO_ROOT/scripts/safe-gh-comment.sh"
if [[ ! -x "$SAFE_GH_HELPER" ]]; then
  echo "Locate the installed safe-gh-comment.sh helper before pushing for PR creation." >&2
  return 1 2>/dev/null || exit 1
fi
if ! PUSH_URLS=$(git -C "$FEATURE_ROOT" remote get-url --push --all origin); then
  echo "Cannot resolve the origin push URL; stop before pushing." >&2
  return 1 2>/dev/null || exit 1
fi
if [[ "$PUSH_URLS" == *$'\n'* ]]; then
  echo "Origin has multiple push URLs; select one repository before continuing." >&2
  return 1 2>/dev/null || exit 1
fi
if [[ "$PUSH_URLS" =~ ^https://github\.com/([A-Za-z0-9-]+)/([A-Za-z0-9_.-]+)(\.git)?$ ||
      "$PUSH_URLS" =~ ^ssh://git@github\.com/([A-Za-z0-9-]+)/([A-Za-z0-9_.-]+)(\.git)?$ ||
      "$PUSH_URLS" =~ ^git@github\.com:([A-Za-z0-9-]+)/([A-Za-z0-9_.-]+)(\.git)?$ ]]; then
  REPO_OWNER="${BASH_REMATCH[1]}"
  REPO_NAME="${BASH_REMATCH[2]%.git}"
  if [[ ! "$REPO_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
    echo "Origin push URL has an invalid GitHub repository name." >&2
    return 1 2>/dev/null || exit 1
  fi
  REPO_SLUG="${REPO_OWNER}/${REPO_NAME}"
else
  echo "Origin push URL must name one owner/repository on github.com; stop before pushing." >&2
  return 1 2>/dev/null || exit 1
fi
PR_TITLE=${PR_TITLE:?Complete the pull request title}
CHANGE_SUMMARY=${CHANGE_SUMMARY:?Describe the resulting behavior}
CHANGE_REASON=${CHANGE_REASON:?Explain why the change is needed}
VALIDATION_SUMMARY=${VALIDATION_SUMMARY:?Record the actual checks and their results}
PR_BODY=$(cat <<EOF
## Summary
${CHANGE_SUMMARY}

${CHANGE_REASON}

## Validation
${VALIDATION_SUMMARY}
EOF
)
if ! git -C "$FEATURE_ROOT" push -u origin "$FEATURE_BRANCH"; then
  echo "Push failed; stop before creating a pull request." >&2
  return 1 2>/dev/null || exit 1
fi
if ! "$SAFE_GH_HELPER" \
    --repo "$REPO_SLUG" pr-create "$PR_TITLE" "$FEATURE_BRANCH" - "$BASE_BRANCH" <<< "$PR_BODY"; then
  echo "GitHub write state is unknown; check for an existing pull request before retrying." >&2
  gh pr list --repo "$REPO_SLUG" --head "$FEATURE_BRANCH" --state all --json number,state,url || true
  return 1 2>/dev/null || exit 1
fi
```

Report the verified pushed commit and PR URL. Include only checks that actually ran. Mention manual verification only when it was performed. Keep the branch and worktree for review.

#### Option 2: Merge Locally

Inspect `git worktree list --porcelain` and select the existing checkout of the base branch as `BASE_WORKTREE`. Preserve paths containing spaces. If that branch has no checkout, use the feature checkout and let the guarded checkout below switch it to the local base. Record the selected path in the task context. Do not try to check out a branch that is already active in another worktree.

Restore the same `TEST_COMMAND` array used in Step 1. For example, a Python project must run its Python checks after the merge too.

```bash
: "${FEATURE_ROOT:?Restore the recorded feature checkout}"
: "${FEATURE_BRANCH:?Restore the recorded feature branch}"
: "${BASE_BRANCH:?Restore the selected base branch}"
: "${BASE_WORKTREE:?Select the base checkout from the worktree inventory}"
: "${REVIEWED_HEAD:?Restore the verified commit}"
if [[ ${#TEST_COMMAND[@]} -eq 0 ]]; then
  echo "Restore the project test arguments before merging." >&2
  return 1 2>/dev/null || exit 1
fi
if ! CURRENT_BRANCH=$(git -C "$FEATURE_ROOT" branch --show-current) ||
   ! CURRENT_HEAD=$(git -C "$FEATURE_ROOT" rev-parse HEAD) ||
   ! WORKTREE_STATUS=$(git -C "$FEATURE_ROOT" status --porcelain) ||
   [[ "$CURRENT_BRANCH" != "$FEATURE_BRANCH" || "$CURRENT_HEAD" != "$REVIEWED_HEAD" || -n "$WORKTREE_STATUS" ]]; then
  echo "The feature checkout changed; repeat checks and review before merging." >&2
  return 1 2>/dev/null || exit 1
fi
if ! WORKTREE_STATUS=$(git -C "$BASE_WORKTREE" status --porcelain) || [[ -n "$WORKTREE_STATUS" ]]; then
  echo "Preserve changes in the base checkout before merging." >&2
  return 1 2>/dev/null || exit 1
fi
if git -C "$BASE_WORKTREE" rev-parse --verify --quiet MERGE_HEAD >/dev/null; then
  echo "The base checkout has an existing merge; preserve it before continuing." >&2
  return 1 2>/dev/null || exit 1
fi
FEATURE_SWITCHED_TO_BASE=false
if [[ "$BASE_WORKTREE" == "$FEATURE_ROOT" ]]; then
  if ! git -C "$BASE_WORKTREE" checkout --no-overwrite-ignore "$BASE_BRANCH"; then
    echo "Checkout failed; preserve local and ignored work." >&2
    return 1 2>/dev/null || exit 1
  fi
  FEATURE_SWITCHED_TO_BASE=true
fi
if ! CURRENT_BRANCH=$(git -C "$BASE_WORKTREE" branch --show-current) || [[ "$CURRENT_BRANCH" != "$BASE_BRANCH" ]]; then
  echo "The selected checkout is not on the intended base." >&2
  return 1 2>/dev/null || exit 1
fi
REMOTE_BASE_AVAILABLE=false
if git -C "$BASE_WORKTREE" config --get remote.origin.url >/dev/null; then
  if git -C "$BASE_WORKTREE" ls-remote --exit-code --heads origin "refs/heads/$BASE_BRANCH" >/dev/null; then
    REMOTE_BASE_AVAILABLE=true
  else
    REMOTE_LOOKUP_STATUS=$?
    if [[ "$REMOTE_LOOKUP_STATUS" != 2 ]]; then
      echo "Could not check the configured origin; stop before merging." >&2
      return 1 2>/dev/null || exit 1
    fi
  fi
fi
finish_merge_failed() {
  if git -C "$BASE_WORKTREE" rev-parse --verify --quiet MERGE_HEAD >/dev/null; then
    if ! git -C "$BASE_WORKTREE" merge --abort; then
      echo "Merge abort failed; retain both checkouts for recovery." >&2
    fi
  fi
  echo "Local merge failed; preserve the branch and both checkouts for recovery." >&2
}
if [[ "$REMOTE_BASE_AVAILABLE" == true ]]; then
  if ! git -C "$BASE_WORKTREE" fetch --no-tags origin "refs/heads/$BASE_BRANCH" ||
     ! git -C "$BASE_WORKTREE" merge --ff-only --no-overwrite-ignore FETCH_HEAD; then
    finish_merge_failed
    return 1 2>/dev/null || exit 1
  fi
fi
if ! git -C "$BASE_WORKTREE" merge --no-overwrite-ignore "$REVIEWED_HEAD"; then
  finish_merge_failed
  return 1 2>/dev/null || exit 1
fi
if ! (cd "$BASE_WORKTREE" && "${TEST_COMMAND[@]}"); then
  echo "Merged-result tests failed; preserve the recovery branch and stop before cleanup." >&2
  return 1 2>/dev/null || exit 1
fi
if ! TESTED_MERGE=$(git -C "$BASE_WORKTREE" rev-parse HEAD); then
  return 1 2>/dev/null || exit 1
fi
```

Record `FEATURE_SWITCHED_TO_BASE`, including after a failed merge, and the tested merge commit. Keep a checkout that was switched to the base branch. A missing origin or remote base uses the validated local base; a failed check of a configured origin stops the run. Remote synchronization remains fast-forward-only. Both synchronization and the feature merge check ignored-file collisions through `--no-overwrite-ignore` before updating files.

Report the local merge and actual test results. Keep the feature branch until the cleanup checks below pass. A local merge does not authorize pushing the base or bypassing a repository's PR-only merge policy.

#### Option 3: Keep As-Is

Report the preserved branch, checkout, commits ahead of the selected base and checks actually performed. Do not push, delete a branch or remove a worktree.

#### Option 4: Discard

List the exact branch, checkout, commits and any local files that would be lost. Require the user's explicit confirmation for that concrete deletion. Reuse an already supplied confirmation only if it covers these same objects and state.

First preserve unrelated, untracked and useful ignored files. Select the base checkout using the worktree inventory. If switching within the feature checkout is necessary, use `git checkout --no-overwrite-ignore "$BASE_BRANCH"` and stop if it fails. If a linked checkout still holds the feature branch, apply Step 7 before deleting that branch. Never remove the primary checkout.

Delete only the confirmed local branch with a quoted branch argument. Delete a remote branch only when that separate deletion was explicitly authorized; inspect its result and report failures. Do not suppress a failed deletion or claim remote success when no deletion ran.

#### Option 5: Push only

```bash
: "${FEATURE_ROOT:?Restore the recorded feature checkout}"
: "${FEATURE_BRANCH:?Restore the recorded feature branch}"
: "${REVIEWED_HEAD:?Restore the verified commit}"
if ! CURRENT_BRANCH=$(git -C "$FEATURE_ROOT" branch --show-current) ||
   ! CURRENT_HEAD=$(git -C "$FEATURE_ROOT" rev-parse HEAD) ||
   ! WORKTREE_STATUS=$(git -C "$FEATURE_ROOT" status --porcelain); then
  echo "Cannot inspect the recorded feature checkout; stop before pushing." >&2
  return 1 2>/dev/null || exit 1
fi
if [[ -n "$WORKTREE_STATUS" ]]; then
  echo "The feature checkout has uncommitted changes. Commit the intended changes, then repeat checks and review before pushing." >&2
  return 1 2>/dev/null || exit 1
fi
if [[ "$CURRENT_BRANCH" != "$FEATURE_BRANCH" || "$CURRENT_HEAD" != "$REVIEWED_HEAD" ]]; then
  echo "The feature branch or commit changed; repeat checks and review before pushing." >&2
  return 1 2>/dev/null || exit 1
fi
if ! git -C "$FEATURE_ROOT" push -u origin "$FEATURE_BRANCH"; then
  echo "Push failed; retain the branch and checkout for recovery." >&2
  return 1 2>/dev/null || exit 1
fi
```

Report the pushed commit. Keep the branch and checkout; this action creates no PR.

### Step 7: Cleanup

**For Options 2, 4:** Remove a linked feature worktree only after verifying all of these conditions:

- `FEATURE_SWITCHED_TO_BASE` is false and the checkout is not now on `BASE_BRANCH`. If it was switched to the base, skip `git worktree remove "$FEATURE_ROOT"`, retain it and report its current role. A linked checkout can now be the base checkout too.
- The path belongs to this task and appears as a linked checkout in `git worktree list --porcelain`. Compare its Git directory with the shared common Git directory; the primary checkout must remain.
- The checkout is clean, no process or active agent session uses it, and no useful ignored files would be lost. Inspect ignored state separately from `git status --porcelain`.
- For Option 2, the recorded feature commit is an ancestor of `TESTED_MERGE`, the base still points to that tested commit, and the merged-result checks passed. On a failed check, preserve the branch and both checkouts.
- For Option 4, the explicit discard authorization covers the exact objects being deleted.

Change to a retained checkout before running `git worktree remove "$FEATURE_ROOT"`. Do not use `--force`. Stop on failure. Delete a merged feature branch with `git branch -d "$FEATURE_BRANCH"` only after it is no longer checked out anywhere and the merge checks above still hold. If the feature checkout is the primary checkout, preserve it and switch branches safely instead of removing it. Report any retained branch or worktree accurately.

**For Options 1, 3, 5:** Keep the branch and worktree intact.

## Quick Reference

| Option | Merge | Push | Keep Branch | Cleanup |
|--------|-------|------|-------------|---------|
| 1. Create PR | - | Yes | Yes | - |
| 2. Merge locally | Yes | - | Until cleanup checks pass | Conditional |
| 3. Keep as-is | - | - | Yes | - |
| 4. Discard | - | Only confirmed remote deletion | Until discard checks pass | Conditional |
| 5. Push only | - | Yes | Yes | - |

## Integration with Claude Octopus

After the develop and deliver phases, a request to create a PR selects Option 1. Verify tests and review, then execute Option 1 (Create PR). A request to merge locally selects Option 2. A request to commit and push selects Option 5 only after the intended changes have been committed and that commit has passed checks and review. If the checkout has uncommitted changes, stop and identify them; this skill does not commit them automatically. Existing authorization remains valid throughout the task.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Reviewing against an assumed main branch | Resolve the selected base before reading the diff |
| Reporting tests passed when none ran | Select and run applicable project checks, or stop |
| Publishing while release edits remain local | Commit approved paths and verify the new revision |
| Claiming manual verification from a template | Report only recorded evidence |
| Deleting recovery work after a failed merge | Stop before cleanup and preserve both checkouts |
| Cleaning up a primary checkout or a kept branch | Only consider cleanup for options 2, 4 after Step 7 |
