# Steelman Arguments Against Multi-Provider Orchestration

This document presents the strongest case **against** using Claude Octopus for your workflow. These are genuine, well-reasoned critiques — not strawmen. If you're considering multi-provider orchestration, you should understand these trade-offs before committing.

> Inspired by [Overstory's STEELMAN.md](https://github.com/jayminwest/overstory/blob/main/STEELMAN.md), which documents honest risks of multi-agent swarms.

## 1. A Single Focused Model Usually Wins

Claude Sonnet 4.6 or Opus 4.6 alone handles most software engineering tasks at or above human expert level. Adding Codex and Gemini perspectives adds cost and latency without proportionally improving output quality.

The research is clear: for well-scoped tasks with clear requirements, a single strong model outperforms a committee. Multi-provider orchestration shines only in the narrow band where the task is ambiguous enough that perspectives differ meaningfully, but structured enough that those differences can be synthesized into a coherent answer.

**When to skip orchestration:** Bug fixes, straightforward features, code formatting, documentation updates, test writing, and any task where you already know the right approach.

## 2. Cost Amplification Is Real

Every `/octo:embrace` workflow invokes at minimum 5-6 external CLI calls. At typical pricing:

| Provider | Per-query cost | Notes |
|----------|---------------|-------|
| Codex (GPT-5.3) | $0.05–0.15 | Uses your OPENAI_API_KEY |
| Gemini (3 Pro) | $0.01–0.03 | Uses your GEMINI_API_KEY |
| Claude (Sonnet 4.6) | Included | Part of Claude Code subscription |
| Claude (Opus 4.6) | $0.10–0.50 | Extra-usage billing |
| Claude (Opus 4.6 Fast) | $0.60–3.00 | 6x Opus pricing |

A full embrace workflow that spawns 6 agents across providers can cost $0.50–2.00 in external API charges. Running `/octo:research` three times a day adds $1–5/day. Over a month, that's $30–150 in API costs on top of your Claude Code subscription.

Compare: a single Claude prompt handling the same task costs $0.00 (included in subscription) and completes in 30 seconds instead of 3 minutes.

## 3. Coordination Overhead Exceeds Value for Simple Tasks

The Double Diamond methodology (Discover → Define → Develop → Deliver) adds structure that benefits complex, ambiguous problems. For most daily development tasks, it's overhead:

- **Discover phase** spawns 5-6 parallel agents to research a question you might already know the answer to
- **Define phase** builds consensus on an approach when there's often only one reasonable approach
- **Develop phase** validates implementation against perspectives that may not meaningfully differ
- **Deliver phase** reviews code that was already written correctly the first time

The ceremony of multi-phase workflows can feel productive while producing the same output as a single well-crafted prompt.

**Use `/octo:quick` instead of `/octo:embrace`** when the task is clear and well-defined.

## 4. Provider Inconsistency Creates False Debates

Different AI models sometimes disagree not because they have genuinely different insights, but because they interpret ambiguous prompts differently, have different training data, or exhibit different calibration characteristics.

Example: You ask three providers about database choice for a new service. Codex recommends PostgreSQL (because OpenAI training data skews toward it). Gemini recommends Cloud Spanner (because Google training data favors Google products). Claude recommends DynamoDB (because the prompt mentioned "serverless"). The "debate" is not three experts with different expertise — it's three models with different biases confusing each other.

The synthesis may sound authoritative ("after weighing all perspectives...") while actually being a diplomatic average of three biased opinions. A single expert model with a well-crafted prompt often produces a more coherent, defensible recommendation.

## 5. Context Fragmentation Across Providers

Each provider receives a compressed version of your prompt. The nuance, history, and implicit context of your Claude Code session — your CLAUDE.md, recent edits, project structure — are not available to Codex or Gemini. They operate on a lossy summary.

This means:
- **Codex** gives generic advice that doesn't account for your specific codebase patterns
- **Gemini** may suggest approaches incompatible with your existing architecture
- **Claude** has full context but its synthesis is constrained by the other providers' decontextualized responses

The "multi-perspective" advantage is diluted when two of three perspectives lack the context to be genuinely useful.

## 6. Debugging Multi-Provider Failures Is Hard

When an `/octo:embrace` workflow produces a bad result, diagnosing where it went wrong requires:

1. Reading the probe synthesis to see what each provider found
2. Checking the grasp consensus to see if the wrong approach was selected
3. Reviewing the tangle validation to see if quality gates caught the issue
4. Inspecting individual provider outputs in `~/.claude-octopus/results/`

Compare: a single Claude conversation has a linear transcript you can scroll through. The debugging surface area scales linearly with the number of providers involved.

## 7. External CLI Dependencies Are Fragile

Octopus depends on Codex CLI, Gemini CLI, and their respective API keys being correctly configured and authenticated. Each is an independent failure point:

- Codex CLI updates can break argument parsing
- Gemini CLI's approval modes and output formats change between versions
- API keys expire, rate limits hit, billing accounts get suspended
- Network issues affect external providers but not local Claude

Every external dependency is a maintenance burden and a source of intermittent failures that are hard to reproduce and debug.

## 8. The Consensus Illusion

When three AI providers agree, it feels like strong validation. But AI models are trained on overlapping data and share similar reasoning patterns. Agreement among AI models is not the same as agreement among independent human experts.

Three AI providers agreeing that "you should use JWT for authentication" doesn't carry the same epistemic weight as three security engineers independently reaching that conclusion. The models may all be wrong in the same way because they learned from the same Stack Overflow answers.

True validation requires human review. Multi-provider consensus can create false confidence that reduces the likelihood of human scrutiny.

## 9. Latency Compounds User Frustration

A single Claude response takes 5–15 seconds. An orchestrated workflow takes 60–180 seconds:

- Provider detection and preflight: ~5s
- Parallel agent spawning: ~10s
- External CLI execution (Codex): ~15–30s
- External CLI execution (Gemini): ~10–20s
- Claude synthesis: ~10–15s
- Quality gates and validation: ~5–10s

During this time, you're waiting. For interactive development where you're iterating rapidly, 3 minutes per question fundamentally changes your workflow from "conversational" to "batch processing."

## 10. Plugin Complexity as Attack Surface

Octopus adds hooks (PreToolUse, PostToolUse, SessionStart), a scheduler daemon, state management files, and external CLI invocations. Each is a surface for:

- Hook scripts that fail silently and corrupt workflow state
- Scheduler jobs that run unattended and accumulate costs
- State files that become stale and mislead future sessions
- External CLIs that receive your prompts (potential data leakage to OpenAI/Google)

The principle of least privilege suggests: use the minimum tooling necessary. If Claude alone handles your task, adding two more AI providers and an orchestration layer violates this principle.

## When Multi-Provider Orchestration Is Worth It

Despite these critiques, there are **genuine use cases** where orchestration provides value that a single model cannot:

1. **High-stakes architectural decisions** — When the cost of a wrong decision exceeds the cost of orchestration. Database choice for a 5-year system. Authentication architecture for a security-sensitive application.

2. **Genuinely ambiguous problems** — When you don't know what you don't know. Exploring a new domain. Evaluating unfamiliar technologies. Research where breadth matters more than depth.

3. **Adversarial review** — When you need a devil's advocate. Security audits where one model attacks and another defends. Code reviews where blind spots in one model are caught by another.

4. **Creative exploration** — Brainstorming, design ideation, and strategic planning where diverse perspectives genuinely expand the solution space.

5. **Bias detection** — When you suspect a single model's recommendation is influenced by training data bias (e.g., always recommending the same framework).

## The Right Default

**Start with Claude alone. Escalate to orchestration when you hit a wall.**

Use `/octo:quick` for daily tasks. Reserve `/octo:embrace` for decisions that warrant the cost and latency. Use `/octo:debate` when you genuinely need adversarial perspectives, not for every code review.

The best orchestration is the one you don't run when you don't need it.
