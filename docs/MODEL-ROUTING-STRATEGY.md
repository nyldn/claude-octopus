# Frontier Model Routing Strategy

Status: accepted and implemented
Decision date: 2026-07-27

## Decision

Claude Octopus uses Opus 5 as its premium lead model, GPT-5.6 Sol as the
independent coding/review peer, and Sonnet 5 as the standard Claude seat.
Fable 5 remains an explicit capability escalation rather than an automatic
default.

Fresh configurations adopt the new roster. Existing environment pins, session
overrides, and `providers.json` settings retain precedence and are not silently
rewritten.

## Roster

| Model | Default job | Standard price per MTok (input/output) |
|---|---|---:|
| Claude Opus 5 | architecture, planning, security reasoning, final judgment | $5 / $25 |
| GPT-5.6 Sol | implementation, terminal work, independent code review | $5 / $30 |
| GPT-5.6 Terra | balanced Codex alternative | $2.50 / $15 |
| GPT-5.6 Luna | budget Codex alternative | $1 / $6 |
| Claude Sonnet 5 | standard Claude orchestration and synthesis | $3 / $15 |
| Claude Haiku 4.5 | budget Claude work | $1 / $5 |
| Claude Fable 5 | opt-in judgment-class escalation | $10 / $50 |

Opus 5 and Fable 5 are both Anthropic-family models. Agreement between them
does not count as independent provider diversity.

## Routing rules

1. Start generic, mergeable work with one capable owner.
2. Add another model only for a distinct job: research, implementation,
   adversarial review, security review, or final verification.
3. Explicit debate, council, squeeze, and multi-model commands still fan out
   because disagreement is their intended output.
4. Model choice never changes permissions, repository rules, or quality gates.
5. User and project configuration always beats release defaults.

## Eval-backed routing in v10

V10 exposes deterministic routing decisions through
`octo_route_task_class` and `octo_route_decision`. These functions do not call
providers or inspect host authentication. Their checked-in oracle is
`data/routing/v10-eval-cases.json`, so policy changes require a reviewable test
case rather than an opaque runtime heuristic.

Set `routing.policy` to `"eval"` in `providers.json`, or use the
`OCTOPUS_ROUTING_POLICY=eval` session override, to apply the evaluated task
class when no higher-precedence model route exists. The model resolver
considers the task class only after environment pins, session overrides, role
and phase routes, and provider role defaults; it is more specific than generic
capability, cost-tier, and release defaults:

| Task class | Codex seat | Claude seat |
|---|---|---|
| Mechanical | GPT-5.6 Luna | Haiku 4.5 |
| Balanced | GPT-5.6 Terra | Sonnet 5 |
| Premium | GPT-5.6 Sol | Opus 5 |
| Review or security | GPT-5.6 Sol | Opus 5 |

The policy and task class are part of the model-cache key. A mechanical result
therefore cannot be reused for a later premium seat. Routing decisions report a
reason such as `eval-mechanical`, `user-pin`, `project-route`, or
`cross-vendor-verifier`.

Independent verification is a vendor-family property, not a model-name
comparison. Opus and Fable are both Anthropic-family models. If Fable or Opus
authored a result that requires independent verification, the evaluated route
selects a non-Anthropic verifier. An explicit same-family verifier pin is still
honored, but coverage is marked `degraded-same-family`.

Role defaults:

- `architect`, `strategist`, `security-reviewer`, `implementer-heavy`: current
  Opus, preferring Opus 5 on Claude Code v2.1.219+.
- `implementer`, `code-reviewer`: GPT-5.6 Sol.
- `synthesizer`: current Sonnet, preferring Sonnet 5 on Claude Code v2.1.197+.
- `researcher`: Antigravity, retaining an independent research role.

## Fallbacks

- Opus: Opus 5 → Opus 4.8 → Opus 4.7 → Opus 4.6.
- Sonnet: Sonnet 5 → Sonnet 4.6.
- Fable refusal/security fallback: Opus 5, overridable with
  `OCTOPUS_FABLE5_FALLBACK_MODEL`.
- Fable input gate: 524,288 bytes by default, overridable with
  `OCTOPUS_FABLE5_MAX_INPUT_BYTES`. An oversized prompt falls back before any
  Fable provider command is invoked and does not consume the run's single
  Fable escalation seat.
- GPT-5.6 requires Codex CLI v0.144.0 or newer.

Every Fable dispatch decision is written to the v10 run event ledger with the
requested model, resolved model, prompt bytes, phase, role, and reason. The
single escalation claim is atomic in the durable run directory, so sibling
subprocesses cannot each spend a premium seat.

## Prompt policy

For Opus 5 and Sonnet 5, prompts should state the goal, relevant context,
boundaries, reasons for unusual constraints, and checkable acceptance criteria.
Avoid duplicated reminders, all-caps emphasis without a real compliance need,
token countdowns, and requests to reveal hidden reasoning. The runtime policy
block is `skills/blocks/frontier-model-routing.md`; Fable-specific constraints
remain in `skills/blocks/fable5-prompting.md`.

## Sources

- Fable optimizer v2.0.0:
  https://github.com/nyldn/fable5-optimizer/tree/v2.0.0
- Anthropic model selection:
  https://platform.claude.com/docs/en/about-claude/models/choosing-a-model
- Opus 5 prompting:
  https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5
- Claude Code v2.1.219:
  https://github.com/anthropics/claude-code/releases/tag/v2.1.219
- GPT-5.6 model guide:
  https://developers.openai.com/api/docs/guides/latest-model
