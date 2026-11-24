---
name: skill-verification-gate
description: "Use when about to declare work complete, fixed, passing, or done"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Invoke installed skills by their `$skill-name`. Known Octopus commands are mapped below. A remaining `/octo:*` reference is a Claude Code command; do not execute it in Codex or invent an equivalent.
> Before the first helper call, derive the absolute plugin root from this loaded skill's path by finding its ancestor containing `.codex-plugin/plugin.json`. Verify that root, bind `OCTO_ROOT`, `CODEX_PLUGIN_ROOT`, and `CLAUDE_PLUGIN_ROOT` to the same root, and export all three in each fresh shell before launching child processes. Use the verified absolute helper path when needed. Do not infer the root from the user's project or assume exports survive tool calls. Stop and report a missing installation if the root cannot be verified.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> Claude-native tool calls in examples are prompt templates to adapt, not Codex call signatures. If a mandatory verification agent or tool is unavailable or unauthorized, report that verification did not run and stop the affected completion step. Never claim a skipped check passed.
> Attribute commits only to actual contributors; do not copy fixed model attribution trailers from examples.
> For host tool equivalents, see `codex-skills/blocks/codex-host-adapter.md`.

> Invoke this entry as `$skill-verification-gate` in Codex. Code-fenced Claude command examples are reference text, not Codex shell commands.


# Verification Gate

## Portable feature evidence

Load the selected feature's policy provenance and open-marker count through the existing boundary adapter. Cite the exact policy passage and conflicting plan action for any verified policy violation. Report unresolved decisions and which tasks depend on them. Stable task completion needs parent verification tied to the current task-contract digest; a checkbox, model claim or historical manifest alone cannot prove completion. Retain result-to-task mappings through correction, cancellation and resume.

## The Iron Law

<HARD-GATE>
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
</HARD-GATE>

If you haven't run the verification command in this turn, you cannot claim it passes.

## The Gate

Before claiming any success or expressing satisfaction:

1. **IDENTIFY** — What command proves this claim?
2. **RUN** — Execute the full command (fresh, not cached)
3. **READ** — Full output, check exit code, count failures
4. **VERIFY** — Does output actually confirm the claim?
5. **ONLY THEN** — State the claim WITH evidence

Skip any step = the claim is unverified.

## Rationalization Table

| Excuse | Reality |
|--------|---------|
| "I ran the tests earlier this session" | Earlier is not fresh. Code changed since. Run again. |
| "The edit was trivial, it can't break anything" | Trivial edits break builds daily. The gate has no size exemption. |
| "The subagent reported success" | Agent reports are claims, not evidence. Verify independently. |
| "CI will catch it anyway" | CI is the safety net, not the verification. Verify before push. |
| "I'm confident this works" | Confidence is not evidence. Run the command. |
| "Running the full suite is slow" | Then run the targeted suite — but run something, fresh. |

## What Counts as Evidence

| Claim | Requires | NOT Sufficient |
|-------|----------|----------------|
| Tests pass | Test command output showing 0 failures | Previous run, "should pass" |
| Build succeeds | Build command exit 0 | Linter passing |
| Bug fixed | Reproduce original symptom: now passes | "Code changed, should work" |
| Regression test works | Red (fail without fix) → Green (pass with fix) | Test passes once |
| Subagent completed task | `git diff` shows expected changes | Subagent says "done" |
| Requirements met | Line-by-line checklist against spec | Tests passing |
| Provider dispatch worked | Output contains expected content | No error ≠ success |

## Red Flags — STOP and Verify

If you catch yourself thinking any of these, STOP:

| Thought | What to do instead |
|---------|-------------------|
| "Should work now" | Run the verification |
| "I'm confident" | Confidence ≠ evidence |
| "Just this once" | No exceptions |
| "The linter passed" | Linter ≠ tests ≠ build |
| "The agent said it worked" | Verify independently |
| "It's a small change" | Small changes cause big bugs |

## Multi-Provider Context

In Claude Octopus workflows, verification is especially critical because:

- **Provider outputs can be hallucinated** — Codex, Antigravity, Copilot, and other providers may claim success without evidence
- **Consensus ≠ correctness** — three models agreeing doesn't mean they're right
- **Synthesis files may belong to earlier runs** — use the path from this invocation
- **orchestrate.sh exit code 0 ≠ quality** — the script ran, but did it produce good output?

For fresh completion of a workflow that produces a synthesis, set
`SYNTHESIS_FILE` to the exact path after confirming this invocation wrote a new synthesis.
Stop the fresh completion check if no new synthesis was written or the path is unknown.

Treat `Synthesis already exists`, a completed resume, and a cache hit as reuse.
For an explicit resume or cache reuse, review the saved evidence for the
identified run and report the result as reused evidence.

```bash
synthesis_file="${SYNTHESIS_FILE:-}"
if [[ ! -f "$synthesis_file" || ! -r "$synthesis_file" ]]; then
  printf '%s\n' 'Verification failed. The current run has no readable synthesis file.' >&2
  exit 1
fi

if ! awk '
  /[^[:space:]]/ && !/^[[:space:]]*#+([[:space:]]|$)/ { found = 1; exit }
  END { exit !found }
' < "$synthesis_file"; then
  printf 'Verification failed. The synthesis has no findings to review in %s.\n' "$synthesis_file" >&2
  exit 1
fi
printf 'Synthesis has content in %s.\n' "$synthesis_file"
```

Read the checked file and verify its findings against the workflow's evidence
before reporting success.

## When to Apply

**ALWAYS before:**
- Committing code
- Creating PRs
- Marking tasks complete
- Moving to next workflow phase
- Reporting results to user
- Claiming a bug is fixed

**In orchestrate.sh workflows:**
- After `probe` (discover) — verify synthesis file exists
- After `grasp` (define) — verify consensus score meets threshold
- After `tangle` (develop) — verify tests pass, not just that code was written
- After `ink` (deliver) — verify review actually ran, not just that it was dispatched

## Examples

### Correct: Evidence-Based Claim
```
$ npm test
  ✓ user.create() saves to database (45ms)
  ✓ user.create() validates email (12ms)
  Tests: 2 passed, 2 total

All 2 tests pass. ← Claim backed by output.
```

### Incorrect: Claim Without Evidence
```
I've implemented the feature. It should work now. The tests should pass.
← No test was run. "Should" is not evidence.
```

### Correct: Regression Test Red-Green
```
1. Write test → run → FAIL (expected, proves test detects the bug)
2. Implement fix → run → PASS (proves fix works)
3. Revert fix → run → FAIL (proves test isn't false-positive)
4. Restore fix → run → PASS (final confirmation)
```

## Integration with Other Skills

This skill is referenced by:
- `flow-develop.md` — verification gate after implementation
- `flow-deliver.md` — verification gate before delivery
- `skill-code-review.md` — verify review findings before reporting
- `skill-tdd.md` — red-green cycle requires evidence at each step
- `skill-factory.md` — autonomous pipeline must verify at every phase
