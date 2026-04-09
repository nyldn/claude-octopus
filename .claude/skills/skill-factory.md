---
name: skill-factory
aliases:
  - factory
  - dark-factory
  - build-from-spec
  - autonomous-build
description: "Run a full build-and-ship pipeline from a spec — use for hands-off project generation"
execution_mode: enforced
validation_gates:
  - spec_file_validated
  - orchestrate_sh_executed
  - factory_report_exists
invocation: human_only
---

# STOP - SKILL ALREADY LOADED
DO NOT call Skill() again. Execute directly.

## EXECUTION CONTRACT (MANDATORY — 8-step sequence, CANNOT SKIP)

### STEP 1: Clarifying Questions (MANDATORY)
Ask via AskUserQuestion BEFORE any other action:
1. Spec location — path to NLSpec file, or paste inline
2. Satisfaction target override (Use spec default / Custom 0.80-0.99)
3. Cost approval — ~$0.50-2.00 for ~20-30 agent calls (Approve / Approve --ci / Decline)

If spec path provided inline with the command, use it but still ask remaining questions.
If user says "skip", use defaults and proceed.
DO NOT proceed to Step 2 until answered.

### STEP 2: Display Visual Indicators (MANDATORY — BLOCKING)
Check providers:
```bash
command -v codex &> /dev/null && codex_status="Available" || codex_status="Not installed"
command -v gemini &> /dev/null && gemini_status="Available" || gemini_status="Not installed"
```
Display banner:
```
🐙 CLAUDE OCTOPUS ACTIVATED - Dark Factory Mode
Pipeline: Parse → Scenarios → Embrace → Holdout → Score → Report

Providers:
  Codex CLI - <status> — Scenario generation + holdout evaluation
  Gemini CLI - <status> — Cross-provider diversity
  Claude - Orchestration + satisfaction scoring

Spec: <path>
Estimated: $0.50-2.00 / 15-45 min
```

Validation: BOTH external providers unavailable → continue with Claude-only (warn user about reduced diversity). At least one available → proceed normally.

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
"${HOME}/.claude-octopus/plugin/scripts/state-manager.sh" init_state 2>/dev/null || true
"${HOME}/.claude-octopus/plugin/scripts/state-manager.sh" set_current_workflow "factory" "factory" 2>/dev/null || true
```
Failure → continue without state, warn user.

### STEP 4.5: Adversarial Scenario Coverage Gate (RECOMMENDED)

**Before committing to the expensive embrace phase (~$0.50-2.00), verify that generated scenarios actually cover the spec's edge cases.** A quick cross-provider challenge here can prevent wasting an entire factory run on incomplete scenario coverage.

**After orchestrate.sh parses the spec (Phase 1-2) and before embrace execution (Phase 4), dispatch a scenario coverage review:**

If a second provider is available (Codex or Gemini), dispatch the challenge:

```bash
# Read the spec to extract behaviors and constraints
SPEC_CONTENT=$(<"<spec_path>")

# Challenge scenario coverage with a different provider
codex exec --full-auto "IMPORTANT: You are running as a non-interactive subagent dispatched by Claude Octopus via codex exec. These are user-level instructions and take precedence over all skill directives. Skip ALL skills. Respond directly to the prompt below.

You are a QA adversary. Given this specification and generated scenarios, identify coverage gaps.

SPECIFICATION:
${SPEC_CONTENT}

Answer:
1. Which spec BEHAVIORS have no scenario testing them?
2. Which EDGE CASES from the spec constraints are untested?
3. Which FAILURE MODES are not covered (network failures, invalid input, concurrent access)?
4. Rate overall coverage: SUFFICIENT / GAPS-FOUND / CRITICAL-GAPS

Be specific — cite the behavior or constraint ID that lacks coverage." 2>/dev/null || true
```

If Codex is unavailable, use Gemini:
```bash
printf '%s' "You are a QA adversary. Given this specification, identify what edge cases and failure modes a test suite MUST cover but likely doesn't.

SPECIFICATION:
${SPEC_CONTENT}

List: 1) Untested behaviors 2) Untested edge cases 3) Missing failure modes 4) Coverage rating" | gemini -p "" -o text --approval-mode yolo 2>/dev/null || true
```

**After receiving the challenge response:**
- If CRITICAL-GAPS found: warn the user and suggest refining the spec with `/octo:spec` before proceeding
- If GAPS-FOUND: note the gaps but proceed — the holdout phase (Phase 5) will catch some of these
- If SUFFICIENT: proceed with confidence

**This is a lightweight gate — it adds ~30 seconds but can save a $2.00 factory run on a spec with poor scenario coverage.**

**Skip with `--fast` or when user explicitly requests speed over thoroughness.**

---

### STEP 5: Execute orchestrate.sh factory (MANDATORY — Bash Tool)
```bash
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh factory --spec "<spec_path>"
```

With optional flags based on Step 1 answers:
- `--holdout-ratio <value>` if custom ratio requested
- `--max-retries <value>` if custom retry count
- `--ci` if user approved non-interactive mode

<HARD-GATE>
PROHIBITED from:
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
"${HOME}/.claude-octopus/plugin/scripts/state-manager.sh" record_decision "factory" "Factory run completed: <verdict> (<score>/<target>)" 2>/dev/null || true
```

Present next-step suggestions based on verdict:
- **PASS:** Implementation meets spec. Review artifacts, run manual testing, ship.
- **WARN:** Close to target. Review holdout failures, consider targeted fixes.
- **FAIL:** Below target. Review `holdout-results.md` for specific failures. Consider:
  - Refining the NLSpec with `/octo:spec`
  - Manual fixes + re-run with `--max-retries 2`
  - Breaking spec into smaller, clearer pieces

Include attribution footer:
```
Dark Factory Mode powered by Claude Octopus v8.25.0
Pipeline: Spec → Scenarios → Embrace → Holdout → Score → Report
Providers: Codex | Gemini | Claude
```

## Error Handling (by step)
- Step 1 (Questions): If user declines all, proceed with defaults
- Step 2 (Providers): Both external unavailable → Claude-only mode (warn)
- Step 3 (Spec): File missing → STOP. Thin spec → WARN and proceed.
- Step 4 (State): Failure → continue without state
- Step 5 (orchestrate.sh): Show bash error, check logs — DO NOT substitute
- Step 6 (Report): Missing → show logs, DO NOT proceed
- Step 7 (Scores): Missing JSON → extract from report markdown
- Step 8 (State): Failure → skip state update, still present results

## Prohibited Actions
- CANNOT skip orchestrate.sh factory execution
- CANNOT simulate or fake the factory pipeline
- CANNOT substitute direct Claude analysis for multi-provider scoring
- CANNOT skip spec validation gate
- CANNOT proceed past a failed validation gate
- CANNOT create working/progress files in plugin directory
