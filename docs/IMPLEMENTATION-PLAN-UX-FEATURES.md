# Implementation Plan: HIGH PRIORITY UX Features

**Version:** 7.15.0+
**Date:** 2026-01-28
**Status:** Ready for Implementation

---

## Executive Summary

This document provides a step-by-step implementation guide for three HIGH PRIORITY UX features that will significantly improve user experience during multi-AI orchestration workflows:

1. **Enhanced Customizable Spinner Verbs** - Dynamic, context-aware progress indicators
2. **Enhanced Progress Indicators** - Real-time provider status with estimated timing
3. **Timeout Visibility** - Clear timeout warnings and progress tracking

**Impact:**
- **User clarity**: Know exactly what's happening at each moment
- **Cost awareness**: See which providers are running and for how long
- **Anxiety reduction**: Clear timing expectations reduce "is this stuck?" concerns
- **Trust building**: Transparent progress creates confidence in the system

**Effort:** Medium (2-3 days implementation, 1 day testing)
**Risk:** Low (additive features, no breaking changes)

---

## Feature 1: Enhanced Customizable Spinner Verbs

### Problem Statement

Current state:
```
TaskCreate({
  subject: "Discover Phase - Multi-AI Research",
  activeForm: "Running multi-AI discover workflow"
})
```

**Issues:**
- Generic "Running multi-AI" doesn't tell user what's happening
- Same verb for all phases (discover, define, develop, deliver)
- No indication of which provider is active
- Missing context about current operation

**Desired state:**
```
🔍 Researching OAuth patterns (Codex)...
🔍 Exploring authentication options (Gemini)...
🔵 Synthesizing research findings...
```

### Solution Design

#### Concept: Multi-Stage Spinner Updates

Each orchestrate.sh workflow has multiple stages:
1. **Provider execution** (Codex, Gemini) - parallel
2. **Synthesis** (Claude) - sequential
3. **Validation gates** - sequential

We update the TaskUpdate activeForm as each stage progresses.

#### File Changes Required

**File 1: `/Users/chris/git/claude-octopus/plugin/scripts/orchestrate.sh`**

**Location:** Lines ~6497-6520 (agent execution section)

**Current code:**
```bash
if run_with_timeout "$TIMEOUT" "${cmd_array[@]}" "$enhanced_prompt" > "$temp_output" 2> "$temp_errors"; then
    success=true
    log INFO "Agent $agent_name completed successfully"
```

**New code:**
```bash
# Before execution: Update task with provider-specific verb
if [[ -n "$CLAUDE_TASK_ID" ]]; then
    local activeForm=""
    case "$workflow_phase" in
        probe|discover)
            case "$agent_name" in
                codex*) activeForm="🔴 Researching technical patterns (Codex)" ;;
                gemini*) activeForm="🟡 Exploring ecosystem and options (Gemini)" ;;
                claude*) activeForm="🔵 Synthesizing research findings" ;;
            esac
            ;;
        grasp|define)
            case "$agent_name" in
                codex*) activeForm="🔴 Analyzing technical requirements (Codex)" ;;
                gemini*) activeForm="🟡 Clarifying scope and constraints (Gemini)" ;;
                claude*) activeForm="🔵 Building consensus on approach" ;;
            esac
            ;;
        tangle|develop)
            case "$agent_name" in
                codex*) activeForm="🔴 Generating implementation code (Codex)" ;;
                gemini*) activeForm="🟡 Exploring alternative approaches (Gemini)" ;;
                claude*) activeForm="🔵 Integrating solutions with quality gates" ;;
            esac
            ;;
        ink|deliver)
            case "$agent_name" in
                codex*) activeForm="🔴 Analyzing code quality (Codex)" ;;
                gemini*) activeForm="🟡 Auditing security and edge cases (Gemini)" ;;
                claude*) activeForm="🔵 Validating and certifying delivery" ;;
            esac
            ;;
    esac

    # Update task via CLAUDE_CODE_CONTROL
    echo "TASK_UPDATE:${CLAUDE_TASK_ID}:activeForm:${activeForm}" >> "$CLAUDE_CODE_CONTROL" 2>/dev/null || true
fi

# Execute agent
if run_with_timeout "$TIMEOUT" "${cmd_array[@]}" "$enhanced_prompt" > "$temp_output" 2> "$temp_errors"; then
    success=true
    log INFO "Agent $agent_name completed successfully"
```

**File 2: `/Users/chris/git/claude-octopus/plugin/.claude/skills/flow-discover.md`**

**Location:** Lines 344-354 (task management section)

**Current code:**
```markdown
TaskCreate({
  subject: "Discover Phase - Multi-AI Research",
  description: "Run multi-provider research using Codex, Gemini, and Claude",
  activeForm: "Running multi-AI discover workflow"
})

TaskUpdate({taskId: "...", status: "in_progress"})

TaskUpdate({taskId: "...", status: "completed"})
```

**New code:**
```markdown
TaskCreate({
  subject: "Discover Phase - Multi-AI Research",
  description: "Run multi-provider research using Codex, Gemini, and Claude",
  activeForm: "Initializing multi-AI research workflow"
})

// orchestrate.sh will update activeForm automatically:
// 🔴 Researching technical patterns (Codex)
// 🟡 Exploring ecosystem and options (Gemini)
// 🔵 Synthesizing research findings

TaskUpdate({taskId: "...", status: "in_progress"})

TaskUpdate({taskId: "...", status: "completed"})
```

