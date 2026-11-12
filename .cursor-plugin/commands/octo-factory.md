---
description: "[advanced] Dark Factory Mode - Spec-in, software-out autonomous pipeline"
disable-model-invocation: true
---

# Factory

## Instructions for Claude

When the user explicitly invokes factory or one of its aliases, load
`skills/skill-factory/SKILL.md` from the active plugin installation and execute
its eight-step contract. Preserve the supplied `--spec`, inline specification,
target, holdout ratio, retry limit, fast-mode choice and prior authorization.

The skill owns the `orchestrate.sh factory` pipeline and its run artifacts.
It validates the spec, reviews generated scenarios before implementation, runs
Holdout Tests, and measures Satisfaction against the selected target. Use the
current provider configuration for cost estimates and actual readiness output
for the provider banner, including Antigravity when it is unavailable.

<HARD-GATE>
Do not replace the pipeline with direct implementation. A declined run stops
before dispatch. Skipping questions does not approve cost. Do not substitute
fallback scores or select a report from another run. Use the loaded plugin root
directly when hooks are untrusted; a missing stable link does not require setup.
</HARD-GATE>
