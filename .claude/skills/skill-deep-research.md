---
name: octopus-research
description: |
  Deep research using Claude Octopus probe workflow.
  Parallel multi-perspective research with AI synthesis.
  
  Use PROACTIVELY when user wants deep analysis or investigation:
  - "research this topic", "investigate how X works"
  - "analyze the architecture", "explore different approaches to Y"
  - "what are the options for Z", "deep dive into X"
  - "comprehensive analysis of Y", "thorough research on Z"
  
  DO NOT use for: simple factual queries Claude can answer directly,
  or questions about specific code in current project (use Read tool).
trigger: |
  Use this skill when the user wants to "research this topic", "investigate how X works",
  "analyze the architecture", "explore different approaches to Y", or "what are the options for Z".
---

# Deep Research Skill

Lightweight wrapper that triggers Claude Octopus probe workflow for comprehensive, multi-perspective research.

## When This Skill Activates

Auto-invokes when user says:
- "research this topic"
- "investigate how X works"
- "analyze the architecture"
- "explore different approaches to Y"
- "what are the options for Z"

## What It Does

**Probe Phase (Discover):**

1. **Parallel Research**: 4 AI agents research simultaneously from different angles:
   - **Researcher**: Technical analysis and documentation
   - **Designer**: UX patterns and user impact
   - **Implementer**: Code examples and implementation
   - **Reviewer**: Best practices and gotchas

2. **AI Synthesis**: Gemini synthesizes all findings into coherent report

3. **Quality Gate**: Ensures comprehensive coverage (≥75% agreement on key findings)

## Usage

```markdown
User: "Research the best state management options for React"

Claude: *Activates octopus-research skill*
        *Runs: ./scripts/orchestrate.sh probe "State management options for React"*
```

## Implementation

When this skill is invoked, Claude should:

1. **Detect research intent**: User wants deep analysis
2. **Invoke probe workflow**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh probe "[user's research question]"
   ```
3. **Present synthesized findings**: Format multi-perspective results

## Output Format

```markdown
## Research Summary: State Management for React

### Overview
Four AI agents researched state management options from different perspectives.

### Key Findings

**From Researcher (Technical Analysis)**:
- Redux: Most mature, 50K+ stars, extensive ecosystem
- Zustand: Lightweight, 500 bytes, minimal boilerplate
- Jotai: Atomic state, React 18 concurrent features

**From Designer (UX Perspective)**:
- Context API: Built-in, no deps, best for simple apps
- Redux DevTools: Time-travel debugging aids UX iteration
- Zustand: Less boilerplate = faster prototyping

**From Implementer (Code Examples)**:
- Zustand wins for developer experience (3 lines of code)
- Redux requires more setup but scales to large teams
- Jotai best for performance-critical apps

**From Reviewer (Best Practices)**:
- Redux: Proven at scale (Meta, Airbnb, Twitter)
- Avoid prop drilling with any solution
- Pick based on team size and app complexity

### Synthesized Recommendation
**For your use case**: Zustand (small team, rapid iteration)
- Pros: Minimal boilerplate, easy learning curve
- Cons: Smaller community than Redux
- Migration path: Can switch to Redux later if needed

**Quality Gate**: PASSED (92% agreement across agents)
```

## Why Use This?

| Aspect | Deep Research | Manual Research |
|--------|---------------|-----------------|
| Perspectives | 4 simultaneous | 1 sequential |
| Time | 2-3 min | 20-30 min |
| Bias | Multi-agent reduces bias | Single viewpoint |
| Synthesis | AI-powered | Manual comparison |

## Configuration

Respects all octopus configuration:
- `--parallel`: Control concurrent agents (default: 4)
- `--timeout`: Set research time limit (default: 300s)
- `--provider`: Force specific AI provider
- `--quality-first`: Prefer premium models for depth

## Example Scenarios

### Scenario 1: Architecture Research
```
User: "Research microservices vs monolith for our e-commerce platform"
→ Probe: 4 agents research from different angles
→ Synthesis: Pros/cons, case studies, recommendation
→ Output: Decision matrix with migration path
```

### Scenario 2: Library Comparison
```
User: "Compare React testing libraries"
→ Probe: Jest vs Vitest vs Playwright analysis
→ Synthesis: Feature matrix, performance, DX
→ Output: Recommendation based on team needs
```

### Scenario 3: Best Practices Discovery
```
User: "How should we handle authentication in Next.js?"
→ Probe: OAuth, JWT, sessions, edge auth patterns
→ Synthesis: Security, UX, implementation complexity
→ Output: Implementation guide with code examples
```

## Advanced Features

### Customizing Research Angles

Probe workflow uses 4 default perspectives, but you can guide it:

```markdown
User: "Research GraphQL vs REST, focusing on mobile app performance"
→ Probe automatically emphasizes:
  - Network efficiency (mobile-specific)
  - Battery impact (mobile-specific)
  - Caching strategies (performance)
  - Developer experience (implementation)
```

### Research Depth Control

- **Quick scan** (--cost-first): 1-2 min, surface-level
- **Standard** (default): 2-3 min, balanced depth
- **Deep dive** (--quality-first): 3-5 min, comprehensive

### Session Recovery

If research is interrupted:
```bash
# Resume from last checkpoint
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh probe --resume
```

## Related Skills

- **octopus-quick-review** (grasp + tangle) - For code review
- **octopus-security** (squeeze) - For security testing
- **Full embrace** - For research → implementation → validation

## When NOT to Use This

❌ **Don't use for**:
- Simple factual queries (use regular Claude)
- Already know the answer (use direct implementation)
- Need real-time data (probe uses training data)

✅ **Do use for**:
- Comparing multiple approaches
- Understanding complex systems
- Discovering best practices
- Architecture decisions
- Technology evaluation

## Technical Notes

- Uses existing probe command from orchestrate.sh
- Requires at least 1 provider (Codex or Gemini)
- Parallel execution reduces research time by 4x
- AI synthesis prevents information overload
- Quality gates ensure no perspective is missed
