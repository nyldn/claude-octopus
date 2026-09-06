---
name: skill-tdd
description: "Build a behavior change with observed red, minimal green, and measured test consolidation"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.


# Test-driven development

Run the red, green, and refactor cycle on the current host. Routine TDD makes
zero additional provider dispatches. Use one external reviewer only when the
user passes `--peer-review`, explicitly requests independent review, or an
existing risk policy requires it. Explicit debate, council, and multi-model
commands retain their own execution contracts.

<HARD-GATE>
NO PRODUCTION BEHAVIOR CHANGE WITHOUT AN OBSERVED, EXPECTED FAILING TEST FIRST.
</HARD-GATE>

## The rule

Do not change production behavior until a focused test fails for the expected
reason. Existing implementation outside the requested change remains intact.

1. Name the observable behavior and the smallest public boundary that proves it.
2. Write one focused test. Directly test an internal invariant only when the
   public boundary cannot isolate its failure mode.
3. Run it and record the expected failure, command, and exit status.
4. Implement the smallest change that passes.
5. Run the focused test, then the affected suite.
6. Refactor only while the tests remain green.

If a test passes before implementation, it is not red evidence. If it errors due
to fixture or syntax problems, repair the test until it fails on the missing
behavior.

## Consolidating tests

Do not equate similar assertions with duplicate guarantees. Keep separate OS,
security, cancellation, and integration boundaries. For every removed test,
record `old_test`, `behavior`, `replacement`, `mutant`, `red_observed`,
`baseline_ms`, `candidate_ms`, and `reason`. The retained test must kill the
named mutant at the intended caller boundary.

After one warm-up, measure five isolated runs and report every sample and the
median. Review a slowdown only when it exceeds both 20 percent and 100 ms.

Completion requires observed red and green evidence, affected-suite results,
and the consolidation ledger when tests were removed. A missing reviewer is
reported as incomplete review, never simulated.

## Strategy rotation

If the same test remains red after two implementation attempts, stop and
recheck the test boundary, fixture, and expected behavior. The strategy-rotation
hook is a signal to try a fundamentally different hypothesis, not another
variation of the same patch.

Adapted from `DEEPENING` in `mattpocock/skills` at commit
`3cca18b368ae95cdbdebbff572ccafa662551015` under the MIT License. See
`THIRD_PARTY_NOTICES.md`.
