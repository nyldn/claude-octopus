# Natural Language Workflow Keyword Research

## Overview

This documentation package provides a comprehensive framework for extracting and analyzing keywords from Claude Code conversation transcripts to identify natural language triggers for `@claude-octopus` workflow personas.

The goal is to enable users to invoke specialized AI workflows through natural language phrases (e.g., "review this code for security issues" → `code-reviewer` persona) without explicitly using slash commands or agent names.

## Quick Start

### Prerequisites
- Node.js 18+ and Python 3.9+
- Access to `/Users/chris/.claude/transcripts/` directory
- NLP libraries: `nltk`, `spacy`, `scikit-learn`

### Execution Sequence

1. **Review Data Sources** - Read `01-data-sources.md` to understand transcript structure
2. **Parse Transcripts** - Run `scripts/parse-transcripts.js` to extract conversations
3. **Extract Keywords** - Run `scripts/extract-keywords.py` for NLP analysis
4. **Categorize Workflows** - Apply mappings from `04-workflow-categorization.md`
5. **Validate Conflicts** - Use `05-conflict-avoidance-strategy.md` to check for claude-code conflicts
6. **Generate Report** - Run `scripts/generate-report.js` to create final documentation

## Documentation Structure

### Core Documentation

| File | Purpose |
|------|---------|
| `01-data-sources.md` | Transcript location, format, schema, and statistics |
| `02-extraction-methodology.md` | JSONL parsing and conversation reconstruction |
| `03-keyword-analysis-framework.md` | NLP techniques for keyword extraction |
| `04-workflow-categorization.md` | Mapping keywords to octopus personas |
| `05-conflict-avoidance-strategy.md` | Preventing interference with claude-code |
| `06-implementation-guide.md` | Step-by-step execution instructions |

### Implementation Tools

| File | Purpose |
|------|---------|
| `scripts/parse-transcripts.js` | Node.js JSONL parser for conversation extraction |
| `scripts/extract-keywords.py` | Python NLP keyword extraction pipeline |
| `scripts/generate-report.js` | Automated research report generation |
| `templates/research-report-template.md` | Final deliverable structure |

## Key Objectives

### 1. Identify Trigger Phrases
Extract 2-5 word phrases that indicate user intent to invoke specialized workflows:
- "review this code" → `code-reviewer`
- "optimize performance" → `performance-engineer`
- "analyze market trends" → `strategy-analyst`

### 2. Map to Personas
Create comprehensive mappings between natural language patterns and 20+ `@claude-octopus` personas covering:
- Architecture & Design
- Code Quality & Security
- Performance & Scalability
- Documentation & Research
- Testing & Deployment
- Business & Strategy

### 3. Avoid Conflicts
Ensure trigger phrases don't interfere with standard claude-code operations like:
- Basic file operations (read, write, edit)
- Simple navigation (find, search, show)
- Version control (commit, push, pull)

### 4. Enable Confidence Scoring
Develop rubrics to score trigger phrase confidence (high/medium/low) based on:
- Phrase specificity and length
- Contextual signals in surrounding conversation
- Presence of domain-specific terminology

## Data Sources

- **Primary:** 282 JSONL transcript files from `/Users/chris/.claude/transcripts/`
- **Size:** 154 MB total
- **Date Range:** January 2026
- **Format:** JSON Lines with `user`, `assistant`, `tool_use`, `tool_result` message types

## Expected Outputs

1. **Keyword Catalog** - Comprehensive list of trigger phrases organized by persona
2. **Confidence Scores** - Quantitative assessment of each trigger phrase
3. **Conversation Examples** - Anonymized samples showing triggers in context
4. **Implementation Guide** - Actionable recommendations for integrating into claude-octopus
5. **Conflict Report** - Analysis of potential conflicts with claude-code operations

## Success Metrics

- ✅ 100+ unique trigger phrases identified
- ✅ Coverage for all 20+ octopus personas
- ✅ <5% false positive rate for claude-code conflicts
- ✅ High confidence (80%+) triggers for top 10 most-used personas
- ✅ Executable implementation plan with code examples

## Getting Help

For questions about:
- **Data Format:** See `01-data-sources.md`
- **Parsing Issues:** See `02-extraction-methodology.md`
- **NLP Techniques:** See `03-keyword-analysis-framework.md`
- **Persona Mappings:** See `04-workflow-categorization.md`
- **Execution:** See `06-implementation-guide.md`

## Next Steps

1. Read through documentation files in numerical order (01-06)
2. Set up development environment with required dependencies
3. Run sample parsing on 5-10 transcript files to validate approach
4. Execute full keyword extraction pipeline on complete dataset
5. Generate and review final research report
6. Integrate findings into claude-octopus workflow system

---

**Last Updated:** January 2026
**Status:** Documentation Complete, Ready for Execution
**Maintainer:** Chris (claude-octopus project)
