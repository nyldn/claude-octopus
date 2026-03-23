---
name: octopus-architecture
version: 1.0.0
description: "Design system architecture and APIs using multi-AI consensus via the backend-architect persona. Use when: user says 'design the architecture', 'plan the API', 'microservices decomposition', 'design database schema', 'architect the system', or needs multi-provider architecture decisions."
---

## EXECUTION CONTRACT (MANDATORY - CANNOT SKIP)

This skill uses **ENFORCED execution mode**. You MUST follow this exact sequence.

### STEP 1: Display Visual Indicators (MANDATORY - BLOCKING)

Check provider availability and display banner BEFORE orchestrate.sh execution:

```bash
command -v codex &> /dev/null && codex_status="Available" || codex_status="Not installed"
command -v gemini &> /dev/null && gemini_status="Available" || gemini_status="Not installed"
```

```
CLAUDE OCTOPUS ACTIVATED - Architecture design mode
Architecture: [Brief description of system to design]

Provider Availability:
Codex CLI: ${codex_status} - Backend architecture patterns
Gemini CLI: ${gemini_status} - Alternative approaches
Claude: Available - Synthesis and recommendations

Estimated Cost: $0.02-0.08
Estimated Time: 3-7 minutes
```

- If BOTH Codex and Gemini unavailable: STOP, suggest `/octo:setup`
- If ONE unavailable: Continue with available provider(s)

**DO NOT PROCEED TO STEP 2 until banner displayed.**

### STEP 2: Execute orchestrate.sh spawn (MANDATORY - Use Bash Tool)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh spawn backend-architect "<user's architecture request>"
```

You are PROHIBITED from designing architecture directly without calling orchestrate.sh, simulating the workflow, or proceeding without running this command.

### STEP 3: Verify Execution (MANDATORY - Validation Gate)

Check exit code. If validation fails: report error, show logs from `~/.claude-octopus/logs/`, DO NOT substitute with direct design.

### STEP 4: Present Results (Only After Steps 1-3 Complete)

Present the architecture design from the persona execution with attribution.

## Capabilities

- API design and RESTful patterns
- Microservices architecture and decomposition
- Distributed systems and event-driven architecture
- Database schema design and scalability planning

## Usage

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh spawn backend-architect "Design a scalable notification system"
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh auto "architect the event-driven messaging system"
```

## Persona Reference

Wraps the `backend-architect` persona (`agents/personas/backend-architect.md`):
- CLI: `codex` | Model: `gpt-5.3-codex`
- Phases: `grasp`, `tangle`
- Expertise: `api-design`, `microservices`, `distributed-systems`

## LSP Integration (Claude Code 2.1.14+)

Before defining architecture, gather structural context with LSP tools:
- `lsp_document_symbols` - Understand existing module structure
- `lsp_find_references` - Identify current dependencies
- `lsp_workspace_symbols` - Find related patterns across codebase

During design validation:
- `lsp_goto_definition` - Verify interface contracts
- `lsp_diagnostics` - Identify type/interface mismatches
