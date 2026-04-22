#!/usr/bin/env bash
# Static + behavioural assertions for the memory-provider contract (#220).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MEM="$PROJECT_ROOT/scripts/lib/memory.sh"
CLAUDE_MEM="$PROJECT_ROOT/scripts/claude-mem-bridge.sh"
MCP_MEM="$PROJECT_ROOT/scripts/mcp-memory-bridge.sh"

# shellcheck disable=SC1090
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Memory Provider Contract (Issue #220)"

test_contract_file_exists() {
    test_case "lib/memory.sh is present and sourceable"
    [[ -r "$MEM" ]] && bash -n "$MEM" && test_pass || test_fail "lib/memory.sh missing or has syntax errors"
}

test_mcp_bridge_exists() {
    test_case "mcp-memory-bridge.sh exists and is executable"
    [[ -x "$MCP_MEM" ]] && test_pass || test_fail "mcp-memory-bridge.sh missing or not +x"
}

test_claude_mem_bridge_still_exists() {
    test_case "existing claude-mem-bridge.sh is untouched"
    [[ -x "$CLAUDE_MEM" ]] && test_pass || test_fail "claude-mem-bridge.sh should still exist"
}

test_primitives_defined() {
    test_case "contract exposes required primitives"
    # shellcheck disable=SC1090
    ( source "$MEM" && \
      declare -f memory_available >/dev/null && \
      declare -f memory_search    >/dev/null && \
      declare -f memory_observe   >/dev/null && \
      declare -f memory_context   >/dev/null && \
      declare -f memory_backends  >/dev/null && \
      declare -f memory_scope     >/dev/null ) \
      && test_pass || test_fail "one or more memory_* primitives not defined"
}

test_backends_defaults_to_claude_mem() {
    test_case "with no MCP config registered, backends resolves to claude-mem"
    local out
    # shellcheck disable=SC1090
    out=$(OCTOPUS_MEMORY_BACKEND=auto CLAUDE_SETTINGS_FILE=/dev/null \
          HOME=/nonexistent-for-test \
          bash -c "source '$MEM'; memory_backends")
    if [[ "$(printf '%s' "$out" | head -1)" == "claude-mem" ]]; then
        test_pass
    else
        test_fail "auto-detect should default to claude-mem when no MCP registered (got: $out)"
    fi
}

test_backends_respects_explicit_env() {
    test_case "explicit OCTOPUS_MEMORY_BACKEND is honoured verbatim"
    local out
    # shellcheck disable=SC1090
    out=$(OCTOPUS_MEMORY_BACKEND="mcp-memory-service,claude-mem" \
          bash -c "source '$MEM'; memory_backends" | tr '\n' ',' | sed 's/,$//')
    [[ "$out" == "mcp-memory-service,claude-mem" ]] \
        && test_pass \
        || test_fail "expected mcp-memory-service,claude-mem got: $out"
}

test_backends_detects_mcp_registered() {
    test_case "auto detects mcp-memory-service when present in mcpServers"
    local tmp_settings
    tmp_settings=$(mktemp)
    cat >"$tmp_settings" <<'JSON'
{"mcpServers": {"memory": {"command": "uvx", "args": ["mcp-memory-service"]}}}
JSON
    local out
    # shellcheck disable=SC1090
    out=$(OCTOPUS_MEMORY_BACKEND=auto CLAUDE_SETTINGS_FILE="$tmp_settings" \
          bash -c "source '$MEM'; memory_backends" | head -1)
    rm -f "$tmp_settings"
    [[ "$out" == "mcp-memory-service" ]] \
        && test_pass \
        || test_fail "expected mcp-memory-service first, got: $out"
}

test_scope_uses_repo_basename() {
    test_case "memory_scope falls back to git repo basename"
    local out expected
    expected=$(basename "$PROJECT_ROOT")
    # shellcheck disable=SC1090
    out=$(cd "$PROJECT_ROOT" && bash -c "source '$MEM'; memory_scope")
    [[ "$out" == "$expected" ]] \
        && test_pass \
        || test_fail "expected '$expected', got: $out"
}

test_scope_env_override_wins() {
    test_case "OCTOPUS_MEMORY_SCOPE overrides auto-detection"
    local out
    # shellcheck disable=SC1090
    out=$(OCTOPUS_MEMORY_SCOPE=myproject bash -c "source '$MEM'; memory_scope")
    [[ "$out" == "myproject" ]] \
        && test_pass \
        || test_fail "expected 'myproject', got: $out"
}

test_mcp_bridge_no_ops_when_cli_missing() {
    test_case "mcp-memory-bridge no-ops gracefully without the CLI"
    local out
    out=$(OCTOPUS_MCP_MEMORY_CMD="this-binary-does-not-exist" "$MCP_MEM" available)
    [[ "$out" == "false" ]] \
        && test_pass \
        || test_fail "expected 'false' when CLI missing, got: $out"
}

test_contract_file_exists
test_mcp_bridge_exists
test_claude_mem_bridge_still_exists
test_primitives_defined
test_backends_defaults_to_claude_mem
test_backends_respects_explicit_env
test_backends_detects_mcp_registered
test_scope_uses_repo_basename
test_scope_env_override_wins
test_mcp_bridge_no_ops_when_cli_missing

test_summary
