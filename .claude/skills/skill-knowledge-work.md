---
name: skill-knowledge-work
description: "Quick toggle between development and knowledge work mode. Use proactively when user mentions research, UX, strategy, or non-coding tasks."
triggerPatterns:
  - "switch.*mode"
  - "knowledge.*mode"
  - "research.*mode"
  - "toggle.*knowledge"
  - "enable.*research"
  - "disable.*research"
---

# Knowledge Work Mode - Quick Toggle Skill

This skill helps users quickly switch between **Development Mode** (code-focused) and **Knowledge Work Mode** (research, UX, strategy).

## When to Use This Skill

**Use PROACTIVELY** when you detect the user wants to:
- Switch from coding to research/analysis work
- Switch from research back to coding
- Check what mode they're currently in
- Work on UX research, market analysis, or strategic planning

## Detection Signals

### Switch to Knowledge Mode
User mentions:
- "I want to do some research"
- "Let's analyze the market"
- "Help me synthesize these papers"
- "Create user personas"
- "Strategic analysis"
- "UX research"

### Switch to Development Mode
User mentions:
- "Back to coding"
- "Let's build this"
- "Time to implement"
- "Ready to code"

### Check Status
User mentions:
- "What mode am I in?"
- "Am I in knowledge mode?"
- "Check my setup"

## How to Use

### Quick Status Check
When user seems unsure about mode:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh km status
```

### Enable Knowledge Mode
When user starts non-coding work:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh km on
```

### Disable Knowledge Mode
When user returns to coding:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh km off
```

### Recommended Setup (First Time)

For the best knowledge work experience, install document skills:
```
/plugin install document-skills@anthropic-agent-skills
```

This provides:
- PDF reading and analysis
- DOCX document creation/editing
- PPTX presentation generation
- XLSX spreadsheet handling

Then enable knowledge mode:
```
/octo:km on
```

The first time you enable knowledge mode, you'll see a recommendation to install document-skills if not already done.

## Conversation Flow Examples

### Example 1: User Switching to Research

**User:** "I want to research authentication best practices before we start coding"

**Claude Response:**
```
I notice you want to do research. Let me switch to Knowledge Work Mode for you, which optimizes auto-routing for research and analysis tasks.
```

Then run:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh km on
```

**Claude:** "✅ Knowledge Work Mode enabled! I'm now optimized for research, UX analysis, and strategic work. What would you like to research about authentication?"

### Example 2: User Switching to Development

**User:** "Okay, I've done enough research. Let's build the authentication system."

**Claude Response:**
```
You're ready to start building! Let me switch back to Development Mode.
```

Then run:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh km off
```

**Claude:** "✅ Development Mode active! Let's build that authentication system. Should we start with the overall architecture or jump into a specific component?"

### Example 3: User Unsure About Mode

**User:** "What mode am I in?"

**Claude Response:**
```
Let me check your current mode.
```

Then run:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh km status
```

**Claude:** "You're currently in [Mode]. This means auto-routing prioritizes [workflows]. Would you like to switch modes?"

## What Changes Per Mode

### Development Mode (Default) 🔧
- "Review this" → Code review
- "Analyze this" → Technical analysis
- "Research X" → Technical research
- Workflows: `embrace`, `probe`, `tangle`
- Agents: `codex`, `gemini`, `code-reviewer`

### Knowledge Work Mode 🎓
- "Review this" → Document/strategy review
- "Analyze this" → Market/user analysis
- "Research X" → Academic/market research
- Workflows: `empathize`, `advise`, `synthesize`
- Agents: `ux-researcher`, `strategy-analyst`, `research-synthesizer`

### Document Delivery 📄

After running empathize/advise/synthesize, convert results to professional formats:
- **DOCX** - Word documents for reports, business cases, academic papers
- **PPTX** - PowerPoint presentations for stakeholder decks, strategy briefs
- **XLSX** - Excel spreadsheets for data analysis, frameworks

Just say:
- "Export this to Word"
- "Create a PowerPoint presentation"
- "Convert to professional document"

Claude will automatically use the document-delivery skill with document-skills plugin.

**Check recent outputs:**
```bash
/octo:deliver-docs
```

**Prerequisites:** Install document-skills plugin:
```bash
/plugin install document-skills@anthropic-agent-skills
```

## Proactive Behavior

**DO proactively offer to switch when:**
- User transitions from coding to research tasks
- User asks about market analysis, UX, or strategy
- User wants to synthesize documents or papers
- User returns from research to implementation

**Example:**
```
User: "I want to analyze user feedback before implementing the feature"

Claude: "That sounds like UX research! Would you like me to enable Knowledge Work Mode?
This will optimize for user research synthesis and analysis. (Just say yes or I can do it now)"
```

**DON'T:**
- Switch modes without asking (unless it's obvious)
- Mention the mode in every response
- Switch back and forth frequently

## Command Reference

| Command | Description | Use When |
|---------|-------------|----------|
| `km` | Show status | User asks what mode they're in |
| `km on` | Enable knowledge mode | User starts research/UX/strategy work |
| `km off` | Disable knowledge mode | User returns to coding |
| `km toggle` | Switch modes | User explicitly asks to toggle |

Also available as slash command:
- `/octo:knowledge-mode on`
- `/octo:knowledge-mode off`
- `/octo:knowledge-mode`

## Integration with Other Skills

- **Before using `/octo:deep-research`**: Suggest enabling knowledge mode
- **Before using `/octo:code-review`**: Ensure development mode is active
- **When user mentions "empathize", "advise", "synthesize"**: Check if knowledge mode is enabled

## Persistence

Mode setting persists across:
- Terminal sessions
- Claude Code restarts
- Different projects

User only needs to toggle once, it stays that way until changed.

## Tips

1. **Context-aware**: Look at what the user is working on to suggest the right mode
2. **Minimize friction**: If obvious, just switch and mention it briefly
3. **Educate once**: First time, explain what mode does. After that, just do it
4. **Show status**: When unsure, check status first before suggesting changes

## Related Skills

- `/octo:parallel-agents` - Multi-AI orchestration
- `/octo:deep-research` - Research workflows (works better in knowledge mode)
- `/octo:configure` - Overall plugin configuration
