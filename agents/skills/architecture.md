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
