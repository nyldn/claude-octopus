---
command: factory
description: "Dark Factory Mode - Spec-in, software-out autonomous pipeline"
aliases:
  - dark-factory
  - build-from-spec
---

# Factory - Dark Factory Mode (v8.25.0)

## INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:factory --spec <path>`):

### Step 1: Ask Clarifying Questions

**CRITICAL: Before starting the factory pipeline, use the AskUserQuestion tool to gather context:**

Ask 3 clarifying questions:
1. Spec path — Where is the NLSpec file? (provide path, or paste inline)
2. Satisfaction target — Accept spec default, or override? (Use spec default / Custom target 0.80-0.99)
3. Cost confirmation — Factory mode runs ~20-30 agent calls (~$0.50-2.00). Proceed? (Yes / Yes with --ci for non-interactive / No)

After receiving answers: validate spec path exists, set overrides, proceed.

### Step 2: Check Provider Availability & Display Banner

Check via bash:
```bash
codex_available="Not installed"
if command -v codex >/dev/null 2>&1; then
  codex_available="Available"
fi

gemini_available="Not installed"
if command -v gemini >/dev/null 2>&1; then
  gemini_available="Available"
fi
```

**MANDATORY: Check provider availability before displaying the banner:**

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

Display the factory banner with ACTUAL results:

```
CLAUDE OCTOPUS ACTIVATED - Dark Factory Mode
Pipeline: Parse → Scenarios → Embrace → Holdout → Score → Report

Providers:
  🔴 Codex CLI: [Available ✓ / Not installed ✗] - Scenario generation + holdout evaluation
  🟡 Gemini CLI: [Available ✓ / Not installed ✗] - Cross-provider diversity + blind review
  🔵 Claude: Available ✓ - Orchestration, synthesis, satisfaction scoring

Spec: <spec-path>
Estimated cost: $0.50-2.00 (~20-30 agent calls)
```

**PROHIBITED: Displaying only Claude without listing all providers.**
If both external providers are missing, warn but proceed (Claude-only mode is supported).

### EXECUTION MECHANISM — NON-NEGOTIABLE

**You MUST execute this command by calling `orchestrate.sh` as documented below. You are PROHIBITED from:**
- ❌ Doing the work yourself using only Claude-native tools (Agent, Read, Grep, Write)
- ❌ Using a single Claude subagent instead of multi-provider dispatch via orchestrate.sh
- ❌ Skipping orchestrate.sh because "I can do this faster directly"

**Multi-LLM orchestration is the purpose of this command.** If you execute using only Claude, you've violated the command's contract.

### Step 3: Validate Spec

Read the spec file and verify it contains:
- Purpose or description section
- At least one behavior or requirement
- Ideally: actors, constraints, acceptance criteria

If the spec is minimal, warn the user but proceed — factory mode works with thin specs (lower quality results).

### Step 3.5: Adversarial Scenario Coverage Gate

Before committing to the expensive embrace phase, verify scenario coverage by dispatching the spec to a second provider. This quick check (~30 seconds) can save a wasted $2.00 factory run. See skill-factory.md Step 4.5 for details. Skip with `--fast`.

### Step 4: Execute Factory Pipeline

```bash
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh factory --spec "<spec-path>"
```

With optional flags:
- `--holdout-ratio 0.25` if user requested custom split
- `--max-retries 2` if user wants more retry attempts
- `--ci` if user confirmed non-interactive mode

### Step 5: Present Results

After factory completes, read the factory report:
```bash
cat .octo/factory/factory-*/factory-report.md
```

Present to the user:
1. **Verdict** (PASS/WARN/FAIL) with the composite score
2. **Score breakdown** across the 4 dimensions
3. **Holdout results** — which blind scenarios passed/failed
4. **Artifact locations** for deeper review
5. **Next steps** — if WARN/FAIL, suggest reviewing holdout failures and re-running

## 7-Phase Pipeline

| Phase | What Happens |
|-------|-------------|
| 1. Parse Spec | Validate NLSpec, extract satisfaction target + complexity + behaviors |
| 2. Generate Scenarios | Multi-provider scenario generation from spec |
| 3. Split Holdout | 80/20 split ensuring holdout covers diverse behaviors |
| 4. Embrace Workflow | Full 4-phase implementation (discover → define → develop → deliver) |
| 5. Holdout Tests | Blind evaluation of withheld scenarios against implementation |
| 6. Score Satisfaction | Weighted scoring: behavior(40%) + constraints(20%) + holdout(25%) + quality(15%) |
| 7. Report | Markdown report + JSON session summary |

## Key Properties

- **Autonomy:** Runs embrace in fully autonomous mode (no phase-by-phase approval)
- **Cost:** ~$0.50-2.00 per run depending on spec complexity and provider costs
- **Retry:** On FAIL verdict, re-runs phases 3-4 with remediation context (up to max-retries)
- **Verdict levels:** PASS (>= target), WARN (>= target - 0.05), FAIL (< target - 0.05)
- **Artifacts:** `.octo/factory/<run-id>/` contains all intermediate files
- **Not for:** Simple bug fixes, code review only, tasks without a clear specification
- **Related commands:** `/octo:spec` (create NLSpec), `/octo:embrace` (manual 4-phase workflow)
