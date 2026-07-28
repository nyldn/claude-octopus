# Control-plane epic (oco-fgg) — decomposition

`oco-fgg` is a P3 tracking epic, not a unit of work. It carries three of the
five "Next Major" bullets from `2026-06-13-next-minor-major.md`. This document
breaks it into issues that can actually be claimed, and records what is already
done so the epic is not re-scoped from scratch each time someone looks at it.

**bd was write-blocked when this was written** (4 pending schema migrations,
v49 → v53, needing the single designated migrator). The `bd create` commands
below are ready to run once writes are restored; nothing here has been filed.

## Status of the parent roadmap section

| Roadmap bullet | State |
|---|---|
| Structured lifecycle events (selection, dispatch, timeout, circuit breaker, review finding, synthesis) | **Done.** `provider.selected` and `circuit-breaker.*` shipped in #509; `review.finding` and `synthesis.start/end` complete the set (oco-aek). |
| Local monitor/HUD rendering events without scraping terminal output | Partly present — `hooks/octopus-hud.mjs` exists. Needs an audit against the event stream rather than new work. |
| Invariant backprop from repeated findings into durable specs | Not started. Child A below. |
| Semantic context adapters for large-codebase discovery | Not started. Child B below. |
| Lock-aware parallel scheduling with leases and recovery | Not started. Child C below. |

The event substrate is the epic's foundation and it is now complete. All three
remaining children consume it, so they are unblocked but should not start
before the event vocabulary is considered stable.

## Child A — invariant backprop from review findings

Repeated findings across reviews are evidence of a missing durable rule. Today
each review rediscovers them.

The `review.finding` events now emit `severity`, `file`, `line`, `category`,
`confidence` and `title` per finding, which is the input this needs. A finding
recurring across N runs at the same `category` (not the same `file:line` — the
line moves) is the backprop signal.

Scope: aggregate `review.finding` over the event log; detect recurrence by
category and title similarity; propose a durable rule; require human
confirmation before writing to any spec. Do **not** auto-write specs — a
mis-generalised invariant is worse than a repeated finding.

Risk: the aggregation is only as good as `category`, which is provider-supplied
and currently unconstrained. Expect to need a category vocabulary first.

```bash
bd create --type=feature --priority=3 --parent=oco-fgg \
  --title="Invariant backprop: derive durable rules from recurring review findings" \
  --description="Aggregate review.finding events across runs, detect recurrence by category rather than file:line, and propose durable spec rules for human confirmation. Never auto-write specs." \
  --acceptance="Recurrence detected across >=3 runs; proposal surfaced to a human; no spec written without confirmation; category vocabulary defined or a follow-up filed."
```

## Child B — semantic context adapters

"Optional ... so large-codebase discovery is explicit and measurable." The two
operative words are *optional* and *measurable*: this is an opt-in adapter with
a benchmark, not a default retrieval layer.

Scope: an adapter interface behind a feature flag, at least one implementation,
and a measurement harness comparing discovery quality against the current
grep/glob path on a fixed task set. If it cannot be measured against the
existing path, it should not ship.

Risk: highest-cost, lowest-certainty of the three. Sequence it last unless a
concrete large-codebase failure motivates it.

```bash
bd create --type=feature --priority=3 --parent=oco-fgg \
  --title="Semantic context adapters for large-codebase discovery (opt-in, measured)" \
  --description="Feature-flagged adapter interface plus one implementation, with a harness measuring discovery quality against the current grep/glob path on a fixed task set." \
  --acceptance="Adapter is opt-in and off by default; benchmark shows a measured delta vs the existing path; no regression when the flag is off."
```

## Child C — lock-aware parallel scheduling

The most immediately useful of the three, because the failure it prevents
already happens: parallel agents contend, and a crashed holder leaves state
behind.

`lib/validation.sh` already implements mkdir-based locking with pid/ts ownership
files and trap-based release — that is the primitive to build leases on, not a
thing to reinvent. What is missing is lease expiry (a crashed holder currently
relies on trap cleanup that a SIGKILL skips) and a recovery report.

Scope: add expiry to the existing lock, detect and reclaim an abandoned lease,
and emit a recovery report naming what was reclaimed and from which pid.

```bash
bd create --type=feature --priority=2 --parent=oco-fgg \
  --title="Lock-aware parallel scheduling: lease expiry and recovery reports" \
  --description="Extend the existing mkdir+pid/ts lock in lib/validation.sh with lease expiry so a SIGKILLed holder does not strand the lock, reclaim abandoned leases, and emit a recovery report." \
  --acceptance="A killed holder's lease is reclaimed after expiry; reclaim is reported with the prior pid; existing trap-based release path is unchanged."
```

## Recommended order

C, then A, then B. C fixes a failure that occurs today and builds on an existing
primitive. A is cheap once the category vocabulary exists and turns the new
event data into something durable. B is the largest bet and should wait for a
concrete motivating failure.

Once the children are filed, `oco-fgg` should stay open only as a parent, or be
closed as superseded by them.
