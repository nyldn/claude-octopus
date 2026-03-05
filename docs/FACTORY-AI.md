# Claude Octopus on Factory AI

Claude Octopus is fully compatible with [Factory AI](https://factory.ai)'s Droid platform. Factory's plugin format is interoperable with Claude Code plugins, so Octopus works on both platforms.

## Quick Install

### From Factory Marketplace

```bash
# Add the Octopus marketplace
droid plugin marketplace add https://github.com/nyldn/claude-octopus

# Install
droid plugin install claude-octopus@nyldn-plugins
```

### From GitHub (Direct)

```bash
# Clone and install locally
git clone https://github.com/nyldn/claude-octopus.git
cd claude-octopus
droid plugin install . --scope project
```

### Via Organization Settings

Add to your `.factory/settings.json` for team-wide deployment:

```json
{
  "extraKnownMarketplaces": {
    "nyldn-plugins": {
      "source": { "source": "github", "repo": "nyldn/claude-octopus" }
    }
  },
  "enabledPlugins": {
    "claude-octopus@nyldn-plugins": true
  }
}
```

## What Works

| Feature | Status | Notes |
|---------|--------|-------|
| 49 slash commands (`/octo:*`) | Works | All commands available via `/octo:` prefix |
| 50 skills | Works | Auto-loaded by Droid's skill system |
| 32 expert personas | Works | Persona routing via `agents/config.yaml` |
| Multi-provider orchestration | Works | Codex + Gemini + host model |
| Double Diamond workflow | Works | Discover, Define, Develop, Deliver |
| Hooks (quality gates, telemetry) | Works | All 10 hook event types |
| Worktree isolation | Works | Factory supports worktrees |
| MCP server integration | Works | Factory has native MCP support |

## Differences from Claude Code

| Aspect | Claude Code | Factory AI |
|--------|------------|------------|
| Plugin root variable | `${CLAUDE_PLUGIN_ROOT}` | `${DROID_PLUGIN_ROOT}` (auto-resolved) |
| Manifest location | `.claude-plugin/plugin.json` | `.factory-plugin/plugin.json` |
| Subagents | "agents" | "droids" |
| Version detection | `claude --version` | `droid --version` |
| Model selection | Claude models + external | Any model (OpenAI, Anthropic, Google, xAI, local) |

Octopus detects which host platform it's running on and adapts automatically. Factory's interop layer resolves `${CLAUDE_PLUGIN_ROOT}` to `${DROID_PLUGIN_ROOT}` transparently.

## Setup

After installing, run:

```
/octo:setup
```

This checks provider availability (Codex CLI, Gemini CLI) and configures your environment.

## Model Configuration

Factory AI is model-agnostic. Octopus's multi-provider orchestration maps naturally:

- **Codex CLI** (`codex`) - Uses your OpenAI API key
- **Gemini CLI** (`gemini`) - Uses your Google API key
- **Host model** - Whatever model Factory is configured to use (Anthropic, OpenAI, Google, etc.)

Configure models via `/octo:model-config`.

## Architecture

Octopus runs its orchestration layer (`scripts/orchestrate.sh`) as a bash subprocess. This is platform-agnostic — it works identically on Claude Code and Factory AI because:

1. Both platforms support `Bash` tool execution
2. Both platforms support hook lifecycle events
3. Both platforms support skills and commands
4. The orchestrator communicates via files and stdout, not platform-specific APIs

The only platform-specific code is version detection (`detect_claude_code_version()`), which auto-detects Factory and assumes full feature parity.

## Troubleshooting

### Plugin not loading

Verify installation:
```bash
droid plugin list
```

Check that `.factory-plugin/plugin.json` exists in the plugin root.

### Commands not appearing

Run `/plugins` in Droid to check plugin status. Ensure the plugin is enabled at the correct scope (user or project).

### External providers not working

Octopus needs Codex CLI and/or Gemini CLI installed for multi-provider workflows:
```bash
# Check availability
command -v codex && echo "Codex OK" || echo "Install: npm install -g @openai/codex"
command -v gemini && echo "Gemini OK" || echo "Install: npm install -g @anthropic-ai/gemini"
```

Single-provider mode (host model only) works without external CLIs.

## Links

- [Factory AI Documentation](https://docs.factory.ai/welcome)
- [Factory Plugin Guide](https://docs.factory.ai/guides/building/building-plugins)
- [Claude Octopus README](../README.md)
- [Claude Octopus GitHub](https://github.com/nyldn/claude-octopus)
