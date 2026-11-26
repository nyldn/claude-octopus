---
name: skill-doc-sync
disable-model-invocation: true
paths:
  - "**/*.md"
  - "**/docs/**"
version: 1.0.0
aliases: [doc-sync, sync-docs, document-release]
description: "Post-ship doc sync across project markdown. Use when: sync docs, update docs, document changes, release notes."
codex_short_description: "Update project documentation to match completed changes"
---

# Post-Ship Documentation Synchronization

Automated documentation synchronization for the Deliver phase. After code is committed and a PR is created, this skill reads all `.md` files in the project, cross-references the diff, auto-updates factual content, checks cross-doc consistency, and updates the PR body.

---

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
# Get the diff stat to identify changed files
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
  DIFF_STAT=$(git diff --stat HEAD~1)
  DIFF_FULL=$(git diff HEAD~1)
else
  BASE_BRANCH=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null)
  DIFF_STAT=$(git diff --stat "$BASE_BRANCH"..HEAD)
  DIFF_FULL=$(git diff "$BASE_BRANCH"..HEAD)
fi

echo "$DIFF_STAT"
```

For each doc file, check whether any paths, function names, counts, or version numbers mentioned in the doc were affected by the diff.

---

## Step 3: Auto-Update Factual Corrections

Fix paths, counts, table entries, and version numbers automatically. These are mechanical changes that do not alter meaning.

Before editing any doc in Steps 3–8, inspect its staged and unstaged changes.
Skip files with existing edits and tell the user which files were skipped.
Keep a list of the exact paths you change for the commit in Step 9.

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
- Mark completed items: scan TODO/FIXME/HACK comments that were removed in the diff and mark corresponding items as done
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
  echo "Resolved TODOs (removed in diff):"
  echo "$REMOVED_TODOS"
fi
```

---

## Step 9: Commit Doc Changes

Commit the files recorded during this run. Add each repository-relative file
path as a separately quoted argument after `set --`. Leave the list empty if
this run made no edits.

```bash
set --
if [ "$#" -eq 0 ]; then
  printf '%s\n' 'No documentation changes needed.'
else
  git --literal-pathspecs add -- "$@" || exit 1
  git --literal-pathspecs commit --only -m "docs: post-ship documentation sync" -- "$@" || exit 1
  printf '%s\n' 'Documentation sync committed.'
fi
```

If staging or committing fails, report the failure and preserve the edits for
recovery. Continue to the PR summary only after a successful commit.

If the current branch has an open PR, write a concise Markdown summary of this
run to a private scratch file and set `DOC_SYNC_SUMMARY_FILE` to its path.
Include the documentation changed and the checks run. Run this block from the
same branch, with the installed Octopus root available in `OCTO_ROOT` or the
host's plugin root variable. Skip this step for branches without an open PR.

```bash
(
  scratch=$(mktemp -d "${TMPDIR:-/tmp}/octopus-doc-sync.XXXXXX") || exit 1
  trap 'rm -rf -- "$scratch"' EXIT
  gh pr view --json url,state,body > "$scratch/pr.json" || exit 1
  state=$(jq -er '.state' "$scratch/pr.json") || exit 1
  [[ "$state" == OPEN ]] || exit 0
  pr_url=$(jq -er '.url | strings | select(length > 0)' "$scratch/pr.json") || exit 1

  python3 -I - "$scratch/pr.json" "${DOC_SYNC_SUMMARY_FILE:?}" > "$scratch/body.md" <<'PY_DOC_SYNC' || exit 1
import json
from pathlib import Path
import re
import sys

start = "<!-- octopus-doc-sync:start -->"
end = "<!-- octopus-doc-sync:end -->"
body = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["body"] or ""
summary = Path(sys.argv[2]).read_text(encoding="utf-8").strip()
if not summary or start in summary or end in summary:
    sys.exit("Doc Sync needs a nonempty summary without section markers.")

section = f"{start}\n## Documentation sync\n\n{summary}\n{end}"
markers = list(re.finditer(r"(?m)^<!-- octopus-doc-sync:(start|end) -->\r?$", body))
if not markers:
    separator = "\n" if body.endswith("\n") else "\n\n" if body else ""
    updated = f"{body}{separator}{section}\n"
elif [marker.group(1) for marker in markers] == ["start", "end"]:
    begin, finish = markers
    updated = body[:begin.start()] + section + body[finish.end():]
else:
    sys.exit("Doc Sync section markers in the PR body are incomplete or duplicated.")

if updated != body:
    sys.stdout.buffer.write(updated.encode("utf-8"))
PY_DOC_SYNC
  [[ -s "$scratch/body.md" ]] || exit 0
  gh pr view "$pr_url" --json url,state,body > "$scratch/current.json" || exit 1
  if ! cmp -s "$scratch/pr.json" "$scratch/current.json"; then
    printf '%s\n' 'The PR changed while preparing the Doc Sync summary. Rerun this step.' >&2
    exit 1
  fi
  pr_path='^https://([A-Za-z0-9.-]+)/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/([1-9][0-9]*)$'
  if ! [[ "$pr_url" =~ $pr_path ]]; then
    printf '%s\n' 'Could not identify the GitHub host, repository, and PR number.' >&2
    exit 1
  fi
  pr_host=${BASH_REMATCH[1]}
  pr_repo=${BASH_REMATCH[2]}
  pr_number=${BASH_REMATCH[3]}
  plugin_root="${OCTO_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-}}}"
  if [[ "$plugin_root" != /* || ! -x "$plugin_root/scripts/safe-gh-comment.sh" ]]; then
    printf '%s\n' 'Could not find the installed Octopus GitHub safety helper.' >&2
    exit 1
  fi
  GH_HOST="$pr_host" "$plugin_root/scripts/safe-gh-comment.sh" --repo "$pr_repo" \
    pr-edit "$pr_number" "$scratch/body.md" >/dev/null || exit 1
  printf 'Updated PR documentation summary.\n'
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