**File 3-6: Update other workflow skills similarly**

- `/Users/chris/git/claude-octopus/plugin/.claude/skills/flow-define.md`
- `/Users/chris/git/claude-octopus/plugin/.claude/skills/flow-develop.md`
- `/Users/chris/git/claude-octopus/plugin/.claude/skills/flow-deliver.md`

### Implementation Steps

#### Step 1: Add Task Update Helper Function
```bash
# File: /Users/chris/git/claude-octopus/plugin/scripts/orchestrate.sh
# Insert after line 565 (generate_usage_table function)

# Update Claude Code task progress
update_task_progress() {
    local task_id="$1"
    local active_form="$2"

    if [[ -z "$task_id" || -z "$CLAUDE_CODE_CONTROL" ]]; then
        return 0
    fi

    # Write to control pipe for Claude Code to update spinner
    echo "TASK_UPDATE:${task_id}:activeForm:${active_form}" >> "$CLAUDE_CODE_CONTROL" 2>/dev/null || true
    log DEBUG "Updated task $task_id: $active_form"
}
```

#### Step 2: Get Task ID from Environment
```bash
# File: /Users/chris/git/claude-octopus/plugin/scripts/orchestrate.sh
# Add after line 63 (WORKSPACE_DIR validation)

# Get Claude Code task ID if available (v2.1.16+)
CLAUDE_TASK_ID="${CLAUDE_CODE_TASK_ID:-}"
CLAUDE_CODE_CONTROL="${CLAUDE_CODE_CONTROL_PIPE:-}"
```

#### Step 3: Define Verb Mapping Function
```bash
# File: /Users/chris/git/claude-octopus/plugin/scripts/orchestrate.sh
# Insert after update_task_progress function

# Get activeForm verb for agent + phase combination
get_active_form_verb() {
    local phase="$1"
    local agent="$2"
    local prompt_context="$3"  # Optional: for even more specific verbs

    # Normalize phase name
    case "$phase" in
        probe) phase="discover" ;;
        grasp) phase="define" ;;
        tangle) phase="develop" ;;
        ink) phase="deliver" ;;
    esac

    # Normalize agent name
    local agent_type="${agent%%:*}"
    agent_type="${agent_type%%-*}"  # codex-max -> codex

    # Generate verb based on phase + agent
    local verb=""
    case "$phase:$agent_type" in
        discover:codex)  verb="🔴 Researching technical patterns (Codex)" ;;
        discover:gemini) verb="🟡 Exploring ecosystem and options (Gemini)" ;;
        discover:claude) verb="🔵 Synthesizing research findings" ;;

        define:codex)    verb="🔴 Analyzing technical requirements (Codex)" ;;
        define:gemini)   verb="🟡 Clarifying scope and constraints (Gemini)" ;;
        define:claude)   verb="🔵 Building consensus on approach" ;;

        develop:codex)   verb="🔴 Generating implementation code (Codex)" ;;
        develop:gemini)  verb="🟡 Exploring alternative approaches (Gemini)" ;;
        develop:claude)  verb="🔵 Integrating solutions with quality gates" ;;

        deliver:codex)   verb="🔴 Analyzing code quality (Codex)" ;;
        deliver:gemini)  verb="🟡 Auditing security and edge cases (Gemini)" ;;
        deliver:claude)  verb="🔵 Validating and certifying delivery" ;;

        *) verb="Processing with $agent" ;;
    esac

    echo "$verb"
}
```

#### Step 4: Integrate into Agent Execution Loop
```bash
# File: /Users/chris/git/claude-octopus/plugin/scripts/orchestrate.sh
# Find: run_agent_task function (around line 6400)
# Modify agent execution to update progress before running

# Inside run_agent_task, before agent execution:
local active_form
active_form=$(get_active_form_verb "$workflow_phase" "$agent_name" "$prompt")
update_task_progress "$CLAUDE_TASK_ID" "$active_form"

# Then execute agent as normal
if run_with_timeout "$TIMEOUT" "${cmd_array[@]}" "$enhanced_prompt" > "$temp_output" 2> "$temp_errors"; then
    # ... existing code
fi
```

#### Step 5: Update Workflow Skill Documentation

For each workflow skill, update the task management section to document the dynamic activeForm behavior.

**Template:**
```markdown
### Task Management Integration

This workflow creates a task with dynamic progress indicators:

**Initial state:**
```
TaskCreate({
  subject: "[Phase] - Multi-AI [Operation]",
  activeForm: "Initializing multi-AI [phase] workflow"
})
```

**Progress updates (automatic via orchestrate.sh):**
- 🔴 [Codex-specific verb]
- 🟡 [Gemini-specific verb]
- 🔵 [Claude-specific verb]

**Final state:**
```
TaskUpdate({taskId: "...", status: "completed"})
```
```

### Testing Strategy

