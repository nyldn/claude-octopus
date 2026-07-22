#!/usr/bin/env bash
# quality.sh — Quality gates, scoring, branching, provider lockout, and ceremonies
# Contains: evaluate_branch_condition, get_branch_display, evaluate_quality_branch,
#           execute_quality_branch, lock_provider, is_provider_locked, get_alternate_provider,
#           reset_provider_lockouts, append_provider_history, read_provider_history,
#           build_provider_context, write_structured_decision, design_review_ceremony,
#           retrospective_ceremony, detect_response_mode, get_gate_threshold,
#           score_importance, search_observations, search_similar_errors, flag_repeat_error,
#           score_cross_model_review, format_review_scorecard, get_cross_model_reviewer
# Extracted from orchestrate.sh (v9.7.8)
# Source-safe: no main execution block.


# ═══════════════════════════════════════════════════════════════════════════════
# CONDITIONAL BRANCHING - Tentacle path selection based on task analysis
# Enables decision trees for workflow routing
# ═══════════════════════════════════════════════════════════════════════════════

# Evaluate which tentacle path to extend
# Returns: premium, standard, fast, or custom branch name
evaluate_branch_condition() {
    local task_type="$1"
    local complexity="$2"
    local custom_condition="${3:-}"

    # Check for user-specified branch override
    if [[ -n "$FORCE_BRANCH" ]]; then
        echo "$FORCE_BRANCH"
        return
    fi

    # Default branching logic based on task type + complexity
    case "$complexity" in
        3)  # Complex tasks → premium tentacle
            case "$task_type" in
                coding|review|design|diamond-*) echo "premium" ;;
                *) echo "standard" ;;
            esac
            ;;
        1)  # Trivial tasks → fast tentacle
            echo "fast"
            ;;
        *)  # Standard tasks → standard tentacle
            echo "standard"
            ;;
    esac
}

# Get display name for branch
get_branch_display() {
    local branch="$1"
    case "$branch" in
        premium) echo "premium (🐙 all providers)" ;;
        standard) echo "standard (🐙 balanced)" ;;
        fast) echo "fast (🐙 minimal)" ;;
        *) echo "$branch" ;;
    esac
}

quality_retries_unlimited() {
    local retry_limit="${MAX_QUALITY_RETRIES:-3}"
    retry_limit="$(printf '%s' "$retry_limit" | tr '[:upper:]' '[:lower:]')"
    case "$retry_limit" in
        unlimited|infinite|inf|forever|-1) return 0 ;;
        *) return 1 ;;
    esac
}

quality_retry_limit() {
    if quality_retries_unlimited; then
        printf '∞\n'
        return 0
    fi
    if [[ "${MAX_QUALITY_RETRIES:-}" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$MAX_QUALITY_RETRIES"
    else
        printf '3\n'
    fi
}

quality_retry_limit_reached() {
    local retry_count="${1:-0}"
    local retry_limit
    if quality_retries_unlimited; then
        return 1
    fi
    retry_limit=$(quality_retry_limit)
    [[ "$retry_count" -ge "$retry_limit" ]]
}

# Evaluate next action based on quality gate outcome
# Returns: proceed, proceed_warn, retry, escalate, abort
evaluate_quality_branch() {
    local success_rate="$1"
    local retry_count="${2:-0}"
    local autonomy="${3:-$AUTONOMY_MODE}"

    # Check for explicit on-fail override
    if [[ "$ON_FAIL_ACTION" != "auto" && $success_rate -lt $QUALITY_THRESHOLD ]]; then
        case "$ON_FAIL_ACTION" in
            retry) echo "retry" ;;
            escalate) echo "escalate" ;;
            abort) echo "abort" ;;
        esac
        return
    fi

    # Auto-determine action based on success rate and settings
    if [[ $success_rate -ge 90 ]]; then
        echo "proceed"  # Quality gate passed
    elif [[ $success_rate -ge $QUALITY_THRESHOLD ]]; then
        echo "proceed_warn"  # Passed with warning
    elif [[ "$LOOP_UNTIL_APPROVED" == "true" ]] && ! quality_retry_limit_reached "$retry_count"; then
        echo "retry"  # Auto-retry enabled
    elif [[ "$autonomy" == "supervised" ]]; then
        echo "escalate"  # Human decision required
    else
        echo "abort"  # Failed, no retry
    fi
}

