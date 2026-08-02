---
name: skill-work-slicing
description: "Break a plan or spec into vertical slices that each declare what blocks them — use when work is agreed but not yet cut into fileable pieces"
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.


# Work Slicing

Turn a plan, spec, or the conversation so far into a set of tickets. Each one is
a **vertical slice** — a narrow but complete path through every layer — and each
declares the tickets that block it.

This is the step between "we know what we are building" and "someone can pick up
a piece of it". It does not decide anything: if decisions are still open, run
`skill-pressure-test` first.

Adapted from `to-tickets` in
[mattpocock/skills](https://github.com/mattpocock/skills) (MIT), retargeted at
this repo's trackers.

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

### 3. File them

This repo has two trackers and they are not interchangeable:

- **`bd` (beads) is the system of record** for work. `bd create --parent=<id>`
  makes a child; `bd dep add <issue> <depends-on>` makes a blocking edge;
  `bd ready` lists what is takeable — open, unblocked, and not in progress.
- **GitHub issues** are the public surface, via `gh`. Use them when the work is
  externally visible or a contributor needs to see it.

Put the detail in the ticket body, not in the parent. The parent indexes; the
ticket holds.

### 4. When bd will not accept writes

`bd` is periodically **write-blocked** by pending Dolt schema migrations, and the
repository rule is explicit: **do not run the migration** unless you are the
single designated migrator, because migrating a second clone forks the schema
irrecoverably.

When writes are blocked, do not pretend the work was filed and do not silently
drop it. Instead:

1. Emit the **ready-to-run `bd create` and `bd dep add` commands**, complete and
   in dependency order, so they can be run unmodified once writes return.
2. Write them into the plan or a roadmap note under `docs/roadmaps/`, which is
   the practice this repo already follows.
3. Say plainly, in the output, that nothing was filed and why.

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
3. **Filed or not filed** — ids and links if filed; if not, the exact commands
   and the reason they were not run.
4. **Left unsliced** — anything in the plan too vague to cut, stated as such
   rather than forced into a ticket.

## Verification

- Every slice is demoable or verifiable alone.
- No slice is a single layer's worth of work.
- The blocking graph is acyclic and every edge is a real constraint.
- If bd was unavailable, the emitted commands run unmodified — check the parent
  ids and the dependency order.
