---
description: "\"[advanced] Force multi-provider parallel execution for any task - manual override mode\""
---

# Multi - Multi-Provider Override

**Forces multi-provider execution for any task using all available AI providers.**

## 🤖 INSTRUCTIONS FOR CLAUDE

### EXECUTION MECHANISM — NON-NEGOTIABLE

**You MUST dispatch work to external providers (Codex, Gemini, Antigravity, etc.) for this command. You are PROHIBITED from:**
- ❌ Executing the entire task using only Claude-native tools
- ❌ Using a single Agent subagent instead of multi-provider dispatch
- ❌ Skipping provider dispatch because "I can handle this alone"

**Multi-LLM orchestration is the purpose of this command.** Single-model execution defeats its purpose.

When the user invokes this command (e.g., `/octo:multi <task>`):

### Step 1: Cost Awareness & Intent Confirmation

**CRITICAL: Before forcing multi-provider execution, use AskUserQuestion to confirm intent and cost awareness:**

```javascript
AskUserQuestion({
  questions: [
    {
      question: "Why do you need multiple AI perspectives?",
      header: "Intent",
      multiSelect: false,
      options: [
        {label: "High-stakes decision", description: "Critical choice requiring comprehensive analysis"},
        {label: "Quality validation", description: "Cross-check important work for accuracy"},
        {label: "Learning different approaches", description: "See how different models think"},
        {label: "Comparing perspectives", description: "Want to see model-specific insights"},
        {label: "Just exploring", description: "Curious about multi-AI capabilities"}
      ]
    },
    {
      question: "Are you aware this uses external API credits?",
      header: "Cost",
      multiSelect: false,
      options: [
        {label: "Yes, proceed", description: "I understand this may use external provider credits or subscriptions"},
        {label: "Tell me more about costs", description: "Explain what I'll be charged"},
        {label: "Use included/local providers only", description: "Use Claude plus providers that do not add per-query API charges"}
      ]
    }
  ]
})
```

**WAIT for the user's answers before proceeding.**

**After receiving answers:**

- **If user selected "Tell me more about costs"**: Explain the cost breakdown, then ask question 2 again
- **If user selected "Use included/local providers only"**: Use Claude plus available included/local providers such as Antigravity, Copilot, Qwen, Ollama, or already-authenticated CLIs; explain any unavailable providers
- **If user selected "Yes, proceed"**: Continue with multi-provider execution
- **Store intent** in context for provider selection (high-stakes → use all available providers, exploring → maybe skip one if unavailable)

### Step 2: Check Provider Availability & Execute

Check which AI providers are available:

```javascript
const codexAvailable = await checkCommandAvailable('codex');
const geminiAvailable = await checkCommandAvailable('gemini');
const agyAvailable = await checkCommandAvailable('agy');
const copilotAvailable = await checkCommandAvailable('copilot');
const qwenAvailable = await checkCommandAvailable('qwen');
const opencodeAvailable = await checkCommandAvailable('opencode');
const ollamaAvailable = await checkCommandAvailable('ollama');
const anyProviderAvailable = [
  codexAvailable,
  geminiAvailable,
  agyAvailable,
  copilotAvailable,
  qwenAvailable,
  opencodeAvailable,
  ollamaAvailable
].some(Boolean);

if (!anyProviderAvailable) {
  console.log("⚠️ No external providers available. Multi-provider mode requires at least one supported provider.");
  console.log("Run `/octo:setup` to configure external providers, or use Claude directly.");
  return;
}

// Proceed with available providers
```

Execute the task with all available providers, incorporating user intent from Step 1.

### Step 3: Adversarial Synthesis (MANDATORY — do NOT skip)

**After collecting responses from all providers, you MUST synthesize — not concatenate.**

The whole point of multi-provider execution is diversity of opinion. Presenting provider responses back-to-back without synthesis defeats this purpose. You MUST produce a structured synthesis with these sections:

1. **Consensus** — Where providers agree. State the shared conclusion and note how many providers converged on it.
2. **Divergence** — Where providers disagree. Quote each provider's position verbatim so the user sees the actual disagreement, not a smoothed-over summary.
3. **Resolution** — Your confidence-weighted recommendation resolving the conflicts. State your confidence level (high/medium/low) and WHY you side with one position over another. If you cannot resolve, say so — an honest "this depends on your context" is better than a false consensus.
4. **Minority Opinions** — Dissenting views that may be valuable even if outnumbered. A single provider flagging a security risk or edge case that others missed is often the most valuable insight.

**Present this synthesis in the chat using this format:**

