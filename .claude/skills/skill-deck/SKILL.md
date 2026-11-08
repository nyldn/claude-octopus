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
4. Build the **sentence skeleton** with one declarative sentence per storyline slide,
   in order. Exclude the cover slide from this skeleton; keep its presentation
   name, subtitle, date and presenter as metadata. The cover still counts toward
   the approved slide-count target. Each storyline title must make a claim that
   advances the answer. Under each claim, record its supporting evidence and
   intended visual. Keep unverified claims marked as assumptions; do not turn
   them into asserted facts.

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

## Slide 1: [Presentation name]
- Cover: [subtitle, date and presenter]
- Visual: [cover layout]

## Slide 2: [The recommendation meets the agreed decision threshold]
- Supporting pillars and the specific ask
- Evidence: [source showing how the recommendation meets the threshold]
- Visual: [comparison of the recommendation with the agreed threshold]

## Slide 3: [A specific proof point supports the first pillar]
- Evidence: [source for the proof point and its link to the pillar]
- Visual: [chart or diagram showing the proof point]

## Slide N: [The requested action unlocks a specific outcome]
- Ask, owner and next step
- Evidence: [source linking the action to the expected outcome]
- Visual: [action, owner and next-step timeline]
```

For Executives / Board, apply the same confirmed question, hypothesis and
sentence skeleton to the purpose-specific outline below. For executive and
board decision briefs, the board content check and the titles-only read must
both pass before outline approval.
For an informational brief such as a Q1 results update, do not require a decision or approval ask.
Put an executive summary on slide 2 covering key findings and implications,
including results when applicable, followed by supporting evidence and
follow-up. Do not invent a decision.

#### Executive and board outline

For executive and board decision briefs, put the decision on slide 2. Use
these content requirements within the sentence skeleton, with supported
declarative titles in place of bracketed placeholders. Keep the question,
opener and hypothesis above the slides in the approved outline. Expand evidence slides as needed;
agree the main-deck and appendix slide counts within the user's target.
If the user selects a five-slide target, combine the evidence and decision
slides, keeping the executive summary on slide 2 and an appendix. Preserve
the selected slide range for longer targets. If the required material,
including one backup slide per expected question, cannot fit, ask the user to
approve a larger target before expanding it. The six-slide example is not a
minimum slide count.

```markdown
## Slide 1: [Decision topic]
- Presentation title, date and presenter

## Slide 2: Executive summary: [The recommendation meets the decision threshold]
- One recommendation sentence with a by-when
- One line of context
- Two or three supporting pillars
- The specific ask and what approval unlocks
- Evidence: [sources supporting the recommendation and pillars]
- Visual: [recommendation, pillars and ask]

## Slide 3: [The recommended option delivers more value than doing nothing]
- Recommended option: benefit, cost and trade-offs
- Do nothing: cost and consequences over the same time horizon
- At least one real alternative: benefit, cost and trade-offs
- Evidence: [sources for the common-horizon costs and consequences]
- Visual: [comparison of the options]

## Slide 4: [The evidence supports a specific conclusion]
- One proof point for this data slide, with its source
- Chart highlight: the single figure that supports the title
- Evidence: [source for the proof point]
- Visual: [chart with the claimed figure highlighted]

## Slide 5: [The requested approval unlocks the outcome by the decision date]
- Repeat the same recommendation and by-when
- Explicit ask: the approval, amount or named resource the audience can grant
- What approval unlocks and who owns the next action
- Evidence: [basis for the requested amount, resource and deadline]
- Visual: [action, owner and next-step timeline]

## Slide 6: Appendix: [The backup evidence answers an expected question]
- Expected question: [the question this backup answers]
- Backup evidence answering this expected question
- Evidence: [source answering the expected question]
- Visual: [backup chart or diagram]
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

#### Storyline gate: titles-only read

Read only the slide-title sentences, top to bottom. Exclude the cover slide
from this titles-only read. The storyline titles must carry the
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
this gate. Preserve the approved cover title and pass the approved sentences
to the renderer as the storyline slide titles.

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
- **Summary slide**: State the supported answer to the governing question; Executives / Board briefs put the executive summary on slide 2 as required in Step 3
- **Next steps / CTA**: Clear actions on the last main-deck slide, before any appendix slides

### By Audience Type

**Executives / Board:**
- Match the brief's decision or informational purpose in Step 3. Apply the
  decision outline and its check only when a decision is requested.
- Lead with business impact and source-backed financial implications.
- Keep the main deck focused on the brief's purpose; put expected-question evidence
  in the approved appendix.
- For decision briefs, end with the specific decision needed. For informational
  briefs, end with the supported conclusion and follow-up from Step 3.

**Engineers / Technical:**
- Include architecture diagrams (describe for slides)
- Show trade-offs and alternatives considered
- Include implementation timelines
- Reference technical specifications

**Investors / Fundraising:**
- For decision briefs, follow the confirmed question, approved pillars and out-of-scope list.
- Treat this fundraising example as optional: Problem → Solution → Market → Traction → Team → Ask.
  Choose or omit topics to support the confirmed question. In a fundraising
  decision brief, include a funding ask and use of funds when they answer that question.
- Include market size (TAM/SAM/SOM), growth metrics and projections when they
  support the confirmed question.
- For informational briefs, end with the supported conclusion and follow-up.
  Do not add a funding ask to an informational update.

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

---

*Slide deck skill for claude-octopus.*
