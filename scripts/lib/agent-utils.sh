#!/usr/bin/env bash
# agent-utils.sh — Agent execution utilities: roles, RALPH loops, retry, image, resume
# Contains: get_role_mapping, get_role_agent, get_role_model, log_role_assignment,
#           has_curated_agents, parse_yaml_value, check_completion_promise,
#           init_ralph_state, update_ralph_state, get_ralph_iteration,
#           run_with_ralph_loop, has_claude_code, run_with_claude_code_ralph,
#           refine_image_prompt, detect_image_type, retry_failed_subtasks,
#           build_anchor_ref, build_file_reference, resume_agent
# Extracted from orchestrate.sh (v9.7.8)
# Source-safe: no main execution block.

# ═══════════════════════════════════════════════════════════════════════════════


# Resolve phase/role-specific agent/provider overrides while preserving existing defaults.
#
# This selects only the agent/provider name used for dispatch. Model selection is
# still handled later by resolve_octopus_model() in scripts/lib/model-resolver.sh.
# That resolver may return values from /tmp/octo-model-cache-*.json before reading
# model environment overrides; clear that cache to force-refresh model selection.
#
# Lookup order for phase="tangle", role="coding":
#   OCTOPUS_TANGLE_CODING_AGENT
#   OCTOPUS_TANGLE_AGENT
#   OCTOPUS_CODING_AGENT
#   <default passed by caller>
octopus_agent_override() {
    local phase="$1"
    local role="$2"
    local default_agent="$3"
    local phase_key role_key env_name value

    phase_key=$(printf '%s' "$phase" | tr '[:lower:]-' '[:upper:]_' | sed -E 's/[^A-Z0-9_]+/_/g; s/^_+//; s/_+$//')
    role_key=$(printf '%s' "$role" | tr '[:lower:]-' '[:upper:]_' | sed -E 's/[^A-Z0-9_]+/_/g; s/^_+//; s/_+$//')

    if [[ -n "$phase_key" && -n "$role_key" ]]; then
        env_name="OCTOPUS_${phase_key}_${role_key}_AGENT"
        value="${!env_name:-}"
        [[ -n "$value" ]] && { echo "$value"; return 0; }
    fi

    if [[ -n "$phase_key" ]]; then
        env_name="OCTOPUS_${phase_key}_AGENT"
        value="${!env_name:-}"
        [[ -n "$value" ]] && { echo "$value"; return 0; }
    fi

    if [[ -n "$role_key" ]]; then
        env_name="OCTOPUS_${role_key}_AGENT"
        value="${!env_name:-}"
        [[ -n "$value" ]] && { echo "$value"; return 0; }
    fi

    echo "$default_agent"
}

# v9.19.0: Safe default for --bare flag (set by providers.sh, but guard for standalone sourcing)
_BARE_OPT="${_BARE_OPT:-}"

# Role-to-agent mapping (function-based for bash 3.x compatibility)
# Returns agent:model format for a given role
#
# v9.29: Role defaults refreshed based on April 2026 benchmark + forum consensus.
#   - architect/strategist/security-reviewer → claude-opus (SWE-bench Pro 64.3, LMArena #1, MCP-Atlas +9.2)
#   - code-reviewer/implementer              → gpt-5.5    (Terminal-Bench 75.1, edge-case review)
# Opt-out:   OCTOPUS_LEGACY_ROLES=1 restores the v9.28 mapping.
# Fallback:  consumers (see lib/agents.sh get_fallback_agent) silently downshift when the
#            preferred CLI is unavailable (e.g. no Anthropic auth → architect → gpt-5.5).
get_role_mapping() {
    local role="$1"

    # Legacy opt-out — v9.28 mapping, preserved verbatim.
    if [[ "${OCTOPUS_LEGACY_ROLES:-0}" == "1" ]]; then
        case "$role" in
            architect)    echo "codex:gpt-5.5" ;;
            researcher)   echo "gemini:gemini-3.1-pro-preview" ;;
            reviewer|code-reviewer|security-reviewer) echo "codex-review:gpt-5.5" ;;
            implementer|implementer-heavy) echo "codex:gpt-5.5" ;;
            synthesizer)  echo "claude:claude-sonnet-4.6" ;;
            strategist)   echo "claude-opus:claude-opus-4.6" ;;
            *)            echo "codex:gpt-5.5" ;;
        esac
        return 0
    fi

    case "$role" in
        architect)         echo "claude-opus:$(opus_default_model 2>/dev/null || echo claude-opus-4.7)" ;;  # Planning, UI/UX, architecture
        researcher)        echo "agy:Gemini 3.1 Pro (High)" ;;                                             # Deep investigation via Antigravity (Google seat)
        reviewer|code-reviewer) echo "codex-review:gpt-5.5" ;;                                              # Code review, edge cases; `reviewer` = alias
        security-reviewer) echo "claude-opus:$(opus_default_model 2>/dev/null || echo claude-opus-4.7)" ;;  # Adversarial reasoning
        implementer)       echo "codex:gpt-5.5" ;;                                                          # Default code generation; terminal-heavy
        implementer-heavy) echo "claude-opus:$(opus_default_model 2>/dev/null || echo claude-opus-4.7)" ;;  # Opt-in: greenfield/refactor/UI-heavy
        synthesizer)       echo "claude:claude-sonnet-4.6" ;;                                               # Result aggregation
        strategist)        echo "claude-opus:$(opus_default_model 2>/dev/null || echo claude-opus-4.7)" ;;  # Premium synthesis
        *)                 echo "codex:gpt-5.5" ;;                                                          # Safe default
    esac
}

