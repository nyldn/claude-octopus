#!/usr/bin/env bash
# Claude Octopus - Intelligence Library (v8.20.0)
# Provides: Provider Intelligence, Cost Routing, Capability Matching,
#           Quorum Consensus, and File Path Validation
#
# Sourced by orchestrate.sh. All functions are prefixed or namespaced
# to avoid collisions with the main script.

# Source guard — prevent double-loading
[[ -n "${_INTELLIGENCE_LOADED:-}" ]] && return 0
_INTELLIGENCE_LOADED=1

# ═══════════════════════════════════════════════════════════════════════════════
# CENTRALIZED JSON HANDLING (Commit 0)
# Provides octo_db_get/set/append wrappers that handle missing jq gracefully
# ═══════════════════════════════════════════════════════════════════════════════

# Check if jq is available (cached for performance)
_INTELLIGENCE_HAS_JQ=""
_intelligence_has_jq() {
    if [[ -z "$_INTELLIGENCE_HAS_JQ" ]]; then
        command -v jq &>/dev/null && _INTELLIGENCE_HAS_JQ="true" || _INTELLIGENCE_HAS_JQ="false"
    fi
    [[ "$_INTELLIGENCE_HAS_JQ" == "true" ]]
}

# Read a value from a JSON file
# Usage: octo_db_get <file> <key> [default_value]
octo_db_get() {
    local file="$1"
    local key="$2"
    local default_value="${3:-}"

    [[ -f "$file" ]] || { echo "$default_value"; return 0; }

    if _intelligence_has_jq; then
        local val
        val=$(jq -r ".$key // empty" "$file" 2>/dev/null)
        if [[ -n "$val" && "$val" != "null" ]]; then
            echo "$val"
        else
            echo "$default_value"
        fi
    else
        # Fallback: simple grep extraction for flat JSON
        local val
        val=$(grep -o "\"$key\"[[:space:]]*:[[:space:]]*[\"0-9][^,}]*" "$file" 2>/dev/null | head -1 | sed 's/.*:[[:space:]]*//' | tr -d '"')
        if [[ -n "$val" ]]; then
            echo "$val"
        else
            echo "$default_value"
        fi
    fi
}

# Write a key-value pair to a JSON file (atomic write)
# Usage: octo_db_set <file> <key> <value>
octo_db_set() {
    local file="$1"
    local key="$2"
    local value="$3"

    # Ensure parent directory exists
    mkdir -p "$(dirname "$file")" 2>/dev/null || true

    if _intelligence_has_jq; then
        if [[ -f "$file" ]]; then
            local tmp="${file}.tmp.$$"
            jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$file" > "$tmp" 2>/dev/null && mv "$tmp" "$file"
        else
            printf '{\"%s\": \"%s\"}\n' "$key" "$value" > "$file"
        fi
    else
        # Fallback: simple JSON structure
        if [[ -f "$file" ]]; then
            # Remove trailing } and add new key
            local tmp="${file}.tmp.$$"
            sed 's/}[[:space:]]*$//' "$file" > "$tmp" 2>/dev/null
            printf ',\n  \"%s\": \"%s\"\n}\n' "$key" "$value" >> "$tmp"
            mv "$tmp" "$file"
        else
            printf '{\n  \"%s\": \"%s\"\n}\n' "$key" "$value" > "$file"
        fi
    fi
}

