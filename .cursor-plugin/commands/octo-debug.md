---
description: "Debug a symptom through reproducible, bounded evidence"
disable-model-invocation: true
---

# Octopus debug

Load `skills/blocks/engineering-method-selection.md` from the installed plugin
and apply only the methods relevant to this task. Preserve this entry point's
execution contract and output format. Read referenced skills as instructions;
do not invoke the current command recursively or add provider calls from a seat.

Load and follow
`${HOME}/.claude-octopus/plugin/.claude/skills/skill-debug/SKILL.md` and its
literal `skills/blocks/debug-feedback-loop.md` reference.

Treat `--peer-review` as an instruction to request one bounded independent review
through existing Octopus routing. Never interpolate the flag or user text into a
shell command. Natural-language independent-review requests have the same meaning.
Otherwise run on the current host with zero additional provider dispatches unless
an existing escalation policy both requires and permits review under the effective
preferences and billing limits. Risk alone does not authorize a paid call;
honor explicit host-only requests.

Finish with the structured reproduction record. `complete` requires the original
scenario to pass and temporary instrumentation to be removed. Use `inconclusive`
when the required environment was unavailable.
