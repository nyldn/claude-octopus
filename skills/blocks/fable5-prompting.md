# Fable 5.1 Dispatch Profile

Apply this block whenever a workflow authors a prompt for Claude Fable 5.1 or the preserved Fable 5 model ID. Current pins use `OCTOPUS_OPUS_MODEL=claude-fable-5-1` or `OCTOPUS_CLAUDE_SDK_MODEL=claude-fable-5-1`; existing `claude-fable-5` pins keep working. Fable follows instructions more strongly than Opus 5 and runs additional safety classifiers. Prompts tuned for older models can degrade its output or trigger refusals.

Source: Anthropic's Fable 5.1 overview
(https://platform.claude.com/docs/en/models/fable-5-1/overview).

## Prompt anti-patterns (remove before dispatch)

- **Reasoning-echo instructions.** Never ask Fable 5 to reveal, transcribe, reproduce, or explain its internal reasoning in the response. This can trigger the `reasoning_extraction` refusal category (`stop_reason: "refusal"`). Ask for the useful rationale or decision instead. If reasoning visibility is needed, read adaptive-thinking blocks, not response text.
- **Token or context countdowns.** Surfacing remaining-token counts makes Fable 5 wrap up early, summarize, or suggest a new session. Omit them; if the harness must show one, add: "You have ample context remaining. Do not stop, summarize, or suggest a new session on account of context limits."
- **Aggressive trigger language.** "CRITICAL", "MUST", all-caps emphasis — only when strict compliance is actually required. Fable 5's instruction following is strong enough that a plain sentence steers it; shouting increases over-compliance and scope creep.
- **Micromanaged step-by-step plans.** Where a boundary plus checkable acceptance criteria suffice, use those. Over-prescriptive skills written for older models can degrade Fable 5 output; prefer stating the goal, the constraints, and what must not change.
- **Enumerated behavior lists.** One brief instruction ("lead with the outcome; drop details that don't change what the reader does next") replaces a list of banned patterns.

## Prompt patterns (add where relevant)

- **Grounded progress claims** (long or autonomous runs): "Before reporting progress, audit each claim against a tool result from this session. Only report work you can point to evidence for; if something is not yet verified, say so explicitly."
- **Act-when-ready** (ambiguous tasks): "When you have enough information to act, act. Do not re-derive established facts, re-litigate settled decisions, or narrate options you will not pursue. If weighing a choice, give a recommendation, not a survey."
- **Scope discipline** (higher effort): "Don't add features, refactor, or introduce abstractions beyond what the task requires. Do the simplest thing that works well."
- **Give the reason, not only the request.** Fable 5 performs better knowing intent: "I'm working on [larger task] for [who]. They need [what the output enables]. With that in mind: [request]."

## Effort discipline

Run Fable at `high` effort by default. Do not default to `xhigh` or `max`: effort applies per tool call and per change, not to how long the model can work, so higher settings do not extend runs. Set `OCTOPUS_FABLE5_MAX_EFFORT=xhigh|max` only for a bounded capability-sensitive step. This raises the effort ceiling without disabling the security, input, or refusal guards. Opus 5 effort recommendations do not carry over to a Fable pin.

## Refusal handling and routing

orchestrate.sh auto-detects either Fable pin (`scripts/lib/fable5.sh`) and enforces the routing rules below without user action, printing a one-line banner: security dispatches reroute to Opus 5 by default (model resolver + dispatch), effort clamps to the configured ceiling, and the claude-sdk shim retries a refused or empty Fable dispatch once on the same fallback. `OCTOPUS_FABLE5_FALLBACK_MODEL` replaces the default Opus 5 target for both the security reroute and SDK retry. Master switch: `OCTOPUS_FABLE5_MODE=auto|off|on` (default `auto`); retry opt-out: `OCTOPUS_FABLE5_NO_RETRY=1`. The prompt-hygiene rules above are not machine-enforced; apply them when authoring dispatch prompts.

- Fable 5 runs safety classifiers targeting offensive cybersecurity (exploit construction, malware, attack tooling), biology/life-sciences methods, and reasoning extraction. Benign security work can also trip them.
- **Security-audit dispatches must not target Fable.** When either Fable model is pinned, route adversarial security passes (`/octo:security`, security-auditor agents) to `claude-opus-5` and frame prompts defensively (find and report vulnerabilities; do not request working exploits).
- On `stop_reason: "refusal"` or an in-band refusal from a Fable 5 dispatch, retry the same prompt once on the configured fallback (`claude-opus-5` by default) rather than rewording toward the classifier.

## Judgment routing

Fable 5 earns its 2x-Opus cost on judgment, not mechanics: ambiguous architecture, API design, product tradeoffs, final plan or implementation judgment, synthesis across conflicting provider outputs. Mechanical work (migrations, repetitive edits, bulk review, glue summaries) belongs on cheaper seats. Cheap-seat agreement never settles a judgment-class decision. Regardless of the routing table, escalate to the premium Claude seat when a change touches a risk surface: API or schema contracts, security-sensitive code or CI configuration, release artifacts, user-facing UI, a new module, or a breaking change. The broader roster and single-owner policy live in `skills/blocks/frontier-model-routing.md`.
