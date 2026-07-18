# Enforcement Patterns (shared block)

House patterns for making process skills hold under generation pressure. Emphasis
("MANDATORY", "CRITICAL") decays over a long session and is counterproductive on models
with strict-compliance costs (see `fable5-prompting.md`); these three patterns do not.
New and revised skills should prefer them over adding more capitalized adjectives.

## 1. Iron Law

One non-negotiable line per discipline, stated in a code block, repeated nowhere else:

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

A skill gets at most ONE Iron Law. If you need three, the skill is doing three jobs.

## 2. Rationalization table

Anticipate the exact excuses the model will generate and pre-refute them. Binary rules
survive; "use sparingly" phrasing does not. Format:

| Excuse | Reality |
|--------|---------|
| "This is just a simple question" | Questions are tasks. The gate applies. |
| "I'm confident it works" | Confidence is not evidence. Run the command. |
| "I already spent an hour on this approach" | Sunk cost. Wrong stays wrong at any invested amount. |
| "The letter of the rule doesn't quite apply here" | Violating the letter of the rule is violating the rule. |

When a skill fails in the field, capture the exact rationalization used and add a row;
tables grow from observed failures, not speculation.

## 3. Terminal state

A process skill ends by naming its successor, not by offering a menu. "Offer next steps"
invites the model to stop; a terminal state hands off:

```
## Terminal State
This phase is complete ONLY when <artifact> exists and <check> passes.
Then invoke `<next-skill>`. Do not begin <later-phase work> from here.
```

The four flow skills chain: discover → define → develop → deliver → ship/finish-branch.
A skill that is genuinely terminal (ship, rollback) says so explicitly.

## Anti-patterns

- Stacking MANDATORY/CRITICAL on every step (emphasis inflation; each instance devalues the rest)
- Coercive injection on ambiguous triggers ("MANDATORY: invoke X before responding" — removed from the auto-router in #632; routing context is advisory)
- Workflow summaries in skill descriptions (creates a shortcut the model takes instead of loading the skill; descriptions state triggering conditions only)
