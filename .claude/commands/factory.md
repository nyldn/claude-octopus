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
codex_available=$(command -v codex &> /dev/null && echo "Available" || echo "Not installed")
gemini_available=$(command -v gemini &> /dev/null && echo "Available" || echo "Not installed")
```

Display the factory banner:

```
CLAUDE OCTOPUS ACTIVATED - Dark Factory Mode
Pipeline: Parse → Scenarios → Embrace → Holdout → Score → Report

Providers:
  Codex CLI - Scenario generation + holdout evaluation
  Gemini CLI - Cross-provider diversity + blind review
  Claude - Orchestration, synthesis, satisfaction scoring

Spec: <spec-path>
Estimated cost: $0.50-2.00 (~20-30 agent calls)
```

If both external providers are missing, warn but proceed (Claude-only mode is supported).

### Step 3: Validate Spec

Read the spec file and verify it contains:
- Purpose or description section
- At least one behavior or requirement
- Ideally: actors, constraints, acceptance criteria

If the spec is minimal, warn the user but proceed — factory mode works with thin specs (lower quality results).

### Step 4: Execute Factory Pipeline

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh factory --spec "<spec-path>"
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