# Append a JSON line to a JSONL file with cap enforcement
# Usage: octo_db_append <file> <json_line> [max_entries]
octo_db_append() {
    local file="$1"
    local entry="$2"
    local max_entries="${3:-500}"

    mkdir -p "$(dirname "$file")" 2>/dev/null || true

    echo "$entry" >> "$file"

    # Enforce cap: trim oldest entries if over limit
    if [[ -f "$file" ]]; then
        local count
        count=$(wc -l < "$file" 2>/dev/null | tr -d ' ')
        if [[ "$count" -gt "$max_entries" ]]; then
            local trim=$((count - max_entries))
            local tmp="${file}.tmp.$$"
            tail -n "$max_entries" "$file" > "$tmp" && mv "$tmp" "$file"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# PROVIDER INTELLIGENCE (Commit 1 — F1+F2 merged)
# Unified provider outcome tracking with Bayesian trust scoring
# Ships in shadow mode by default
# ═══════════════════════════════════════════════════════════════════════════════

# Record an agent outcome to telemetry
# Usage: record_outcome <provider> <agent_type> <task_type> <phase> <outcome> <duration_ms>
record_outcome() {
    local provider="$1"
    local agent_type="$2"
    local task_type="$3"
    local phase="$4"
    local outcome="$5"
    local duration_ms="$6"

    [[ "${OCTOPUS_PROVIDER_INTELLIGENCE:-shadow}" == "off" ]] && return 0

    local telemetry_file="${WORKSPACE_DIR:-.}/.octo/provider-telemetry.jsonl"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +%s)

    local entry
    if _intelligence_has_jq; then
        entry=$(jq -n -c \
            --arg p "$provider" \
            --arg a "$agent_type" \
            --arg t "$task_type" \
            --arg ph "$phase" \
            --arg o "$outcome" \
            --arg d "$duration_ms" \
            --arg ts "$timestamp" \
            '{provider:$p, agent:$a, task_type:$t, phase:$ph, outcome:$o, duration_ms:($d|tonumber), timestamp:$ts}' 2>/dev/null)
    else
        entry="{\"provider\":\"$provider\",\"agent\":\"$agent_type\",\"task_type\":\"$task_type\",\"phase\":\"$phase\",\"outcome\":\"$outcome\",\"duration_ms\":$duration_ms,\"timestamp\":\"$timestamp\"}"
    fi

    octo_db_append "$telemetry_file" "$entry" 500

    log "DEBUG" "Intelligence: recorded $outcome for $provider/$agent_type ($task_type, ${duration_ms}ms)" 2>/dev/null || true
}

# Get Bayesian provider score
# Formula: (successes + 3.5) / (successes + failures + 5) — prior: 0.7, weight: 5
# Usage: get_provider_score <provider>
get_provider_score() {
    local provider="$1"
    local telemetry_file="${WORKSPACE_DIR:-.}/.octo/provider-telemetry.jsonl"
    local default_score="0.70"

    [[ -f "$telemetry_file" ]] || { echo "$default_score"; return 0; }

    local successes=0 failures=0

    if _intelligence_has_jq; then
        successes=$(grep "\"provider\":\"$provider\"" "$telemetry_file" 2>/dev/null | grep '"outcome":"success"' | wc -l | tr -d ' ')
        failures=$(grep "\"provider\":\"$provider\"" "$telemetry_file" 2>/dev/null | grep -E '"outcome":"(fail|timeout)"' | wc -l | tr -d ' ')
    else
        successes=$(grep -c "\"provider\":\"$provider\".*\"outcome\":\"success\"" "$telemetry_file" 2>/dev/null || echo 0)
        failures=$(grep -c "\"provider\":\"$provider\".*\"outcome\":\"fail\|timeout\"" "$telemetry_file" 2>/dev/null || echo 0)
    fi

    local total=$((successes + failures))
    if [[ $total -lt 5 ]]; then
        echo "$default_score"
        return 0
    fi

    # Bayesian score with prior (0.7, weight 5)
    # score = (successes + 3.5) / (successes + failures + 5)
    # Use bc for floating point, fall back to awk
    local score
    if command -v bc &>/dev/null; then
        score=$(echo "scale=2; ($successes + 3.5) / ($successes + $failures + 5)" | bc 2>/dev/null)
    else
        score=$(awk "BEGIN { printf \"%.2f\", ($successes + 3.5) / ($successes + $failures + 5) }" 2>/dev/null)
    fi

    echo "${score:-$default_score}"
}

# Get provider ranking sorted by score descending
# Includes fairness floor: providers with < 5% of tasks get priority sampling
# Usage: get_provider_ranking
get_provider_ranking() {
    local telemetry_file="${WORKSPACE_DIR:-.}/.octo/provider-telemetry.jsonl"
    local providers="codex gemini claude"

    if [[ ! -f "$telemetry_file" ]]; then
        echo "$providers"
        return 0
    fi

    local total_tasks
    total_tasks=$(wc -l < "$telemetry_file" 2>/dev/null | tr -d ' ')
    local fairness_threshold=$((total_tasks * 5 / 100))  # 5% floor
    [[ $fairness_threshold -lt 3 ]] && fairness_threshold=3

    local ranked=""
    for p in $providers; do
        local count
        count=$(grep -c "\"provider\":\"$p\"" "$telemetry_file" 2>/dev/null || echo 0)
        local score
        score=$(get_provider_score "$p")

        # Boost score for undersampled providers (fairness floor)
        if [[ $count -lt $fairness_threshold && $total_tasks -gt 20 ]]; then
            score="0.99"  # Force to top for sampling
        fi

        ranked+="$score $p\n"
    done

    echo -e "$ranked" | sort -rn | awk '{print $2}' | tr '\n' ' ' | sed 's/ $//'
}

