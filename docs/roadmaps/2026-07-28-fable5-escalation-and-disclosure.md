# Fable 5 escalation, Codex review flip, progressive disclosure

Three features shipped together on `feat/fable5-escalation-and-feature-disclosure`.
This records the design decisions and the two places the original framing was
changed, so neither gets re-litigated from scratch.

**bd was write-blocked when this shipped** (4 pending schema migrations, v49 →
v53, needing the single designated migrator). The `bd create` commands at the
bottom are ready to run once writes are restored; nothing here has been filed.

## What shipped

| Feature | Mechanism | Default |
|---|---|---|
| Selective Fable 5 escalation | `fable5_maybe_escalate` at `lib/dispatch.sh`, judgment roles only | off, opt-in |
| Authorship-aware review flip | `_octo_reviewer_flip_active` in `lib/agent-utils.sh` | off, opt-in |
| Progressive feature disclosure | `config/features.json` + `features_v1` ledger + `/octo:whats-new` | always on, one advisory line |

## Two changes to the original framing

### Fable 5 reviews nothing that Opus wrote

The request was for Fable 5 to check "PRDs, plans, specs and reviews".
Escalation deliberately does **not** cover review. `frontier-model-routing.md`
states that Anthropic-family agreement is not an independent check, so Fable
reviewing an Opus-authored plan is a same-family echo bought at twice the Opus 5
price. Fable's value here is capability, not vendor diversity.

The eligible roles are therefore `architect` and `strategist` only: authoring
judgment artifacts and premium synthesis/arbitration. `code-reviewer` is
explicitly excluded and stays on GPT-5.6 Sol, which the routing doc already
assigns. Fable authors and arbitrates; Codex opposes.

Note these are the *real* role names from `agent-utils.sh`. An earlier draft of
this design used invented roles (`prd-author`, `prd-scorer`, `adjudicator`) that
do not exist anywhere in the dispatch path, and an allowlist built on them would
have matched nothing. `/octo:prd`, `flow-define` and `skill-council` all
dispatch through `architect` and `strategist`, so those two cover the intended
surface.

### Codex is not made the default implementer for native sessions

Inside octo workflows Codex already is the default implementer
(`agent-utils.sh` maps `implementer` to `codex:gpt-5.6-sol`, and `workflows.sh`
tangle coding dispatches it). Extending that to native Claude Code sessions was
dropped, not deferred: `codex exec --sandbox workspace-write` collapses the
user's review surface from per-edit permission prompts to a single Bash approval
covering arbitrary workspace writes. `frontier-model-routing.md` is explicit
that a model change must never broaden write authority, and unlike the rest of
this work that is not something CI can catch or a user can undo after the fact.

What was actually missing was authorship-aware review, which is what shipped.

## Why escalation lives in dispatch, not the model resolver

`model-resolver.sh` caches on `provider/agent/phase/role/config-cksum` with no
liveness component. An escalation applied there would keep serving a cached
`claude-fable-5` after the seat was marked quota-dead mid-session, and would
need a cache-bypass plus a test to prove the bypass works.

`lib/dispatch.sh` runs after the cache on every call, which is also where
`fable5_maybe_reroute` already lives. Putting escalation there removes the
failure mode instead of guarding it. A regression test asserts escalation is
called from `dispatch.sh` and *not* from `model-resolver.sh`, so a future move
into the resolver fails loudly.

## Headroom is reactive because it cannot be predictive

No endpoint reports remaining Fable 5 usage on a Claude Code seat, and the limit
is a rolling window shared with the user's interactive Claude usage, which the
plugin cannot observe. A self-maintained budget ledger would drift from reality
immediately and give false confidence.

So: escalate, and if the dispatch comes back rate-limited, `quota-watcher` marks
`claude-fable-5` dead and escalation stands down for the TTL. The claude-sdk
shim's existing refusal retry (which gates on the model string, not on
`fable5_mode_active`) already lands a refused Fable dispatch on Opus 5, so an
escalated dispatch inherits that for free.

