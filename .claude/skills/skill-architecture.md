---
name: octopus-architecture
description: |
  System architecture and design skill leveraging the backend-architect persona.
  Use for API design, microservices patterns, and distributed systems planning.
---

# Architecture Skill

Invokes the backend-architect persona for system design during the `grasp` (define) and `tangle` (develop) phases.

## Usage

```bash
# Via orchestrate.sh
./scripts/orchestrate.sh spawn backend-architect "Design a scalable notification system"

# Via auto-routing (detects architecture intent)
./scripts/orchestrate.sh auto "architect the event-driven messaging system"
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
- Model: `gpt-5.1-codex-max`
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
