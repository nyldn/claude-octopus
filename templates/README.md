# Claude Octopus Executive Templates

Professional PowerPoint templates for executive-level readouts and reports.

## Overview

This directory contains templates designed for C-suite communication following best practices:
- **Pyramid Principle**: Lead with conclusions, support with evidence
- **BLUF (Bottom Line Up Front)**: Start with the key message
- **Data-driven**: Quantify impact wherever possible
- **Executive-appropriate**: Clean, professional design

## Prerequisites

**Required:** Install the document-skills plugin to use these templates:

```bash
/plugin install document-skills@anthropic-agent-skills
```

## Available Templates

### 1. Executive Summary (`executive-summary.json`)
**Use for:** Quick updates, decision briefs, stakeholder summaries

**Structure:** (5 slides)
1. Title with key message
2. Problem/Opportunity
3. Analysis summary
4. Recommendation
5. Next steps

**Best for:** When you have 5 minutes with a busy executive

---

### 2. Board Presentation (`board-presentation.json`)
**Use for:** Board meetings, quarterly reviews, governance reporting

**Structure:** (10 slides)
1. Title
2. Agenda
3. Executive summary
4. Performance metrics
5. Strategic updates
6. Risk & mitigation
7. Financial overview
8. Board decisions needed
9. Next steps
10. Appendix

**Best for:** Formal board meetings and strategic reviews

---

### 3. Business Case (`business-case.json`)
**Use for:** Investment proposals, strategic initiatives, major decisions

**Structure:** (9 slides)
1. Title
2. Executive summary
3. Market opportunity
4. Proposed solution
5. Financial model
6. Implementation plan
7. Risk assessment
8. Recommendation
9. Next steps

**Best for:** Seeking approval for significant investments or initiatives

---

### 4. Status Update (`status-update.json`)
**Use for:** Regular progress reports, project updates, team communications

**Structure:** (6 slides)
1. Title
2. Progress highlights
3. Key metrics
4. Blockers & risks
5. Next milestones
6. Ask/Support needed

**Best for:** Weekly or monthly stakeholder updates

---

### 5. Workshop Readout (`workshop-readout.json`)
**Use for:** Workshop synthesis, session summaries, alignment documentation

**Structure:** (7 slides)
1. Title
2. Workshop overview
3. Key themes
4. Decisions made
5. Action items
6. Open questions
7. Next steps

**Best for:** Communicating workshop outcomes to leadership

## How to Use Templates

### Method 1: With Knowledge Mode Workflows

1. Run a knowledge mode workflow:
   ```bash
   /co:km on
   "Run strategic analysis on market entry opportunities"
   ```

2. Request template-based export:
   ```bash
   "Export this to a business case presentation"
   ```

3. Claude will:
   - Select appropriate template (business-case.json)
   - Apply executive theme
   - Generate PPTX using document-skills plugin

### Method 2: With Markdown Files

If you have existing markdown content:

1. Identify your content type:
   - Strategic analysis → business-case template
   - UX research → workshop-readout or executive-summary
   - Status report → status-update template

2. Request conversion:
   ```bash
   "Convert this markdown to a board presentation using the board-presentation template"
   ```

### Method 3: From Scratch

1. Specify template and content:
   ```bash
   "Create an executive summary about our Q4 performance using the executive-summary template"
   ```

2. Claude will use the exec-communicator persona to structure content appropriately

## Theme System

### Executive Theme (`themes/executive-theme.json`)

Professional design system for C-suite presentations:

**Colors:**
- Primary: Navy Blue (#1F4788) - Trust, stability
- Secondary: Slate Blue (#5B7A9F) - Professionalism
- Accent: Coral Red (#E8505B) - Emphasis, alerts
- Success: Green (#27AE60) - Positive indicators
- Warning: Orange (#F39C12) - Caution

**Typography:**
- Font: Calibri (fallback: Arial, Helvetica)
- Title: 44pt bold
- Slide titles: 32pt bold
- Body: 18pt regular
- Bullets: 16pt regular

**Layout:**
- Margins: 0.75" on all sides
- Max bullets per slide: 7 (ideally 5)
- Generous white space

## Best Practices

### Executive Communication Principles

1. **Pyramid Principle**
   - Lead with the answer
   - Support with grouped arguments
   - Organize by importance

2. **One Main Idea Per Slide**
   - Each slide should have a clear headline
   - Headline should carry the message
   - Body supports the headline

3. **Quantify Impact**
   - Use numbers wherever possible
   - Show trends with charts
   - Compare to targets/benchmarks

4. **Clear Call to Action**
   - Make asks explicit
   - Specify who does what by when
   - Include decision deadlines

5. **Prepare for Q&A**
   - Include appendix slides
   - Anticipate questions
   - Have supporting data ready

### Slide Design Tips

**Do:**
- Use 5-7 bullet points maximum
- Include slide numbers
- Add clear headlines
- Use charts over tables
- Leave white space
- Be consistent with fonts/colors

**Don't:**
- Cram slides with text
- Use fancy transitions
- Include decorative graphics
- Mix too many fonts
- Use bright neon colors
- Forget to proofread

## Integration with Claude Octopus

### Workflow Integration

```
Knowledge Mode Workflow → doc-delivery skill → Template Selection → PPTX Generation
         |                      |                     |                    |
    advise/empathize/     skill-doc-delivery    template matching    document-skills
     synthesize              .md file              .json file          /pptx skill
```

### Auto-Suggestion

When you complete a knowledge mode workflow, Claude will automatically suggest:
- **After advise workflow** → business-case or board-presentation
- **After empathize workflow** → workshop-readout or executive-summary
- **After synthesize workflow** → executive-summary with research findings

### Persona Integration

The `exec-communicator` persona automatically:
- Structures content using pyramid principle
- Applies BLUF formatting
- Selects appropriate templates
- Ensures executive-appropriate tone

## Customization

### Creating Custom Templates

1. Copy an existing .json template
2. Modify slide structure
3. Update content_structure arrays
4. Add to templates/pptx/
5. Reference in doc-delivery skill

### Creating Custom Themes

1. Copy executive-theme.json
2. Modify colors/fonts/typography
3. Save to templates/themes/
4. Reference in template .json files

## Troubleshooting

### document-skills Plugin Not Installed

**Error:** "document-skills plugin required"

**Solution:**
```bash
/plugin install document-skills@anthropic-agent-skills
```

### Template Not Found

**Error:** "Template [name] not found"

**Solution:** Verify template exists in `templates/pptx/` and is referenced correctly.

### Formatting Issues

**Issue:** Slides don't match template

**Solution:** Ensure theme is correctly referenced in template .json file.

## Examples

### Example 1: Board Update

```bash
User: "Create a board presentation about our Q4 performance"

Claude:
1. Uses board-presentation.json template
2. Structures content with agenda, exec summary, metrics, strategy, financials
3. Applies executive theme (navy blue, Calibri, professional)
4. Generates PPTX with 10 slides
5. Saves to ~/.claude-octopus/exports/pptx/
```

### Example 2: Quick Executive Brief

```bash
User: "I need a 5-slide deck summarizing our AI strategy"

Claude:
1. Uses executive-summary.json template
2. Applies pyramid principle
3. Leads with strategy recommendation
4. Supports with 3-5 bullet points per slide
5. Ends with clear next steps
```

### Example 3: Workshop Synthesis

```bash
User: "Synthesize yesterday's strategy workshop for leadership"

Claude:
1. Uses workshop-readout.json template
2. Extracts key themes from notes
3. Documents decisions and action items
4. Lists open questions
5. Includes participant quotes
```

## File Locations

```
templates/
├── README.md (this file)
├── pptx/
│   ├── executive-summary.json
│   ├── board-presentation.json
│   ├── business-case.json
│   ├── status-update.json
│   └── workshop-readout.json
└── themes/
    └── executive-theme.json

~/.claude-octopus/
└── exports/
    └── pptx/ (generated presentations saved here)
```

## Getting Help

For questions about:
- **Template usage** → Ask Claude: "How do I use the business-case template?"
- **Customization** → Ask Claude: "How can I customize the executive theme?"
- **Integration** → Ask Claude: "How does doc-delivery integrate with templates?"
- **Best practices** → Ask Claude: "What are best practices for executive presentations?"

## Version History

- **1.0.0** (2026-01-19) - Initial template library with 5 executive templates

---

*Executive Templates for claude-octopus v7.7.0+*
