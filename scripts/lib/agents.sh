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

# count_words() lives in lib/utils.sh; pull it in when this file is sourced
# standalone (tests do) rather than through orchestrate.sh's load order.
if ! declare -f count_words >/dev/null 2>&1; then
    if ! source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"; then
        return 1 2>/dev/null || exit 1
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# SECURITY: Result integrity verification (v8.7.0)
# SHA-256 hash recording and verification for agent result files
# ═══════════════════════════════════════════════════════════════════════════════
# Portable mtime in epoch seconds. GNU form first, and the result is validated
# as numeric: on Linux `stat -f` is --file-system, so `stat -f %m` SUCCEEDS and
# prints the mount point. Probing BSD-style first therefore returned "/" on
# Linux and every age comparison built on it silently misbehaved.
_octo_file_mtime() {
    local f="$1" v
    v="$(stat -c %Y "$f" 2>/dev/null)" || v=""
    [[ "$v" =~ ^[0-9]+$ ]] || v="$(stat -f %m "$f" 2>/dev/null)" || v=""
    [[ "$v" =~ ^[0-9]+$ ]] && printf '%s\n' "$v" || printf '0\n'
}

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
# EFFORT LEVEL MAPPING (v8.32.0; refreshed for Opus 5)
# Maps phase + complexity to Claude SDK effort levels.
# Gated by SUPPORTS_SDK_MODEL_CAPS (Claude Code v2.1.49+)
# Override: OCTOPUS_EFFORT_OVERRIDE=low|medium|high|xhigh|max
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
            low|medium|high|xhigh|max)
                # v9.51: Fable 5 clamp applies to explicit overrides too.
                if declare -f fable5_clamp_effort >/dev/null 2>&1; then
                    fable5_clamp_effort "$OCTOPUS_EFFORT_OVERRIDE"
                else
                    echo "$OCTOPUS_EFFORT_OVERRIDE"
                fi
                return ;;
            *) log "WARN" "Invalid OCTOPUS_EFFORT_OVERRIDE='$OCTOPUS_EFFORT_OVERRIDE' — ignoring (use low|medium|high|xhigh|max)" ;;
        esac
    fi

    # Opus 5 defaults to high. Automatic xhigh remains available for legacy
    # Opus hosts and can be re-enabled on Opus 5 with
    # OCTOPUS_OPUS5_AUTO_XHIGH=1. Explicit OCTOPUS_EFFORT_OVERRIDE always wins.
    local _deep="high"
    if [[ "${SUPPORTS_XHIGH_EFFORT:-false}" == "true" \
          && ( "${SUPPORTS_OPUS_5:-false}" != "true" || "${OCTOPUS_OPUS5_AUTO_XHIGH:-0}" == "1" ) ]]; then
        _deep="xhigh"
    fi

    # Phase-aware mapping
    local effort=""
    case "$phase" in
        probe|discover)
            # Research: Opus high is the balanced default.
            effort="high"
            ;;
        grasp|define)
            # Scoping/planning: high by default, xhigh only if explicitly marked complex.
            case "$complexity" in
                3) effort="$_deep" ;;
                *) effort="high" ;;
            esac
            ;;
        tangle|develop)
            # Implementation: xhigh for complex work, high for ordinary work.
            case "$complexity" in
                1) effort="high" ;;
                3) effort="$_deep" ;;
                *) effort="high" ;;
            esac
            ;;
        ink|deliver)
            # Review: xhigh for security/architecture/deep review, high otherwise.
            case "$complexity" in
                3) effort="$_deep" ;;
                *) effort="high" ;;
            esac
            ;;
        *)
            effort="high"
            ;;
    esac

    # Defensive default
    effort="${effort:-high}"

    # v9.51: Fable 5 effort clamp — xhigh/max → high when the opus seat is
    # pinned to claude-fable-5 (applies to user overrides too; that is the
    # point of the guard). No-op when lib/fable5.sh is not loaded.
    if declare -f fable5_clamp_effort >/dev/null 2>&1; then
        effort="$(fable5_clamp_effort "$effort")"
    fi

    echo "$effort"
}