# Get agent win rate for a specific agent+task_type pair
# Usage: get_agent_win_rate <agent_type> <task_type>
get_agent_win_rate() {
    local agent_type="$1"
    local task_type="$2"
    local telemetry_file="${WORKSPACE_DIR:-.}/.octo/provider-telemetry.jsonl"

    [[ -f "$telemetry_file" ]] || { echo ""; return 0; }

    local successes failures
    successes=$(grep "\"agent\":\"$agent_type\"" "$telemetry_file" 2>/dev/null | grep "\"task_type\":\"$task_type\"" | grep -c '"outcome":"success"' || echo 0)
    failures=$(grep "\"agent\":\"$agent_type\"" "$telemetry_file" 2>/dev/null | grep "\"task_type\":\"$task_type\"" | grep -c -E '"outcome":"(fail|timeout)"' || echo 0)

    local total=$((successes + failures))
    [[ $total -lt 5 ]] && { echo ""; return 0; }

    echo $((successes * 100 / total))
}

# Suggest a routing override based on historical performance
# Returns best agent if confident, empty string otherwise
# Usage: suggest_routing_override <agent_type> <task_type> <phase>
suggest_routing_override() {
    local current_agent="$1"
    local task_type="$2"
    local phase="$3"
    local telemetry_file="${WORKSPACE_DIR:-.}/.octo/provider-telemetry.jsonl"

    [[ -f "$telemetry_file" ]] || { echo ""; return 0; }

    local current_rate
    current_rate=$(get_agent_win_rate "$current_agent" "$task_type")

    # Find all agents that have handled this task type
    local best_agent="" best_rate=0
    local agents
    agents=$(grep "\"task_type\":\"$task_type\"" "$telemetry_file" 2>/dev/null | grep -o '"agent":"[^"]*"' | sort -u | sed 's/"agent":"//;s/"//')

    for agent in $agents; do
        [[ "$agent" == "$current_agent" ]] && continue
        local rate
        rate=$(get_agent_win_rate "$agent" "$task_type")
        [[ -z "$rate" ]] && continue
        [[ $rate -ge 60 && $rate -gt $best_rate ]] && { best_rate=$rate; best_agent="$agent"; }
    done

    # Only suggest override if 20%+ improvement
    if [[ -n "$best_agent" && -n "$current_rate" && $best_rate -gt $((current_rate + 20)) ]]; then
        echo "$best_agent"
    elif [[ -n "$best_agent" && -z "$current_rate" && $best_rate -ge 60 ]]; then
        echo "$best_agent"
    else
        echo ""
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# SMART COST ROUTING (Commit 2 — F4+F13 merged)
# 3-tier cost routing with built-in trivial task fast path
# ═══════════════════════════════════════════════════════════════════════════════

# Detect trivial tasks that can be handled without LLM agents
# Returns: "trivial" or "standard"
# Usage: detect_trivial_task <prompt>
detect_trivial_task() {
    local prompt="$1"
    local prompt_lower
    prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')

    # Deterministic pattern matching for trivial operations
    if [[ "$prompt_lower" =~ ^(fix|correct)[[:space:]]+(the[[:space:]]+)?typo ]]; then
        echo "trivial"; return 0
    fi
    if [[ "$prompt_lower" =~ ^rename[[:space:]]+[a-zA-Z_]+[[:space:]]+(to|->)[[:space:]]+[a-zA-Z_]+$ ]]; then
        echo "trivial"; return 0
    fi
    if [[ "$prompt_lower" =~ ^(add|insert)[[:space:]]+import[[:space:]] ]]; then
        echo "trivial"; return 0
    fi
    if [[ "$prompt_lower" =~ ^remove[[:space:]]+(the[[:space:]]+)?unused[[:space:]]+(import|variable) ]]; then
        echo "trivial"; return 0
    fi
    if [[ "$prompt_lower" =~ ^(update|bump|change)[[:space:]]+(the[[:space:]]+)?version[[:space:]]+(to|from) ]]; then
        echo "trivial"; return 0
    fi
    if [[ "$prompt_lower" =~ ^change[[:space:]]+[\"\'a-zA-Z_]+[[:space:]]+(to|->)[[:space:]]+[\"\'a-zA-Z_]+$ ]]; then
        echo "trivial"; return 0
    fi

    echo "standard"
}

# Handle a trivial task locally without spawning LLM agents
# Returns structured suggestion for Claude Code to execute
# Usage: handle_trivial_task <prompt>
handle_trivial_task() {
    local prompt="$1"

    log "INFO" "Trivial task detected -- handling locally (no LLM cost)" 2>/dev/null || true

    echo ""
    echo "Fast path: No LLM agents needed for this task."
    echo ""
    echo "Suggested action:"
    echo "  $prompt"
    echo ""
    echo "This task can be handled directly by Claude Code without external providers."

    # Record outcome as instant success
    record_outcome "local" "fast-path" "trivial" "auto-route" "success" "0" 2>/dev/null || true
}

# Select cost-aware agent based on complexity and tier
# Usage: select_cost_aware_agent <agent_type> <complexity>
select_cost_aware_agent() {
    local agent_type="$1"
    local complexity="$2"
    local cost_tier="${OCTOPUS_COST_TIER:-balanced}"

    case "$cost_tier" in
        aggressive)
            case "$complexity" in
                0) echo "skip"; return 0 ;;
                1) echo "codex-spark" ;;
                2) echo "$agent_type" ;;
                3) echo "$agent_type" ;;
                *) echo "$agent_type" ;;
            esac
            ;;
        premium)
            # Always use the original (presumably best) agent
            echo "$agent_type"
            ;;
        balanced|*)
            case "$complexity" in
                0) echo "codex-spark" ;;
                *) echo "$agent_type" ;;
            esac
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# CAPABILITY MATCHING (Commit 3 — F9)
# YAML-based capability matching for agent selection
# ═══════════════════════════════════════════════════════════════════════════════

