---
command: blind-debate
description: "Blind Debate - Independent ideation then multi-round convergence. All AIs work independently on the same prompt, then debate."
skill: skill-blind-debate
---

# Blind Debate

Blind Ideation → Reveal → Multi-round Convergence debate. All AI agents receive the same prompt independently, then debate each other's responses over multiple rounds.

## Instructions for Claude

### MANDATORY COMPLIANCE — DO NOT SKIP

**When the user explicitly invokes `/octo:blind-debate`, you MUST execute the blind debate workflow below.** You are PROHIBITED from answering the question directly, skipping the multi-provider blind debate, or deciding the topic is "too simple." The user chose this command deliberately — respect that choice.

---

### Execution

1. Follow the `skill-blind-debate` instructions (Steps 1-6) exactly.
2. Start with Step 1: check provider availability and display the visual indicator banner.
3. Step 2: parse arguments and create debate folder.
4. Step 3 (CRITICAL): BLIND PHASE — send identical prompt to all agents in parallel. Claude writes response BEFORE reading advisor outputs.
5. Step 4: CONVERGENCE ROUNDS — all agents see all responses, critique, and revise. Use escalating prompts.
6. Step 5: write final synthesis with diversity analysis, convergence journey, and remaining disagreements.
7. Step 6 (if --synthesize): generate deliverable.

### Post-Completion — Interactive Next Steps

**After the blind debate completes, ask the user what to do next:**

```javascript
AskUserQuestion({
  questions: [
    {
      question: "The blind debate is complete. What would you like to do next?",
      header: "Next Steps",
      multiSelect: false,
      options: [
        {label: "Run more convergence rounds", description: "Continue debating with additional rounds"},
        {label: "Act on the synthesis", description: "Proceed with the recommended approach"},
        {label: "Blind-debate a related topic", description: "Start a new blind debate on a follow-up question"},
        {label: "Export results", description: "Save the debate as a document (PPTX/DOCX/PDF)"},
        {label: "Done for now", description: "I have what I need"}
      ]
    }
  ]
})
```
