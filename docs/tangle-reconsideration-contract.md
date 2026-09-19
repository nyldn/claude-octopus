# Tangle reconsideration JSON v1

Planner reconsideration uses a schema-versioned JSON contract. Every adequacy `scope_review` recommendation must have exactly one matching `action` + `path` decision (`accept` or `reject`) with non-empty rationale; extra recommendation identities are rejected. The nested `decomposition` uses the existing Tangle decomposition JSON v1 contract.

The runtime renders `decisions` to human-readable planner adjudication and renders the nested decomposition into the historical internal wire representation for downstream scope/execution logic. The old `DECISIONS:/DECOMPOSITION:` response remains a deprecated compatibility fallback.

`OCTOPUS_TANGLE_RECONSIDERATION_CONTEXT_BUDGET_RATIO` defaults to `90` (range 60-100) and applies only to this supervised `phase=tangle`, `role=researcher` reconsideration call. Ordinary decomposition researcher dispatches keep the normal 60% role quota.
