# Validation Gates Reference

Standard patterns for enforcing multi-AI orchestration across Claude Octopus skills.

## Purpose

Validation gates ensure that skills which invoke `orchestrate.sh` actually execute it rather than substituting with direct research or implementation. This is critical because:

1. **Cost Transparency**: Users need to know when external providers are being used
2. **Quality Assurance**: Multi-AI perspectives provide better outcomes than single-agent work
3. **Compliance**: Plugin promises multi-AI orchestration, must deliver it
4. **Trust**: Users rely on visual indicators to understand what's happening

## Standard Enforcement Pattern

All skills that invoke `orchestrate.sh` MUST include this pattern:

### 1. Frontmatter Configuration

```yaml
---
name: skill-example
execution_mode: enforced
pre_execution_contract:
  - interactive_questions_answered  # If skill asks questions first
  - visual_indicators_displayed     # Always required
validation_gates:
  - orchestrate_sh_executed          # Always required
  - synthesis_file_exists            # Or appropriate artifact
---
```

**Fields Explained:**
- `execution_mode: enforced` - Enables strict validation
- `pre_execution_contract` - Must complete before proceeding
- `validation_gates` - Must verify before presenting results

### 2. Execution Contract Section

Add after the frontmatter and description:

```markdown
## ⚠️ EXECUTION CONTRACT (MANDATORY - CANNOT SKIP)

This skill uses **ENFORCED execution mode**. You MUST follow this exact sequence.

### STEP 1: Display Visual Indicators (MANDATORY - BLOCKING)

**Check provider availability:**

```bash
command -v codex &> /dev/null && codex_status="Available ✓" || codex_status="Not installed ✗"
command -v gemini &> /dev/null && gemini_status="Available ✓" || gemini_status="Not installed ✗"
```

**Display this banner BEFORE orchestrate.sh execution:**

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - [Workflow type]
[Emoji] [Phase Name]: [Brief description]

Provider Availability:
🔴 Codex CLI: ${codex_status} - [Role in this workflow]
🟡 Gemini CLI: ${gemini_status} - [Role in this workflow]
🔵 Claude: Available ✓ - [Role in this workflow]

💰 Estimated Cost: $[range]
⏱️  Estimated Time: [range] minutes
```

**Validation:**
- If BOTH Codex and Gemini unavailable → STOP, suggest: `/octo:setup`
- If ONE unavailable → Continue with available provider(s)
- If BOTH available → Proceed normally

**DO NOT PROCEED TO STEP 2 until banner displayed.**

---

### STEP 2: Execute orchestrate.sh [workflow] (MANDATORY - Use Bash Tool)

**You MUST execute this command via the Bash tool:**

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh [workflow] "<user's request>"
```

**CRITICAL: You are PROHIBITED from:**
- ❌ Executing the task directly without calling orchestrate.sh
- ❌ Using direct research/implementation as a substitute
- ❌ Claiming you're "simulating" the workflow
- ❌ Proceeding to Step 3 without running this command

**This is NOT optional. You MUST use the Bash tool to invoke orchestrate.sh.**

---

### STEP 3: Verify Execution (MANDATORY - Validation Gate)

**After orchestrate.sh completes, verify it succeeded:**

```bash
# Find the latest synthesis/output file (created within last 10 minutes)
OUTPUT_FILE=$(find ~/.claude-octopus/results -name "[workflow]-*-*.md" -mmin -10 2>/dev/null | head -n1)

if [[ -z "$OUTPUT_FILE" ]]; then
  echo "❌ VALIDATION FAILED: No output file found"
  echo "orchestrate.sh did not execute properly"
  exit 1
fi

echo "✅ VALIDATION PASSED: Output file exists at $OUTPUT_FILE"
```

**If validation fails:**
1. Report error to user
2. Show logs from `~/.claude-octopus/logs/`
3. DO NOT proceed with presenting results
4. DO NOT substitute with direct work

---

### STEP 4: Present Results (Only After Steps 1-3 Complete)

Read the output file and format results for the user.

**Include attribution:**
```
---
*Multi-AI [Task Type] powered by Claude Octopus*
*Providers: 🔴 Codex | 🟡 Gemini | 🔵 Claude*
*Full output: $OUTPUT_FILE*
```
```

### 3. Prohibited Actions Section

Add clear prohibitions:

```markdown
## ❌ PROHIBITED SUBSTITUTIONS

You are EXPLICITLY PROHIBITED from:

1. **Direct Execution**: Performing the task yourself instead of calling orchestrate.sh
2. **Web Search Substitution**: Using WebSearch instead of multi-AI orchestration
3. **Simulation Claims**: Saying you're "simulating" or "representing" the workflow
4. **Skipping Validation**: Proceeding without verifying synthesis file exists
5. **Missing Indicators**: Skipping visual indicators that show provider usage

**Why These Are Prohibited:**
- Users need cost transparency (external providers cost money)
- Multi-AI perspectives provide better quality than single-agent work
- Visual indicators are contractual - users must see what's running
- Synthesis files prove orchestration actually occurred
```

## Validation Gate Types

Different workflows produce different artifacts:

### Research Workflows (probe, research)
```bash
SYNTHESIS_FILE=$(find ~/.claude-octopus/results -name "probe-synthesis-*.md" -mmin -10 2>/dev/null | head -n1)
```

### Definition Workflows (grasp, define)
```bash
SYNTHESIS_FILE=$(find ~/.claude-octopus/results -name "grasp-synthesis-*.md" -mmin -10 2>/dev/null | head -n1)
```

### Implementation Workflows (tangle, develop)
```bash
SYNTHESIS_FILE=$(find ~/.claude-octopus/results -name "tangle-synthesis-*.md" -mmin -10 2>/dev/null | head -n1)
```