# record_agent_start() and record_agent_complete() live in lib/cost.sh

# Update agent status in progress file
update_agent_status() {
    local agent_name="$1"
    local status="$2"  # waiting, running, completed, ok, degraded, failed, timeout, skipped
    local elapsed_ms="${3:-0}"
    local cost="${4:-0.0}"
    local timeout_secs="${5:-${TIMEOUT:-300}}"  # Use provided or global timeout
    local task_id="${6:-legacy-${agent_name}}"
    local phase="${7:-}"
    local output_file="${8:-}"

    # Legacy rows and optional integrations can supply blank, null, or textual
    # metrics. Normalize before arithmetic and jq --argjson so progress updates
    # remain fail-safe instead of aborting the caller.
    [[ "$elapsed_ms" =~ ^[0-9]+$ ]] || elapsed_ms=0
    [[ "$cost" =~ ^[0-9]+([.][0-9]+)?$ ]] || cost=0.0

    # Skip if progress tracking disabled or no progress file
    if [[ "$PROGRESS_TRACKING_ENABLED" != "true" ]]; then
        return 0
    fi

    if [[ ! -f "$PROGRESS_FILE" ]]; then
        log DEBUG "Progress file not found - skipping agent status update"
        return 0
    fi

    # Calculate timeout tracking (v7.16.0 Feature 3)
    [[ "$timeout_secs" =~ ^[0-9]+$ ]] || timeout_secs=0
    local timeout_ms=$((timeout_secs * 1000))
    local timeout_warning="false"
    local remaining_ms=0
    local timeout_pct=0

    if [[ "$status" == "running" && $elapsed_ms -gt 0 && $timeout_ms -gt 0 ]]; then
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
        --arg task_id "$task_id" \
        --arg phase "$phase" \
        --arg status "$status" \
        --arg started "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg updated "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg output_file "$output_file" \
        --argjson elapsed "$elapsed_ms" \
        --argjson cost "$cost" \
        --argjson timeout_ms "$timeout_ms" \
        --arg timeout_warning "$timeout_warning" \
        --argjson remaining_ms "$remaining_ms" \
        --argjson timeout_pct "$timeout_pct" \
        '{name: $name, task_id: $task_id, phase: $phase, status: $status, started_at: $started, updated_at: $updated, output_file: $output_file, elapsed_ms: $elapsed, cost: $cost, timeout_ms: $timeout_ms, timeout_warning: ($timeout_warning == "true"), remaining_ms: $remaining_ms, timeout_pct: $timeout_pct}')

    # Upsert by task identity, then derive totals from the terminal rows. This
    # makes retries/idempotent hook updates safe and prevents stale running rows.
    atomic_json_update "$PROGRESS_FILE" \
        --argjson agent "$agent_record" \
        '
        def terminal:
          .status as $status
          | (["completed", "ok", "degraded", "failed", "timeout", "skipped"] | index($status)) != null;
        def phase_rank($phase):
          if ($phase == "probe" or $phase == "discover") then 1
          elif ($phase == "grasp" or $phase == "define") then 2
          elif ($phase == "tangle" or $phase == "develop") then 3
          elif ($phase == "ink" or $phase == "deliver") then 4
          else 0 end;
        def canonical_phase($phase):
          if phase_rank($phase) == 1 then "discover"
          elif phase_rank($phase) == 2 then "define"
          elif phase_rank($phase) == 3 then "develop"
          elif phase_rank($phase) == 4 then "deliver"
          else $phase end;
        ([.agents[]? | select(.task_id == $agent.task_id)] | first) as $previous
        | .phase = (
            if phase_rank($agent.phase) >= phase_rank(.phase) and phase_rank($agent.phase) > 0
            then canonical_phase($agent.phase)
            else .phase end)
        | .updated_at = $agent.updated_at
        | .agents = (
            if $previous == null then
              (.agents // []) + [$agent]
            else
              [(.agents // [])[] |
                if .task_id == $agent.task_id then
                  ($agent + {started_at: ($previous.started_at // $agent.started_at)})
                else . end]
            end)
        | .total_agents = ([.total_agents // 0, (.agents | length)] | max)
        | .completed_agents = ([.agents[] | select(terminal)] | length)
        | .successful_agents = ([.agents[] | select(.status == "completed" or .status == "ok" or .status == "degraded")] | length)
        | .failed_agents = ([.agents[] | select(.status == "failed")] | length)
        | .timeout_agents = ([.agents[] | select(.status == "timeout")] | length)
        | .skipped_agents = ([.agents[] | select(.status == "skipped")] | length)
        | .total_time_ms = ([.agents[] | select(terminal) | .elapsed_ms] | add // 0)
        | .total_cost = ([.agents[] | select(terminal) | .cost] | add // 0)
        ' || {
        log WARN "Failed to update agent status for $agent_name"
        return 1
    }

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
        mod_time="$(_octo_file_mtime "$checkpoint_file")"
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
    mod_time="$(_octo_file_mtime "$checkpoint_file")"
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

# Resolve a curated persona name to the provider used by `orchestrate.sh spawn`.
# Direct provider names return non-zero so the caller preserves its existing path.
resolve_persona_spawn_target() {
    local persona="$1"
    local primary fallback

    case "$persona" in
        ''|*[!a-zA-Z0-9_-]*) return 1 ;;
    esac
    if [[ -n "${AVAILABLE_AGENTS:-}" && " $AVAILABLE_AGENTS " == *" $persona "* ]]; then
        return 1
    fi

    primary="$(get_agent_config "$persona" "cli" 2>/dev/null | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//' || true)"
    [[ -n "$primary" ]] || return 1

    if ! declare -f is_agent_available_v2 >/dev/null 2>&1 || is_agent_available_v2 "$primary"; then
        printf '%s\n' "$primary"
        return 0
    fi

    fallback="$(get_agent_config "$persona" "fallback_cli" 2>/dev/null | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//' || true)"
    if [[ -n "$fallback" ]] && is_agent_available_v2 "$fallback"; then
        printf '%s\n' "$fallback"
        return 0
    fi

    # Preserve the configured primary so normal dispatch reports its concrete
    # availability/authentication failure when no configured fallback can run.
    printf '%s\n' "$primary"
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

    if [[ ! -f "$skill_file" ]]; then
        skill_file="${PLUGIN_DIR}/.claude/skills/${skill_name}/SKILL.md"
    fi

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

# ── Extracted from orchestrate.sh (optimization sweep) ──

# Maps phase context to the appropriate codex-* agent type
# Usage: get_codex_agent_for_phase <phase> [task_hint]
get_codex_agent_for_phase() {
    local phase="${1:-develop}"
    local task_hint="${2:-}"

    # Task hints override phase defaults
    case "$task_hint" in
        fast|spark)         echo "codex-spark" ; return 0 ;;
        reasoning)          echo "codex-reasoning" ; return 0 ;;
        large-codebase)     echo "codex-large-context" ; return 0 ;;
        budget|cheap)       echo "codex-mini" ; return 0 ;;
    esac

    # Phase-based agent selection
    case "$phase" in
        deliver|ink|review|quick)
            echo "codex-spark"
            ;;
        *)
            echo "codex"
            ;;
    esac
}

get_agent_for_task() {
    local task_type="$1"
    case "$task_type" in
        image) echo "agy" ;;
        review) echo "codex-review" ;;
        coding) echo "codex" ;;
        design) echo "agy" ;;          # Antigravity Google seat
        copywriting) echo "agy" ;;     # Antigravity — creative writing
        research) echo "agy" ;;        # Antigravity — analysis/synthesis
        general) echo "codex" ;;       # Default to codex for general tasks
        *) echo "codex" ;;
    esac
}

