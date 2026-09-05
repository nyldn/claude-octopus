#!/usr/bin/env bash
# Canonical provider identity registry.
# Source-safe and Bash 3.2 compatible: no associative arrays, no shell options.
#
# Columns: id|aliases|command|organization|capabilities
# Capabilities describe which shared interfaces should expose the provider and
# stable routing traits such as whether it accepts cross-vendor model IDs.
# Every provider must implement the universal baseline below. Optional capability
# omissions must be documented in octo_provider_limitations_rows().

OCTO_PROVIDER_BASELINE_CAPABILITIES="model-config dispatch env"
OCTO_PROVIDER_OPTIONAL_CAPABILITIES="council health detect"

octo_provider_registry_rows() {
    cat <<'EOF'
codex|openai,gpt*|codex|openai|model-config,council,health,detect,dispatch,env
commandcode|command-code*|command-code|commandcode|model-config,council,health,detect,dispatch,env,model-gateway,custom-model-auto
claude|anthropic,sonnet*,opus*|claude|anthropic|model-config,council,health,detect,dispatch,env
claude-sdk|claude-agent*|claude-agent|anthropic|model-config,health,detect,dispatch,env
agy|antigravity*,gemini,gemini-*|agy|google|model-config,council,health,detect,dispatch,env,custom-model-auto
perplexity||perplexity|perplexity|model-config,health,detect,dispatch,env
opencode||opencode|opencode|model-config,council,detect,dispatch,env,model-gateway,custom-model-auto
openrouter||openrouter|openrouter|model-config,council,health,detect,dispatch,env,model-gateway,custom-model-auto
orcarouter||orcarouter|orcarouter|model-config,council,health,detect,dispatch,env,model-gateway,custom-model-auto
atlascloud|atlas,atlas-cloud|atlascloud|atlascloud|model-config,health,detect,dispatch,env,model-gateway,custom-model-auto
openai-compatible||openai-compatible|openai-compatible|model-config,council,detect,dispatch,env,model-gateway,custom-model-auto
openai-tools||openai-compatible|openai-compatible|model-config,council,dispatch,env,model-gateway,custom-model-auto
openai-compatible-agent||openai-compatible|openai-compatible|model-config,dispatch,env,model-gateway,custom-model-auto
cursor-agent|cursor|cursor-agent|cursor|model-config,council,health,detect,dispatch,env,model-gateway,custom-model-auto
grok|xai|grok|xai|model-config,health,detect,dispatch,env,custom-model-auto
qwen||qwen|alibaba|model-config,council,health,detect,dispatch,env,custom-model-auto
ollama|local|ollama|local|model-config,health,detect,dispatch,env,model-gateway,custom-model-auto
copilot|github-copilot|copilot|github|model-config,health,detect,dispatch,env,model-gateway
vibe||vibe|mistral|model-config,health,detect,dispatch,env,custom-model-auto
kimi||kimi|moonshot|model-config,health,detect,dispatch,env,custom-model-auto
EOF
}

