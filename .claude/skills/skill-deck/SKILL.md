---
name: skill-deck
disable-model-invocation: true
aliases:
  - deck
  - slides
  - presentation
description: Generate slide deck presentations from briefs — use when you need slides, pitch decks, or visual summaries
trigger: |
  EXPLICITLY USE when user requests:
  - "create a deck", "build slides", "make a presentation"
  - "generate a pitch deck", "create board presentation"
  - "slide deck for [topic]", "presentation about [topic]"
  - "investor deck", "strategy presentation", "project update slides"

  DO NOT activate for:
  - Converting existing markdown to PPTX (use /octo:docs instead)
  - General file conversions (use document-skills directly)
---

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

- Use the **Task tool** with `Explore` or `general-purpose` subagent to gather relevant information
- For deeper multi-AI research, suggest: "For comprehensive multi-provider research, run `/octo:discover [topic]` first, then `/octo:deck` to build slides from the results"
- If the user provides their own content, notes, or a research file, skip this step entirely

This step is OPTIONAL. Many decks are built from the user's own knowledge or existing documents.

### Step 3: Generate Outline

Build a slide-by-slide outline in Markdown format. For Executives / Board,
infer the purpose from the brief. When it calls for a decision, use the
executive and board outline below. For an informational brief such as a
Q1 results update, do not require a decision or approval ask. Use the general
structure with an executive summary on slide 2 covering results, key drivers
and implications, then evidence and follow-up. Do not invent a decision to
fit the template. If the purpose is unclear, clarify it before outlining.
For other audiences, use this general structure:

```markdown
## Slide 1: [Title Slide]
- Presentation title
- Subtitle / Date / Author

## Slide 2: [Agenda / Overview]
- Key topics to cover

## Slide 3: [First Content Section]
- Bullet point 1
- Bullet point 2
- Bullet point 3

## Slide N: [Summary / Next Steps]
- Key takeaways
- Call to action
```

#### Executive and board outline

For decision briefs, put the decision on slide 2. Use this structure instead of the agenda-first
template or a summary saved for the end. Expand evidence slides as needed;
agree the main-deck and appendix slide counts within the user's target.
Combine the evidence and decision slides for a five-slide total, keeping
the executive summary on slide 2 and an appendix. If the required material,
including one backup slide per expected question, cannot fit, ask the user to
approve a larger target before expanding it. The six-slide example is not a
minimum slide count.

```markdown
## Slide 1: [Decision topic]
- Presentation title, date and presenter

## Slide 2: Executive summary: [recommendation]
- One recommendation sentence with a by-when
- One line of context
- Two or three supporting pillars
- The specific ask and what approval unlocks

## Slide 3: [Why the recommended option beats the alternatives]
- Recommended option: benefit, cost and trade-offs
- Do nothing: cost and consequences over the same time horizon
- At least one real alternative: benefit, cost and trade-offs

## Slide 4: [The evidence supports a specific conclusion]
- One proof point for this data slide, with its source
- Chart highlight: the single figure that supports the title

## Slide 5: [Approve the specific next action by the decision date]
- Repeat the same recommendation and by-when
- Explicit ask: the approval, amount or named resource the audience can grant
- What approval unlocks and who owns the next action

## Slide 6: Appendix: [Expected question]
- Backup evidence answering this expected question
```

#### Board outline check

For decision briefs, check the following before asking for outline approval:

- Could the audience make the requested decision from slide 2 alone? It must
  lead with one recommendation, then context, two or three pillars, the ask
  and what approval unlocks. Keep the same recommendation and deadline
  throughout the deck.
- Does the options comparison include doing nothing, its cost and at least
  one real alternative? Use a common time horizon and cite cost estimates.
- Is the ask something this audience can grant, such as a specific approval,
  amount or named resource, with a by-when? "Support" alone is insufficient.
- Does every data slide have one proof point and a chart highlight tied to
  the single figure claimed by its title? Include the source and the intended
  highlight in the outline passed to the renderer.
- Is there one backup slide per expected question in the appendix? Name the
  questions and include the appendix in the outline submitted for approval.

Do not invent costs, evidence, deadlines or approval authority. If decision
material is missing, identify the gap and ask for it before presenting the
outline as ready for approval. This check covers outline content; it does not
claim that rendered slides have been visually inspected.

**IMPORTANT:** Present the outline to the user for approval using **AskUserQuestion**:

- "Looks good, render the deck" — Proceed to Step 4 with the selected renderer
- "Add more slides" — Expand specific sections
- "Change focus" — Restructure around different themes
- "Start over" — Return to Step 1

This is the **wireframe gate** — the user MUST approve the outline structure before PPTX generation.

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
- **Agenda slide**: 3-5 key topics for non-board decks > 7 slides; board decks use slide 2 for the executive summary
- **One idea per slide**: Keep slides focused
- **5-7 bullets max**: Per slide for readability
- **Summary slide**: Key takeaways at the end for non-board decks; board decks lead with the executive summary
- **Next steps / CTA**: Final slide with clear actions

### By Audience Type

**Executives / Board:**
- Match the brief's decision or informational purpose in Step 3. Apply the
  decision outline and its check only when a decision is requested.
- Lead with business impact and source-backed financial implications.
- Keep the main deck focused on the decision; put expected-question evidence
  in the approved appendix.

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
→ Step 3: Generate outline, get approval
→ Step 4: Render PPTX
```

### Research-Backed Deck
```
User: "Build a presentation about AI trends in healthcare"
→ Step 1: Clarify audience and scope
→ Step 2: Research using Task agents
→ Step 3: Generate outline from research, get approval
→ Step 4: Render PPTX
```

### Deep Research + Deck
```
User: "I need a comprehensive investor deck about the autonomous vehicles market"
→ Suggest: "/octo:discover autonomous vehicles market" first
→ Then: "/octo:deck" using the research synthesis
```

---

*Slide deck skill for claude-octopus.*
