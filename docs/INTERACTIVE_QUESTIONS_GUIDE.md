# Interactive Questions Guide for Command Development

This guide provides best practices for creating interactive AskUserQuestion flows in Claude Octopus commands.

---

## Why Interactive Questions?

**Problem**: Commands with complex configuration options (scopes, flags, JSON) create friction:
- Users must know all options upfront
- Manual JSON/config is error-prone
- No guidance on which options to choose
- Steep learning curve for new users

**Solution**: Guide users through decisions with visual, interactive questions:
- Present choices with descriptions
- Let users see options before deciding
- Validate selections automatically
- Lower barrier to entry

---

## When to Add Interactive Questions

Add AskUserQuestion flows when a command:

1. **Has custom scopes or filters** (extract feature scopes, security audit boundaries)
2. **Requires complex configuration** (debate rounds, research depth, test coverage goals)
3. **Has multiple modes** (quick/standard/deep, all features/specific feature)
4. **Costs money** (external API usage, multi-provider execution)
5. **Impacts scope significantly** (full codebase vs single feature)

**Don't add when:**
- Command has single, clear purpose (simple toggles, direct execution)
- Configuration is obvious from context
- Adding questions would slow down expert users unnecessarily

---

## Pattern: Two-Step Execution

All commands with interactive questions should follow this pattern:

```markdown
## 🤖 INSTRUCTIONS FOR CLAUDE

When the user invokes this command (e.g., `/octo:command <arguments>`):

### Step 1: Ask Clarifying Questions

**CRITICAL: Use AskUserQuestion to gather context before execution:**

```javascript
AskUserQuestion({
  questions: [
    {
      question: "Clear, specific question about intent?",
      header: "Short Label",  // Max 12 chars
      multiSelect: false,     // or true for multiple selections
      options: [
        {label: "Option 1", description: "What this choice means"},
        {label: "Option 2 (Recommended)", description: "Why this is recommended"},
        {label: "Option 3", description: "When to choose this"}
      ]
    },
    // 1-4 questions max (don't overwhelm)
  ]
})
```

**After receiving answers, incorporate them into execution context.**

### Step 2: Execute Command

Use the answers to customize execution:
- Pass context to skills/agents
- Adjust parameters based on selections
- Generate appropriate outputs
```

---

## Best Practices

### 1. Question Design

**Good Questions:**
- **Clear intent**: "How deep should the research go?"
- **Actionable**: Each option leads to different execution
- **Scoped**: 2-4 options (not overwhelming)
- **Mutually exclusive**: Options don't overlap (unless multiSelect)

**Bad Questions:**
- Too vague: "What do you want?"
- Too many options: 10+ choices
- Overlapping: Options aren't clearly distinct
- No impact: Answer doesn't change execution

### 2. Option Labels

**Format:**
- **Label**: Short (1-5 words), descriptive
- **Description**: Explains what happens, why to choose
- **(Recommended)**: Mark default/recommended choices

**Examples:**

✅ **Good:**
```javascript
{label: "Quick overview", description: "High-level summary (< 1 min)"}
{label: "Deep dive (Recommended)", description: "Comprehensive analysis (5-10 min)"}
{label: "Just exploring", description: "Curious about capabilities, no urgency"}
```

❌ **Bad:**
```javascript
{label: "Option A", description: "A"}  // Not descriptive
{label: "Super deep comprehensive exhaustive analysis", description: "Deep"} // Too long
{label: "Fast", description: ""}  // No description
```

### 3. Header Labels

- **Max 12 characters** (displayed as chip/tag)
- **Noun or short phrase**: "Depth", "Scope", "Cost", "Focus"
- **Consistent**: Use same terminology across commands

**Examples:**
- ✅ "Depth", "Scope", "Cost", "Mode", "Focus", "Priority"
- ❌ "How deep do you want this to be?", "Configuration"

### 4. Question Count

- **1-2 questions**: Simple commands (multi.md - intent + cost)
- **3 questions**: Standard commands (discover.md - depth + focus + output)
- **4-5 questions**: Complex commands (plan.md - comprehensive intake)
- **Never >5**: Break into phases or reconsider necessity

### 5. Multi-Select Usage

Use `multiSelect: true` when:
- Choices aren't mutually exclusive
- User might want combination (focus areas, refinement options)
- "All of the above" makes sense

**Example:**
```javascript
{
  question: "Which aspects should we focus on?",
  header: "Focus",
  multiSelect: true,  // User can select multiple
  options: [
    {label: "Security", description: "Vulnerability analysis"},
    {label: "Performance", description: "Speed and efficiency"},
    {label: "Architecture", description: "Design patterns"}
  ]
}
```

### 6. Recommended Options

Mark recommended options to guide users:

```javascript
{label: "Standard depth (Recommended)", description: "Balanced analysis for most use cases"}
```

This helps new users while allowing experts to choose alternatives.

---

## Real-World Examples

### Example 1: Feature Extraction (extract.md)

**Context**: Large codebases need feature-based scoping

```javascript
AskUserQuestion({
  questions: [
    {
      question: "This codebase is large. Which features do you want to extract?",
      header: "Feature Scope",
      multiSelect: false,
      options: [
        {label: "All features (Recommended)", description: "Extract all 8 features separately"},
        {label: "Specific feature only", description: "Choose one feature (faster, focused)"},
        {label: "Full codebase", description: "Extract everything as one (slower)"}
      ]
    }
  ]
})
```

