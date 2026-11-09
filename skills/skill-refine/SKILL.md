---
name: skill-refine
description: "Score and improve an artifact with a frozen rubric, independent models, implemented edits, and bounded rescoring"
disable-model-invocation: true
---

# Rubric-guided refinement

Execute the workflow below when invoked through `/octo:refine` or
`/octo:ladder`. This is a host-managed workflow using real provider calls.
Never role-play other models or invent their scores. The score validator checks
structure and arithmetic; it does not verify the truth of a model's judgments.

Set `OCTO_SKILL_FILE` to the absolute path of this loaded `SKILL.md` supplied by
the host. Resolve its installation before reading resources or running commands.
This works without a stable plugin link or trusted startup hooks. If the host
supplies no skill path, use its explicit plugin root; stop if neither resolves.

```bash
OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${OCTO_ROOT:-}}}"
if [[ -n "${OCTO_SKILL_FILE:-}" ]]; then
  [[ "$OCTO_SKILL_FILE" == /* && -f "$OCTO_SKILL_FILE" ]] || exit 1
  OCTO_ROOT="$(cd "$(dirname "$OCTO_SKILL_FILE")" && pwd -P)"
  while [[ "$OCTO_ROOT" != / && ! -f "$OCTO_ROOT/.claude-plugin/plugin.json" && ! -f "$OCTO_ROOT/.codex-plugin/plugin.json" ]]; do
    OCTO_ROOT="$(dirname "$OCTO_ROOT")"
  done
fi
[[ -n "$OCTO_ROOT" && -f "$OCTO_ROOT/scripts/refinement-judge.sh" && -f "$OCTO_ROOT/scripts/refinement-score.py" && -f "$OCTO_ROOT/skills/skill-refine/SKILL.md" ]] || {
  printf '%s\n' 'Cannot resolve this installed Octopus skill' >&2
  exit 1
}
```
Keep this absolute root in the workflow context and include its assignment in
each new shell invocation. Shell variables may not persist between tool calls.
If the judge adapter or score validator is missing at this root, stop and name
the missing component rather than running a command with an empty root.

## 1. Establish scope and budget

Read the supplied artifact and relevant project instructions. Accept text,
files, plans, code, images, or other artifacts the host can actually inspect.
For binary, visual, or remote artifacts, obtain a faithful readable or rendered
snapshot with the appropriate host tools. If you cannot inspect it, stop and
name the missing capability. Do not score an unseen attachment or a URL title.

Before any external provider call, including model-assisted research, inspect
the candidate, supporting evidence, and accessible project context for
credentials and private tokens. Repeat this inspection for new content before
dispatch. If secrets are found, stop the run before research or judging and
report the affected input or file without quoting its secret values. Do not
continue by creating a sanitized copy, changing working directories, or asking
a judge to ignore the original. The current adapter restricts writes and tools;
it does not enforce isolation from the secret-bearing original or other
readable files. Secret-bearing inputs require an execution boundary that
prevents those reads, which this adapter does not provide. Host inspection is
not an automatic secret scanner or a guarantee of data isolation.

Record the audience, intended outcome, constraints, editable paths, and what
must be preserved. A request to improve a plan authorizes editing the plan,
not executing the project described by it. A scoring or review-only request
produces assessments and proposed revisions without changing the original.
Otherwise invocation authorizes scoped improvements to the supplied artifact.
Ask only for missing information that prevents a useful, bounded run.

Validate all options before work. Defaults are target 95/100, max five
improvement rounds, max 30 elapsed minutes, and max 14 external model calls.
`--max-rounds` accepts integers 1 through 10; minutes and calls must be positive
integers; target must be finite and between 0 and 100. Preserve explicit budgets.
Retries, research, scoring, and model-assisted edits all consume the call budget.
Baseline is round zero. Check remaining time and calls before every dispatch,
and reserve two scoring calls before starting an improvement. Bound each call
by the remaining elapsed budget. Never reset counters on resume or restart a
run to evade a limit. Stop after two rounds without verified improvement.

Create a unique run directory in the user's project under
`.claude-octopus/refine/<run-id>/`, never in the installed plugin. Check the
project's ignore rules before writing sensitive content there. If it is not
ignored, use a private directory outside the repository and report its path.
Keep the original, best candidate, rubric, model responses, score reports, and
an append-only `iterations.jsonl`. Record hashes, actual model IDs and effort,
calls, elapsed time, available usage/cost data, changes, and reasons for keeping
or rejecting candidates. Unknown monetary cost stays unknown.

Snapshot the exact initial content and existing dirty edits. Work on a candidate
copy. Publish only an accepted candidate into the authorized paths after checking
that the original has not changed since it was read. Preserve concurrent edits
and stop on a conflict. Never use `git reset --hard`, `git clean`, blanket
checkout, `git add -A`, or automatic commits to manage these experiments.

## Phase loading and fixed judging contract

Use the host's native shell, file inspection, and task tools. On Codex, load
`skills/blocks/codex-host-adapter.md` from the resolved plugin root. Do not assume
that a host exposes a provider or subagent until its tools confirm availability.

Before each phase, read its entire resource from the resolved installed plugin
root, using the exact phase paths listed below. These paths work
for both Claude and Codex installations. Stop if a resource is missing. Load only
the next phase, and reload its resource after compaction before resuming it:

1. Scope, secret inspection, candidate preservation, and budgets are above.
2. Load `skills/skill-refine/references/phase-2.md` to select and freeze the rubric.
3. Load `skills/skill-refine/references/phase-3.md` before independent scoring.
4. Load `skills/skill-refine/references/phase-4.md` before edits and rescoring.
5. Load `skills/skill-refine/references/phase-5.md` before delivery and trajectory.

Before external research or judging, inspect candidate, evidence and accessible
context for secrets as required above. Run declared guards before model review.
Choose exactly Claude and Codex with `preflight.sh --providers claude,codex`,
without changing the council roster. Preserve fixed explicit models and efforts,
record requested and resolved identities, and stop on a required provider failure.
A readiness receipt is selection evidence only. Fresh dispatch auth, quota, and
policy checks remain mandatory, including when credentials change after selection.

Both independent read-only judges must receive the same frozen candidate, blind
rubric, and guard evidence. Hide target, prior scores, author and other judges.
Always use `refinement-pair.py` through its mandatory single-judge adapter.
Reserve both calls before launch and count failures, cancellation, research,
retries, and resume against the same total budget and absolute deadline. Never
redispatch a reserved pair ID. Raw stdout and one successful seat cannot pass.
For a material rubric correction, follow phase 2's explicit version transition
and rescore the original before the best candidate within the remaining budget.

Bind assessment identities to actual dispatch metadata, exactly one canonical
`claude` and one `codex`, plus rubric and candidate hashes. Run
`scripts/refinement-score.py` on both valid assessments. Its conservative lower
score, criterion minima, no blockers, passing guards and disagreement limit of
10 points control acceptance. Verify findings before edits. Never average away
failure or weaken the rubric. Accept only verified improvement with no regression.
Stop after two stalled rounds or any budget, evidence, cancellation or provider
blocker. Resume only with matching ledger, original, candidate, current rubric version, fixed
panel, models and efforts; never reset counters. Label target success only when
the validator reports `target_met: true` for the delivered bytes. Preserve
concurrent edits and existing approval boundaries through delivery.
