#!/usr/bin/env bash
# Claude Octopus — Agent Lifecycle & Management
# ═══════════════════════════════════════════════════════════════════════════════
# Extracted from orchestrate.sh in v9.7.5 monolith decomposition.
# Contains: get_agent_config, get_agent_memory, get_agent_skills,
#           get_agent_permission_mode, load_agent_skill_content,
#           build_skill_context, load_curated_persona, get_curated_agent_cli,
#           get_phase_agents, select_curated_agent, record_result_hash,
#           get_effort_level, update_agent_status,
#           save_agent_checkpoint, load_agent_checkpoint,
#           load_earned_skills, build_memory_context
# Source-safe: no main execution block.
# ═══════════════════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════════════════════
# SECURITY: Result integrity verification (v8.7.0)
# SHA-256 hash recording and verification for agent result files
# ═══════════════════════════════════════════════════════════════════════════════
record_result_hash() {
    local result_file="$1"
    local manifest_dir="${WORKSPACE_DIR:-${HOME}/.claude-octopus}"
    local manifest="${manifest_dir}/.integrity-manifest"

    [[ "${OCTOPUS_SECURITY_V870:-true}" != "true" ]] && return 0
    [[ ! -f "$result_file" ]] && return 0

    mkdir -p "$manifest_dir"
    local hash
    hash=$(shasum -a 256 "$result_file" 2>/dev/null | awk '{print $1}') || return 0
    echo "${result_file}:${hash}:$(date +%s)" >> "$manifest"
}

# ═══════════════════════════════════════════════════════════════════════════════
# EFFORT LEVEL MAPPING (v8.32.0)
# Maps phase + complexity to Claude SDK effort levels (low/medium/high)
# Gated by SUPPORTS_SDK_MODEL_CAPS (Claude Code v2.1.49+)
# Override: OCTOPUS_EFFORT_OVERRIDE=low|medium|high
# ═══════════════════════════════════════════════════════════════════════════════

get_effort_level() {
    local phase="$1"
    local complexity="${2:-2}"  # 1=low, 2=medium, 3=high

    # Not supported — return empty (caller should omit effort field)
    if [[ "$SUPPORTS_SDK_MODEL_CAPS" != "true" ]]; then
        echo ""
        return
    fi

    # User override — validate against enum
    if [[ -n "${OCTOPUS_EFFORT_OVERRIDE:-}" ]]; then
        # v8.34.0: ultrathink keyword support (v2.1.68+)
        if [[ "$OCTOPUS_EFFORT_OVERRIDE" == "ultrathink" && "$SUPPORTS_ULTRATHINK" == "true" ]]; then
            echo "high"  # ultrathink triggers via keyword, effort API maps to high
            return 0
        fi
        case "$OCTOPUS_EFFORT_OVERRIDE" in
            low|medium|high) echo "$OCTOPUS_EFFORT_OVERRIDE"; return ;;
            *) log "WARN" "Invalid OCTOPUS_EFFORT_OVERRIDE='$OCTOPUS_EFFORT_OVERRIDE' — ignoring (use low|medium|high)" ;;
        esac
    fi

    # Phase-aware mapping
    local effort=""
    case "$phase" in
        probe|discover)
            # Research: low complexity = medium effort (v8.34: Opus defaults to medium), high = medium (never high — broad not deep)
            case "$complexity" in
                1) effort="medium" ;;
                3) effort="medium" ;;
                *) effort="medium" ;;
            esac
            ;;
        grasp|define)
            # Scoping: always medium — needs reasoning but not maximum depth
            effort="medium"
            ;;
        tangle|develop)
            # Implementation: scale with complexity — this is where depth matters
            case "$complexity" in
                1) effort="medium" ;;
                3) effort="high" ;;
                *) effort="medium" ;;
            esac
            ;;
        ink|deliver)
            # Review: medium for standard, high for complex (security, architecture)
            case "$complexity" in
                3) effort="high" ;;
                *) effort="medium" ;;
            esac
            ;;
        *)
            effort="medium"
            ;;
    esac

    # Defensive default
    effort="${effort:-medium}"
    echo "$effort"
}

# record_agent_start() and record_agent_complete() live in lib/cost.sh