#### Test Case 1: Single Phase Workflow
```bash
# Create test script
cat > /tmp/test-spinner-verbs.sh << 'EOF'
#!/bin/bash
export CLAUDE_CODE_TASK_ID="test-task-123"
export CLAUDE_CODE_CONTROL_PIPE="/tmp/task-control.pipe"
mkfifo "$CLAUDE_CODE_CONTROL_PIPE" 2>/dev/null || true

# Monitor control pipe in background
tail -f "$CLAUDE_CODE_CONTROL_PIPE" &
TAIL_PID=$!

# Run workflow
cd /Users/chris/git/claude-octopus/plugin
./scripts/orchestrate.sh probe "What are OAuth best practices?"

# Cleanup
kill $TAIL_PID 2>/dev/null
rm "$CLAUDE_CODE_CONTROL_PIPE"
EOF

chmod +x /tmp/test-spinner-verbs.sh
/tmp/test-spinner-verbs.sh
```

**Expected output:**
```
TASK_UPDATE:test-task-123:activeForm:🔴 Researching technical patterns (Codex)
TASK_UPDATE:test-task-123:activeForm:🟡 Exploring ecosystem and options (Gemini)
TASK_UPDATE:test-task-123:activeForm:🔵 Synthesizing research findings
```

#### Test Case 2: Full Embrace Workflow
```bash
export CLAUDE_CODE_TASK_ID="test-embrace-456"
./scripts/orchestrate.sh embrace "Build user authentication system"
```

**Expected:** See all 4 phases with 3 provider updates each (12 total updates)

#### Test Case 3: Provider Unavailable
```bash
# Rename codex temporarily
sudo mv /usr/local/bin/codex /usr/local/bin/codex.bak

export CLAUDE_CODE_TASK_ID="test-missing-789"
./scripts/orchestrate.sh probe "Research GraphQL"

# Restore
sudo mv /usr/local/bin/codex.bak /usr/local/bin/codex
```

**Expected:** Only see 🟡 and 🔵 updates, skip 🔴

### Rollout Plan

#### Phase 1: Implementation (Day 1)
- [ ] Add helper functions to orchestrate.sh
- [ ] Implement get_active_form_verb with all phase/agent combinations
- [ ] Integrate update_task_progress into agent execution loop
- [ ] Test manually with control pipe monitoring

#### Phase 2: Skill Updates (Day 2)
- [ ] Update flow-discover.md documentation
- [ ] Update flow-define.md documentation
- [ ] Update flow-develop.md documentation
- [ ] Update flow-deliver.md documentation
- [ ] Update skill-deep-research.md documentation

#### Phase 3: Testing (Day 2-3)
- [ ] Run all test cases above
- [ ] Verify in actual Claude Code session
- [ ] Check that spinners update smoothly
- [ ] Validate no errors in logs

#### Phase 4: Release (Day 3)
- [ ] Update CHANGELOG.md with new feature
- [ ] Bump version to 7.15.0
- [ ] Create release notes highlighting spinner improvements
- [ ] Deploy to registry

### Documentation Updates

**File 1: `/Users/chris/git/claude-octopus/plugin/docs/VISUAL-INDICATORS.md`**

Add section:
```markdown
## Dynamic Progress Spinners (v7.15.0+)

When running multi-AI workflows, the progress spinner shows exactly which provider
is executing and what operation they're performing:

**Discover Phase:**
- 🔴 Researching technical patterns (Codex)
- 🟡 Exploring ecosystem and options (Gemini)
- 🔵 Synthesizing research findings

**Define Phase:**
- 🔴 Analyzing technical requirements (Codex)
- 🟡 Clarifying scope and constraints (Gemini)
- 🔵 Building consensus on approach

[... etc for all phases]
```

**File 2: `/Users/chris/git/claude-octopus/plugin/CHANGELOG.md`**

```markdown
## [7.15.0] - 2026-01-XX

### Added
- **Enhanced Customizable Spinner Verbs**: Dynamic progress indicators show exactly
  which AI provider is running and what operation they're performing in real-time
- Task progress updates automatically via CLAUDE_CODE_CONTROL_PIPE integration
- Phase-specific and provider-specific activeForm verbs for all workflows
```

---

## Feature 2: Enhanced Progress Indicators

### Problem Statement

Current state:
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 Discover Phase: Researching OAuth patterns

Providers:
🔴 Codex CLI: Available ✓
🟡 Gemini CLI: Available ✓
🔵 Claude: Available ✓

💰 Estimated Cost: $0.01-0.05
⏱️  Estimated Time: 2-5 minutes
```

**Issues:**
- No real-time status updates during execution
- Can't see which provider is currently active vs. waiting
- No indication of progress through provider queue
- Users left wondering "is it stuck?" during long operations

**Desired state:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 Discover Phase: Researching OAuth patterns

Provider Status:
🔴 Codex CLI: ✅ Completed (23s) - $0.02
🟡 Gemini CLI: ⏳ Running... (11s elapsed)
🔵 Claude: ⏸️  Waiting

💰 Cost So Far: $0.02 (est. total: $0.04)
⏱️  Time: 34s elapsed (est. total: 2-3 min)
```

### Solution Design

#### Concept: Live Status Board

Create a status file that orchestrate.sh updates in real-time, which Claude monitors and displays to the user.

#### Architecture

```
orchestrate.sh
    ↓ writes status
${WORKSPACE_DIR}/status-${SESSION_ID}.json
    ↓ reads via hook
Claude (PreToolUse hook)
    ↓ displays
User sees live updates
```

#### File Changes Required

**File 1: `/Users/chris/git/claude-octopus/plugin/scripts/orchestrate.sh`**

**Location:** After line 565 (usage tracking section)

