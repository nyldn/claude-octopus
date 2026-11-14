---
name: skill-prototype
disable-model-invocation: true
description: "Prototype one risky assumption within a fixed budget, then keep or discard the result"
---

# Bounded prototype

Use a prototype to answer one named question, not to start implementation by a
different name.

## Contract

Agree on the question, hypothesis, deadline, artifact path, and success signal
before writing. Record the source revision. Store artifacts through
`scripts/plan-storage.sh`, outside the installed plugin cache.

Native read-only plan mode permits a proposal only. Wait for an explicit
execution handoff before creating files. Choosing prototype mode does not
authorize deployment, provider calls, browser login, repository rewrites, or
new permissions.

Stop at the deadline. Return observations, a `keep`, `discard`, or `inconclusive`
verdict, and the disposition of each artifact. Automatic cleanup may remove
only artifacts created by this run after ownership checks. Retain anything the
user changed.

The completion record contains `question`, `hypothesis`, `deadline`,
`artifact_path`, `source_revision`, `observations`, `verdict`, and
`disposition`.

Adapted from `prototype` in `mattpocock/skills` at commit
`3cca18b368ae95cdbdebbff572ccafa662551015` under the MIT License. See
`THIRD_PARTY_NOTICES.md`.