# Update agent status in progress file
update_agent_status() {
    local agent_name="$1"
    local status="$2"  # waiting, running, completed, failed
    local elapsed_ms="${3:-0}"
    local cost="${4:-0.0}"
    local timeout_secs="${5:-${TIMEOUT:-300}}"  # Use provided or global timeout

    # Skip if progress tracking disabled or no progress file
    if [[ "$PROGRESS_TRACKING_ENABLED" != "true" ]]; then
        return 0
    fi

    if [[ ! -f "$PROGRESS_FILE" ]]; then
        log DEBUG "Progress file not found - skipping agent status update"
        return 0
    fi

    # Calculate timeout tracking (v7.16.0 Feature 3)
    local timeout_ms=$((timeout_secs * 1000))
    local timeout_warning="false"
    local remaining_ms=0
    local timeout_pct=0

    if [[ "$status" == "running" && $elapsed_ms -gt 0 ]]; then
        # Calculate percentage of timeout used
        timeout_pct=$((elapsed_ms * 100 / timeout_ms))

        # Warn if at or above 80% threshold
        if [[ $timeout_pct -ge 80 ]]; then
            timeout_warning="true"
            remaining_ms=$((timeout_ms - elapsed_ms))
            log WARN "Agent $agent_name approaching timeout ($timeout_pct% of ${timeout_secs}s)"
        fi
    fi

    # Create agent status record (JSON string for jq)
    local agent_record
    agent_record=$(jq -n \
        --arg name "$agent_name" \
        --arg status "$status" \
        --arg started "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --argjson elapsed "$elapsed_ms" \
        --argjson cost "$cost" \
        --argjson timeout_ms "$timeout_ms" \
        --arg timeout_warning "$timeout_warning" \
        --argjson remaining_ms "$remaining_ms" \
        --argjson timeout_pct "$timeout_pct" \
        '{name: $name, status: $status, started_at: $started, elapsed_ms: $elapsed, cost: $cost, timeout_ms: $timeout_ms, timeout_warning: ($timeout_warning == "true"), remaining_ms: $remaining_ms, timeout_pct: $timeout_pct}')

    # Use atomic_json_update for race-free updates
    atomic_json_update "$PROGRESS_FILE" \
        --argjson agent "$agent_record" \
        '.agents += [$agent]' || {
        log WARN "Failed to update agent status for $agent_name"
        return 1
    }

    # Update totals if completed
    if [[ "$status" == "completed" ]]; then
        atomic_json_update "$PROGRESS_FILE" \
            --argjson elapsed "$elapsed_ms" \
            --argjson cost "$cost" \
            '.completed_agents += 1 | .total_time_ms += $elapsed | .total_cost += $cost' || {
            log WARN "Failed to update progress totals"
        }
    fi

    log DEBUG "Updated agent status: $agent_name -> $status (${elapsed_ms}ms, \$${cost})"
}

save_agent_checkpoint() {
    local task_id="$1"
    local agent_type="$2"
    local phase="$3"
    local partial_output="${4:-}"

    local checkpoint_dir="${WORKSPACE_DIR}/.octo/checkpoints"
    local checkpoint_file="$checkpoint_dir/${task_id}.checkpoint.json"
    mkdir -p "$checkpoint_dir"

    # Debounce: skip if checkpoint < 5 minutes old
    if [[ -f "$checkpoint_file" ]]; then
        local mod_time now age
        if stat -f %m "$checkpoint_file" &>/dev/null; then
            mod_time=$(stat -f %m "$checkpoint_file")
        else
            mod_time=$(stat -c %Y "$checkpoint_file")
        fi
        now=$(date +%s)
        age=$((now - mod_time))
        if [[ $age -lt 300 ]]; then
            log DEBUG "Checkpoint debounce: skipping (${age}s < 300s)"
            return 0
        fi
    fi

    # Sanitize and truncate
    local safe_output
    safe_output=$(sanitize_secrets "${partial_output:0:4096}")

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    if command -v jq &>/dev/null; then
        jq -n \
            --arg task_id "$task_id" \
            --arg agent_type "$agent_type" \
            --arg phase "$phase" \
            --arg output "$safe_output" \
            --arg timestamp "$timestamp" \
            '{task_id: $task_id, agent_type: $agent_type, phase: $phase,
              partial_output: $output, timestamp: $timestamp}' \
            > "$checkpoint_file" 2>/dev/null
    else
        # Fallback without jq: simple format (escape quotes in output)
        local escaped_output
        escaped_output=$(echo "$safe_output" | sed 's/"/\\"/g' | tr '\n' ' ')
        cat > "$checkpoint_file" << CKPTEOF
{"task_id":"$task_id","agent_type":"$agent_type","phase":"$phase","partial_output":"$escaped_output","timestamp":"$timestamp"}
CKPTEOF
    fi

    log DEBUG "Saved checkpoint: $checkpoint_file"
}

load_agent_checkpoint() {
    local task_id="$1"

    local checkpoint_file="${WORKSPACE_DIR}/.octo/checkpoints/${task_id}.checkpoint.json"

    if [[ ! -f "$checkpoint_file" ]]; then
        return 1
    fi

    # Check age: expire after 24h
    local mod_time now age
    if stat -f %m "$checkpoint_file" &>/dev/null; then
        mod_time=$(stat -f %m "$checkpoint_file")
    else
        mod_time=$(stat -c %Y "$checkpoint_file")
    fi
    now=$(date +%s)
    age=$((now - mod_time))

    if [[ $age -gt 86400 ]]; then
        log DEBUG "Checkpoint expired (${age}s > 86400s): $checkpoint_file"
        rm -f "$checkpoint_file"
        return 1
    fi

    cat "$checkpoint_file"
}

