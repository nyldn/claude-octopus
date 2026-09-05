#!/usr/bin/env bash
_profile_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_profile_lib_dir}/agent-spec.sh" 2>/dev/null || true
source "${_profile_lib_dir}/provider-registry.sh" || { echo "dispatch: failed to load provider-registry.sh" >&2; return 1 2>/dev/null || exit 1; }
if ! declare -f octopus_resolve_reasoning_level >/dev/null 2>&1; then
    source "${_profile_lib_dir}/execution-profile.sh" 2>/dev/null || true
fi
if ! declare -f cursor_agent_resolve_mode >/dev/null 2>&1; then
    source "${_profile_lib_dir}/cursor-agent.sh" 2>/dev/null || true
fi
if ! declare -f octo_codex_model_version_ok >/dev/null 2>&1; then
    source "${_profile_lib_dir}/provider-versions.sh" 2>/dev/null || true
fi
# Claude Octopus — Agent Dispatch & Model Resolution
# ═══════════════════════════════════════════════════════════════════════════════
# Extracted from orchestrate.sh in v9.7.7 monolith decomposition.
# Contains: get_agent_command, get_agent_model, validate_model_allowed,
#           apply_tool_policy, apply_persona, get_agent_readonly,
#           get_role_budget_proportion, enforce_context_budget
# Source-safe: no main execution block.
# ═══════════════════════════════════════════════════════════════════════════════

#                    gpt-5.2-codex, gpt-5.4-mini (budget), gpt-5 (standard), gpt-5.2, gpt-5.1
# - OpenAI Reasoning: o3, o3-pro (API-key only), o3 (API-key only), o3-mini (API-key only)
# - OpenAI Large Context: gpt-4.1 (1M ctx, API-key only), gpt-5.4 (1M ctx, API-key only)
# - Google Antigravity CLI: agy --print stdin dispatch, optional OCTOPUS_AGY_MODEL
# Note: "API-key only" models require OPENAI_API_KEY; they are NOT available via ChatGPT subscription/OAuth.

_octopus_is_safe_openai_compatible_dispatch_value() {
    local value="$1"
    [[ -z "$value" ]] && return 1
    [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]] && return 1
    [[ "$value" == *"\\"* ]] && return 1
    case "$value" in
        *[[:space:]]*|*\*|*";"*|*"|"*|*"&"*|*'$'*|*'`'*|*"'"*|*'"'*|*"("*|*")"*|*"<"*|*">"*|*"!"*|*"*"*|*"?"*|*"["*|*"]"*|*"{"*|*"}"*)
            return 1
            ;;
    esac
    return 0
}

_octopus_is_safe_env_var_name() {
    [[ "${1:-}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

_octopus_hex_encode_kimi_model() {
    local model="$1" encoded
    encoded="$(LC_ALL=C printf '%s' "$model" | od -An -v -tx1 | tr -d '[:space:]')" || return 1
    [[ "$encoded" =~ ^([0-9A-Fa-f][0-9A-Fa-f])+$ ]] || return 1
    printf '%s\n' "$encoded"
}

_octopus_claude_reasoning_fragment() {
    local level="$1" policy="${2:-best_effort}"
    if [[ "${SUPPORTS_EFFORT_COMMAND:-false}" != "true" ||
          "${SUPPORTS_EFFORT_CLI_FLAG:-false}" != "true" ]]; then
        return 0
    fi
    octopus_reasoning_cli_fragment claude "$level" "$policy"
}

# Exact model pins must stay exact, so an unsafe Fable security pin is rejected
# instead of being silently rerouted to a different model.
_octopus_validate_exact_claude_dispatch_model() {
    local model="${1:-}" role="${2:-}" agent_type="${3:-}" phase="${4:-}" prompt_bytes="${5:-0}"
    [[ "$agent_type" == *:* ]] || return 0
    if ! octo_agent_spec_exact_role_allowed "$agent_type" "$role" "$phase"; then
        log "ERROR" "Exact Fable 5 model pins cannot be used for security dispatches"
        return 1
    fi
    if declare -f fable5_is_model >/dev/null 2>&1 && fable5_is_model "$model"; then
        if ! fable5_prompt_within_budget "$prompt_bytes"; then
            log "ERROR" "Exact Fable 5 model pin exceeds the configured input ceiling"
            return 1
        fi
    fi
    return 0
}

# Model-qualified seats must stay exact, so the validator above rejects an
# oversized Fable prompt. Non-exact environment pins may use the documented
# non-Fable fallback instead, but the replacement still has to be safe to place
# in the legacy command string.
_octopus_apply_nonexact_fable_input_gate() {
    local model="${1:-}" agent_type="${2:-}" prompt_bytes="${3:-0}"
    if [[ "$agent_type" == *:* ]] ||
       ! declare -f fable5_is_model >/dev/null 2>&1 ||
       ! fable5_is_model "$model"; then
        printf '%s\n' "$model"
        return 0
    fi

    local gate_rc=0 fallback_model=""
    fable5_prompt_within_budget "$prompt_bytes" || gate_rc=$?
    case "$gate_rc" in
        0)
            printf '%s\n' "$model"
            return 0
            ;;
        1)
            fallback_model="$(fable5_fallback_model)"
            if ! validate_model_name "$fallback_model"; then
                log "ERROR" "Invalid Fable 5 fallback model"
                return 1
            fi
            log "WARN" "Fable 5 input gate: ${prompt_bytes} bytes exceeds ${OCTOPUS_FABLE5_MAX_INPUT_BYTES:-524288}; using ${fallback_model} before dispatch"
            printf '%s\n' "$fallback_model"
            ;;
        *)
            log "ERROR" "Invalid Fable 5 input-gate configuration"
            return 1
            ;;
    esac
}

