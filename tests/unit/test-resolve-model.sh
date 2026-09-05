#!/usr/bin/env bash
# Test: resolve_octopus_model (v3.0 refactor)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "resolve_octopus_model (v3.0 refactor)"

PLUGIN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ORCHESTRATE_SH="${PLUGIN_DIR}/scripts/orchestrate.sh"


echo "Testing resolve_octopus_model (v3.0)"
echo "======================================"

# Mock Workspace and config for testing
export CLAUDE_OCTOPUS_WORKSPACE="/tmp/octopus-test-v3"
rm -rf "$CLAUDE_OCTOPUS_WORKSPACE"
mkdir -p "$CLAUDE_OCTOPUS_WORKSPACE/.claude-octopus/config"
CONFIG_FILE="$CLAUDE_OCTOPUS_WORKSPACE/.claude-octopus/config/providers.json"

# Mock HOME so it picks up our config
export HOME_ORIG="$HOME"
export HOME="$CLAUDE_OCTOPUS_WORKSPACE"

# Mock log function
log() { :; }
export -f log

# Source only the minimal files needed for resolve_octopus_model.
# Sourcing the full orchestrate.sh can hang on VPS environments due to
# provider detection, version checks, and heavy initialization code.
export CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR"
export CLAUDE_CODE_SESSION=""
export SUPPORTS_OPUS_4_7="${SUPPORTS_OPUS_4_7:-false}"
source "${PLUGIN_DIR}/scripts/lib/model-resolver.sh"

assert_eq() {
    local actual="$1"
    local expected="$2"
    local desc="$3"
    test_case "$desc"
    if [[ "$actual" == "$expected" ]]; then
        test_pass
    else
        test_fail "expected=[$expected] got=[$actual]"
        return 0
    fi
}

logged_load_error=""
log() { logged_load_error="$1:$2"; }
_model_resolver_load_error "catalog unavailable"
assert_eq "$logged_load_error" "ERROR:catalog unavailable" "Load failures use the project logger when available"
unset -f log
fallback_load_error="$(_model_resolver_load_error "catalog unavailable" 2>&1)"
assert_eq "$fallback_load_error" "model-resolver: catalog unavailable" "Load failures retain a bootstrap stderr fallback"
log() { :; }
export -f log

# Clear model resolution caches (in-memory + persistent file)
# Must be called between tests that change env vars or config files
clear_model_cache() {
    # Clear all in-memory cache variables
    for var in $(compgen -v | grep '^_OCTO_MODEL_CACHE_'); do
        unset "$var" 2>/dev/null || true
    done
    # Clear persistent file cache
    rm -f /tmp/octo-model-cache-*.json 2>/dev/null || true
}

# Test 1: Hard-coded defaults
clear_model_cache
assert_eq "$(resolve_octopus_model "codex" "codex")" "gpt-5.6-sol" "Default codex"
clear_model_cache
assert_eq "$(resolve_octopus_model "agy" "agy")" "default" "Default Antigravity"
clear_model_cache
assert_eq "$(resolve_octopus_model "gemini" "gemini")" "default" "Legacy Gemini ID resolves through Antigravity"

# Test 2: Env var overrides
clear_model_cache
export OCTOPUS_CODEX_MODEL="env-model"
assert_eq "$(resolve_octopus_model "codex" "codex")" "env-model" "Env var override"
unset OCTOPUS_CODEX_MODEL

# Test 3: Config file defaults (v3.0)
clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": {
    "codex": { "default": "config-default" }
  }
}
EOF
assert_eq "$(resolve_octopus_model "codex" "codex")" "config-default" "Config file default"

# Explicit-only frontier models must not become routine defaults, even if a
# providers.json file was hand-edited. Session pins remain deliberate and valid.
clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": { "codex": { "default": "gpt-6-astra" } }
}
EOF
assert_eq "$(resolve_octopus_model "codex" "codex")" "gpt-5.6-sol" "Explicit-only Astra is rejected as config default"
clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "overrides": { "codex": "gpt-6-astra" },
  "providers": { "codex": { "default": "gpt-5.6-sol" } }
}
EOF
assert_eq "$(resolve_octopus_model "codex" "codex")" "gpt-6-astra" "Explicit Astra session override remains valid"

clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": {
    "codex": {
      "default": "gpt-5.6-sol",
      "frontier": "gpt-6-astra",
      "roles": { "reviewer": "gpt-6-astra" }
    }
  },
  "cost_mode": "premium",
  "tiers": { "premium": { "codex": "gpt-6-astra" } }
}
EOF
assert_eq "$(resolve_octopus_model "codex" "codex-frontier")" "gpt-5.6-sol" "Explicit-only Astra is rejected as capability mapping"
clear_model_cache
assert_eq "$(resolve_octopus_model "codex" "codex" "review" "reviewer")" "gpt-5.6-sol" "Explicit-only Astra is rejected as provider-role default"
clear_model_cache
assert_eq "$(resolve_octopus_model "codex" "codex")" "gpt-5.6-sol" "Explicit-only Astra is rejected as cost-tier mapping"

clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": { "codex": { "default": "gpt-5.6-sol" } },
  "routing": { "phases": { "review": "gpt-6-astra" } }
}
EOF
assert_eq "$(resolve_octopus_model "codex" "codex" "review")" "gpt-5.6-sol" "Explicit-only Astra is rejected as persistent phase route"

# Test 4: Capability mapping
clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": {
    "codex": { "default": "config-default", "spark": "config-spark" }
  }
}
EOF
assert_eq "$(resolve_octopus_model "codex" "codex-spark")" "config-spark" "Capability mapping"

# Test 5: Phase routing
clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": {
    "codex": { "default": "config-default" }
  },
  "routing": {
    "phases": { "deliver": "deliver-model" }
  }
}
EOF
assert_eq "$(resolve_octopus_model "codex" "codex" "deliver")" "deliver-model" "Phase routing"

# Test 5b: Literal object role routing preserves exact provider model IDs
clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": {
    "commandcode": { "default": "deepseek/deepseek-v4-pro" }
  },
  "routing": {
    "roles": {
      "researcher": {
        "provider": "commandcode",
        "model": "minimaxai/minimax-m3"
      }
    }
  }
}
EOF
assert_eq "$(resolve_octopus_model "commandcode" "commandcode-research" "probe" "researcher")" "minimaxai/minimax-m3" "Literal object role routing"

# Test 5b.1: Explicit role routing outranks a provider-local role default.
clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": {
    "commandcode": {
      "default": "deepseek/deepseek-v4-pro",
      "roles": { "researcher": "deepseek/deepseek-v4-flash" }
    }
  },
  "routing": {
    "roles": {
      "researcher": {
        "provider": "commandcode",
        "model": "minimaxai/minimax-m3"
      }
    }
  }
}
EOF
assert_eq "$(resolve_octopus_model "commandcode" "commandcode-research" "probe" "researcher")" "minimaxai/minimax-m3" "Explicit role route beats provider-local role default"

# Test 5c: Literal object phase routing preserves exact provider model IDs
clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": {
    "commandcode": { "default": "deepseek/deepseek-v4-pro" }
  },
  "routing": {
    "phases": {
      "research": {
        "provider": "commandcode",
        "model": "minimaxai/minimax-m3"
      }
    }
  }
}
EOF
assert_eq "$(resolve_octopus_model "commandcode" "commandcode-research" "research" "")" "minimaxai/minimax-m3" "Literal object phase routing"

# Test 5d: Cross-provider literal role route does not leak its model
clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": {
    "commandcode": { "default": "deepseek/deepseek-v4-pro" }
  },
  "routing": {
    "roles": {
      "researcher": {
        "provider": "claude",
        "model": "claude-sonnet-4.6"
      }
    },
    "phases": {
      "research": {
        "provider": "commandcode",
        "model": "minimaxai/minimax-m3"
      }
    }
  }
}
EOF
assert_eq "$(resolve_octopus_model "commandcode" "commandcode-research" "research" "researcher")" "minimaxai/minimax-m3" "Cross-provider literal role falls through to matching phase"

# Regression: object-route provider aliases are canonicalized before comparison.
clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": { "agy": { "default": "agy-default" } },
  "routing": {
    "phases": {
      "research": { "provider": "antigravity", "model": "agy-alias-phase" }
    }
  }
}
EOF
assert_eq "$(resolve_octopus_model "agy" "agy" "research" "")" "agy-alias-phase" "Literal object phase routing canonicalizes provider aliases"

