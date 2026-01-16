---
description: Check for Claude Code updates and assess impact on claude-octopus
---

# Claude Code Update Check

Run this routine to assess new Claude Code features for claude-octopus compatibility.

## Steps

1. **Check current Claude Code version:**
```bash
claude --version
```

2. **Check for available updates:**
```bash
npm view @anthropic-ai/claude-code version
```

3. **Review changelog for relevant features:**
   - Open: https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md
   - Focus on: hooks, skills, agents, MCP tools, parallel execution, CLI changes

4. **Key features to monitor for claude-octopus:**
   - **Hooks** - PreToolUse/PostToolUse/Stop for phase validation
   - **Skills** - Hot reload, nested discovery, context forking
   - **Agents** - Model selection fixes, background task controls
   - **Environment Variables** - Session ID, temp directory, task controls
   - **Parallel Execution** - Bug fixes affecting fan-out/tangle phases

5. **Update checklist:**
   - [ ] Check if new env vars benefit orchestrate.sh
   - [ ] Review hook enhancements for quality gates
   - [ ] Assess MCP/tool changes for agent coordination
   - [ ] Test parallel execution improvements

## Version Compatibility Matrix

| Claude Code | Claude-Octopus | Notes |
|-------------|----------------|-------|
| 2.1.9+ | 4.5.0+ | Full compatibility, session ID support |
| 2.1.7+ | 4.5.0+ | MCP auto-mode, keyboard shortcuts |
| 2.1.0+ | 4.0.0+ | Hooks in frontmatter, hot reload |
| 2.0.x | 3.x | Legacy mode |

## Schedule

Run this check:
- After major Claude Code releases (2.x.0)
- Monthly for patch releases
- When users report compatibility issues