_octopus_openai_compatible_runtime_config() {
    local provider="$1"
    local config_provider="$provider" base_url api_key_env credential_value
    provider="${provider%%:*}"
    if declare -f octo_provider_canonical >/dev/null 2>&1; then
        provider="$(octo_provider_canonical "$provider" 2>/dev/null || printf '%s' "$provider")"
    fi
    config_provider="$provider"
    case "$provider" in
        openai-compatible|openai-tools|openai-compatible-agent) config_provider="openai-compatible-agent" ;;
    esac

    base_url="$(octopus_provider_definition_field "$config_provider" base_url)"
    [[ -n "$base_url" ]] || base_url="${OPENAI_COMPAT_BASE_URL:-}"

    api_key_env="$(octopus_provider_definition_field "$config_provider" api_key_env)"
    [[ -n "$api_key_env" ]] || api_key_env="${OPENAI_COMPAT_API_KEY_ENV:-OPENAI_API_KEY}"

    if [[ -z "$base_url" ]]; then
        log ERROR "OpenAI-compatible provider '$config_provider' has no base_url in providers.json and OPENAI_COMPAT_BASE_URL is unset"
        return 1
    fi
    case "$base_url" in
        http://*|https://*) ;;
        *)
            log ERROR "OpenAI-compatible provider '$config_provider' requires an http(s) base_url"
            return 1
            ;;
    esac
    if ! _octopus_is_safe_openai_compatible_dispatch_value "$base_url"; then
        log ERROR "Invalid OpenAI-compatible base_url for provider '$provider'"
        return 1
    fi
    if [[ "$base_url" == http://* ]] &&
       [[ ! "$base_url" =~ ^http://(localhost|127\.0\.0\.1)(:[0-9]+)?(/|$) ]]; then
        log ERROR "OpenAI-compatible provider '$config_provider' requires HTTPS for non-loopback endpoints"
        return 1
    fi
    if ! _octopus_is_safe_env_var_name "$api_key_env"; then
        log ERROR "Invalid api_key_env for OpenAI-compatible provider '$provider': '$api_key_env'"
        return 1
    fi
    credential_value="$(printenv "$api_key_env" 2>/dev/null || true)"
    if [[ -z "$credential_value" ]]; then
        log ERROR "OpenAI-compatible provider '$config_provider' requires credential env '$api_key_env', but it is unset"
        return 1
    fi

    printf '%s\t%s\n' "$base_url" "$api_key_env"
}

# ── Does a resolved codex model name indicate an OSS/local model that codex
#    serves through ollama (and would silently auto-pull)? codex's built-in OSS
#    family is gpt-oss*; ollama-served models also carry a size tag like ':120b'.
#    Cloud codex models (gpt-5.x, o3, gpt-4.1, gpt-5.2-codex) never use that tag
#    form, so this stays conservative and leaves normal codex dispatch untouched.
#    NOTE: keep in sync with _codex_model_is_oss() in helpers/codex-run.sh. ──
_codex_dispatch_is_oss_model() {
    local m="$1"
    [[ -z "$m" ]] && return 1
    # Preserve the caller's nocasematch setting instead of forcing it off.
    local _restore_nocasematch
    _restore_nocasematch=$(shopt -p nocasematch || true)
    shopt -s nocasematch
    local rc=1
    if [[ "$m" == gpt-oss* ]] || [[ "$m" =~ :[0-9]+(\.[0-9]+)?b$ ]]; then
        rc=0
    elif [[ -n "${OCTOPUS_CODEX_OSS_PATTERNS:-}" && "$m" =~ ${OCTOPUS_CODEX_OSS_PATTERNS} ]]; then
        rc=0
    fi
    eval "${_restore_nocasematch:-shopt -u nocasematch}"
    return $rc
}

_octopus_require_codex_model_version() {
    local model="$1"
    [[ "$model" == "gpt-6-astra" ]] || return 0
    local installed_version
    installed_version="$(octo_codex_installed_version)"
    if ! octo_codex_model_version_ok "$installed_version" "$model"; then
        log "ERROR" "gpt-6-astra requires Codex CLI ${OCTO_CODEX_ASTRA_MIN_VERSION}+; found ${installed_version}"
        return 1
    fi
}

# ── Build the `codex exec` dispatch string. For OSS/local models, wrap it in the
#    pull-guard shim (helpers/codex-run.sh) so codex cannot fire an unbounded
#    `ollama pull` for an absent multi-GB model unless OCTOPUS_OLLAMA_ALLOW_PULL
#    is set — closing the codex-side vector that ollama-run.sh does not cover.
#    Cloud models are emitted unchanged (zero behavior change for the common path). ──
_build_codex_exec_command() {
    local model="$1" sandbox_flag="$2" reasoning_fragment="${3:-}"
    _octopus_require_codex_model_version "$model" || return 1
    local base="codex exec --skip-git-repo-check --model ${model}"
    [[ -n "$reasoning_fragment" ]] && base+=" ${reasoning_fragment}"
    base+=" ${sandbox_flag} -"
    if _codex_dispatch_is_oss_model "$model"; then
        echo "${PLUGIN_DIR}/scripts/helpers/codex-run.sh ${base}"
    else
        echo "$base"
    fi
}

_octopus_allowed_model_or_fallback() {
    local provider="$1"
    local model="$2"
    local fallback=""

    if fallback="$(validate_model_allowed "$provider" "$model")"; then
        printf '%s\n' "$model"
        return 0
    fi
    if [[ -z "$fallback" ]] || ! validate_model_name "$fallback"; then
        log ERROR "Invalid allowlist fallback model for $provider"
        return 1
    fi
    printf '%s\n' "$fallback"
}

# Extract the concrete model serialized by a generated provider command. The
# fallback preserves providers whose command shape does not carry --model.
octo_dispatch_command_model() {
    local command="${1:-}" fallback="${2:-}" resolved
    resolved="$(printf '%s\n' "$command" | awk '
      { for (i = 1; i <= NF; i++) if ($i == "--model" && i < NF) { print $(i + 1); exit } }
    ')"
    printf '%s\n' "${resolved:-$fallback}"
}

# Role-based tool policy is needed during command construction, including when
# dispatch.sh is sourced without the monolithic orchestrator.
get_tool_policy() {
    local role="${1:-}"
    case "$role" in
        researcher|ai-engineer|business-analyst|research-synthesizer|ux-researcher)
            echo "read_search" ;;
        implementer|tdd-orchestrator|debugger|python-pro|typescript-pro|frontend-developer)
            echo "full" ;;
        code-reviewer|security-auditor|performance-engineer|test-automator)
            echo "read_exec" ;;
        synthesizer|orchestrator|context-manager|docs-architect|exec-communicator|academic-writer|product-writer)
            echo "read_communicate" ;;
        *) echo "full" ;;
    esac
}

# Kimi Code's non-interactive mode cannot enforce a read-only tool boundary.
# Keep its eligibility fail-closed: a role must be explicitly write-capable,
# and persona frontmatter can still narrow an otherwise write-capable role.
octo_kimi_role_is_write_capable() {
    local role="${1:-}"
    [[ -n "$role" ]] || return 1
    if declare -f get_agent_readonly >/dev/null 2>&1 && \
       [[ "$(get_agent_readonly "$role")" == "true" ]]; then
        return 1
    fi
    case "$role" in
        implementer|tdd-orchestrator|debugger|python-pro|typescript-pro|frontend-developer)
            return 0 ;;
        *)
            return 1 ;;
    esac
}

