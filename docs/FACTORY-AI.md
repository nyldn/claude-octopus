# Claude Octopus on Factory AI

Claude Octopus is fully compatible with [Factory AI](https://factory.ai)'s Droid platform. Factory's plugin format is interoperable with Claude Code plugins, so Octopus works on both platforms.

## Quick Install

### From Factory Marketplace

```bash
# Add the Octopus marketplace
droid plugin marketplace add https://github.com/nyldn/claude-octopus

# Install (marketplace name matches the GitHub repo name)
droid plugin install octo@claude-octopus
```

> **Note:** Factory registers marketplaces by GitHub repo name, not the internal
> `marketplace.json` name. If `octo@claude-octopus` doesn't work, run
> `droid plugin marketplace list` to check the registered name, then use
> `droid plugin install claude-octopus@<registered-name>`.

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
    "claude-octopus": {
      "source": { "source": "github", "repo": "nyldn/claude-octopus" }
    }
  },
  "enabledPlugins": {
    "octo@claude-octopus": true
  }
}
```

## What Works

| Feature | Status | Notes |
|---------|--------|-------|
| 44 skills (auto-discovered) | Works | Generated `skills/<name>/SKILL.md` directories |
| 49 slash commands | Works | Copied to `commands/` at plugin root |
| 32 expert personas | Works | Persona routing via `agents/config.yaml` |
| Multi-provider orchestration | Works | Codex + Gemini + host model |
| Double Diamond workflow | Works | Discover, Define, Develop, Deliver |
| Hooks (quality gates, telemetry) | Works | All 10 hook event types |
| Worktree isolation | Works | Factory supports worktrees |
| MCP server integration | Works | Factory has native MCP support |

### What Doesn't Map

| Feature | Notes |
|---------|-------|
| 6 human-only skills | Excluded from Factory (require interactive Claude Code features) |
| Command namespacing (`/octo:*`) | Factory commands use filename as-is (`/setup`, `/define`), not prefixed with `octo:` |

## Differences from Claude Code

| Aspect | Claude Code | Factory AI |
|--------|------------|------------|
| Plugin root variable | `${CLAUDE_PLUGIN_ROOT}` | `${DROID_PLUGIN_ROOT}` (auto-resolved) |
| Manifest location | `.claude-plugin/plugin.json` | `.factory-plugin/plugin.json` |
| Skill format | `.claude/skills/<name>.md` (flat) | `skills/<name>/SKILL.md` (directory per skill) |
| Skill frontmatter | Extended (agent, context, trigger, etc.) | Simple (name, version, description) |
| Commands | `.claude/commands/<name>.md` | `commands/<name>.md` (no plugin prefix) |
| Subagents | "agents" | "droids" |
| Version detection | `claude --version` | `droid --version` |
| Model selection | Claude models + external | Any model (OpenAI, Anthropic, Google, xAI, local) |

Octopus detects which host platform it's running on and adapts automatically. Factory's interop layer resolves `${CLAUDE_PLUGIN_ROOT}` to `${DROID_PLUGIN_ROOT}` transparently.

## Cross-Platform Skill Discovery

Claude Code discovers skills from `.claude/skills/` (declared in `.claude-plugin/plugin.json`). Factory AI discovers skills from `skills/<name>/SKILL.md` directories at the plugin root.

To serve both platforms from the same repo, Octopus uses a **build script** that generates Factory-compatible skill directories from the Claude Code source files:

```bash
# Generate Factory-compatible skills/ directory
bash scripts/build-factory-skills.sh

# Clean generated skills
bash scripts/build-factory-skills.sh --clean
```

The build script:
1. Reads each `.claude/skills/*.md` file
2. Strips Octopus-specific frontmatter (agent, context, execution_mode, trigger, etc.)
3. Adds `version: 1.0.0` (required by Factory)
4. Merges `trigger` content into `description` (Factory uses description for skill selection)
5. Skips skills marked `invocation: human_only`
6. Writes `skills/<skill-name>/SKILL.md`
7. Copies `.claude/commands/*.md` to `commands/` for Factory command discovery

The generated `skills/` and `commands/` directories are **committed to git** (not gitignored), so Factory discovers everything immediately on install without a build step.

> **Note:** On Claude Code, commands are namespaced as `/octo:<name>` (e.g., `/octo:setup`).
> On Factory, they appear as `/<name>` (e.g., `/setup`) since Factory uses the filename directly.

### Regenerating After Skill or Command Changes

When you add, modify, or remove skills in `.claude/skills/` or commands in `.claude/commands/`, regenerate:

```bash
bash scripts/build-factory-skills.sh
```

Then commit the updated `skills/` and `commands/` directories.

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
3. Both platforms support skills (Factory via `skills/`, Claude Code via `.claude/skills/`)
4. The orchestrator communicates via files and stdout, not platform-specific APIs

The only platform-specific code is version detection (`detect_claude_code_version()`), which auto-detects Factory and assumes full feature parity.

## Troubleshooting

### Plugin not loading

Verify installation:
```bash
droid plugin list
```

Check that `.factory-plugin/plugin.json` exists in the plugin root.

### Skills not appearing

Verify the `skills/` directory exists and contains SKILL.md files:
```bash
ls skills/*/SKILL.md | wc -l
# Should show 44
```

If missing, regenerate:
```bash
bash scripts/build-factory-skills.sh
```

Also run `/plugins` in Droid to check plugin status. Ensure the plugin is enabled at the correct scope (user or project).

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
