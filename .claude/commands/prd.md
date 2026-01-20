---
name: prd
description: Write an AI-optimized PRD using multi-AI orchestration and 100-point scoring framework
arguments:
  - name: feature
    description: The feature or system to write a PRD for
    required: true
---

/skill skill-prd

Write a PRD for: $ARGUMENTS.feature