# Runtime metadata is kept in a keyed companion table so the original
# five-column identity contract remains backward compatible for third-party
# consumers. Provider Registry 2.0 validates exact ID parity between both
# tables; adding a provider to only one side is therefore a hard failure.
#
# Columns:
# id|auth_mode|health_handler|detect_handler|model_env|default_model_resolver|
# context_tokens|cost_class|sandbox_class|independence_org
octo_provider_runtime_rows() {
    cat <<'EOF'
codex|api-key-or-cli-session|check_provider_health|detect_providers|OCTOPUS_CODEX_MODEL|resolve_octopus_model|12000|variable|plugin-isolated|openai
commandcode|api-key-or-cli-session|check_provider_health|detect_providers|OCTOPUS_COMMANDCODE_MODEL|resolve_octopus_model|12000|variable|provider-managed|commandcode
claude|cli-session|check_provider_health|detect_providers|OCTOPUS_CLAUDE_MODEL|resolve_octopus_model|12000|bundled|host-managed|anthropic
claude-sdk|api-key|check_provider_health|detect_providers|OCTOPUS_CLAUDE_SDK_MODEL|resolve_octopus_model|1000000|metered|provider-managed|anthropic
agy|cli-session|check_provider_health|detect_providers|OCTOPUS_AGY_MODEL|resolve_octopus_model|12000|bundled|plugin-isolated|google
perplexity|api-key|check_provider_health|detect_providers|OCTOPUS_PERPLEXITY_MODEL|resolve_octopus_model|12000|metered|provider-managed|perplexity
opencode|provider-config|none|detect_providers|OCTOPUS_OPENCODE_MODEL|resolve_octopus_model|12000|variable|provider-managed|opencode
openrouter|api-key|check_provider_health|detect_providers|OCTOPUS_OPENROUTER_MODEL|resolve_octopus_model|12000|metered|provider-managed|openrouter
orcarouter|api-key|check_provider_health|detect_providers|OCTOPUS_ORCAROUTER_MODEL|resolve_octopus_model|12000|metered|provider-managed|orcarouter
atlascloud|api-key|check_provider_health|detect_providers|OCTOPUS_ATLASCLOUD_MODEL|resolve_octopus_model|12000|metered|plugin-isolated|atlascloud
openai-compatible|api-key|none|detect_providers|OCTOPUS_OPENAI_COMPATIBLE_MODEL|resolve_octopus_model|12000|metered|provider-managed|openai-compatible
openai-tools|api-key|none|none|OCTOPUS_OPENAI_TOOLS_MODEL|resolve_octopus_model|12000|metered|host-managed|openai-compatible
openai-compatible-agent|api-key|none|none|OCTOPUS_OPENAI_COMPATIBLE_AGENT_MODEL|resolve_octopus_model|12000|metered|plugin-isolated|openai-compatible
cursor-agent|api-key-or-cli-session|check_provider_health|detect_providers|OCTOPUS_CURSOR_AGENT_MODEL|resolve_octopus_model|12000|bundled|provider-managed|cursor
grok|api-key-or-cli-session|check_provider_health|detect_providers|OCTOPUS_GROK_MODEL|resolve_octopus_model|12000|metered|plugin-isolated|xai
qwen|api-key-or-cli-session|check_provider_health|detect_providers|OCTOPUS_QWEN_MODEL|resolve_octopus_model|12000|variable|provider-managed|alibaba
ollama|local-runtime|check_provider_health|detect_providers|OCTOPUS_OLLAMA_MODEL|resolve_octopus_model|12000|local|local-runtime|local
copilot|cli-session|check_provider_health|detect_providers|OCTOPUS_COPILOT_MODEL|resolve_octopus_model|12000|bundled|provider-managed|github
vibe|api-key-or-cli-session|check_provider_health|detect_providers|OCTOPUS_VIBE_MODEL|resolve_octopus_model|12000|metered|provider-managed|mistral
kimi|api-key-or-cli-session|check_provider_health|detect_providers|OCTOPUS_KIMI_MODEL|resolve_octopus_model|12000|metered|provider-managed|moonshot
EOF
}

octo_provider_normalize() {
    printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | tr -d ' ,'
}

octo_provider_canonical() {
    local requested normalized id aliases command org caps alias alias_base
    local best_id="" best_len=0 id_len old_ifs
    requested="${1:-}"
    normalized="$(octo_provider_normalize "$requested")"
    [[ -n "$normalized" ]] || return 1

    # Exact canonical IDs always win over aliases and prefixes.
    while IFS='|' read -r id aliases command org caps; do
        if [[ "$normalized" == "$id" ]]; then
            printf '%s\n' "$id"
            return 0
        fi
    done <<EOF
$(octo_provider_registry_rows)
EOF

    # Aliases are exact unless explicitly suffixed with '*'.
    while IFS='|' read -r id aliases command org caps; do
        old_ifs="$IFS"
        IFS=','
        for alias in $aliases; do
            IFS="$old_ifs"
            [[ -n "$alias" ]] || continue
            case "$alias" in
                *'*')
                    alias_base="${alias%\*}"
                    if [[ "$normalized" == "$alias_base"* ]]; then
                        printf '%s\n' "$id"
                        return 0
                    fi
                    ;;
                *)
                    if [[ "$normalized" == "$alias" ]]; then
                        printf '%s\n' "$id"
                        return 0
                    fi
                    ;;
            esac
            IFS=','
        done
        IFS="$old_ifs"
    done <<EOF
