---
name: prd-score
description: Score an existing PRD against the 100-point AI-optimization framework
arguments:
  - name: file
    description: Path to the PRD file to score (relative or absolute)
    required: true
---

/skill skill-prd-score

Score this PRD: $ARGUMENTS.file
