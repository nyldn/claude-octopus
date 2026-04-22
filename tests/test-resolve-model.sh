#!/usr/bin/env bash
# Test: resolve_octopus_model (v3.0 refactor)

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/helpers/test-framework.sh"
test_suite "resolve_octopus_model (v3.0 refactor)"

PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
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
assert_eq "$(resolve_octopus_model "codex" "codex")" "gpt-5.4" "Default codex"
clear_model_cache
assert_eq "$(resolve_octopus_model "gemini" "gemini")" "gemini-3.1-pro-preview" "Default gemini"

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

# Test 8: Session override
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