Cost containment is a per-run cap: one escalated dispatch per process tree.
Councils, debates and review fleets dispatch many seats, and escalating each one
is exactly the spend the one-owner rule exists to prevent.

## Disclosure state model

Manifest (`config/features.json`, checked in) declares `id`, `added_in`,
`title`, `description`, `kind`, `key`, `default`, `prereq`, optional
`reoffer_at` and `backfill`. Ledger (`features_v1` in `state.json`, per user)
records `{decision, at_version}` plus a `features_watermark`.

Four states: absent (never offered), `enabled`, `declined`, `disabled`.
`declined` and `disabled` are deliberately distinct even though both suppress
offers. Collapsing them would mean a future "re-offer disabled features" change
resurrects every past rejection, which is the nagware failure this design exists
to avoid. The one legitimate re-ask is a manifest `reoffer_at` above the version
at which the user declined.

Two decisions worth recording:

- **A corrupt ledger disables disclosure entirely.** An unreadable `state.json`
  makes every decision read come back empty, which is indistinguishable from
  "never offered" — so disclosure would re-offer every feature every session
  while also being unable to write the answer down. `octo_features_available`
  therefore requires the ledger to be absent or valid JSON.
- **The watermark seeds from `last_seen_version`, not the current version.**
  Seeding from the current version would put every feature shipped in this
  release below the watermark and nothing would ever be offered. The advisory
  hook seeds from the version the user is coming *from*.

`model_defaults_v2: "accepted"` is left in place and not migrated. It gates a
different thing (role routing, with an `OCTOPUS_LEGACY_ROLES` escape hatch) and
rewriting it would invalidate consent users already gave.

## Known gaps

- **The advisory fires once per version jump.** A user who ignores that line
  does not hear again until the next upgrade. `/octo:whats-new` remains
  discoverable, but a user who misses the line and never runs the command stays
  unaware. Deliberate: firing every session is the nagware failure above.
- **No input-size gate on escalation.** The intended guard was to skip
  escalation above `OCTOPUS_FABLE5_MAX_INPUT_KB`, but the prompt is not assembled
  at the point where dispatch resolves the model, so the gate belongs in
  `lib/agents.sh`/`lib/spawn.sh`. Not implemented rather than implemented in the
  wrong place. Filed below.
- **Codex handoff hardening not done.** The dirty-tree guard, before/after diff
  attribution, handoff packet contract, and orchestrator-side re-run of quality
  gates were scoped out of this PR. Filed below.

```bash
bd create --type=feature --priority=2 \
  --title="Fable 5 escalation: input-size gate before an escalated dispatch" \
  --description="Skip escalation when the assembled prompt exceeds OCTOPUS_FABLE5_MAX_INPUT_KB. Must live where the prompt is assembled (lib/agents.sh or lib/spawn.sh), not in dispatch.sh where the model is resolved before the prompt exists." \
  --acceptance="An oversized prompt logs a WARN and stays on Opus 5; an undersized one escalates; the threshold is configurable and has a documented default."

bd create --type=feature --priority=2 \
  --title="Codex implementation handoff hardening" \
  --description="Four hardenings of the octo-workflow Codex handoff: refuse or snapshot on a dirty tree, capture before/after diff for attribution, codify the handoff packet (task, target files, acceptance criteria, forbidden paths, session decisions) in flow-develop with a validation gate, and re-run quality gates orchestrator-side rather than trusting Codex self-reported results." \
  --acceptance="Dirty-tree guard covered by a test; handoff packet missing acceptance criteria fails loud; a Codex stub that lies about tests fails the workflow; effective sandbox mode logged per dispatch."

bd create --type=task --priority=3 \
  --title="Surface unactioned feature offers beyond the single version-jump advisory" \
  --description="The SessionStart advisory fires once per version jump. A user who misses it never hears again. Consider mentioning the outstanding count in /octo:doctor or /octo:setup output, which the user visits deliberately, without reintroducing per-session nagging." \
  --acceptance="Outstanding offers are discoverable from at least one command the user already runs; no new per-session advisory."
```
