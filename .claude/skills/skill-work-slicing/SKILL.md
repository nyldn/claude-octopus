---
name: skill-work-slicing
disable-model-invocation: true
description: "Break a plan or spec into vertical slices that each declare what blocks them — use when work is agreed but not yet cut into fileable pieces"
codex_short_description: "Split an agreed plan into independently deliverable tasks"
---

# Work Slicing

Turn a plan, spec, or the conversation so far into a set of tickets. Each one is
a **vertical slice** — a narrow but complete path through every layer — and each
declares the tickets that block it.

This is the step between "we know what we are building" and "someone can pick up
a piece of it". It does not decide anything: if decisions are still open, run
`skill-pressure-test` first.

Before slicing, map unresolved decision records and their dependencies. Each
record names its question, required evidence, owner, resolution, and unblocked
implementation. A dependency cycle withholds ready status until it is recut.
Invalidated decisions reopen affected work rather than leaving stale completion.

Adapted from `to-tickets` in
[mattpocock/skills](https://github.com/mattpocock/skills) (MIT).

## When To Use

- A plan or spec exists and needs cutting into fileable work.
- A tracking epic is too big to claim and needs children.
- Several people or sessions will work in parallel and need boundaries.

## When Not To Use

- Decisions are still open. Slicing unresolved work produces tickets that get
  reopened. Use `skill-pressure-test`.
- The work fits one session. File one ticket, or none.
- You want parallel *execution* across agents right now, with worktrees and
  waves. That is `/octo:parallel`, which decomposes into work packages it then
  runs. This produces tracker state for humans and future sessions.

## Inputs

The plan, spec, or conversation. Optionally a parent epic id to hang the slices
under.

## Workflow

### 1. Slice vertically

Each slice cuts a narrow but complete path through every layer it touches —
schema, API, UI, tests. It is **not a horizontal** slice of one layer.

- A completed slice is demoable or verifiable on its own.
- Each is sized to fit one fresh context window.
- "Add the database columns" is horizontal and untestable alone. "Store and
  display the user's timezone, end to end" is vertical.

The first slice through a new area is the tracer bullet: thin, complete, and
proves the path exists before anything is built out along it.

### 2. Declare what blocks what

For every slice, name the slices that must close first. Only real ordering
constraints — not preference, not tidiness. Two slices that merely touch the same
file are not blocked on each other; two where one cannot be verified until the
other exists are.

Cycles mean the slicing is wrong, not that the tracker needs a workaround. Recut.

### 3. Select the project tracker

Use the user's explicit tracker choice or the current project's documented
tracker. Check the project root and its configuration with read-only commands.
When more than one tracker is configured, follow the project's rules for this
kind of work. If those rules leave the destination ambiguous, ask before filing.

- Use Beads only when the current project uses it. Verify the active Beads
  workspace from the project root before using `bd`.
- For GitHub Issues, confirm the target repository and that issues are enabled.
  Pass `--repo OWNER/REPO` to `gh issue` so a fork or CLI default cannot choose
  the destination.
- For another configured tracker, use its supported ticket and dependency
  operations. If it has no dependency links, list blockers in the ticket body.

### 4. File the slices

Put the detail in the ticket body, not in the parent. The parent indexes; the
ticket holds.

Use the tracker's atomic claim operation and read ownership back before editing a
slice. If the tracker cannot claim atomically, use one integrator and do not treat
an assignee read followed by a write as a lock. Never overwrite another owner's
claim.

### 5. Preserve work when filing is blocked

If there is no configured tracker or it cannot accept writes, save an
explicitly unfiled proposal in the project's existing plan location. Keep the
slice order and dependency edges, along with any tickets already filed. Report
the specific blocker. Provide retry commands only for the confirmed tracker
and only for slices that still need filing.

For a confirmed Beads workspace, retry commands can use `bd create --parent=<id>`
and `bd dep add <issue> <depends-on>` in dependency order. If a Dolt schema
migration blocks writes, do not run the migration. Leave it to the project's
designated migrator.

## Provider Or Data Priority

1. The plan or spec as written.
2. The repository, to check whether a slice is already partly built.
3. The user, for sizing and priority. Do not invent priorities.

## Stop Or Checkpoint Rules

- Stop and recut if any slice cannot be verified on its own.
- Stop if the blocking graph has a cycle.
- Stop before filing if more than about ten slices come out of one plan — that
  usually means the plan is really several, and filing them all buries the first.
- Confirm the slice list with the user before filing anything. Filing is visible
  to others and awkward to undo.

## Output Contract

1. **Slice list** — title, one-line scope, and what it blocks on.
2. **Order** — which slices are takeable now, and which wait.
3. **Filing status** — IDs and links for filed slices, plus the proposal path
   and reason for any unfiled slices.
4. **Left unsliced** — anything in the plan too vague to cut, stated as such
   rather than forced into a ticket.

## Verification

- Every slice is demoable or verifiable alone.
- No slice is a single layer's worth of work.
- The blocking graph is acyclic and every edge is a real constraint.
- Any retry commands target the confirmed project and preserve the parent IDs
  and dependency order.
