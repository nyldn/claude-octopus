---
name: skill-authoring
description: "Principles for writing skills that behave the same way every run — use when adding, editing, or reviewing a skill in this plugin"
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.


# Skill Authoring

A skill exists to get determinism out of a stochastic system. **Predictability**
is the goal, and it means the agent takes the same *process* every run — not that
it produces the same output. Every rule below serves that.

`docs/PLUGIN-ASSEMBLY-STANDARD.md` already fixes the *structure* a skill body
should take. This is about what makes the content inside that structure work.

Adapted from `writing-great-skills` in
[mattpocock/skills](https://github.com/mattpocock/skills) (MIT), with the
invocation section rewritten for how this plugin actually loads skills.

## When To Use

- Writing a new skill, or reviewing one in a PR.
- A skill fires when it should not, or fails to fire when it should.
- A skill behaves differently run to run on the same input.
- Deciding whether something should be a skill at all, or a command, or prose in
  `CLAUDE.md`.

## When Not To Use

- For the mechanical checklist — file layout, registration, required sections.
  That is `docs/PLUGIN-ASSEMBLY-STANDARD.md` and the CI suites.
- For writing prompts that are not skills. That is `skill-meta-prompt`.

## Inputs

The skill under construction or review, and an honest answer to: what should the
agent do differently because this exists?

## Workflow

### Invocation: how this plugin differs

Upstream draws a clean line between a **model-invoked** skill (carries a
description, the agent can fire it autonomously, costs context every turn) and a
**user-invoked** one (`disable-model-invocation: true`, zero context cost, but
the user must remember it exists).

**That line does not transfer cleanly here, and getting it wrong breaks
routing.** Six skills in this repo declare `invocation: human_only`. That key is
custom — `scripts/build-codex-skills.sh` strips it from the generated tree, and
nothing reads it. The real effect comes from an advisory reminder in
`hooks/context-reinforcement.sh`, kept in step by
`tests/unit/test-human-only-skill-list.sh`.

Do **not** reach for `disable-model-invocation: true` to express "human-only"
here. Four of those six are named in command bodies (`commands/parallel.md`,
`factory.md`, `research.md`, `security.md`) and the model reaches them on the
user's behalf when running those commands. Disabling model invocation would break
`/octo:parallel`, `/octo:factory`, `/octo:research`, `/octo:security`.

So in this plugin: "human-only" means *do not fire from prompt-keyword
auto-routing*. Declare it with `invocation: human_only`, add the skill to the
hook's list, and accept that it is advisory.

### Writing the description

The description does two jobs: say what the skill is, and list the branches that
should trigger it. It sits in the context window every turn, so it earns harder
pruning than the body.

- Lead with the word that does the invoking.
- **One trigger per branch.** Synonyms that rename the same branch are
  duplication: "use for test-first development … when the user wants TDD" is one
  branch written twice.
- Cut identity that the body already carries. Triggers, plus any "when another
  skill needs this" clause, and nothing else.
- Beware collision. With this many skills the scarce resource is trigger space,
  not skill count. Before adding a trigger phrase, check whether an existing
  skill or `hooks/user-prompt-submit.sh` already claims it — that hook
  auto-invokes on strong matches, and a new overlapping phrase degrades a working
  route rather than adding one.

### Information hierarchy

Content is either a **step** (an ordered action) or **reference** (a rule or fact
consulted on demand). A skill can be all of one, or both. Place each piece on the
rung it belongs:

1. **In-skill step** — what the agent does, in order.
2. **In-skill reference** — consulted while working. A flat set of peer rules is
   a legitimate shape, not a smell.
3. **External reference** — pushed into a sibling file and reached by a pointer,
   loaded only when the pointer fires. `skills/blocks/` is where shared ones live.

Push too little down and the top bloats; push too much and the agent never finds
what it needs. Branching is the cleanest test: inline what every run needs, push
behind a pointer what only some runs reach.

### Completion criteria

Every step ends on a condition that says the work is done. Make it:

- **Checkable** — can the agent tell done from not-done without guessing?
- **Exhaustive where it matters** — "every changed file accounted for" rather
  than "review the changes". A vague criterion invites stopping early on
  something that looks finished.

"Produce a summary" is not a completion criterion. "Every boundary in the table
maps to a real handoff in the setup" is.

### Enforcement, and its cost

A body that names the orchestrator script directly is required by
`tests/unit/test-mandatory-compliance.sh` to carry a `MANDATORY COMPLIANCE` block
and a `PROHIBITED` list. That is deliberate for skills that dispatch providers
and spend money. It is dead weight on an advisory skill — so if a skill only
advises, refer to workflows by their `/octo:` command names and skip the
ceremony rather than adding a compliance block nobody needs.

## Provider Or Data Priority

1. The existing skills, as worked examples of the conventions.
2. `docs/PLUGIN-ASSEMBLY-STANDARD.md` for required structure.
3. The CI suites, which encode constraints prose does not mention.

## Stop Or Checkpoint Rules

- Stop before adding a skill whose triggers overlap an existing one. Extend the
  existing skill instead; a near-duplicate makes both harder to reach.
- Stop if the answer to "what does the agent do differently" is "nothing it
  would not have done anyway".
- If the content is one paragraph of advice with no process, it belongs in the
  skill that already covers the area, not in a new file.

## Output Contract

When reviewing, report:

1. **Verdict** — ship, revise, or fold into an existing skill.
2. **Predictability risks** — where two runs would diverge.
3. **Trigger collisions** — which existing skill or hook arm competes.
4. **Criteria that are not checkable** — quoted, with a replacement.
5. **Misplaced content** — what should move up or down the hierarchy.

## Verification

- The description names distinct branches, with no synonym pairs.
- Every step has a criterion the agent can evaluate.
- No trigger phrase collides with `hooks/user-prompt-submit.sh` or an existing
  skill's description.
- The skill is registered in `.claude-plugin/plugin.json` and `make sync` is
  clean.
- If it declares `invocation: human_only`, it is in the hook list and
  `tests/unit/test-human-only-skill-list.sh` passes.