# Get agent type for a role
get_role_agent() {
    local role="$1"
    local mapping
    mapping=$(get_role_mapping "$role")
    echo "${mapping%%:*}"  # Return agent type (before colon)
}

# Get model for a role
get_role_model() {
    local role="$1"
    local mapping
    mapping=$(get_role_mapping "$role")
    echo "${mapping##*:}"  # Return model (after colon)
}

# Log role assignment for verbose mode
log_role_assignment() {
    local role="$1"
    local purpose="$2"
    local agent
    agent=$(get_role_agent "$role")
    local has_persona="no"
    [[ -n "$(get_persona_instruction "$role" 2>/dev/null)" ]] && has_persona="yes"
    log DEBUG "Using ${role} role (${agent}, persona: ${has_persona}) for: ${purpose}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# v3.3 FEATURE: AGENT PERSONAS
# Specialized system instructions for each agent role
# Personas inject domain expertise and behavioral guidelines into prompts
# ═══════════════════════════════════════════════════════════════════════════════

# [EXTRACTED to lib/persona-loader.sh] get_persona_instruction()

# [EXTRACTED to lib/dispatch.sh in v9.7.7]

# get_role_for_context() — extracted to lib/routing.sh (v8.21.0)

# ═══════════════════════════════════════════════════════════════════════════════
# v3.4 FEATURE: CURATED AGENT LOADER
# Load specialized agent personas from agents/ directory
# Integrates wshobson/agents curated subset with CLI-specific routing
# ═══════════════════════════════════════════════════════════════════════════════

AGENTS_DIR="${PLUGIN_DIR}/agents"
AGENTS_CONFIG="${AGENTS_DIR}/config.yaml"

# v8.53.0: User-scope agents directory (Cursor-inspired: ~/.cursor/agents/)
# Users can add personal agent personas here without modifying the plugin.
USER_AGENTS_DIR="${HOME}/.claude/agents"

# Check if curated agents are available
has_curated_agents() {
    [[ -d "$AGENTS_DIR" && -f "$AGENTS_CONFIG" ]]
}

# Parse YAML value (simple bash parsing, no jq dependency)
# Usage: parse_yaml_value "file.yaml" "key"
parse_yaml_value() {
    local file="$1"
    local key="$2"
    grep -m1 "^[[:space:]]*${key}:" "$file" 2>/dev/null | sed "s/^[[:space:]]*${key}:[[:space:]]*//" | tr -d '"'
}

# Get agent config value
# Usage: get_agent_config "backend-architect" "cli"
# [EXTRACTED to lib/agents.sh]

# v8.2.0: Get agent memory scope from config (project/none)
# [EXTRACTED to lib/agents.sh]

# v8.2.0: Get agent skills list from config
# [EXTRACTED to lib/agents.sh]

# v8.2.0: Get agent permission mode from config (plan/acceptEdits/default)
# [EXTRACTED to lib/agents.sh]

# [EXTRACTED to lib/dispatch.sh in v9.7.7]

# v8.2.0: Load skill file content (strips YAML frontmatter)
# [EXTRACTED to lib/agents.sh]

# v8.2.0: Build combined skill context for agent prompt injection
# [EXTRACTED to lib/agents.sh]

# Load persona content from curated agent file
# Returns the full markdown content (excluding frontmatter)
# [EXTRACTED to lib/agents.sh]

# Get CLI command for curated agent
# [EXTRACTED to lib/agents.sh]

# Get agents for a specific phase
# [EXTRACTED to lib/agents.sh]

# Select best curated agent for task
# Uses phase context and expertise matching
# [EXTRACTED to lib/agents.sh]

# ═══════════════════════════════════════════════════════════════════════════════
# v3.5 FEATURE: RALPH-WIGGUM ITERATION PATTERN
# Iterative loop support with completion promises
# Inspired by anthropics/claude-code/plugins/ralph-wiggum
# ═══════════════════════════════════════════════════════════════════════════════

# Default completion promise pattern
COMPLETION_PROMISE="${CLAUDE_OCTOPUS_COMPLETION_PROMISE:-<promise>COMPLETE</promise>}"
RALPH_MAX_ITERATIONS="${CLAUDE_OCTOPUS_RALPH_MAX_ITERATIONS:-50}"
RALPH_STATE_FILE=""  # Deferred — set lazily in init_ralph_state()

# Check if output contains completion promise
check_completion_promise() {
    local output="$1"
    local promise="${2:-$COMPLETION_PROMISE}"

    # Extract promise tag pattern
    local tag_pattern
    tag_pattern=$(echo "$promise" | sed 's/<promise>\(.*\)<\/promise>/\1/')

    if [[ "$output" == *"<promise>"*"</promise>"* ]]; then
        # Extract actual promise content
        local actual_promise
        actual_promise=$(echo "$output" | grep -o '<promise>[^<]*</promise>' | head -1)

        if [[ "$actual_promise" == "$promise" ]]; then
            log INFO "Completion promise detected: $actual_promise"
            return 0
        fi
    fi
    return 1
}

# Initialize ralph-wiggum style iteration state
init_ralph_state() {
    local prompt="$1"
    local max_iterations="${2:-$RALPH_MAX_ITERATIONS}"
    local promise="${3:-$COMPLETION_PROMISE}"
    # Lazy init — WORKSPACE_DIR not available at source time
    RALPH_STATE_FILE="${WORKSPACE_DIR}/ralph-state.md"

    cat > "$RALPH_STATE_FILE" << EOF
---
iteration: 0
max_iterations: $max_iterations
completion_promise: "$promise"
started: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
status: running
---

# Original Prompt
$prompt

# Iteration Log
EOF

    log INFO "Ralph iteration state initialized (max: $max_iterations)"
}

# Update ralph state after iteration
update_ralph_state() {
    local iteration="$1"
    local status="${2:-running}"
    local notes="${3:-}"

    [[ ! -f "$RALPH_STATE_FILE" ]] && return 1

    # Update iteration count in frontmatter
    sed -i.bak "s/^iteration:.*/iteration: $iteration/" "$RALPH_STATE_FILE"
    sed -i.bak "s/^status:.*/status: $status/" "$RALPH_STATE_FILE"
    rm -f "${RALPH_STATE_FILE}.bak"

    # Append to iteration log
    echo "" >> "$RALPH_STATE_FILE"
    echo "## Iteration $iteration - $(date +"%H:%M:%S")" >> "$RALPH_STATE_FILE"
    [[ -n "$notes" ]] && echo "$notes" >> "$RALPH_STATE_FILE"
}

# Get current ralph iteration count
get_ralph_iteration() {
    [[ ! -f "$RALPH_STATE_FILE" ]] && echo "0" && return
    grep -m1 "^iteration:" "$RALPH_STATE_FILE" | awk '{print $2}'
}

# Run agent with ralph-wiggum style iteration
# Keeps iterating until completion promise or max iterations
run_with_ralph_loop() {
    local agent_type="$1"
    local prompt="$2"
    local max_iterations="${3:-$RALPH_MAX_ITERATIONS}"
    local promise="${4:-$COMPLETION_PROMISE}"

    init_ralph_state "$prompt" "$max_iterations" "$promise"

    local iteration=0
    local output=""
    local completed=false

    echo ""
    echo -e "${MAGENTA}${_BOX_TOP}${NC}"
    echo -e "${MAGENTA}║  RALPH-WIGGUM ITERATION MODE                              ║${NC}"
    echo -e "${MAGENTA}║  Iterating until: $promise           ${NC}"
    echo -e "${MAGENTA}${_BOX_BOT}${NC}"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would iterate: $prompt"
        log INFO "[DRY-RUN] Agent: $agent_type, Max iterations: $max_iterations"
        log INFO "[DRY-RUN] Completion promise: $promise"
        return 0
    fi

    while [[ $iteration -lt $max_iterations ]]; do
        ((iteration++)) || true
        log INFO "Ralph iteration $iteration/$max_iterations"

        # Build iteration context
        local iteration_prompt
        if [[ $iteration -eq 1 ]]; then
            iteration_prompt="$prompt

When you have completed the task successfully, output exactly: $promise"
        else
            iteration_prompt="Continue working on: $prompt

Previous attempt did not complete. Review your work, identify issues, and continue.
This is iteration $iteration of $max_iterations.
Output $promise when the task is truly complete."
        fi

        # Run agent
        output=$(run_agent_sync "$agent_type" "$iteration_prompt" 300)

        # Check for completion
        if check_completion_promise "$output" "$promise"; then
            completed=true
            update_ralph_state "$iteration" "completed" "Task completed successfully"
            break
        fi

        update_ralph_state "$iteration" "running" "Iteration completed, promise not found"

        # Brief pause between iterations
        sleep 2
    done

    if [[ "$completed" == "true" ]]; then
        echo ""
        echo -e "${GREEN}✓ Ralph loop completed in $iteration iterations${NC}"
        echo ""
    else
        echo ""
        echo -e "${YELLOW}⚠ Ralph loop reached max iterations ($max_iterations)${NC}"
        update_ralph_state "$iteration" "max_iterations_reached"
        echo ""
    fi

    echo "$output"
}

# Check if Claude Code CLI is available for advanced iteration
has_claude_code() {
    command -v claude &>/dev/null
}

# Run with Claude Code + ralph-wiggum plugin if available
run_with_claude_code_ralph() {
    local prompt="$1"
    local max_iterations="${2:-$RALPH_MAX_ITERATIONS}"
    local promise="${3:-$COMPLETION_PROMISE}"

    if ! has_claude_code; then
        log WARN "Claude Code CLI not found, falling back to native iteration"
        run_with_ralph_loop "codex" "$prompt" "$max_iterations" "$promise"
        return
    fi

    log INFO "Using Claude Code with ralph-wiggum pattern"

    # Check if ralph-wiggum plugin is installed
    if claude plugin list 2>/dev/null | grep -q "ralph-wiggum"; then
        # Use actual ralph-wiggum
        claude "/ralph-loop \"$prompt\" --max-iterations $max_iterations --completion-promise \"$promise\""
    else
        # Use Claude Code with manual iteration prompt
        local iteration_prompt="$prompt

IMPORTANT: When task is complete, output exactly: $promise
Do not output this promise until the task is truly finished."

        claude${_BARE_OPT} --print "$iteration_prompt"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# v3.0 FEATURE: NANO BANANA PROMPT REFINEMENT
# Intelligent prompt enhancement for image generation tasks
# Analyzes user intent and crafts optimized prompts for visual output
# ═══════════════════════════════════════════════════════════════════════════════

# Refine image prompt using "nano banana" technique
# Takes raw user prompt and returns an enhanced prompt optimized for image generation
refine_image_prompt() {
    local raw_prompt="$1"
    local image_type="${2:-general}"

    log INFO "Applying nano banana prompt refinement for: $image_type"

    # Build refinement prompt based on image type
    local refinement_prompt=""
    case "$image_type" in
        "app-icon"|"favicon")
            refinement_prompt="Transform this into a detailed image generation prompt for an app icon/favicon:
Original request: $raw_prompt

Create a prompt that specifies:
- Simple, recognizable silhouette that works at small sizes (16x16 to 512x512)
- Bold colors with good contrast
- Minimal detail that scales well
- Professional, modern aesthetic
- Square format with optional rounded corners

Output ONLY the refined prompt, nothing else."
            ;;
        "social-media")
            refinement_prompt="Transform this into a detailed image generation prompt for social media:
Original request: $raw_prompt

Create a prompt that specifies:
- Eye-catching composition with focal point
- Appropriate aspect ratio (16:9 for banners, 1:1 for posts)
- Brand-friendly colors and style
- Space for text overlay if needed
- Professional quality suitable for marketing

Output ONLY the refined prompt, nothing else."
            ;;
        "diagram")
            refinement_prompt="Transform this into a detailed image generation prompt for a technical diagram:
Original request: $raw_prompt

Create a prompt that specifies:
- Clean, professional diagram style
- Clear visual hierarchy and flow
- Appropriate use of shapes, arrows, and connections
- Readable labels and annotations
- Light or neutral background for clarity

Output ONLY the refined prompt, nothing else."
            ;;
        *)
            refinement_prompt="Transform this into a detailed, optimized image generation prompt:
Original request: $raw_prompt

Enhance the prompt with:
- Specific visual style and composition details
- Lighting, mood, and atmosphere
- Color palette suggestions
- Technical specifications (resolution, aspect ratio if implied)
- Quality modifiers (professional, high-quality, detailed)

Output ONLY the refined prompt, nothing else."
            ;;
    esac

    # Use Gemini for intelligent prompt refinement
    local refined
    refined=$(run_agent_sync "gemini-fast" "$refinement_prompt" 60 2>/dev/null) || {
        log WARN "Prompt refinement failed, using original"
        echo "$raw_prompt"
        return
    }

    echo "$refined"
}

# Detect image type from prompt for targeted refinement
detect_image_type() {
    local prompt_lower="$1"

    if [[ "$prompt_lower" =~ (app[[:space:]]?icon|favicon|icon[[:space:]]for[[:space:]]?(an?[[:space:]])?app) ]]; then
        echo "app-icon"
    elif [[ "$prompt_lower" =~ (social[[:space:]]?media|twitter|linkedin|facebook|instagram|og[[:space:]]?image|banner|header) ]]; then
        echo "social-media"
    elif [[ "$prompt_lower" =~ (diagram|flowchart|architecture|sequence|infographic) ]]; then
        echo "diagram"
    else
        echo "general"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# v3.0 FEATURE: LOOP-UNTIL-APPROVED RETRY LOGIC
# Retry failed subtasks until quality gate passes
# ═══════════════════════════════════════════════════════════════════════════════

# Store failed tasks for retry (global array - bash 3.x compatible)
FAILED_SUBTASKS=""  # Newline-separated list for compatibility

# Extract a multiline prompt from a tangle result file.
# Result files write "# Prompt: <first line>" followed by the original prompt body
# until "# Started:". Preserve that body so retries do not collapse to a useless
# one-line prompt such as "Original task context:".
extract_tangle_retry_prompt() {
    local result_file="$1"
    local prompt result_dir task_id previous_task_id previous_result_file
    prompt=$(awk '
        /^# Prompt: / {
            sub(/^# Prompt: /, "")
            print
            in_prompt=1
            next
        }
        /^# Started:/ { exit }
        in_prompt { print }
    ' "$result_file" 2>/dev/null || true)

    if [[ -n "$prompt" ]]; then
        printf '%s\n' "$prompt"
        return 0
    fi

    # Continuation result files can lack a # Prompt header. When retrying a
    # failed retry artifact, fall back to the previous artifact for the same
    # subtask so the original context is not lost.
    result_dir=$(dirname "$result_file")
    task_id=$(tangle_result_task_id "$result_file")
    previous_task_id=$(tangle_previous_retry_task_id "$task_id")
    if [[ -n "$previous_task_id" ]]; then
        previous_result_file=$(find "$result_dir" -maxdepth 1 -type f -name "*-${previous_task_id}.md" 2>/dev/null | head -1 || true)
        if [[ -n "$previous_result_file" && -f "$previous_result_file" && "$previous_result_file" != "$result_file" ]]; then
            extract_tangle_retry_prompt "$previous_result_file"
        fi
    fi
}
tangle_result_header_value() {
    local result_file="$1"
    local prefix="$2"
    awk -v prefix="$prefix" '
        index($0, prefix) == 1 {
            sub(prefix, "")
            print
            exit
        }
    ' "$result_file" 2>/dev/null || true
}

tangle_result_last_status() {
    local result_file="$1"
    awk '
        /^## Status: / {
            sub(/^## Status: /, "")
            value=$0
        }
        END { print value }
    ' "$result_file" 2>/dev/null || true
}

normalize_tangle_result_agent() {
    local agent="$1"
    printf '%s\n' "$agent" | sed 's/ (.*$//'
}

tangle_result_agent() {
    local result_file="$1"
    local agent base
    agent=$(tangle_result_header_value "$result_file" "# Agent: ")
    agent=$(normalize_tangle_result_agent "$agent")
    if [[ -z "$agent" ]]; then
        base=$(basename "$result_file" .md)
        if [[ "$base" == *-tangle-* ]]; then
            agent="${base%%-tangle-*}"
        fi
    fi
    printf '%s\n' "$agent"
}

tangle_result_task_id() {
    local result_file="$1"
    local task_id base suffix
    task_id=$(tangle_result_header_value "$result_file" "# Task ID: ")
    if [[ -z "$task_id" ]]; then
        base=$(basename "$result_file" .md)
        if [[ "$base" == *-tangle-* ]]; then
            suffix="${base#*-tangle-}"
            task_id="tangle-${suffix}"
        fi
    fi
    printf '%s\n' "$task_id"
}


tangle_previous_retry_task_id() {
    local task_id="$1"
    local parsed group retry_num suffix
    parsed=$(printf '%s\n' "$task_id" | sed -n 's/^tangle-\(.*\)-retry\([0-9][0-9]*\)-\([0-9][0-9]*\)$/\1|\2|\3/p')
    [[ -n "$parsed" ]] || return 0
    IFS='|' read -r group retry_num suffix <<EOF_PREVIOUS_TASK_ID
$parsed
EOF_PREVIOUS_TASK_ID
    if [[ "$retry_num" -le 1 ]]; then
        printf 'tangle-%s-%s\n' "$group" "$suffix"
    else
        printf 'tangle-%s-retry%s-%s\n' "$group" "$((retry_num - 1))" "$suffix"
    fi
}

tangle_result_workdir() {
    local result_file="$1"
    awk '
        /^workdir: / {
            sub(/^workdir: /, "")
            print
            exit
        }
    ' "$result_file" 2>/dev/null || true
}

tangle_result_transcript_files() {
    local result_file="$1"
    local dir base suffix candidate
    dir=$(dirname "$result_file")
    base=$(basename "$result_file" .md)
    if [[ "$base" == *-tangle-* ]]; then
        suffix="${base#*-tangle-}"
        for candidate in \
            "$dir/.tmp-tangle-${suffix}.err" \
            "$dir/.tmp-tangle-${suffix}.out" \
            "$dir/.raw-tangle-${suffix}.out"; do
            [[ -f "$candidate" ]] && printf '%s\n' "$candidate"
        done
    fi
}

tangle_retry_error_diagnostics() {
    local result_file="$1"
    local files diagnostics
    files="$result_file"
    files="$files"$'\n'"$(tangle_result_transcript_files "$result_file")"
    diagnostics=$(printf '%s\n' "$files" | while IFS= read -r file; do
        [[ -f "$file" ]] || continue
        grep -nEi '(^|[^A-Za-z])(SyntaxError|ReferenceError|TypeError|Error:|Cannot find module|Invalid or unexpected token|FAIL:|START FAILED|FATAL|exited [1-9]|EADDRINUSE|Permission denied|No such file|cat:|timeout|timedOut|missing-done|Empty output)' "$file" 2>/dev/null | sed "s#^#$file:#"
    done | tail -80)
    printf '%s\n' "$diagnostics"
}

tangle_retry_worktree_diagnostics() {
    local result_file="$1"
    local workdir changed_files suspicious
    workdir=$(tangle_result_workdir "$result_file")
    [[ -n "$workdir" && -d "$workdir/.git" ]] || return 0

    {
        echo "Worktree status:"
        git -C "$workdir" status --short 2>/dev/null | sed -n '1,80p' || true
        echo ""
        echo "Diff stat:"
        git -C "$workdir" diff --stat 2>/dev/null | sed -n '1,80p' || true
    }

    changed_files=$(git -C "$workdir" status --short 2>/dev/null | awk '{print $NF}' | sed -n '1,120p' || true)
    suspicious=$(printf '%s\n' "$changed_files" | while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        if [[ "$path" != *.js && "$path" != *.mjs && "$path" != *.cjs && "$path" != *.ts && "$path" != *.mts && "$path" != *.cts ]]; then
            continue
        fi
        [[ -f "$workdir/$path" ]] || continue
        grep -nE '\\\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$workdir/$path" 2>/dev/null | sed "s#^#$path:#" | sed -n '1,12p'
    done | sed -n '1,40p')
    if [[ -n "$suspicious" ]]; then
        echo ""
        echo "Suspicious literal template placeholders in changed JS/TS files:"
        printf '%s\n' "$suspicious"
    fi
}

tangle_retry_diagnostics() {
    local result_file="$1"
    local error_diagnostics worktree_diagnostics
    error_diagnostics=$(tangle_retry_error_diagnostics "$result_file")
    worktree_diagnostics=$(tangle_retry_worktree_diagnostics "$result_file")

    if [[ -z "$error_diagnostics" && -z "$worktree_diagnostics" ]]; then
        printf '<no additional diagnostics captured>\n'
        return 0
    fi

    if [[ -n "$error_diagnostics" ]]; then
        echo "Transcript/error indicators:"
        printf '%s\n' "$error_diagnostics"
    fi
    if [[ -n "$worktree_diagnostics" ]]; then
        [[ -n "$error_diagnostics" ]] && echo ""
        echo "Worktree/diff indicators:"
        printf '%s\n' "$worktree_diagnostics"
    fi
}

# Build a retry prompt that explains the failed output/completion quality while
# keeping the same provider path. This is deliberately not a provider fallback:
# empty/partial output, missing completion markers, plan-only responses and
# missing worktree evidence should get feedback and another attempt first.
build_tangle_retry_feedback_prompt() {
    local result_file="$1"
    local original_prompt="$2"
    local task_id status role agent output_excerpt diagnostics

    task_id=$(tangle_result_task_id "$result_file")
    status=$(tangle_result_last_status "$result_file")
    role=$(tangle_result_header_value "$result_file" "# Role: ")
    agent=$(tangle_result_agent "$result_file")
    output_excerpt=$(awk '
        /^# Started:/ { after_started=1; next }
        after_started && /^## Output$/ { in_output=1; next }
        after_started && /^## Status:/ { in_output=0 }
        in_output { print }
    ' "$result_file" 2>/dev/null || true)
    output_excerpt=$(printf '%s\n' "$output_excerpt" | tail -80 || true)
    diagnostics=$(tangle_retry_diagnostics "$result_file")

    cat <<EOF
RETRY FEEDBACK:
The previous attempt for ${task_id:-this tangle subtask} failed output/quality validation.
Failure status: ${status:-unknown}
Previous provider/agent: ${agent:-unknown}
Previous role: ${role:-unknown}

This is an output/completion-quality retry, not a provider availability fallback.
Use the same provider/role path for this retry unless the operator explicitly configured OCTOPUS_TANGLE_RETRY_SWITCH_PROVIDER=true.

Retry rules:
- Do not restart the whole roadmap.
- Complete only the failed assigned subtask.
- Use the existing worktree state and preserve successful edits from other subtasks.
- If this is a [CODING] task, edit repository files directly; do not only describe a plan.
- Finish with explicit sections: ## Worktree Changes, ## Integration Evidence, and ## Verification.
- If a boundary blocks completion, report the blocker explicitly instead of returning empty or partial output.

Previous output excerpt, if any:
${output_excerpt:-<no useful output captured>}

Observed diagnostics from transcript and worktree:
${diagnostics:-<no additional diagnostics captured>}

Original subtask prompt:
${original_prompt}
EOF
}

# Retry failed subtasks
retry_failed_subtasks() {
    local task_group="$1"
    local retry_count="$2"

    if [[ -z "$FAILED_SUBTASKS" ]]; then
        log DEBUG "No failed subtasks to retry"
        return 0
    fi

    # Count tasks (newline-separated)
    local task_count
    task_count=$(echo "$FAILED_SUBTASKS" | grep -c .)
    local retry_limit_display="${MAX_QUALITY_RETRIES:-${CLAUDE_OCTOPUS_MAX_RETRIES:-3}}"
    if declare -f quality_retry_limit >/dev/null 2>&1; then
        retry_limit_display=$(quality_retry_limit)
    fi
    log INFO "Retrying $task_count failed subtasks (attempt $retry_count/${retry_limit_display})..."

    local pids=""
    local subtask_num=0
    local pid_count=0

    # Process newline-separated list
    while IFS= read -r failed_task; do
        [[ -z "$failed_task" ]] && continue

        # Parse failed task info. New result-file entries preserve multiline prompts
        # and carry failure status; the legacy agent:prompt format remains supported.
        local agent=""
        local prompt=""
        local role="implementer"
        local result_file=""
        local result_task_id=""
        local result_task_suffix=""
        local retry_from_result=false
        if [[ "$failed_task" == result:* ]]; then
            result_file="${failed_task#result:}"
            agent=$(tangle_result_agent "$result_file")
            role=$(tangle_result_header_value "$result_file" "# Role: ")
            [[ -z "$role" ]] && role="implementer"
            result_task_id=$(tangle_result_task_id "$result_file")
            result_task_suffix="${result_task_id##*-}"
            [[ "$result_task_suffix" =~ ^[0-9]+$ ]] || result_task_suffix="$subtask_num"
            prompt=$(extract_tangle_retry_prompt "$result_file")
            if [[ -z "$prompt" && -n "${WORKSPACE_DIR:-}" && -n "$result_task_id" ]]; then
                local retry_instruction_file="${WORKSPACE_DIR}/agent-teams/${result_task_id}.json"
                if [[ -f "$retry_instruction_file" ]] && command -v jq >/dev/null 2>&1; then
                    prompt=$(jq -r '.prompt // empty' "$retry_instruction_file" 2>/dev/null || true)
                fi
            fi
            prompt=$(build_tangle_retry_feedback_prompt "$result_file" "$prompt")
            retry_from_result=true
        else
            # Legacy format: agent:prompt
            agent="${failed_task%%:*}"
            prompt="${failed_task#*:}"
        fi

        # v8.18.0: Provider lockout was designed for provider availability failures.
        # For result-file retries, keep the same provider by default and send feedback;
        # only switch if an operator explicitly opts in.
        if [[ "$retry_from_result" == "true" ]]; then
            if [[ "${OCTOPUS_TANGLE_RETRY_SWITCH_PROVIDER:-false}" == "true" ]] && is_provider_locked "$agent"; then
                local alt_agent
                alt_agent=$(get_alternate_provider "$agent")
                log WARN "Provider $agent is locked out, rerouting retry to $alt_agent"
                agent="$alt_agent"
            fi
        elif is_provider_locked "$agent"; then
            local alt_agent
            alt_agent=$(get_alternate_provider "$agent")
            log WARN "Provider $agent is locked out, rerouting retry to $alt_agent"
            agent="$alt_agent"
        fi

        # Determine role based on agent type for legacy retries. Result-file retries
        # keep the role captured in the failed artifact.
        if [[ "$retry_from_result" != "true" ]]; then
            role="implementer"
            [[ "$agent" == "gemini" || "$agent" == "gemini-fast" ]] && role="researcher"
        fi

        # v8.19.0: Search for similar errors and inject context into retry prompt
        local error_keyword
        error_keyword=$(echo "$prompt" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' ' ' | head -c 50)
        local similar_count
        similar_count=$(search_similar_errors "$error_keyword" 2>/dev/null) || similar_count=0
        if [[ "$similar_count" -gt 0 ]]; then
            prompt="[RETRY CONTEXT: This task has failed $similar_count time(s) previously. Analyze error patterns before attempting.]

$prompt"
            flag_repeat_error "$error_keyword" 2>/dev/null || true
        fi

        # v8.30: Attempt agent continuation/resume before cold spawn
        local retry_suffix="$subtask_num"
        [[ "$retry_from_result" == "true" && -n "$result_task_suffix" ]] && retry_suffix="$result_task_suffix"
        local retry_task_id="tangle-${task_group}-retry${retry_count}-${retry_suffix}"
        local _did_resume=false
        if [[ "$SUPPORTS_CONTINUATION" == "true" ]]; then
            # Result-file retries resume the exact failed artifact. Legacy retries
            # retain the historical loop-index mapping.
            local orig_task_id="tangle-${task_group}-${retry_suffix}"
            if [[ "$retry_from_result" == "true" && -n "$result_task_id" ]]; then
                orig_task_id="$result_task_id"
            elif [[ $retry_count -gt 1 ]]; then
                orig_task_id="tangle-${task_group}-retry$((retry_count - 1))-${retry_suffix}"
            fi
            local prev_agent_id
            prev_agent_id=$(bridge_get_agent_id "$orig_task_id" 2>/dev/null) || true
            if [[ -n "$prev_agent_id" ]]; then
                local iteration_prompt="Continue working on the previous task. The output was insufficient.

Revise and improve your response:
$prompt"
                if resume_agent "$prev_agent_id" "$iteration_prompt" "$retry_task_id" "$role" "tangle"; then
                    _did_resume=true
                    log "INFO" "Resumed agent $prev_agent_id for retry (task=$retry_task_id)"
                else
                    log "DEBUG" "Resume failed for agent $prev_agent_id, falling back to cold spawn"
                fi
            fi
        fi

        if [[ "$_did_resume" == "true" ]]; then
            # Resume dispatches via Agent Teams (no background pid)
            ((subtask_num++)) || true
        elif should_use_agent_teams "$agent" 2>/dev/null; then
            # Agent Teams dispatch (no background pid)
            spawn_agent "$agent" "$prompt" "$retry_task_id" "$role" "tangle"
            ((subtask_num++)) || true
        else
            # Legacy bash subprocess
            local pid
            pid=$(spawn_agent_capture_pid "$agent" "$prompt" "$retry_task_id" "$role" "tangle")
            pids="$pids $pid"
            ((subtask_num++)) || true
            ((pid_count++)) || true
        fi
    done <<< "$FAILED_SUBTASKS"

    # Wait for retry tasks
    local completed=0
    while [[ $completed -lt $pid_count ]]; do
        completed=0
        for pid in $pids; do
            if ! kill -0 "$pid" 2>/dev/null; then
                ((completed++)) || true
            fi
        done
        echo -ne "\r${YELLOW}Retry progress: $completed/${pid_count} tasks${NC}"
        sleep 2
    done
    echo ""

    # Clear failed tasks for re-evaluation
    FAILED_SUBTASKS=""
}

# ═══════════════════════════════════════════════════════════════════════════════
# ANCHOR FRAGMENT MENTIONS (v8.8 - Claude Code v2.1.41+)
# Uses @file#anchor syntax to reference specific sections instead of entire files
# Reduces context consumption by 60-80% for documentation-heavy workflows
# ═══════════════════════════════════════════════════════════════════════════════

# Build an @file#anchor reference for a specific section of a file
# Args: $1=file_path, $2=anchor (heading text, lowercased, hyphenated)
# Returns: "@file#anchor" string if supported, or full file path as fallback
build_anchor_ref() {
    local file_path="$1"
    local anchor="${2:-}"

    if [[ "$SUPPORTS_ANCHOR_MENTIONS" == "true" ]] && [[ -n "$anchor" ]]; then
        echo "@${file_path}#${anchor}"
    else
        echo "@${file_path}"
    fi
}

# Build context-efficient file references for agent prompts
# When anchor mentions are available, references specific sections rather than whole files
# Args: $1=file_path, $2=section_heading (optional)
# Returns: Instruction string for agent prompt
build_file_reference() {
    local file_path="$1"
    local section="${2:-}"

    if [[ "$SUPPORTS_ANCHOR_MENTIONS" == "true" ]] && [[ -n "$section" ]]; then
        # Convert heading to anchor format: lowercase, spaces to hyphens
        local anchor
        anchor=$(echo "$section" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
        echo "Refer to $(build_anchor_ref "$file_path" "$anchor") for context."
    else
        echo "Refer to @${file_path} for context."
    fi
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
# [EXTRACTED to lib/agents.sh]

# ═══════════════════════════════════════════════════════════════════════════════
# AGENT TEAMS CONDITIONAL MIGRATION (v8.5 - Claude Code v2.1.34+)
# Claude-to-Claude agents can use native Agent Teams instead of bash subprocesses
# Codex and Gemini remain bash-spawned (external CLIs)
# ═══════════════════════════════════════════════════════════════════════════════
OCTOPUS_AGENT_TEAMS="${OCTOPUS_AGENT_TEAMS:-auto}"  # auto | native | legacy

# [EXTRACTED to lib/agent-sync.sh]

# ═══════════════════════════════════════════════════════════════════════════════
# v8.30: Agent continuation/resume for iterative retries
# Resumes a previous agent's transcript instead of cold-spawning a new one.
# Only works for Claude agents via Agent Teams. Falls back to spawn_agent() on failure.
# ═══════════════════════════════════════════════════════════════════════════════
resume_agent() {
    local agent_id="$1"
    local prompt="$2"
    local task_id="${3:-$(date +%s)}"
    local role="${4:-}"
    local phase="${5:-}"

    # Gate: continuation must be supported
    if [[ "$SUPPORTS_CONTINUATION" != "true" ]]; then
        log "DEBUG" "resume_agent: SUPPORTS_CONTINUATION=false, falling back"
        return 1
    fi

    # Gate: agent_id must be non-empty
    if [[ -z "$agent_id" ]]; then
        log "DEBUG" "resume_agent: empty agent_id, falling back"
        return 1
    fi

    # Gate: Agent Teams must be available (resume only works for Claude agents)
    if [[ "$SUPPORTS_STABLE_AGENT_TEAMS" != "true" ]]; then
        log "DEBUG" "resume_agent: Agent Teams not available, falling back"
        return 1
    fi

    log "INFO" "Resuming agent $agent_id for task $task_id (phase=${phase:-none}, role=${role:-none})"

    # Write resume instruction JSON for Claude Code's Agent tool
    local teams_dir="${WORKSPACE_DIR}/agent-teams"
    mkdir -p "$teams_dir"

    local resume_instruction_file="${teams_dir}/${task_id}.json"
    if command -v jq &>/dev/null; then
        jq -n \
            --arg agent_id "$agent_id" \
            --arg task_id "$task_id" \
            --arg role "${role:-none}" \
            --arg phase "${phase:-none}" \
            --arg prompt "$prompt" \
            --arg result_file "${RESULTS_DIR}/claude-${task_id}.md" \
            '{dispatch_method: "send_message", agent_id: $agent_id,
              task_id: $task_id, role: $role, phase: $phase,
              prompt: $prompt, result_file: $result_file,
              dispatched_at: now | todate}' \
            > "$resume_instruction_file" 2>/dev/null
    else
        log "WARN" "resume_agent: jq not available, falling back"
        return 1
    fi

    # Register task in bridge ledger (non-fatal if ledger missing)
    bridge_register_task "$task_id" "claude-resume" "${phase:-unknown}" "${role:-none}" || true

    # Emit structured signal for Claude Code to pick up
    echo "AGENT_TEAMS_RESUME:${agent_id}:${task_id}:${role:-none}:${phase:-none}"

    # Write initial result file header
    local result_file="${RESULTS_DIR}/claude-${task_id}.md"
    mkdir -p "$RESULTS_DIR"
    echo "# Agent: claude (resumed via continuation)" > "$result_file"
    echo "# Task ID: $task_id" >> "$result_file"
    echo "# Resumed Agent: $agent_id" >> "$result_file"
    echo "# Role: ${role:-none}" >> "$result_file"
    echo "# Phase: ${phase:-none}" >> "$result_file"
    echo "# Dispatch: Agent Teams (SendMessage)" >> "$result_file"
    echo "# Started: $(date)" >> "$result_file"
    echo "" >> "$result_file"

    log "DEBUG" "Resume instruction written to: $resume_instruction_file"
    return 0
}

# [EXTRACTED to lib/spawn.sh]