# Capability cache (populated on first access)
_CAPABILITY_CACHE_FILE=""

# Load agent capabilities from config.yaml
# Usage: load_agent_capabilities <agent_name>
load_agent_capabilities() {
    local agent_name="$1"
    local config_file="${PLUGIN_DIR:-}/agents/config.yaml"

    [[ -f "$config_file" ]] || { echo ""; return 0; }

    # Extract capabilities for the given agent
    # YAML parsing via awk: find agent block, extract capabilities line
    local caps
    caps=$(awk -v agent="$agent_name:" '
        $0 ~ "^  " agent { found=1; next }
        found && /^  [a-z]/ { found=0 }
        found && /capabilities:/ {
            gsub(/.*capabilities:[[:space:]]*\[/, "")
            gsub(/\].*/, "")
            gsub(/,/, " ")
            gsub(/[[:space:]]+/, " ")
            print
            exit
        }
    ' "$config_file" 2>/dev/null)

    echo "$caps"
}

# Extract task capabilities from a prompt
# Maps common keywords to capability names
# Usage: extract_task_capabilities <prompt>
extract_task_capabilities() {
    local prompt="$1"
    local prompt_lower
    prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')
    local caps=""

    [[ "$prompt_lower" =~ secur ]] && caps+="vulnerability-scanning owasp-compliance "
    [[ "$prompt_lower" =~ test ]] && caps+="test-writing coverage-analysis "
    [[ "$prompt_lower" =~ (api|endpoint|rest|graphql) ]] && caps+="api-design microservices "
    [[ "$prompt_lower" =~ (database|schema|sql|migration) ]] && caps+="schema-design query-optimization "
    [[ "$prompt_lower" =~ (frontend|react|css|ui|ux) ]] && caps+="react css accessibility "
    [[ "$prompt_lower" =~ (performance|optimize|latency|speed) ]] && caps+="query-optimization scalability profiling "
    [[ "$prompt_lower" =~ (deploy|ci.?cd|kubernetes|docker) ]] && caps+="ci-cd kubernetes docker "
    [[ "$prompt_lower" =~ (debug|error|fix|bug) ]] && caps+="error-analysis stack-traces debugging "
    [[ "$prompt_lower" =~ (python|django|fastapi) ]] && caps+="python fastapi django "
    [[ "$prompt_lower" =~ (typescript|node|react) ]] && caps+="typescript node react "
    [[ "$prompt_lower" =~ (architect|design|system) ]] && caps+="api-design system-design scalability "
    [[ "$prompt_lower" =~ (llm|ai|prompt|rag) ]] && caps+="llm-applications rag-systems prompt-engineering "
    [[ "$prompt_lower" =~ (document|docs|readme) ]] && caps+="documentation technical-writing "

    # Deduplicate
    echo "$caps" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

# Score capability match between an agent and task
# Returns 0-100 score
# Usage: score_capability_match <agent_name> <task_capabilities>
score_capability_match() {
    local agent_name="$1"
    local task_caps="$2"

    [[ -z "$task_caps" ]] && { echo "0"; return 0; }

    local agent_caps
    agent_caps=$(load_agent_capabilities "$agent_name")
    [[ -z "$agent_caps" ]] && { echo "0"; return 0; }

    # Compute intersection
    local task_count=0 match_count=0
    for cap in $task_caps; do
        ((task_count++))
        for acap in $agent_caps; do
            if [[ "$cap" == "$acap" ]]; then
                ((match_count++))
                break
            fi
        done
    done

    [[ $task_count -eq 0 ]] && { echo "0"; return 0; }
    echo $((match_count * 100 / task_count))
}

# Find the best capability match among all agents for a phase
# Returns agent name or empty string
# Usage: find_best_capability_match <task_capabilities> <phase>
find_best_capability_match() {
    local task_caps="$1"
    local phase="$2"
    local config_file="${PLUGIN_DIR:-}/agents/config.yaml"

    [[ -f "$config_file" ]] || { echo ""; return 0; }
    [[ -z "$task_caps" ]] && { echo ""; return 0; }

    local best_agent="" best_score=0

    # Get all agent names from config
    local agents
    agents=$(grep -E '^  [a-z][a-z0-9_-]+:$' "$config_file" 2>/dev/null | sed 's/://;s/^  //')

    for agent in $agents; do
        # Check if agent has capabilities defined
        local caps
        caps=$(load_agent_capabilities "$agent")
        [[ -z "$caps" ]] && continue

        # Check phase affinity if phase is specified
        if [[ -n "$phase" ]]; then
            local phases
            phases=$(awk -v agent="$agent:" '
                $0 ~ "^  " agent { found=1; next }
                found && /^  [a-z]/ { found=0 }
                found && /phases:/ { print; exit }
            ' "$config_file" 2>/dev/null)
            [[ -n "$phase" && -n "$phases" && ! "$phases" =~ $phase ]] && continue
        fi

        local score
        score=$(score_capability_match "$agent" "$task_caps")
        if [[ $score -gt $best_score && $score -ge 40 ]]; then
            best_score=$score
            best_agent="$agent"
        fi
    done

    echo "$best_agent"
}

# ═══════════════════════════════════════════════════════════════════════════════
# QUORUM CONSENSUS (Commit 4 — F8 simplified)
# Two modes: moderator (default) and quorum (2/3 wins)
# ═══════════════════════════════════════════════════════════════════════════════

# Extract significant keywords from text (filters stop words)
# Usage: extract_keywords <text> [max_count]
extract_keywords() {
    local text="$1"
    local max_count="${2:-20}"

    echo "$text" | tr '[:upper:]' '[:lower:]' | \
        tr -cs '[:alpha:]' '\n' | \
        grep -vxE '(the|a|an|is|are|was|were|to|for|in|on|of|and|or|but|with|that|this|it|not|be|have|has|had|do|does|did|will|would|could|should|can|may|from|by|at|as|if|then|than|so|no|yes|all|each|every|both|few|more|most|other|some|such|only|just|also|very|often|still|already|even|how|what|when|where|why|which|who|about|after|before|between|during|into|through|under|over|above|below|up|down|out|off|again|further|been|being|here|there|its|my|your|our|their|his|her|we|they|you|he|she|me|him|them|us|i)' | \
        sort | uniq -c | sort -rn | \
        head -n "$max_count" | awk '{print $2}'
}

# Detect agreement level between three outputs
# Returns: "agree", "partial", or "disagree"
# Usage: detect_agreement <output_a> <output_b> <output_c>
detect_agreement() {
    local output_a="${1:0:500}"
    local output_b="${2:0:500}"
    local output_c="${3:0:500}"

    local kw_a kw_b kw_c
    kw_a=$(extract_keywords "$output_a" 15)
    kw_b=$(extract_keywords "$output_b" 15)
    kw_c=$(extract_keywords "$output_c" 15)

    # Compute pairwise overlap
    local overlap_ab overlap_ac overlap_bc
    overlap_ab=$(_keyword_overlap "$kw_a" "$kw_b")
    overlap_ac=$(_keyword_overlap "$kw_a" "$kw_c")
    overlap_bc=$(_keyword_overlap "$kw_b" "$kw_c")

    local agree_count=0
    [[ $overlap_ab -ge 60 ]] && ((agree_count++))
    [[ $overlap_ac -ge 60 ]] && ((agree_count++))
    [[ $overlap_bc -ge 60 ]] && ((agree_count++))

    case $agree_count in
        3) echo "agree" ;;
        2|1) echo "partial" ;;
        0) echo "disagree" ;;
    esac
}

