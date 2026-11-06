---
name: skill-deck
description: "Generate slide deck presentations from briefs — use when you need slides, pitch decks, or visual summaries"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Cross-reference commands use installed skill names in Codex rather than `/octo:*` slash commands.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `skills/blocks/codex-host-adapter.md`.


# Slide Deck Generator

Generate professional slide decks from briefs with optional research, outline approval, and PPTX export.

## Prerequisites

Inspect the current session's advertised skills. A standalone `pptx` or another
plugin's `pptx` skill is sufficient; plugin ownership is not a prerequisite.
An explicit renderer such as a house-template or Google Slides skill must also
be advertised. Do not infer availability from files on disk.

Set `OCTO_ROOT` to the installed Octopus root identified by this loaded skill or
the host's plugin-root metadata. Verify that it contains
`scripts/helpers/document-renderer.py`. Pass `--format pptx`, one `--available-skill NAME` for
each advertised skill, and `--renderer NAME` or `--template PATH` when the user
supplied them. Quote each argument as data. For example, when `pptx` is exposed:

```bash
python3 "$OCTO_ROOT/scripts/helpers/document-renderer.py" --format pptx \
  --available-skill pptx
```

The helper reads `~/.claude-octopus/document-renderers.json` for saved choices.
Use its returned `skill` and `template`. An unavailable selection or ambiguous
discovery needs correction before rendering; do not silently substitute another
skill. When no renderer is advertised, explain what format capability is missing
and offer installation guidance without installing it automatically. An outline
can still be prepared. See `docs/DOCUMENT-RENDERERS.md` for configuration and
selection precedence.

## Pipeline (4 Steps)

### Step 1: Gather Brief

Parse the user's topic and description. Use **AskUserQuestion** to clarify:

**Question 1 - Audience:**
- Executives / Board
- Engineers / Technical
- Investors / Fundraising
- General / Mixed

**Question 2 - Slide count target:**
- Short (5-10 slides)
- Standard (10-20 slides)
- Extended (20+ slides)

**Question 3 - Tone:**
- Formal / Business
- Technical / Detailed
- Casual / Conversational

If the user already provided clear context (e.g., "10-slide investor pitch deck about our Series A"), skip questions where the answer is obvious.

### Step 2: Research (Optional)

If the topic needs external research or context gathering:

- Use the **host subagent tool** with `Explore` or `general-purpose` subagent to gather relevant information
- For deeper multi-AI research, suggest: "For comprehensive multi-provider research, run `/octo:discover [topic]` first, then `/octo:deck` to build slides from the results"
- If the user provides their own content, notes, or a research file, skip this step entirely

This step is OPTIONAL. Many decks are built from the user's own knowledge or existing documents.

### Step 3: Generate Outline

Build the outline as an answer-first storyline before choosing slide layouts.
Keep the brief's audience, purpose and approved slide-count target.

1. Define one **governing question** from the brief. For a decision deck, state
   the decision, the threshold for yes and an out-of-scope list. For an
   informational brief, state the question the audience needs answered and
   what would count as a useful answer. Do not invent a decision or approval
   ask for an informational update. Confirm the governing question with the user before
   building the skeleton, using **AskUserQuestion**. Reuse an already explicit
   confirmation of that exact question; an unanswered question is not approval.
2. Write an **SCQA opener** with the situation, complication and question.
   The question must match the confirmed governing question. Keep the opener
   brief and use supplied or sourced facts; mark evidence gaps rather than
   inventing context.
3. Write a **working hypothesis**: a one-sentence answer with two to four pillars
   that must be true. Tie each pillar to available evidence or label it as an
   assumption to validate. An informational deck's answer can be a conclusion
   about results rather than a recommendation to approve something.
4. Build the **sentence skeleton** with one declarative sentence per slide,
   in order. Each title must make a claim that advances the answer. Under each
   title, record its supporting evidence and intended visual. Keep unverified
   claims marked as assumptions; do not turn them into asserted facts.

For example, a decision storyline could use this shape. Replace bracketed
material with supported claims before presenting it as ready for approval:

```markdown
## Governing question
Should we [action] by [date], given [decision threshold]?
- Out of scope: [excluded topics]

## SCQA opener
- Situation: [established context]
- Complication: [change that makes the question matter]
- Question: [the confirmed governing question]

## Working hypothesis
[One-sentence answer], because [two to four evidence-backed pillars].

## Slide 1: [The audience should take a specific action by a specific date]
- Context and the decision at stake

## Slide 2: [The recommendation meets the agreed decision threshold]
- Supporting pillars and the specific ask

## Slide 3: [A specific proof point supports the first pillar]
- Evidence, source and planned visual

## Slide N: [The requested action unlocks a specific outcome]
- Ask, owner and next step
```

