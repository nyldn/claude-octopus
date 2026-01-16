# Claude Octopus - Development Guide

This document is for **developers working on the Claude Octopus plugin itself**. For plugin usage, see the main [CLAUDE.md](../CLAUDE.md).

## Development Commands

```bash
# Make scripts executable (required after clone)
chmod +x scripts/*.sh

# Verify shell script syntax
bash -n ./scripts/orchestrate.sh

# Test with dry-run (shows plan without execution)
./scripts/orchestrate.sh -n auto "prompt"

# Verbose mode for debugging
./scripts/orchestrate.sh -v auto "prompt"

# Run test suite
./scripts/test-claude-octopus.sh
```

## Architecture

### Entry Point
- **orchestrate.sh** (~7000 lines) - Main bash orchestrator with Double Diamond workflows

### Core Patterns

**Double Diamond Workflow**:
1. **Probe** (Discover): Parallel research from 4 perspectives, AI-synthesized
2. **Grasp** (Define): Multi-tentacled consensus on problem definition
3. **Tangle** (Develop): Map-reduce with 75% quality gate
4. **Ink** (Deliver): Validation and final deliverable generation

**Auto-Routing**: Classifies prompts via regex patterns and routes to Double Diamond phases or single agents.

**Fan-Out**: Sends same prompt to multiple agents in parallel for diverse perspectives.

**Map-Reduce**: Gemini decomposes → parallel execution → Gemini synthesizes.

### Key Functions (orchestrate.sh)

#### Double Diamond Functions
- `classify_task()` - Double Diamond intent + task type detection
- `probe_discover()` - Phase 1: Parallel research
- `grasp_define()` - Phase 2: Consensus building
- `tangle_develop()` - Phase 3: Quality-gated development
- `ink_deliver()` - Phase 4: Validated delivery
- `embrace_full_workflow()` - All 4 phases sequentially
- `preflight_check()` - Dependency validation

#### Provider Routing Functions (v4.8)
- `detect_providers()` - Returns installed CLIs with auth methods
- `load_providers_config()` - Loads ~/.claude-octopus/.providers-config
- `save_providers_config()` - Saves provider configuration
- `auto_detect_provider_config()` - Auto-populates from installed CLIs
- `score_provider()` - Score a provider for task (0-150 scale)
- `select_provider()` - Select best provider using scoring
- `get_tiered_agent_v2()` - Enhanced routing with provider scoring
- `is_agent_available_v2()` - Check availability including OpenRouter
- `get_fallback_agent_v2()` - Smart fallback with scoring
- `execute_openrouter()` - Execute prompt via OpenRouter API

#### Agent Management
- `spawn_agent()` - Launch agent process
- `get_agent_command()` - Get CLI command for agent type
- `get_agent_command_array()` - Get command as array (for proper quoting)

### Workspace Structure
```
~/.claude-octopus/           # Override with CLAUDE_OCTOPUS_WORKSPACE
├── results/
│   ├── probe-synthesis-*.md      # Research findings
│   ├── grasp-consensus-*.md      # Problem definitions
│   ├── tangle-validation-*.md    # Quality gate reports
│   └── delivery-*.md             # Final deliverables
├── logs/                    # Execution logs
├── plans/                   # Execution plans
├── .user-config             # User intent and preferences (v4.5)
├── .providers-config        # Provider tiers and routing (v4.8)
└── pids                     # Process tracking
```

## Adding New Functionality

### New Agent Type
1. `orchestrate.sh`: Add case in `get_agent_command()` and `get_agent_command_array()`
2. `orchestrate.sh`: Update `AVAILABLE_AGENTS` variable
3. `skill.md`: Update agent selection guide table

### New Task Type Classification
1. Update `classify_task()` regex patterns in `orchestrate.sh`
2. Update auto-routing logic in `auto_route()`
3. Update skill.md task types documentation

### New Double Diamond Phase
1. Add function in `orchestrate.sh` following `probe_discover()` pattern
2. Add command dispatch case in main command handler
3. Update documentation in skill.md and CLAUDE.md

### New Provider Support
1. Add provider variables: `PROVIDER_<NAME>_INSTALLED`, `_AUTH_METHOD`, `_TIER`, `_COST_TIER`, `_PRIORITY`
2. Update `detect_providers()` to detect CLI installation
3. Update `get_provider_capabilities()` with provider capabilities
4. Update `get_provider_context_limit()` with context limits
5. Update `load_providers_config()` and `save_providers_config()`
6. Add setup wizard step for tier configuration
7. Update `score_provider()` scoring logic if needed

## Provider Scoring Algorithm

The `score_provider()` function uses a 0-150 scale:

| Factor | Points | Description |
|--------|--------|-------------|
| Base | 50 | Starting score for available provider |
| Cost (cost-first) | +0-50 | Higher for cheaper tiers |
| Cost (quality-first) | +0-30 | Higher for premium tiers |
| Complexity match | +0-20 | Higher tiers for complex tasks |
| Priority | +0-10 | User preference |
| Capability bonus | +10 | Vision for images, long-context for research |

Returns -1 if provider lacks required capability.

## Testing

The test suite is in `scripts/test-claude-octopus.sh`:

```bash
# Run all tests
./scripts/test-claude-octopus.sh

# Tests are organized in sections:
# 1-10: Core functionality
# 11-19: Crossfire, quality gates, etc.
# 20: Multi-provider routing (27 tests)
```

### Adding New Tests

Tests use simple assertions:

```bash
test_my_feature() {
    local result
    result=$(my_function "input")
    [[ "$result" == "expected" ]] || { echo "FAIL: description"; return 1; }
    echo "PASS: my_feature"
}
```

## Configuration File Formats

### .user-config (v1.1)
```
version: 1.1
intent: backend
codex_tier: standard
gemini_tier: standard
claude_tier: opus
```

### .providers-config (v2.0)
```yaml
version: "2.0"
providers:
  codex:
    installed: true
    auth_method: "oauth"
    subscription_tier: "plus"
    cost_tier: "low"
    priority: 2
  # ... other providers
cost_optimization:
  strategy: "balanced"
```

## Shell Script Conventions

- Bash 3.x compatible (macOS default)
- `set -eo pipefail` for strict error handling
- Use `|| true` for commands that may "fail" but shouldn't exit
- Quote all variables: `"$var"` not `$var`
- Use `local` for function variables
- Prefix internal functions with `_` (e.g., `_helper_func`)
