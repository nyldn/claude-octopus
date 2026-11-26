---
name: skill-design-lineage
description: "Persist design documents with branch tracking, revision chains, and cross-session discovery"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Invoke installed skills by their `$skill-name`. Known Octopus commands are mapped below. A remaining `/octo:*` reference is a Claude Code command; do not execute it in Codex or invent an equivalent.
> Before the first helper call, derive the absolute plugin root from this loaded skill's path by finding its ancestor containing `.codex-plugin/plugin.json`. Verify that root, bind `OCTO_ROOT`, `CODEX_PLUGIN_ROOT`, and `CLAUDE_PLUGIN_ROOT` to the same root, and export all three in each fresh shell before launching child processes. Use the verified absolute helper path when needed. Do not infer the root from the user's project or assume exports survive tool calls. Stop and report a missing installation if the root cannot be verified.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> Claude-native tool calls in examples are prompt templates to adapt, not Codex call signatures. If a mandatory verification agent or tool is unavailable or unauthorized, report that verification did not run and stop the affected completion step. Never claim a skipped check passed.
> Attribute commits only to actual contributors; do not copy fixed model attribution trailers from examples.
> For host tool equivalents, see `codex-skills/blocks/codex-host-adapter.md`.

> Invoke this entry as `$skill-design-lineage` in Codex. Code-fenced Claude command examples are reference text, not Codex shell commands.


# Design Document Lineage

When a design introduces or changes domain terms, load
`codex-skills/blocks/domain-modeling.md`. Record each definition in the existing design
lineage artifact with its evidence source, checked time, and scope. A changed
definition invalidates dependent decisions. Link and reopen them instead of
leaving stale implementation guidance marked current.

## Overview

Persist design documents from brainstorming and planning sessions with branch tracking, revision chains, and cross-session discoverability. Design docs are immutable after creation -- new revisions supersede prior versions rather than editing in place.


## Storage Location

All design documents are stored under:

```
~/.claude-octopus/designs/<project-slug>/
```

The project slug is derived from the current git repository name or working directory basename:

```bash
SLUG=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
DESIGNS_DIR="${HOME}/.claude-octopus/designs/${SLUG}"
mkdir -p "$DESIGNS_DIR"
```


## Filename Format

Design documents follow a strict naming convention:

```
{user}-{branch}-design-{datetime}.md
```

Where:
- `{user}` -- the current OS username (`$USER` or `whoami`)
- `{branch}` -- the current git branch with slashes replaced with dashes,
  or `no-branch` if Git cannot resolve `HEAD`
- `{datetime}` -- ISO 8601 compact timestamp (`YYYYMMDD-HHmmss`)

If that filename already exists, the new design adds a unique suffix before
`.md`. Both documents remain available in the revision history.

Example:
```
chris-feature-auth-refactor-design-20260321-143022.md
```

Resolution:
```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || BRANCH=no-branch
BRANCH_SLUG=${BRANCH//\//-}
DATETIME=$(date -u +"%Y%m%d-%H%M%S")
FILENAME="${USER}-${BRANCH_SLUG}-design-${DATETIME}.md"
```


## Design Document Template

Each design document contains YAML frontmatter followed by structured sections.

### Frontmatter Metadata

    ---
    branch: feature/auth-refactor
    user: chris
    created: 2026-03-21T14:30:22Z
    supersedes: chris-feature-auth-refactor-design-20260320-091500.md
    ---

Fields:
- `branch` -- the git branch at time of creation
- `user` -- the OS username who created the document
- `created` -- ISO 8601 timestamp of creation
- `supersedes` -- filename of the prior design document this revision replaces (omitted if this is the first design for the branch)

### Document Sections

```markdown
# Design: [Title]

## Problem Statement
[What problem does this design solve? Why does it matter?]

## Constraints
[Technical, timeline, resource, or organizational constraints that bound the solution space.]

## Approaches Considered
[List each approach evaluated, with brief pros/cons for each.]

### Approach A: [Name]
- **Pros:** ...
- **Cons:** ...

### Approach B: [Name]
- **Pros:** ...
- **Cons:** ...

## Recommendation
[Which approach is recommended and why. Include the key trade-off that drove the decision.]

## Open Questions
[Unresolved questions that may affect implementation or require follow-up.]
```


## Step 1: Save Design

After a brainstorm, planning, or define workflow produces design output, save it to the standard location with metadata.

```bash
SLUG=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
DESIGNS_DIR="${HOME}/.claude-octopus/designs/${SLUG}"
mkdir -p "$DESIGNS_DIR" || exit 1

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || BRANCH=no-branch
BRANCH_SLUG=${BRANCH//\//-}
DATETIME=$(date -u +"%Y%m%d-%H%M%S")
FILENAME="${USER}-${BRANCH_SLUG}-design-${DATETIME}.md"
FRONTMATTER_DELIMITER=---

FILEPATH=$(python3 -I -c '
import os
from pathlib import Path
import shutil
import sys
import tempfile

destination = Path(sys.argv[1])
with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=".design-") as draft:
    shutil.copyfileobj(sys.stdin.buffer, draft)
    draft.flush()
    # Publish the complete document without replacing an existing revision.
    try:
        os.link(draft.name, destination)
    except FileExistsError:
        suffix = Path(draft.name).name[len(".design-"):]
        destination = destination.with_name(f"{destination.stem}-{suffix}.md")
        os.link(draft.name, destination)
print(destination)
' "$DESIGNS_DIR/$FILENAME" <<EOF
${FRONTMATTER_DELIMITER}
branch: ${BRANCH}
user: ${USER}
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
${SUPERSEDES:+supersedes: ${SUPERSEDES}}
${FRONTMATTER_DELIMITER}

# Design: [Title]

## Problem Statement
[Content from brainstorm/planning session]

## Constraints
[Identified constraints]

## Approaches Considered
[Evaluated approaches]

## Recommendation
[Selected approach and rationale]

## Open Questions
[Unresolved items]
EOF
) || exit 1
FILENAME="${FILEPATH##*/}"
printf 'Design saved to %s\n' "$FILEPATH"
```