**New code:**
```bash
# ═══════════════════════════════════════════════════════════════════════════════
# LIVE PROGRESS TRACKING (v7.15.0+)
# Provides real-time status updates for multi-provider workflows
# ═══════════════════════════════════════════════════════════════════════════════

# Progress status file
PROGRESS_FILE="${WORKSPACE_DIR}/progress-${CLAUDE_CODE_SESSION:-session}.json"

# Initialize progress tracking
init_progress_tracking() {
    local phase="$1"
    local total_agents="$2"

    cat > "$PROGRESS_FILE" << EOF
{
  "session_id": "${CLAUDE_CODE_SESSION:-session}",
  "phase": "$phase",
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "total_agents": $total_agents,
  "completed_agents": 0,
  "total_cost": 0.0,
  "total_time_ms": 0,
  "agents": []
}
EOF

    log DEBUG "Progress tracking initialized for phase: $phase"
}

# Update agent status
update_agent_status() {
    local agent_name="$1"
    local status="$2"  # waiting, running, completed, failed
    local elapsed_ms="${3:-0}"
    local cost="${4:-0.0}"

    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 0
    fi

    # Create agent status record
    local agent_record
    agent_record=$(cat << EOF
{
  "name": "$agent_name",
  "status": "$status",
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "elapsed_ms": $elapsed_ms,
  "cost": $cost
}
EOF
)

    # Append to agents array using jq
    local tmp_file="${PROGRESS_FILE}.tmp"
    jq --argjson agent "$agent_record" \
        '.agents += [$agent]' \
        "$PROGRESS_FILE" > "$tmp_file" && mv "$tmp_file" "$PROGRESS_FILE"

    # Update totals if completed
    if [[ "$status" == "completed" ]]; then
        jq --argjson elapsed "$elapsed_ms" \
           --argjson cost "$cost" \
           '.completed_agents += 1 | .total_time_ms += $elapsed | .total_cost += $cost' \
           "$PROGRESS_FILE" > "$tmp_file" && mv "$tmp_file" "$PROGRESS_FILE"
    fi

    log DEBUG "Updated agent status: $agent_name -> $status"
}

# Get current progress summary
get_progress_summary() {
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        echo "No progress data available"
        return 1
    fi

    jq -r '
        "Phase: \(.phase)",
        "Completed: \(.completed_agents)/\(.total_agents)",
        "Total Cost: $\(.total_cost)",
        "Total Time: \(.total_time_ms / 1000)s",
        "",
        "Agent Status:",
        (.agents[] | "  \(.name): \(.status) (\(.elapsed_ms / 1000)s, $\(.cost))")
    ' "$PROGRESS_FILE"
}

# Format progress for display
format_progress_display() {
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 0
    fi

    local phase completed total total_cost total_time
    phase=$(jq -r '.phase' "$PROGRESS_FILE")
    completed=$(jq -r '.completed_agents' "$PROGRESS_FILE")
    total=$(jq -r '.total_agents' "$PROGRESS_FILE")
    total_cost=$(jq -r '.total_cost' "$PROGRESS_FILE")
    total_time=$(jq -r '.total_time_ms / 1000' "$PROGRESS_FILE")

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🐙 LIVE PROGRESS: $phase Phase"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Provider Status:"

    # Read agents and format status
    jq -r '.agents[] |
        if .status == "completed" then
            "✅ \(.name): Completed (\(.elapsed_ms / 1000)s) - $\(.cost)"
        elif .status == "running" then
            "⏳ \(.name): Running... (\(.elapsed_ms / 1000)s elapsed)"
        elif .status == "failed" then
            "❌ \(.name): Failed"
        else
            "⏸️  \(.name): Waiting"
        end
    ' "$PROGRESS_FILE" | sed 's/codex/🔴 Codex CLI/; s/gemini/🟡 Gemini CLI/; s/claude/🔵 Claude/'

    echo ""
    echo "Progress: $completed/$total providers"
    echo "💰 Cost So Far: \$$total_cost"
    echo "⏱️  Time: ${total_time}s elapsed"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}
```

**File 2: `/Users/chris/git/claude-octopus/plugin/.claude/hooks/visual-feedback.sh`**

**Location:** Create new hook file

**New file content:**
```bash
#!/usr/bin/env bash
# Visual Feedback Hook - Live Progress Updates
# Triggered periodically during orchestrate.sh execution

set -eo pipefail

WORKSPACE_DIR="${HOME}/.claude-octopus"
PROGRESS_FILE="${WORKSPACE_DIR}/progress-${CLAUDE_CODE_SESSION:-session}.json"

# Only run if progress file exists and is recent (< 5 min old)
if [[ ! -f "$PROGRESS_FILE" ]]; then
    exit 0
fi

# Check file age
if [[ "$(uname)" == "Darwin" ]]; then
    file_age=$(($(date +%s) - $(stat -f %m "$PROGRESS_FILE")))
else
    file_age=$(($(date +%s) - $(stat -c %Y "$PROGRESS_FILE")))
fi

if [[ $file_age -gt 300 ]]; then
    # File older than 5 minutes, ignore
    exit 0
fi

# Format and display progress
if command -v jq &>/dev/null; then
    phase=$(jq -r '.phase' "$PROGRESS_FILE" 2>/dev/null || echo "unknown")
    completed=$(jq -r '.completed_agents' "$PROGRESS_FILE" 2>/dev/null || echo "0")
    total=$(jq -r '.total_agents' "$PROGRESS_FILE" 2>/dev/null || echo "0")

    if [[ "$completed" != "$total" ]]; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🐙 LIVE PROGRESS: $phase Phase ($completed/$total providers)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # Show agent statuses
        jq -r '.agents[] |
            if .status == "completed" then
                "✅ \(.name): Completed (\(.elapsed_ms / 1000)s) - $\(.cost)"
            elif .status == "running" then
                "⏳ \(.name): Running... (\(.elapsed_ms / 1000)s elapsed)"
            elif .status == "failed" then
                "❌ \(.name): Failed"
            else
                "⏸️  \(.name): Waiting"
            end
        ' "$PROGRESS_FILE" 2>/dev/null | sed 's/codex/🔴 Codex CLI/; s/gemini/🟡 Gemini CLI/; s/claude/🔵 Claude/'

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
fi

exit 0
```