$(octo_provider_registry_rows)
EOF

    # Agent variants such as commandcode-research use canonical-ID prefixes.
    # Choose the longest matching ID so claude-sdk-* cannot collapse to claude.
    while IFS='|' read -r id aliases command org caps; do
        if [[ "$normalized" == "$id-"* ]]; then
            id_len=${#id}
            if (( id_len > best_len )); then
                best_id="$id"
                best_len=$id_len
            fi
        fi
    done <<EOF
$(octo_provider_registry_rows)
EOF
    [[ -n "$best_id" ]] || return 1
    printf '%s\n' "$best_id"
}

# Preserve the public provider labels emitted by existing runtime artifacts,
# but resolve every executor alias through the canonical registry first.
octo_provider_identity_from_agent_type() {
    local agent_type="${1:-}" canonical
    agent_type="${agent_type%%:*}"
    canonical="$(octo_provider_canonical "$agent_type" 2>/dev/null)" || {
        printf 'unknown\n'
        return 0
    }
    case "$canonical" in
        openai-compatible|openai-tools|openai-compatible-agent) printf 'openai-compatible\n' ;;
        claude|claude-sdk) printf 'anthropic\n' ;;
        agy) printf 'google\n' ;;
        *) printf '%s\n' "$canonical" ;;
    esac
}

octo_provider_valid() {
    octo_provider_canonical "${1:-}" >/dev/null 2>&1
}

octo_provider_field() {
    local requested field canonical id aliases command org caps
    requested="$1"
    field="$2"
    canonical="$(octo_provider_canonical "$requested")" || return 1
    while IFS='|' read -r id aliases command org caps; do
        [[ "$id" == "$canonical" ]] || continue
        case "$field" in
            id) printf '%s\n' "$id" ;;
            aliases) printf '%s\n' "$aliases" ;;
            command) printf '%s\n' "$command" ;;
            organization|org) printf '%s\n' "$org" ;;
            capabilities) printf '%s\n' "$caps" ;;
            *) return 1 ;;
        esac
        return 0
    done <<EOF
$(octo_provider_registry_rows)
EOF
    return 1
}

octo_provider_command() { octo_provider_field "$1" command; }
octo_provider_org() { octo_provider_field "$1" organization; }

octo_provider_runtime_field() {
    local requested field canonical id auth health detect model_env resolver context cost sandbox independence
    requested="$1"
    field="$2"
    canonical="$(octo_provider_canonical "$requested")" || return 1
    while IFS='|' read -r id auth health detect model_env resolver context cost sandbox independence; do
        [[ "$id" == "$canonical" ]] || continue
        case "$field" in
            id) printf '%s\n' "$id" ;;
            auth_mode|auth) printf '%s\n' "$auth" ;;
            health_handler|health) printf '%s\n' "$health" ;;
            detect_handler|detect) printf '%s\n' "$detect" ;;
            model_env) printf '%s\n' "$model_env" ;;
            default_model_resolver|model_resolver) printf '%s\n' "$resolver" ;;
            context_tokens|context) printf '%s\n' "$context" ;;
            cost_class|cost) printf '%s\n' "$cost" ;;
            sandbox_class|sandbox) printf '%s\n' "$sandbox" ;;
            independence_org|independence_organization) printf '%s\n' "$independence" ;;
            *) return 1 ;;
        esac
        return 0
    done <<EOF
$(octo_provider_runtime_rows)
EOF
    return 1
}

octo_provider_auth_mode() { octo_provider_runtime_field "$1" auth_mode; }
octo_provider_health_handler() { octo_provider_runtime_field "$1" health_handler; }
octo_provider_detect_handler() { octo_provider_runtime_field "$1" detect_handler; }
octo_provider_model_env() { octo_provider_runtime_field "$1" model_env; }
octo_provider_default_model_resolver() { octo_provider_runtime_field "$1" default_model_resolver; }
octo_provider_context_tokens() { octo_provider_runtime_field "$1" context_tokens; }
octo_provider_cost_class() { octo_provider_runtime_field "$1" cost_class; }
octo_provider_sandbox_class() { octo_provider_runtime_field "$1" sandbox_class; }
octo_provider_independence_org() { octo_provider_runtime_field "$1" independence_org; }

octo_provider_runtime_ids() {
    local id auth health detect model_env resolver context cost sandbox independence out=""
    while IFS='|' read -r id auth health detect model_env resolver context cost sandbox independence; do
        out="${out}${out:+ }${id}"
    done <<EOF
$(octo_provider_runtime_rows)
EOF
    printf '%s\n' "$out"
}