get_agent_description() {
    local agent="$1"
    local agent_file="$PLUGIN_DIR/agents/personas/$agent.md"

    # v8.53.0: Fall back to user-scope agents
    if [[ ! -f "$agent_file" ]]; then
        agent_file="${USER_AGENTS_DIR}/${agent}.md"
    fi

    if [[ -f "$agent_file" ]]; then
        grep -m1 "^description:" "$agent_file" 2>/dev/null | sed 's/description:[[:space:]]*//' | cut -c1-80
    else
        echo "Specialized agent"
    fi
}

show_agent_recommendations() {
    local prompt="$1"
    local recommendations="$2"

    # Only show in interactive mode (not CI, not dry-run)
    [[ "$CI_MODE" == "true" ]] && return
    [[ "$DRY_RUN" == "true" ]] && return

    # Split into an array. Globbing is disabled around the split so an agent
    # name list containing `*` or `?` cannot expand into matching filenames.
    local _had_noglob=false
    case "$-" in *f*) _had_noglob=true ;; esac
    set -f
    local IFS=$' \t\n'
    # shellcheck disable=SC2206 # deliberate word splitting; globbing disabled above
    local rec_array=($recommendations)
    [[ "$_had_noglob" == "true" ]] || set +f

    local count=${#rec_array[@]}
    [[ $count -lt 2 ]] && return

    echo ""
    echo -e "${CYAN}${_HEAVY}${NC}"
    echo -e "${CYAN}🐙 Multiple providers could handle this task:${NC}"
    echo ""

    local i=1
    for agent in "${rec_array[@]}"; do
        local desc
        desc=$(get_agent_description "$agent")
        echo -e "  ${GREEN}$i.${NC} ${YELLOW}$agent${NC}"
        echo "     $desc"
        echo ""
        ((i++)) || true
    done

    local primary="${rec_array[0]}"
    echo -e "${CYAN}Recommended: ${GREEN}$primary${NC} (best match based on keywords)"
    echo -e "${CYAN}${_HEAVY}${NC}"
    echo ""
}

