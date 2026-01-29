---
name: octopus-state-manager
description: Manage persistent state across sessions for Claude Octopus workflows
triggers:
  - "state"
  - "session"
  - "persistence"
aliases:
  - state
  - session-state
dependencies:
  - "${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh"
---

# State Manager - Session Persistence for Claude Octopus

Provides persistent state tracking across sessions, context resets, and workflow phases.

## Purpose

The state manager enables:
- **Session Resumption**: Continue work after context resets
- **Decision Tracking**: Record and retrieve architectural decisions
- **Blocker Management**: Track impediments across phases
- **Context Preservation**: Pass information between workflow phases
- **Metrics Collection**: Measure execution time and provider usage

## State File Structure

State is stored in `.claude-octopus/state.json`:

```json
{
  "version": "1.0.0",
  "project_id": "unique-hash",
  "current_workflow": "flow-develop",
  "current_phase": "develop",
  "session_start": "2026-01-28T14:30:00Z",
  "decisions": [
    {
      "phase": "define",
      "decision": "React 19 + Next.js 15",
      "rationale": "Modern stack with best DX",
      "date": "2026-01-28",
      "commit": "abc123f"
    }
  ],
  "blockers": [
    {
      "description": "Waiting for API endpoint",
      "phase": "develop",
      "status": "active",
      "created": "2026-01-28"
    }
  ],
  "context": {
    "discover": "researched auth patterns, chose JWT",
    "define": "user wants passwordless magic links",
    "develop": "implementing backend API first",
    "deliver": null
  },
  "metrics": {
    "phases_completed": 2,
    "total_execution_time_minutes": 45,
    "provider_usage": {
      "codex": 12,
      "gemini": 10,
      "claude": 25
    }
  }
}
```

## When to Use

### Use State Manager When:
- ✅ Starting a new workflow (initialize state)
- ✅ Completing a workflow phase (update metrics, context)
- ✅ Making architectural decisions (record decision)
- ✅ Encountering blockers (track impediments)
- ✅ Resuming after context reset (read prior state)
- ✅ Switching between workflows (set current workflow)

### Don't Use State Manager For:
- ❌ Storing code or large content (use files instead)
- ❌ Temporary values within a single session
- ❌ Data that belongs in git commits

## Usage Patterns

### 1. Initialize State (Start of Session)

Before running any workflow:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" init_state
```

This creates:
- `.claude-octopus/state.json` (state file)
- `.claude-octopus/context/` (phase context files)
- `.claude-octopus/summaries/` (execution summaries)
- `.claude-octopus/quick/` (quick mode outputs)

**Safe to run multiple times** - validates existing state or recreates if corrupted.

### 2. Read State (Pre-Execution)

Before executing a workflow phase, read prior state to understand context:

```bash
# Get full state
state=$("${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" read_state)

# Extract specific information
current_phase=$(echo "$state" | jq -r '.current_phase')
decisions=$(echo "$state" | jq -r '.decisions')
discover_context=$(echo "$state" | jq -r '.context.discover')

# Use this information to scope your work
echo "Previous phase: $current_phase"
echo "Decisions made: $decisions"
echo "Discovery findings: $discover_context"
```

### 3. Record Decision (During Execution)

When making architectural or implementation decisions:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" write_decision \
  "define" \
  "Use React 19 with Next.js 15 and TypeScript" \
  "Modern stack with best developer experience, Server Components support"
```

**When to Record Decisions:**
- Technology stack choices
- Architectural patterns selected
- Implementation approach
- Design decisions
- Security choices

**When NOT to Record:**
- Implementation details (those go in code)
- Temporary choices
- Obvious defaults

### 4. Update Context (Post-Execution)

After completing a workflow phase, summarize findings:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_context \
  "discover" \
  "Researched authentication patterns: JWT vs session-based. Community prefers JWT for API-first apps. Found 3 battle-tested libraries: jose, jsonwebtoken, auth0. Chose jose for ESM support."
```

**Context Guidelines:**
- **Be concise** (1-3 sentences max)
- **Focus on outcomes**, not process
- **Highlight key findings** that inform next phases
- **Include rationale** for choices

### 5. Track Blockers (As Needed)

When encountering impediments:

```bash
# Record new blocker
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" write_blocker \
  "Waiting for API endpoint /auth/login to be deployed" \
  "develop" \
  "active"

# Update blocker when resolved
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_blocker_status \
  "Waiting for API endpoint /auth/login to be deployed" \
  "resolved"
```

### 6. Update Metrics (Post-Execution)

After executing workflow phases:

```bash
# Increment phase completion counter
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics \
  "phases_completed" \
  "1"

# Track execution time (in minutes)
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics \
  "execution_time" \
  "15"

# Track provider usage
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics \
  "provider" \
  "gemini"
```

### 7. Set Current Workflow (Workflow Start)

At the beginning of each workflow:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" set_current_workflow \
  "flow-develop" \
  "develop"
```

### 8. Display Summary (Debug/Status Check)

To see current state at a glance:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" show_summary
```

Output:
```
=== Claude Octopus State Summary ===

Project ID: a3f2c8b9e1d4f7a6
Session Start: 2026-01-28T14:30:00Z
Current Workflow: flow-develop
Current Phase: develop

Metrics:
  Phases Completed: 2
  Execution Time: 45 minutes
  Provider Usage:
    - Codex: 12
    - Gemini: 10
    - Claude: 25

Decisions: 3
Active Blockers: 1
```

## Integration with Workflows

All Double Diamond flows should integrate state management:

### Pre-Execution (Read State)

```bash
# Initialize if needed
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" init_state

# Set current workflow
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" set_current_workflow \
  "flow-define" \
  "define"

