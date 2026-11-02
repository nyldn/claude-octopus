---
name: skill-council
disable-model-invocation: true
description: "Run a configurable multi-LLM council with personas, budget caps, synthesis, veto gates, and optional implementation handoff."
---

# Council

Use this skill for `/octo:council` and council-style requests.

## EXECUTION CONTRACT: MANDATORY

`/octo:council` is a runner-backed workflow. Execute the real shell runner by default:

```bash
"${CLAUDE_PLUGIN_ROOT:-$HOME/.claude-octopus/plugin}/scripts/orchestrate.sh" council <user arguments>
```

**Sandbox-safe invocation (required under Claude Code's sandbox).** `orchestrate.sh`
must be the FIRST token of the command. The sandbox's unsandboxed-command allowlist is a
leading-anchored prefix match, so a command that begins with `cd …`, an inline
`VAR=… ` env-assignment, or any other prefix will NOT match an `…/orchestrate.sh *`
entry — the runner then executes sandboxed and its `codex`/`agy` seat children fail to
write temp files (`Operation not permitted`, agy `mkstemp` in `/var/folders`), so the
council abandons the runner and falls back to direct single-provider dispatch. To run
against a worktree, pass `--dir <path>` (the runner already honors `-d/--dir`) instead
of wrapping in `cd <path> && …`; set any environment in a separate prior step or via a
leading `env VAR=… /abs/path/orchestrate.sh council …` so the resolvable binary path is
still first. Never prefix the runner with `cd`.

Do not simulate a council, role-play all members inside the current model, or answer directly in place of the runner. A single-model simulation must be explicitly requested with `--simulate` or `--single-model`; when used, label the output as `single-model simulation` and keep the generated `summary.json` path visible. Otherwise, missing provider quorum is a partial/failed council, not permission to silently downgrade.

## Phase 0A: Interactive Clarification

If the user invokes `/octo:council` with an ambiguous task, missing goal/depth intent, uncertain implementation permission, or unclear research/corpus expectations, use `AskUserQuestion` before running the council runner. If the prompt already includes clear flags and a clear task, skip this phase and execute immediately.

Use 2-4 mutually exclusive choices per question, put the recommended option first, and map the answers to runner flags before execution. Do not end with a free-form question or a set of questions; present the choice interaction and wait for the answer.

Default council clarification:

```javascript
AskUserQuestion({
  questions: [
    {
      question: "How should the council handle this request?",
      header: "Council Goal",
      multiSelect: false,
      options: [
        {label: "Advice (Recommended)", description: "Return a structured recommendation without implementation"},
        {label: "Decision", description: "Optimize for choosing between specific options"},
        {label: "Implementation plan", description: "Produce a plan but do not edit files"},
        {label: "Review", description: "Critique existing code, docs, or strategy"}
      ]
    },
    {
      question: "How deep should the council go?",
      header: "Depth",
      multiSelect: false,
      options: [
        {label: "Standard (Recommended)", description: "Balanced cost and coverage"},
        {label: "Quick", description: "Faster, lower-cost pass"},
        {label: "Deep", description: "More critique and revision, higher cost"}
      ]
    },
    {
      question: "Should the council use project research or corpus storage?",
      header: "Context",
      multiSelect: false,
      options: [
        {label: "No corpus (Recommended)", description: "Run with the provided prompt and write normal run artifacts"},
        {label: "Research first", description: "Add --research-first before provider fanout"},
        {label: "Append corpus", description: "Use --corpus-mode append for durable project notes"},
        {label: "Require corpus", description: "Use --corpus-mode require and stop if no corpus workspace exists"}
      ]
    }
  ]
})
```

Translate answers as follows:

- Advice, Decision, Implementation plan, or Review -> `--goal advice|decision|plan|review`
- Quick, Standard, or Deep -> `--depth quick|standard|deep`
- Research first -> `--research-first`
- Append corpus or Require corpus -> `--corpus-mode append|require`

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
- whether research must happen before council fanout (`--research-first`)
- whether findings, research, synthesis, and plans must be appended to the project corpus (`--corpus-mode append|require`)

Show the selected council, provider availability, benchmark freshness, quorum requirement, and cost estimate before provider fanout. Re-check the budget before critique, revision, synthesis, and implementation planning so the run stops before the next phase would exceed `--max-cost`. If the run is a dry run, stop after this preflight and write `summary.json`.

If `--research-first` is set, gather local corpus evidence first, then current external sources when allowed. Store concise findings as run artifacts before provider fanout. If `--corpus-mode append` or `--corpus-mode require` is set, append the research notes, findings, synthesis, and implementation plan to the project's durable corpus conventions before claiming completion; `require` must stop when no corpus workspace is available.

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

## Interactive Choice Handling

When the user needs to clarify scope, select a depth/provider/corpus option, approve a gate, or decide between follow-up actions, use `AskUserQuestion` with 2-4 mutually exclusive choices. Put the recommended choice first. Do not end with a free-form question or a set of questions; present the choice interaction and wait for the answer.