# Internal: compute keyword overlap percentage
_keyword_overlap() {
    local kw_a="$1"
    local kw_b="$2"

    local count_a=0 matches=0
    for word in $kw_a; do
        ((count_a++))
        for other in $kw_b; do
            if [[ "$word" == "$other" ]]; then
                ((matches++))
                break
            fi
        done
    done

    local count_b=0
    for word in $kw_b; do ((count_b++)); done

    local union=$((count_a + count_b - matches))
    [[ $union -eq 0 ]] && { echo "0"; return 0; }

    echo $((matches * 100 / union))
}

# Resolve by quorum: find the two most similar outputs, use the longer one
# Usage: resolve_by_quorum <output_a> <output_b> <output_c>
resolve_by_quorum() {
    local output_a="$1"
    local output_b="$2"
    local output_c="$3"

    local kw_a kw_b kw_c
    kw_a=$(extract_keywords "$output_a" 20)
    kw_b=$(extract_keywords "$output_b" 20)
    kw_c=$(extract_keywords "$output_c" 20)

    local overlap_ab overlap_ac overlap_bc
    overlap_ab=$(_keyword_overlap "$kw_a" "$kw_b")
    overlap_ac=$(_keyword_overlap "$kw_a" "$kw_c")
    overlap_bc=$(_keyword_overlap "$kw_b" "$kw_c")

    # Find highest overlap pair
    local winner dissenter
    if [[ $overlap_ab -ge $overlap_ac && $overlap_ab -ge $overlap_bc ]]; then
        # A and B agree most — C dissents
        dissenter="C"
        local len_a=${#output_a} len_b=${#output_b}
        [[ $len_a -ge $len_b ]] && winner="$output_a" || winner="$output_b"
    elif [[ $overlap_ac -ge $overlap_ab && $overlap_ac -ge $overlap_bc ]]; then
        # A and C agree most — B dissents
        dissenter="B"
        local len_a=${#output_a} len_c=${#output_c}
        [[ $len_a -ge $len_c ]] && winner="$output_a" || winner="$output_c"
    else
        # B and C agree most — A dissents
        dissenter="A"
        local len_b=${#output_b} len_c=${#output_c}
        [[ $len_b -ge $len_c ]] && winner="$output_b" || winner="$output_c"
    fi

    log "WARN" "Quorum: participant $dissenter dissented (overlap: AB=$overlap_ab% AC=$overlap_ac% BC=$overlap_bc%)" 2>/dev/null || true

    echo "$winner"
}

# Apply consensus mode to resolve 3 outputs
# Usage: apply_consensus <mode> <output_a> <output_b> <output_c> <prompt>
apply_consensus() {
    local mode="$1"
    local output_a="$2"
    local output_b="$3"
    local output_c="$4"
    local prompt="$5"

    log "INFO" "Consensus mode: $mode" 2>/dev/null || true

    case "$mode" in
        quorum)
            resolve_by_quorum "$output_a" "$output_b" "$output_c"
            ;;
        moderator|*)
            # Default: return all outputs for Claude to synthesize (existing behavior)
            # The caller handles synthesis
            echo "MODERATOR_MODE"
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# BASELINE TELEMETRY (v8.20.1)
# Lightweight usage metrics for measuring intelligence feature impact
# ═══════════════════════════════════════════════════════════════════════════════

# Record a task metric
# Usage: record_task_metric <metric_name> <value>
record_task_metric() {
    local metric_name="$1"
    local value="$2"

    [[ "${OCTOPUS_PROVIDER_INTELLIGENCE:-shadow}" == "off" ]] && return 0

    local metrics_file="${WORKSPACE_DIR:-.}/.octo/metrics.jsonl"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +%s)
    local session_id="${CLAUDE_CODE_SESSION:-unknown}"

    local entry
    if _intelligence_has_jq; then
        entry=$(jq -n -c \
            --arg m "$metric_name" \
            --arg v "$value" \
            --arg ts "$timestamp" \
            --arg s "$session_id" \
            '{metric:$m, value:$v, timestamp:$ts, session:$s}' 2>/dev/null)
    else
        entry="{\"metric\":\"$metric_name\",\"value\":\"$value\",\"timestamp\":\"$timestamp\",\"session\":\"$session_id\"}"
    fi

    octo_db_append "$metrics_file" "$entry" 1000
}

# Get summary statistics for a metric within a time window
# Returns: count sum min max avg (space-separated)
# Usage: get_metric_summary <metric_name> [window_hours]
get_metric_summary() {
    local metric_name="$1"
    local window_hours="${2:-24}"
    local metrics_file="${WORKSPACE_DIR:-.}/.octo/metrics.jsonl"
    local default="0 0 0 0 0"

    [[ -f "$metrics_file" ]] || { echo "$default"; return 0; }

    # Extract matching metric values
    local values
    values=$(grep "\"metric\":\"$metric_name\"" "$metrics_file" 2>/dev/null | \
        grep -o '"value":"[^"]*"' | sed 's/"value":"//;s/"//' | \
        grep -E '^[0-9]+\.?[0-9]*$')

    [[ -z "$values" ]] && { echo "$default"; return 0; }

    # Compute stats using awk
    echo "$values" | awk '
        BEGIN { count=0; sum=0; min=999999999; max=0 }
        {
            count++; sum+=$1
            if ($1 < min) min=$1
            if ($1 > max) max=$1
        }
        END {
            if (count > 0) {
                printf "%d %d %d %d %d", count, sum, min, max, int(sum/count)
            } else {
                print "0 0 0 0 0"
            }
        }
    '
}

# ═══════════════════════════════════════════════════════════════════════════════
# ANTI-DRIFT CHECKPOINTS (v8.21.0 — F3 simplified)
# Lightweight output validation using heuristic checks
# Ships as warnings only — never blocks, discards, or modifies output
# ═══════════════════════════════════════════════════════════════════════════════

# Check if agent output has drifted from the prompt intent
# Returns: "ok", "warn:<reason>", or "drift:<reason>"
# Usage: check_output_drift <prompt> <output> <agent_type>
check_output_drift() {
    local prompt="$1"
    local output="$2"
    local agent_type="$3"

    local output_len=${#output}

    # Length check: flag suspiciously short or extremely long outputs
    if [[ $output_len -lt 50 ]]; then
        echo "warn:output_too_short (${output_len} chars)"
        return 0
    fi
    if [[ $output_len -gt 50000 ]]; then
        echo "warn:output_too_long (${output_len} chars)"
        return 0
    fi

    # Refusal detection
    local output_start
    output_start=$(echo "${output:0:100}" | tr '[:upper:]' '[:lower:]')
    if [[ "$output_start" =~ ^(i\ cannot|i\'m\ sorry|i\ can\'t|as\ an\ ai|i\ apologize) ]]; then
        echo "drift:agent_refusal"
        return 0
    fi

    # Key term presence: extract significant words from prompt, check output
    local prompt_lower
    prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')
    local output_lower
    output_lower=$(echo "${output:0:2000}" | tr '[:upper:]' '[:lower:]')

    local key_terms
    key_terms=$(echo "$prompt_lower" | tr -cs '[:alpha:]' '\n' | \
        grep -vxE '(the|a|an|is|are|was|were|to|for|in|on|of|and|or|but|with|that|this|it|not|be|have|do|will|would|could|should|can|may|from|by|at|as|if|then|than|so|no|yes|all|each|every|some|such|only|just|also|very|how|what|when|where|why|which|who|about|please|make|use|create|add|get|set|run|check|help|want|need)' | \
        sort | uniq | head -8)

    local key_count=0 found_count=0
    for term in $key_terms; do
        [[ ${#term} -lt 3 ]] && continue
        ((key_count++))
        if [[ "$output_lower" == *"$term"* ]]; then
            ((found_count++))
        fi
    done

    # If we have 4+ key terms and less than 25% appear in output, flag it
    if [[ $key_count -ge 4 && $found_count -lt $((key_count / 4 + 1)) ]]; then
        echo "warn:low_key_term_overlap ($found_count/$key_count terms)"
        return 0
    fi

    echo "ok"
}

# Run drift check on agent output (non-blocking)
# Usage: run_drift_check <prompt> <output> <agent_type> <phase>
run_drift_check() {
    local prompt="$1"
    local output="$2"
    local agent_type="$3"
    local phase="$4"

    [[ "${OCTOPUS_ANTI_DRIFT:-warn}" == "off" ]] && return 0

    local result
    result=$(check_output_drift "$prompt" "$output" "$agent_type")

    case "$result" in
        ok)
            log "DEBUG" "Drift check passed for $agent_type" 2>/dev/null || true
            ;;
        warn:*)
            local reason="${result#warn:}"
            log "WARN" "Drift warning for $agent_type: $reason" 2>/dev/null || true
            record_task_metric "drift_warning" "1" 2>/dev/null || true
            ;;
        drift:*)
            local reason="${result#drift:}"
            log "ERROR" "Drift detected in $agent_type: $reason" 2>/dev/null || true
            record_task_metric "drift_detected" "1" 2>/dev/null || true
            ;;
    esac

    return 0  # Always non-blocking
}

# ═══════════════════════════════════════════════════════════════════════════════
# FILE PATH VALIDATION (Commit 5 — F15 simplified)
# Non-blocking warnings for nonexistent file references
# ═══════════════════════════════════════════════════════════════════════════════

# Check file references in agent output
# Returns list of nonexistent files (space-separated)
# Usage: check_file_references <output> [project_root]
check_file_references() {
    local output="$1"
    local project_root="${2:-${PROJECT_ROOT:-.}}"

    # Extract file paths from output (common patterns)
    local paths
    paths=$(echo "$output" | grep -oE '(src|lib|app|test|tests|pkg|cmd|internal|scripts|config|public|assets|components|pages|utils|hooks|services|models|controllers|routes|middleware|api)/[a-zA-Z0-9_./-]+\.[a-zA-Z]{1,5}' | head -50 | sort -u)

    # Also check explicit ./ paths
    local dot_paths
    dot_paths=$(echo "$output" | grep -oE '\./[a-zA-Z0-9_./-]+\.[a-zA-Z]{1,5}' | head -20 | sort -u)

    local all_paths="$paths"$'\n'"$dot_paths"
    local missing=""
    local count=0

    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        ((count++))
        [[ $count -gt 50 ]] && break  # Safety limit

        # Strip leading ./
        path="${path#./}"

        if [[ ! -f "$project_root/$path" ]]; then
            missing+="$path "
        fi
    done <<< "$all_paths"

    echo "$missing" | sed 's/ $//'
}

# Run file validation on agent output (non-blocking)
# Usage: run_file_validation <agent_type> <output>
run_file_validation() {
    local agent_type="$1"
    local output="$2"

    [[ "${OCTOPUS_FILE_VALIDATION:-true}" == "false" ]] && return 0

    local missing
    missing=$(check_file_references "$output")

    if [[ -n "$missing" ]]; then
        local count
        count=$(echo "$missing" | wc -w | tr -d ' ')
        log "WARN" "Agent $agent_type referenced $count nonexistent file(s): $missing" 2>/dev/null || true
    else
        log "DEBUG" "Agent $agent_type file references validated" 2>/dev/null || true
    fi
}