# Read prior context
discover_findings=$("${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get_context "discover")

if [ "$discover_findings" != "null" ]; then
  echo "Building on discovery phase findings:"
  echo "$discover_findings"
fi

# Get prior decisions
decisions=$("${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get_decisions "all")
if [ "$decisions" != "[]" ]; then
  echo "Respecting prior decisions:"
  echo "$decisions" | jq -r '.[] | "- \(.decision) (\(.phase))"'
fi
```

### Post-Execution (Write State)

```bash
# Record key decision made during this phase
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" write_decision \
  "$phase_name" \
  "$decision_summary" \
  "$rationale"

# Update context for next phase
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_context \
  "$phase_name" \
  "$key_findings_summary"

# Update metrics
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics \
  "phases_completed" \
  "1"

# Track execution time
execution_time=$((end_time - start_time))
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_metrics \
  "execution_time" \
  "$execution_time"
```

## Error Handling

The state manager includes built-in safety:

### Atomic Writes
- Uses temp file + atomic move to prevent corruption
- Validates JSON before committing
- Backs up state before each write

### Validation
- Checks JSON validity on every read
- Detects corrupted files and recreates
- Graceful degradation if state missing

### Recovery
- Backup saved to `.claude-octopus/state.json.backup`
- Corrupted files moved to `.claude-octopus/state.json.corrupt.<timestamp>`
- Can reinitialize at any time

## Best Practices

### DO:
- ✅ Initialize state at the start of each session
- ✅ Read state before executing workflows
- ✅ Record decisions with clear rationale
- ✅ Update context after each phase
- ✅ Track meaningful metrics
- ✅ Commit state file to git for persistence

### DON'T:
- ❌ Store large content in state (use files)
- ❌ Record every minor decision
- ❌ Skip state initialization
- ❌ Manually edit state.json (use CLI)
- ❌ Store sensitive data in state

## Debugging

### Check if state exists:
```bash
if [ -f .claude-octopus/state.json ]; then
  echo "State file exists"
else
  echo "State file missing - run init_state"
fi
```

### Validate state JSON:
```bash
if jq empty .claude-octopus/state.json 2>/dev/null; then
  echo "State file is valid JSON"
else
  echo "State file is corrupted"
fi
```

### View raw state:
```bash
cat .claude-octopus/state.json | jq .
```

### Reset state:
```bash
rm -rf .claude-octopus
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" init_state
```

## Examples

### Example 1: Starting a New Feature

```bash
# Initialize state
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" init_state

# Run discovery
# ... discovery workflow executes ...

# Record findings
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_context \
  "discover" \
  "Found 3 auth patterns. JWT preferred for API-first architecture."

# Run definition
# ... definition workflow executes ...

# Record decision
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" write_decision \
  "define" \
  "JWT authentication with jose library" \
  "ESM support, actively maintained, follows standards"

# Update context
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_context \
  "define" \
  "Spec: Passwordless magic links, 15min token expiry, refresh tokens"
```

### Example 2: Resuming After Context Reset

```bash
# Read prior state
state=$("${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" read_state)

# Extract context
echo "$state" | jq -r '.context'
# Output:
# {
#   "discover": "Found 3 auth patterns. JWT preferred...",
#   "define": "Spec: Passwordless magic links...",
#   "develop": null,
#   "deliver": null
# }

# Extract decisions
echo "$state" | jq -r '.decisions'
# Output: Array of decision objects

# Continue from where you left off
current_phase=$(echo "$state" | jq -r '.current_phase')
echo "Resuming from phase: $current_phase"
```

### Example 3: Tracking Blockers

```bash
# Hit a blocker during development
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" write_blocker \
  "Need production API keys for auth provider" \
  "develop" \
  "active"

# Later, when unblocked
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" update_blocker_status \
  "Need production API keys for auth provider" \
  "resolved"

# Check active blockers
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" get_active_blockers
```

## File Structure

State management creates this directory structure:

```
.claude-octopus/
├── state.json                    # Main state file
├── state.json.backup             # Backup before last write
├── context/                      # Phase context files
│   ├── discover-context.md
│   ├── define-context.md
│   ├── develop-context.md
│   └── deliver-context.md
├── summaries/                    # Execution summaries
│   └── flow-develop-20260128-summary.md
└── quick/                        # Quick mode outputs
    └── 20260128-143045-summary.md
```

## API Reference

See `state-manager.sh help` for full command reference.

### Core Commands

| Command | Description | Example |
|---------|-------------|---------|
| `init_state` | Initialize state file | `state-manager.sh init_state` |
| `read_state` | Get full state as JSON | `state-manager.sh read_state` |
| `write_decision` | Record a decision | `state-manager.sh write_decision "define" "React 19" "Modern DX"` |
| `update_context` | Update phase context | `state-manager.sh update_context "discover" "Found X"` |
| `update_metrics` | Update metrics | `state-manager.sh update_metrics "provider" "gemini"` |
| `show_summary` | Display state summary | `state-manager.sh show_summary` |

## Troubleshooting

### State file corrupted
```bash
# State manager auto-recovers, but you can manually restore:
cp .claude-octopus/state.json.backup .claude-octopus/state.json
```

### State file missing
```bash
# Reinitialize (safe operation):
"${CLAUDE_PLUGIN_ROOT}/scripts/state-manager.sh" init_state
```

### Invalid JSON in state
```bash
# Check validity:
jq empty .claude-octopus/state.json

# If invalid, look for backups:
ls -la .claude-octopus/*.backup .claude-octopus/*.corrupt.*
```

## Conclusion

The state manager enables session persistence, decision tracking, and context preservation across Claude Octopus workflows. Integrate it into all flows to provide continuity across context resets and improve workflow efficiency.