**File 3: `/Users/chris/git/claude-octopus/plugin/.claude-plugin/hooks.json`**

**Modification:** Add periodic progress check

```json
{
  "PreToolUse": [
    {
      "matcher": {
        "tool": "Bash",
        "pattern": "orchestrate\\.sh.*(probe|grasp|tangle|ink|embrace)"
      },
      "hooks": [
        {
          "type": "script",
          "script": "${CLAUDE_PLUGIN_ROOT}/.claude/hooks/visual-feedback.sh"
        }
      ]
    }
  ],
  "Notification": [
    {
      "matcher": {
        "pattern": ".*"
      },
      "hooks": [
        {
          "type": "script",
          "script": "${CLAUDE_PLUGIN_ROOT}/.claude/hooks/visual-feedback.sh",
          "interval": 10000
        }
      ]
    }
  ]
}
```

### Implementation Steps

#### Step 1: Add Progress Tracking Functions
Copy the progress tracking functions into orchestrate.sh after the usage tracking section.

#### Step 2: Initialize Progress on Workflow Start
```bash
# File: orchestrate.sh
# In main workflow execution function (around line 8000)

# After argument parsing, before agent execution:
init_progress_tracking "$workflow_phase" "$total_agents"

# Mark all agents as "waiting" initially
for agent in "${agent_list[@]}"; do
    update_agent_status "$agent" "waiting" 0 0.0
done
```

#### Step 3: Update Status During Execution
```bash
# File: orchestrate.sh
# In agent execution loop (around line 6500)

# Before running agent
local start_time=$(date +%s%3N)
update_agent_status "$agent_name" "running" 0 0.0

# Run agent
if run_with_timeout "$TIMEOUT" "${cmd_array[@]}" "$enhanced_prompt" > "$temp_output" 2> "$temp_errors"; then
    local end_time=$(date +%s%3N)
    local elapsed_ms=$((end_time - start_time))
    local cost=$(calculate_cost_for_agent "$agent_name" "$prompt")

    update_agent_status "$agent_name" "completed" "$elapsed_ms" "$cost"
else
    update_agent_status "$agent_name" "failed" "$elapsed_ms" 0.0
fi
```

#### Step 4: Create Visual Feedback Hook
Create the hook script at `.claude/hooks/visual-feedback.sh` with executable permissions:

```bash
chmod +x /Users/chris/git/claude-octopus/plugin/.claude/hooks/visual-feedback.sh
```

#### Step 5: Update hooks.json
Add the Notification hook for periodic progress updates.

### Testing Strategy

#### Test Case 1: Monitor Progress File
```bash
# Terminal 1: Watch progress file
watch -n 1 'cat ~/.claude-octopus/progress-*.json | jq .'

# Terminal 2: Run workflow
cd /Users/chris/git/claude-octopus/plugin
./scripts/orchestrate.sh probe "What are GraphQL best practices?"
```

**Expected:** See JSON update in real-time as each provider starts/completes.

#### Test Case 2: Verify Hook Integration
```bash
# In Claude Code session
/octo:research "OAuth authentication patterns"
```

**Expected:** See live progress updates every 10 seconds showing which provider is running.

#### Test Case 3: Multi-Agent Parallel
```bash
./scripts/orchestrate.sh probe "Compare REST vs GraphQL" --parallel
```

**Expected:** See multiple agents in "running" state simultaneously.

### Rollout Plan

#### Phase 1: Core Implementation (Day 1)
- [ ] Add progress tracking functions to orchestrate.sh
- [ ] Implement init_progress_tracking
- [ ] Implement update_agent_status
- [ ] Integrate into agent execution loop
- [ ] Test with progress file monitoring

#### Phase 2: Hook Integration (Day 2)
- [ ] Create visual-feedback.sh hook script
- [ ] Update hooks.json with Notification hook
- [ ] Test hook triggers correctly
- [ ] Verify formatting looks clean

#### Phase 3: Refinement (Day 2-3)
- [ ] Add cost calculation per agent
- [ ] Add elapsed time formatting
- [ ] Add progress bar visual
- [ ] Test with all workflow types

#### Phase 4: Release (Day 3)
- [ ] Document in VISUAL-INDICATORS.md
- [ ] Update CHANGELOG
- [ ] Bump version
- [ ] Deploy

### Documentation Updates

**File: `/Users/chris/git/claude-octopus/plugin/docs/VISUAL-INDICATORS.md`**

