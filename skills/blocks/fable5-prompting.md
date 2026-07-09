# Fable 5 Dispatch Profile

Apply this block whenever a workflow authors a prompt for Claude Fable 5 — that is, when `OCTOPUS_OPUS_MODEL=claude-fable-5` or `OCTOPUS_CLAUDE_SDK_MODEL=claude-fable-5` is pinned, or a dispatch explicitly targets `claude-fable-5`. Fable 5 (Mythos-class) follows instructions more strongly than Opus 4.8 and runs safety classifiers that earlier Claude models do not. Prompts tuned for older models can degrade its output or trigger refusals.

Source: Anthropic's Fable 5 prompting guide
(https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5).

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

Run Fable 5 at `high` effort by default. Do not default to `xhigh` or `max`: effort applies per tool call and per change, not to how long the model can work, so higher settings do not extend runs — they make each step overthink and produce broader changes than asked. Lower effort on Fable 5 still often exceeds `xhigh` on prior models. Raise effort only for a specific capability-sensitive step. The Opus 4.8 `xhigh` recommendations in CLAUDE.md (tangle/ink deep work) do not carry over to a Fable 5 pin.

## Refusal handling and routing

- Fable 5 runs safety classifiers targeting offensive cybersecurity (exploit construction, malware, attack tooling), biology/life-sciences methods, and reasoning extraction. Benign security work can also trip them.
- **Security-audit dispatches must not target Fable 5.** When `OCTOPUS_OPUS_MODEL=claude-fable-5` is pinned, route adversarial security passes (`/octo:security`, security-auditor agents) to `claude-opus-4.8` and frame prompts defensively (find and report vulnerabilities; do not request working exploits).
- On `stop_reason: "refusal"` or an in-band refusal from a Fable 5 dispatch, retry the same prompt on `claude-opus-4.8` rather than rewording toward the classifier.

## Judgment routing

Fable 5 earns its 2x-Opus cost on judgment, not mechanics: ambiguous architecture, API design, product tradeoffs, final plan or implementation judgment, synthesis across conflicting provider outputs. Mechanical work (migrations, repetitive edits, bulk review, glue summaries) belongs on cheaper seats. Cheap-seat agreement never settles a judgment-class decision. Regardless of the routing table, escalate to the premium Claude seat when a change touches a risk surface: API or schema contracts, security-sensitive code or CI configuration, release artifacts, user-facing UI, a new module, or a breaking change.
