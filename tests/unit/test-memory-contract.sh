#!/usr/bin/env bash
# Static + behavioural assertions for the memory-provider contract (#220).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MEM="$PROJECT_ROOT/scripts/lib/memory.sh"
CLAUDE_MEM="$PROJECT_ROOT/scripts/claude-mem-bridge.sh"
MCP_MEM="$PROJECT_ROOT/scripts/mcp-memory-bridge.sh"
AGENTMEMORY="$PROJECT_ROOT/scripts/agentmemory-bridge.sh"

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

test_agentmemory_bridge_exists() {
    test_case "agentmemory-bridge.sh exists and is executable"
    [[ -x "$AGENTMEMORY" ]] && test_pass || test_fail "agentmemory-bridge.sh missing or not +x"
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
    out=$(env -i "PATH=${PATH}" "OCTOPUS_MEMORY_BACKEND=auto" "CLAUDE_SETTINGS_FILE=/dev/null" \
          "HOME=${TEST_TMP_DIR}/empty-home" \
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
    out=$(OCTOPUS_MEMORY_BACKEND="agentmemory,mcp-memory-service,claude-mem" \
          bash -c "source '$MEM'; memory_backends" | tr '\n' ',' | sed 's/,$//')
    [[ "$out" == "agentmemory,mcp-memory-service,claude-mem" ]] \
        && test_pass \
        || test_fail "expected agentmemory,mcp-memory-service,claude-mem got: $out"
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
          bash -c "source '$MEM'; memory_backends")
    out=$(printf '%s\n' "$out" | sed -n '1p')
    rm -f "$tmp_settings"
    [[ "$out" == "mcp-memory-service" ]] \
        && test_pass \
        || test_fail "expected mcp-memory-service first, got: $out"
}

test_backends_detects_agentmemory_registered() {
    test_case "auto detects agentmemory when present in mcpServers"
    local tmp_settings
    tmp_settings=$(mktemp)
    cat >"$tmp_settings" <<'JSON'
{"mcpServers": {"agentmemory": {"command": "npx", "args": ["-y", "@agentmemory/mcp"]}}}
JSON
    local out
    # shellcheck disable=SC1090
    out=$(OCTOPUS_MEMORY_BACKEND=auto CLAUDE_SETTINGS_FILE="$tmp_settings" \
          bash -c "source '$MEM'; memory_backends")
    out=$(printf '%s\n' "$out" | sed -n '1p')
    rm -f "$tmp_settings"
    [[ "$out" == "agentmemory" ]] \
        && test_pass \
        || test_fail "expected agentmemory first, got: $out"
}

test_backends_detects_agentmemory_registered_in_servers() {
    test_case "auto detects agentmemory when present in servers"
    local tmp_settings
    tmp_settings=$(mktemp)
    cat >"$tmp_settings" <<'JSON'
{"servers": {"memory": {"command": "npx", "args": ["-y", "@agentmemory/mcp"]}}}
JSON
    local out
    # shellcheck disable=SC1090
    out=$(OCTOPUS_MEMORY_BACKEND=auto CLAUDE_SETTINGS_FILE="$tmp_settings" \
          bash -c "source '$MEM'; memory_backends")
    out=$(printf '%s\n' "$out" | sed -n '1p')
    rm -f "$tmp_settings"
    [[ "$out" == "agentmemory" ]] \
        && test_pass \
        || test_fail "expected agentmemory first, got: $out"
}

test_backends_detects_agentmemory_env() {
    test_case "auto detects agentmemory when AGENTMEMORY_URL is set"
    local out
    # shellcheck disable=SC1090
    out=$(OCTOPUS_MEMORY_BACKEND=auto CLAUDE_SETTINGS_FILE=/dev/null \
          AGENTMEMORY_URL=http://localhost:3111 \
          bash -c "source '$MEM'; memory_backends")
    out=$(printf '%s\n' "$out" | sed -n '1p')
    [[ "$out" == "agentmemory" ]] \
        && test_pass \
        || test_fail "expected agentmemory first, got: $out"
}

