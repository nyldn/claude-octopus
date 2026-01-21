# ASCII Diagram Standard

This document defines conventions for ASCII workflow diagrams in Claude Octopus skills.

## Why ASCII Diagrams?

1. **Universal rendering** - Works in any text environment
2. **LLM-friendly** - Models understand and follow visual flows
3. **Documentation** - Self-documenting workflow structure
4. **Consistency** - Recognizable patterns across skills

---

## Box Characters

### Standard Box (Primary Container)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              TITLE IN CAPS                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│  Content goes here                                                          │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Characters used:**
- `┌` `┐` `└` `┘` - Corners
- `─` - Horizontal line
- `│` - Vertical line
- `├` `┤` - T-junctions for separators

### Simple Box (Alternative)

```
+-----------------------------------------------------------------------+
|                              TITLE IN CAPS                             |
+-----------------------------------------------------------------------+
|  Content goes here                                                     |
+-----------------------------------------------------------------------+
```

**Use when:** Unicode box characters might not render correctly.

---

## Flow Arrows

### Vertical Flow (Primary)

```
│  Step 1: Do something                                                    │
│       ↓                                                                  │
│  Step 2: Do next thing                                                   │
│       ↓                                                                  │
│  Step 3: Final step                                                      │
```

### Horizontal Flow

```
Input → Process → Output
```

### Branching Flow

```
│       ↓                                                                  │
│  Step 2: Decision Point                                                  │
│       ├── Yes → Path A                                                   │
│       └── No  → Path B                                                   │
```

### Parallel Flow

```
│       ↓                                                                  │
│  Step 2: Parallel Execution                                              │
│       ├── Agent A: Task 1                                                │
│       ├── Agent B: Task 2                                                │
│       └── Agent C: Task 3                                                │
│       ↓ (wait for all)                                                   │
```

---

## Standard Workflow Template

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           WORKFLOW NAME                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Step 1: [Phase Name]                                                       │
│       → [Brief description of what happens]                                 │
│       ↓                                                                     │
│  Step 2: [Phase Name]                                                       │
│       → [Brief description]                                                 │
│       → [Additional detail if needed]                                       │
│       ↓                                                                     │
│  Step 3: [Phase Name]                                                       │
│       → [Brief description]                                                 │
│       ↓                                                                     │
│  Step 4: [Phase Name]                                                       │
│       → [Brief description]                                                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Phase Labels

Use consistent phase labeling:

### For Sequential Phases

```
Step 1: Input Collection
Step 2: Validation
Step 3: Processing
Step 4: Output Generation
Step 5: Verification
```

### For Named Phases (Double Diamond)

```
🔍 Discover Phase: Research and exploration
🎯 Define Phase: Requirements and scope
🛠️ Develop Phase: Implementation
✅ Deliver Phase: Validation and review
```

### For Parallel Execution

```
Phase 2 [Parallel]:
  ├── 2a: Codex analysis
  ├── 2b: Gemini analysis
  └── 2c: Claude synthesis
```

---

## Data Flow Indicators

### Input Sources

```
[User Input] ─────────────────┐
                              ↓
[External URL] ──────────────→ Processing
                              ↑
[Context Data] ───────────────┘
```

### Output Destinations

```
Processing ──────────────────→ [Results File]
           ├─────────────────→ [Session Log]
           └─────────────────→ [User Display]
```

---

## Complex Example: Multi-Agent Workflow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    MULTI-AGENT RESEARCH WORKFLOW                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  [User Query] ─────────────────────────────────────────────────────────────┐│
│       ↓                                                                    ││
│  Step 1: Query Analysis                                                    ││
│       → Parse intent and scope                                             ││
│       → Identify required perspectives                                     ││
│       ↓                                                                    ││
│  Step 2: Parallel Research [Fan-Out]                                       ││
│       ├── 🔴 Codex: Technical implementation analysis                      ││
│       ├── 🟡 Gemini: Ecosystem and alternatives                            ││
│       └── 🔵 Claude: Strategic synthesis                                   ││
│       ↓ (75% quality gate)                                                 ││
│  Step 3: Results Synthesis [Fan-In]                                        ││
│       → Merge perspectives                                                 ││
│       → Resolve conflicts                                                  ││
│       → Generate consensus                                                 ││
│       ↓                                                                    ││
│  Step 4: Output Generation                                                 ││
│       → Format findings                                                    ││
│       → Create recommendations                                             ││
│       ↓                                                                    ││
│  [Research Results] ←──────────────────────────────────────────────────────┘│
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Conditional Flows

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       CONDITIONAL WORKFLOW                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Step 1: Evaluate Condition                                                 │
│       ↓                                                                     │
│  Step 2: Branch                                                             │
│       │                                                                     │
│       ├── IF condition A:                                                   │
│       │       → Execute Path A                                              │
│       │       → Path A specific steps                                       │
│       │       ↓                                                             │
│       ├── ELSE IF condition B:                                              │
│       │       → Execute Path B                                              │
│       │       ↓                                                             │
│       └── ELSE:                                                             │
│               → Execute Default Path                                        │
│               ↓                                                             │
│  Step 3: Converge                                                           │
│       → All paths merge here                                                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Loop Structures

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ITERATIVE WORKFLOW                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Step 1: Initialize                                                         │
│       → Set iteration counter = 0                                           │
│       → Define exit criteria                                                │
│       ↓                                                                     │
│  ┌─────────────────────────────────────────────────────────┐                │
│  │  LOOP (max N iterations)                                │                │
│  │       ↓                                                 │                │
│  │  Step 2: Execute Iteration                              │                │
│  │       → Perform work                                    │                │
│  │       ↓                                                 │                │
│  │  Step 3: Evaluate                                       │                │
│  │       → Check exit criteria                             │                │
│  │       ├── Met → EXIT LOOP                               │                │
│  │       └── Not met → CONTINUE                            │────────────┐   │
│  │                                                         │            │   │
│  └─────────────────────────────────────────────────────────┘←───────────┘   │
│       ↓ (exit)                                                              │
│  Step 4: Finalize                                                           │
│       → Report results                                                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Sizing Guidelines

### Width

- **Standard:** 77 characters inside box (79 total with borders)
- **Minimum:** 60 characters for readability
- **Maximum:** 79 characters (fits standard terminals)

### Height

- **Simple workflows:** 10-20 lines
- **Complex workflows:** 20-40 lines
- **Maximum:** Split into multiple diagrams if > 50 lines

---

## Do's and Don'ts

### DO

✅ Use consistent box characters throughout a diagram
✅ Align arrows vertically
✅ Use whitespace for readability
✅ Label all branches clearly
✅ Include brief descriptions with each step

### DON'T

❌ Mix box character styles (`┌` with `+`)
❌ Use overly long step descriptions (wrap to next line)
❌ Create diagrams wider than 79 characters
❌ Omit exit conditions for loops
❌ Leave dangling arrows

---

## Integration Checklist

When adding a diagram to a skill:

- [ ] Placed near top of skill file (after frontmatter)
- [ ] Uses standard box characters
- [ ] All steps are numbered or labeled
- [ ] Arrows clearly show flow direction
- [ ] Parallel paths are visually distinct
- [ ] Loop exit conditions are shown
- [ ] Width is ≤ 79 characters

---

## Related Documentation

- [OUTPUT-FORMAT-STANDARD.md](./OUTPUT-FORMAT-STANDARD.md) - Output templates
- [ERROR-HANDLING-STANDARD.md](./ERROR-HANDLING-STANDARD.md) - Error flows
- [WORKFLOW-SKILLS.md](./WORKFLOW-SKILLS.md) - Workflow patterns
