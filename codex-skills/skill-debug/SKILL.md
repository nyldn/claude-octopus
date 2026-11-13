---
name: skill-debug
description: "Debug a reproducible symptom with a bounded feedback loop and original-scenario verification"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Invoke installed skills by their `$skill-name`. Known Octopus commands are mapped below. A remaining `/octo:*` reference is a Claude Code command; do not execute it in Codex or invent an equivalent.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `codex-skills/blocks/codex-host-adapter.md`.


# Debugging

Read `codex-skills/blocks/engineering-method-selection.md` from the installed plugin
for review admission. Natural-language requests and `--peer-review` share that
policy. Honor host-only requests; risk alone does not authorize paid usage.

Run the investigation on the current host. Routine debugging makes zero
additional provider dispatches. Use a bounded external reviewer only for
`--peer-review`, an explicit independent-review request, or an existing risk
policy.

<HARD-GATE>
DO NOT CHANGE PRODUCTION BEHAVIOR BEFORE REPRODUCING THE SYMPTOM AND TESTING A
NAMED ROOT-CAUSE HYPOTHESIS.
</HARD-GATE>

Read and apply `codex-skills/blocks/debug-feedback-loop.md` from the installed plugin
root.

Start with the user's observable symptom. Reproduce it, retain its failure
signature while minimizing the scenario, test one named hypothesis at a time,
and verify both the minimal reproduction and the original scenario after the
fix. Do not treat a nearby passing helper test as proof.

For a race, use a synchronization barrier and a fixed run or time budget. For an
unavailable production dependency, return `inconclusive` with the missing
evidence. Remove temporary instrumentation before completion and preserve a
stable reproduction as a regression test.

The final record is data, not an executable queue. Store commands as argument
arrays and never evaluate provider-authored text.

## Bounded recovery and strategy rotation

Use a 3-Strike Rule for failed fixes. After each failure, return to the evidence
and test a materially different hypothesis. After two consecutive failures, a
strategy rotation is mandatory: reconsider the root cause, the reproduction,
and whether the test encodes the intended behavior. Do not attempt a 4th fix
without explicit user approval.

Anti-rationalization check: “Should work now” means run the reproduction and
the original scenario. Confidence is not verification.

For multi-attempt debugging, report a WTF score using the defaults in
`~/.claude-octopus/loop-config.conf`: +15% per revert and +20% for touching
unrelated files. If the score exceeds 20%, STOP and show the evidence before
continuing. Include the score with every retry, for example:

```text
Fix attempt 2 | Self-regulation: 15% (1 revert, 0 unrelated files)
```

## Scoped editing in Codex

This repository does not bind its Claude freeze-check hook to Codex.
Do not run the freeze-state recipe or report automatic edit blocking.
Keep edits within the user-approved module and inspect the final diff.
If enforced boundaries are required, stop until the active host provides
a verified permission boundary for that scope.