# Execute action based on quality gate branch decision
execute_quality_branch() {
    local branch="$1"
    local task_group="$2"
    local retry_count="${3:-0}"

    echo ""
    echo -e "${MAGENTA}┌${_DASH}┐${NC}"
    echo -e "${MAGENTA}│  Quality Gate Decision: ${YELLOW}${branch}${MAGENTA}                              │${NC}"
    echo -e "${MAGENTA}└${_DASH}┘${NC}"
    echo ""

    case "$branch" in
        proceed)
            log INFO "✓ Quality gate PASSED - proceeding to delivery"
            return 0
            ;;
        proceed_warn)
            log WARN "⚠ Quality gate PASSED with warnings - proceeding cautiously"
            return 0
            ;;
        retry)
            log INFO "↻ Quality gate FAILED - retrying (attempt $((retry_count + 1))/$(quality_retry_limit))"
            return 2  # Signal retry
            ;;
        escalate)
            log WARN "⚡ Quality gate FAILED - escalating to human review"
            echo ""
            echo -e "${YELLOW}Manual review required. Results at: ${RESULTS_DIR}/tangle-validation-${task_group}.md${NC}"
            # Claude Code v2.1.9: CI mode auto-fails on escalation
            if [[ "$CI_MODE" == "true" ]]; then
                log ERROR "CI mode: Quality gate FAILED - aborting (no human review available)"
                echo "::error::Quality gate failed - manual review required"
                return 1
            fi
            read -p "Continue anyway? (y/n) " -n 1 -r
            echo
            [[ $REPLY =~ ^[Yy]$ ]] && return 0 || return 1
            ;;
        abort)
            log ERROR "✗ Quality gate FAILED - aborting workflow"
            return 1
            ;;
        *)
            log ERROR "Unknown quality branch: $branch"
            return 1
            ;;
    esac
}

# Default settings
MAX_PARALLEL=3
TIMEOUT=600  # v7.20.1: Increased from 300s (5min) to 600s (10min) for better probe reliability (~25% -> 95% success rate)
VERBOSE=false
DRY_RUN=false
SKIP_SMOKE_TEST="${OCTOPUS_SKIP_SMOKE_TEST:-false}"

# v3.0 Feature: Autonomy Modes & Quality Control
# - autonomous: Full auto, proceed on failures
# - semi-autonomous: Auto with quality gates (default)
# - supervised: Human approval required after each phase
# - loop-until-approved: Retry failed tasks until quality gate passes
AUTONOMY_MODE="${CLAUDE_OCTOPUS_AUTONOMY:-semi-autonomous}"
QUALITY_THRESHOLD="${CLAUDE_OCTOPUS_QUALITY_THRESHOLD:-75}"
MAX_QUALITY_RETRIES="${MAX_QUALITY_RETRIES:-${CLAUDE_OCTOPUS_MAX_RETRIES:-3}}"
LOOP_UNTIL_APPROVED="${LOOP_UNTIL_APPROVED:-false}"
RESUME_SESSION=false

# v3.1 Feature: Cost-Aware Routing
# Complexity tiers: trivial (1), standard (2), complex/premium (3)
FORCE_TIER=""  # "", "trivial", "standard", "premium"

# v3.2 Feature: Conditional Branching
# Tentacle paths for workflow routing based on conditions
FORCE_BRANCH=""           # "", "premium", "standard", "fast"
ON_FAIL_ACTION="auto"     # "auto", "retry", "escalate", "abort"
CURRENT_BRANCH=""         # Tracks current branch for session recovery

# v3.3 Feature: Agent Personas
# Inject specialized system instructions into agent prompts
DISABLE_PERSONAS="${CLAUDE_OCTOPUS_DISABLE_PERSONAS:-false}"

# Session recovery
SESSION_FILE="${WORKSPACE_DIR}/session.json"

# v8.18.0 Feature: Sentinel Work Monitor
# GitHub-aware work monitor that triages issues/PRs/CI failures
OCTOPUS_SENTINEL_ENABLED="${OCTOPUS_SENTINEL_ENABLED:-false}"
OCTOPUS_SENTINEL_INTERVAL="${OCTOPUS_SENTINEL_INTERVAL:-600}"

# v8.18.0 Feature: Response Mode Auto-Tuning
OCTOPUS_RESPONSE_MODE="${OCTOPUS_RESPONSE_MODE:-auto}"

# v8.18.0 Feature: Pre-Work Design Review Ceremony
OCTOPUS_CEREMONIES="${OCTOPUS_CEREMONIES:-true}"

# v8.19.0 Feature: Configurable Quality Gate Thresholds (Veritas-inspired)
# Per-phase env vars override the global QUALITY_THRESHOLD
OCTOPUS_GATE_PROBE="${OCTOPUS_GATE_PROBE:-50}"
OCTOPUS_GATE_GRASP="${OCTOPUS_GATE_GRASP:-75}"
OCTOPUS_GATE_TANGLE="${OCTOPUS_GATE_TANGLE:-75}"
OCTOPUS_GATE_INK="${OCTOPUS_GATE_INK:-80}"
OCTOPUS_GATE_SECURITY="${OCTOPUS_GATE_SECURITY:-100}"

# v8.19.0 Feature: Cross-Model Review Scoring (4x10)
OCTOPUS_REVIEW_4X10="${OCTOPUS_REVIEW_4X10:-false}"

# v8.19.0 Feature: Agent Heartbeat & Dynamic Timeout
OCTOPUS_AGENT_TIMEOUT="${OCTOPUS_AGENT_TIMEOUT:-}"

# v8.19.0 Feature: Tool Policy RBAC for Personas
OCTOPUS_TOOL_POLICIES="${OCTOPUS_TOOL_POLICIES:-true}"

# v8.20.0 Feature: Provider Intelligence (shadow = log only, active = influences routing, off = disabled)
OCTOPUS_PROVIDER_INTELLIGENCE="${OCTOPUS_PROVIDER_INTELLIGENCE:-shadow}"

# v8.20.0 Feature: Smart Cost Routing (aggressive/balanced/premium)
OCTOPUS_COST_TIER="${OCTOPUS_COST_TIER:-balanced}"

