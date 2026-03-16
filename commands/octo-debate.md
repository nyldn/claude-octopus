---
description: "AI Debate Hub - Structured four-way debates between Claude, Sonnet, Gemini, and Codex"
---

# Debate

Structured four-way AI debates between Claude, Sonnet, Gemini, and Codex.

## 🤖 INSTRUCTIONS FOR CLAUDE

### MANDATORY COMPLIANCE — DO NOT SKIP

**When the user explicitly invokes `/octo:debate`, you MUST execute the structured debate workflow below.** You are PROHIBITED from answering the question directly, skipping the multi-provider debate, or deciding the topic is "too simple" for a four-way debate. The user chose this command deliberately — respect that choice.

---

### Execution

1. Follow the `skill-debate` instructions (Steps 1-7) exactly.
2. Start with Step 1: check provider availability and display the visual indicator banner.
3. Step 2: ask clarifying questions via AskUserQuestion before proceeding.
4. Steps 3-5: parse arguments, set up debate folder, conduct rounds with all three participants.
5. Steps 6-7: write final synthesis and present results to the user.
6. Apply quality gates and cost tracking from `skill-debate-integration` throughout.

### Post-Completion — Interactive Next Steps

**CRITICAL: After the debate completes, you MUST ask the user what to do next. Do NOT end the session silently.**

```javascript
AskUserQuestion({
  questions: [
    {
      question: "The debate is complete. What would you like to do next?",
      header: "Next Steps",
      multiSelect: false,
      options: [
        {label: "Run another round", description: "Continue the debate with additional rounds"},
        {label: "Act on the winner", description: "Proceed with the winning argument's recommendation"},
        {label: "Debate a related topic", description: "Start a new debate on a follow-up question"},
        {label: "Export the synthesis", description: "Save the debate results as a document"},
        {label: "Done for now", description: "I have what I need"}
      ]
    }
  ]
})
```