Add section:
```markdown
## Live Progress Tracking (v7.15.0+)

During multi-provider workflows, you'll see real-time status updates:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🐙 LIVE PROGRESS: Discover Phase (2/3 providers)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Provider Status:
✅ 🔴 Codex CLI: Completed (23s) - $0.02
⏳ 🟡 Gemini CLI: Running... (11s elapsed)
⏸️  🔵 Claude: Waiting

Progress: 2/3 providers
💰 Cost So Far: $0.02
⏱️  Time: 34s elapsed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Status updates appear automatically every 10 seconds during execution.
```

---

## Feature 3: Timeout Visibility

### Problem Statement

Current state:
- Timeout is configured via `TIMEOUT=300` (5 minutes default)
- No warning when approaching timeout
- Silent failure when timeout exceeded
- Users don't know if operation is stuck or still processing

**Issues:**
- "Is this stuck?" anxiety
- Surprise timeout failures
- No guidance on adjusting timeout
- Missing context about why timeout occurred

**Desired state:**
```
🐙 LIVE PROGRESS: Discover Phase
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⏳ 🟡 Gemini CLI: Running... (4m 32s / 5m timeout)
⚠️  WARNING: Approaching timeout (28s remaining)

Tip: Increase timeout with: --timeout 600
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Solution Design

#### Concept: Timeout Awareness

1. Track elapsed time vs. timeout limit
2. Warn at 80% threshold (e.g., 4min of 5min)
3. Show timeout in progress display
4. Provide actionable guidance

#### File Changes Required

**File 1: `/Users/chris/git/claude-octopus/plugin/scripts/orchestrate.sh`**

**Location:** In the progress tracking section (after Feature 2 implementation)

**Modification to update_agent_status:**
```bash
# Update agent status WITH timeout awareness
update_agent_status() {
    local agent_name="$1"
    local status="$2"  # waiting, running, completed, failed, timeout-warning
    local elapsed_ms="${3:-0}"
    local cost="${4:-0.0}"
    local timeout_ms="${5:-$((TIMEOUT * 1000))}"

    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 0
    fi

    # Check if approaching timeout (80% threshold)
    local timeout_warning="false"
    local remaining_ms=0
    if [[ "$status" == "running" ]]; then
        local threshold_ms=$((timeout_ms * 80 / 100))
        if [[ $elapsed_ms -gt $threshold_ms ]]; then
            timeout_warning="true"
            remaining_ms=$((timeout_ms - elapsed_ms))
        fi
    fi

    # Create agent status record
    local agent_record
    agent_record=$(cat << EOF
{
  "name": "$agent_name",
  "status": "$status",
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "elapsed_ms": $elapsed_ms,
  "cost": $cost,
  "timeout_ms": $timeout_ms,
  "timeout_warning": $timeout_warning,
  "remaining_ms": $remaining_ms
}
EOF
)

    # ... rest of function as before
}
```

**Modification to format_progress_display:**
```bash
# Format progress for display WITH timeout warnings
format_progress_display() {
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 0
    fi

    # ... existing code ...

    echo "Provider Status:"

    # Read agents and format status WITH timeout info
    jq -r '.agents[] |
        if .status == "completed" then
            "✅ \(.name): Completed (\(.elapsed_ms / 1000)s) - $\(.cost)"
        elif .status == "running" then
            if .timeout_warning then
                "⏳ \(.name): Running... (\(.elapsed_ms / 1000)s / \(.timeout_ms / 1000)s timeout)\n⚠️  WARNING: Approaching timeout (\(.remaining_ms / 1000)s remaining)"
            else
                "⏳ \(.name): Running... (\(.elapsed_ms / 1000)s / \(.timeout_ms / 1000)s timeout)"
            end
        elif .status == "failed" then
            "❌ \(.name): Failed"
        else
            "⏸️  \(.name): Waiting"
        end
    ' "$PROGRESS_FILE" | sed 's/codex/🔴 Codex CLI/; s/gemini/🟡 Gemini CLI/; s/claude/🔵 Claude/'

    # Show timeout guidance if any warnings
    local has_warnings
    has_warnings=$(jq -r '[.agents[].timeout_warning] | any' "$PROGRESS_FILE")

    if [[ "$has_warnings" == "true" ]]; then
        echo ""
        echo "💡 Tip: Increase timeout with: --timeout 600"
    fi

    # ... rest of function ...
}
```

**Modification to run_with_timeout:**
```bash
# File: orchestrate.sh
# Find run_with_timeout function (around line 2964)
# Modify to log timeout events

run_with_timeout() {
    local timeout_secs="$1"
    shift

    # ... existing timeout implementation ...

    # If timeout occurred, log it
    if [[ $? -eq 124 ]] || [[ $? -eq 143 ]]; then
        log ERROR "Timeout exceeded after ${timeout_secs}s"
        echo "ERROR: Operation timed out after ${timeout_secs}s" >&2
        echo "Increase timeout with: --timeout $((timeout_secs * 2))" >&2
        return 124
    fi

    # ... rest of function ...
}
```

### Implementation Steps

#### Step 1: Add Timeout Tracking to Progress
Modify update_agent_status to include timeout_ms and calculate warnings.

#### Step 2: Update Display Formatting
Modify format_progress_display to show timeout info and warnings.

#### Step 3: Add Timeout Handler
Improve run_with_timeout to provide actionable guidance.

#### Step 4: Add Periodic Timeout Checks
```bash
# File: orchestrate.sh
# Add function to check timeouts during execution