Design docs are **read-only after creation**. To revise a design, create a new document with a `supersedes` reference to the prior version.


## Step 2: Discover Prior Designs

Before writing a new design, search for related prior designs using keyword matching.

```bash
SLUG=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
DESIGNS_DIR="${HOME}/.claude-octopus/designs/${SLUG}"

# Search for designs matching keywords (case-insensitive)
KEYWORDS="auth refactor"
grep -li "$KEYWORDS" "${DESIGNS_DIR}"/*.md 2>/dev/null | head -10
```

Constraints:
- Keyword search is limited to **10 results** to avoid overwhelming context
- Search is case-insensitive via `grep -li`
- Only searches within the current project slug's directory

When prior designs are found, present them to the user:

```
Found 2 prior designs related to "auth refactor":
  1. chris-feature-auth-refactor-design-20260320-091500.md (2026-03-20)
  2. chris-main-design-20260315-140000.md (2026-03-15)

Would you like to review any of these before creating a new design?
```


## Step 3: Link Revision Chain

If a prior design exists for the same branch, use the newest matching document
as `SUPERSEDES` before saving the next revision. Compare the original branch in
the frontmatter because different branch names can share a filename slug.
Existing designs keep their original filenames.

```bash
SLUG=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
DESIGNS_DIR="${HOME}/.claude-octopus/designs/${SLUG}"
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || BRANCH=no-branch

BRANCH_DESIGNS=$(python3 -I - "$DESIGNS_DIR" "$BRANCH" <<'PY_DESIGNS'
from pathlib import Path
import sys

root = Path(sys.argv[1])
branch_field = f"branch: {sys.argv[2]}"
matches = []
for design in root.glob("*-design-*.md"):
    try:
        if not design.is_file() or "\n" in design.name:
            continue
        with design.open(encoding="utf-8") as document:
            if document.readline().rstrip("\n") != "---":
                continue
            branches = []
            for line in document:
                line = line.rstrip("\n")
                if line == "---":
                    if branches == [branch_field]:
                        matches.append((design.stat().st_mtime_ns, design.name))
                    break
                if line.startswith("branch:"):
                    branches.append(line)
    except (OSError, UnicodeError):
        continue

for _, name in sorted(matches, reverse=True)[:3]:
    print(name)
PY_DESIGNS
) || exit 1
SUPERSEDES=${BRANCH_DESIGNS%%$'\n'*}
```

This creates a linked chain of revisions:
```
v3 (supersedes: v2) -> v2 (supersedes: v1) -> v1 (no supersedes)
```

To walk the full revision history, start with the design just saved. In a fresh
shell, set `FILENAME` to the basename of the printed path and `DESIGNS_DIR` to
the design directory from Step 1.

```bash
current="$FILENAME"
while [[ -n "$current" ]]; do
  echo "$current"
  current=$(grep '^supersedes:' "${DESIGNS_DIR}/${current}" 2>/dev/null | sed 's/supersedes: *//' || true)
done
```


## Step 4: Cross-Session Discovery

Downstream commands (deliver, review, develop) can auto-discover design context.
Run the lookup block from Step 3 in the same shell before running this block.
It returns up to three filenames for the current branch, newest first.

```bash
if [[ -n "$BRANCH_DESIGNS" ]]; then
  echo "Design context found for branch ${BRANCH}:"
  while IFS= read -r design; do
    printf '  - %s\n' "$design"
  done <<< "$BRANCH_DESIGNS"
  DESIGN_CONTEXT=$(<"${DESIGNS_DIR}/${SUPERSEDES}")
fi
```

Downstream skills should check for designs before starting work:
- **flow-discover**: Check for existing designs to avoid duplicate research
- **flow-define**: Incorporate prior design constraints into requirements
- **flow-develop**: Read the recommended approach from the latest design
- **skill-brainstorm**: Surface prior designs as starting context


## Caps and Limits

- **Max 50 design docs per project slug** -- when the limit is reached, warn the user and suggest archiving old designs
- **Keyword search limited to 10 results** -- prevents context overload
- **Design doc template max 500 lines** -- encourages concise, actionable designs

Cap enforcement:
```bash
DOC_COUNT=$(ls "${DESIGNS_DIR}"/*.md 2>/dev/null | wc -l | tr -d ' ')
if [[ "$DOC_COUNT" -ge 50 ]]; then
  echo "Warning: ${DOC_COUNT} design docs in ${DESIGNS_DIR}. Consider archiving old designs."
fi
```


## Integration Notes

### Works With
- **flow-discover** -- Design docs capture research findings for persistence
- **flow-define** -- Design constraints feed into requirement definitions
- **skill-brainstorm** -- Brainstorm output can be saved as a design document
- **skill-thought-partner** -- Exploration sessions can produce design artifacts

### Downstream Discovery
- **flow-develop** -- Reads latest design before implementation
- **flow-deliver** -- References design decisions during review
- **skill-code-review** -- Checks implementation against design recommendations

### Immutability Rule
Design docs are **read-only after creation**. To update a design:
1. Create a new design document
2. Set `supersedes` to the prior document's filename
3. The prior document remains unchanged for audit trail

This ensures a complete history of design evolution is always available.
