---
name: octopus-architecture
description: "Review system architecture, simplify boundaries, or compare interface designs from repository evidence"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Invoke installed skills by their `$skill-name`. Known Octopus commands are mapped below. A remaining `/octo:*` reference is a Claude Code command; do not execute it in Codex or invent an equivalent.
> Before the first helper call, derive the absolute plugin root from this loaded skill's path by finding its ancestor containing `.codex-plugin/plugin.json`. Verify that root, then bind `OCTO_ROOT` to it in each fresh shell or use the verified absolute helper path. Do not infer it from the user's project or assume exports survive tool calls. Stop and report a missing installation if the root cannot be verified.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> Claude-native tool calls in examples are prompt templates to adapt, not Codex call signatures. If a mandatory verification agent or tool is unavailable or unauthorized, report that verification did not run and stop the affected completion step. Never claim a skipped check passed.
> Attribute commits only to actual contributors; do not copy fixed model attribution trailers from examples.
> For host tool equivalents, see `codex-skills/blocks/codex-host-adapter.md`.

> Invoke this entry as `$octopus-architecture` in Codex. Code-fenced Claude command examples are reference text, not Codex shell commands.


# Architecture review

Load `codex-skills/blocks/engineering-method-selection.md` from the installed plugin
and apply only the methods relevant to this task. Preserve this entry point's
execution contract and output format. Read referenced skills as instructions;
do not invoke the current command recursively or add provider calls from a seat.

Run this method on the current host. A routine architecture review makes zero additional provider dispatches.
`--peer-review`, an explicit independent-review
request, or an existing risk policy may add one bounded external reviewer through
Octopus routing. Report incomplete independent coverage if that reviewer cannot
read the source or does not return a grounded contribution.

## Method

Read and apply `codex-skills/blocks/architecture-simplification.md` from the installed
plugin root. Pin the source revision and inspect implementation, callers, tests,
recent churn, and failure behavior before recommending a boundary.

For a single simplification, produce one evidence-backed interface. For a design
choice, produce two alternatives from the same immutable requirements:

- Draft A minimizes caller knowledge and configuration.
- Draft B makes the next demonstrated extension easier.

Label two host-generated drafts as correlated alternatives from one model. If an
independent reviewer is authorized, send it the same source and requirements but
not Draft A before its first response. Transport diversity does not prove model
family diversity. Unknown family means unknown independence.

## Completion

Return `Evidence`, `Caller contract`, `Proposed interface`, `Migration`, `Test
impact`, and `Decision`. The decision is `keep`, `simplify`, or `investigate`.
`simplify` requires exact source evidence and a concrete caller example. A design
review never authorizes an automatic refactor.

## LSP Integration

When the host exposes language-server tools, use document symbols, workspace
symbols, definitions, and references to confirm module boundaries and caller
relationships before proposing an interface. Treat LSP results as an index:
verify consequential claims against source and tests, and fall back to
repository search when the language server is unavailable or incomplete.

Adapted from `codebase-design` and `DESIGN-IT-TWICE` in `mattpocock/skills` at
commit `3cca18b368ae95cdbdebbff572ccafa662551015` under the MIT License. See
`THIRD_PARTY_NOTICES.md`.
