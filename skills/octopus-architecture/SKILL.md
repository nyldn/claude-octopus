---
name: octopus-architecture
description: "Review system architecture, simplify boundaries, or compare interface designs from repository evidence"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.


# Architecture review

Run this method on the current host. A routine architecture review makes zero additional provider dispatches.
`--peer-review`, an explicit independent-review
request, or an existing risk policy may add one bounded external reviewer through
Octopus routing. Report incomplete independent coverage if that reviewer cannot
read the source or does not return a grounded contribution.

## Method

Read and apply `skills/blocks/architecture-simplification.md` from the installed
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
