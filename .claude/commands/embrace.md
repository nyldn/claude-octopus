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

**Each phase MUST be executed through the `orchestrate.sh` entrypoint. Direct Skill calls for the workflow phases are not permitted because they can recursively reload command instructions. You are PROHIBITED from:**
- Using the Agent tool to do research yourself instead of running the discovery phase
- Using WebFetch/Read/Grep as a substitute for multi-provider research
- Implementing code directly instead of running the develop phase
- Using a single code-reviewer agent instead of running the deliver phase
- Skipping `orchestrate.sh` calls because "I can do this faster directly"

**The ENTIRE POINT of `/octo:embrace` is multi-LLM orchestration.** If you execute phases using only Claude-native tools (Agent, WebFetch, Write, Edit), you have violated the command's purpose even if you followed the phase structure.

**Self-check after completion:** You should be able to list the `orchestrate.sh` commands you ran. If you used only Claude-native tools, you executed incorrectly.

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

After receiving answers, incorporate them into all subsequent phase invocations — use the scope to calibrate research depth, focus areas to weight provider perspectives, autonomy level to control phase transitions, and debate preference to gate handoffs.

Normalize the debate preference immediately:
- `DEBATE_GATES=define` for "Yes — debate at Define→Develop gate"
- `DEBATE_GATES=both` for "Yes — debate at both gates"
- `DEBATE_GATES=none` for "No — skip debates"
- `DEBATE_GATES=auto` for "Only if disagreement detected"

**Gate ledger invariant:** if `DEBATE_GATES=define`, a `embrace-gate-define-develop-*.md` artifact from the current run MUST exist before Phase 3 starts. If `DEBATE_GATES=both`, both `embrace-gate-define-develop-*.md` and `embrace-gate-develop-deliver-*.md` artifacts from the current run MUST exist before their next phases. Autonomy mode does not waive requested gates. If a requested gate command fails or produces no artifact, STOP and report the failed gate instead of continuing.

### Remote/Cloud Defaults

If `CLAUDE_CODE_REMOTE=true` or `OCTOPUS_REMOTE_SESSION=true`, do not block on clarifying questions. Use these defaults unless the user's prompt says otherwise:

- scope: infer from the prompt
- focus: all relevant areas
- autonomy: autonomous
- debate gates: only if provider disagreement is detected

Plan locally first, then run the approved `/octo:embrace` prompt in the hosted or remote-control session with `OCTOPUS_REMOTE_SESSION=true` set in that environment.

## Step 2: Check Provider Availability & Display Banner

**MANDATORY: Run this bash command BEFORE the banner.**

```bash
set -euo pipefail

echo "PROVIDER_CHECK_START"
printf "codex:%s\n" "$(command -v codex >/dev/null 2>&1 && echo available || echo missing)"
printf "gemini:%s\n" "$(command -v gemini >/dev/null 2>&1 && echo available || echo missing)"
printf "perplexity:%s\n" "$([ -n "${PERPLEXITY_API_KEY:-}" ] && echo available || echo missing)"
printf "opencode:%s\n" "$(command -v opencode >/dev/null 2>&1 && echo available || echo missing)"
printf "copilot:%s\n" "$(command -v copilot >/dev/null 2>&1 && echo available || echo missing)"
printf "qwen:%s\n" "$(command -v qwen >/dev/null 2>&1 && echo available || echo missing)"
printf "ollama:%s\n" "$(command -v ollama >/dev/null 2>&1 && curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && echo available || echo missing)"
printf "openrouter:%s\n" "$([ -n "${OPENROUTER_API_KEY:-}" ] && echo available || echo missing)"
printf "agy:%s\n" "$(command -v agy >/dev/null 2>&1 && echo available || echo missing)"
echo "PROVIDER_CHECK_END"
```

Render the provider banner from actual provider checks. Do not hand-write or summarize this banner; run this block and display its output exactly. The output MUST include the Antigravity line even when `agy` is missing.

```bash
status_cli() { command -v "$1" >/dev/null 2>&1 && echo "Available ✓" || echo "Not installed ✗"; }
status_env() { [[ -n "${1:-}" ]] && echo "Configured ✓" || echo "Not configured ✗"; }
codex_status="$(status_cli codex)"
gemini_status="$(status_cli gemini)"
agy_status="$(status_cli agy)"
opencode_status="$(status_cli opencode)"
copilot_status="$(status_cli copilot)"
qwen_status="$(status_cli qwen)"
if command -v ollama >/dev/null 2>&1 && curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then ollama_status="Available ✓"; else ollama_status="Not installed ✗"; fi
perplexity_status="$(status_env "${PERPLEXITY_API_KEY:-}")"
cat <<BANNER
🐙 **CLAUDE OCTOPUS ACTIVATED** - Full Double Diamond Workflow
🐙 Embrace: [Brief description]

Phases: 🔍 Discover → 🎯 Define → 🛠️ Develop → ✅ Deliver

Provider Availability:
🔴 Codex CLI: ${codex_status}
🟡 Gemini CLI: ${gemini_status}
🧭 Antigravity CLI: ${agy_status}
🟤 OpenCode: ${opencode_status}
🟢 Copilot CLI: ${copilot_status}
🟠 Qwen CLI: ${qwen_status}
⚫ Ollama: ${ollama_status}
🔵 Claude: Available ✓
🟣 Perplexity: ${perplexity_status}
BANNER
```

