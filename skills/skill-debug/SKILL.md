---
name: skill-debug
description: "Debug a reproducible symptom with a bounded feedback loop and original-scenario verification"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.


# Debugging

Run the investigation on the current host. Routine debugging makes zero
additional provider dispatches. Use a bounded external reviewer only for
`--peer-review`, an explicit independent-review request, or an existing risk
policy.

<HARD-GATE>
DO NOT CHANGE PRODUCTION BEHAVIOR BEFORE REPRODUCING THE SYMPTOM AND TESTING A
NAMED ROOT-CAUSE HYPOTHESIS.
</HARD-GATE>

Read and apply `skills/blocks/debug-feedback-loop.md` from the installed plugin
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

## Scoped freeze guard

When the symptom is localized to one user-approved module, resolve that module
to a physical directory before editing and activate the existing freeze guard:

```bash
freeze_dir="$(cd "<module-directory>" 2>/dev/null && pwd -P)" || exit 1
printf '%s\n' "$freeze_dir" > "/tmp/octopus-freeze-${CLAUDE_SESSION_ID:-$$}.txt"
```

Do not auto-freeze when the root cause is still unknown, the reproduction spans
modules, or the user opted out. After original-scenario verification, run
`/octo:unfreeze` or remove only this workflow's freeze state.

Adapted from `diagnosing-bugs` in `mattpocock/skills` at commit
`3cca18b368ae95cdbdebbff572ccafa662551015` under the MIT License. See
`THIRD_PARTY_NOTICES.md`.