### Validation Workflows (ink, deliver)
```bash
VALIDATION_FILE=$(find ~/.claude-octopus/results -name "ink-validation-*.md" -mmin -10 2>/dev/null | head -n1)
```

### Debate Workflows
```bash
DEBATE_FILE=$(find ~/.claude-octopus/results -name "debate-*.md" -mmin -10 2>/dev/null | head -n1)
```

### Code Review Workflows
```bash
REVIEW_FILE=$(find ~/.claude-octopus/results -name "code-review-*.md" -mmin -10 2>/dev/null | head -n1)
```

## Language Patterns

Use imperative, blocking language:

### ✅ GOOD (Strong, Mandatory)
- "You MUST execute..."
- "PROHIBITED from..."
- "CANNOT SKIP..."
- "BLOCKING step..."
- "DO NOT PROCEED until..."
- "MANDATORY validation..."

### ❌ BAD (Weak, Suggestive)
- "You should execute..."
- "It's recommended to..."
- "Consider calling..."
- "Try to run..."
- "Preferably use..."
- "Optional validation..."

## Examples by Skill Type

### Research Skill (skill-deep-research.md)

See `.claude/skills/skill-deep-research.md` for reference implementation.

**Key elements:**
- Visual indicators showing all 3 providers
- Bash tool invocation of `orchestrate.sh probe`
- Synthesis file validation
- Attribution in output

### Review Skill (skill-code-review.md - if updated)

```yaml
execution_mode: enforced
validation_gates:
  - orchestrate_sh_executed
  - review_file_exists
```

Execute:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh code-review "<commit range or files>"
```

Validate:
```bash
REVIEW_FILE=$(find ~/.claude-octopus/results -name "code-review-*.md" -mmin -10 2>/dev/null | head -n1)
```

### Architecture Skill

```yaml
execution_mode: enforced
validation_gates:
  - orchestrate_sh_executed
  - architecture_file_exists
```

Execute:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh architecture "<system design prompt>"
```

Validate:
```bash
ARCH_FILE=$(find ~/.claude-octopus/results -name "architecture-*.md" -mmin -10 2>/dev/null | head -n1)
```

### Security Audit Skill

```yaml
execution_mode: enforced
validation_gates:
  - orchestrate_sh_executed
  - security_report_exists
```

Execute:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh security-audit "<scope>"
```

Validate:
```bash
SECURITY_FILE=$(find ~/.claude-octopus/results -name "security-audit-*.md" -mmin -10 2>/dev/null | head -n1)
```

## Migration Checklist

When updating a skill to add validation gates:

- [ ] Add frontmatter fields (execution_mode, pre_execution_contract, validation_gates)
- [ ] Add EXECUTION CONTRACT section with numbered steps
- [ ] Add visual indicators (Step 1)
- [ ] Add orchestrate.sh execution (Step 2) with Bash tool
- [ ] Add validation gate (Step 3) with file existence check
- [ ] Add result presentation (Step 4)
- [ ] Add PROHIBITED SUBSTITUTIONS section
- [ ] Use imperative language throughout
- [ ] Include attribution in output

## Testing Validation Gates

After adding validation gates, test:

```bash
# 1. Try to execute skill
/octo:[skill-name] "test prompt"

# 2. Verify visual indicators appear
# Should see 🐙 banner with provider status

# 3. Verify orchestrate.sh executes
# Should see Bash tool invocation in transcript

# 4. Verify synthesis file created
ls -la ~/.claude-octopus/results/
# Should see recent file matching pattern

# 5. Verify results include attribution
# Should see "Multi-AI ... powered by Claude Octopus"
```

## Common Mistakes to Avoid

### ❌ Mistake 1: Optional Validation
```markdown
You should verify the synthesis file exists (optional).
```

**Fix:**
```markdown
**MANDATORY Validation Gate:**
You MUST verify the synthesis file exists before proceeding.
```

### ❌ Mistake 2: Allowing Substitution
```markdown
If orchestrate.sh fails, you can research directly.
```

**Fix:**
```markdown
If orchestrate.sh fails:
1. Report error to user
2. DO NOT substitute with direct research
3. DO NOT proceed without fixing the error
```

### ❌ Mistake 3: Missing Visual Indicators
```markdown
Execute orchestrate.sh...
```

**Fix:**
```markdown
**STEP 1: Display Visual Indicators (BLOCKING)**
[Full banner with provider status]

**DO NOT PROCEED TO STEP 2 until banner displayed.**

**STEP 2: Execute orchestrate.sh...**
```

### ❌ Mistake 4: Weak Language
```markdown
It would be good to run orchestrate.sh
```

**Fix:**
```markdown
You MUST execute orchestrate.sh via the Bash tool.
You are PROHIBITED from skipping this step.
```

## Enforcement Philosophy

**Why Strict Enforcement Matters:**

1. **User Trust**: Users choose Claude Octopus specifically for multi-AI orchestration
2. **Cost Transparency**: External providers cost money - users must know when they're used
3. **Quality Promise**: Multi-AI provides better outcomes than single-agent
4. **Contractual Obligation**: Visual indicators are a promise to users

**The Goal:**
- 100% of skills that invoke orchestrate.sh actually invoke it
- 0% substitution with direct work
- 100% visibility via visual indicators
- 100% validation via artifact checks

## Summary

Validation gates transform skills from "suggestions" to "contracts":

**Before (Weak):**
- "You should call orchestrate.sh"
- No verification
- Easy to skip
- Users uncertain what's happening

**After (Strong):**
- "You MUST call orchestrate.sh"
- Mandatory verification
- Impossible to skip
- Users see exactly what's running

All skills that use orchestrate.sh must follow this pattern to ensure consistent, reliable, transparent multi-AI orchestration.
