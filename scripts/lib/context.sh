#!/usr/bin/env bash
# Context detection & memory/skill context building
# Extracted from orchestrate.sh and lib/agents.sh (v9.7.x decomposition)
#
# Functions: detect_context, get_context_display, get_context_info,
#            detect_response_mode, build_skill_context, build_memory_context


# count_words() lives in lib/utils.sh; pull it in when this file is sourced
# standalone (tests do) rather than through orchestrate.sh's load order.
if ! declare -f count_words >/dev/null 2>&1; then
    if ! source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"; then
        return 1 2>/dev/null || exit 1
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# CONTEXT DETECTION (v7.8.1)
# Auto-detects Dev vs Knowledge context to tailor workflow behavior
# Returns: "dev" or "knowledge" with confidence level
# ═══════════════════════════════════════════════════════════════════════════════

# Detect context from prompt content and project type
# Returns: "dev" or "knowledge"
detect_context() {
    local prompt="$1"
    local prompt_lower
    prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')
    
    local dev_score=0
    local knowledge_score=0
    local confidence="medium"
    
    local knowledge_mode=""
    if [[ -f "$USER_CONFIG_FILE" ]]; then
        knowledge_mode=$(grep "^knowledge_work_mode:" "$USER_CONFIG_FILE" 2>/dev/null | sed 's/.*: *//' | tr -d '"' || echo "")
    fi
    
    case "$knowledge_mode" in
        true|on)
            echo "knowledge:high:override"
            return
            ;;
        false|off)
            echo "dev:high:override"
            return
            ;;
    esac
    
    # Step 2: Analyze prompt content (strongest signal)
    # Knowledge context indicators
    local knowledge_patterns="market|roi|stakeholder|strategy|business.?case|competitive|literature|synthesis|academic|papers|research.?question|persona|user.?research|journey.?map|pain.?point|interview|presentation|report|prd|proposal|executive.?summary|swot|gtm|go.?to.?market|market.?entry|consulting|workshop"
    
    # Dev context indicators
    local dev_patterns="api|endpoint|database|function|class|module|implement|debug|refactor|test|deploy|build|code|migration|schema|controller|component|service|interface|typescript|javascript|python|react|node|sql|html|css|git|commit|pr|pull.?request|fix|bug|error|lint|compile"
    
    # Count matches
    local knowledge_matches
    # v9.5: count matches via bash loop instead of echo|grep|wc pipeline (zero subshells)
    knowledge_matches=0
    local _km_pat
    for _km_pat in ${knowledge_patterns//|/ }; do
        [[ "$prompt_lower" == *"$_km_pat"* ]] && ((knowledge_matches++)) || true
    done

    local dev_matches=0
    for _km_pat in ${dev_patterns//|/ }; do
        [[ "$prompt_lower" == *"$_km_pat"* ]] && ((dev_matches++)) || true
    done
    
    ((dev_score += dev_matches * 2))
    ((knowledge_score += knowledge_matches * 2))
    
    # Step 3: Check project type (secondary signal)
    # Check for code project indicators
    if [[ -f "${PROJECT_ROOT}/package.json" ]] || \
       [[ -f "${PROJECT_ROOT}/Cargo.toml" ]] || \
       [[ -f "${PROJECT_ROOT}/go.mod" ]] || \
       [[ -f "${PROJECT_ROOT}/pyproject.toml" ]] || \
       [[ -f "${PROJECT_ROOT}/pom.xml" ]] || \
       [[ -f "${PROJECT_ROOT}/Makefile" ]]; then
        ((dev_score += 1))
    fi
    
    # Check for knowledge project indicators
    if [[ -d "${PROJECT_ROOT}/research" ]] || \
       [[ -d "${PROJECT_ROOT}/reports" ]] || \
       [[ -d "${PROJECT_ROOT}/strategy" ]]; then
        ((knowledge_score += 1))
    fi
    
    # Step 4: Determine context and confidence
    if [[ $dev_score -gt $knowledge_score ]]; then
        if [[ $((dev_score - knowledge_score)) -ge 3 ]]; then
            confidence="high"
        fi
        echo "dev:$confidence:auto"
    elif [[ $knowledge_score -gt $dev_score ]]; then
        if [[ $((knowledge_score - dev_score)) -ge 3 ]]; then
            confidence="high"
        fi
        echo "knowledge:$confidence:auto"
    else
        # Tie - default to dev in code repos, knowledge otherwise
        if [[ -f "${PROJECT_ROOT}/package.json" ]] || [[ -f "${PROJECT_ROOT}/Cargo.toml" ]]; then
            echo "dev:low:fallback"
        else
            echo "knowledge:low:fallback"
        fi
    fi
}


# Get display name for context
get_context_display() {
    local context_result="$1"
    local context="${context_result%%:*}"
    local rest="${context_result#*:}"
    local confidence="${rest%%:*}"
    
    case "$context" in
        dev) echo "[Dev]" ;;
        knowledge) echo "[Knowledge]" ;;
        *) echo "" ;;
    esac
}