check_timeout_warnings() {
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return 0
    fi

    # Check for any agents approaching timeout
    local warnings
    warnings=$(jq -r '[.agents[] | select(.timeout_warning == true) | .name] | join(", ")' "$PROGRESS_FILE")

    if [[ -n "$warnings" && "$warnings" != "null" ]]; then
        log WARN "Agents approaching timeout: $warnings"
        echo "" >&2
        echo "⚠️  WARNING: The following providers are approaching timeout:" >&2
        echo "    $warnings" >&2
        echo "    Consider increasing timeout with: --timeout 600" >&2
        echo "" >&2
    fi
}
```

#### Step 5: Integrate Timeout Checks
Call check_timeout_warnings periodically during parallel execution.

### Testing Strategy

#### Test Case 1: Normal Execution (No Timeout)
```bash
./scripts/orchestrate.sh probe "Quick test" --timeout 300
```

**Expected:** No timeout warnings, clean completion.

#### Test Case 2: Approaching Timeout
```bash
# Use short timeout to test warning
./scripts/orchestrate.sh probe "Complex research topic" --timeout 30
```

**Expected:** See warning at ~24 seconds with guidance to increase timeout.

#### Test Case 3: Timeout Exceeded
```bash
# Force timeout with very short limit
./scripts/orchestrate.sh probe "Long operation" --timeout 5
```

**Expected:** Timeout after 5s with clear error message and suggestion to use `--timeout 300`.

#### Test Case 4: Increased Timeout
```bash
# Verify increased timeout works
./scripts/orchestrate.sh probe "Research topic" --timeout 600
```

**Expected:** Longer timeout, different warning threshold (480s instead of 240s).

### Rollout Plan

#### Phase 1: Implementation (Day 1)
- [ ] Modify update_agent_status for timeout tracking
- [ ] Update format_progress_display for warnings
- [ ] Enhance run_with_timeout error messages
- [ ] Add check_timeout_warnings function

#### Phase 2: Integration (Day 2)
- [ ] Integrate timeout checks into parallel execution
- [ ] Test all timeout scenarios
- [ ] Verify guidance messages are helpful

#### Phase 3: Documentation (Day 2)
- [ ] Update CLI reference with timeout examples
- [ ] Add troubleshooting guide for timeouts
- [ ] Update visual indicators docs

#### Phase 4: Release (Day 3)
- [ ] Update CHANGELOG
- [ ] Bump version
- [ ] Deploy

### Documentation Updates

**File 1: `/Users/chris/git/claude-octopus/plugin/docs/CLI-REFERENCE.md`**

Add section:
```markdown
## Timeout Configuration

### Default Timeout

All workflows have a default timeout of 5 minutes (300 seconds) per provider.

### Increasing Timeout

For complex operations that need more time:

```bash
./scripts/orchestrate.sh probe "Complex research" --timeout 600  # 10 minutes
./scripts/orchestrate.sh tangle "Large codebase" --timeout 900   # 15 minutes
```

### Timeout Warnings

You'll see warnings when approaching timeout:

```
⏳ 🟡 Gemini CLI: Running... (4m 32s / 5m timeout)
⚠️  WARNING: Approaching timeout (28s remaining)

💡 Tip: Increase timeout with: --timeout 600
```

### Timeout Best Practices

| Operation Type | Recommended Timeout |
|----------------|---------------------|
| Quick research | 300s (5 min) - Default |
| Deep research | 600s (10 min) |
| Code generation | 600s (10 min) |
| Large codebase analysis | 900s (15 min) |
| Security audit | 900s (15 min) |
```

**File 2: `/Users/chris/git/claude-octopus/plugin/docs/TROUBLESHOOTING.md`** (create if needed)

```markdown
# Troubleshooting Guide

## Timeout Issues

### Problem: Operation times out before completion

**Symptoms:**
```
ERROR: Operation timed out after 300s
Increase timeout with: --timeout 600
```

**Solutions:**

1. **Increase timeout:**
   ```bash
   ./scripts/orchestrate.sh probe "..." --timeout 600
   ```

2. **Break into smaller tasks:**
   Instead of: "Research entire authentication system"
   Use: "Research JWT basics" → "Research OAuth flows" → "Research session management"

3. **Use faster providers:**
   - `gemini-fast` instead of `gemini`
   - `codex-mini` instead of `codex-max`

4. **Check network connectivity:**
   Slow API responses can cause timeouts.

### Problem: Timeout warnings appear too early

**Symptoms:**
```
⚠️  WARNING: Approaching timeout (1m 30s remaining)
```

**Solutions:**

