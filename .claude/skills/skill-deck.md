---
name: skill-deck
aliases:
  - deck
  - slides
  - presentation
description: Generate slide decks from briefs with optional multi-AI research
trigger: |
  AUTOMATICALLY ACTIVATE when user requests:
  - "create a deck", "build slides", "make a presentation"
  - "generate a pitch deck", "create board presentation"
  - "slide deck for [topic]", "presentation about [topic]"
  - "investor deck", "strategy presentation", "project update slides"

  DO NOT activate for:
  - Converting existing markdown to PPTX (use /octo:docs instead)
  - General file conversions (use document-skills directly)
  - When document-skills plugin not installed
---

# Slide Deck Generator

Generate professional slide decks from briefs with optional research, outline approval, and PPTX export.

## Prerequisites

The `document-skills` plugin MUST be installed for PPTX rendering:

```bash
/plugin list | grep document-skills
```

If not installed, tell the user:
```text
The document-skills plugin is required for PPTX generation.
Install it with: /plugin install document-skills@anthropic-agent-skills
```

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

- "Looks good, generate PPTX" — Proceed to Step 4
- "Add more slides" — Expand specific sections
- "Change focus" — Restructure around different themes
- "Start over" — Return to Step 1

This is the **wireframe gate** — the user MUST approve the outline structure before PPTX generation.

### Step 4: Render PPTX

Once the outline is approved:

1. Use the `document-skills:pptx` skill to convert the approved markdown outline to PowerPoint
2. Each `##` heading becomes a slide
3. Bullet points under each heading become slide content
4. Save the PPTX file to the current working directory with a descriptive filename

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
```text
User: "Create a 10-slide deck about our Q1 results"
→ Step 1: Clarify audience (executives)
→ Step 2: Skip (user has the data)
→ Step 3: Generate outline, get approval
→ Step 4: Render PPTX
```

### Research-Backed Deck
```text
User: "Build a presentation about AI trends in healthcare"
→ Step 1: Clarify audience and scope
→ Step 2: Research using Task agents
→ Step 3: Generate outline from research, get approval
→ Step 4: Render PPTX
```

### Deep Research + Deck
```text
User: "I need a comprehensive investor deck about the autonomous vehicles market"
→ Suggest: "/octo:discover autonomous vehicles market" first
→ Then: "/octo:deck" using the research synthesis
```

---

*Slide deck skill for claude-octopus v8.12.0+*
