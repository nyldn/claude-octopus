---
name: skill-doc-sync
disable-model-invocation: true
paths:
  - "**/*.md"
  - "**/docs/**"
version: 1.0.0
description: "Post-ship doc sync across project markdown. Use when: sync docs, update docs, document changes, release notes."
---

# Post-Ship Documentation Synchronization

Automated documentation synchronization for the Deliver phase. After code is committed and a PR is created, this skill reads all `.md` files in the project, cross-references the diff, auto-updates factual content, checks cross-doc consistency, and updates the PR body.

---

Invoke the registered skill explicitly: `/octo:skill-doc-sync` in Claude Code or
`$skill-doc-sync` in Codex. The former frontmatter aliases did not register commands.

## Caps

- **Max 30 doc files scanned** — skip files beyond the cap, warn the user
- **Never clobber CHANGELOG** — append only, never delete existing entries
- **Ask user before changing narrative/philosophy sections** — risky changes require confirmation

---

## Step 1: Discover Docs

Find all `.md` files in the project root (max depth 2), skipping `node_modules/` and `.git/`.

```bash
# Discover all markdown files (max depth 2, skip noise directories)
DOC_FILES=$(find . -maxdepth 2 -name '*.md' \
  -not -path './node_modules/*' \
  -not -path './.git/*' \
  -not -path './vendor/*' \
  -not -path './.claude/*' \
  2>/dev/null | head -30)

DOC_COUNT=$(echo "$DOC_FILES" | wc -l | tr -d ' ')
echo "Found $DOC_COUNT doc files to scan (cap: 30)"

if [[ "$DOC_COUNT" -ge 30 ]]; then
  echo "WARNING: Doc file cap reached (30). Some files may be skipped."
fi
```

Read each discovered doc file so you have their current content in context.

---

## Step 2: Cross-Reference Diff

Run `git diff --stat HEAD~1` (or diff against the base branch if on a feature branch) to identify which files changed and what content may now be stale in each doc.

```bash
DOC_SYNC_ROOT="$(git rev-parse --show-toplevel)" || exit 1
cd -- "$DOC_SYNC_ROOT" || exit 1
DOC_SYNC_BRANCH="$(git symbolic-ref --quiet --short HEAD)" || {
  echo "Select the intended documentation branch before proceeding." >&2; exit 1;
}
if [[ -z "${DOC_SYNC_BASE_REF:-}" ]]; then
  DOC_SYNC_BASE_REF="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD)" || {
    echo "Set DOC_SYNC_BASE_REF to the verified base; origin/HEAD is unavailable." >&2; exit 1;
  }
fi
git rev-parse --verify "${DOC_SYNC_BASE_REF}^{commit}" >/dev/null || exit 1
if [[ "$DOC_SYNC_BRANCH" == "${DOC_SYNC_BASE_REF#origin/}" ]]; then
  DOC_SYNC_DIFF_BASE="$(git rev-parse --verify HEAD^)" || exit 1
else
  DOC_SYNC_DIFF_BASE="$(git merge-base HEAD "$DOC_SYNC_BASE_REF")" || exit 1
fi
DIFF_STAT="$(git diff --stat "$DOC_SYNC_DIFF_BASE" HEAD)" || exit 1
DIFF_FULL="$(git diff "$DOC_SYNC_DIFF_BASE" HEAD)" || exit 1
printf '%s\n' "$DIFF_STAT"
```

For each doc file, check whether any paths, function names, counts, or version numbers mentioned in the doc were affected by the diff.

---

## Step 3: Auto-Update Factual Corrections

Before editing, check the repository's instructions and generator ownership.
Run its documented generators for generated counts, versions and release facts.
Do not hand-edit generated output. In Claude Octopus, `scripts/sync-readme.py`
owns README facts and `make sync` updates the generated adapters. Review the
resulting diff and use `make sync-check` to verify it. If a generator would touch
files outside this run's recorded scope, inspect and expand the scope before
running it; do not commit those files implicitly.

Record the exact Markdown paths this run will edit in the Bash array
`DOC_SYNC_PATHS`, for example `DOC_SYNC_PATHS=(README.md "docs/User guide.md")`.
Use the actual selected paths, including any generated Markdown output. Run this
block before the first edit or generator. Skip files that already contain user
changes; handle an overlapping edit only under separate explicit authorization.