This is expected behavior - warnings appear at 80% of timeout.
If you consistently see warnings, increase the default timeout.
```

---

## Combined Implementation Timeline

### Day 1: Core Development
**Morning:**
- [ ] Feature 1: Add spinner verb functions to orchestrate.sh
- [ ] Feature 2: Add progress tracking functions to orchestrate.sh
- [ ] Feature 3: Add timeout tracking to progress system

**Afternoon:**
- [ ] Feature 1: Integrate spinner updates into agent loop
- [ ] Feature 2: Create visual-feedback.sh hook
- [ ] Feature 3: Enhance timeout error messages

### Day 2: Integration & Testing
**Morning:**
- [ ] Feature 1: Update all workflow skill docs
- [ ] Feature 2: Update hooks.json for periodic updates
- [ ] Feature 3: Add timeout guidance to displays

**Afternoon:**
- [ ] Test all features together in real workflow
- [ ] Fix any integration issues
- [ ] Refine display formatting

### Day 3: Documentation & Release
**Morning:**
- [ ] Update VISUAL-INDICATORS.md
- [ ] Update CLI-REFERENCE.md
- [ ] Create TROUBLESHOOTING.md
- [ ] Update CHANGELOG.md

**Afternoon:**
- [ ] Final testing with all features enabled
- [ ] Bump version to 7.15.0
- [ ] Create release notes
- [ ] Deploy to registry

---

## Success Metrics

### Feature 1: Enhanced Spinner Verbs
**Before:**
- Users see: "Running multi-AI workflow"
- Clarity: 3/10

**After:**
- Users see: "🔴 Researching technical patterns (Codex)"
- Clarity: 9/10

**Metric:** User feedback on clarity

### Feature 2: Enhanced Progress Indicators
**Before:**
- No visibility into which provider is active
- "Is this stuck?" anxiety high

**After:**
- Live status for all providers
- Clear progress through queue

**Metric:** Reduction in "is this stuck?" support questions

### Feature 3: Timeout Visibility
**Before:**
- Surprise timeouts with no warning
- No guidance on resolution

**After:**
- Warnings at 80% threshold
- Clear guidance on increasing timeout

**Metric:** Reduction in timeout-related failures

---

## Risk Mitigation

### Risk 1: Performance Impact
**Concern:** Frequent file I/O for progress updates could slow execution

**Mitigation:**
- Use efficient JSON updates with jq
- Limit hook frequency to 10-second intervals
- Make progress tracking optional via flag

### Risk 2: Hook Compatibility
**Concern:** Notification hooks may not work in all Claude Code versions

**Mitigation:**
- Check Claude Code version before enabling
- Graceful degradation if hooks unavailable
- Document minimum version requirement (v2.1.16+)

### Risk 3: Display Clutter
**Concern:** Too many progress updates could overwhelm users

**Mitigation:**
- Consolidate updates into single status block
- Use clear formatting with separators
- Allow users to disable with --quiet flag

---

## Appendix: Example Output

### Complete Workflow with All Features

```
User: /octo:research "OAuth authentication patterns"

Claude:
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 Discover Phase: Researching OAuth authentication patterns

Provider Availability:
🔴 Codex CLI: Available ✓
🟡 Gemini CLI: Available ✓
🔵 Claude: Available ✓ (Strategic synthesis)

💰 Estimated Cost: $0.01-0.05
⏱️  Estimated Time: 2-5 minutes

Starting research workflow...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🐙 LIVE PROGRESS: Discover Phase (1/3 providers)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[Spinner: 🔴 Researching technical patterns (Codex)]

Provider Status:
⏳ 🔴 Codex CLI: Running... (12s / 300s timeout)
⏸️  🟡 Gemini CLI: Waiting
⏸️  🔵 Claude: Waiting

Progress: 0/3 providers
💰 Cost So Far: $0.00
⏱️  Time: 12s elapsed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[... 10 seconds later ...]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🐙 LIVE PROGRESS: Discover Phase (2/3 providers)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[Spinner: 🟡 Exploring ecosystem and options (Gemini)]

Provider Status:
✅ 🔴 Codex CLI: Completed (23s) - $0.02
⏳ 🟡 Gemini CLI: Running... (11s / 300s timeout)
⏸️  🔵 Claude: Waiting

Progress: 1/3 providers
💰 Cost So Far: $0.02
⏱️  Time: 34s elapsed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[... 10 seconds later ...]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🐙 LIVE PROGRESS: Discover Phase (3/3 providers)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[Spinner: 🔵 Synthesizing research findings]

Provider Status:
✅ 🔴 Codex CLI: Completed (23s) - $0.02
✅ 🟡 Gemini CLI: Completed (18s) - $0.01
⏳ 🔵 Claude: Running... (5s / 300s timeout)

Progress: 2/3 providers
💰 Cost So Far: $0.03
⏱️  Time: 46s elapsed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[... synthesis completes ...]

✅ Research Complete!

Final Stats:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🐙 Discover Phase: COMPLETED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

All Providers:
✅ 🔴 Codex CLI: Completed (23s) - $0.02
✅ 🟡 Gemini CLI: Completed (18s) - $0.01
✅ 🔵 Claude: Completed (12s) - $0.00

Progress: 3/3 providers
💰 Total Cost: $0.03
⏱️  Total Time: 53s
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Research Findings: OAuth Authentication Patterns

[Synthesized research results...]
```

---

## Conclusion

These three HIGH PRIORITY features transform the multi-AI orchestration UX from opaque to transparent. Users will know:

1. **What's happening** - Dynamic spinner verbs show current operation
2. **Which provider is active** - Live status for all providers
3. **How long it's taking** - Elapsed time and timeout warnings

**Combined impact:**
- Dramatically reduced user anxiety
- Clear cost and time visibility
- Professional, polished UX
- Trust in the system

**Next steps:**
1. Review this implementation plan
2. Approve for development
3. Begin Day 1 implementation
4. Release as v7.15.0 with comprehensive UX improvements
