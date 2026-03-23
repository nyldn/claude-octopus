---
name: skill-doc-delivery
version: 1.0.0
description: "Convert markdown knowledge work outputs to DOCX, PPTX, XLSX, and PDF office documents using the document-skills plugin. Use when: user says 'export to Word', 'create PowerPoint', 'convert to DOCX', 'create presentation from this synthesis', or requests office format conversion of research, analysis, or workflow outputs from ~/.claude-octopus/results/."
---

# Document Delivery for Knowledge Workers

Convert knowledge work outputs from markdown to professional office documents (DOCX, PPTX, XLSX).

## Prerequisites

Verify the document-skills plugin is installed:

```bash
/plugin list | grep document-skills
```

If not installed:

```bash
/plugin install document-skills@anthropic-agent-skills
```

## Format Selection by Purpose

| Purpose | Format | Plugin Command |
|---------|--------|---------------|
| Stakeholder presentations, persona decks, strategy decks | PPTX | `/document-skills:pptx` |
| Detailed docs, business cases, literature reviews, specs | DOCX | `/document-skills:docx` |
| Final publications, archival versions | PDF | `/document-skills:pdf` |
| Data tables, frameworks, calculations | XLSX | `/document-skills:xlsx` |

### Workflow-Specific Recommendations

- **After empathize** → PPTX for persona decks, DOCX for detailed persona docs
- **After advise** → PPTX for strategy presentations, DOCX for business cases
- **After synthesize** → DOCX for literature reviews, PDF for final publications

## Conversion Process

### Step 1: Locate Source Markdown

```bash
ls -lht ~/.claude-octopus/results/ | head -10
```

### Step 2: Convert Using Document-Skills Plugin

**PPTX:** Each `##` heading becomes a slide, bullet points auto-format.
**DOCX:** Supports headings, lists, tables, and formatting.
**PDF:** Ideal for final deliverables and archival.

### Step 3: Apply Professional Styling

- Use heading styles and bullet hierarchies consistently
- Add table of contents for DOCX >5 pages
- One main idea per slide for PPTX (5-7 bullets max)
- Add metadata (title, author, date) to all formats

## Common Patterns

**Single document:** Locate most recent `.md` in results, recommend format based on workflow type, convert.

**Presentation from research:** Locate markdown, map `##` headings to slides, add title slide and summary.

**Batch conversion:** Convert same source to multiple formats (e.g., DOCX + PPTX).

## Edge Cases

- **No workflow output:** Suggest running `/octo:empathize`, `/octo:advise`, or `/octo:synthesize` first
- **Format not specified:** Ask user about audience and purpose to recommend format
- **Plugin missing:** Direct user to install with `/plugin install document-skills@anthropic-agent-skills`

## Integration

```
1. Run workflow: /octo:empathize (or advise/synthesize)
2. Review markdown in ~/.claude-octopus/results/
3. Request conversion: "Export to PowerPoint"
4. This skill activates → professional document delivered
```