```markdown
## Multi-Provider Synthesis

### Consensus
[Where all providers agree]

### Divergence
- 🔴 **Codex**: "[direct quote or close paraphrase]"
- 🟡 **Gemini**: "[direct quote or close paraphrase]"
- 🔵 **Claude**: "[direct quote or close paraphrase]"

### Resolution
[Your recommendation with confidence level and reasoning]

### Minority Opinions
[Dissenting views worth preserving — or "None: all providers converged"]
```

**Skip this step with `--fast` or when user explicitly requests speed over thoroughness.** In fast mode, present raw provider responses without synthesis.

---

## Quick Usage

Just use natural language:
```
"Run this with all providers: What is Redis?"
"I want multiple AI models to look at this architecture"
"Get multiple perspectives on whether to use TypeScript"
"Force multi-provider analysis of this design decision"
```

Or use explicit commands:
```
/octo:multi "Explain how OAuth works"
/octo:multi "Review this simple function"
/octo:multi "What is JWT?"
```

## How It Works

This command activates the multi-provider skill in **forced mode**, which:
- Executes multi-provider analysis even for simple tasks
- Uses Claude plus all available external providers, including Codex, Gemini, and Antigravity when installed
- Provides multiple perspectives when you need comprehensive analysis
- Bypasses automatic routing that might use only Claude

## What This Does

Normal Claude Octopus workflows automatically decide when to use multiple providers:
- "octo research OAuth" → automatically triggers multi-provider (probe workflow)
- "What is OAuth?" → uses Claude only (simple question)

**The multi command forces multi-provider mode even for simple tasks:**
- `/octo:multi "What is OAuth?"` → forces Claude plus available external providers
- "Run this with all providers: Explain Redis" → forces multi-provider execution

## When to Use

Use forced parallel mode when:
- **High-stakes decisions** requiring comprehensive analysis from multiple models
- **Comparing perspectives** - you want to see how different models approach the same problem
- **Simple questions with depth** - seemingly simple questions that deserve thorough analysis
- **Learning different approaches** - exploring how each model thinks about a topic

Don't use forced parallel mode when:
- Task already auto-triggers workflows (octo research, octo build, octo review)
- Simple factual questions Claude can answer reliably
- Cost efficiency is important (external CLIs cost ~$0.02-0.08 per query)

## Cost Awareness

Forcing parallel mode uses external CLIs for every task:

| Provider | Cost per Query | What It Uses |
|----------|----------------|--------------|
| 🔴 Codex CLI | ~$0.01-0.05 | Your OPENAI_API_KEY |
| 🟡 Gemini CLI | ~$0.01-0.03 | Your GEMINI_API_KEY |
| 🧭 Antigravity CLI (`agy`) | Included with access/subscription | Antigravity CLI auth |
| 🔵 Claude | Included | Claude Code subscription |

**Total cost per forced query: ~$0.02-0.08**

Use judiciously for tasks where multiple perspectives add value. For routine work, let automatic routing decide when multi-provider is beneficial.

## Natural Language Alternatives

You can also force parallel mode with natural language:
- "run this with all providers: [task]"
- "I want multiple AI models to look at [topic]"
- "get multiple perspectives on [question]"
- "use all providers for [analysis]"
- "force multi-provider analysis of [topic]"

## Examples

**Force parallel for simple question:**
```
/octo:multi "What is the difference between OAuth and JWT?"
```
→ Gets perspectives from Claude plus available external providers even though Claude could answer alone

**Force parallel for architecture decision:**
```
"Run this with all providers: Should we use microservices or monolith?"
```
→ Forces comprehensive multi-model analysis for critical decision

**Force parallel for code review:**
```
/octo:multi "Review this simple helper function for edge cases"
```
→ Gets thorough review from multiple models even for small code

## What You'll See

When the multi command activates, you'll see the visual indicator banner:

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider mode
Force parallel execution

Providers:
🔴 Codex CLI - [Role in this task]
🟡 Gemini CLI - [Role in this task]
🧭 Antigravity CLI - [Role in this task]
🔵 Claude - [Role in this task]
```

Then you'll see results from each provider marked with its indicator (for example 🔴 🟡 🧭 🔵).

## See Also

- `/octo:debate` - Structured provider debates (better for adversarial analysis)
- `/octo:research` - Research workflow (auto-triggers multi-provider for research)
- `/octo:review` - Review workflow (auto-triggers multi-provider for validation)
- [TRIGGERS.md](../../docs/TRIGGERS.md) - Full guide to what triggers multi-provider mode