test_scope_uses_repo_basename() {
    test_case "memory_scope falls back to git repo basename"
    local out expected
    # Derive the expectation from the same source memory_scope uses — git's
    # toplevel — not from PROJECT_ROOT. PROJECT_ROOT is resolved logically
    # (`cd && pwd`, line 7) while `git rev-parse --show-toplevel` resolves
    # symlinks, so the two diverge behind a symlinked checkout and this case
    # failed with `expected 'octo-linked', got: claude-octopus`. The code is
    # right: a scope keyed on the link name would fragment one repo's memory
    # across every path used to reach it. Same class as #712.
    local scope_root
    scope_root=$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel 2>/dev/null || true)
    [[ -n "$scope_root" ]] || scope_root=$(cd -P "$PROJECT_ROOT" && pwd)
    expected=$(basename "$scope_root")
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

test_agentmemory_bridge_no_ops_when_server_missing() {
    test_case "agentmemory-bridge no-ops gracefully without the server"
    local out
    out=$(AGENTMEMORY_URL="http://127.0.0.1:9" AGENTMEMORY_TIMEOUT=1 "$AGENTMEMORY" available)
    [[ "$out" == "false" ]] \
        && test_pass \
        || test_fail "expected 'false' when server missing, got: $out"
}

DEJA="$PROJECT_ROOT/scripts/deja-bridge.sh"

# A stand-in for the deja binary, so detection and the search mapping are
# exercised without deja installed or any real session history read.
_deja_stub() {
    local stub="${TEST_TMP_DIR}/deja-stub/deja"
    mkdir -p "$(dirname "$stub")"
    cat >"$stub" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "search" ]]; then
cat <<'JSON'
{"schema_version":2,"tier":"exact","total":1,"hits":[{"session":{"harness":"codex","id":"abc123","project":"myapp","title":"pool exhausted under load","started":"2026-01-02T03:04:05Z","updated":"2026-01-02T03:10:00Z"},"count":2,"snippets":["raised max_client_conn","transaction mode"],"score":1.5,"tier":"exact"}]}
JSON
fi
SH
    chmod +x "$stub"
    printf '%s' "$stub"
}

test_deja_bridge_exists() {
    test_case "deja-bridge.sh exists and is executable"
    [[ -x "$DEJA" ]] && test_pass || test_fail "deja-bridge.sh missing or not +x"
}

test_backends_detects_deja_registered() {
    test_case "auto detects deja when its MCP server is registered and the CLI is present"
    local tmp_settings stub out
    stub=$(_deja_stub)
    tmp_settings=$(mktemp)
    cat >"$tmp_settings" <<JSON
{"mcpServers": {"deja": {"command": "$stub", "args": ["mcp"]}}}
JSON
    # shellcheck disable=SC1090
    out=$(OCTOPUS_MEMORY_BACKEND=auto CLAUDE_SETTINGS_FILE="$tmp_settings" DEJA_BIN="$stub" \
          HOME="${TEST_TMP_DIR}/empty-home" bash -c "source '$MEM'; memory_backends" | tr '\n' ',' | sed 's/,$//')
    rm -f "$tmp_settings"
    [[ "$out" == "deja,claude-mem" ]] \
        && test_pass \
        || test_fail "expected deja,claude-mem got: $out"
}

test_backends_detects_deja_plugin() {
    test_case "auto detects deja when its Claude Code plugin is enabled"
    local tmp_settings stub out
    stub=$(_deja_stub)
    tmp_settings=$(mktemp)
    cat >"$tmp_settings" <<'JSON'
{"enabledPlugins": {"deja-vu@deja-vu": true}}
JSON
    # shellcheck disable=SC1090
    out=$(OCTOPUS_MEMORY_BACKEND=auto CLAUDE_SETTINGS_FILE="$tmp_settings" DEJA_BIN="$stub" \
          HOME="${TEST_TMP_DIR}/empty-home" bash -c "source '$MEM'; memory_backends" | head -1)
    rm -f "$tmp_settings"
    [[ "$out" == "deja" ]] \
        && test_pass \
        || test_fail "expected deja first, got: $out"
}

