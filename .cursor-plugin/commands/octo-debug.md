---
description: "Debug a symptom through reproducible, bounded evidence"
disable-model-invocation: true
---

# Octopus debug

Load and follow
`${HOME}/.claude-octopus/plugin/.claude/skills/skill-debug/SKILL.md` and its
literal `skills/blocks/debug-feedback-loop.md` reference.

Treat `--peer-review` as an instruction to request one bounded independent review
through existing Octopus routing. Never interpolate the flag or user text into a
shell command. Otherwise run on the current host with zero additional provider
dispatches.

Finish with the structured reproduction record. `complete` requires the original
scenario to pass and temporary instrumentation to be removed. Use `inconclusive`
when the required environment was unavailable.
