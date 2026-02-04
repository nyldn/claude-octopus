# Debug Mode

Enable detailed debug logging for troubleshooting Claude Octopus issues.

## Usage

### Option 1: Environment Variable

```bash
export OCTOPUS_DEBUG=1
./scripts/orchestrate.sh <command>
```

### Option 2: Command-line Flag

```bash
./scripts/orchestrate.sh --debug <command>
```

### Option 3: Inline

```bash
OCTOPUS_DEBUG=1 ./scripts/orchestrate.sh <command>
```

## What Debug Mode Shows

Debug mode provides detailed logging including:

- **Startup information**: Command, workspace directory, project root
- **Provider detection**: Which AI providers are found and their authentication status
- **Agent execution**: Agent type, role, phase, timeout, command being executed
- **Execution results**: Exit codes, output lengths, timing information
- **Workflow progress**: Phase transitions and task group IDs
- **Error context**: Enhanced error messages with full context

## Example Output

```bash
$ OCTOPUS_DEBUG=1 ./scripts/orchestrate.sh detect-providers

[DEBUG] ═══ Orchestrate.sh starting ═══
[DEBUG] COMMAND=detect-providers
[DEBUG] OCTOPUS_DEBUG=1
[DEBUG] WORKSPACE_DIR=/Users/chris/.claude-octopus
[DEBUG] PROJECT_ROOT=/Users/chris/git/claude-octopus
[DEBUG] Arguments:

[DEBUG] ═══ Detecting AI providers ═══
[DEBUG] Checking for Codex CLI...
[DEBUG] ✓ Codex CLI found with auth: oauth
[DEBUG] Checking for Gemini CLI...
[DEBUG] ✓ Gemini CLI found with auth: oauth
[DEBUG] Checking for Claude CLI...
[DEBUG] ✓ Claude CLI found
[DEBUG] Checking for OpenRouter API key...
[DEBUG] ✗ OpenRouter API key not found
[DEBUG] Detected providers: codex:oauth gemini:oauth claude:oauth
```

## When to Use Debug Mode

- **Troubleshooting errors**: When commands fail or behave unexpectedly
- **Provider issues**: When AI providers aren't being detected or called correctly
- **Performance debugging**: To understand execution flow and timing
- **Development**: When working on orchestrate.sh itself
- **Bug reports**: Include debug output when reporting issues

## Note

Debug mode automatically enables verbose mode (`--verbose`), so you'll see both debug logs and standard verbose output.

## Disabling Debug Mode

```bash
# If set via environment variable
unset OCTOPUS_DEBUG

# Or just don't use the --debug flag
./scripts/orchestrate.sh <command>
```
