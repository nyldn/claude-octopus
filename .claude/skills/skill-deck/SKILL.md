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

Build a slide-by-slide outline in markdown format. Structure:

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
- **Agenda slide**: 3-5 key topics (for decks > 7 slides)
- **One idea per slide**: Keep slides focused
- **5-7 bullets max**: Per slide for readability
- **Summary slide**: Key takeaways at the end
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