# v8.20.0 Feature: Consensus Mode (moderator = current behavior, quorum = 2/3 wins)
OCTOPUS_CONSENSUS="${OCTOPUS_CONSENSUS:-moderator}"

# v8.20.0 Feature: File Path Validation (non-blocking warnings)
OCTOPUS_FILE_VALIDATION="${OCTOPUS_FILE_VALIDATION:-true}"

# v8.21.0 Feature: Anti-Drift Checkpoints (heuristic output validation, warnings only)
OCTOPUS_ANTI_DRIFT="${OCTOPUS_ANTI_DRIFT:-warn}"

# v8.21.0 Feature: Persona Packs (community persona customization)
OCTOPUS_PERSONA_PACKS="${OCTOPUS_PERSONA_PACKS:-auto}"

# v8.25.0 Feature: Dark Factory Mode (spec-in, software-out autonomous pipeline)
OCTOPUS_FACTORY_MODE="${OCTOPUS_FACTORY_MODE:-false}"
OCTOPUS_FACTORY_HOLDOUT_RATIO="${OCTOPUS_FACTORY_HOLDOUT_RATIO:-0.20}"
OCTOPUS_FACTORY_MAX_RETRIES="${OCTOPUS_FACTORY_MAX_RETRIES:-1}"
OCTOPUS_FACTORY_SATISFACTION_TARGET="${OCTOPUS_FACTORY_SATISFACTION_TARGET:-}"

# v8.18.0 Feature: Reviewer Lockout Protocol
# When a provider's output is rejected during quality gates,
# lock it out from self-revision and route retries to an alternate provider.
LOCKED_PROVIDERS=""

lock_provider() {
    local provider="$1"
    # v9.5: bash builtin word check (zero subshells)
    if [[ " $LOCKED_PROVIDERS " != *" $provider "* ]]; then
        LOCKED_PROVIDERS="${LOCKED_PROVIDERS:+$LOCKED_PROVIDERS }$provider"
        log WARN "Provider locked out: $provider (will not self-revise)"
    fi
}

is_provider_locked() {
    local provider="$1"
    [[ " $LOCKED_PROVIDERS " == *" $provider "* ]]
}

get_alternate_provider() {
    local locked_provider="$1"
    case "$locked_provider" in
        codex|codex-fast|codex-mini)
            if ! is_provider_locked "agy"; then
                echo "agy"
            elif ! is_provider_locked "claude-sonnet"; then
                echo "claude-sonnet"
            else
                echo "$locked_provider"  # All locked, use original
            fi
            ;;
        agy|agy-research|antigravity)
            if ! is_provider_locked "codex"; then
                echo "codex"
            elif ! is_provider_locked "claude-sonnet"; then
                echo "claude-sonnet"
            else
                echo "$locked_provider"
            fi
            ;;
        claude-sonnet|claude*)
            if ! is_provider_locked "codex"; then
                echo "codex"
            elif ! is_provider_locked "agy"; then
                echo "agy"
            else
                echo "$locked_provider"
            fi
            ;;
        *)
            echo "$locked_provider"
            ;;
    esac
}

reset_provider_lockouts() {
    if [[ -n "$LOCKED_PROVIDERS" ]]; then
        log INFO "Resetting provider lockouts (were: $LOCKED_PROVIDERS)"
    fi
    LOCKED_PROVIDERS=""
}

# v8.18.0 Feature: Per-Provider History Files
# Each provider accumulates project-specific knowledge in .octo/providers/{name}-history.md

append_provider_history() {
    case "${OCTOPUS_PROVIDER_HISTORY:-on}" in
        off|false|0|no) return 0 ;;
    esac

    local provider="$1"
    local phase="$2"
    local task_brief="$3"
    local learned="$4"

    local history_dir="${WORKSPACE_DIR}/.octo/providers"
    local history_file="$history_dir/${provider}-history.md"
    mkdir -p "$history_dir"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Append structured entry
    cat >> "$history_file" << HISTEOF
### ${phase} | ${timestamp}
**Task:** ${task_brief:0:100}
**Learned:** ${learned:0:200}
---
HISTEOF

    # Cap at 50 entries: count entries and trim oldest if exceeded
    local entry_count
    entry_count=$(grep -c "^### " "$history_file" 2>/dev/null || echo "0")
    if [[ "$entry_count" -gt 50 ]]; then
        local excess=$((entry_count - 50))
        # Remove oldest entries (from top of file)
        local trim_line
        trim_line=$(grep -n "^### " "$history_file" | sed -n "$((excess + 1))p" | cut -d: -f1)
        if [[ -n "$trim_line" && "$trim_line" -gt 1 ]]; then
            tail -n "+$trim_line" "$history_file" > "$history_file.tmp" && mv "$history_file.tmp" "$history_file"
        fi
    fi

    log DEBUG "Appended provider history for $provider (phase: $phase)"
}

read_provider_history() {
    case "${OCTOPUS_PROVIDER_HISTORY:-on}" in
        off|false|0|no) return 0 ;;
    esac

    local provider="$1"
    local history_file="${WORKSPACE_DIR}/.octo/providers/${provider}-history.md"

    if [[ -f "$history_file" ]]; then
        cat "$history_file"
    fi
}

