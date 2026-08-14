---
name: skill-intake
description: "Move incoming issues and pull requests through triage states until each is actionable or closed — use when the queue has piled up or a report arrives unsorted"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.


# Intake

Work the incoming queue. Each item moves through a small set of states until it
is either actionable by someone who did not write it, or closed with a reason.

**A pull request is an issue with attached code.** Same states, same moves, with
the deltas noted below. Resolving a bare `#42` means checking both.

Adapted from `triage` in
[mattpocock/skills](https://github.com/mattpocock/skills) (MIT), cut down to the
states this repo can actually represent and retargeted at `gh` and `bd`.

## When To Use

- Open issues or PRs have accumulated and nobody knows which are real.
- A new report arrives and needs sorting before anyone works it.
- An issue has been sitting because it is not clear what it is asking for.
- Before planning, to establish what is actually in the queue.

## When Not To Use

- To do the work an item describes. Triage decides what happens to it, not how.
- For local, private notes. That is `skill-issues` and `.octo/ISSUES.md`.
- To review a PR's code quality. That is `skill-code-review` or
  `skill-staged-review`; intake decides whether the PR should be reviewed at all.

## Inputs

An issue or PR reference, or nothing — with nothing, take the queue in order.
`gh issue list` and `gh pr list` for the public surface; `bd ready` and
`bd blocked` for tracked work.

## Workflow

### 1. Categorise

What kind of thing is it: a bug, an enhancement, a question, or noise. For a PR,
also: does it correspond to an existing issue, or arrive unannounced?

Do not skip this because the title looks obvious. Titles are written by people
who already know what they meant.

### 2. Verify

The step that earns the whole skill. For a bug: **reproduce it, or establish that
you cannot.** For a PR: check the claim it makes is the change it contains.

An unverified bug report is a hypothesis. Filing it as fact wastes whoever picks
it up. If reproduction needs something you do not have — credentials, a dataset,
a platform — that is `needs-info`, not `verified`.

### 3. Assign a state

- **`needs-triage`** — arrived, not yet sorted. The entry state.
- **`needs-info`** — blocked on the reporter. Say exactly what is missing; "more
  detail" is not a request anyone can act on.
- **`verified`** — reproduced or confirmed, ready to be worked.
- **`needs-decision`** — real, but what to do is a judgement call the maintainer
  has not made. Do not resolve these by inference. Escalate, or run
  `skill-pressure-test` with the maintainer.
- **`closed`** — not a bug, out of scope, duplicate, or fixed. Always with a
  reason, and for out-of-scope, why.

### 4. Write the brief

For anything reaching `verified`, write what someone picking it up needs and
would otherwise have to rediscover: where the relevant code is, what you already
ruled out, and how to tell when it is fixed. This is the difference between an
item that gets worked and one that gets re-triaged.

For a PR, add: whether it has tests, whether CI is green, and whether it conflicts
with anything in flight.

### 5. Record it

For public comment text, stream the completed note through the outbound gate:

```bash
printf '%s\n' "$TRIAGE_NOTE" | \
  "${CLAUDE_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}/scripts/safe-gh-comment.sh" \
    --repo OWNER/REPO issue-comment ISSUE_NUMBER -
```

Use `gh issue edit --add-label` only for the label mutation. Use `bd update` for
tracked work. If `bd` writes are blocked by pending migrations, say so and do
not run the migration — see `skill-work-slicing` for that constraint.

## Provider Or Data Priority

1. The repository — reproduce against the actual code.
2. CI logs and run history for anything claiming a failure.
3. The reporter, for what only they can supply.
4. Never assume the report is accurate because it is detailed.

## Stop Or Checkpoint Rules

- Stop before closing anything a human filed deliberately, unless it is a clear
  duplicate. Closing is the one move that is rude to get wrong.
- Stop before `needs-decision` items and surface them rather than guessing.
- Do not merge or push as part of triage, even for a PR that looks ready.
- One item at a time. Batch-labelling a queue without reading it is how real
  reports end up buried under a label.

## Output Contract

Per item:

1. **Reference and category.**
2. **State assigned, and why.**
3. **Verification result** — reproduced, could not reproduce, or not attempted
   with the reason.
4. **Brief** — for verified items only.
5. **Action taken** — labels, comments, or the exact commands not run and why.

Then a queue summary: counts by state, and which items are now takeable.

## Verification

- Every `verified` item was actually reproduced, or says explicitly that it was
  not and why.
- Every `needs-info` names the specific missing thing.
- Every closure carries a reason.
- Nothing was merged, pushed, or fixed during triage.
