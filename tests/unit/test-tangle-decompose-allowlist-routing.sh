#!/usr/bin/env bash
# Regression: tangle decomposition must not dispatch only to providers excluded
# by the active provider allowlist.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/octo-tangle-routing.XXXXXX")"
trap 'rm -rf "$TEST_HOME"' EXIT INT TERM

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "tangle decomposition allowlist routing"

export HOME="$TEST_HOME"
export OCTOPUS_CONFIG_DIR="$TEST_HOME/.claude-octopus/config"
export OCTOPUS_PROVIDERS_CONFIG="$OCTOPUS_CONFIG_DIR/providers.json"
export PLUGIN_DIR="$PROJECT_ROOT"
mkdir -p "$OCTOPUS_CONFIG_DIR"

cat > "$OCTOPUS_PROVIDERS_CONFIG" <<'JSON'
{
  "routing": {
    "features": {
      "review": [
        "codex",
        "claude-opus",
        "openrouter-glm52",
        "openrouter-kimi-k3"
      ]
    }
  }
}
JSON

source "$PROJECT_ROOT/scripts/lib/provider-allowlist.sh"
source "$PROJECT_ROOT/scripts/lib/execution-profile.sh"
source "$PROJECT_ROOT/scripts/lib/agent-utils.sh"
source "$PROJECT_ROOT/scripts/lib/workflows.sh"

CALL_LOG="$TEST_HOME/decompose-calls.log"
log() { :; }

run_agent_sync() {
    local agent="$1"
    printf '%s\n' "$agent" >> "$CALL_LOG"
    octo_provider_allowed "$agent" || return 1
    case "$agent" in
        claude-opus|openrouter-glm52)
            printf '1. [CODING] Routed task - Files: scripts/lib/workflows.sh - Task: use an allowed configured provider\n'
            return 0
            ;;
        *) return 1 ;;
    esac
}

test_case "Claude-only session routes decomposition to the configured Fable/Opus seat"
if (
    rm -f "$CALL_LOG"
    export OCTO_ALLOWED_PROVIDERS="claude"
    result=$(tangle_reformat_decomposition "task" "bad decomposition" "provider failure" "")
    [[ "$result" == *"Routed task"* ]] &&
    [[ "$(sed -n '1p' "$CALL_LOG")" == "claude-opus" ]] &&
    [[ "$(wc -l < "$CALL_LOG")" -eq 1 ]]
); then
    test_pass
else
    test_fail "Claude-only decomposition did not select claude-opus from the configured fleet"
fi

test_case "OpenRouter family allowlist routes decomposition to a configured model alias"
if (
    rm -f "$CALL_LOG"
    export OCTO_ALLOWED_PROVIDERS="openrouter"
    result=$(tangle_reformat_decomposition "task" "bad decomposition" "provider failure" "")
    [[ "$result" == *"Routed task"* ]] &&
    [[ "$(sed -n '1p' "$CALL_LOG")" == "openrouter-glm52" ]] &&
    [[ "$(wc -l < "$CALL_LOG")" -eq 1 ]]
); then
    test_pass
else
    test_fail "OpenRouter decomposition did not select the first configured OpenRouter model"
fi

test_case "initial and reformat decomposition share the allowlist-aware candidate chain"
if [[ "$(grep -c 'tangle_run_decomposition' "$PROJECT_ROOT/scripts/lib/workflows.sh" || true)" -ge 3 ]]; then
    test_pass
else
    test_fail "tangle_develop and reformat are not wired to one decomposition dispatcher"
fi

test_summary