get_agent_command() {
    local agent_type="$1"
    local phase="${2:-}"
    local role="${3:-}"
    local prompt_bytes="${4:-0}"
    local model=""
    local agent_executor
    agent_executor="$(octo_agent_spec_executor "$agent_type")"
    # Allow swapping the claude binary (e.g. clarp = subscription-billed drop-in
    # for `claude -p`, instead of metered API). Default unchanged. May include
    # args (word-split downstream by read -ra), e.g. "clarp --strict-mcp-config".
    local _claude_bin="${OCTOPUS_CLAUDE_BIN:-claude}"
    # A Claude provider nested under a non-Claude host must not recursively load
    # user-scoped plugins/hooks. Unlike --bare, limiting setting sources keeps
    # OAuth/keychain authentication available.
    if [[ "${OCTOPUS_HOST:-standalone}" == "codex" ]]; then
        if [[ " $_claude_bin " != *" --setting-sources "* ]]; then
            _claude_bin="${_claude_bin} --setting-sources project,local"
        fi
    fi

    # Configurable sandbox mode (v7.13.1 - Issue #9)
    # Priority: OCTOPUS_CODEX_SANDBOX env var > default (workspace-write)
    # Valid values: workspace-write (default), danger-full-access, read-only
    local codex_sandbox="${OCTOPUS_CODEX_SANDBOX:-workspace-write}"

    # Security: reject values not in allowlist
    case "$codex_sandbox" in
        workspace-write|danger-full-access|read-only)
            ;;
        *)
            log "ERROR" "Invalid OCTOPUS_CODEX_SANDBOX value: '${codex_sandbox}'. Allowed: workspace-write, danger-full-access, read-only"
            log "ERROR" "Falling back to workspace-write for safety."
            codex_sandbox="workspace-write"
            ;;
    esac

    local sandbox_flag="--sandbox ${codex_sandbox}"

    # Spawned `claude --print` subprocesses have no interactive approver, so any
    # tool that would prompt is silently denied ("Read is blocked in the current
    # permission mode"). Pre-approve read tools for every role; write-capable
    # roles additionally accept edits (bug 260609). Comma-joined, no spaces —
    # downstream `read -ra` word-splits the command string.
    local claude_perm="--allowed-tools Read,Glob,Grep"
    case "$role" in
        implementer|developer)
            claude_perm="--permission-mode acceptEdits --allowed-tools Read,Glob,Grep,Edit,Write"
            ;;
    esac

    case "$agent_executor" in
        # v8.9.0: Spark, reasoning, and large-context variants share the
        # same command shape; only model resolution differs by agent type.
        codex|codex-standard|codex-max|codex-mini|codex-general|codex-spark|codex-reasoning|codex-large-context)
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            local reasoning_level reasoning_policy reasoning_fragment
            reasoning_level="$(octopus_resolve_reasoning_level codex "$phase" "$role")" || return 1
            reasoning_policy="$(octopus_resolve_reasoning_policy codex "$phase" "$role")" || return 1
            reasoning_fragment="$(octopus_reasoning_cli_fragment codex "$reasoning_level" "$reasoning_policy")" || return 1
            _build_codex_exec_command "$model" "$sandbox_flag" "$reasoning_fragment"
            ;;
        # gemini* is a compatibility alias for stale saved workflows. It must
        # never invoke gemini-cli; all Google seats execute through AGY.
        gemini|gemini-fast|gemini-image|agy|agy-research|antigravity)
            if [[ "$agent_type" == *:* ]]; then
                if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                    return 1
                fi
                echo "env OCTOPUS_AGY_MODEL=${model} ${PLUGIN_DIR}/scripts/helpers/agy-exec.sh"
            else
                echo "${PLUGIN_DIR}/scripts/helpers/agy-exec.sh"
            fi
            ;;
        codex-review)
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            _octopus_require_codex_model_version "$model" || return 1
            # `codex exec review` has no --sandbox/--profile flag (unlike plain
            # `codex exec`), so it silently inherits sandbox_mode from the
            # user's ~/.codex/config.toml — OCTOPUS_CODEX_SANDBOX would not
            # constrain it otherwise. -c overrides the config value directly.
            echo "codex exec review --model ${model} --skip-git-repo-check -c sandbox_mode=${codex_sandbox}"
            ;;
        claude)
            local reasoning_level reasoning_policy reasoning_fragment
            reasoning_level="$(octopus_resolve_reasoning_level claude "$phase" "$role")" || return 1
            reasoning_policy="$(octopus_resolve_reasoning_policy claude "$phase" "$role")" || return 1
            reasoning_fragment="$(_octopus_claude_reasoning_fragment "$reasoning_level" "$reasoning_policy")" || return 1
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            _octopus_validate_exact_claude_dispatch_model "$model" "$role" "$agent_type" "$phase" "$prompt_bytes" || return 1
            model="$(_octopus_apply_nonexact_fable_input_gate "$model" "$agent_type" "$prompt_bytes")" || return 1
            [[ "$agent_type" == *:* ]] || model="${model//./-}"
            echo "${_claude_bin}${_BARE_OPT} --print --model ${model} ${reasoning_fragment} ${claude_perm}" ;;
        claude-sonnet)
            local reasoning_level reasoning_policy reasoning_fragment
            reasoning_level="$(octopus_resolve_reasoning_level claude "$phase" "$role")" || return 1
            reasoning_policy="$(octopus_resolve_reasoning_policy claude "$phase" "$role")" || return 1
            reasoning_fragment="$(_octopus_claude_reasoning_fragment "$reasoning_level" "$reasoning_policy")" || return 1
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            _octopus_validate_exact_claude_dispatch_model "$model" "$role" "$agent_type" "$phase" "$prompt_bytes" || return 1
            model="$(_octopus_apply_nonexact_fable_input_gate "$model" "$agent_type" "$prompt_bytes")" || return 1
            [[ "$agent_type" == *:* ]] || model="${model//./-}"
            echo "${_claude_bin}${_BARE_OPT} --print --model ${model} ${reasoning_fragment} ${claude_perm}" ;;
        claude-opus|claude-opus-fast)
            # Resolve a concrete model so current-host detection and user pins
            # remain visible on the wire instead of depending on a moving alias.
            # claude-opus-fast is a compatibility executor. Claude's spawned
            # --print CLI does not expose a documented --fast flag, so both
            # executors use the same validated standard command shape.
            local opus_effort="high"
            if declare -f get_effort_level >/dev/null 2>&1; then
                local opus_complexity="2"
                case "${phase:-}" in
                    tangle|develop|ink|deliver) opus_complexity="3" ;;
                esac
                opus_effort="$(get_effort_level "${phase:-unknown}" "$opus_complexity")"
                opus_effort="${opus_effort:-high}"
            elif [[ -n "${OCTOPUS_EFFORT_OVERRIDE:-}" ]]; then
                opus_effort="$OCTOPUS_EFFORT_OVERRIDE"
            fi
            local opus_model_flag
            if [[ "$agent_type" == *:* ]]; then
                opus_model_flag="$(get_agent_model "$agent_type" "$phase" "$role")" || return 1
                _octopus_validate_exact_claude_dispatch_model "$opus_model_flag" "$role" "$agent_type" "$phase" "$prompt_bytes" || return 1
            else
                opus_model_flag="$(opus_default_model)"
                # Selective Fable 5 escalation for judgment-class roles, before
                # the security reroute so a security dispatch can never end up
                # on Fable even if the allowlist is later widened. Exact seats
                # bypass escalation because changing their model breaks the pin.
                if declare -f fable5_resolve_dispatch_model >/dev/null 2>&1; then
                    local fable_decision fable_requested fable_reason
                    if ! fable_decision="$(fable5_resolve_dispatch_model "$opus_model_flag" "$role" "$agent_type" "$phase" "$prompt_bytes")"; then
                        log "ERROR" "Invalid Fable 5 input-gate configuration"
                        return 1
                    fi
                    fable_requested="$(jq -r '.requested_model' <<< "$fable_decision")"
                    opus_model_flag="$(jq -r '.resolved_model' <<< "$fable_decision")"
                    fable_reason="$(jq -r '.reason' <<< "$fable_decision")"
                    if [[ "${OCTOPUS_DISPATCH_PREVIEW:-false}" != "true" ]] && \
                       declare -f run_contract_record_event >/dev/null 2>&1; then
                        run_contract_record_event "routing.decision" \
                            "requested_model=$fable_requested" \
                            "resolved_model=$opus_model_flag" \
                            "reason=$fable_reason" "prompt_bytes=$prompt_bytes" \
                            "phase=${phase:-unknown}" "role=${role:-none}" >/dev/null 2>&1 || true
                    fi
                else
                    if declare -f fable5_maybe_escalate >/dev/null 2>&1; then
                        opus_model_flag="$(fable5_maybe_escalate "$opus_model_flag" "$role" "$agent_type" "$phase")"
                    fi
                    if declare -f fable5_maybe_reroute >/dev/null 2>&1; then
                        opus_model_flag="$(fable5_maybe_reroute "$opus_model_flag" "$role" "$agent_type" "$phase")"
                    fi
                fi
            fi
            # Clamp on the resolved model, so an escalated dispatch is clamped
            # while unrelated Opus 5 work in the same run keeps its effort.
            if declare -f fable5_clamp_effort_for_model >/dev/null 2>&1; then
                opus_effort="$(fable5_clamp_effort_for_model "$opus_effort" "$opus_model_flag")"
            fi
            if [[ "${SUPPORTS_XHIGH_EFFORT:-false}" != "true" ]]; then
                case "$opus_effort" in
                    xhigh|max)
                        log "WARN" "Claude effort ${opus_effort} is unavailable on this CLI; using high"
                        opus_effort="high"
                        ;;
                esac
            fi
            opus_model_flag="$(_octopus_allowed_model_or_fallback "claude" "$opus_model_flag")" || return 1
            if ! validate_model_name "$opus_model_flag"; then
                log "ERROR" "Invalid resolved Claude Opus model: '${opus_model_flag}'"
                return 1
            fi
            case "$opus_effort" in
                low|medium|high|xhigh|max) ;;
                *)
                    log "ERROR" "Invalid resolved Claude effort: '${opus_effort}'"
                    return 1
                    ;;
            esac
            [[ "$agent_type" == *:* ]] || opus_model_flag="${opus_model_flag//./-}"
            local opus_reasoning_fragment=""
            opus_reasoning_fragment="$(_octopus_claude_reasoning_fragment "$opus_effort" best_effort)" || return 1
            echo "${_claude_bin}${_BARE_OPT} --print --model ${opus_model_flag}${opus_reasoning_fragment:+ ${opus_reasoning_fragment}} ${claude_perm}"
            ;;
        claude-opus-legacy) echo "${_claude_bin}${_BARE_OPT} --print --model claude-opus-4-6 ${claude_perm}" ;; # v9.23: explicit 4.6 opt-in
        openrouter)
            if [[ "$agent_type" == *:* ]]; then
                model="$(get_agent_model "$agent_type" "$phase" "$role")" || return 1
                echo "openrouter_execute_model ${model}"
            else
                echo "openrouter_execute"
            fi
            ;;                 # OpenRouter API (v4.8)
        orcarouter)
            if [[ "$agent_type" == *:* ]]; then
                model="$(get_agent_model "$agent_type" "$phase" "$role")" || return 1
                echo "orcarouter_execute_model ${model}"
            else
                echo "orcarouter_execute"
            fi
            ;;                 # OrcaRouter gateway (OpenAI-compatible)
        openrouter-glm5) echo "openrouter_execute_model z-ai/glm-5" ;;           # v8.11.0: GLM-5 via OpenRouter
        openrouter-kimi) echo "openrouter_execute_model moonshotai/kimi-k2.5" ;; # v8.11.0: Kimi K2.5 via OpenRouter
        openrouter-deepseek) echo "openrouter_execute_model deepseek/deepseek-v4-pro" ;;
        openai-compatible|openai-tools|openai-compatible-agent)  # Generic OpenAI-compatible tool-loop agent
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            if ! validate_model_name "$model"; then
                log ERROR "Invalid OpenAI-compatible model name: ${model}"
                return 1
            fi
            if ! _octopus_is_safe_openai_compatible_dispatch_value "${PWD}"; then
                log ERROR "Invalid OpenAI-compatible cwd: ${PWD}"
                return 1
            fi
            local reasoning_level reasoning_policy reasoning_fragment runtime_config base_url api_key_env tool_fragment=""
            reasoning_level="$(octopus_resolve_reasoning_level openai-compatible-agent "$phase" "$role")" || return 1
            reasoning_policy="$(octopus_resolve_reasoning_policy openai-compatible-agent "$phase" "$role")" || return 1
            reasoning_fragment="$(octopus_reasoning_cli_fragment openai-compatible-agent "$reasoning_level" "$reasoning_policy")" || return 1
            runtime_config="$(_octopus_openai_compatible_runtime_config "$agent_type")" || return 1
            IFS=$'\t' read -r base_url api_key_env <<<"$runtime_config"
            # Review prompts already contain the complete diff and context. Do
            # not expose file/shell tools in this phase: a malicious diff could
            # otherwise prompt-inject a model into reading or exfiltrating CI
            # credentials inherited by the provider process (#893).
            [[ "$phase" == "review" ]] && tool_fragment="--tool-policy none"
            echo "${PLUGIN_DIR}/scripts/helpers/openai-compatible-agent.py --provider generic --base-url ${base_url} --api-key-env ${api_key_env} --model ${model} ${reasoning_fragment} ${tool_fragment} --cwd ${PWD}"
            ;;
        atlascloud-agent)  # Atlas Cloud via the OpenAI-compatible tool-loop agent
            if [[ "$agent_type" == *:* ]]; then
                model="$(get_agent_model "$agent_type" "$phase" "$role")" || return 1
            else
                model="${ATLASCLOUD_MODEL:-${OCTOPUS_ATLASCLOUD_MODEL:-${OPENAI_COMPAT_MODEL:-}}}"
                if [[ -z "$model" && -f "${HOME}/.claude-octopus/config/providers.json" ]] && command -v jq &>/dev/null; then
                    model="$(jq -r '.providers.atlascloud.default // empty' "${HOME}/.claude-octopus/config/providers.json" 2>/dev/null || true)"
                fi
                if [[ -z "$model" ]]; then
                    log ERROR "ATLASCLOUD_MODEL, OCTOPUS_ATLASCLOUD_MODEL, OPENAI_COMPAT_MODEL, or providers.json atlascloud.default is required"
                    return 1
                fi
            fi
            if ! validate_model_name "$model"; then
                log ERROR "Invalid Atlas Cloud model name: ${model}"
                return 1
            fi
            local fallback
            fallback=$(validate_model_allowed "atlascloud" "$model")
            if [[ $? -ne 0 ]]; then
                if [[ -n "$fallback" ]]; then
                    if ! validate_model_name "$fallback"; then
                        log ERROR "Invalid Atlas Cloud fallback model name"
                        return 1
                    fi
                    model="$fallback"
                else
                    return 1
                fi
            fi
            if ! _octopus_is_safe_openai_compatible_dispatch_value "${PWD}"; then
                log ERROR "Invalid Atlas Cloud cwd: ${PWD}"
                return 1
            fi
            echo "${PLUGIN_DIR}/scripts/helpers/openai-compatible-agent.py --provider atlascloud --model ${model} --cwd ${PWD}"
            ;;
        perplexity|perplexity-fast)  # v8.24.0: Perplexity Sonar — web-grounded research (Issue #22)
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            echo "perplexity_execute $model"
            ;;
        copilot|copilot-research)  # v9.9.0: GitHub Copilot CLI via helpers/copilot-exec.sh (Issue #198)
            # copilot's only non-interactive mode is `-p <text>` (argv), but the spawn
            # contract feeds the prompt via stdin. The shim bridges stdin -> -p so the
            # advisor does not open an interactive session and hang (silent drop).
            # -s: silent (no footer noise); --disable-builtin-mcps: skip MCP startup latency.
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            echo "env OCTOPUS_COPILOT_MODEL=${model} ${PLUGIN_DIR}/scripts/helpers/copilot-exec.sh"
            ;;
        ollama|ollama-*)  # v9.9.0: Ollama local LLM — ollama run
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            # Route through the guard shim instead of a bare `ollama run`: that
            # auto-pulls a missing model, so a provider-failure cascade could
            # silently kick off an unbounded multi-GB download. The shim refuses
            # to pull an absent model unless OCTOPUS_OLLAMA_ALLOW_PULL=true.
            echo "${PLUGIN_DIR}/scripts/helpers/ollama-run.sh $model"
            ;;
        qwen|qwen-research)  # v9.10.0: Qwen CLI — fork of Gemini CLI
            # oco-dar: NO_BROWSER=1 stops a stale token from hijacking the user's
            # browser into the OAuth device-flow. Pre-flight (qwen_is_usable) should
            # already gate this out; this is defense-in-depth if dispatch is reached.
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            # OPENAI_COMPAT auth (OPENAI_API_KEY + OPENAI_BASE_URL) needs an explicit
            # --auth-type: the qwen CLI does not auto-detect it from env vars alone
            # in non-interactive mode (Issue #566).
            local qwen_auth_flag=""
            if declare -f qwen_auth_method >/dev/null 2>&1 && [[ "$(qwen_auth_method)" == "env:OPENAI_COMPAT" ]]; then
                qwen_auth_flag="--auth-type openai"
            fi
            echo "env NODE_NO_WARNINGS=1 NO_BROWSER=1 qwen -o text --approval-mode yolo -m ${model} ${qwen_auth_flag}"
            ;;
        grok|grok-research)  # xAI Grok CLI — headless single-turn via helpers/grok-exec.sh
            # Wire config/env model selection through to the shim (parity with codex/
            # gemini/qwen). get_agent_model reads providers.json + OCTOPUS_GROK_MODEL;
            # pass it via an env prefix so grok-exec.sh emits --model. Grok model ids are
            # single tokens (grok-4-fast, ...) so the prefix survives argv word-splitting.
            # Without this, providers.json model picks were silently ignored (the shim
            # only saw a shell-exported OCTOPUS_GROK_MODEL).
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then return 1; fi
            if [[ -n "$model" && "$model" != "default" ]]; then
                echo "env OCTOPUS_GROK_MODEL=${model} ${PLUGIN_DIR}/scripts/helpers/grok-exec.sh"
            else
                echo "${PLUGIN_DIR}/scripts/helpers/grok-exec.sh"
            fi
            ;;
        kimi|kimi-research)  # Moonshot Kimi Code CLI — headless single-turn via helpers/kimi-exec.sh
            # Kimi's non-interactive print mode auto-approves tool calls and has
            # no CLI permission allowlist. Prompt-only tool policies therefore
            # cannot make a review or research seat read-only.
            if [[ "$agent_type" == "kimi-research" || "$phase" == "review" ]] || \
               ! octo_kimi_role_is_write_capable "$role"; then
                log ERROR "Kimi Code cannot enforce a read-only tool policy; choose a sandboxed provider for role '${role:-unknown}'"
                return 1
            fi
            # Model wiring mirrors grok: get_agent_model reads providers.json +
            # OCTOPUS_KIMI_MODEL. Kimi aliases may contain whitespace, while all
            # command consumers split this legacy command string into argv. Hex
            # keeps the transport one inert token; kimi-exec.sh decodes it without
            # eval before adding the exact alias to its command array.
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then return 1; fi
            if [[ -n "$model" && "$model" != "default" ]]; then
                local model_hex
                model_hex="$(_octopus_hex_encode_kimi_model "$model")" || return 1
                echo "env OCTOPUS_KIMI_MODEL_HEX=${model_hex} ${PLUGIN_DIR}/scripts/helpers/kimi-exec.sh"
            else
                echo "${PLUGIN_DIR}/scripts/helpers/kimi-exec.sh"
            fi
            ;;
        claude-sdk|claude-sdk-agent|claude-sdk-research)  # v9.50.0: Claude Agent SDK seat
            # Routes to helpers/claude-sdk-exec.sh when CLAUDE_SDK_API_KEY is set —
            # unlocks Opus 5 + 1M context independent of the host session. Model
            # wiring mirrors grok: env prefix so providers.json picks reach the shim.
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then return 1; fi
            _octopus_validate_exact_claude_dispatch_model "$model" "$role" "$agent_type" "$phase" "$prompt_bytes" || return 1
            model="$(_octopus_apply_nonexact_fable_input_gate "$model" "$agent_type" "$prompt_bytes")" || return 1
            if [[ -n "$model" && "$model" != "default" ]]; then
                if [[ "$agent_type" == *:* ]] && declare -f fable5_is_model >/dev/null 2>&1 && fable5_is_model "$model"; then
                    echo "env OCTOPUS_CLAUDE_SDK_MODEL=${model} OCTOPUS_FABLE5_NO_RETRY=1 ${PLUGIN_DIR}/scripts/helpers/claude-sdk-exec.sh"
                else
                    echo "env OCTOPUS_CLAUDE_SDK_MODEL=${model} ${PLUGIN_DIR}/scripts/helpers/claude-sdk-exec.sh"
                fi
            else
                echo "${PLUGIN_DIR}/scripts/helpers/claude-sdk-exec.sh"
            fi
            ;;
        commandcode|commandcode-research|commandcode-fast)
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            local commandcode_mode="plan"
            case "$role" in
                implementer|developer) commandcode_mode="yolo" ;;
            esac
            # OCTOPUS_COMMANDCODE_PERMISSION_MODE env override (Issue #710),
            # matching the OCTOPUS_CODEX_SANDBOX precedent above: dispatch
            # always passes a positional arg to commandcode-exec.sh, so its
            # own env-var fallback is dead unless honoured here first.
            if [[ -n "${OCTOPUS_COMMANDCODE_PERMISSION_MODE:-}" ]]; then
                case "$OCTOPUS_COMMANDCODE_PERMISSION_MODE" in
                    plan|default|dont-ask|auto-accept|yolo)
                        commandcode_mode="$OCTOPUS_COMMANDCODE_PERMISSION_MODE"
                        ;;
                    *)
                        log "ERROR" "Invalid OCTOPUS_COMMANDCODE_PERMISSION_MODE value: '${OCTOPUS_COMMANDCODE_PERMISSION_MODE}'. Allowed: plan, default, dont-ask, auto-accept, yolo"
                        log "ERROR" "Falling back to role-derived default (${commandcode_mode})."
                        ;;
                esac
            fi
            echo "${PLUGIN_DIR}/scripts/helpers/commandcode-exec.sh ${model} ${commandcode_mode}"
            ;;
        cursor-agent)  # Cursor CLI (`agent`) — Cursor subscription models, default `auto`
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            # `agent -p` has write and shell access, so seats are read-only
            # unless the role writes code: --mode ask, --mode plan, or --force.
            # Role table + OCTOPUS_CURSOR_AGENT_MODE override live in
            # lib/cursor-agent.sh (cursor_agent_resolve_mode), matching the
            # OCTOPUS_CODEX_SANDBOX / OCTOPUS_COMMANDCODE_PERMISSION_MODE precedent.
            local cursor_mode cursor_mode_flag
            cursor_mode="$(cursor_agent_resolve_mode "$role")"
            cursor_mode_flag="$(cursor_agent_mode_flag "$cursor_mode")"
            # NOTE: bare ${model} (no quotes) — downstream uses `read -ra` which
            # does NOT interpret quotes; literal " would be passed to --model.
            echo "agent --trust --output-format text${cursor_mode_flag:+ ${cursor_mode_flag}} --model ${model}"
            ;;
        vibe|vibe-research)  # Mistral Vibe — interactive CLI (model in ~/.vibe/config.toml)
            # Routed through helpers/vibe-exec.sh: vibe's -p only accepts the
            # prompt as argv (stdin yields "No prompt provided"), so the shim
            # reads stdin and re-passes it as `-p "<prompt>"`. Keeps spawn.sh's
            # uniform stdin contract intact (Issue #173).
            if [[ "$agent_type" == *:* ]]; then
                model="$(get_agent_model "$agent_type" "$phase" "$role")" || return 1
                echo "env OCTOPUS_VIBE_MODEL=${model} ${PLUGIN_DIR}/scripts/helpers/vibe-exec.sh --output text"
            else
                echo "${PLUGIN_DIR}/scripts/helpers/vibe-exec.sh --output text"
            fi
            ;;
        opencode|opencode-fast|opencode-research)  # v9.11.0: OpenCode CLI — multi-provider router
            if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
                return 1
            fi
            # Uses default text output (ANSI stripped by caller) — consistent with other providers
            # --model flag uses provider/model format; we store bare name and map here
            local oc_model_flag=""
            if [[ -n "$model" && "$model" != "default" ]]; then
                oc_model_flag="-m ${model}"
            fi
            # --pure skips opencode's external-plugin auto-title path, which
            # otherwise resolves an SDK handle for a hardcoded small model
            # before the prompt is even sent — an unresolvable catalog/model
            # there hangs `opencode run` indefinitely with no timeout or error
            # (Issue #566). It's a global flag, so it must precede the `run`
            # subcommand or risk being ignored/rejected.
            echo "opencode --pure run ${oc_model_flag}"
            ;;
        *) return 1 ;;
    esac
}