build_provider_context() {
    local agent_type="$1"
    local base_provider="${agent_type%%-*}"  # codex-fast -> codex
    local history
    history=$(read_provider_history "$base_provider")

    if [[ -z "$history" ]]; then
        return
    fi

    # Truncate to max 2000 chars for prompt injection
    if [[ ${#history} -gt 2000 ]]; then
        history="${history:0:2000}..."
    fi

    echo "## Provider History (${base_provider})
Recent learnings from this project:
${history}"
}

# v8.18.0 Feature: Structured Decision Format
# Append-only .octo/decisions.md with structured, git-mergeable entries

write_structured_decision() {
    local type="$1"          # quality-gate | debate-synthesis | phase-completion | security-finding
    local source="$2"        # which function/phase generated this
    local summary="$3"       # one-line summary
    local scope="${4:-}"     # files/areas affected
    local confidence="${5:-medium}"  # low | medium | high
    local rationale="${6:-}" # why this decision was made
    local related="${7:-}"   # related decision IDs or refs
    local importance="${8:-}"  # v8.19.0: optional importance (1-10), auto-scored if empty

    local decisions_dir="${WORKSPACE_DIR}/.octo"
    local decisions_file="$decisions_dir/decisions.md"
    mkdir -p "$decisions_dir"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local decision_id
    decision_id="D-$(date +%s)-$$"

    # v8.19.0: Auto-score importance if not provided
    if [[ -z "$importance" ]]; then
        importance=$(score_importance "$type" "$confidence" "$scope")
    fi

    # Append structured entry (git-mergeable: append-only, no edits to existing lines)
    cat >> "$decisions_file" << DECEOF

### type: ${type} | timestamp: ${timestamp} | source: ${source}
**ID:** ${decision_id}
**Summary:** ${summary}
**Scope:** ${scope:-project-wide}
**Confidence:** ${confidence}
**Importance:** ${importance}
**Rationale:** ${rationale:-No rationale provided}
${related:+**Related:** ${related}}
---
DECEOF

    # v8.34.0: Companion JSONL for machine-queryable decisions (enables recurrence detection)
    local jsonl_file="$decisions_dir/decisions.jsonl"
    local safe_summary="${summary//\"/\\\"}"
    local safe_rationale="${rationale//\"/\\\"}"
    safe_rationale="${safe_rationale:-No rationale provided}"
    local safe_scope="${scope//\"/\\\"}"
    safe_scope="${safe_scope:-project-wide}"
    if ! echo "{\"id\":\"${decision_id}\",\"type\":\"${type}\",\"timestamp\":\"${timestamp}\",\"source\":\"${source}\",\"summary\":\"${safe_summary}\",\"scope\":\"${safe_scope}\",\"confidence\":\"${confidence}\",\"importance\":${importance}}" >> "$jsonl_file" 2>/dev/null; then
        log WARN "Failed to append decision $decision_id to $jsonl_file"
    fi

    log DEBUG "Recorded structured decision: $decision_id ($type from $source)"

    # Backward compat: also write to state.json via write_decision() if available
    if command -v write_decision &>/dev/null 2>&1; then
        write_decision "${source}" "${summary}" "${rationale:-$type}" 2>/dev/null || true
    fi
}

# v8.18.0 Feature: Pre-Work Design Review Ceremony
# Before tangle phase, each provider states its approach; conflicts are resolved.
# After failures, a retrospective fires.

design_review_ceremony() {
    local prompt="$1"
    local context="${2:-}"

    # Skip in dry-run or when ceremonies disabled
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would run design review ceremony"
        return 0
    fi
    if [[ "$OCTOPUS_CEREMONIES" != "true" ]]; then
        log DEBUG "Ceremonies disabled (OCTOPUS_CEREMONIES=$OCTOPUS_CEREMONIES)"
        return 0
    fi

    echo ""
    echo -e "${CYAN}${_BOX_TOP}${NC}"
    echo -e "${CYAN}║  📋 DESIGN REVIEW CEREMONY                               ║${NC}"
    echo -e "${CYAN}║  Each provider states their approach before implementation ║${NC}"
    echo -e "${CYAN}${_BOX_BOT}${NC}"
    echo ""

    local ceremony_prompt="You are participating in a design review ceremony before implementation begins.

Task: $prompt
${context:+Context: $context}

State your HIGH-LEVEL approach in 3-5 bullet points:
1. Architecture/pattern choice and why
2. Key dependencies or prerequisites
3. Risk areas and mitigation strategies
4. Testing approach
5. Integration considerations

Be concise and specific. This is a planning exercise, not implementation."

    # Configured review participants are the ceremony roster. Explicit legacy
    # environment overrides remain supported for operators who set them.
    local design_codex_agent="${OCTOPUS_DESIGN_REVIEW_CODEX_AGENT:-codex-mini}"
    local design_agy_agent="${OCTOPUS_DESIGN_REVIEW_AGY_AGENT:-${OCTOPUS_DESIGN_REVIEW_GEMINI_AGENT:-agy}}"
    local design_claude_agent="${OCTOPUS_DESIGN_REVIEW_CLAUDE_AGENT:-claude-opus}"
    local design_synthesis_agent="${OCTOPUS_DESIGN_REVIEW_SYNTH_AGENT:-claude-opus}"
    local design_timeout="${OCTOPUS_DESIGN_REVIEW_TIMEOUT:-0}"
    local design_synth_timeout="${OCTOPUS_DESIGN_REVIEW_SYNTH_TIMEOUT:-0}"
    local design_retries="${OCTOPUS_DESIGN_REVIEW_RETRIES:-1}"
    if [[ ! "$design_timeout" =~ ^[0-9]+$ ]]; then
        log WARN "Invalid OCTOPUS_DESIGN_REVIEW_TIMEOUT='${design_timeout}', defaulting to no wall timeout"
        design_timeout=0
    fi
    if [[ ! "$design_synth_timeout" =~ ^[0-9]+$ ]]; then
        log WARN "Invalid OCTOPUS_DESIGN_REVIEW_SYNTH_TIMEOUT='${design_synth_timeout}', defaulting to no wall timeout"
        design_synth_timeout=0
    fi
    if [[ ! "$design_retries" =~ ^[0-9]+$ ]]; then
        log WARN "Invalid OCTOPUS_DESIGN_REVIEW_RETRIES='${design_retries}', defaulting to 1"
        design_retries=1
    fi

    local _design_timeout_label="none"
    [[ "$design_timeout" != "0" ]] && _design_timeout_label="${design_timeout}s"
    local _synth_timeout_label="none"
    [[ "$design_synth_timeout" != "0" ]] && _synth_timeout_label="${design_synth_timeout}s"

    local design_fleet=""
    if [[ -n "${OCTOPUS_DESIGN_REVIEW_FLEET:-}" ]]; then
        design_fleet="$OCTOPUS_DESIGN_REVIEW_FLEET"
    elif [[ -n "${OCTOPUS_DESIGN_REVIEW_CODEX_AGENT:-}${OCTOPUS_DESIGN_REVIEW_AGY_AGENT:-}${OCTOPUS_DESIGN_REVIEW_GEMINI_AGENT:-}${OCTOPUS_DESIGN_REVIEW_CLAUDE_AGENT:-}" ]]; then
        design_fleet="${design_codex_agent}:implementer:implementation approach"$'\n'
        design_fleet+="${design_agy_agent}:researcher:independent architecture approach"$'\n'
        design_fleet+="${design_claude_agent}:code-reviewer:integration and risk approach"$'\n'
    elif declare -f build_review_fleet >/dev/null 2>&1; then
        design_fleet=$(build_review_fleet)
    fi
    if [[ -z "$design_fleet" ]]; then
        design_fleet="${design_codex_agent}:implementer:implementation approach"$'\n'
        design_fleet+="${design_agy_agent}:researcher:independent architecture approach"$'\n'
        design_fleet+="${design_claude_agent}:code-reviewer:integration and risk approach"$'\n'
    fi

    local design_agents=""
    local design_approaches=""
    local design_agent design_role design_specialty design_approach design_attempt design_succeeded
    while IFS=':' read -r design_agent design_role design_specialty; do
        design_agent=${design_agent//$'\r'/}
        [[ -z "$design_agent" ]] && continue
        design_role="${design_role:-code-reviewer}"
        design_agents+="${design_agents:+, }${design_agent}"
        design_approach=""
        design_succeeded=false
        for ((design_attempt = 0; design_attempt <= design_retries; design_attempt++)); do
            if design_approach=$(OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED="design-review-ceremony" run_agent_sync "$design_agent" "$ceremony_prompt" "$design_timeout" "$design_role" "ceremony" 2>/dev/null); then
                design_succeeded=true
                break
            fi
            if (( design_attempt < design_retries )); then
                log WARN "Design review provider $design_agent failed; retrying ($((design_attempt + 1))/$design_retries)"
            fi
        done
        if [[ "$design_succeeded" != "true" ]]; then
            log WARN "Design review provider $design_agent unavailable after $((design_retries + 1)) attempts"
        fi
        design_approaches+=$'\n\n'"${design_agent} APPROACH:"$'\n'"${design_approach:-[unavailable]}"
    done <<< "$design_fleet"

    log INFO "Design review: gathered configured provider approaches"
    log INFO "Design review agents: ${design_agents:-none}; synthesis=${design_synthesis_agent}, timeout=${_design_timeout_label}, synth_timeout=${_synth_timeout_label}"

    # Synthesize conflicts and resolution
    local synthesis
    synthesis=$(OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED="design-review-ceremony" run_agent_sync "$design_synthesis_agent" "You are synthesizing a design review ceremony.

The configured providers stated their approaches to this task:
${design_approaches:-[all providers unavailable]}

Identify:
1. CONFLICTS: Where do the approaches disagree?
2. GAPS: What did everyone miss?
3. RESOLUTION: The recommended unified approach (2-3 sentences)

Be brief and actionable." "$design_synth_timeout" "synthesizer" "ceremony" 2>/dev/null) || true

    if [[ -n "$synthesis" ]]; then
        echo -e "${GREEN}Design Review Summary:${NC}"
        echo "$synthesis" | head -20
        echo ""

        # Record outcome
        write_structured_decision \
            "phase-completion" \
            "design_review_ceremony" \
            "Design review completed for: ${prompt:0:60}" \
            "" \
            "medium" \
            "${synthesis:0:200}" \
            "" 2>/dev/null || true
    fi

    log INFO "Design review ceremony complete"
}

retrospective_ceremony() {
    local prompt="$1"
    local failure_context="${2:-}"

    # Skip in dry-run or when ceremonies disabled
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would run retrospective ceremony"
        return 0
    fi
    if [[ "$OCTOPUS_CEREMONIES" != "true" ]]; then
        log DEBUG "Ceremonies disabled"
        return 0
    fi

    echo ""
    echo -e "${YELLOW}${_BOX_TOP}${NC}"
    echo -e "${YELLOW}║  🔍 RETROSPECTIVE CEREMONY                               ║${NC}"
    echo -e "${YELLOW}║  Analyzing what went wrong and how to improve             ║${NC}"
    echo -e "${YELLOW}${_BOX_BOT}${NC}"
    echo ""

    local retro_prompt="Analyze this failure and provide root-cause analysis.

Original task: $prompt
Failure context: ${failure_context:-Quality gate failed during development phase}

Provide:
1. ROOT CAUSE: Why did this fail? (1-2 sentences)
2. CONTRIBUTING FACTORS: What made it worse?
3. PREVENTION: How to avoid this next time (actionable)
4. IMMEDIATE FIX: What should be tried now

Be specific and actionable. No platitudes."

    local retro_analysis
    retro_analysis=$(run_agent_sync "claude-sonnet" "$retro_prompt" 60 "code-reviewer" "retrospective" 2>/dev/null) || true

    if [[ -n "$retro_analysis" ]]; then
        echo -e "${YELLOW}Retrospective Analysis:${NC}"
        echo "$retro_analysis" | head -15
        echo ""

        # Record findings
        write_structured_decision \
            "quality-gate" \
            "retrospective_ceremony" \
            "Retrospective on failure: ${prompt:0:60}" \
            "" \
            "high" \
            "${retro_analysis:0:200}" \
            "" 2>/dev/null || true
    fi

    log INFO "Retrospective ceremony complete"
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
    word_count=$(echo "$prompt" | wc -w | tr -d ' ')

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

# ═══════════════════════════════════════════════════════════════════════════════
# v8.19.0 FEATURE: CONFIGURABLE QUALITY GATE THRESHOLDS (Veritas-inspired)
# Per-phase env vars override hardcoded thresholds. Security floor: always 100.
# ═══════════════════════════════════════════════════════════════════════════════

get_gate_threshold() {
    local phase="$1"

    # Check for explicit env var override first
    local override=""
    case "$phase" in
        probe|discover) override="${OCTOPUS_GATE_PROBE}" ;;
        grasp|define)   override="${OCTOPUS_GATE_GRASP}" ;;
        tangle|develop) override="${OCTOPUS_GATE_TANGLE}" ;;
        ink|deliver)    override="${OCTOPUS_GATE_INK}" ;;
        security)
            override="${OCTOPUS_GATE_SECURITY}"
            # Security floor: never allow below 100
            if [[ -n "$override" && "$override" -lt 100 ]]; then
                log WARN "Security gate threshold clamped to 100 (was $override)"
                override=100
            fi
            echo "${override:-100}"
            return 0
            ;;
    esac

    # If explicit override, use it
    if [[ -n "$override" ]]; then
        echo "$override"
        return 0
    fi

    # SPC: Calculate threshold from historical quality_gate data (mean - 3σ lower bound)
    local metrics_file="${WORKSPACE_DIR:-.}/.octo/metrics.jsonl"
    if [[ -f "$metrics_file" ]]; then
        local spc_threshold
        spc_threshold=$(grep '"metric":"quality_gate"' "$metrics_file" 2>/dev/null | \
            grep -o '"value":"[^"]*"' | sed 's/"value":"//;s/"//' | \
            grep -E '^[0-9]+\.?[0-9]*$' | awk '
            {
                values[NR] = $1; count++; sum += $1
            }
            END {
                if (count >= 5) {
                    mean = sum / count
                    sumsq = 0
                    for (i = 1; i <= count; i++) sumsq += (values[i] - mean)^2
                    stddev = sqrt(sumsq / count)
                    lcl = mean - 3 * stddev
                    # Clamp: never below 50 or above 95
                    if (lcl < 50) lcl = 50
                    if (lcl > 95) lcl = 95
                    printf "%d", lcl
                }
            }')

        if [[ -n "$spc_threshold" ]]; then
            log "DEBUG" "SPC threshold for $phase: $spc_threshold (from historical data)"
            echo "$spc_threshold"
            return 0
        fi
    fi

    # Fallback to static default
    echo "${QUALITY_THRESHOLD}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# v8.19.0 FEATURE: OBSERVATION IMPORTANCE SCORING (Veritas-inspired)
# Numeric importance (1-10) auto-scored by decision type and confidence.
# ═══════════════════════════════════════════════════════════════════════════════

score_importance() {
    local type="$1"
    local confidence="${2:-medium}"
    local scope="${3:-}"

    # Base scores by decision type
    local base_score
    case "$type" in
        security-finding) base_score=8 ;;
        quality-gate)     base_score=7 ;;
        debate-synthesis) base_score=6 ;;
        phase-completion) base_score=5 ;;
        *)                base_score=5 ;;
    esac

    # Confidence adjustment
    case "$confidence" in
        high) base_score=$((base_score + 1)) ;;
        low)  base_score=$((base_score - 1)) ;;
    esac

    # Clamp 1-10
    [[ $base_score -lt 1 ]] && base_score=1
    [[ $base_score -gt 10 ]] && base_score=10

    echo "$base_score"
}