# Regression: a cross-provider legacy role route must not mask a matching
# literal object phase route for the provider being resolved.
clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": { "commandcode": { "default": "deepseek/deepseek-v4-pro" } },
  "routing": {
    "roles": { "researcher": "claude:sonnet" },
    "phases": {
      "research": { "provider": "commandcode", "model": "minimaxai/minimax-m3" }
    }
  }
}
EOF
assert_eq "$(resolve_octopus_model "commandcode" "commandcode-research" "research" "researcher")" "minimaxai/minimax-m3" "Cross-provider legacy role falls through to matching object phase"

# Regression: a bare provider alias keeps role-provider precedence over a
# legacy phase model route, while model-like gpt-* values remain model routes.
clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": { "agy": { "default": "agy-default" } },
  "routing": {
    "roles": { "researcher": "gemini" },
    "phases": { "research": "agy-phase-model" }
  }
}
EOF
assert_eq "$(resolve_octopus_model "agy" "agy-research" "research" "researcher")" "agy-default" "Bare gemini alias preserves matching role-provider precedence"

clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": { "codex": { "default": "gpt-default" } },
  "routing": {
    "roles": { "logic-reviewer": "gpt-5.5" },
    "phases": { "review": "gpt-phase-model" }
  }
}
EOF
assert_eq "$(resolve_octopus_model "codex" "codex" "review" "logic-reviewer")" "gpt-5.5" "Bare gpt model keeps role precedence over a phase route"

clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": { "commandcode": { "default": "deepseek/deepseek-v4-pro" } },
  "routing": {
    "roles": { "logic-reviewer": "deepseek/deepseek-v4-pro" },
    "phases": { "review": "minimaxai/minimax-m3" }
  }
}
EOF
assert_eq "$(resolve_octopus_model "commandcode" "commandcode" "review" "logic-reviewer")" "deepseek/deepseek-v4-pro" "Command Code gateway keeps a vendor-qualified bare role over its phase route"

clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": { "openrouter": { "default": "openai/gpt-5.5" } },
  "routing": {
    "roles": { "logic-reviewer": "anthropic/claude-sonnet-4" },
    "phases": { "review": "openai/gpt-5.5" }
  }
}
EOF
assert_eq "$(resolve_octopus_model "openrouter" "openrouter" "review" "logic-reviewer")" "anthropic/claude-sonnet-4" "OpenRouter gateway keeps a cross-vendor bare role over its phase route"

clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": { "qwen": { "default": "qwen3-coder" } },
  "routing": {
    "roles": { "logic-reviewer": "qwen3-coder" },
    "phases": { "review": "qwen3-max" }
  }
}
EOF
assert_eq "$(resolve_octopus_model "qwen" "qwen" "review" "logic-reviewer")" "qwen3-coder" "Qwen keeps its native bare role over a phase route"

clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": { "perplexity": { "default": "sonar-pro" } },
  "routing": {
    "roles": { "researcher": "sonar-pro" },
    "phases": { "research": "sonar" }
  }
}
EOF
assert_eq "$(resolve_octopus_model "perplexity" "perplexity" "research" "researcher")" "sonar-pro" "Perplexity keeps its native bare role over a phase route"

clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": { "perplexity": { "default": "sonar-pro" } },
  "routing": {
    "roles": { "researcher": "gpt-5.5" },
    "phases": { "research": "sonar-pro" }
  }
}
EOF
assert_eq "$(resolve_octopus_model "perplexity" "perplexity" "research" "researcher")" "sonar-pro" "Perplexity rejects a known cross-vendor bare role in favor of its phase route"

for default_provider in grok vibe; do
    clear_model_cache
    cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": { "$default_provider": { "default": "default" } },
  "routing": {
    "roles": { "logic-reviewer": "default" },
    "phases": { "review": "${default_provider}-phase" }
  }
}
EOF
    assert_eq "$(resolve_octopus_model "$default_provider" "$default_provider" "review" "logic-reviewer")" "default" "$default_provider keeps its provider-local default role sentinel over a phase route"
done

test_case "catalogued native models resolve to their registry organization"
catalog_family_mismatches=""
while IFS= read -r catalog_model; do
    [[ -n "$catalog_model" ]] || continue
    catalog_provider="$(get_model_capability "$catalog_model" provider)"
    octo_provider_has_capability "$catalog_provider" model-gateway && continue
    catalog_org="$(octo_provider_org "$catalog_provider")"
    route_family="$(_octo_route_value_model_family "$catalog_model")"
    if [[ "$route_family" != "$catalog_org" ]]; then
        catalog_family_mismatches="${catalog_family_mismatches}${catalog_model}:${route_family}->${catalog_org} "
    fi
