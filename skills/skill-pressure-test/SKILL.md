---
name: skill-pressure-test
description: "Interrogate a plan, decision, or design one question at a time until it holds — use to stress-test your own thinking before committing to it"
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.


# Pressure Test

Interview the user relentlessly about a plan, decision, or design until you both
reach a shared understanding of it. Walk each branch of the decision tree,
resolving dependencies between decisions one at a time.

This is not brainstorming. `skill-thought-partner` opens a space up and looks for
what might be there; this closes one down and looks for what is wrong with it.
Use this when there is already a position on the table and the risk is that it is
wrong in a way nobody has said out loud.

Adapted from the `grilling` skill in
[mattpocock/skills](https://github.com/mattpocock/skills) (MIT).

## When To Use

- The user has a plan, spec, or design and wants it attacked before they commit.
- A decision keeps getting deferred because its dependencies are tangled.
- Scope feels slippery and nobody can say precisely what is in it.
- Before a large or hard-to-reverse change, where being wrong is expensive.

## When Not To Use

- To generate options. That is `skill-decision-support`.
- To explore an open space with no position yet. That is `skill-thought-partner`.
- When the user wants the work done, not examined. Say so and stop.
- When you can settle the question by reading the codebase. Read it instead.

## Inputs

The plan, decision, or design under test, in whatever form exists — a document, a
paragraph, or just the last few turns of conversation. Nothing needs writing up
first; extracting the shape is part of the job.

## Workflow

**Ask one question at a time.** Wait for the answer before asking the next. A
batch of questions is a questionnaire, and it gets questionnaire answers:
shallow, and shaped by whichever one the reader happened to care about. One
question, answered properly, changes what the next question should be.

**Carry a recommended answer with every question.** "What should happen when the
token expires?" is work handed back. "What should happen when the token expires?
I would refresh silently and only surface an error if the refresh fails, because
the alternative interrupts the user mid-task — do you agree?" is a question that
can be answered in one word, and disagreed with precisely.

**Look facts up; put decisions to the user.** If the answer is discoverable in
the filesystem, the git history, a config file, or a tool you can run, find it —
asking is a tax on the user for work you could have done. Decisions are
different: they are the user's, and no amount of reading the codebase produces
them. Do not infer a decision from a pattern and proceed as though it were
settled.

**Follow dependencies, not a list.** When an answer makes another question moot,
drop it. When it opens two new ones, ask those before returning. The order is
whatever the tree dictates.

**Name disagreement when you find it.** If an answer contradicts an earlier one,
say which two and ask which holds. Quiet reconciliation is how a plan ends up
meaning two things.

## Provider Or Data Priority

1. The repository — code, config, history, tests. Facts live here.
2. The user — for every decision, preference, and priority.
3. External sources only when the decision turns on something outside the repo,
   and say so when it does.

## Stop Or Checkpoint Rules

- **Do not act on the plan until the user confirms you have reached shared
  understanding.** This skill produces agreement, not changes.
- Stop when the remaining questions no longer change what anyone would do. More
  interrogation past that point is theatre.
- Stop and say so if the plan turns out to be sound. Manufacturing an objection
  to look rigorous is worse than finding none.
- If an answer invalidates the premise of the whole plan, stop the interview and
  raise that. Do not keep grilling the details of something already dead.

## Output Contract

1. **Where it stands** — sound as-is, sound with the changes below, or unsound.
2. **Decisions settled** — one line each, in the order they were made, since
   later ones often depend on earlier ones.
3. **Changes to the plan** — what the answers actually altered.
4. **Still open** — questions raised and not resolved, and what each one blocks.
5. **Facts found** — anything looked up that the user did not know, with where
   it came from.

## Verification

- Every question was asked singly and answered before the next.
- No decision in the summary was inferred rather than answered.
- Every fact cites where it came from.
- Nothing in the plan was changed during the interview.
