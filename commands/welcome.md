---
description: Welcome to Claude Octopus! Get started with setup instructions.
---

# 🐙 Welcome to Claude Octopus!

Thanks for installing Claude Octopus - your multi-tentacled orchestrator for comprehensive AI problem-solving.

## Quick Setup (2 minutes)

### Step 1: Install ONE Provider

You only need **one** of these (not both):

**Option A: OpenAI Codex** (best for code generation)
```bash
npm install -g @openai/codex
codex login  # OAuth (recommended)
# OR set API key:
export OPENAI_API_KEY="sk-..."
```
Get API key: https://platform.openai.com/api-keys

**Option B: Google Gemini** (best for analysis)
```bash
npm install -g @google/gemini-cli
gemini  # OAuth (recommended)
# OR set API key:
export GEMINI_API_KEY="AIza..."
```
Get API key: https://aistudio.google.com/app/apikey

### Step 2: Verify Setup

Run this to check your setup:
```
/claude-octopus:setup
```

Or run:
```bash
cd ~/.claude/plugins/claude-octopus && ./scripts/orchestrate.sh detect-providers
```

### Step 3: Start Using It!

Just talk to Claude naturally:

- "Research OAuth authentication patterns"
- "Build a user authentication system"
- "Review this code for security vulnerabilities"
- "Use adversarial review to critique my implementation"

Claude Octopus automatically activates when you need multi-AI collaboration!

## What Can It Do?

### 🔍 Research & Exploration (Probe)
Parallel research from multiple AI perspectives with synthesis

### 🎯 Problem Definition (Grasp)
Build consensus on problem statements and requirements

### 🔨 Implementation (Tangle)
Parallel development with quality gates (75% threshold)

### ✅ Validation (Ink)
Pre-delivery validation and result synthesis

### ⚔️ Adversarial Review (Crossfire)
- **Grapple**: Two models debate solutions until consensus
- **Squeeze**: Red team security review (Blue Team vs Red Team)

## Need Help?

- Run `/claude-octopus:setup` to check your configuration
- Check logs: `~/.claude-octopus/logs/`
- Report issues: https://github.com/nyldn/claude-octopus/issues

## Advanced Usage

For direct CLI usage or automation, see:
```
cd ~/.claude/plugins/claude-octopus && cat docs/CLAUDE.md
```

---

**Ready?** Just start talking to Claude naturally about your coding tasks!