load_earned_skills() {
    local skills_dir="${WORKSPACE_DIR}/.octo/skills/earned"

    if [[ ! -d "$skills_dir" ]]; then
        return
    fi

    local skills_content=""
    for skill_file in "$skills_dir"/*.md; do
        [[ -f "$skill_file" ]] || continue
        # Read just the header and latest occurrence
        local header
        header=$(head -3 "$skill_file")
        local latest
        latest=$(grep -A 5 "^#### Occurrence" "$skill_file" | tail -6)
        skills_content="${skills_content}
${header}
${latest}
"
    done

    if [[ -n "$skills_content" ]]; then
        echo "$skills_content"
    fi
}

# Get agent config value
# Usage: get_agent_config "backend-architect" "cli"
get_agent_config() {
    local agent_name="$1"
    local field="$2"

    if [[ ! -f "$AGENTS_CONFIG" ]]; then
        echo ""
        return 1
    fi

    # Extract agent block and find field
    awk -v agent="$agent_name" -v field="$field" '
        $0 ~ "^  " agent ":" { found=1; next }
        found && /^  [a-z]/ { found=0 }
        found && $0 ~ "^    " field ":" {
            gsub(/^[[:space:]]*[a-z_]+:[[:space:]]*/, "")
            gsub(/[\[\]"]/, "")
            print
            exit
        }
    ' "$AGENTS_CONFIG"
}

# v8.2.0: Get agent memory scope from config (project/none)
get_agent_memory() {
    local agent_name="$1"
    local memory
    memory=$(get_agent_config "$agent_name" "memory")
    echo "${memory:-none}"
}

# v8.2.0: Get agent skills list from config
get_agent_skills() {
    local agent_name="$1"
    local skills
    skills=$(get_agent_config "$agent_name" "skills")
    echo "${skills:-}"
}

# v8.2.0: Get agent permission mode from config (plan/acceptEdits/default)
get_agent_permission_mode() {
    local agent_name="$1"
    local mode
    mode=$(get_agent_config "$agent_name" "permissionMode")
    echo "${mode:-default}"
}

# v8.2.0: Load skill file content (strips YAML frontmatter)
load_agent_skill_content() {
    local skill_name="$1"
    local skill_file="${PLUGIN_DIR}/.claude/skills/${skill_name}.md"

    if [[ -f "$skill_file" ]]; then
        # Extract content after YAML frontmatter
        awk '
            BEGIN { in_fm=0; past_fm=0 }
            /^---$/ && !past_fm { in_fm=!in_fm; if (!in_fm) past_fm=1; next }
            past_fm { print }
        ' "$skill_file"
    fi
}

# v8.2.0: Build combined skill context for agent prompt injection
build_skill_context() {
    local agent_name="$1"
    local skills
    skills=$(get_agent_skills "$agent_name")

    [[ -z "$skills" ]] && return

    local context=""
    for skill in $(echo "$skills" | tr ',' ' '); do
        skill=$(echo "$skill" | tr -d '[:space:]')
        local content
        content=$(load_agent_skill_content "$skill")
        if [[ -n "$content" ]]; then
            context+="
--- Skill: ${skill} ---
${content}
"
        fi
    done

    echo "$context"
}

# Load persona content from curated agent file
# Returns the full markdown content (excluding frontmatter)
load_curated_persona() {
    local agent_name="$1"
    local persona_file

    persona_file=$(get_agent_config "$agent_name" "file")
    [[ -z "$persona_file" ]] && return 1

    local full_path="${AGENTS_DIR}/${persona_file}"
    [[ ! -f "$full_path" ]] && return 1

    # Extract content after YAML frontmatter (skip --- ... ---)
    awk '
        BEGIN { in_frontmatter=0; past_frontmatter=0 }
        /^---$/ && !past_frontmatter {
            in_frontmatter = !in_frontmatter
            if (!in_frontmatter) past_frontmatter=1
            next
        }
        past_frontmatter { print }
    ' "$full_path"
}

# Get CLI command for curated agent
get_curated_agent_cli() {
    local agent_name="$1"
    local cli_type

    cli_type=$(get_agent_config "$agent_name" "cli")
    [[ -z "$cli_type" ]] && cli_type="codex"

    get_agent_command "$cli_type"
}