#### Storyline gate: titles-only read

Read only the slide-title sentences, top to bottom. They must carry the
argument from the governing question to the ask without relying on body
bullets. For informational decks, read from the question to the supported
conclusion and follow-up instead. Label titles fail: "Market overview",
"Financials" and "Next steps" name topics without saying what the audience
should understand. Rewrite them as supported declarative claims. If the
argument skips a pillar, contradicts the hypothesis or ends without answering
the question, revise the skeleton and repeat the titles-only read before
asking for outline approval. A passing titles-only read does not establish
that the evidence is true or that rendered slides have been inspected.

Present the confirmed question, opener, hypothesis and sentence skeleton with
its evidence notes for approval using **AskUserQuestion**:

- "Looks good, render the deck" - Proceed to Step 4 with the selected renderer
- "Add more slides" - Expand specific parts, then repeat the titles-only read
- "Change focus" - Revise the question if needed, confirm it and rebuild the storyline
- "Start over" - Return to Step 1

This is the **wireframe gate**. The user MUST approve the sentence skeleton before PPTX generation.
Changing the governing question or slide claims after approval returns to
this gate. Pass the approved sentences to the renderer as the slide titles.

### Step 4: Render the approved deck

Once the outline is approved:

1. Invoke the resolved renderer skill using its advertised host invocation.
2. Pass the approved slide skeleton, visual callout plan, appendix list and
   selected template together. Use empty callout or appendix lists when none
   were approved; do not invent material to fill them.
3. Preserve the approved titles, content and template requirements. Follow the
   selected skill's format and authentication rules. Stop on an unsupported
   format or template instead of silently changing the renderer.
4. For a PPTX renderer, save a descriptively named file in the working directory
   and report the actual saved artifact path in the response.
   For a native Slides renderer, report the actual deck URL. Follow its approval
   rules for publication and sharing. On failure, report the failure and retain
   the approved outline; do not claim a finished deck.

Example filename: `Series-A-Pitch-Deck-2026-02-14.pptx`

## Slide Structure Best Practices

Apply these when generating outlines:

- **Title slide**: Presentation name, subtitle, date, presenter
- **Storyline**: Slide titles carry the argument in the approved sentence order
- **One idea per slide**: Keep slides focused
- **5-7 bullets max**: Per slide for readability
- **Summary slide**: State the supported answer to the governing question
- **Next steps / CTA**: Final slide with clear actions

### By Audience Type

**Executives / Board:**
- Lead with business impact and metrics
- Use "So what?" framing for every slide
- Include financial implications
- End with decisions needed

**Engineers / Technical:**
- Include architecture diagrams (describe for slides)
- Show trade-offs and alternatives considered
- Include implementation timelines
- Reference technical specifications

**Investors / Fundraising:**
- Problem → Solution → Market → Traction → Team → Ask
- Include market size (TAM/SAM/SOM)
- Show growth metrics and projections
- Clear funding ask and use of funds

**General / Mixed:**
- Balance detail with accessibility
- Define technical terms
- Use analogies and examples
- Include visual descriptions

## Integration with Other Skills

This skill works well in combination with:

- `/octo:discover [topic]` — Research first, then build deck from findings
- `/octo:docs` — For converting existing markdown to other formats
- `/octo:prd` — Generate a PRD, then create a presentation summarizing it
- `/octo:brainstorm` — Brainstorm ideas, then structure into a deck

## Example Workflows

### Quick Deck from Brief
```
User: "Create a 10-slide deck about our Q1 results"
→ Step 1: Clarify audience (executives)
→ Step 2: Skip (user has the data)
→ Step 3: Confirm the question, check the sentence skeleton, get approval
→ Step 4: Render PPTX
```

### Research-Backed Deck
```
User: "Build a presentation about AI trends in healthcare"
→ Step 1: Clarify audience and scope
→ Step 2: Research using Task agents
→ Step 3: Confirm the question, build a sourced sentence skeleton, get approval
→ Step 4: Render PPTX
```

### Deep Research + Deck
```
User: "I need a comprehensive investor deck about the autonomous vehicles market"
→ Suggest: "/octo:discover autonomous vehicles market" first
→ Then: "/octo:deck" using the research synthesis
```


*Slide deck skill for claude-octopus.*