search_observations() {
    local keywords="$1"
    local min_importance="${2:-1}"

    local decisions_file="${WORKSPACE_DIR}/.octo/decisions.md"
    if [[ ! -f "$decisions_file" ]]; then
        return 0
    fi

    local current_entry=""
    local current_importance=0
    local matches=""

    while IFS= read -r line; do
        if [[ "$line" == "### type:"* ]]; then
            # Process previous entry if it matches
            if [[ -n "$current_entry" && $current_importance -ge $min_importance ]]; then
                # v9.5: bash case-insensitive match (zero subshells, was echo|grep -qi)
                shopt -s nocasematch
                if [[ "$current_entry" == *"$keywords"* ]]; then
                    matches="${matches}${current_entry}
---
"
                fi
                shopt -u nocasematch
            fi
            current_entry="$line"
            current_importance=0
        elif [[ "$line" == "**Importance:"* ]]; then
            # v9.5: bash regex (zero subshells, was echo|grep -o|head)
            [[ "$line" =~ ([0-9]+) ]] && current_importance="${BASH_REMATCH[1]}" || current_importance=0
            current_entry="${current_entry}
${line}"
        elif [[ "$line" != "---" ]]; then
            current_entry="${current_entry}
${line}"
        fi
    done < "$decisions_file"

    # Process last entry
    if [[ -n "$current_entry" && $current_importance -ge $min_importance ]]; then
        shopt -s nocasematch
        if [[ "$current_entry" == *"$keywords"* ]]; then
            matches="${matches}${current_entry}"
        fi
        shopt -u nocasematch
    fi

    if [[ -n "$matches" ]]; then
        echo "$matches"
    fi
}

