---
name: skill-council
description: "Run a configurable multi-LLM council with personas, budget caps, synthesis, veto gates, and optional implementation handoff."
---

# Council

Use this skill for `/octo:council` and council-style requests.

## Phase 0: Preflight

Collect or infer:

- goal: `advice`, `decision`, `plan`, `implement`, or `review`
- domain: `auto`, `architecture`, `product`, `security`, `business`, `research`, or `docs`
- style: `balanced`, `adversarial`, `implementation`, `executive`, or `red-team`
- depth: `quick`, `standard`, or `deep`
- members: `auto`, `3`, `5`, or `7`
- budget cap in USD
- providers and provider availability
- pinned personas
- implementation permission and worktree isolation

Show the selected council, provider availability, benchmark freshness, quorum requirement, and cost estimate before provider fanout. Re-check the budget before critique, revision, synthesis, and implementation planning so the run stops before the next phase would exceed `--max-cost`. If the run is a dry run, stop after this preflight and write `summary.json`.

## Quorum

- quick requires at least one non-chair response plus a synthesis-capable chair
- standard and deep require at least two non-chair responses plus a synthesis-capable chair
- if the chair fails, retry once with the highest-scoring synthesis-capable fallback
- if quorum is lost, stop by default and present partial artifacts instead of pretending consensus exists

## Council Procedure

1. **Independent advice:** ask each selected persona for recommendation, assumptions, risks, implementation notes, and confidence.
2. **Cross-critique:** for standard/deep runs, semi-anonymize responses and ask members to critique gaps, assumptions, and risks.
3. **Revision:** for deep runs or high disagreement, let members revise their positions after critique.
4. **Chair synthesis:** produce agreement, disagreement, minority reports, risk register, implementation path, confidence, and conditions that would change the recommendation.
5. **Ratify / veto:** verifier, red-team, security, legal, finance, and medical roles can veto implementation for critical risks.

## Implementation Gates

- **Gate A:** user accepts the council synthesis or asks for revision.
- **Gate B:** user accepts the concrete implementation plan generated from the synthesis.
- **Gate C:** execution proceeds through existing Octopus implementation safety behavior. This is a one-shot authorization for the accepted plan, not per-file approval, unless existing safety hooks detect destructive or risky actions.

Never implement from council output without explicit approval. Preserve disagreement, summarize risks, and keep vetoes visible in the final answer and artifacts.
