---
command: octo:meta-prompt
description: "Generate an optimized prompt for any task using meta-prompting techniques"
---

# /octo:meta-prompt

Generate well-structured, verifiable prompts using proven meta-prompting techniques.

**Usage:**
```
/octo:meta-prompt
/octo:meta-prompt [task description]
```

**What it does:**
- Applies Task Decomposition for complex tasks
- Uses Fresh Eyes Review (different experts for creation vs. validation)
- Builds in Iterative Verification steps
- Enforces No Guessing (explicit uncertainty disclaimers)
- Assigns Specialized Experts for subtasks

**See:** skill-meta-prompt for full documentation.

---

**Generated prompt includes:**
- Role definition
- Structured instructions with phases
- Expert assignments
- Verification checkpoints
- Output format specification

**Example:**
```
/octo:meta-prompt create a code review checklist

→ What is the main goal?
→ What's the expected output?
→ How important is accuracy?
→ [Generates structured prompt with techniques applied]
```