# [EXTRACTED to lib/error-tracking.sh]

search_similar_errors() {
    local keywords="$1"

    local error_file="${WORKSPACE_DIR}/.octo/errors/error-log.md"
    if [[ ! -f "$error_file" ]]; then
        echo "0"
        return
    fi

    local match_count
    match_count=$(grep -ci -- "$keywords" "$error_file" 2>/dev/null || true)
    match_count="${match_count:-0}"
    echo "$match_count"
}

flag_repeat_error() {
    local keywords="$1"

    local match_count
    match_count=$(search_similar_errors "$keywords")

    if [[ "$match_count" -ge 2 ]]; then
        log WARN "Repeat error detected ($match_count occurrences): $keywords"
        write_structured_decision \
            "security-finding" \
            "flag_repeat_error" \
            "Repeat error pattern detected ($match_count occurrences): ${keywords:0:100}" \
            "error-learning" \
            "high" \
            "Same error pattern has occurred $match_count times, suggesting a systemic issue" \
            "" 2>/dev/null || true
        return 0
    fi
    return 1
}

# [EXTRACTED to lib/heartbeat.sh] start_heartbeat_monitor(), check_agent_heartbeat(),
# compute_dynamic_timeout(), cleanup_heartbeat()

# ═══════════════════════════════════════════════════════════════════════════════
# v8.19.0 FEATURE: CROSS-MODEL REVIEW SCORING 4x10 (Veritas-inspired)
# 4-dimensional review scoring: security/reliability/performance/accessibility
# ═══════════════════════════════════════════════════════════════════════════════

