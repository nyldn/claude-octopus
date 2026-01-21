---
command: docs
description: Document delivery with export to PPTX, DOCX, PDF formats
---

# Docs - Document Delivery Skill

## 🤖 INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:docs <arguments>`):

**✓ CORRECT - Use the Skill tool:**
```
Skill(skill: "octo:docs", args: "<user's arguments>")
```

**✗ INCORRECT - Do NOT use Task tool:**
```
Task(subagent_type: "octo:docs", ...)  ❌ Wrong! This is a skill, not an agent type
```

**Why:** This command loads the `skill-doc-delivery` skill. Skills use the `Skill` tool, not `Task`.

---

**Auto-loads the `skill-doc-delivery` skill for document creation and export.**

## Quick Usage

Just use natural language:
```
"Create a technical document for the API architecture"
"Generate presentation slides for the project review"
"Export the research findings to PDF"
```

## Supported Formats

- **PPTX**: PowerPoint presentations
- **DOCX**: Word documents
- **PDF**: Portable documents
- **Markdown**: Documentation files

## Document Types

- Technical specifications
- Architecture diagrams
- Project presentations
- Research reports
- Design proposals
- User guides

## Natural Language Examples

```
"Create a presentation about our microservices architecture"
"Generate a technical specification document for the API"
"Export the debate results to a PDF report"
```
