#!/usr/bin/env bash
# lib/embrace.sh — Embrace/probe workflow coordination
# Extracted from orchestrate.sh
# Functions: get_dispatch_strategy, load_blind_spot_checklist

get_dispatch_strategy() {
    local prompt="$1"
    local workflow="${2:-auto}"
    local strategy="${OCTOPUS_DISPATCH_STRATEGY:-smart}"

    case "$strategy" in
        full)
            local all_p="claude-sonnet"
            command -v codex >/dev/null 2>&1 && all_p="codex,${all_p}"
            command -v gemini >/dev/null 2>&1 && all_p="gemini,${all_p}"
            echo "3:${all_p}:high"
            return 0 ;;
        minimal)
            if command -v gemini >/dev/null 2>&1; then echo "2:gemini,claude-sonnet:high"
            elif command -v codex >/dev/null 2>&1; then echo "2:codex,claude-sonnet:high"
            else echo "1:claude-sonnet:high"; fi
            return 0 ;;
    esac

    # Auto-detect workflow from prompt if not specified
    if [[ "$workflow" == "auto" ]]; then
        local p_lower
        p_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')
        local _re_sec='security|vulnerabilit|cve|owasp|injection|xss|csrf'
        local _re_rev='review|code.review|pull.request|bug.*find|audit|quality'
        local _re_arch='architect|system.design|trade.?off|debate|compare|vs([[:space:]]|$)|versus'
        if [[ "$p_lower" =~ $_re_sec ]]; then
            workflow="security"
        elif [[ "$p_lower" =~ $_re_rev ]]; then
            workflow="review"
        elif [[ "$p_lower" =~ $_re_arch ]]; then
            workflow="architecture"
        else
            workflow="research"
        fi
    fi

    # v9.10.0: Detect all available providers for dispatch strategy
    local has_codex=false has_gemini=false has_copilot=false has_qwen=false has_ollama=false has_cursor_agent=false
    command -v codex >/dev/null 2>&1 && has_codex=true
    command -v gemini >/dev/null 2>&1 && has_gemini=true
    command -v copilot >/dev/null 2>&1 && has_copilot=true
    command -v qwen >/dev/null 2>&1 && has_qwen=true
    command -v ollama >/dev/null 2>&1 && curl -sf http://localhost:11434/api/tags &>/dev/null && has_ollama=true
    if declare -f cursor_agent_is_available >/dev/null 2>&1; then
        cursor_agent_is_available && has_cursor_agent=true
    elif command -v agent >/dev/null 2>&1; then
        local _agent_ver
        _agent_ver=$(agent --version 2>&1 || true)
        if printf '%s\n' "$_agent_ver" | grep -cE '^20[0-9]{2}\.' >/dev/null 2>&1; then
            # Auth check fallback when helper not loaded
            if [[ -n "${CURSOR_API_KEY:-}" ]] || [[ -f "${HOME}/.cursor/agent-cli-state.json" ]]; then
                has_cursor_agent=true
            fi
        fi
    fi

    # Build available CLI providers list (excluding Claude which is always available)
    local -a cli_providers=()
    [[ "$has_codex" == true ]] && cli_providers+=(codex)
    [[ "$has_gemini" == true ]] && cli_providers+=(gemini)
    [[ "$has_copilot" == true ]] && cli_providers+=(copilot)
    [[ "$has_qwen" == true ]] && cli_providers+=(qwen)
    [[ "$has_cursor_agent" == true ]] && cli_providers+=(cursor-agent)
    local cli_count=${#cli_providers[@]}

    case "$workflow" in
        review|security)
            # Each provider misses different bugs — more perspectives = better coverage
            if [[ $cli_count -ge 3 ]]; then
                local providers_str
                providers_str=$(IFS=,; echo "${cli_providers[*]}")
                echo "$((cli_count + 1)):${providers_str},claude-sonnet:high"
            elif [[ "$has_codex" == true && "$has_gemini" == true ]]; then
                echo "3:codex,gemini,claude-sonnet:high"
            elif [[ "$has_codex" == true ]]; then echo "2:codex,claude-sonnet:high"
            elif [[ "$has_gemini" == true ]]; then echo "2:gemini,claude-sonnet:high"
            elif [[ "$has_qwen" == true ]]; then echo "2:qwen,claude-sonnet:medium"
            else echo "1:claude-sonnet:medium"; fi ;;
        architecture)
            # Maximize training bias diversity
            if [[ "$has_codex" == true && "$has_gemini" == true ]]; then
                echo "2:codex,gemini:high"
            elif [[ "$has_codex" == true ]]; then echo "2:codex,claude-sonnet:medium"
            elif [[ "$has_gemini" == true ]]; then echo "2:gemini,claude-sonnet:medium"
            elif [[ "$has_qwen" == true ]]; then echo "2:qwen,claude-sonnet:medium"
            else echo "1:claude-sonnet:low"; fi ;;
        research|*)
            # Research benefits from diverse perspectives
            if [[ $cli_count -ge 2 ]]; then
                local providers_str
                providers_str=$(IFS=,; echo "${cli_providers[*]}")
                echo "$((cli_count + 1)):${providers_str},claude-sonnet:high"
            elif [[ "$has_gemini" == true ]]; then echo "2:gemini,claude-sonnet:high"
            elif [[ "$has_codex" == true ]]; then echo "2:codex,claude-sonnet:medium"
            elif [[ "$has_qwen" == true ]]; then echo "2:qwen,claude-sonnet:medium"
            elif [[ "$has_copilot" == true ]]; then echo "2:copilot,claude-sonnet:medium"
            else echo "1:claude-sonnet:medium"; fi ;;
    esac
}

load_blind_spot_checklist() {
    local prompt="$1"
    local blind_spots_dir="${SCRIPT_DIR}/../config/blind-spots"
    local manifest="${blind_spots_dir}/manifest.json"

    [[ ! -f "$manifest" ]] && return

    local prompt_lower
    prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')

    # Find matching domain files via manifest trigger keywords
    local matched_files
    matched_files=$(jq -r --arg p "$prompt_lower" '
        .domains[] |
        select([.trigger_keywords[] as $kw | $p | test($kw; "i")] | any) |
        .file
    ' "$manifest" 2>/dev/null | sort -u)

    [[ -z "$matched_files" ]] && return

    # Collect relevant blind spot prompts from matched domains
    local checklist=""
    while IFS= read -r domain_file; do
        [[ -z "$domain_file" ]] && continue
        local file="${blind_spots_dir}/${domain_file}"
        [[ ! -f "$file" ]] && continue

        local spots
        spots=$(jq -r --arg p "$prompt_lower" '
            .blind_spots[] |
            select([.trigger_keywords[] as $kw | $p | test($kw; "i")] | any) |
            .injection_prompt
        ' "$file" 2>/dev/null)

        while IFS= read -r spot; do
            [[ -z "$spot" ]] && continue
            checklist="${checklist}
- ${spot}"
        done <<< "$spots"
    done <<< "$matched_files"

    [[ -z "$checklist" ]] && return
    echo "$checklist"
}
