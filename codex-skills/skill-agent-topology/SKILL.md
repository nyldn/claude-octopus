---
name: skill-agent-topology
description: "Audit whether a multi-agent setup earns its coordination cost — use before adding an agent, or when a workflow feels slow or agents agree without adding signal"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.


# Agent Topology Audit

Most advice about multi-agent systems is about how to add agents. This is about
whether to. It audits a setup you already have, counts what each boundary
between agents costs, and compares that against what the boundary buys. Removing
an agent is a valid, and often the correct, result.

The framing comes from Liu, Canhui (2026), *The Organizational Behavior of
Agentic AI* ([arXiv:2606.30986](https://arxiv.org/abs/2606.30986)), which models
coordination overhead as **contextual transaction cost** — the cost of making
task context usable across an agent boundary.

## When To Use

- Before adding another agent, seat, or phase to a workflow that already works.
- When a workflow is slow and it is not obvious which part is earning its time.
- When agents keep agreeing. Agreement that costs three dispatches and produces
  what one would have produced is overhead wearing the costume of consensus.
- When a handoff keeps losing something and the fix keeps being "add more
  context to the prompt".
- After a workflow produced a bad result and you want to know whether the
  topology or the models were at fault.

## When Not To Use

- To pick a workflow for a new task. That is `/octo:auto`, which already routes
  by intent, or `skill-decision-support` for a general option comparison.
- To decide whether to delegate a task to agents at all. That is the allocation
  step in `skill-intent-contract`.
- To choose between providers or models. See `skills/blocks/frontier-model-routing.md`.
- For a single-agent task. There are no boundaries to count.

## Inputs

- The workflow or setup under audit: which agents or seats, in what order, with
  what passing between them.
- What each agent receives and what it returns. Prompt and output shape matter
  more than model identity here.
- Optionally, a transcript or run directory, which turns estimates into
  observations.

If the setup is only described rather than run, say so in the output. An audit
of a described topology is a prediction; an audit of a transcript is a
measurement.

## Workflow

### 1. Draw the boundaries

List every point where context crosses from one agent to another. Include the
entry boundary (human to first agent) and the exit boundary (last agent to
human) — they cost too, and the exit boundary is where synthesis quality is
usually won or lost.

Count them. The number of boundaries, not the number of agents, is what drives
coordination cost. Three agents in a star cost fewer crossings than three in a
chain.

### 2. Name what is lost at each boundary

For each crossing, work through these and record only the ones that actually
apply. Naming a cost that is not present is as unhelpful as missing one:

- **Token and latency burden** — what it costs to restate context.
- **Handoff** — what the receiving agent needs that the sending agent held but
  did not pass.
- **Compression loss** — what got summarised away. Free-text summary between
  agents is the usual culprit.
- **Semantic drift** — where the receiver's reading of a term differs from the
  sender's.
- **Verification burden** — work spent checking the other agent rather than
  doing the task.
- **Governance** — approvals, gates, and waiting.

### 3. Name what the boundary buys

A boundary is earned only by a gain that a single agent could not produce:

- **Specialisation** — genuinely different capability, not a different label on
  the same model.
- **Parallelism** — real wall-clock reduction on independent work.
- **Cross-vendor diversity** — different training data and different blind
  spots. Note that same-family agreement is not this; see
  `skills/blocks/frontier-model-routing.md`.
- **Adversarial review** — a seat whose job is to disagree, where disagreement
  is the product.

### 4. Compare against the single-expert null

The baseline is always one capable agent doing the whole task. The cited
research found human-imitation topologies — pipelines, manager hierarchies, and
committees deliberating in free text — measuring *below* that baseline, while
agent-native forms built around shared memory measured above it. The single
expert stays competitive precisely because it pays no internal transaction cost.

So the **burden of proof falls on the boundary**. Absent a gain term that a
single agent could not deliver, the recommendation is to collapse.

Treat this as a directional prior, not proof. It is one simulation study plus
model traces, and it is the source of the framing rather than a measurement of
your setup. Effect sizes from that paper are deliberately not reproduced here:
they describe the study's conditions, not yours.

**One caveat that changes the reading, and must not be skipped.** What the study
penalised was committee deliberation in free text with no independent evidence —
agents talking to each other about the same information. Providers that bring
genuinely independent evidence, different models with different training data
and real web search, are not that committee. `/octo:debate` and `/octo:council`
are therefore better positioned than the studied form. The problem those results
identify is the handoff, not the panel.

### 5. Reuse the overlap gate that already exists

Do not invent a new "is this agent adding anything" metric. The council roster
already has one: `council_persona_overlap_score` in `scripts/lib/council.sh`
computes a Jaccard index over persona capability tokens, and the roster builder
drops a candidate above `OCTOPUS_COUNCIL_DEDUP_THRESHOLD` (default 0.65).

Apply the same idea one level down. Two agents whose *inputs* overlap that
heavily are usually one agent with two prompts.

## Provider Or Data Priority

1. A real transcript or run directory, if one exists.
2. The workflow definition, for boundaries not exercised in that run.
3. The user's description, flagged as unverified.

Prefer counting observed crossings over reasoning about intended ones. Workflows
routinely skip or repeat boundaries at runtime.

## Stop Or Checkpoint Rules

- Stop and ask if the setup cannot be enumerated. An audit of a topology you had
  to guess at is not evidence.
- Stop before recommending removal of a boundary that exists for a safety,
  approval, or compliance reason. Coordination cost is not the only axis, and
  this diagnostic does not price the others.
- If every boundary is earned, say so and stop. A clean audit is a real result;
  manufacturing a finding to look useful is worse than none.

## Output Contract

Report in this order:

1. **Verdict** — one of: collapse to a single agent; remove specific boundaries;
   keep as is; restructure from chain to shared context.
2. **Boundary table** — one row per crossing: what crosses, dominant cost term,
   gain term claimed, and whether the gain is real.
3. **What the single expert would have produced** — the null, stated concretely
   enough to compare against.
4. **For each boundary kept, what carries context across it** — the specific
   artifact, file, or state that survives the crossing. A boundary kept without
   naming this is a boundary that will keep losing information.
5. **Confidence and basis** — measured from a transcript, or predicted from a
   description.

## Verification

- Every boundary in the table maps to a real handoff in the setup, nameable in
  the workflow definition or transcript.
- Every claimed gain names the specific thing a single agent could not have
  produced. "Diversity" alone does not qualify; different training data or a
  different evidence source does.
- Any cost term listed is one you can point at a concrete instance of.
- The verdict follows from the table. If the table shows no earned boundary and
  the verdict is "keep as is", one of the two is wrong.