score_cross_model_review() {
    local review_output="$1"

    local sec=5 rel=5 perf=5 acc=5

    # v9.5: Lowercase once for heuristic matching (zero forks via pipe-once instead of 12 echo|grep chains)
    local rl
    rl=$(printf '%s' "$review_output" | tr '[:upper:]' '[:lower:]')

    # Try explicit "Security: 8/10" patterns first (bash regex — zero forks)
    # Note: regex must be in variables for bash 3.2 compatibility
    local _re_sec='[Ss]ecurity[: ]*([0-9]+)/10'
    local _re_rel='[Rr]eliability[: ]*([0-9]+)/10'
    local _re_perf='[Pp]erformance[: ]*([0-9]+)/10'
    local _re_acc='[Aa]ccessib[a-z]*[: ]*([0-9]+)/10'
    [[ "$review_output" =~ $_re_sec ]] && sec="${BASH_REMATCH[1]}"
    [[ "$review_output" =~ $_re_rel ]] && rel="${BASH_REMATCH[1]}"
    [[ "$review_output" =~ $_re_perf ]] && perf="${BASH_REMATCH[1]}"
    [[ "$review_output" =~ $_re_acc ]] && acc="${BASH_REMATCH[1]}"

    # Heuristic fallback for missing dimensions (zero forks via [[ glob ]])
    if [[ "$sec" == 5 ]]; then
        if [[ "$rl" == *vulnerab* || "$rl" == *injection* || "$rl" == *xss* || "$rl" == *csrf* || "$rl" == *insecure* ]]; then
            sec=4
        elif [[ "$rl" == *secure* || "$rl" == *"no vulnerab"* || "$rl" == *safe* ]]; then
            sec=8
        fi
    fi

    if [[ "$rel" == 5 ]]; then
        if [[ "$rl" == *crash* || "$rl" == *unstable* || "$rl" == *"race condition"* || "$rl" == *deadlock* ]]; then
            rel=4
        elif [[ "$rl" == *robust* || "$rl" == *reliable* || "$rl" == *stable* || "$rl" == *resilient* ]]; then
            rel=8
        fi
    fi

    if [[ "$perf" == 5 ]]; then
        if [[ "$rl" == *slow* || "$rl" == *bottleneck* || "$rl" == *"n+1"* || "$rl" == *leak* ]]; then
            perf=4
        elif [[ "$rl" == *optimized* || "$rl" == *efficient* || "$rl" == *performant* ]]; then
            perf=8
        fi
    fi

    if [[ "$acc" == 5 ]]; then
        if [[ "$rl" == *inaccessib* || "$rl" == *"no aria"* || "$rl" == *"missing alt"* ]]; then
            acc=4
        elif [[ "$rl" == *accessible* || "$rl" == *wcag* || "$rl" == *aria* || "$rl" == *a11y* ]]; then
            acc=8
        fi
    fi

    # Clamp all to 0-10
    for var in sec rel perf acc; do
        local val="${!var}"
        [[ "$val" -lt 0 ]] 2>/dev/null && eval "$var=0"
        [[ "$val" -gt 10 ]] 2>/dev/null && eval "$var=10"
    done

    echo "${sec}:${rel}:${perf}:${acc}"
}