octo_provider_has_capability() {
    local provider capability caps
    provider="$1"
    capability="$2"
    caps="$(octo_provider_field "$provider" capabilities)" || return 1
    case ",$caps," in
        *",$capability,"*) return 0 ;;
    esac
    return 1
}

# shellcheck disable=SC2120 # Optional capability is used by cross-file consumers.
octo_provider_ids() {
    local capability="${1:-}" id aliases command org caps out=""
    while IFS='|' read -r id aliases command org caps; do
        if [[ -n "$capability" ]]; then
            case ",$caps," in
                *",$capability,"*) ;;
                *) continue ;;
            esac
        fi
        out="${out}${out:+ }${id}"
    done <<EOF
$(octo_provider_registry_rows)
EOF
    printf '%s\n' "$out"
}


octo_provider_jq_contract_json() {
    command -v jq >/dev/null 2>&1 || return 1
    octo_provider_registry_rows | jq -R -s '
      split("\n")
      | map(select(length > 0) | split("|")
          | {id: .[0], aliases: ((.[1] // "") | split(",") | map(select(length > 0)))}) as $rows
      | {
          exact: (reduce $rows[] as $row ({};
            . + {($row.id): $row.id}
              + (reduce ($row.aliases[] | select(endswith("*") | not)) as $alias
                   ({}; . + {($alias): $row.id})))),
          prefixes: ([
            $rows[] as $row
            | ({prefix: ($row.id + "-"), id: $row.id}),
              ($row.aliases[] | select(endswith("*"))
               | {prefix: .[0:-1], id: $row.id})
          ] | sort_by(.prefix | length) | reverse)
        }
    '
}

octo_provider_limitations_rows() {
    cat <<'EOF'
claude-sdk|council|sdk-agent-runtime-is-not-a-supported-council-seat
perplexity|council|research-api-runtime-is-not-a-supported-council-seat
opencode|health|no-provider-specific-health-probe
atlascloud|council|atlascloud-runtime-is-not-a-supported-council-seat
openai-compatible|health|generic-api-provider-has-no-provider-specific-health-probe
openai-tools|health|generic-tool-loop-has-no-provider-specific-health-probe
openai-tools|detect|api-configured-runtime-has-no-local-cli-detection
openai-compatible-agent|council|agent-runtime-is-not-a-supported-council-seat
openai-compatible-agent|health|generic-agent-runtime-has-no-provider-specific-health-probe
openai-compatible-agent|detect|api-configured-runtime-has-no-local-cli-detection
grok|council|grok-runtime-is-not-a-supported-council-seat
ollama|council|local-runtime-is-not-a-supported-council-seat
copilot|council|copilot-runtime-is-not-a-supported-council-seat
vibe|council|vibe-runtime-is-not-a-supported-council-seat
kimi|council|kimi-runtime-is-not-a-supported-council-seat
EOF
}

octo_provider_limitation_reason() {
    local requested capability canonical id cap reason
    requested="$1"
    capability="$2"
    canonical="$(octo_provider_canonical "$requested")" || return 1
    while IFS='|' read -r id cap reason; do
        if [[ "$id" == "$canonical" && "$cap" == "$capability" ]]; then
            printf '%s\n' "$reason"
            return 0
        fi
    done <<EOF
$(octo_provider_limitations_rows)
EOF
    return 1
}

octo_provider_validate_contracts() {
    local id aliases command org caps capability reason key seen=""

    while IFS='|' read -r id aliases command org caps; do
        [[ -n "$id" && -n "$command" && -n "$org" && -n "$caps" ]] || {
            echo "provider registry: incomplete metadata for '$id'" >&2
            return 1
        }
        for capability in $OCTO_PROVIDER_BASELINE_CAPABILITIES; do
            octo_provider_has_capability "$id" "$capability" || {
                echo "provider registry: '$id' is missing baseline capability '$capability'" >&2
                return 1
            }
        done
        for capability in $OCTO_PROVIDER_OPTIONAL_CAPABILITIES; do
            if octo_provider_has_capability "$id" "$capability"; then
                if octo_provider_limitation_reason "$id" "$capability" >/dev/null 2>&1; then
                    echo "provider registry: '$id' declares '$capability' and a contradictory limitation" >&2
                    return 1
                fi
            else
                reason="$(octo_provider_limitation_reason "$id" "$capability" 2>/dev/null || true)"
                [[ -n "$reason" ]] || {
                    echo "provider registry: '$id' omits '$capability' without an explicit limitation" >&2
                    return 1
                }
            fi
        done
    done <<EOF
$(octo_provider_registry_rows)
EOF

    while IFS='|' read -r id capability reason; do
        [[ -n "$id" && -n "$capability" && -n "$reason" ]] || {
            echo "provider registry: malformed limitation row" >&2
            return 1
        }
        octo_provider_valid "$id" || {
            echo "provider registry: limitation references unknown provider '$id'" >&2
            return 1
        }
        case " $OCTO_PROVIDER_OPTIONAL_CAPABILITIES " in
            *" $capability "*) ;;
            *)
                echo "provider registry: limitation for non-optional capability '$capability'" >&2
                return 1
                ;;
        esac
        key="$id:$capability"
        case " $seen " in
            *" $key "*)
                echo "provider registry: duplicate limitation '$key'" >&2
                return 1
                ;;
        esac
        seen="${seen}${seen:+ }${key}"
        if octo_provider_has_capability "$id" "$capability"; then
            echo "provider registry: limitation contradicts declared capability '$key'" >&2
            return 1
        fi
    done <<EOF
$(octo_provider_limitations_rows)
EOF
    local runtime_ids registry_ids auth health detect model_env resolver context cost sandbox independence
    runtime_ids="$(octo_provider_runtime_ids | tr ' ' '\n' | LC_ALL=C sort)"
    registry_ids="$(octo_provider_ids | tr ' ' '\n' | LC_ALL=C sort)"
    [[ "$runtime_ids" == "$registry_ids" ]] || {
        echo "provider registry: runtime metadata inventory differs from canonical provider inventory" >&2
        return 1
    }

    while IFS='|' read -r id auth health detect model_env resolver context cost sandbox independence; do
        [[ -n "$id" && -n "$auth" && -n "$health" && -n "$detect" && -n "$model_env" && -n "$resolver" && -n "$context" && -n "$cost" && -n "$sandbox" && -n "$independence" ]] || {
            echo "provider registry: incomplete runtime metadata for '$id'" >&2
            return 1
        }
        case "$auth" in api-key|cli-session|api-key-or-cli-session|local-runtime|provider-config) ;; *) echo "provider registry: invalid auth mode '$auth' for '$id'" >&2; return 1 ;; esac
        case "$health" in check_provider_health|none) ;; *) echo "provider registry: invalid health handler '$health' for '$id'" >&2; return 1 ;; esac
        case "$detect" in detect_providers|none) ;; *) echo "provider registry: invalid detect handler '$detect' for '$id'" >&2; return 1 ;; esac
        [[ "$model_env" =~ ^[A-Z][A-Z0-9_]*$ ]] || { echo "provider registry: invalid model env '$model_env' for '$id'" >&2; return 1; }
        [[ "$resolver" == "resolve_octopus_model" ]] || { echo "provider registry: invalid model resolver '$resolver' for '$id'" >&2; return 1; }
        [[ "$context" =~ ^[0-9]+$ && "$context" -gt 0 ]] || { echo "provider registry: invalid context ceiling '$context' for '$id'" >&2; return 1; }
        case "$cost" in bundled|metered|local|variable) ;; *) echo "provider registry: invalid cost class '$cost' for '$id'" >&2; return 1 ;; esac
        case "$sandbox" in host-managed|plugin-isolated|provider-managed|local-runtime) ;; *) echo "provider registry: invalid sandbox class '$sandbox' for '$id'" >&2; return 1 ;; esac
        if octo_provider_has_capability "$id" health; then
            [[ "$health" != "none" ]] || { echo "provider registry: '$id' declares health capability without a handler" >&2; return 1; }
        else
            [[ "$health" == "none" ]] || { echo "provider registry: '$id' has a health handler without the capability" >&2; return 1; }
        fi
        if octo_provider_has_capability "$id" detect; then
            [[ "$detect" != "none" ]] || { echo "provider registry: '$id' declares detect capability without a handler" >&2; return 1; }
        else
            [[ "$detect" == "none" ]] || { echo "provider registry: '$id' has a detect handler without the capability" >&2; return 1; }
        fi
    done <<EOF
$(octo_provider_runtime_rows)
EOF
    return 0
}