# v9.3.0: Per-role context budget proportions
# WHY: Prevents chatty agents from consuming all context while verifiers get starved
get_role_budget_proportion() {
    local role="$1"
    case "$role" in
        implementer|researcher|developer) echo "60" ;;
        planner|reviewer|architect)       echo "40" ;;
        verifier|synthesizer|release)     echo "25" ;;
        *)                                echo "100" ;; # no reduction for unknown roles
    esac
}

# Provider-aware context ceiling. OCTOPUS_CONTEXT_BUDGET remains the global
# fallback for compatibility; provider-specific env vars let higher-context CLIs
# opt in without inflating smaller providers.
get_provider_context_limit() {
    local agent_type="${1:-}"
    local provider executor registry_default model_env context_env
    provider="$(octo_agent_spec_provider "$agent_type")"
    executor="$(octo_agent_spec_executor "$agent_type")"
    local default_budget="${OCTOPUS_CONTEXT_BUDGET:-12000}"

    case "$executor" in
        codex-large-context) echo "${OCTOPUS_CODEX_LARGE_CONTEXT_BUDGET:-${default_budget}}" ; return 0 ;;
        claude-sdk*) echo "${OCTOPUS_CLAUDE_SDK_CONTEXT_BUDGET:-1000000}" ; return 0 ;;  # v9.50.0: Agent SDK 1M window
        claude-opus*|claude-sonnet|claude) echo "${OCTOPUS_CLAUDE_CONTEXT_BUDGET:-${default_budget}}" ; return 0 ;;
    esac

    registry_default="$(octo_provider_context_tokens "$provider" 2>/dev/null || printf '%s' "$default_budget")"
    model_env="$(octo_provider_model_env "$provider" 2>/dev/null || true)"
    context_env="${model_env%_MODEL}_CONTEXT_BUDGET"
    if [[ -n "$model_env" && -n "${!context_env:-}" ]]; then
        printf '%s\n' "${!context_env}"
    elif [[ -n "${OCTOPUS_CONTEXT_BUDGET:-}" ]]; then
        printf '%s\n' "$OCTOPUS_CONTEXT_BUDGET"
    else
        printf '%s\n' "$registry_default"
    fi
}

