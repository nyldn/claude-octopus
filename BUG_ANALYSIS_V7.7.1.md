# Bug Analysis: v7.7.1 Auto-Invoke Feature Failure

## Status: FIXED in v7.7.1

## Summary
The v7.7.1 "auto-invoke orchestration" feature did not work as intended. The plugin installed successfully but Claude did not automatically trigger the skills on natural language requests like "research OAuth 2.0 patterns".

## Resolution (v7.7.1)
Updated all skill `description:` fields with directive language ("Use PROACTIVELY when...") 
so Claude Code can properly auto-invoke skills based on natural language patterns.

## Root Cause

**Claude Code does not read or use the `trigger:` field in skill frontmatter for automatic skill invocation.**

### How Claude Code Skills Actually Work

1. **Plugin Loading**: Claude Code loads skills listed in `plugin.json`
2. **Description Extraction**: It extracts the `description:` field from each skill's YAML frontmatter
3. **System Prompt Injection**: The skill name and description are injected into Claude's system prompt
4. **Manual Decision**: Claude (the AI) must manually decide to invoke skills based on the descriptions

### What v7.7.1 Implemented (Incorrectly)

The v7.7.1 implementation added extensive `trigger:` patterns in skill frontmatter:

```yaml
trigger: |
  AUTOMATICALLY ACTIVATE when user requests research or exploration:
  - "research X" or "explore Y" or "investigate Z"
  - "what are the options for X" or "what are my choices for Y"
  # ... etc
```

**Problem**: This `trigger:` field is never read by Claude Code. It's documentation-only.

### Current Skill Descriptions (Not Directive)

The `description:` fields are descriptive rather than directive:

```yaml
description: |
  Discover phase workflow - Research and exploration using external CLI providers.
  Part of the Double Diamond methodology (Discover phase).
  Uses Codex and Gemini CLIs for multi-perspective research.
```

This tells Claude WHAT the skill does, but not WHEN to use it.

## How Other Plugins Achieve "Auto-Invoke"

Looking at successful auto-invoking plugins in the system prompt, they use DIRECTIVE descriptions:

**Example from co:personas**:
```
"co:personas:backend-architect: ... Masters REST/GraphQL/gRPC APIs, event-driven architectures,
service mesh patterns, and modern backend frameworks. ... Use PROACTIVELY when creating new
backend services or APIs."
```

**Key phrases that trigger automatic invocation:**
- "Use PROACTIVELY for..."
- "Use IMMEDIATELY for..."
- "Use when the user asks to..."
- "Use for..."

## The Fix

### Option 1: Update `description:` Field (Recommended)

Move the trigger logic from the `trigger:` field into the `description:` field:

```yaml
description: |
  Deep research with multi-source synthesis and comprehensive analysis. Uses Codex and Gemini
  CLIs for multi-perspective research. Use PROACTIVELY when the user requests research or
  exploration: "research X", "explore Y", "investigate Z", "what are the options for X",
  "find information about Y", "compare X vs Y", or questions about best practices, patterns,
  or ecosystem research.
```

**Pros:**
- Works with Claude Code's actual implementation
- Visible to Claude in the system prompt
- No assumption about unsupported features

**Cons:**
- Description becomes longer
- Mixes "what it does" with "when to use it"

### Option 2: Programmatic Approach

Instead of relying on Claude's judgment, implement a hook or command that explicitly invokes skills:

```yaml
# In a PreToolUse hook or similar
if user_message matches research patterns:
    force invoke co:discover skill
```

**Pros:**
- More reliable triggering
- Can implement complex pattern matching

**Cons:**
- Requires hook system
- Less flexible than Claude's judgment
- May feel intrusive to users

### Option 3: Hybrid Approach (Best?)

1. Update `description:` with directive language (Option 1)
2. Keep detailed `trigger:` patterns as internal documentation for Claude to read when the skill is invoked
3. The `trigger:` field becomes helpful context that Claude sees when reading the skill file

## Testing Strategy

To test if auto-invoke works:

1. **Test Setup**:
   ```bash
   # Install updated plugin
   # Restart Claude Code session
   ```

2. **Test Cases**:
   - User: "Research OAuth 2.0 authentication patterns for React apps"
     - Expected: Claude proactively invokes `/co:discover` or `/co:research` skill
   - User: "Compare Redis vs Memcached"
     - Expected: Claude proactively invokes discover/research skill
   - User: "What are the best practices for API pagination?"
     - Expected: Claude proactively invokes discover/research skill

3. **Success Criteria**:
   - Claude automatically invokes the skill WITHOUT user typing `/co:discover`
   - Skill executes and provides multi-AI orchestrated results
   - No manual skill invocation required

## Recommended Next Steps

1. **Immediate**: Roll back to v7.7.0 (already done)
2. **Next Version (v7.7.2 or v7.8.0)**:
   - Update all workflow skill `description:` fields with directive language
   - Test auto-invoke behavior thoroughly before release
   - Consider creating a test suite that validates auto-invoke triggering
3. **Documentation**:
   - Update README to explain that auto-invoke relies on directive descriptions
   - Add developer guide explaining Claude Code skill invocation mechanics

## Related Files

- `.claude/skills/flow-discover.md` (and other flow-* skills)
- `.claude/skills/skill-deep-research.md`
- `.claude/skills/skill-debate.md`
- `.claude-plugin/plugin.json`

## References

- Commit cac771c: "feat: Add auto-invoke orchestration for v7.7.1"
- System prompt skill descriptions (visible to Claude during execution)
- Claude Code plugin documentation