# Get full context info for verbose mode
get_context_info() {
    local context_result="$1"
    local context="${context_result%%:*}"
    local rest="${context_result#*:}"
    local confidence="${rest%%:*}"
    local method="${rest#*:}"
    
    echo "Context: $context (confidence: $confidence, method: $method)"
}


# v8.18.0 Feature: Response Mode Auto-Tuning
# Auto-detect task complexity and adjust execution depth

detect_response_mode() {
    local prompt="$1"
    local task_type="${2:-}"
    local prompt_lower
    prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')

    # Check for env var override first
    if [[ "$OCTOPUS_RESPONSE_MODE" != "auto" ]]; then
        echo "$OCTOPUS_RESPONSE_MODE"
        return
    fi

    # User signal detection
    # v9.5: bash regex (zero subshells, was echo|grep)
    if [[ "$prompt_lower" =~ (quick|fast|simple|brief|short) ]]; then
        echo "direct"
        return
    fi
    if [[ "$prompt_lower" =~ (thorough|comprehensive|complete|detailed|in-depth|exhaustive) ]]; then
        echo "full"
        return
    fi

    # Task type heuristics
    case "${task_type}" in
        crossfire-*)
            echo "full"
            return
            ;;
        image-*)
            echo "lightweight"
            return
            ;;
        diamond-*)
            echo "standard"
            return
            ;;
    esac

    # Word count heuristics
    local word_count
    word_count=$(count_words "$prompt")

    if [[ $word_count -lt 10 ]]; then
        echo "direct"
        return
    fi
    if [[ $word_count -gt 80 ]]; then
        echo "full"
        return
    fi

    # Technical keyword density scoring
    local tech_score=0
    local tech_keywords="api database schema migration authentication authorization security performance optimization architecture microservice docker kubernetes terraform infrastructure pipeline deployment integration webhook endpoint middleware"

    # v9.5: bash builtin word boundary check (zero subshells per iteration, was echo|grep per keyword)
    for keyword in $tech_keywords; do
        if [[ " $prompt_lower " == *" $keyword "* ]]; then
            ((tech_score++)) || true
        fi
    done

    if [[ $tech_score -ge 3 ]]; then
        echo "full"
    elif [[ $tech_score -ge 1 ]]; then
        echo "standard"
    else
        echo "standard"
    fi
}


# v8.2.0: Build combined skill context for agent prompt injection
build_skill_context() {
    local agent_name="$1"
    local skills
    skills=$(get_agent_skills "$agent_name")

    [[ -z "$skills" ]] && return

    local context=""
    for skill in ${skills//,/ }; do
        skill="${skill//[[:space:]]/}"
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
            project_hash="${PROJECT_ROOT//\//-}"
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
