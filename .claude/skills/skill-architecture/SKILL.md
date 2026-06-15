---
name: octopus-architecture
description: System architecture and API design with multi-AI consensus — use for design reviews and new subsystems
execution_mode: enforced
pre_execution_contract:
  - visual_indicators_displayed
validation_gates:
  - orchestrate_sh_executed
  - persona_output_exists
---

## ⚠️ EXECUTION CONTRACT (MANDATORY - CANNOT SKIP)

This skill uses **ENFORCED execution mode**. You MUST follow this exact sequence.

### STEP 1: Display Visual Indicators (MANDATORY - BLOCKING)

**Check provider availability:**

```bash
providers_output="$("${HOME}/.claude-octopus/plugin/scripts/helpers/check-providers.sh" 2>/dev/null || true)"
provider_status() {
  provider="$1"
  if printf '%s\n' "$providers_output" | grep -q "^${provider}:available"; then
    echo "Available ✓"
  else
    echo "Not installed ✗"
  fi
}
codex_status="$(provider_status codex)"
gemini_status="$(provider_status gemini)"
agy_status="$(provider_status agy)"
```

**Display this banner BEFORE orchestrate.sh execution:**

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Architecture design mode
🏗️ Architecture: [Brief description of system to design]

Provider Availability:
🔴 Codex CLI: ${codex_status} - Backend architecture patterns
🟡 Gemini CLI: ${gemini_status} - Alternative approaches
🧭 Antigravity CLI: ${agy_status} - Additional external-model challenge
🔵 Claude: Available ✓ - Synthesis and recommendations

💰 Estimated Cost: $0.02-0.08
⏱️  Estimated Time: 3-7 minutes
```

**Validation:**
- If no external providers are available → STOP, suggest: `/octo:setup`
- If one or more external providers are available → Continue with available provider(s)

**DO NOT PROCEED TO STEP 2 until banner displayed.**

---

### STEP 2: Execute orchestrate.sh spawn (MANDATORY - Use Bash Tool)

**You MUST execute this command via the Bash tool:**

```bash
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh spawn backend-architect "<user's architecture request>"
```

**CRITICAL: You are PROHIBITED from:**
- ❌ Designing architecture directly without calling orchestrate.sh
- ❌ Using direct analysis as a substitute
- ❌ Claiming you're "simulating" the workflow
- ❌ Proceeding to Step 3 without running this command

**This is NOT optional. You MUST use the Bash tool to invoke orchestrate.sh.**

---

### STEP 3: Verify Execution (MANDATORY - Validation Gate)

**After orchestrate.sh completes, verify it succeeded:**

```bash
# Check for persona output (varies by persona type)
# For spawn commands, check exit code and output
if [ $? -ne 0 ]; then
  echo "❌ VALIDATION FAILED: orchestrate.sh spawn failed"
  exit 1
fi

echo "✅ VALIDATION PASSED: Architecture design completed"
```

**If validation fails:**
1. Report error to user
2. Show logs from `~/.claude-octopus/logs/`
3. DO NOT proceed with presenting results
4. DO NOT substitute with direct design

---

### STEP 4: Present Results (Only After Steps 1-3 Complete)

Present the architecture design from the persona execution.

**Include attribution:**
```
---
*Multi-AI Architecture Design powered by Claude Octopus*
*Providers: available external providers + 🔵 Claude*
```

---

# Architecture Skill

Invokes the backend-architect persona for system design during the `grasp` (define) and `tangle` (develop) phases.

## Usage

```bash
# Via orchestrate.sh
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh spawn backend-architect "Design a scalable notification system"

# Via auto-routing (detects architecture intent)
${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh auto "architect the event-driven messaging system"
```

## Capabilities

- API design and RESTful patterns
- Microservices architecture
- Distributed systems design
- Event-driven architecture
- Database schema design
- Scalability planning

## Persona Reference

This skill wraps the `backend-architect` persona defined in:
- `agents/personas/backend-architect.md`
- CLI: `codex`
- Model: `gpt-5.3-codex`
- Phases: `grasp`, `tangle`
- Expertise: `api-design`, `microservices`, `distributed-systems`

## Example Prompts

```
"Design the API contract for the user service"
"Plan the event sourcing architecture"
"Design the caching strategy for the product catalog"
"Create a microservices decomposition plan"
```

## LSP Integration (Claude Code 2.1.14+)

For enhanced structural awareness during architecture design, leverage Claude Code's LSP tools:

### Recommended LSP Tool Usage

1. **Before defining architecture**, gather structural context:
   ```
   lsp_document_symbols - Understand existing module structure
   lsp_find_references  - Identify current dependencies
   lsp_workspace_symbols - Find related patterns across codebase
   ```

2. **During design validation**:
   ```
   lsp_goto_definition  - Verify interface contracts
   lsp_hover           - Check type signatures
   lsp_diagnostics     - Identify type/interface mismatches
   ```

### Example Workflow

```typescript
// Step 1: Understand existing structure
const symbols = await lsp_document_symbols("src/services/user.ts")
const references = await lsp_find_references("UserService", line=5, char=10)

// Step 2: Identify patterns in codebase
const patterns = await lsp_workspace_symbols("Service")

// Step 3: Design new architecture informed by existing patterns
// ... architecture design ...

// Step 4: Validate design with diagnostics
const issues = await lsp_diagnostics("src/services/*.ts")
```

This ensures architecture recommendations align with existing codebase patterns and type contracts.
