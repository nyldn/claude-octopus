# GPT-5.4 Prompting Guide (for Octopus Dispatchers)

Condensed from the official OpenAI GPT-5.4 prompt guidance:
<https://developers.openai.com/api/docs/guides/prompt-guidance>

Consulted by `lib/dispatch.sh` Codex prompt builders and by the `code-reviewer`, `implementer`, and `python-pro`/`typescript-pro` personas. Keep edits synchronized with upstream OpenAI guidance.

## 1. Reasoning Effort

GPT-5.4 supports five effort levels: `none` < `low` < `medium` < `high` < `xhigh`. Higher ≠ better output — it just trades latency + cost for depth.

| Effort  | When to use                                                          |
|---------|----------------------------------------------------------------------|
| `none`  | Extraction, classification, triage. Speed > depth.                   |
| `low`   | Latency-sensitive tasks with a minor reasoning component.            |
| `medium`| Default for most Octopus phases (probe, grasp, review).              |
| `high`  | Complex implementation (tangle, security analysis).                  |
| `xhigh` | Long agentic loops only. Expensive. Reserve for multi-step work.     |

**Rule:** Before raising effort, tighten the prompt first. Stronger output contracts beat higher effort for most failures.

## 2. Output Contracts

Constrain structure and volume explicitly. GPT-5.4 tends toward verbose prose by default.

```
Return ONLY these sections, in this order:
- Summary (1 sentence)
- Findings (bulleted, max 5)
- Recommendation (1 sentence)

Do not add preamble. Do not wrap in markdown fences unless requested.
Prefer concise, information-dense writing.
```

For structured output (JSON, SQL, patch files): explicitly say "Output only the requested format. No prose. No markdown fences unless requested."

## 3. Tool Persistence

GPT-5.4 will sometimes stop at the first plausible answer. For agentic loops:

```
Use tools whenever they materially improve correctness.
Do not stop early if another tool call is likely to improve the answer.
Parallelize independent retrieval steps. Sequence dependent work.
Do not skip prerequisite steps just because the final action seems obvious.
```

## 4. `phase` Field in Multi-Step Loops

When replaying prior assistant turns, preserve `phase` metadata. Missing `phase` causes GPT-5.4 to misinterpret working commentary as a final answer.

- `phase=working` → intermediate thinking, tool output summarization
- `phase=final`   → user-facing answer

`lib/dispatch.sh` already tags Octopus tangle/ink iterations with phase markers — keep these intact when composing multi-turn prompts.

## 5. Instruction Priority

Explicit hierarchies prevent drift:

```
Priority order (highest first):
1. Safety and honesty constraints
2. The most recent user instruction
3. Earlier instructions in this conversation
4. Style / tone defaults

If a newer instruction conflicts with an earlier one, follow the newer.
```

When updating a plan mid-conversation, state scope (what's replaced), override (what's new), and what carries forward.

## 6. Anti-Patterns

- **Empty-result acceptance.** Don't conclude "no matches" without a retry fallback.
- **Skipped prerequisites.** Multi-step workflows commonly skip setup steps.
- **Effort over prompt.** Users frequently crank effort instead of tightening prompt; usually prompt wins.
- **Implicit ambiguity.** For `gpt-5.4-mini`, enumerate every edge case — don't rely on "you MUST".
- **Unbounded verbosity.** GPT-5.4 is chatty by default. Always set output contracts.

## 7. `gpt-5.4-mini` (Budget Tier)

Mini is ~10x cheaper ($0.25/$2 MTok) but brittle to implicit instructions:

- Put critical rules first, before context.
- Use numbered steps for tool-use workflows.
- Specify edge cases and ambiguity behavior explicitly.
- Prefer structural scaffolding ("Step 1: …  Step 2: …") over narrative prose.

## 8. Octopus-Specific Notes

- **`/octo:review`** — dispatches to GPT-5.4 by default (edge-case strength). Use `effort=medium` + output contract requiring `severity`, `file:line`, `rationale`.
- **`/octo:security`** — routes to Claude Opus 4.7 by default (adversarial reasoning). Skip this guide for that path.
- **`/octo:develop`** — Codex dispatchers auto-inject the output contract block for patch generation. Don't add a second "no preamble" instruction — it's already there.
- **Cost ceiling** — `xhigh` effort ~2x `high` latency and cost. Only set `xhigh` when the user invoked `/octo:deep` or the task type is `security` / `architecture-heavy`.

## Maintenance

When OpenAI updates the official guide, refresh this document. Tag the version in the first git-log entry. Callers reference this path directly — don't rename without updating:

```
grep -rn 'GPT-5.4-PROMPTING\.md' plugin/
```