```bash
if ! declare -p DOC_SYNC_PATHS >/dev/null 2>&1 || [[ ${#DOC_SYNC_PATHS[@]} == 0 ]]; then
  echo "Record the exact documentation paths before editing." >&2; exit 1
fi
DOC_SYNC_HEAD="$(git rev-parse HEAD)" || exit 1
python3 - "${DOC_SYNC_PATHS[@]}" <<'PY_PATHS'
from pathlib import Path
import sys
root = Path.cwd().resolve()
for raw in sys.argv[1:]:
    path = Path(raw)
    if path.is_absolute() or '..' in path.parts or '.git' in path.parts or path.suffix != '.md':
        raise SystemExit('Documentation scope must contain repository-relative Markdown paths')
    target = root / path
    if target.is_symlink():
        raise SystemExit('Do not edit a symlink through doc-sync')
    try:
        target.resolve().relative_to(root)
    except ValueError:
        raise SystemExit('Documentation path escapes the repository')
PY_PATHS
[[ "$?" == 0 ]] || exit 1
for doc in "${DOC_SYNC_PATHS[@]}"; do
  DOC_SYNC_EXISTING="$(git --literal-pathspecs status --porcelain --untracked-files=all -- "$doc")" || exit 1
  [[ -z "$DOC_SYNC_EXISTING" ]] || {
    printf 'Preserve pre-existing changes in %s; exclude this path before editing.\n' "$doc" >&2; exit 1;
  }
  if git check-ignore -q -- "$doc"; then
    printf 'Documentation path is ignored: %s\n' "$doc" >&2; exit 1
  else
    DOC_SYNC_IGNORE_STATUS=$?
    [[ "$DOC_SYNC_IGNORE_STATUS" == 1 ]] || exit "$DOC_SYNC_IGNORE_STATUS"
  fi
done
```

Keep `DOC_SYNC_ROOT`, `DOC_SYNC_BRANCH`, `DOC_SYNC_HEAD`, `DOC_SYNC_BASE_REF` and
`DOC_SYNC_PATHS` in the task context. Restore the exact values in later shell
calls. Do not reconstruct the owned paths from all currently modified files.

Fix factual paths, counts, table entries and versions within that scope.

**Auto-update targets:**
- File paths that were renamed or moved in the diff
- Numeric counts (e.g., "42 tests" when the number changed)
- Version strings (e.g., `v9.5.0` when `package.json` bumped)
- Table entries referencing renamed or removed items
- Import/require paths that changed

**WHY:** Stale factual references erode trust in documentation. A user who sees a wrong path or count will doubt everything else in the doc.

---

## Step 4: Risky Change Detection

Flag narrative, philosophy, or security-related doc sections for user confirmation. Do NOT auto-edit these.

**Risky categories (require user approval):**
- Sections with headings containing: "Philosophy", "Principles", "Vision", "Mission", "Security", "Threat Model", "Architecture Decision"
- Paragraphs that express opinion, strategy, or rationale (not just facts)
- Content under `## Why` or `## Rationale` headings
- Any changes to `SECURITY.md` or `CONTRIBUTING.md` beyond version bumps

**WHY:** Narrative and philosophy sections reflect human judgment. Silently rewriting them risks misrepresenting the project's intent.

When risky changes are detected, present them to the user:
```
The following doc sections may need updating but contain narrative/philosophy content.
I will NOT auto-edit these. Please review and confirm each change:

1. README.md ## Philosophy — mentions "single-binary deployment" but diff adds Docker support
2. SECURITY.md ## Threat Model — new auth endpoint not documented

Approve changes? (list numbers to approve, or "skip all")
```

---

## Step 5: CHANGELOG Voice Polish

Apply the "sell test" to every CHANGELOG entry: **"Would a user reading this bullet think 'oh nice, I want to try that'?"**

**Rules:**
- Lead with the user benefit, not the implementation detail
- Use active voice ("Add X" not "X was added")
- Keep bullets under 120 characters
- Never delete existing CHANGELOG entries (append only)
- Group by: Added, Changed, Fixed, Removed (Keep a Changelog format)

**Example transformations:**
```
BAD:  "Refactored spawn_agent to use parameter expansion instead of basename"
GOOD: "Speed up agent spawning by eliminating 750 subshell forks (92% reduction)"

BAD:  "Added SUPPORTS_MCP_ELICITATION flag"
GOOD: "Support MCP elicitation for richer interactive prompts (CC v2.1.76+)"
```