The rendered banner must look like this shape, with ACTUAL statuses:

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Full Double Diamond Workflow
🐙 Embrace: [Brief description]

Phases: 🔍 Discover → 🎯 Define → 🛠️ Develop → ✅ Deliver

Provider Availability:
🔴 Codex CLI: [Available ✓ / Not installed ✗]
🟡 Gemini CLI: [Available ✓ / Not installed ✗]
🧭 Antigravity CLI: [Available ✓ / Not installed ✗]
🟤 OpenCode: [Available ✓ / Not installed ✗]
🟢 Copilot CLI: [Available ✓ / Not installed ✗]
🟠 Qwen CLI: [Available ✓ / Not installed ✗]
⚫ Ollama: [Available ✓ / Not installed ✗]
🔵 Claude: Available ✓
🟣 Perplexity: [Configured ✓ / Not configured ✗]

Scope: [answer]  Focus: [answer]  Autonomy: [answer]
```

## Step 3: Execute Phases via orchestrate.sh

**CRITICAL: Each phase MUST run through `orchestrate.sh`. Do not invoke `/octo:discover`, `/octo:define`, `/octo:develop`, or `/octo:deliver` via Skill calls inside this command; direct phase dispatch prevents recursive command loading.**

**CRITICAL: Run every orchestrate.sh command from the user's project directory. Do NOT `cd` into the plugin first — dispatched providers (codex workdir, gemini workspace) sandbox themselves to the invoking directory, and a plugin cwd makes every provider unable to read the user's project files. If the prompt references files outside the project (e.g. /tmp), pass `-d <dir>` or set `OCTOPUS_GEMINI_INCLUDE_DIRS`.**

### Phase 1 — Discover

Run the Discover phase via orchestrate.sh:

```bash
bash "${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh" probe <user's prompt>
```

This will dispatch to Codex, Gemini, and other available providers. Results saved to `~/.claude-octopus/results/probe-synthesis-*.md`.

**Supervised mode:** After Discover completes, present key findings and ask to proceed.
**Semi-autonomous/Autonomous:** Proceed automatically.

### Phase 2 — Define

Run the define phase via orchestrate.sh:

```bash
bash "${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh" grasp <user's prompt>
```

This builds consensus across providers. Results saved to `~/.claude-octopus/results/grasp-consensus-*.md`.

**Supervised mode:** Present consensus and ask to proceed.

### Debate Gate (if enabled)

If user selected debate gates at Define→Develop transition:
1. Read consensus from `~/.claude-octopus/results/grasp-consensus-*.md`
2. Run the explicit Embrace gate via orchestrate.sh:

```bash
latest_consensus="$(ls -t ~/.claude-octopus/results/grasp-consensus-*.md | head -1)"
bash "${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh" embrace-gate define-develop "<user's prompt>" "$latest_consensus"
```

3. Verify `~/.claude-octopus/results/embrace-gate-define-develop-*.md` exists for this run before Phase 3. If the command fails or no artifact exists, STOP.

4. If risks surface and autonomy is supervised/manual, present via AskUserQuestion:
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

Run the develop phase via orchestrate.sh:

```bash
bash "${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh" tangle <user's prompt>
```

This dispatches implementation with quality gates. Results saved to `~/.claude-octopus/results/tangle-validation-*.md`.

### Second Debate Gate (if "both gates" selected)

If `DEBATE_GATES=both`, run this before Phase 4:

```bash
latest_tangle="$(ls -t ~/.claude-octopus/results/tangle-validation-*.md | head -1)"
bash "${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh" embrace-gate develop-deliver "<user's prompt>" "$latest_tangle"
```

Verify `~/.claude-octopus/results/embrace-gate-develop-deliver-*.md` exists for this run before Phase 4. If the command fails or no artifact exists, STOP. In autonomous mode, continue only after the gate artifact exists; do not silently skip this gate.

### Phase 4 — Deliver

Run the deliver phase via orchestrate.sh:

```bash
bash "${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh" ink <user's prompt>
```

This runs multi-provider validation. Results saved to `~/.claude-octopus/results/delivery-*.md`.

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

| Phase | Command | orchestrate.sh | Output |
|-------|---------|----------------|--------|
| Discover | `/octo:discover` | `probe-single` per provider | `probe-synthesis-*.md` |
| Define | `/octo:define` | `grasp` | `grasp-consensus-*.md` |
| Develop | `/octo:develop` | `tangle` | `tangle-validation-*.md` |
| Deliver | `/octo:deliver` | `ink` | `delivery-*.md` |
