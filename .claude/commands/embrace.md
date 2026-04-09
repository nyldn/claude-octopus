---
command: embrace
description: "Full Double Diamond workflow - Research → Define → Develop → Deliver"
aliases:
  - full-cycle
  - complete-workflow
---

# Embrace - Complete Double Diamond Workflow

**Your first output line MUST be:** `🐙 Octopus Embrace`

## MANDATORY COMPLIANCE — DO NOT SKIP

**When the user invokes `/octo:embrace`, you MUST execute the full multi-LLM workflow below. You are PROHIBITED from:**
- Deciding the task is "too simple" for the workflow
- Doing the task directly instead of running the phases
- Skipping phases because you judge them unnecessary
- Substituting your own approach for the structured workflow

**The user chose `/octo:embrace` deliberately.** Respect that choice.

## EXECUTION MECHANISM — NON-NEGOTIABLE

**Each phase MUST be executed by invoking the corresponding skill using the Skill tool. You are PROHIBITED from:**
- Using the Agent tool to do research yourself instead of invoking `/octo:discover`
- Using WebFetch/Read/Grep as a substitute for multi-provider research
- Implementing code directly instead of invoking `/octo:develop`
- Using a single code-reviewer agent instead of invoking `/octo:deliver`
- Skipping `orchestrate.sh` calls because "I can do this faster directly"

**The ENTIRE POINT of `/octo:embrace` is multi-LLM orchestration.** If you execute phases using only Claude-native tools (Agent, WebFetch, Write, Edit), you have violated the command's purpose even if you followed the phase structure.

**Self-check after completion:** You should be able to list the Skill invocations and orchestrate.sh commands you ran. If you used only Claude-native tools, you executed incorrectly.

---

## Step 1: Ask Clarifying Questions

```javascript
AskUserQuestion({
  questions: [
    {
      question: "What's the scope of this project?",
      header: "Scope",
      multiSelect: false,
      options: [
        {label: "Small feature", description: "Single component or small addition"},
        {label: "Medium feature", description: "Multiple components or moderate complexity"},
        {label: "Large feature", description: "System-wide changes or new subsystem"},
        {label: "Full system", description: "Complete application or major architecture"}
      ]
    },
    {
      question: "What areas require the most attention?",
      header: "Focus Areas",
      multiSelect: true,
      options: [
        {label: "Architecture design", description: "System structure and design patterns"},
        {label: "Security", description: "Authentication, authorization, data protection"},
        {label: "Performance", description: "Speed, scalability, optimization"},
        {label: "User experience", description: "UI/UX and usability"}
      ]
    },
    {
      question: "What's your preferred level of autonomy?",
      header: "Autonomy",
      multiSelect: false,
      options: [
        {label: "Supervised (default)", description: "Review and approve after each phase"},
        {label: "Semi-autonomous", description: "Only intervene if quality gates fail"},
        {label: "Autonomous", description: "Run all 4 phases automatically"},
        {label: "Manual", description: "I'll guide each step explicitly"}
      ]
    },
    {
      question: "Should critical decisions be stress-tested with a Multi-LLM debate?",
      header: "Multi-LLM Debate Gates",
      multiSelect: false,
      options: [
        {label: "Yes — debate at Define→Develop gate", description: "Recommended for Large/Full scope"},
        {label: "Yes — debate at both gates", description: "Maximum rigor, uses external API credits"},
        {label: "No — skip debates", description: "Standard workflow without debate checkpoints"},
        {label: "Only if disagreement detected", description: "Auto-trigger when providers diverge"}
      ]
    }
  ]
})
```

After receiving answers, incorporate them into all subsequent phase invocations — use the scope to calibrate research depth, focus areas to weight provider perspectives, autonomy level to control phase transitions, and debate preference to gate Define→Develop handoffs.

## Step 2: Check Provider Availability & Display Banner

**MANDATORY: Run this bash command BEFORE the banner.**

```bash
echo "PROVIDER_CHECK_START"
printf "codex:%s\n" "$(command -v codex >/dev/null 2>&1 && echo available || echo missing)"
printf "gemini:%s\n" "$(command -v gemini >/dev/null 2>&1 && echo available || echo missing)"
printf "perplexity:%s\n" "$([ -n "${PERPLEXITY_API_KEY:-}" ] && echo available || echo missing)"
printf "opencode:%s\n" "$(command -v opencode >/dev/null 2>&1 && echo available || echo missing)"
printf "copilot:%s\n" "$(command -v copilot >/dev/null 2>&1 && echo available || echo missing)"
printf "qwen:%s\n" "$(command -v qwen >/dev/null 2>&1 && echo available || echo missing)"
printf "ollama:%s\n" "$(command -v ollama >/dev/null 2>&1 && curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && echo available || echo missing)"
printf "openrouter:%s\n" "$([ -n "${OPENROUTER_API_KEY:-}" ] && echo available || echo missing)"
echo "PROVIDER_CHECK_END"
```