# Normalize before Bash arithmetic. The maximum keeps a later four-character
# token estimate inside a signed 32-bit shell integer on every supported host.
octo_normalize_context_budget() {
    local value="${1:-}" label="${2:-context budget}"
    local max_budget=536870911
    local LC_ALL=C

    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        log ERROR "Invalid $label '$value': expected a positive decimal integer"
        return 2
    fi
    while [[ "${#value}" -gt 1 && "${value:0:1}" == "0" ]]; do
        value="${value:1}"
    done
    if [[ "$value" == "0" ]] ||
       [[ "${#value}" -gt "${#max_budget}" ]] ||
       { [[ "${#value}" -eq "${#max_budget}" ]] && [[ "$value" -gt "$max_budget" ]]; }; then
        log ERROR "Invalid $label '$1': expected 1..$max_budget"
        return 2
    fi

    printf '%s\n' "$value"
}

summarize_then_dispatch() {
    local prompt="$1"
    local role="${2:-}"
    local target_agent="${3:-unknown}"
    local budget="${4:-12000}"
    budget=$(octo_normalize_context_budget "$budget" "summarizer context budget") || return 2
    local char_budget=$((budget * 4))

    # Keep the summarizer request itself bounded; preserve both task framing and
    # tail-loaded instructions/diffs because provider CLIs often fail near ARG_MAX.
    local summary_input="$prompt"
    local max_summary_input="${OCTOPUS_OVERSIZE_SUMMARY_INPUT_CHARS:-120000}"
    if [[ ${#summary_input} -gt $max_summary_input ]]; then
        local head_chars=$((max_summary_input / 2))
        local tail_chars=$((max_summary_input - head_chars))
        local tail_start=$((${#summary_input} - tail_chars))
        summary_input="${summary_input:0:$head_chars}

[... middle omitted before preflight summarization; original prompt was ${#prompt} chars ...]

${summary_input:$tail_start:$tail_chars}"
    fi

    local summary_prompt="Condense this oversized agent prompt before provider dispatch.

Target provider: ${target_agent}
Role: ${role:-none}
Target budget: about ${budget} tokens (${char_budget} chars)

Preserve:
- the user's exact objective and constraints
- file paths, commands, URLs, IDs, and quoted requirements
- acceptance criteria and verification instructions
- any explicit safety or permission limits

Remove repetition, logs, duplicate context, and low-value boilerplate. Return only the condensed prompt.

Oversized prompt:
${summary_input}"

    local candidates=()
    if [[ -n "${OCTOPUS_OVERSIZE_SUMMARIZER:-}" ]]; then
        candidates+=("$OCTOPUS_OVERSIZE_SUMMARIZER")
    fi
    candidates+=("agy" "codex-mini" "claude-sonnet" "codex")

    local candidate summary previous_strategy previous_debug
    previous_strategy="${OCTOPUS_OVERSIZE_STRATEGY-}"
    previous_debug="${OCTOPUS_DEBUG-}"
    export OCTOPUS_OVERSIZE_STRATEGY=truncate
    export OCTOPUS_DEBUG="${OCTOPUS_DEBUG:-false}"

    for candidate in "${candidates[@]}"; do
        [[ "$candidate" == "$target_agent" ]] && continue
        if type validate_agent_type >/dev/null 2>&1 && ! validate_agent_type "$candidate" >/dev/null 2>&1; then
            continue
        fi
        if ! type run_agent_sync >/dev/null 2>&1; then
            break
        fi
        summary=$(run_agent_sync "$candidate" "$summary_prompt" 120 "synthesizer" "preflight" 2>/dev/null) || summary=""
        if [[ -n "$summary" && "$summary" != "Provider available" ]]; then
            if [[ -n "$previous_strategy" ]]; then
                export OCTOPUS_OVERSIZE_STRATEGY="$previous_strategy"
            else
                unset OCTOPUS_OVERSIZE_STRATEGY
            fi
            if [[ -n "$previous_debug" ]]; then
                export OCTOPUS_DEBUG="$previous_debug"
            else
                unset OCTOPUS_DEBUG
            fi
            printf '%s\n' "$summary"
            return 0
        fi
    done

    if [[ -n "$previous_strategy" ]]; then
        export OCTOPUS_OVERSIZE_STRATEGY="$previous_strategy"
    else
        unset OCTOPUS_OVERSIZE_STRATEGY
    fi
    if [[ -n "$previous_debug" ]]; then
        export OCTOPUS_DEBUG="$previous_debug"
    else
        unset OCTOPUS_DEBUG
    fi
    return 1
}

octo_fit_prompt_to_char_budget() {
    local prompt="$1"
    local char_budget="$2"
    local marker="$3"
    local marker_chars prefix_chars

    [[ "$char_budget" =~ ^[0-9]+$ ]] || return 1
    if [[ ${#prompt} -le "$char_budget" ]]; then
        printf '%s\n' "$prompt"
        return 0
    fi

    marker_chars=${#marker}
    if [[ "$marker_chars" -ge "$char_budget" ]]; then
        printf '%s\n' "${prompt:0:$char_budget}"
        return 0
    fi
    prefix_chars=$((char_budget - marker_chars))
    printf '%s%s\n' "${prompt:0:$prefix_chars}" "$marker"
}

octo_context_budget_warning() {
    local message="$1"
    if type octo_notice_warn >/dev/null 2>&1; then
        octo_notice_warn "$message"
    else
        log WARN "$message"
    fi
}

enforce_context_budget() {
    local prompt="$1"
    local role="${2:-}"
    local agent_type="${3:-}"
    local phase="${4:-}"
    local budget
    budget=$(get_provider_context_limit "$agent_type")
    budget=$(octo_normalize_context_budget "$budget" "provider context budget") || return 2

    # v9.3.0: Scale budget by role proportion
    if [[ -n "$role" ]]; then
        local proportion budget_whole budget_remainder
        proportion=$(get_role_budget_proportion "$role")
        budget_whole=$((budget / 100))
        budget_remainder=$((budget % 100))
        budget=$((budget_whole * proportion + budget_remainder * proportion / 100))
        if [[ "$budget" -lt 1 ]]; then
            log ERROR "Invalid effective context budget for role '$role': value rounds to zero"
            return 2
        fi
    fi

    # Rough token estimate: ~4 chars per token
    local char_budget=$((budget * 4))

    if [[ ${#prompt} -gt $char_budget ]]; then
        local strategy="${OCTOPUS_OVERSIZE_STRATEGY:-summarize}"
        local original_chars=${#prompt}
        local target="${agent_type:-unknown}"

        case "$strategy" in
            fail)
                log "ERROR" "Context budget: prompt for $target is ${original_chars} chars; limit is $char_budget chars (~$budget tokens)"
                type record_oversize_event >/dev/null 2>&1 && record_oversize_event "$target" "$original_chars" "$original_chars" "failed" "$role" "$phase" "$budget" || true
                type write_agent_status >/dev/null 2>&1 && write_agent_status "$target" "failed" "$((original_chars / 4))" 0 "Prompt exceeded context budget" 0 "" "$role" || true
                return 78
                ;;
            summarize)
                local summarized
                if summarized=$(summarize_then_dispatch "$prompt" "$role" "$target" "$budget") && [[ -n "$summarized" ]]; then
                    if [[ ${#summarized} -gt $char_budget ]]; then
                        summarized=$(octo_fit_prompt_to_char_budget "$summarized" "$char_budget" $'\n\n[... summarized output truncated to fit context budget (~'"$budget"$' tokens) ...]')
                    fi
                    type record_oversize_event >/dev/null 2>&1 && record_oversize_event "$target" "$original_chars" "${#summarized}" "summarized" "$role" "$phase" "$budget" || true
                    octo_context_budget_warning "Context budget: summarized $target role=${role:-none} phase=${phase:-none} from ${original_chars} to ${#summarized} chars (budget=$budget tokens/$char_budget chars)"
                    printf '%s\n' "$summarized"
                    return 0
                fi
                log "DEBUG" "Context budget: truncating prompt for $target from ${#prompt} to $char_budget chars (~$budget tokens)"
                local truncated
                truncated=$(octo_fit_prompt_to_char_budget "$prompt" "$char_budget" $'\n\n[... truncated to fit context budget (~'"$budget"$' tokens) ...]')
                type record_oversize_event >/dev/null 2>&1 && record_oversize_event "$target" "$original_chars" "${#truncated}" "truncated" "$role" "$phase" "$budget" || true
                octo_context_budget_warning "Context budget: summarizer unavailable; truncated $target role=${role:-none} phase=${phase:-none} from ${original_chars} to ${#truncated} chars (budget=$budget tokens/$char_budget chars)"
                printf '%s\n' "$truncated"
                ;;
            truncate|*)
                log "DEBUG" "Context budget: truncating prompt for $target from ${#prompt} to $char_budget chars (~$budget tokens)"
                local truncated
                truncated=$(octo_fit_prompt_to_char_budget "$prompt" "$char_budget" $'\n\n[... truncated to fit context budget (~'"$budget"$' tokens) ...]')
                type record_oversize_event >/dev/null 2>&1 && record_oversize_event "$target" "$original_chars" "${#truncated}" "truncated" "$role" "$phase" "$budget" || true
                octo_context_budget_warning "Context budget: truncated $target role=${role:-none} phase=${phase:-none} from ${original_chars} to ${#truncated} chars (budget=$budget tokens/$char_budget chars)"
                printf '%s\n' "$truncated"
                ;;
        esac
    else
        echo "$prompt"
    fi
}

# Get model for agent type with v3.0 unified precedence
get_agent_model() {
    local agent_type="$1"
    local phase="${2:-}"
    local role="${3:-}"
    local agent_executor
    agent_executor="$(octo_agent_spec_executor "$agent_type")"
    
    # Auto-migrate stale model names on first call when the routing helper is
    # part of the current harness. dispatch.sh is also sourced independently by
    # hooks and compatibility tests, where the migration helper is optional.
    if declare -F migrate_provider_config >/dev/null 2>&1; then
        migrate_provider_config
    fi

    # Determine base provider identity through the canonical registry. Prefix
    # aliases (including retired gemini-* IDs) are resolved there, so adding a
    # provider does not require another ordered case list in dispatch.
    local provider=""
    provider="$(octo_provider_canonical "$agent_executor" 2>/dev/null || true)"

    local resolved_model
    # A model-qualified agent spec (provider:model) is an explicit seat identity.
    # Preserve the literal model instead of collapsing back to the provider default.
    if [[ "$agent_type" == *:* ]]; then
        resolved_model="${agent_type#*:}"
        [[ -n "$resolved_model" ]] || { log ERROR "Empty model in agent spec: $agent_type"; return 1; }
        if ! validate_model_name_for_provider "$provider" "$resolved_model"; then
            log ERROR "Invalid explicit model '$resolved_model' for provider '$provider'"
            return 1
        fi
    elif ! resolved_model=$(resolve_octopus_model "$provider" "$agent_type" "$phase" "$role"); then
        return 1
    fi

    # v8.31.0: Apply model restriction service if configured
    if [[ -n "$provider" ]]; then
        local fallback=""
        if fallback=$(validate_model_allowed "$provider" "$resolved_model"); then
            :
        elif [[ "$agent_type" == *:* ]]; then
            log ERROR "Explicit model '$resolved_model' is blocked for provider '$provider'; refusing to substitute '$fallback'"
            return 1
        elif [[ -n "$fallback" ]]; then
            if ! validate_model_name "$fallback"; then
                log ERROR "Invalid fallback model name for $provider"
                return 1
            fi
            echo "$fallback"
            return 0
        else
            return 1
        fi
    fi
    echo "$resolved_model"
}

# v8.31.0: Model restriction service — per-provider allowlists for cost/compliance control
# Set OCTOPUS_CODEX_ALLOWED_MODELS, OCTOPUS_AGY_ALLOWED_MODELS, etc. (comma-separated)
# Empty or unset = no restriction (all models allowed)
validate_model_allowed() {
    local provider="$1"
    local model="$2"
    local allowlist_var=""
    allowlist_var="$(octo_provider_model_allowlist_var "$provider" 2>/dev/null || true)"
    [[ -n "$allowlist_var" ]] || return 0

    local allowlist="${!allowlist_var:-}"
    [[ -z "$allowlist" ]] && return 0  # No allowlist = all allowed

    # Check if model is in comma-separated allowlist
    # v9.5: bash builtin substring check (zero subshells, was echo|grep)
    if [[ ",$allowlist," == *",$model,"* ]]; then
        return 0
    fi

    log WARN "Model '$model' blocked by $allowlist_var (allowed: $allowlist)"
    # v8.49.0: Use capability-aware fallback instead of naive first-in-list
    local fallback=""
    if command -v find_capable_fallback &>/dev/null 2>&1; then
        # Try to find a model with matching capabilities that IS in the allowlist
        local capable
        capable=$(find_capable_fallback "$model" "$provider" 2>/dev/null) || true
        if [[ -n "$capable" ]] && [[ ",$allowlist," == *",$capable,"* ]]; then
            fallback="$capable"
            log WARN "Capability-aware fallback: $fallback (matches blocked model's capabilities)"
        fi
    fi
    # Final fallback: first allowed model if capability match not found
    if [[ -z "$fallback" ]]; then
        fallback=$(echo "$allowlist" | cut -d',' -f1)
        log WARN "Falling back to first allowed: $fallback"
    fi
    echo "$fallback"
    return 1
}

apply_tool_policy() {
    local role="$1"
    local prompt="$2"
    local agent_name="${3:-}"   # v8.53.0: optional agent name for readonly check

    # Disabled by env var
    if [[ "${OCTOPUS_TOOL_POLICIES}" != "true" ]]; then
        echo "$prompt"
        return
    fi

    # v8.53.0: readonly: true in frontmatter takes precedence over role-based policy
    if [[ -n "$agent_name" ]]; then
        local is_readonly
        is_readonly=$(get_agent_readonly "$agent_name")
        if [[ "$is_readonly" == "true" ]]; then
            echo "TOOL POLICY (readonly: true): You MUST NOT use Write, Edit, or Bash for modifications. Only Read, Glob, Grep, WebSearch, and WebFetch are permitted.

${prompt}"
            return
        fi
    fi

    local policy
    policy=$(get_tool_policy "$role")

    local restriction=""
    case "$policy" in
        read_search)
            restriction="TOOL POLICY: You MUST NOT use Write, Edit, or Bash for modifications. Only Read, Glob, Grep, WebSearch, and WebFetch are permitted for this role."
            ;;
        read_exec)
            restriction="TOOL POLICY: You MUST NOT use Write or Edit. You may use Bash for read-only commands like running tests. Read, Glob, Grep are permitted."
            ;;
        read_communicate)
            restriction="TOOL POLICY: You MUST NOT use Write, Edit, or Bash. Only Read, Glob, and Grep are permitted for this role."
            ;;
        full)
            # No restrictions
            echo "$prompt"
            return
            ;;
    esac

    if [[ -n "$restriction" ]]; then
        echo "${restriction}

${prompt}"
    else
        echo "$prompt"
    fi
}

# Map namespaced council roles to their legacy persona/tool-policy semantics.
# Model/provider routing must keep the original namespaced role so council seats
# cannot inherit unrelated execution-role routes from routing.roles.
octo_persona_role() {
    case "${1:-}" in
        design-feasibility-reviewer) echo "implementer" ;;
        design-research-reviewer) echo "researcher" ;;
        design-code-reviewer) echo "code-reviewer" ;;
        design-synthesizer) echo "synthesizer" ;;
        implementation-logic-reviewer) echo "logic-reviewer" ;;
        implementation-security-reviewer) echo "security-reviewer" ;;
        implementation-architecture-reviewer) echo "arch-reviewer" ;;
        implementation-cve-reviewer) echo "cve-reviewer" ;;
        implementation-diversity-reviewer) echo "reviewer" ;;
        implementation-verifier|implementation-debater|implementation-synthesizer) echo "code-reviewer" ;;
        *) printf '%s\n' "${1:-}" ;;
    esac
}

# Apply persona instruction to a prompt
# Usage: apply_persona <role> <prompt>
# Returns: Enhanced prompt with persona prefix
apply_persona() {
    local role="$1"
    local prompt="$2"
    local skip_persona="${3:-false}"
    local agent_name="${4:-}"   # v8.53.0: optional agent name for readonly policy

    # Allow opt-out for backward compatibility
    if [[ "$skip_persona" == "true" || "$DISABLE_PERSONAS" == "true" ]]; then
        echo "$prompt"
        return
    fi

    local persona_role persona
    persona_role="$(octo_persona_role "$role")"
    persona=$(get_persona_instruction "$persona_role")

    if [[ -z "$persona" ]]; then
        echo "$prompt"
        return
    fi

    # Combine persona with original prompt
    local combined
    combined=$(cat << EOF
$persona

---

**Task:**
$prompt
EOF
)

    # v8.19.0: Apply tool policy RBAC (v8.53.0: pass agent_name for readonly check)
    combined=$(apply_tool_policy "$persona_role" "$combined" "$agent_name")

    echo "$combined"
}

# v8.53.0: Get readonly flag from agent persona frontmatter
# Returns "true" if the persona file has "readonly: true" in its YAML frontmatter.
# Falls back to user-scope agents dir (USER_AGENTS_DIR) if not in plugin personas.
# Parses only within --- frontmatter delimiters to avoid false positives in body content.
get_agent_readonly() {
    local agent_name="$1"
    local persona_file="${PLUGIN_DIR}/agents/personas/${agent_name}.md"

    if [[ ! -f "$persona_file" ]]; then
        persona_file="${USER_AGENTS_DIR:-${HOME}/.claude/agents}/${agent_name}.md"
    fi

    [[ ! -f "$persona_file" ]] && echo "false" && return

    # Extract only YAML frontmatter (between --- delimiters), then grep for readonly
    local val
    val=$(awk '
        BEGIN { in_fm=0; past_fm=0 }
        /^---$/ && !past_fm { in_fm=!in_fm; if (!in_fm) past_fm=1; next }
        in_fm && /^readonly:/ { print; exit }
    ' "$persona_file" | sed 's/readonly:[[:space:]]*//' | tr -d '"' | tr '[:upper:]' '[:lower:]')
    echo "${val:-false}"
}


# ── Extracted from orchestrate.sh ──
find_capable_fallback() {
    local blocked_model="$1"
    local provider="$2"

    # Get capabilities of the blocked model
    local catalog
    catalog=$(get_model_catalog "$blocked_model")
    local req_ctx req_tools req_images req_reasoning _prov _tier _status
    IFS='|' read -r req_ctx req_tools req_images req_reasoning _prov _tier _status <<< "$catalog"

    # Get all models for this provider, sorted by cost (cheapest first)
    local -a candidates=()
    case "$provider" in
        codex)
            candidates=(gpt-5.6-luna gpt-5.6-terra gpt-5.5 gpt-5.6-sol gpt-5.4-pro o3) ;;
        gemini|agy)
            candidates=(default) ;;
        claude)
            candidates=(claude-haiku-4.5 claude-sonnet-5 claude-opus-4.8 claude-opus-5) ;;
        openrouter)
            candidates=(z-ai/glm-5 moonshotai/kimi-k2.5 deepseek/deepseek-v4-pro deepseek/deepseek-r1-0528) ;;
        orcarouter)
            candidates=(anthropic/claude-haiku-4.5 anthropic/claude-sonnet-4.6 anthropic/claude-opus-4.8) ;;
        perplexity)
            candidates=(sonar sonar-pro) ;;
        cursor-agent)
            candidates=(auto composer-2.5-fast composer-2.5 gpt-5.6-sol-high claude-sonnet-5-thinking-high) ;;
    esac

    for candidate in "${candidates[@]}"; do
        [[ "$candidate" == "$blocked_model" ]] && continue

        local c_catalog
        c_catalog=$(get_model_catalog "$candidate")
        local c_ctx c_tools c_images c_reasoning
        IFS='|' read -r c_ctx c_tools c_images c_reasoning _ _ _ <<< "$c_catalog"

        # Check capability match
        [[ "$req_ctx" =~ ^[0-9]+$ && "$c_ctx" =~ ^[0-9]+$ ]] || continue
        (( c_ctx < req_ctx )) && continue
        [[ "$req_tools" == "yes" && "$c_tools" != "yes" ]] && continue
        [[ "$req_images" == "yes" && "$c_images" != "yes" ]] && continue
        [[ "$req_reasoning" == "yes" && "$c_reasoning" != "yes" ]] && continue

        echo "$candidate"
        return 0
    done

    # No capable fallback found
    return 1
}