format_review_scorecard() {
    local sec="$1" rel="$2" perf="$3" acc="$4"

    local bar_full="████████████████████"  # 20 chars = 10 blocks
    local bar_empty="░░░░░░░░░░░░░░░░░░░░"

    _bar() {
        local val="$1"
        local filled=$((val * 2))
        local empty=$((20 - filled))
        echo "${bar_full:0:$filled}${bar_empty:0:$empty} ${val}/10"
    }

    echo "╔══════════════════════════════════════╗"
    echo "║  CROSS-MODEL REVIEW SCORECARD (4x10) ║"
    echo "╠══════════════════════════════════════╣"
    echo "║  Security:      $(_bar "$sec") ║"
    echo "║  Reliability:   $(_bar "$rel") ║"
    echo "║  Performance:   $(_bar "$perf") ║"
    echo "║  Accessibility: $(_bar "$acc") ║"
    echo "╚══════════════════════════════════════╝"
}

get_cross_model_reviewer() {
    local author_provider="$1"

    case "$author_provider" in
        codex*) echo "agy" ;;
        agy*|antigravity) echo "codex" ;;
        claude*) echo "codex" ;;
        *) echo "codex" ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# v8.19.0 FEATURE: AGENT ROUTING RULES (Veritas-inspired)
# JSON-based routing rules with first-match-wins evaluation.
# ═══════════════════════════════════════════════════════════════════════════════


# ── Extracted from orchestrate.sh ──
run_project_quality_checks() {
    local project_dir="${1:-.}"
    local commands
    commands=$(detect_project_quality_commands "$project_dir")

    [[ -z "$commands" ]] && { echo "No quality commands detected"; return 0; }

    local passed=0 failed=0 total=0
    local -a failures=()

    while IFS= read -r cmd; do
        [[ -z "$cmd" ]] && continue
        ((total++))
        if eval "$cmd" &>/dev/null; then
            ((passed++))
        else
            ((failed++))
            failures+=("$cmd")
        fi
    done <<< "$commands"

    echo "Quality checks: $passed/$total passed"
    if [[ $failed -gt 0 ]]; then
        echo "Failed:"
        printf '  - %s\n' "${failures[@]}"
        return 1
    fi
    return 0
}

detect_project_quality_commands() {
    local project_dir="${1:-.}"
    local -a commands=()

    # Node.js / package.json
    if [[ -f "$project_dir/package.json" ]]; then
        local scripts
        scripts=$(jq -r '.scripts // {} | keys[]' "$project_dir/package.json" 2>/dev/null)
        for script in lint typecheck type-check tsc check; do
            if [[ $'\n'"$scripts"$'\n' == *$'\n'"$script"$'\n'* ]]; then
                commands+=("npm run $script")
            fi
        done
    fi

    # Python / pyproject.toml / setup.cfg
    if [[ -f "$project_dir/pyproject.toml" ]] || [[ -f "$project_dir/setup.cfg" ]]; then
        command -v ruff &>/dev/null && commands+=("ruff check $project_dir")
        command -v mypy &>/dev/null && commands+=("mypy $project_dir")
    fi

    # Rust / Cargo.toml
    if [[ -f "$project_dir/Cargo.toml" ]]; then
        commands+=("cargo clippy --quiet" "cargo test --no-run --quiet")
    fi

    # Go / go.mod
    if [[ -f "$project_dir/go.mod" ]]; then
        commands+=("go vet ./...")
    fi

    # Makefile with lint target
    if [[ -f "$project_dir/Makefile" ]]; then
        if grep -q '^lint:' "$project_dir/Makefile" 2>/dev/null; then
            commands+=("make lint")
        fi
    fi

    # Output as newline-separated list
    printf '%s\n' "${commands[@]}"
}