Display banner with ACTUAL results:

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Full Double Diamond Workflow
🐙 Embrace: [Brief description]

Phases: 🔍 Discover → 🎯 Define → 🛠️ Develop → ✅ Deliver

Provider Availability:
🔴 Codex CLI: [status]    🟡 Gemini CLI: [status]
🟣 Perplexity: [status]   🟤 OpenCode: [status]
🔵 Claude: Available ✓

Scope: [answer]  Focus: [answer]  Autonomy: [answer]
```

## Step 3: Execute Phases via Skill Invocations

**CRITICAL: Each phase MUST be invoked as a separate skill. This ensures each phase's full enforcement instructions (including orchestrate.sh dispatch) load fresh into context.**

### Phase 1 — Discover

Invoke the discover skill:
```
Skill(skill: "octo:discover", args: "<user's prompt>")
```

This will dispatch to Codex, Gemini, and other available providers via `orchestrate.sh probe-single`. Results saved to `~/.claude-octopus/results/probe-synthesis-*.md`.

**Supervised mode:** After Discover completes, present key findings and ask to proceed.
**Semi-autonomous/Autonomous:** Proceed automatically.

### Phase 2 — Define

Invoke the define skill:
```
Skill(skill: "octo:define", args: "<user's prompt>")
```

This builds consensus across providers via `orchestrate.sh`. Results saved to `~/.claude-octopus/results/grasp-consensus-*.md`.

**Supervised mode:** Present consensus and ask to proceed.

### Debate Gate (if enabled)

If user selected debate gates at Define→Develop transition:
1. Read consensus from `~/.claude-octopus/results/grasp-consensus-*.md`
2. Run a quick adversarial debate challenging the approach:

```
Skill(skill: "octo:debate", args: "Given this consensus, what are the biggest risks? What alternatives were dismissed too quickly? --rounds 1 --debate-style adversarial --max-words 200")
```

3. If risks surface, present via AskUserQuestion:
```javascript
AskUserQuestion({
  questions: [{
    question: "The debate gate surfaced concerns. How should we proceed?",
    header: "Debate Gate",
    multiSelect: false,
    options: [
      {label: "Proceed anyway", description: "Accept risks and continue to Develop"},
      {label: "Revise approach", description: "Adjust plan based on debate findings"},
      {label: "Run deeper debate", description: "Thorough 3-round debate before deciding"},
      {label: "Stop and review", description: "Pause for manual review"}
    ]
  }]
})
```

### Phase 3 — Develop

Invoke the develop skill:
```
Skill(skill: "octo:develop", args: "<user's prompt>")
```

This dispatches implementation via `orchestrate.sh tangle` with quality gates. Results saved to `~/.claude-octopus/results/tangle-validation-*.md`.

### Second Debate Gate (if "both gates" selected)

Same pattern as above but collaborative style, reviewing implementation quality.

### Phase 4 — Deliver

Invoke the deliver skill:
```
Skill(skill: "octo:deliver", args: "<user's prompt>")
```

This runs multi-provider validation via `orchestrate.sh ink`. Results saved to `~/.claude-octopus/results/delivery-*.md`.

### Auto Code Review (MANDATORY)

After Develop completes, launch two verification agents in background:

```
Agent(model: "sonnet", subagent_type: "feature-dev:code-reviewer", run_in_background: true,
  description: "Code review: embrace deliver",
  prompt: "Review all code changes from this session. Check git diff. Focus on bugs, security, logic errors. Report only high-confidence issues.")

Agent(model: "sonnet", run_in_background: true,
  description: "E2E test: embrace deliver",
  prompt: "Run the project's test suite and verify no regressions. Report tests passed/failed.")
```

Include findings in final results.

## Step 4: Present Results & Next Steps

**MANDATORY: Present results AND ask what to do next.**

Read result files from `~/.claude-octopus/results/` and present a concise synthesis. Then:

```javascript
AskUserQuestion({
  questions: [{
    question: "The embrace workflow has completed all 4 phases. What next?",
    header: "Next Steps",
    multiSelect: false,
    options: [
      {label: "Review phase outputs in detail", description: "Walk through each phase's findings"},
      {label: "Refine the implementation", description: "Make adjustments based on results"},
      {label: "Run another iteration", description: "Re-run specific phases with updated context"},
      {label: "Start a new task", description: "Move on to something else"},
      {label: "Export results", description: "Save a summary document"}
    ]
  }]
})
```

**PROHIBITED: Ending the session without asking this question.**

---

## Quick Reference

| Phase | Skill | orchestrate.sh | Output |
|-------|-------|----------------|--------|
| Discover | `/octo:discover` | `probe-single` per provider | `probe-synthesis-*.md` |
| Define | `/octo:define` | `grasp` | `grasp-consensus-*.md` |
| Develop | `/octo:develop` | `tangle` | `tangle-validation-*.md` |
| Deliver | `/octo:deliver` | `ink` | `delivery-*.md` |
