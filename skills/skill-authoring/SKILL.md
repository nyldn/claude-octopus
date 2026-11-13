---
name: skill-authoring
disable-model-invocation: true
description: "Principles for writing skills that behave the same way every run — use when adding, editing, or reviewing a skill in this plugin"
codex_display_name: "Skill Authoring"
---

# Skill Authoring

Load `skills/blocks/engineering-method-selection.md` from the installed plugin
and apply only the methods relevant to this task. Preserve this entry point's
execution contract and output format. Read referenced skills as instructions;
do not invoke the current command recursively or add provider calls from a seat.

## Domain language

Load `skills/blocks/domain-modeling.md` when a skill discusses providers, models,
access, billing, reviewers, or votes. Reuse the shared definitions instead of
inventing local synonyms. State the source and time of observations. Never infer
authentication, entitlement, billing mode, quota, or model-family independence
from a binary or transport name alone.

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

### Invocation: explicit by default

Every shipped command and skill carries `disable-model-invocation: true`.
In Claude Code, the user chooses an `/octo:*` command or names a skill explicitly.
The Codex generator also writes `policy.allow_implicit_invocation: false` to each
skill's `agents/openai.yaml`; Codex users invoke the installed `$skill-name`.
Do not depend on automatic activation for either host.

Use the absolute entry path supplied by the host to derive the plugin root.
Resolve symlinks first, then walk upward from that file's directory. At each
ancestor containing the selected host's plugin manifest, check its registration:

1. Claude Code: read `.claude-plugin/plugin.json`. Expand each declared `skills`
   path beneath that ancestor and append `SKILL.md`. Require the resolved loaded
   entry to equal one of those existing registered files.
2. Codex: read `.codex-plugin/plugin.json`. Expand the declared `skills` directory
   beneath that ancestor. Require the loaded entry to be the existing
   `<skills-directory>/<registered-name>/SKILL.md`, with the skill directory an
   immediate child of that declared directory.
3. Accept exactly one matching ancestor as the plugin root. Reject paths outside
   the root, missing registered entries, and zero or ambiguous matches. Stop if
   the host does not expose the loaded entry's absolute path; do not guess from
   the current directory, a cache name, or an unrelated environment variable.

Before loading another skill, construct its host-registered path under that
verified root and confirm its complete `SKILL.md` exists. Load the complete
host-specific `SKILL.md` entry. For this repository's current Codex manifest,
the registered path pattern is `codex-skills/<registered-name>/SKILL.md`, such
as `codex-skills/skill-authoring/SKILL.md`; derive the directory from the
manifest rather than assuming this package layout elsewhere.

Treat the loaded body as instructions in the current conversation. Follow its
steps in order and pass the user's text as workflow arguments, never executable
path content. Do not invoke the current skill recursively. `.claude/skills/`
contains development sources; it is not the Codex discovery directory. Do not
assume a hook's environment variables or a fallback checkout identify the plugin
that supplied the loaded entry.

Plain-language routing is a separate, legacy-compatible opt-in controlled by
`OCTOPUS_AUTO_ROUTER_MODE=suggest|invoke`. Its default is `off`. New skills must
never depend on prompt-keyword auto-routing for reachability.

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
  skill or `hooks/user-prompt-submit.sh` already claims it. The hook is opt-in,
  but overlapping phrases still degrade routing for users who enable it.

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
advises, name the registered workflow skill and omit a dispatch contract. Add
one when the skill actually dispatches providers.

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
- The native entry is registered in `.claude-plugin/plugin.json`. The Codex
  entry is under the skills directory declared in `.codex-plugin/plugin.json`,
  with matching `name` and `agents/openai.yaml` metadata. `make sync-check` passes.
- It declares `disable-model-invocation: true`; the generated Codex interface has
  `policy.allow_implicit_invocation: false`. Composing commands load the verified
  host-specific entry directly.
- `tests/unit/test-native-skill-registration.sh`,
  `tests/unit/test-codex-manifest.sh`, and
  `tests/unit/test-explicit-activation.sh` pass. These static checks do not prove
  invocation on an installed host. Record Claude and Codex discovery and
  explicit-invocation results separately when that acceptance is required.