# This replaces the simple get_agent_for_task for cost-aware routing
# v4.5: Now resource-aware based on user config
get_tiered_agent() {
    local task_type="$1"
    local complexity="${2:-2}"  # Default: standard
    local agent=""

    # Load user config for resource-aware routing (v4.5)
    load_user_config 2>/dev/null || true

    # Apply resource tier adjustment
    local adjusted_complexity
    adjusted_complexity=$(get_resource_adjusted_tier "$complexity" 2>/dev/null || echo "$complexity")

    case "$task_type" in
        image)
            # Antigravity selects the compatible image-capable service model.
            agent="agy"
            ;;
        review)
            # Reviews use standard tier (already cost-effective)
            agent="codex-review"
            ;;
        coding|general)
            # Coding tasks: tier based on adjusted complexity
            case "$adjusted_complexity" in
                1) agent="codex-mini" ;;      # Trivial → mini (cheapest)
                2) agent="codex-standard" ;;  # Standard → standard tier
                3) agent="codex" ;;           # Complex → premium
                *) agent="codex-standard" ;;
            esac
            ;;
        design|copywriting|research)
            # Antigravity (agy) is the Google seat.
            # Model tier is selected via OCTOPUS_AGY_MODEL, not separate agents.
            agent="agy"
            ;;
        diamond-*)
            # Double Diamond workflows: respect resource tier
            case "$USER_RESOURCE_TIER" in
                pro|api-only) agent="codex-standard" ;;  # Conservative
                *) agent="codex" ;;                       # Premium
            esac
            ;;
        *)
            # Safe default: standard tier
            agent="codex-standard"
            ;;
    esac

    # Apply API key fallback (v4.5)
    get_fallback_agent "$agent" "$task_type" 2>/dev/null || echo "$agent"
}
