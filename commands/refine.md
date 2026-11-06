---
command: refine
disable-model-invocation: true
description: Improve an artifact through rubric scoring, cross-model critique, edits, and bounded rescoring
---

# Refine

Read and follow `skills/skill-refine/SKILL.md` from the installed Octopus
root. Use `${CLAUDE_PLUGIN_ROOT}` when available, otherwise
`${HOME}/.claude-octopus/plugin`. Do not invoke this command recursively.

Input: $ARGUMENTS

Examples:

```text
/octo:refine plans/migration.md until 95+, using Claude Opus and Codex
/octo:refine this proposal for a technical buyer --max-rounds 3
/octo:refine src/parser.py --rubric review-rubric.json --target 90
/octo:refine draft.md --review-only
```

These options are instructions to the host workflow, not flags for
`orchestrate.sh`: `--rubric <file>`, `--target <0..100>`,
`--max-rounds <1..10>`, `--max-minutes <positive integer>`,
`--max-calls <positive integer>`, and `--review-only`.

Defaults: target 95/100, five improvement rounds, 30 minutes, 14 external model
calls. Stop when any limit is reached or two rounds make no verified progress.
An explicit user budget overrides the defaults. Validate options before edits
or provider calls. `/octo:ladder` is an alias for this workflow.
