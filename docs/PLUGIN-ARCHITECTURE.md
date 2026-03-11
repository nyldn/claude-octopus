# Plugin Architecture - How Claude Octopus Works

This guide explains the internal architecture of Claude Octopus for contributors and advanced users.

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Claude Code                             │
│  ┌────────────────────────────────────────────────────────┐ │
│  │            Claude Octopus Plugin                        │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │ │
│  │  │    Skills    │  │    Hooks     │  │   Commands   │ │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘ │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                            ↓
        ┌──────────────────────────────────────┐
        │      orchestrate.sh (Bash)            │
        └──────────────────────────────────────┘
                            ↓
        ┌──────────────┬────────────┬───────────┐
        │  Codex CLI   │ Gemini CLI │  Claude   │
        │  (OpenAI)    │  (Google)  │ Subagent  │
        └──────────────┴────────────┴───────────┘
```

---

## Component Overview

### 1. Plugin Manifest (plugin.json)

**Location:** `.claude-plugin/plugin.json`

**Purpose:** Defines the plugin metadata, skills, commands, and dependencies.

```json
{
  "name": "octo",
  "version": "8.49.1",
  "description": "Multi-tentacled orchestrator...",
  "skills": [
    "./.claude/skills/skill-parallel-agents.md",
    "./.claude/skills/flow-discover.md",
    "./.claude/skills/flow-define.md",
    "./.claude/skills/flow-develop.md",
    "./.claude/skills/flow-deliver.md",
    "./.claude/skills/skill-debate.md",
    ...
  ],
  "commands": [
    "./.claude/commands/octo.md",
    "./.claude/commands/embrace.md",
    ...
  ]
}
```

**Key Fields:**
- `skills`: Array of markdown files defining skills (50 total in the current manifest)
- `commands`: Array of markdown files defining slash commands (38 total in the current manifest)

#### Command Prefix Safeguard

The plugin manifest name must remain `octo`.

| File | Value | Purpose |
|------|-------|---------|
| `package.json` | `claude-octopus` | Package and marketplace identity |
| `.claude-plugin/plugin.json` | `octo` | Command prefix for `/octo:*` |

If the plugin name changes, command paths change with it:
- `octo` + `discover` -> `/octo:discover`
- `claude-octopus` + `discover` -> `/claude-octopus:discover`

**Why this matters:**
- It breaks existing user workflows and docs immediately
- It changes every slash-command path exposed by the plugin
- The repository already includes validation for this via `make test-plugin-name` and `./tests/validate-plugin-name.sh`

---

### 2. Skills System

Skills are markdown files with YAML frontmatter that define Claude's behavior for specific tasks.

**Location:** `.claude/skills/*.md`

#### Skill Structure

```markdown
---
name: skill-name
description: |
  Brief description of what this skill does
trigger: |
  AUTOMATICALLY ACTIVATE when user says:
  - "pattern 1"
  - "pattern 2"

  DO NOT activate for:
  - "pattern 3"
---

# Skill Content

Instructions for Claude on how to handle this task...
```

#### Critical YAML Frontmatter Fields

**Required Fields:**
1. `name` - Unique skill identifier (kebab-case)
2. `description` - Clear description (used in skill discovery)
3. `trigger` - When to activate (natural language patterns)

**Example: flow-discover.md**
```yaml
---
name: flow-discover
description: |
  Discover phase workflow - Research and exploration using external CLI providers.
trigger: |
  AUTOMATICALLY ACTIVATE when user requests research or exploration:
  - "research X" or "explore Y" or "investigate Z"
  - "what are the options for X"

  DO NOT activate for:
  - Simple file searches (use Read/Grep tools)
  - Built-in commands (/plugin, /help, etc.)
---
```

#### Workflow Skills

Claude Octopus uses flow-based wrappers for the core Double Diamond phases.

| Skill | File | Triggers | Wrapper For |
|-------|------|----------|-------------|
| Discover | flow-discover.md | "research X" | `orchestrate.sh probe` |
| Define | flow-define.md | "define requirements for X" | `orchestrate.sh grasp` |
| Develop | flow-develop.md | "build X", "implement Y" | `orchestrate.sh tangle` |
| Deliver | flow-deliver.md | "review X", "validate Y" | `orchestrate.sh ink` |

**How they work:**
1. User says natural language trigger (e.g., "research OAuth patterns")
2. Claude Code matches trigger pattern to skill
3. Skill activates and instructs Claude to execute the matching `orchestrate.sh` phase
4. Orchestrate.sh coordinates external CLIs
5. Results are synthesized and returned to chat

---

### 3. Hooks System

Hooks inject additional context or execute commands at specific points in the workflow.

**Location:** `.claude-plugin/hooks.json`

#### Hook Types

| Hook | When It Fires | Purpose |
|------|---------------|---------|
| `PreToolUse` | Before a tool executes | Inject context, validate, warn |
| `PostToolUse` | After a tool completes | Process results, quality gates |
| `SessionStart` | When session begins | Initialize state, sync session |
| `Stop` | When session ends | Cleanup, save state |

#### Visual Indicators Hook

```json
{
  "PreToolUse": [
    {
      "matcher": {
        "tool": "Bash",
        "pattern": "orchestrate\\.sh.*(probe|grasp|tangle|ink)"
      },
      "hooks": [
        {
          "type": "prompt",
          "prompt": "🐙 **CLAUDE OCTOPUS ACTIVATED** - Using external CLI providers"
        }
      ]
    },
    {
      "matcher": {
        "tool": "Bash",
        "pattern": "codex exec"
      },
      "hooks": [
        {
          "type": "prompt",
          "prompt": "🔴 **Codex CLI Executing** - Using your OpenAI API credentials"
        }
      ]
    },
    {
      "matcher": {
        "tool": "Bash",
        "pattern": "gemini -[yr]"
      },
      "hooks": [
        {
          "type": "prompt",
          "prompt": "🟡 **Gemini CLI Executing** - Using your Google API credentials"
        }
      ]
    }
  ]
}
```

**How it works:**
1. User triggers a workflow (e.g., "research X")
2. Skill instructs Claude to run `orchestrate.sh probe "X"`
3. Before Bash tool executes, PreToolUse hook fires
4. Hook matcher checks if command matches `orchestrate\.sh.*probe`
5. If matched, prompt injection adds visual indicator to Claude's context
6. Claude sees: "🐙 **CLAUDE OCTOPUS ACTIVATED**" and outputs it to user
7. Then orchestrate.sh executes normally

---

### 4. Orchestrate.sh (Core Engine)

**Location:** `scripts/orchestrate.sh`

**Purpose:** Bash script that coordinates multiple AI CLI providers.

#### Architecture

```bash
orchestrate.sh
  ├── detect-providers        # Fast provider detection
  ├── probe <prompt>          # Research phase
  ├── grasp <prompt>          # Define phase
  ├── tangle <prompt>         # Develop phase
  ├── ink <prompt>            # Deliver phase
  ├── embrace <prompt>        # Full workflow
  ├── grapple <prompt>        # Adversarial debate
  ├── squeeze <prompt>        # Security review
  ├── auto <prompt>           # Smart routing
  ├── octopus-configure       # Interactive setup
  ├── preflight               # Dependency check
  └── status                  # Provider status
```

#### Workflow Execution Pattern

```bash
#!/bin/bash
# Simplified example of probe workflow

probe() {
  local prompt="$1"
  local session_id="${CLAUDE_CODE_SESSION:-default}"
  local output_dir="${HOME}/.claude-octopus/results/${session_id}"

  # Step 1: Call Codex CLI
  codex exec "${prompt}" > "${output_dir}/probe_codex.md"

  # Step 2: Call Gemini CLI
  gemini -y "${prompt}" > "${output_dir}/probe_gemini.md"

  # Step 3: Claude synthesis (via Task tool)
  # (Claude reads both results and synthesizes)

  # Step 4: Write synthesis
  cat > "${output_dir}/probe-synthesis-$(date +%Y%m%d-%H%M%S).md" <<EOF
# Research Synthesis: ${prompt}

## Codex Perspective
$(cat "${output_dir}/probe_codex.md")

## Gemini Perspective
$(cat "${output_dir}/probe_gemini.md")

## Synthesis
[Claude's integrated analysis]
EOF

  echo "${output_dir}/probe-synthesis-*.md"
}
```

---

### 5. Session Management

#### Session-Aware Storage

Claude Octopus uses `CLAUDE_CODE_SESSION` environment variable to organize results by session:

```
~/.claude-octopus/
├── results/
│   ├── abc-123-session-id/
│   │   ├── probe-synthesis-20260118-143022.md
│   │   ├── tangle-synthesis-20260118-145800.md
│   │   └── ink-validation-20260118-150200.md
│   └── xyz-456-session-id/
│       └── probe-synthesis-20260118-160000.md
└── debates/
    ├── abc-123-session-id/
    │   └── 042-redis-vs-memcached/
    │       ├── context.md
    │       ├── state.json
    │       └── rounds/
    └── xyz-456-session-id/
        └── 043-graphql-vs-rest/
```

**Benefits:**
- Results organized by conversation
- Easy to find specific session outputs
- Automatic cleanup when sessions expire
- No cross-session pollution

#### Session Sync Hook

**Location:** `hooks/session-sync.sh`

**Purpose:** Propagates CLAUDE_CODE_SESSION to orchestrate.sh

```bash
#!/bin/bash
# Simplified session sync hook

if [[ -n "${CLAUDE_CODE_SESSION:-}" ]]; then
  export CLAUDE_CODE_SESSION
  echo "Session ${CLAUDE_CODE_SESSION} synchronized"
fi
```

**Fires on:** `SessionStart` hook

---

### 6. AI Debate Hub

**Location:** `.claude/skills/skill-debate.md` + `.claude/skills/skill-debate-integration.md`

**Origin:** Based on [wolverin0/claude-skills](https://github.com/wolverin0/claude-skills) (MIT License), now fully integrated.

#### Architecture

```
.claude/skills/
├── skill-debate.md                  # Debate skill with YAML frontmatter
└── skill-debate-integration.md      # Enhancement layer (quality gates, cost tracking)
```

---

### 7. Quality Gates

**Location:** `hooks/quality-gate.sh`

**Purpose:** Validate results before proceeding to next phase

#### Quality Dimensions

```bash
evaluate_quality() {
  local file="$1"
  local threshold=75

  # Code Quality (25%)
  code_score=$(check_code_quality "$file")

  # Security (35%)
  security_score=$(check_security "$file")

  # Best Practices (20%)
  practices_score=$(check_best_practices "$file")

  # Completeness (20%)
  completeness_score=$(check_completeness "$file")

  # Calculate weighted score
  total=$((code_score * 25 + security_score * 35 + practices_score * 20 + completeness_score * 20))
  total=$((total / 100))

  if (( total < threshold )); then
    echo "FAILED: Quality score ${total} below threshold ${threshold}"
    return 1
  fi

  echo "PASSED: Quality score ${total}"
  return 0
}
```

**Fires on:** `PostToolUse` hook after tangle phase

---

## Data Flow

### Complete Workflow Example: "Research OAuth Patterns"

```
1. User: "Research OAuth patterns"
   ↓
2. Claude Code: Match trigger patterns in skills
   ↓
3. flow-discover.md: AUTOMATICALLY ACTIVATE
   ↓
4. PreToolUse Hook: Inject "🐙 CLAUDE OCTOPUS ACTIVATED"
   ↓
5. Claude: Output visual indicator to user
   ↓
6. Claude: Execute Bash tool: ./scripts/orchestrate.sh probe "OAuth patterns"
   ↓
7. orchestrate.sh:
   - Detect providers (Codex, Gemini available)
   - Call codex exec "OAuth patterns" → saves to probe_codex.md
   - Call gemini -y "OAuth patterns" → saves to probe_gemini.md
   ↓
8. orchestrate.sh: Write synthesis file with timestamp
   ↓
9. Claude: Read synthesis file
   ↓
10. Claude: Present results to user in chat
```

---

## File Structure

```
claude-octopus/
├── .claude-plugin/
│   ├── plugin.json                 # Plugin manifest
│   ├── marketplace.json            # Marketplace registry
│   └── hooks.json                  # Hook definitions
├── .claude/
│   ├── commands/                   # Slash commands (41)
│   ├── hooks/                      # Hook scripts
│   └── skills/                     # Skill definitions (44)
│       ├── flow-discover.md        # Research workflow
│       ├── flow-define.md          # Define workflow
│       ├── flow-develop.md         # Develop workflow
│       ├── flow-deliver.md         # Deliver workflow
│       ├── skill-debate.md         # Debate skill
│       ├── skill-deep-research.md  # Deep research
│       └── ...                     # 38 more skills
├── agents/
│   └── config.yaml                 # Agent persona definitions
├── scripts/
│   └── orchestrate.sh              # Core orchestration engine
├── tests/
│   ├── unit/                       # Unit tests
│   ├── integration/                # Integration tests
│   └── smoke/                      # Smoke tests
└── docs/                           # Documentation
```

---

## Contributing

### Adding a New Workflow Skill

1. **Create skill file:** `.claude/skills/my-workflow.md`
2. **Add YAML frontmatter:**
   ```yaml
   ---
   name: my-workflow
   description: |
     What this workflow does
   trigger: |
     AUTOMATICALLY ACTIVATE when user says:
     - "trigger pattern 1"
     - "trigger pattern 2"
   ---
   ```
3. **Add skill content:** Instructions for Claude
4. **Register in plugin.json:** Add to `skills` array
5. **Test:** Restart Claude Code and test triggers
6. **Add tests:** Create test suite in `tests/`

### Adding a Visual Indicator

1. **Identify command pattern:** What bash command should trigger indicator?
2. **Add hook to hooks.json:**
   ```json
   {
     "matcher": {
       "tool": "Bash",
       "pattern": "my-command.*"
     },
     "hooks": [
       {
         "type": "prompt",
         "prompt": "🔵 **My Tool Executing** - Description"
       }
     ]
   }
   ```
3. **Test:** Trigger the command and verify indicator appears
4. **Document:** Add to the visual indicators section in `docs/COMMAND-REFERENCE.md`

### Preserving the Command Prefix

Before changing plugin metadata, verify the command prefix stays stable:

```bash
make test-plugin-name
./tests/validate-plugin-name.sh
```

If `.claude-plugin/plugin.json` ever stops using `"name": "octo"`, every `/octo:*` command path becomes a breaking change.

### Adding a Quality Gate

1. **Create gate script:** `hooks/my-quality-gate.sh`
2. **Implement validation logic:**
   ```bash
   #!/bin/bash
   check_quality() {
     # Your validation logic
     # Return 0 for pass, 1 for fail
   }
   ```
3. **Add PostToolUse hook:** Register in hooks.json
4. **Test:** Run workflow and verify gate executes
5. **Document:** Add to quality gates section

---

## Testing

### Test Suite Structure

```
tests/
├── unit/
│   ├── test-skill-frontmatter.sh       # Validate YAML frontmatter
│   ├── test-hook-patterns.sh           # Test hook regex patterns
│   └── test-workflow-routing.sh        # Test auto-routing logic
├── integration/
│   ├── test-debate-integration.sh      # Test debate workflow
│   ├── test-session-sync.sh            # Test session management
│   └── test-quality-gates.sh           # Test quality validation
└── smoke/
    ├── test-plugin-loads.sh            # Verify plugin loads
    ├── test-providers-detect.sh        # Test provider detection
    └── test-basic-workflows.sh         # Smoke test all workflows
```

### Running Tests

```bash
# All tests
make test

# Specific suite
make test-unit
make test-integration
make test-smoke

# Single test
./tests/unit/test-skill-frontmatter.sh
```

---

## Performance Considerations

### Provider Detection Speed

**Goal:** < 1 second for provider detection

**Implementation:**
```bash
# Fast detection (parallel checks)
detect_providers() {
  {
    codex --version &>/dev/null && echo "CODEX=ready" || echo "CODEX=missing"
  } &
  {
    gemini --version &>/dev/null && echo "GEMINI=ready" || echo "GEMINI=missing"
  } &
  wait
}
```

### Session Storage Cleanup

**Goal:** Automatic cleanup of old sessions

**Implementation:**
- Sessions older than 30 days auto-deleted
- Configurable via `~/.claude-octopus/config.json`
- Runs on SessionStart hook

---

## Security

### API Key Handling

- **Never log API keys** to debug output
- **Never commit API keys** to git
- **Use environment variables** for API keys
- **Validate keys** before use

### Hook Execution

- **Sandboxed execution:** Hooks run in restricted environment
- **Input validation:** Sanitize all inputs to hooks
- **Timeout enforcement:** Max 30 seconds per hook

---

## Debugging

### Enable Debug Mode

```bash
export CLAUDE_OCTOPUS_DEBUG=1
./scripts/orchestrate.sh probe "test"
```

### Check Hook Execution

```bash
# View hook logs
tail -f ~/.claude/debug/*.txt | grep -i hook
```

### Validate Skill Frontmatter

```bash
# Run validation test
./tests/unit/test-skill-frontmatter.sh
```

---

## See Also

- **[README](../README.md)** - Main documentation
- **[Command and Usage Reference](./COMMAND-REFERENCE.md)** - Commands, triggers, and provider indicators
- **[CLI Reference](./CLI-REFERENCE.md)** - Direct CLI usage
- **[Documentation Guide](./README.md)** - Docs landing page
- **[CONTRIBUTING.md](../CONTRIBUTING.md)** - Contribution guidelines
