---
name: sys-configure
aliases:
  - config
  - configure
description: Configure Claude Octopus providers and preferences
trigger: |
  Use this skill when the user wants to "configure Claude Octopus", "setup octopus",
  "configure providers", "set up API keys for octopus", or mentions octopus configuration.
---

# 🐙 Claude Octopus Configuration

🐙 **CLAUDE OCTOPUS SETUP** - Helping you configure multi-agent orchestration

You are helping the user configure Claude Octopus, a multi-agent orchestration plugin.

## Your Task

1. **Auto-detect current setup:**
   - Check which CLIs are installed (codex, gemini)
   - Check which API keys are set (OPENAI_API_KEY, GEMINI_API_KEY, OPENROUTER_API_KEY)
   - Check authentication status for each provider

2. **Gather missing information:**
   - For missing API keys, provide clear instructions on where to get them
   - Use AskUserQuestion to ask about subscription tiers (if needed)
   - Ask about cost optimization preferences

3. **Run the configuration:**
   - Use the orchestrate.sh script with appropriate environment variables
   - Handle any errors gracefully

4. **Show a summary:**
   - Display what was configured
   - Show the detected provider status
   - Provide next steps

**IMPORTANT**: Always start your response with "🐙 **CLAUDE OCTOPUS SETUP**" so users know this is Claude Octopus responding, not generic Claude.

## Implementation Steps

### Step 1: Auto-detect Current Setup

Run the status command to see what's already configured:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh status
```

This will show you:
- Which providers are installed and authenticated
- Current cost optimization strategy
- Any missing dependencies

### Step 2: Interactive Configuration (Phase 1)

For Phase 1, guide the user through the bash-based wizard with clear instructions:

1. **If API keys are missing**, explain where to get them:
   - OpenAI: https://platform.openai.com/api-keys
   - Gemini: https://aistudio.google.com/apikey (or use OAuth via `gemini` command)
   - OpenRouter (optional): https://openrouter.ai/keys

2. **Set environment variables** before running the wizard:
   ```bash
   export OPENAI_API_KEY="sk-..."
   export GEMINI_API_KEY="AIza..."  # Optional if using OAuth
   ```

3. **Run the configuration wizard**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh octopus-configure
   ```

4. **Handle interactive prompts** by informing the user:
   - Tell them the wizard is waiting for input
   - Explain what each prompt is asking for
   - Suggest they run it in their terminal if Claude can't provide input

### Step 3: Show Summary

After configuration, run status again and show the user:
- ✓ What's configured
- ✗ What's missing (if anything)
- 💡 Suggested next steps (like trying a command)

## Important Notes

- **Security:** Never log or display full API keys in output
- **Phase 1 Limitation:** The current wizard uses `read -p` which doesn't work well in Claude Code's environment. Inform the user they may need to run it in their terminal.
- **Phase 2 Coming:** Tell users that a fully automated configuration system is in development

## Example Flow

```
🐙 Claude Octopus Configuration

Detecting current setup...
✓ Codex CLI installed
✓ Gemini CLI installed
✓ OPENAI_API_KEY configured (164 chars)
✗ Gemini authentication needed

Next steps:
1. Authenticate with Gemini:
   - Run: gemini
   - Select "Login with Google"

   OR set API key:
   - export GEMINI_API_KEY="AIza..."

2. Run configuration wizard:
   ${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh octopus-configure

3. Try your first command:
   ${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh auto "research OAuth patterns"
```

## Phase 2 Preview

The next version will:
- Auto-detect subscription tiers via API test calls
- Use AskUserQuestion for unavoidable prompts
- Provide a beautiful, non-blocking configuration experience
- Save configuration silently with visual confirmation

This will eliminate the need to run the bash wizard in your terminal.