done < <(octo_model_ids)
if [[ -z "$catalog_family_mismatches" ]]; then
    test_pass
else
    test_fail "model catalog family drift: $catalog_family_mismatches"
fi

# Registry wildcard aliases are data, not shell globs. A matching filesystem
# entry must not replace the literal gpt* alias before its base is compared.
alias_glob_dir="$TEST_TMP_DIR/provider-alias-glob"
mkdir -p "$alias_glob_dir"
: > "$alias_glob_dir/gpt-collision"
previous_pwd="$PWD"
cd "$alias_glob_dir"
alias_glob_result="$(_octo_canonical_known_provider_name "gpt")"
cd "$previous_pwd"
assert_eq "$alias_glob_result" "codex" "Provider wildcard aliases ignore matching filesystem entries"

# Test 6: Recursive reference (codex:spark)
clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": {
    "codex": { "default": "config-default", "spark": "config-spark" }
  },
  "routing": {
    "phases": { "deliver": "codex:spark" }
  }
}
EOF
assert_eq "$(resolve_octopus_model "codex" "codex" "deliver")" "config-spark" "Recursive reference"

# Recursive provider references must use the canonical provider for the lookup,
# not only for the cross-provider comparison.
clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": {
    "codex": { "default": "config-default", "spark": "config-spark" }
  },
  "routing": {
    "phases": { "deliver": "openai:spark" }
  }
}
EOF
assert_eq "$(resolve_octopus_model "codex" "codex" "deliver")" "config-spark" "Recursive provider alias uses canonical model namespace"

# Test 7: Tier mapping
clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": {
    "codex": { "default": "config-default", "mini": "config-mini" }
  },
  "tiers": {
    "budget": { "codex": "mini" }
  }
}
EOF
export OCTOPUS_COST_MODE="budget"
assert_eq "$(resolve_octopus_model "codex" "codex")" "config-mini" "Tier mapping (budget)"
unset OCTOPUS_COST_MODE

# Test 8: Provider-scoped role routing wins over phase routing
clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": {
    "codex": { "default": "deepseek-ai/DeepSeek-V4-Pro", "logic_review": "gpt-5.5" },
    "claude": { "default": "claude-sonnet-4.6", "review": "claude-review-phase" },
    "agy": { "default": "default" }
  },
  "routing": {
    "phases": { "review": "claude:review" },
    "roles": { "logic-reviewer": "codex:logic_review" }
  }
}
EOF
assert_eq "$(resolve_octopus_model "codex" "codex" "review" "logic-reviewer")" "gpt-5.5" "Provider-scoped role routing overrides review phase routing for matching provider"
clear_model_cache
assert_eq "$(resolve_octopus_model "claude" "claude-sonnet" "review" "logic-reviewer")" "claude-review-phase" "Cross-provider role routing falls back to matching phase routing for claude"
clear_model_cache
assert_eq "$(resolve_octopus_model "gemini" "gemini" "review" "logic-reviewer")" "default" "Legacy Gemini routing resolves through Antigravity without cross-provider model leakage"
clear_model_cache
assert_eq "$(resolve_octopus_model "codex" "codex" "review" "arch-reviewer")" "deepseek-ai/DeepSeek-V4-Pro" "Cross-provider phase routing does not leak claude model to codex"

clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": {
    "codex": { "default": "deepseek-ai/DeepSeek-V4-Pro" },
    "claude": { "default": "claude-sonnet-4.6", "review": "claude-review-phase" }
  },
  "routing": {
    "phases": { "review": "claude:review" },
    "roles": { "logic-reviewer": "gpt-5.5" }
  }
}
EOF
assert_eq "$(resolve_octopus_model "claude" "claude-sonnet" "review" "logic-reviewer")" "claude-review-phase" "Bare role model invalid for provider falls back to matching phase routing"

# Test 9: Session override
clear_model_cache
cat > "$CONFIG_FILE" << EOF
{
  "version": "3.0",
  "providers": {
    "codex": { "default": "config-default" }
  },
  "overrides": { "codex": "session-override" }
}
EOF
assert_eq "$(resolve_octopus_model "codex" "codex")" "session-override" "Session override"

# Cleanup
export HOME="$HOME_ORIG"
rm -rf "$CLAUDE_OCTOPUS_WORKSPACE"
test_summary
