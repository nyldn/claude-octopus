## Pre-Discovery: Optional Project Persistence

Workflow state is stored in the host workspace by default. Only create the
project-local `.octo/` lifecycle artifacts when the user explicitly opts in by
setting `OCTOPUS_PROJECT_PERSISTENCE=true`.

```bash
# Restore the literal OCTO_ROOT and RUN_ID emitted by the new-run bootstrap.
if [[ "${OCTOPUS_PROJECT_PERSISTENCE:-false}" == "true" ]]; then
  HANDOFF_STATE_FILE=$("${OCTO_ROOT:?}/scripts/state-manager.sh" handoff_path) || exit 1
  python3 "$OCTO_ROOT/scripts/helpers/discovery-handoff.py" prepare "$HANDOFF_STATE_FILE" "${RUN_ID:?Restore the discovery run ID}" || exit 1
fi
```


## Native Plan Mode Compatibility (v7.23.0+)

**IMPORTANT:** claude-octopus workflows are designed to persist across context clearing.

### Detecting Native Plan Mode

Check if native plan mode is active:

```bash
# Check for native plan mode markers
if [[ -n "${PLAN_MODE_ACTIVE}" ]] || claude-code plan status 2>/dev/null | grep -q "active"; then
    echo "⚠️  Native plan mode detected"
    echo ""
    echo "   Resolve Claude Octopus workflow state with: octopus state-path"
    echo "   State will persist across plan mode context clears"
    echo "   Multi-AI orchestration will continue normally"
    echo ""
fi
```

### State Persistence Across Context Clearing

**How it works:**
- Native plan mode may clear Claude's memory via `ExitPlanMode`
- Claude Octopus workflow state persists in the host workspace, namespaced by project; resolve its exact path with `state-manager.sh state_path`
- Each workflow phase reads prior state at startup
- Context is automatically restored from files

**No action required** - state management handles this automatically via STEP 3 in the execution contract.


## ⚠️ EXECUTION CONTRACT (MANDATORY - CANNOT SKIP)

This skill uses **ENFORCED execution mode**. You MUST follow this exact sequence.

### STEP 1: Detect Work Context (MANDATORY)

Analyze the user's prompt and project to determine context:

**Knowledge Context Indicators**:
- Business/strategy terms: "market", "ROI", "stakeholders", "strategy", "competitive", "business case"
- Research terms: "literature", "synthesis", "academic", "papers", "personas", "interviews"
- Deliverable terms: "presentation", "report", "PRD", "proposal", "executive summary"

**Dev Context Indicators**:
- Technical terms: "API", "endpoint", "database", "function", "implementation", "library"
- Action terms: "implement", "debug", "refactor", "build", "deploy", "code"

**Also check**: Does project have `package.json`, `Cargo.toml`, etc.? (suggests Dev Context)

**Capture context_type = "Dev" or "Knowledge"**

**DO NOT PROCEED TO STEP 2 until context determined.** Context type (Dev vs Knowledge) determines which provider prompts to use — wrong context produces irrelevant research that wastes provider credits.


### STEP 2: Display Visual Indicators (MANDATORY - BLOCKING)

**MANDATORY: You MUST use the native shell command tool to run this provider check BEFORE displaying the banner. Do NOT skip it. Do NOT assume availability.**

```bash
bash "${OCTO_ROOT:?}/scripts/helpers/check-providers.sh"
```

**Use the ACTUAL results below. PROHIBITED: Showing only "🔵 Claude: Available ✓" without listing all providers.**

If `OCTO_ALLOWED_PROVIDERS` is set, treat it as the source of truth for which providers may participate. Providers filtered out by that allowlist are intentionally reported as unavailable; do not invoke or recommend them in the workflow.


**Display this banner BEFORE orchestrate.sh execution:**

**For Dev Context:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 [Dev] Discover Phase: [Brief description of technical research]

Provider Availability:
🔴 Codex CLI: ${codex_status}
🟡 Antigravity CLI: ${agy_status}
🧭 Antigravity CLI: ${agy_status}
🟣 Perplexity: ${perplexity_status}
🔵 Claude: Available ✓ (Strategic synthesis)