**WHY:** The CHANGELOG is marketing copy for developers. Every bullet should make someone want to upgrade.

---

## Step 6: Cross-Doc Consistency

Check that key values are aligned across all documentation files.

**Consistency checks:**
- Version numbers match across `README.md`, `CLAUDE.md`, `package.json`, `CHANGELOG.md`, and any other files referencing the current version
- Feature lists in README match what is actually implemented (cross-reference with command/skill directories)
- Badge URLs and shield.io references are up to date
- Links between docs are not broken (relative path references)
- Command counts and skill counts match actual directory listings

```bash
# Example: check version consistency
PKG_VERSION=$(grep '"version"' package.json | head -1 | sed 's/.*"version": *"//' | sed 's/".*//')
echo "package.json version: $PKG_VERSION"

# Check README mentions this version
if ! grep -q "$PKG_VERSION" README.md 2>/dev/null; then
  echo "WARNING: README.md does not mention version $PKG_VERSION"
fi

# Check CHANGELOG has an entry for this version
if ! grep -q "$PKG_VERSION" CHANGELOG.md 2>/dev/null; then
  echo "WARNING: CHANGELOG.md has no entry for version $PKG_VERSION"
fi
```

---

## Step 7: Discoverability Check

Ensure every documentation file is reachable from `README.md` or `CLAUDE.md`. Orphaned docs are invisible docs.

**Check:**
- Every `.md` file in the project should be linked from either `README.md` or `CLAUDE.md` (directly or transitively through another linked doc)
- Flag orphaned docs that have no inbound links
- Suggest where to add links for orphaned docs

**WHY:** Documentation that cannot be found does not exist from the user's perspective. Every doc must be one or two clicks from the entry points.

---

## Step 8: TODOS.md Update

Update the project's task tracking based on the diff.

**Actions:**
- Treat removed TODO/FIXME/HACK comments as completion candidates. Inspect the implementation and its acceptance evidence before marking a corresponding item done. A moved or deleted comment alone does not prove completion.
- Flag new deferred work: scan TODO/FIXME/HACK comments that were added in the diff and create new tracking entries
- Update completion percentages if the project uses progress tracking

```bash
# Find new TODOs added in the diff
NEW_TODOS=$(echo "$DIFF_FULL" | grep '^+' | grep -iE 'TODO|FIXME|HACK' | grep -v '^+++' || true)
if [[ -n "$NEW_TODOS" ]]; then
  echo "New TODOs found in diff:"
  echo "$NEW_TODOS"
fi

# Find TODOs removed in the diff
REMOVED_TODOS=$(echo "$DIFF_FULL" | grep '^-' | grep -iE 'TODO|FIXME|HACK' | grep -v '^---' || true)
if [[ -n "$REMOVED_TODOS" ]]; then
  echo "Removed TODOs requiring completion verification:"
  echo "$REMOVED_TODOS"
fi
```

---

## Step 9: Commit Doc Changes

Commit only the reviewed changes in the recorded paths. Preserve unrelated user
edits and staged entries. If the branch, HEAD or ownership record changed,
stop and re-establish the scope before committing. A failed commit leaves the
changes available for inspection; do not reset or discard them.

```bash
: "${DOC_SYNC_ROOT:?Restore the recorded repository}"
: "${DOC_SYNC_HEAD:?Restore the pre-edit commit}"
: "${DOC_SYNC_BRANCH:?Restore the recorded branch}"
if ! declare -p DOC_SYNC_PATHS >/dev/null 2>&1 || [[ ${#DOC_SYNC_PATHS[@]} == 0 ]]; then
  echo "Restore the recorded documentation path array." >&2; exit 1
fi
cd -- "$DOC_SYNC_ROOT" || exit 1
[[ "$(git rev-parse HEAD)" == "$DOC_SYNC_HEAD" &&
   "$(git symbolic-ref --quiet --short HEAD)" == "$DOC_SYNC_BRANCH" ]] || {
  echo "The checkout changed during doc-sync; inspect it before committing." >&2; exit 1;
}
if git --literal-pathspecs diff --quiet HEAD -- "${DOC_SYNC_PATHS[@]}"; then
  echo "No changes in the recorded documentation paths."
else
  DOC_SYNC_DIFF_STATUS=$?
  [[ "$DOC_SYNC_DIFF_STATUS" == 1 ]] || exit "$DOC_SYNC_DIFF_STATUS"
  git --literal-pathspecs diff HEAD -- "${DOC_SYNC_PATHS[@]}" || exit 1
  git --literal-pathspecs add --all -- "${DOC_SYNC_PATHS[@]}" || exit 1
  git --literal-pathspecs commit --only -m "docs: synchronize reviewed documentation" -- "${DOC_SYNC_PATHS[@]}" || exit 1
fi
```