**Why it works:**
- Presents auto-detected features with counts
- Clear trade-offs (all vs specific vs full)
- Guides users toward recommended approach

---

### Example 2: Cost Awareness (multi.md)

**Context**: Multi-provider execution costs money

```javascript
AskUserQuestion({
  questions: [
    {
      question: "Why do you need multiple AI perspectives?",
      header: "Intent",
      multiSelect: false,
      options: [
        {label: "High-stakes decision", description: "Critical choice requiring comprehensive analysis"},
        {label: "Just exploring", description: "Curious about multi-AI capabilities"}
      ]
    },
    {
      question: "Are you aware this uses external API credits?",
      header: "Cost",
      multiSelect: false,
      options: [
        {label: "Yes, proceed (~$0.02-0.08/query)", description: "I understand the cost"},
        {label: "Tell me more about costs", description: "Explain charges first"},
        {label: "Use free providers only", description: "Skip paid APIs"}
      ]
    }
  ]
})
```

**Why it works:**
- Confirms user intent (prevents accidental expensive operations)
- Provides informed consent before charging
- Offers escape hatch ("tell me more", "free only")

---

### Example 3: Research Depth (discover.md)

**Context**: Research can range from quick to exhaustive

```javascript
AskUserQuestion({
  questions: [
    {
      question: "How deep should the research go?",
      header: "Depth",
      multiSelect: false,
      options: [
        {label: "Quick overview", description: "High-level summary (< 1 min)"},
        {label: "Moderate depth (Recommended)", description: "Balanced exploration (2-3 min)"},
        {label: "Comprehensive", description: "Detailed analysis (5-7 min)"},
        {label: "Deep dive", description: "Exhaustive research (10+ min)"}
      ]
    },
    {
      question: "What's your primary focus area?",
      header: "Focus",
      multiSelect: false,
      options: [
        {label: "Technical implementation", description: "Code patterns, APIs, frameworks"},
        {label: "Best practices", description: "Industry standards, conventions"},
        {label: "Ecosystem & tools", description: "Libraries, community insights"},
        {label: "Trade-offs", description: "Pros/cons of approaches"}
      ]
    }
  ]
})
```

**Why it works:**
- Right-sizes effort (prevents over/under-analysis)
- Focuses research direction
- Sets time expectations upfront

---

## Implementation Checklist

When adding interactive questions to a command:

- [ ] **Identify decision points**: What configuration currently requires manual input?
- [ ] **Design 1-4 questions**: Keep it focused
- [ ] **Write clear labels**: Short, descriptive, actionable
- [ ] **Add descriptions**: Explain each option
- [ ] **Mark recommended**: Guide new users
- [ ] **Place in Step 1**: Before any execution
- [ ] **Use answers in Step 2**: Pass context to execution
- [ ] **Test question flow**: Ensure all branches work
- [ ] **Document fallbacks**: What if user skips? What are defaults?
- [ ] **Add to command docs**: Show example flow in user documentation

---

## Common Mistakes to Avoid

### ❌ Asking for information Claude can detect

**Bad:**
```javascript
{question: "Is this a large codebase?", ...}
```

**Good:**
```javascript
// Auto-detect size, only ask if ambiguous
const fileCount = await getFileCount(target);
if (fileCount > 500) {
  // Trigger feature detection automatically
}
```

### ❌ Too many questions

**Bad:** 7 questions before execution (user fatigue)

**Good:** 3 focused questions, optional refinement later

### ❌ Questions that don't change execution

**Bad:**
```javascript
{question: "Do you like multi-AI mode?", ...}
```
This doesn't impact execution, so don't ask.

### ❌ Jargon without explanation

**Bad:**
```javascript
{label: "AST-based semantic analysis", description: "Uses AST"}
```

**Good:**
```javascript
{label: "Deep code analysis", description: "Analyzes code structure, not just syntax"}
```

---

## Testing Interactive Flows

**Manual testing:**
1. Invoke command with different answer combinations
2. Verify execution changes based on answers
3. Check that all option paths work
4. Ensure recommended options are actually good defaults

**User testing:**
1. Watch a new user go through flow
2. Note confusion points
3. Refine question wording
4. Simplify if users consistently pick same option

---

## Migration Strategy

**For existing commands with manual config:**

1. **Phase 1**: Add interactive questions, keep manual config as fallback
2. **Phase 2**: Deprecate manual approach, encourage interactive
3. **Phase 3**: Remove manual approach (or move to "expert mode")

**Example migration:**
```markdown
## Usage

**Interactive (Recommended):**
```bash
/octo:command <target>  # Guided flow with questions
```

**Direct (Advanced):**
```bash
/octo:command <target> --scope <json>  # Manual configuration
```

Note: Most users should use the interactive flow. Direct mode is for automation/CI.
```

---

## Summary

**Key Principles:**
1. **Guide, don't quiz**: Questions should help users make decisions, not test knowledge
2. **Clear choices**: 2-4 mutually exclusive options with descriptions
3. **Actionable**: Each answer changes execution meaningfully
4. **Respectful of time**: 1-4 questions max, mark recommended options
5. **Graceful defaults**: If user skips, use sensible defaults

**Benefits:**
- Lower barrier to entry for new users
- Fewer errors from manual configuration
- Discoverable features (users see options they didn't know existed)
- Informed consent for costly operations
- Consistent UX across commands

---

## See Also

- `extract.md` - Comprehensive example with feature detection + scope refinement
- `multi.md` - Cost awareness example
- `discover.md` - Research depth + focus example
- `plan.md` - Complex 5-question intake flow
