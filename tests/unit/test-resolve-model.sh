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

TESTS_RUN=0
TESTS_PASSED=0

assert_eq() {
    TESTS_RUN=$((TESTS_RUN + 1))
    local actual="$1"
    local expected="$2"
    local desc="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo -e "${GREEN}✓${NC} $desc (got: $actual)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $desc (expected: $expected, got: $actual)"
        exit 1
    fi
}

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
