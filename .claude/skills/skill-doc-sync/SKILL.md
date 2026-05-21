---
name: skill-doc-sync
paths:
  - "**/*.md"
  - "**/docs/**"
version: 1.0.0
aliases: [doc-sync, sync-docs, document-release]
description: "Post-ship doc sync across project markdown. Use when: sync docs, update docs, document changes, release notes."
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

Commit all documentation changes to the current branch and update the PR body with a doc-sync summary.

```bash
# Stage only .md files that were modified by this skill
git add *.md docs/*.md 2>/dev/null || true

# Check if there are staged changes
if git diff --cached --quiet; then
  echo "No documentation changes needed — all docs are up to date."
else
  git commit -m "docs: post-ship documentation sync

  - Auto-updated paths, counts, and version references
  - CHANGELOG entries polished for user benefit
  - Cross-doc consistency verified
  - Discoverability check passed
  "

  echo "Documentation sync committed."
fi
```

If a PR exists for the current branch, update its body to include a doc-sync section:
```bash
# Update PR body with doc-sync summary (if PR exists)
PR_NUMBER=$(gh pr view --json number -q '.number' 2>/dev/null || true)
if [[ -n "$PR_NUMBER" ]]; then
  echo "Updating PR #$PR_NUMBER with doc-sync summary..."
fi
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