💰 Estimated Cost: 0.01-0.08 USD
⏱️  Estimated Time: 2-5 minutes
```

**For Knowledge Context:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 [Knowledge] Discover Phase: [Brief description of strategic research]

Provider Availability:
🔴 Codex CLI: ${codex_status}
🟡 Antigravity CLI: ${agy_status}
🧭 Antigravity CLI: ${agy_status}
🟣 Perplexity: ${perplexity_status}
🔵 Claude: Available ✓ (Strategic synthesis)

💰 Estimated Cost: 0.01-0.08 USD
⏱️  Estimated Time: 2-5 minutes
```

**DO NOT PROCEED TO STEP 3 until banner displayed.** The banner shows users which providers will run and what costs they'll incur — starting API calls without this visibility violates cost transparency.


### STEP 3: Read Prior State (MANDATORY - State Management)

**Before executing the workflow, read any prior context:**

```bash
# Initialize state if needed
"${OCTO_ROOT:?}/scripts/state-manager.sh" init_state

# Set current workflow
"${OCTO_ROOT:?}/scripts/state-manager.sh" set_current_workflow "flow-discover" "discover"

# Get prior decisions (if any)
prior_decisions=$("${OCTO_ROOT:?}/scripts/state-manager.sh" get_decisions "all")

# Get context from previous phases
prior_context=$("${OCTO_ROOT:?}/scripts/state-manager.sh" read_state | jq -r '.context')

# Display what you found (if any)
if [[ "$prior_decisions" != "[]" && "$prior_decisions" != "null" ]]; then
  echo "📋 Building on prior decisions:"
  echo "$prior_decisions" | jq -r '.[] | "  - \(.decision) (\(.phase)): \(.rationale)"'
fi
```

**This provides context from:**
- Prior workflow phases (if resuming a session)
- Architectural decisions already made
- User vision captured in earlier phases
- If **claude-mem** is installed, its MCP tools (`search`, `timeline`, `get_observations`) are available — use them to check for relevant past session context before launching research agents

**DO NOT PROCEED TO STEP 4 until state read.**


### STEP 3.5: Parse Intensity & Build Agent Fleet (MANDATORY)

**Parse the `breadth` and `intensity` parameters from the skill args.** The args string may start with `[breadth=light|standard|exhaustive]` and/or `[intensity=quick|standard|deep]`. If only breadth is specified, map `light -> quick`, `standard -> standard`, and `exhaustive -> deep`. If neither is specified, default to `"standard"` (backward compatible with `/octo:embrace` which doesn't pass intensity).

**Build the fleet dynamically using `build-fleet.sh`** — this is the single source of truth for provider-to-perspective assignment. It detects ALL available providers (codex, agy, copilot, qwen, opencode, ollama, perplexity, openrouter) and assigns perspectives with model family diversity enforcement.

```bash
FLEET_OUTPUT=$("${OCTO_ROOT:?}/scripts/helpers/build-fleet.sh" research "${INTENSITY}" "${PROMPT}" 2>/dev/null)
```

The output is one line per agent: `agent_type|label|perspective_prompt`

**Parse each line into the fleet array:**
- `agent_type`: the provider to dispatch (codex, agy, copilot, qwen, opencode, claude-sonnet, perplexity, etc.)
- `label`: human-readable name (e.g., "Problem Analysis", "Ecosystem Overview", "Contrarian Analysis")
- `perspective_prompt`: the angle-specific prompt to send to that provider
- `task_id`: generate as `probe-${RUN_TIMESTAMP}-${RUN_NONCE}-<index>` for each entry

**Fleet sizes by intensity:**

| Intensity | Agents | Behavior |
|-----------|--------|----------|
| **Quick** | 2 | Two most diverse providers |
| **Standard** | 4-5 | Rotates across available providers + Claude for edge cases and codebase analysis |
| **Deep** | 6-10 | ALL available providers get unique perspectives (bonus slots for copilot, qwen, opencode, etc.) |

**Model family diversity is enforced automatically** — the script prioritizes spreading agents across different model families (OpenAI, Google, Microsoft, Alibaba, Anthropic) to avoid agreement bias from same-family models.

**DO NOT hardcode provider assignments.** Always use build-fleet.sh output. If the script is unavailable, fall back to the available-provider path (for example codex + agy + claude-sonnet when installed).

**DO NOT PROCEED TO STEP 4 until the fleet is built.**


Restore the printed bootstrap assignments in each shell; never generate another
identity here. Use `probe-${RUN_TIMESTAMP}-${RUN_NONCE}-<index>` for every probe task ID. Do not call `date` again for this run; every probe artifact, the synthesis file, and verification must carry this same identity.