Write a summary of the actual changes and checks to a private file, review it,
and set `DOC_SYNC_SUMMARY_FILE` to its absolute path. The PR body must distinguish
local changes from pushed changes and pending CI. Use this block only when the
user has authorized updating the PR. It preserves the existing body outside its
managed doc-sync section and uses the outbound credential gate. An API failure
stops the update rather than reporting that no PR exists.

```bash
(
  : "${DOC_SYNC_ROOT:?Restore the recorded repository}"
  : "${DOC_SYNC_BRANCH:?Restore the recorded branch}"
  : "${DOC_SYNC_SUMMARY_FILE:?Set the reviewed summary file}"
  cd -- "$DOC_SYNC_ROOT" || exit 1
  [[ "$(git symbolic-ref --quiet --short HEAD)" == "$DOC_SYNC_BRANCH" ]] || {
    echo "The recorded PR branch is no longer checked out; stop before updating its body." >&2; exit 1;
  }
  DOC_SYNC_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${DROID_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}}"
  SAFE_POST="$DOC_SYNC_PLUGIN_ROOT/scripts/safe-gh-comment.sh"
  [[ -x "$SAFE_POST" && -f "$DOC_SYNC_SUMMARY_FILE" ]] || exit 1
  DOC_SYNC_REPO="${DOC_SYNC_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}" || exit 1
  [[ -n "$DOC_SYNC_REPO" ]] || exit 1
  DOC_SYNC_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/octo-doc-sync.XXXXXX")" || exit 1
  trap 'rm -rf -- "$DOC_SYNC_TEMP"' EXIT
  gh pr list --repo "$DOC_SYNC_REPO" --state open --head "$DOC_SYNC_BRANCH" --json number,body > "$DOC_SYNC_TEMP/prs.json" || exit 1
  PR_NUMBER="$(python3 - "$DOC_SYNC_TEMP/prs.json" "$DOC_SYNC_SUMMARY_FILE" "$DOC_SYNC_TEMP/body.md" <<'PY_BODY'
import json
from pathlib import Path
import sys
prs = json.loads(Path(sys.argv[1]).read_text())
if not prs:
    print('none')
    raise SystemExit(0)
if len(prs) != 1 or type(prs[0].get('number')) is not int or prs[0]['number'] < 1:
    raise SystemExit('Expected exactly one PR for the recorded branch')
body = prs[0].get('body') or ''
start, end = '<!-- octopus-doc-sync:start -->', '<!-- octopus-doc-sync:end -->'
section = start + '\n## Documentation sync\n\n' + Path(sys.argv[2]).read_text().strip() + '\n' + end
if start in body or end in body:
    if body.count(start) != 1 or body.count(end) != 1 or body.index(start) > body.index(end):
        raise SystemExit('Ambiguous doc-sync section; inspect the PR body')
    body = body[:body.index(start)] + section + body[body.index(end) + len(end):]
else:
    body = body + ('\n\n' if body else '') + section + '\n'
Path(sys.argv[3]).write_text(body)
print(prs[0]['number'])
PY_BODY
  )" || exit 1
  if [[ "$PR_NUMBER" == none ]]; then
    echo "No open PR for the recorded branch; keep the summary local."
  else
    "$SAFE_POST" --repo "$DOC_SYNC_REPO" pr-edit "$PR_NUMBER" "$DOC_SYNC_TEMP/body.md" || exit 1
    printf 'Updated documentation summary on PR #%s.\n' "$PR_NUMBER"
  fi
)
```

---

## Integration

This skill is designed to work as a sub-step of `flow-deliver`. After validation and review are complete, invoke doc-sync to ensure documentation stays current with the shipped code.

**Invocation from flow-deliver:**
```
After PR creation and CI passes:
1. Run doc-sync to update documentation
2. Push doc changes to the PR branch
3. Re-run CI if doc changes affect tests
```

**Standalone invocation:**
```
User: "sync docs"
User: "update documentation after merge"
User: "document changes from last release"
```
