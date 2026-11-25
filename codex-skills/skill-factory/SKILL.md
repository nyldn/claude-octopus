---
name: skill-factory
description: "Run a full build-and-ship pipeline from a spec — use for hands-off project generation"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Invoke installed skills by their `$skill-name`. Known Octopus commands are mapped below. A remaining `/octo:*` reference is a Claude Code command; do not execute it in Codex or invent an equivalent.
> Before the first helper call, derive the absolute plugin root from this loaded skill's path by finding its ancestor containing `.codex-plugin/plugin.json`. Verify that root, bind `OCTO_ROOT`, `CODEX_PLUGIN_ROOT`, and `CLAUDE_PLUGIN_ROOT` to the same root, and export all three in each fresh shell before launching child processes. Use the verified absolute helper path when needed. Do not infer the root from the user's project or assume exports survive tool calls. Stop and report a missing installation if the root cannot be verified.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> Claude-native tool calls in examples are prompt templates to adapt, not Codex call signatures. If a mandatory verification agent or tool is unavailable or unauthorized, report that verification did not run and stop the affected completion step. Never claim a skipped check passed.
> Attribute commits only to actual contributors; do not copy fixed model attribution trailers from examples.
> For host tool equivalents, see `codex-skills/blocks/codex-host-adapter.md`.

> Invoke this entry as `$skill-factory` in Codex. Code-fenced Claude command examples are reference text, not Codex shell commands.


# STOP - SKILL ALREADY LOADED
DO NOT call Skill() again. Execute directly.

## EXECUTION CONTRACT (MANDATORY — 8-step sequence, CANNOT SKIP)

### STEP 1: Clarifying Questions (MANDATORY)
Ask via AskUserQuestion BEFORE any other action:
1. Spec location — path to NLSpec file, or paste inline
2. Satisfaction target override (Use spec default / Custom 0.80-0.99)
3. Cost approval — ~0.50-2.00 USD for ~20-30 agent calls (Approve / Approve --ci / Decline)

If spec path provided inline with the command, use it but still ask remaining questions.
Use defaults for optional answers the user skips. If the user declines the
cost, end the workflow. If the cost answer is missing or unclear, ask for
explicit approval before proceeding to Step 2.

In each shell that can dispatch providers, set `FACTORY_COST_APPROVAL` from
the user's answer for this run. Use `approve` for Approve and `approve-ci`
for Approve --ci.

### STEP 2: Display Visual Indicators (MANDATORY — BLOCKING)
Check providers:
```bash
command -v codex &> /dev/null && codex_status="Available" || codex_status="Not installed"
command -v agy &> /dev/null && agy_status="Available" || agy_status="Not installed"
```
Display banner:
```
🐙 CLAUDE OCTOPUS ACTIVATED - Dark Factory Mode
Pipeline: Parse → Scenarios → Embrace → Holdout → Score → Report

Providers:
  Codex CLI - <status> — Scenario generation + holdout evaluation
  Antigravity CLI - <status> — Additional external-model challenge
  Claude - Orchestration + satisfaction scoring

Spec: <path>
Estimated: 0.50-2.00 USD / 15-45 min
```

Validation: All external providers unavailable → continue with Claude-only (warn user about reduced diversity). At least one available → proceed normally.

### STEP 3: Validate Spec File (MANDATORY — Validation Gate)
```bash
if [[ ! -f "<spec_path>" ]]; then
    echo "ERROR: Spec file not found at <spec_path>"
    exit 1
fi
# Check minimum content
word_count=$(wc -w < "<spec_path>")
if [[ $word_count -lt 20 ]]; then
    echo "WARNING: Spec is very thin ($word_count words). Results may be limited."
fi
```
If spec file missing → STOP, ask user for correct path.
If spec is thin (< 50 words) → WARN but proceed.
DO NOT proceed past this gate if file does not exist.

### STEP 4: Read Prior State (OPTIONAL)
```bash
"${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}/scripts/state-manager.sh" init_state 2>/dev/null || true
"${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}/scripts/state-manager.sh" set_current_workflow "factory" "factory" 2>/dev/null || true
```
Failure → continue without state, warn user.

### STEP 4.5: Adversarial Scenario Coverage Gate (RECOMMENDED)

**Before committing to the expensive embrace phase (~0.50-2.00 USD), verify that generated scenarios actually cover the spec's edge cases.** A quick cross-provider challenge here can prevent wasting an entire factory run on incomplete scenario coverage.

**After orchestrate.sh parses the spec (Phase 1-2) and before embrace execution (Phase 4), dispatch a scenario coverage review:**

If a second provider is available, dispatch the challenge through Octopus routing:

```bash
case "${FACTORY_COST_APPROVAL:-}" in
    approve|approve-ci) ;;
    *) printf '%s\n' 'Factory requires explicit cost approval.' >&2; exit 1 ;;
esac
# Read the spec to extract behaviors and constraints
SPEC_CONTENT=$(<"<spec_path>")
review_provider=""
command -v codex >/dev/null 2>&1 && review_provider="codex"
[[ -z "$review_provider" ]] && command -v agy >/dev/null 2>&1 && review_provider="agy"

if [[ -n "$review_provider" ]]; then
  "${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}/scripts/orchestrate.sh" spawn "$review_provider" \
    "You are a QA adversary. Given this specification and generated scenarios, identify coverage gaps.

SPECIFICATION:
${SPEC_CONTENT}

Answer:
1. Which spec BEHAVIORS have no scenario testing them?
2. Which EDGE CASES from the spec constraints are untested?
3. Which FAILURE MODES are not covered (network failures, invalid input, concurrent access)?
4. Rate overall coverage: SUFFICIENT / GAPS-FOUND / CRITICAL-GAPS

Be specific — cite the behavior or constraint ID that lacks coverage." 2>/dev/null || true
fi
```

