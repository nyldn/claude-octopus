---
description: "\"Multi-LLM council for advice, decision support, implementation plans, and gated implementation\""
---

# Council

Use `/octo:council <task>` when the user wants a structured council of multiple LLM personas to advise, critique, synthesize, and optionally hand off an approved implementation plan.

## MANDATORY COMPLIANCE

Run the real Octopus runner by default. Your council execution action must resolve the plugin root and call:

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/orchestrate.sh" council $ARGUMENTS
```

If `CLAUDE_PLUGIN_ROOT` is unset, use `${HOME}/.claude-octopus/plugin/scripts/orchestrate.sh`.

PROHIBITED: Do not simulate a council, role-play multiple personas inside one model, or answer directly unless the user explicitly passes `--simulate` or `--single-model`. If simulation is requested, label it as `single-model simulation` in the response and preserve the runner's `summary.json` path.

Run through `skill-council` for preflight, research-first handling, artifact review, and gate handling, but do not let the skill replace the shell runner. Do not skip provider/cost preflight, quorum checks, run artifacts, or implementation gates.

When clarification or options are needed before execution, use `AskUserQuestion` with 2-4 mutually exclusive choices per question, then run the real council runner with the selected flags. Do not end the response with a loose question or a list of questions.

### Interactive Clarification Before Execution

If the task, goal, depth, implementation permission, research mode, or corpus handling is ambiguous, ask before running the council runner:

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
        {label: "Research first", description: "Gather local corpus context before provider fanout"},
        {label: "Append corpus", description: "Append research, synthesis, and plans to the project corpus"},
        {label: "Require corpus", description: "Stop if no durable corpus workspace is available"}
      ]
    }
  ]
})
```

If the user already provided clear flags and a clear task, skip clarification and execute immediately.

## Examples

```text
/octo:council --depth quick --goal advice "Should we use Redis here?"
/octo:council --goal decision --domain architecture "Should this service stay monolithic?"
/octo:council --goal implement --implement plan-only "Refactor the auth flow"
/octo:council --dry-run --members 7 --persona finance-analyst "Review this pricing strategy"
```

## Flags

- `--goal advice|decision|plan|implement|review`
- `--domain auto|architecture|product|security|business|research|docs`
- `--style balanced|adversarial|implementation|executive|red-team`
- `--depth quick|standard|deep`
- `--members auto|3|5|7`
- `--persona <name>[,<name>]`
- `--implement never|after-approval|plan-only`
- `--worktree auto|on|off`
- `--benchmark auto|on|off`
- `--providers auto|claude,codex,gemini,agy,opencode,openrouter`
- `--max-cost <usd>`
- `--simulate`
- `--single-model`
- `--research-first`
- `--corpus-mode off|append|require`
- `--dry-run`
- `--json`
- `--output-dir <path>`