# Get agents for a specific phase
get_phase_agents() {
    local phase="$1"

    if [[ ! -f "$AGENTS_CONFIG" ]]; then
        echo ""
        return
    fi

    # Extract agents array for phase
    awk -v phase="$phase" '
        $0 ~ "^  " phase ":" { found=1; next }
        found && /^  [a-z]/ { found=0 }
        found && /agents:/ {
            gsub(/.*agents:[[:space:]]*\[/, "")
            gsub(/\].*/, "")
            gsub(/,/, " ")
            print
            exit
        }
    ' "$AGENTS_CONFIG"
}

# Select best curated agent for task
# Uses phase context and expertise matching
select_curated_agent() {
    local prompt="$1"
    local phase="${2:-}"
    local prompt_lower
    prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')

    # Get phase default agents
    local candidates
    candidates=$(get_phase_agents "$phase")

    # If no phase specified, check all agents by expertise
    if [[ -z "$candidates" ]]; then
        candidates="backend-architect code-reviewer security-auditor test-automator"
    fi

    # Simple expertise matching
    for agent in $candidates; do
        local expertise
        expertise=$(get_agent_config "$agent" "expertise")
        for skill in $expertise; do
            if [[ "$prompt_lower" == *"$skill"* ]]; then
                echo "$agent"
                return
            fi
        done
    done

    # Return first candidate as default
    echo "$candidates" | awk '{print $1}'
}

# ═══════════════════════════════════════════════════════════════════════════════
# CROSS-MEMORY WARM START (v8.5 - Claude Code v2.1.33+)
# Injects persistent memory context into agent prompts for cross-session learning
# Reads from MEMORY.md files based on agent memory scope (project/user/local)
# ═══════════════════════════════════════════════════════════════════════════════
MEMORY_INJECTION_ENABLED="${OCTOPUS_MEMORY_INJECTION:-true}"

# Build memory context from MEMORY.md files
# Args: $1=memory_scope (project|user|local)
# Returns: compact context block (max ~500 tokens / ~2000 chars) or empty string
build_memory_context() {
    local scope="${1:-none}"

    # Guard: only works with persistent memory support
    if [[ "$SUPPORTS_PERSISTENT_MEMORY" != "true" ]]; then
        return
    fi

    # Guard: disabled by user
    if [[ "$MEMORY_INJECTION_ENABLED" != "true" ]]; then
        return
    fi

    # v8.26: When native auto-memory is active (v2.1.59+), delegate project/user memory
    # to Claude Code's native system. Keep Octopus injection for local scope only
    # (provider-specific ephemeral context not visible to native memory).
    if [[ "$SUPPORTS_NATIVE_AUTO_MEMORY" == "true" ]]; then
        if [[ "$scope" == "project" || "$scope" == "user" ]]; then
            log "DEBUG" "Delegating $scope memory to native auto-memory (v2.1.59+)"
            return
        fi
    fi

    # Skip if no scope
    if [[ "$scope" == "none" || -z "$scope" ]]; then
        return
    fi

    local memory_file=""
    case "$scope" in
        project)
            # Claude Code stores project memory by path hash
            # Try common locations
            local project_hash
            project_hash=$(echo "$PROJECT_ROOT" | tr '/' '-')
            memory_file="${HOME}/.claude/projects/${project_hash}/memory/MEMORY.md"
            if [[ ! -f "$memory_file" ]]; then
                # Try with leading dash (Claude Code convention)
                memory_file="${HOME}/.claude/projects/-${project_hash}/memory/MEMORY.md"
            fi
            ;;
        user)
            memory_file="${HOME}/.claude/memory/MEMORY.md"
            ;;
        local)
            memory_file="${PROJECT_ROOT}/.claude/memory/MEMORY.md"
            ;;
    esac

    if [[ -z "$memory_file" || ! -f "$memory_file" ]]; then
        log "DEBUG" "No memory file found for scope=$scope (tried: $memory_file)"
        return
    fi

    # v8.8: If anchor mentions available, use @file#anchor for context-efficient references
    # This avoids loading the full memory file into the prompt
    if [[ "$SUPPORTS_ANCHOR_MENTIONS" == "true" ]]; then
        log "DEBUG" "Using anchor mention for memory: @${memory_file}"
        echo "Context from persistent memory: @${memory_file}"
        echo "(Using anchor-based reference for context efficiency)"
        return
    fi

    # Fallback: Read memory file and truncate to ~2000 chars (roughly 500 tokens)
    local content
    content=$(head -c 2000 "$memory_file" 2>/dev/null) || return

    if [[ -z "$content" ]]; then
        return
    fi

    # If truncated, add ellipsis
    if [[ $(wc -c < "$memory_file" 2>/dev/null) -gt 2000 ]]; then
        content="${content}
...
(memory truncated to fit context)"
    fi

    log "DEBUG" "Memory context loaded: scope=$scope, size=${#content} chars"
    echo "$content"
}