**After receiving the challenge response:**
- If CRITICAL-GAPS found: warn the user and suggest refining the spec with `$flow-spec` before proceeding
- If GAPS-FOUND: note the gaps but proceed — the holdout phase (Phase 5) will catch some of these
- If SUFFICIENT: proceed with confidence

**This is a lightweight gate — it adds ~30 seconds but can save a 2.00 USD factory run on a spec with poor scenario coverage.**

**Skip with `--fast` or when user explicitly requests speed over thoroughness.**


### STEP 5: Execute orchestrate.sh factory (MANDATORY — Bash Tool)
```bash
factory_args=(factory --spec "<spec_path>")
case "${FACTORY_COST_APPROVAL:-}" in
    approve) ;;
    approve-ci) factory_args+=(--ci) ;;
    *) printf '%s\n' 'Factory requires explicit cost approval.' >&2; exit 1 ;;
esac
"${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}/scripts/orchestrate.sh" "${factory_args[@]}"
```

If the command exits nonzero, report the error, show logs from
`~/.claude-octopus/logs/`, and stop. Do not run Steps 6 through 8 or use an earlier
run's artifacts after a failed execution.

Append optional flags to `factory_args` before dispatch when requested:
- `--holdout-ratio <value>` if custom ratio requested
- `--max-retries <value>` if custom retry count

<HARD-GATE>
After cost approval, PROHIBITED from:
- Running embrace directly (MUST use factory command which wraps it)
- Simulating or faking holdout testing
- Substituting direct Claude analysis for multi-provider scoring
- Skipping the factory pipeline
- Creating working/progress files in plugin directory
</HARD-GATE>

### STEP 6: Verify Factory Report (MANDATORY — Validation Gate)
```bash
REPORT_FILE=$(find .octo/factory -name "factory-report.md" -mmin -60 2>/dev/null | sort -r | head -1)
if [[ -z "$REPORT_FILE" ]]; then
    echo "ERROR: Factory report not found"
    exit 1
fi
cat "$REPORT_FILE"
```
If validation fails: report error, show logs from `~/.claude-octopus/logs/`, DO NOT proceed, DO NOT substitute.

Factory requires at least two structured generated scenarios so implementation
has a visible case and evaluation has an independent holdout. Missing or empty
holdout evidence stops the run without a score or completion report. Preserve
evaluation failures, including on retries, instead of presenting a successful run.
A provider response must contain a score from 0 to 1 or usable scenario verdicts;
empty, diagnostic-only or malformed responses do not establish an evaluation.

### STEP 7: Read Scores and Present Results (MANDATORY)
```bash
SCORES_FILE=$(find .octo/factory -name "satisfaction-scores.json" -mmin -60 2>/dev/null | sort -r | head -1)
if [[ -n "$SCORES_FILE" ]]; then
    cat "$SCORES_FILE"
fi
```

Present to user:
1. **Verdict** with emoji (PASS/WARN/FAIL)
2. **Composite score** vs satisfaction target
3. **Dimension breakdown** (behavior, constraints, holdout, quality)
4. **Holdout highlights** — which blind scenarios passed/failed
5. **Artifact directory** path for deep review

### STEP 8: Update State & Next Steps (MANDATORY)
```bash
"${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${HOME}/.claude-octopus/plugin}}/scripts/state-manager.sh" record_decision "factory" "Factory run completed: <verdict> (<score>/<target>)" 2>/dev/null || true
```

Present next-step suggestions based on verdict:
- **PASS:** Implementation meets spec. Review artifacts, run manual testing, ship.
- **WARN:** Close to target. Review holdout failures, consider targeted fixes.
- **FAIL:** Below target. Review `holdout-results.md` for specific failures. Consider:
  - Refining the NLSpec with `$flow-spec`
  - Manual fixes + re-run with `--max-retries 2`
  - Breaking spec into smaller, clearer pieces

Include attribution footer:
```
Dark Factory Mode powered by Claude Octopus v8.25.0
Pipeline: Spec → Scenarios → Embrace → Holdout → Score → Report
Providers: Codex | Antigravity | Claude
```

## Error Handling (by step)
- Step 1 (Questions): Stop on declined cost approval. Ask for explicit approval if the cost answer is missing or unclear.
- Step 2 (Providers): Both external unavailable → Claude-only mode (warn)
- Step 3 (Spec): File missing → STOP. Thin spec → WARN and proceed.
- Step 4 (State): Failure → continue without state
- Step 5 (orchestrate.sh): Show bash error, check logs — DO NOT substitute
- Step 6 (Report): Missing → show logs, DO NOT proceed
- Step 7 (Scores): Missing JSON → extract from report markdown
- Step 8 (State): Failure → skip state update, still present results

## Prohibited Actions
- CANNOT skip orchestrate.sh factory execution after cost approval
- CANNOT simulate or fake the factory pipeline
- CANNOT substitute direct Claude analysis for multi-provider scoring
- CANNOT skip spec validation gate
- CANNOT proceed past a failed validation gate
- CANNOT create working/progress files in plugin directory
