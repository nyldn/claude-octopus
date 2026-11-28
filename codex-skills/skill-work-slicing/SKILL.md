---
name: skill-work-slicing
description: "Break a plan or spec into vertical slices that each declare what blocks them — use when work is agreed but not yet cut into fileable pieces"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Invoke installed skills by their `$skill-name`. Known Octopus commands are mapped below. A remaining `/octo:*` reference is a Claude Code command; do not execute it in Codex or invent an equivalent.
> Before the first helper call, derive the absolute plugin root from this loaded skill's path by finding its ancestor containing `.codex-plugin/plugin.json`. Verify that root, bind `OCTO_ROOT`, `CODEX_PLUGIN_ROOT`, and `CLAUDE_PLUGIN_ROOT` to the same root, and export all three in each fresh shell before launching child processes. Use the verified absolute helper path when needed. Do not infer the root from the user's project or assume exports survive tool calls. Stop and report a missing installation if the root cannot be verified.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> Claude-native tool calls in examples are prompt templates to adapt, not Codex call signatures. If a mandatory verification agent or tool is unavailable or unauthorized, report that verification did not run and stop the affected completion step. Never claim a skipped check passed.
> Attribute commits only to actual contributors; do not copy fixed model attribution trailers from examples.
> For host tool equivalents, see `codex-skills/blocks/codex-host-adapter.md`.

> Invoke this entry as `$skill-work-slicing` in Codex. Code-fenced Claude command examples are reference text, not Codex shell commands.


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
  waves. That is `$flow-parallel`, which decomposes into work packages it then
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

- Use Beads if the project uses it or the user selects it. Confirm the exact
  workspace the command will target before using `bd` for this project.
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

If no tracker was confirmed, or filing or linking fails in the confirmed
tracker, preserve an explicitly unfiled proposal for the remaining work. Use
the project's existing plan location. If there is no plan location, include the
proposal in your response.

Read back filed tickets and their dependencies before planning a retry. Keep
the slice order, existing ticket IDs, and missing dependency edges. Report the
specific blocker. Provide retry steps only for the confirmed tracker and only
for missing tickets or links. Check the completed links before reporting
dependent slices as ready.

For a missing link, use the confirmed tracker's dependency operation on the
existing tickets. If the operation needs to happen in the tracker's UI,
provide manual recovery steps with both ticket IDs and the direction of the
link.

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
3. **Filing status** — IDs and links for filed slices, plus the remaining
   proposal or its path and the reason filing stopped.
4. **Left unsliced** — anything in the plan too vague to cut, stated as such
   rather than forced into a ticket.

## Verification

- Every slice is demoable or verifiable alone.
- No slice is a single layer's worth of work.
- The blocking graph is acyclic and every edge is a real constraint.
- Any retry commands target the confirmed project and preserve the parent IDs
  and dependency order.
