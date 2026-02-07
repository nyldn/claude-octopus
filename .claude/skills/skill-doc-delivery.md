---
name: skill-doc-delivery
aliases:
  - docs
  - document-delivery
  - doc-delivery
description: Convert markdown to DOCX, PPTX, XLSX office documents
trigger: |
  AUTOMATICALLY ACTIVATE when user requests:
  - Export knowledge work to office formats (e.g., "export to Word", "create PowerPoint", "convert to DOCX")
  - Generate professional documents from research (e.g., "create presentation from this synthesis")
  - Deliver knowledge work as polished documents (e.g., "make this a business case document")

  Look for markdown files in ~/.claude-octopus/results/ from:
  - empathize workflow (UX research → personas/journey maps)
  - advise workflow (strategy → business cases/decks)
  - synthesize workflow (research → literature reviews)

  DO NOT activate for:
  - Code-related document requests
  - General file conversions (use document-skills directly)
  - When document-skills plugin not installed
---

# Document Delivery for Knowledge Workers

Convert knowledge work outputs from markdown to professional office documents (DOCX, PPTX, XLSX).

## Overview

This skill helps you transform knowledge work results into polished, deliverable documents:

- **After empathize** → Export personas to PPTX decks or requirements to DOCX specs
- **After advise** → Convert strategic analysis to PPTX presentations or DOCX business cases
- **After synthesize** → Generate literature reviews as DOCX academic format or PDF

## Prerequisites Check

Before converting documents, verify the document-skills plugin is installed:

```bash
/plugin list | grep document-skills
```

If not installed:

```bash
/plugin install document-skills@anthropic-agent-skills
```

## Format Recommendations by Workflow

### Empathize Workflow → UX Research Outputs

**Best for PPTX (PowerPoint):**
- Persona decks for stakeholder presentations
- Journey map visualizations
- Research synthesis highlights
- Executive summaries

**Best for DOCX (Word):**
- Detailed persona documentation
- Research requirements specifications
- Interview transcripts and analysis
- User story documentation

### Advise Workflow → Strategic Analysis

**Best for PPTX (PowerPoint):**
- Strategy presentations for leadership
- Market analysis decks
- Competitive intelligence briefs
- Business case pitch decks
- Board presentations

**Best for DOCX (Word):**
- Comprehensive business cases
- Strategic recommendations reports
- Market research documentation
- Financial analysis reports

### Synthesize Workflow → Research Synthesis

**Best for DOCX (Word):**
- Literature review papers
- Research synthesis reports
- Academic research documentation
- Annotated bibliographies
- Technical white papers

**Best for PDF:**
- Final publications
- Archival versions
- Shareable research reports

## Conversion Guidelines

### Step 1: Locate Source Markdown

Knowledge work outputs are stored in:
```bash
~/.claude-octopus/results/
```

List recent outputs:
```bash
ls -lht ~/.claude-octopus/results/ | head -10
```

### Step 2: Choose Format Based on Purpose

Ask yourself:
- **Presenting to stakeholders?** → PPTX (visual, concise)
- **Comprehensive documentation?** → DOCX (detailed, structured)
- **Final publication?** → PDF (archival, unchangeable)
- **Data/frameworks?** → XLSX (tables, calculations)

### Step 3: Use Document-Skills Plugin

The document-skills plugin provides these capabilities:

**For DOCX (Word):**
```
Use the /document-skills:docx skill to convert markdown to Word format.
Supports headings, lists, tables, and formatting.
```

**For PPTX (PowerPoint):**
```
Use the /document-skills:pptx skill to convert markdown to PowerPoint.
Each ## heading becomes a slide, bullet points auto-format.
```

**For PDF:**
```
Use the /document-skills:pdf skill to generate PDF documents.
Ideal for final deliverables and archival.
```

### Step 4: Apply Professional Styling

After conversion, consider:
- **Consistent formatting** - Use heading styles, bullet hierarchies
- **Visual hierarchy** - Important points first, details later
- **Brand alignment** - Add logos, colors, fonts if needed
- **Readability** - Break up long paragraphs, use white space

## Common Conversion Patterns

### Pattern 1: Single Workflow → Single Document

User ran one workflow, wants one document:

```
User: "Export my latest synthesis to a Word document"

1. Check ~/.claude-octopus/results/ for most recent .md file
2. Identify it's from synthesize workflow
3. Recommend DOCX for academic report format
4. Use document-skills:docx to convert
5. Save to appropriate location
```

### Pattern 2: Multiple Sections → Presentation

User wants to create a deck from research:

```
User: "Create a PowerPoint from this research"

1. Locate the research markdown
2. Identify key sections (## headings)
3. Use document-skills:pptx to convert
4. Each ## heading becomes a slide
5. Recommend adding title slide and summary
```

### Pattern 3: Batch Conversion

User wants multiple formats:

```
User: "Create both a Word doc and PowerPoint from this strategy"

1. Locate source markdown
2. Convert to DOCX using document-skills:docx
3. Convert to PPTX using document-skills:pptx
4. Provide both file paths
```

## Professional Styling Tips

### DOCX (Word) Best Practices

- Use built-in heading styles (Heading 1, Heading 2, etc.)
- Add table of contents for documents >5 pages
- Use bullet points and numbered lists appropriately
- Include page numbers and headers/footers
- Add executive summary at the beginning
- Use tables for structured data

### PPTX (PowerPoint) Best Practices

- One main idea per slide
- Use title slide with author/date
- 5-7 bullet points max per slide
- Use consistent fonts and colors
- Add slide numbers
- Include summary/next steps slide
- Use visuals where possible (charts, diagrams)

### PDF Best Practices

- Convert from DOCX after final review
- Ensure all fonts are embedded
- Optimize for screen or print
- Add metadata (title, author, keywords)
- Use bookmarks for navigation

## Example Workflows

### Example 1: UX Research Persona Deck

```markdown
Input: ~/.claude-octopus/results/empathize-session-2026-01-18.md

Output Goal: Stakeholder presentation

Steps:
1. Read the empathize markdown
2. Extract persona sections
3. Convert to PPTX using document-skills:pptx
4. Each persona becomes a slide
5. Add title slide and key insights summary
6. Save as "UX-Personas-2026-01-18.pptx"
```

### Example 2: Strategic Business Case

```markdown
Input: ~/.claude-octopus/results/advise-market-analysis-2026-01-18.md

Output Goal: Comprehensive business case document

Steps:
1. Read the advise markdown
2. Structure as: Executive Summary, Analysis, Recommendations, Appendix
3. Convert to DOCX using document-skills:docx
4. Add table of contents
5. Format tables and charts properly
6. Save as "Market-Analysis-Business-Case-2026-01-18.docx"
```

### Example 3: Literature Review Paper

```markdown
Input: ~/.claude-octopus/results/synthesize-ai-safety-2026-01-18.md

Output Goal: Academic paper format

Steps:
1. Read the synthesize markdown
2. Structure as: Abstract, Introduction, Literature Review, Gaps, Conclusions
3. Convert to DOCX using document-skills:docx
4. Apply academic formatting (citations, references)
5. Export to PDF for final version
6. Save as "AI-Safety-Literature-Review-2026-01-18.pdf"
```

## Handling Edge Cases

### No Recent Workflow Output

If user requests export but no workflow was run:

```
Response: "I don't see any recent knowledge work outputs. Would you like to run:
- /octo:empathize (UX research)
- /octo:advise (strategic analysis)
- /octo:synthesize (literature review)

Then I can convert the results to your preferred format."
```

### Format Not Specified

If user doesn't specify format:

```
Response: "I can convert this to:
- DOCX (Word) - Best for detailed documentation
- PPTX (PowerPoint) - Best for presentations
- PDF - Best for final deliverables

Which format would you prefer based on your use case?"
```

### Multiple Markdown Files

If multiple outputs exist:

```
Response: "I found several knowledge work outputs:
1. empathize-personas-2026-01-15.md (3 days ago)
2. advise-market-analysis-2026-01-18.md (today)
3. synthesize-research-2026-01-10.md (8 days ago)

Which would you like to convert?"
```

### Document-Skills Not Installed

If plugin missing:

```
Response: "The document-skills plugin is required for conversion.
Install it with:

/plugin install document-skills@anthropic-agent-skills

Then I can convert your knowledge work to office formats."
```

## Integration with Knowledge Mode

This skill is designed to work seamlessly with the three knowledge mode workflows:

```
Knowledge Work Flow:
1. Run workflow: /octo:empathize (or advise/synthesize)
2. Review markdown output in ~/.claude-octopus/results/
3. Request conversion: "Export to PowerPoint"
4. This skill activates automatically
5. Professional document delivered
```

## Best Practices

1. **Review Before Converting** - Check markdown quality first
2. **Choose Right Format** - Match format to audience and purpose
3. **Add Context** - Include dates, authors, version numbers
4. **Test Compatibility** - Ensure recipients can open the format
5. **Archive Sources** - Keep original markdown files
6. **Version Control** - Use descriptive filenames with dates

## Quick Reference Commands

```bash
# List recent knowledge work outputs
ls -lht ~/.claude-octopus/results/ | head -5

# Check document-skills installed
/plugin list | grep document-skills

# Install document-skills
/plugin install document-skills@anthropic-agent-skills

# View specific markdown
cat ~/.claude-octopus/results/[filename].md
```

## Getting Help

For questions about:
- **Document conversion** → Ask about specific format needs
- **Knowledge workflows** → See /octo:knowledge-mode
- **Document-skills capabilities** → See /document-skills:* skills
- **Styling and formatting** → Ask for best practices by format

---

*Document delivery skill for claude-octopus v7.3.0+*