test_backends_skips_deja_without_cli() {
    test_case "a registered deja without the CLI on PATH is not selected"
    local tmp_settings out
    tmp_settings=$(mktemp)
    cat >"$tmp_settings" <<'JSON'
{"mcpServers": {"deja": {"command": "deja", "args": ["mcp"]}}}
JSON
    # shellcheck disable=SC1090
    out=$(OCTOPUS_MEMORY_BACKEND=auto CLAUDE_SETTINGS_FILE="$tmp_settings" DEJA_BIN="this-binary-does-not-exist" \
          HOME="${TEST_TMP_DIR}/empty-home" bash -c "source '$MEM'; memory_backends" | head -1)
    rm -f "$tmp_settings"
    [[ "$out" == "claude-mem" ]] \
        && test_pass \
        || test_fail "expected claude-mem first, got: $out"
}

test_deja_bridge_no_ops_when_cli_missing() {
    test_case "deja-bridge no-ops gracefully without the CLI"
    local avail found
    avail=$(DEJA_BIN="this-binary-does-not-exist" "$DEJA" available)
    found=$(DEJA_BIN="this-binary-does-not-exist" "$DEJA" search "anything" 5)
    [[ "$avail" == "false" && -z "$found" ]] \
        && test_pass \
        || test_fail "expected 'false' and no results when CLI missing, got: $avail / $found"
}

test_deja_bridge_search_maps_hits() {
    test_case "deja-bridge search returns a JSON array of sessions"
    command -v jq >/dev/null 2>&1 || { test_skip "jq not installed"; return; }
    local stub out
    stub=$(_deja_stub)
    out=$(DEJA_BIN="$stub" "$DEJA" search "pool exhausted" 5 myapp)
    [[ "$(printf '%s' "$out" | jq -r '.[0].session_id + " " + .[0].harness + " " + .[0].source')" == "abc123 codex deja" ]] \
        && test_pass \
        || test_fail "unexpected search output: $out"
}

test_deja_bridge_search_skips_relevance_tier() {
    test_case "deja-bridge search returns nothing when deja only has nearest matches"
    command -v jq >/dev/null 2>&1 || { test_skip "jq not installed"; return; }
    local stub out
    stub=$(_deja_stub)
    sed -i.bak 's/"tier":"exact"/"tier":"relevance"/g' "$stub" && rm -f "$stub.bak"
    out=$(DEJA_BIN="$stub" "$DEJA" search "pool exhausted" 5 myapp)
    [[ -z "$out" || "$out" == "[]" ]] \
        && test_pass \
        || test_fail "expected no results for a relevance-tier answer, got: $out"
}

test_contract_file_exists
test_mcp_bridge_exists
test_deja_bridge_exists
test_deja_bridge_search_skips_relevance_tier
test_agentmemory_bridge_exists
test_claude_mem_bridge_still_exists
test_primitives_defined
test_backends_defaults_to_claude_mem
test_backends_respects_explicit_env
test_backends_detects_mcp_registered
test_backends_detects_agentmemory_registered
test_backends_detects_agentmemory_registered_in_servers
test_backends_detects_agentmemory_env
test_scope_uses_repo_basename
test_scope_env_override_wins
test_mcp_bridge_no_ops_when_cli_missing
test_agentmemory_bridge_no_ops_when_server_missing
test_backends_detects_deja_registered
test_backends_detects_deja_plugin
test_backends_skips_deja_without_cli
test_deja_bridge_no_ops_when_cli_missing
test_deja_bridge_search_maps_hits

test_summary
