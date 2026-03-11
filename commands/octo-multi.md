---
description: Force multi-provider parallel execution for any task - manual override mode
---

# Multi - Multi-Provider Override

**Forces multi-provider execution for any task using all available AI providers.**

## 🤖 INSTRUCTIONS FOR CLAUDE

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
        {label: "Yes, proceed (~$0.02-0.08/query)", description: "I understand this costs money via Codex + Gemini APIs"},
        {label: "Tell me more about costs", description: "Explain what I'll be charged"},
        {label: "Use free providers only", description: "Skip Codex/Gemini, use Claude only"}
      ]
    }
  ]
})
```

**After receiving answers:**

- **If user selected "Tell me more about costs"**: Explain the cost breakdown, then ask question 2 again
- **If user selected "Use free providers only"**: Explain that multi requires external providers, suggest using Claude directly instead
- **If user selected "Yes, proceed"**: Continue with multi-provider execution
- **Store intent** in context for provider selection (high-stakes → use all 3, exploring → maybe skip one if unavailable)

### Step 2: Check Provider Availability & Execute

Check which AI providers are available:

```javascript
const codexAvailable = await checkCommandAvailable('codex');
const geminiAvailable = await checkCommandAvailable('gemini');

if (!codexAvailable && !geminiAvailable) {
  console.log("⚠️ No external providers available. Multi-provider mode requires Codex and/or Gemini.");
  console.log("Run `/octo:setup` to configure external providers, or use Claude directly.");
  return;
}

// Proceed with available providers
```

Execute the task with all available providers, incorporating user intent from Step 1.

---

## Quick Usage

Just use natural language:
```
"Run this with all providers: What is Redis?"
"I want all three AI models to look at this architecture"
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
- Uses Codex CLI + Gemini CLI + Claude simultaneously
- Provides multiple perspectives when you need comprehensive analysis
- Bypasses automatic routing that might use only Claude

## What This Does

Normal Claude Octopus workflows automatically decide when to use multiple providers:
- "octo research OAuth" → automatically triggers multi-provider (probe workflow)
- "What is OAuth?" → uses Claude only (simple question)

**The multi command forces multi-provider mode even for simple tasks:**
- `/octo:multi "What is OAuth?"` → forces Codex + Gemini + Claude
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
| 🔵 Claude | Included | Claude Code subscription |

**Total cost per forced query: ~$0.02-0.08**

Use judiciously for tasks where multiple perspectives add value. For routine work, let automatic routing decide when multi-provider is beneficial.

## Natural Language Alternatives

You can also force parallel mode with natural language:
- "run this with all providers: [task]"
- "I want all three AI models to look at [topic]"
- "get multiple perspectives on [question]"
- "use all providers for [analysis]"
- "force multi-provider analysis of [topic]"

## Examples

**Force parallel for simple question:**
```
/octo:multi "What is the difference between OAuth and JWT?"
```
→ Gets perspectives from Codex, Gemini, and Claude even though Claude could answer alone

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
🔵 Claude - [Role in this task]
```

Then you'll see results from each provider marked with their indicator (🔴 🟡 🔵).

## See Also

- `/octo:debate` - Structured three-way debates (better for adversarial analysis)
- `/octo:research` - Research workflow (auto-triggers multi-provider for research)
- `/octo:review` - Review workflow (auto-triggers multi-provider for validation)
- [COMMAND-REFERENCE.md](../../docs/COMMAND-REFERENCE.md#natural-language-triggers) - Activation rules and forced multi-provider guidance
