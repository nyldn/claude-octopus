---
name: skill-design-lineage
aliases:
  - design-lineage
  - design-docs
  - design-history
description: "Persist design documents with branch tracking, revision chains, and cross-session discovery"
trigger: |
  AUTOMATICALLY ACTIVATE when user says:
  - "save design" or "save this design"
  - "design document" or "create a design doc"
  - "design history" or "show design history"
  - "find prior designs" or "search designs"
  DO NOT activate for generic documentation or README creation.
paths:
  - "**/todo/**"
  - "**/specs/**"
  - "**/PRD*"
---

# Design Document Lineage

## Overview

Persist design documents from brainstorming and planning sessions with branch tracking, revision chains, and cross-session discoverability. Design docs are immutable after creation -- new revisions supersede prior versions rather than editing in place.

---

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

---

## Filename Format

Design documents follow a strict naming convention:

```
{user}-{branch}-design-{datetime}.md
```

Where:
- `{user}` -- the current OS username (`$USER` or `whoami`)
- `{branch}` -- the current git branch, sanitized (slashes replaced with dashes)
- `{datetime}` -- ISO 8601 compact timestamp (`YYYYMMDD-HHmmss`)

Example:
```
chris-feature-auth-refactor-design-20260321-143022.md
```

Resolution:
```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | tr '/' '-' || echo "no-branch")
DATETIME=$(date -u +"%Y%m%d-%H%M%S")
FILENAME="${USER}-${BRANCH}-design-${DATETIME}.md"
```

---

## Design Document Template

Each design document contains YAML frontmatter followed by structured sections.

### Frontmatter Metadata

```yaml
---
branch: feature/auth-refactor
user: chris
created: 2026-03-21T14:30:22Z
supersedes: chris-feature-auth-refactor-design-20260320-091500.md
---
```

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

---

## Step 1: Save Design

After a brainstorm, planning, or define workflow produces design output, save it to the standard location with metadata.

```bash
SLUG=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
DESIGNS_DIR="${HOME}/.claude-octopus/designs/${SLUG}"
mkdir -p "$DESIGNS_DIR"

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | tr '/' '-' || echo "no-branch")
DATETIME=$(date -u +"%Y%m%d-%H%M%S")
FILENAME="${USER}-${BRANCH}-design-${DATETIME}.md"
FILEPATH="${DESIGNS_DIR}/${FILENAME}"

cat > "$FILEPATH" <<EOF
---
branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "no-branch")
user: ${USER}
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
${SUPERSEDES:+supersedes: ${SUPERSEDES}}
---

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
```

Design docs are **read-only after creation**. To revise a design, create a new document with a `supersedes` reference to the prior version.

---

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

---

## Step 3: Link Revision Chain

If a prior design exists for the same branch, the new design document includes a `supersedes` field in its frontmatter pointing to the prior filename.

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | tr '/' '-' || echo "no-branch")

# Find the most recent design for this branch
PRIOR=$(ls -t "${DESIGNS_DIR}"/*-${BRANCH}-design-*.md 2>/dev/null | head -1)

if [[ -n "$PRIOR" ]]; then
  SUPERSEDES=$(basename "$PRIOR")
fi
```

This creates a linked chain of revisions:
```
v3 (supersedes: v2) -> v2 (supersedes: v1) -> v1 (no supersedes)
```

To walk the full revision history for a branch:
```bash
current="$FILENAME"
while [[ -n "$current" ]]; do
  echo "$current"
  current=$(grep '^supersedes:' "${DESIGNS_DIR}/${current}" 2>/dev/null | sed 's/supersedes: *//' || true)
done
```

---

## Step 4: Cross-Session Discovery

Downstream commands (deliver, review, develop) auto-discover design context by checking the designs directory before starting work.

```bash
SLUG=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
DESIGNS_DIR="${HOME}/.claude-octopus/designs/${SLUG}"
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | tr '/' '-' || echo "no-branch")

# Find designs for current branch
BRANCH_DESIGNS=$(ls -t "${DESIGNS_DIR}"/*-${BRANCH}-design-*.md 2>/dev/null | head -3)

if [[ -n "$BRANCH_DESIGNS" ]]; then
  echo "Design context found for branch ${BRANCH}:"
  for design in $BRANCH_DESIGNS; do
    echo "  - $(basename "$design")"
  done
  # Read the most recent design for context
  LATEST_DESIGN=$(echo "$BRANCH_DESIGNS" | head -1)
  DESIGN_CONTEXT=$(<"$LATEST_DESIGN")
fi
```

Downstream skills should check for designs before starting work:
- **flow-discover**: Check for existing designs to avoid duplicate research
- **flow-define**: Incorporate prior design constraints into requirements
- **flow-develop**: Read the recommended approach from the latest design
- **skill-brainstorm**: Surface prior designs as starting context

---

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

---

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
