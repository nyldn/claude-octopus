#!/bin/bash
# tests/unit/test-adapter-flags.sh
# Tests for adapter flag ordering, parameter forwarding, and env var allowlists
# Validates fixes from repo-audit-2026-03-21

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Adapter Flag Ordering & Parameter Forwarding"

MCP_SRC="$PROJECT_ROOT/mcp-server/src/index.ts"
OC_SRC="$PROJECT_ROOT/openclaw/src/index.ts"

# ═══════════════════════════════════════════════════════════════════════════════
# Debate Flag Placement — grapple flags must go AFTER the command
# ═══════════════════════════════════════════════════════════════════════════════

test_mcp_debate_uses_post_flags() {
    test_case "MCP debate passes grapple flags via postFlags (after command)"
    if grep -q 'runOrchestrate("grapple".*\[\].*postFlags' "$MCP_SRC"; then
        test_pass
    else
        test_fail "MCP debate should use postFlags parameter"
    fi
}

test_oc_debate_uses_post_flags() {
    test_case "OpenClaw debate passes grapple flags via postFlags (after command)"
    if grep -q 'executeOrchestrate("grapple".*\[\].*\[' "$OC_SRC"; then
        test_pass
    else
        test_fail "OpenClaw debate should use postFlags parameter"
    fi
}

test_mcp_has_post_flags_param() {
    test_case "MCP runOrchestrate accepts postFlags parameter"
    if grep -q 'postFlags: string\[\] = \[\]' "$MCP_SRC"; then test_pass; else test_fail "missing postFlags param"; fi
}

test_oc_has_post_flags_param() {
    test_case "OpenClaw executeOrchestrate accepts postFlags parameter"
    if grep -q 'postFlags: string\[\] = \[\]' "$OC_SRC"; then test_pass; else test_fail "missing postFlags param"; fi
}

test_mcp_args_include_post_flags() {
    test_case "MCP args array includes postFlags after command"
    if grep -q '\.\.\.postFlags, prompt' "$MCP_SRC"; then test_pass; else test_fail "missing postFlags in args"; fi
}

test_oc_args_include_post_flags() {
    test_case "OpenClaw args array includes postFlags after command"
    if grep -q '\.\.\.postFlags, prompt' "$OC_SRC"; then test_pass; else test_fail "missing postFlags in args"; fi
}

test_oc_no_dash_d_flag() {
    test_case "OpenClaw debate does NOT use -d flag (was wrongly mapped to --dir)"
    if grep -A5 'grapple' "$OC_SRC" | grep -q '"-d"'; then
        test_fail "OpenClaw debate should not use -d flag"
    else
        test_pass
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Quality Threshold Forwarding
# ═══════════════════════════════════════════════════════════════════════════════

test_mcp_forwards_quality_threshold() {
    test_case "MCP develop forwards quality_threshold as -q flag"
    if grep -q '"-q"' "$MCP_SRC" && grep -q 'quality_threshold' "$MCP_SRC"; then test_pass; else test_fail "missing -q flag"; fi
}

test_oc_forwards_quality_threshold() {
    test_case "OpenClaw develop forwards quality_threshold as -q flag"
    if grep -q '"-q"' "$OC_SRC" && grep -q 'quality_threshold' "$OC_SRC"; then test_pass; else test_fail "missing -q flag"; fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Environment Variable Allowlists
# ═══════════════════════════════════════════════════════════════════════════════

test_mcp_forwards_anthropic_base_url() {
    test_case "MCP env includes ANTHROPIC_BASE_URL"
    if grep -q 'ANTHROPIC_BASE_URL' "$MCP_SRC"; then test_pass; else test_fail "missing"; fi
}

test_mcp_forwards_anthropic_auth_token() {
    test_case "MCP env includes ANTHROPIC_AUTH_TOKEN"
    if grep -q 'ANTHROPIC_AUTH_TOKEN' "$MCP_SRC"; then test_pass; else test_fail "missing"; fi
}

test_oc_forwards_anthropic_base_url() {
    test_case "OpenClaw env includes ANTHROPIC_BASE_URL"
    if grep -q 'ANTHROPIC_BASE_URL' "$OC_SRC"; then test_pass; else test_fail "missing"; fi
}

test_oc_forwards_perplexity_key() {
    test_case "OpenClaw env includes PERPLEXITY_API_KEY"
    if grep -q 'PERPLEXITY_API_KEY' "$OC_SRC"; then test_pass; else test_fail "missing"; fi
}

test_mcp_forwards_copilot_token() {
    test_case "MCP env includes COPILOT_GITHUB_TOKEN"
    if grep -q 'COPILOT_GITHUB_TOKEN' "$MCP_SRC"; then test_pass; else test_fail "missing"; fi
}

test_oc_forwards_copilot_token() {
    test_case "OpenClaw env includes COPILOT_GITHUB_TOKEN"
    if grep -q 'COPILOT_GITHUB_TOKEN' "$OC_SRC"; then test_pass; else test_fail "missing"; fi
}

test_mcp_forwards_gh_token() {
    test_case "MCP env includes GH_TOKEN for Copilot auth"
    if grep -q 'GH_TOKEN' "$MCP_SRC"; then test_pass; else test_fail "missing"; fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Debate Description Accuracy
# ═══════════════════════════════════════════════════════════════════════════════

test_oc_debate_says_four_way() {
    test_case "OpenClaw debate description says Four-way"
    if grep -q 'Four-way' "$OC_SRC"; then test_pass; else test_fail "should say Four-way"; fi
}

test_oc_debate_has_mode_param() {
    test_case "OpenClaw debate exposes mode parameter"
    if grep -q 'cross-critique.*blinded\|mode.*cross-critique' "$OC_SRC"; then test_pass; else test_fail "missing mode param"; fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Council Adapter Wiring
# ═══════════════════════════════════════════════════════════════════════════════

test_mcp_exposes_council_tool() {
    test_case "MCP server exposes octopus_council"
    if grep -q 'octopus_council' "$MCP_SRC" && grep -q 'runOrchestrate("council"' "$MCP_SRC"; then
        test_pass
    else
        test_fail "MCP server should expose octopus_council mapped to council"
    fi
}

test_oc_exposes_council_tool() {
    test_case "OpenClaw exposes octopus_council"
    if grep -q 'name: "octopus_council"' "$OC_SRC" && grep -q 'executeOrchestrate("council"' "$OC_SRC"; then
        test_pass
    else
        test_fail "OpenClaw should expose octopus_council mapped to council"
    fi
}

test_oc_manifest_allows_council_workflow() {
    test_case "OpenClaw manifest allows council workflow"
    if grep -q '"council"' "$PROJECT_ROOT/openclaw/openclaw.plugin.json"; then
        test_pass
    else
        test_fail "OpenClaw manifest should include council in enabledWorkflows"
    fi
}

test_cursor_has_council_command() {
    test_case "Cursor plugin has octo-council command"
    if [[ -f "$PROJECT_ROOT/.cursor-plugin/commands/octo-council.md" ]]; then
        test_pass
    else
        test_fail "Cursor plugin should include octo-council.md"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Copilot Provider Wiring
# ═══════════════════════════════════════════════════════════════════════════════

test_copilot_in_available_agents() {
    test_case "copilot in AVAILABLE_AGENTS"
    if grep -q 'copilot' "$PROJECT_ROOT/scripts/orchestrate.sh" | head -1 && \
       grep 'AVAILABLE_AGENTS=' "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -q 'copilot'; then
        test_pass
    else
        test_fail "copilot should be in AVAILABLE_AGENTS"
    fi
}

test_copilot_in_dispatch() {
    test_case "copilot dispatch routes through helpers/copilot-exec.sh"
    if grep -q 'helpers/copilot-exec.sh' "$PROJECT_ROOT/scripts/lib/dispatch.sh"; then test_pass; else test_fail "copilot dispatch does not route through the shim"; fi
}

test_copilot_shim_nonint_flags() {
    test_case "copilot-exec.sh shim runs copilot non-interactively"
    if grep -q 'copilot -p' "$PROJECT_ROOT/scripts/helpers/copilot-exec.sh" && \
       grep -q 'no-ask-user' "$PROJECT_ROOT/scripts/helpers/copilot-exec.sh"; then test_pass; else test_fail "shim missing -p/--no-ask-user non-interactive invocation"; fi
}

test_copilot_lib_exists() {
    test_case "scripts/lib/copilot.sh exists"
    if [[ -f "$PROJECT_ROOT/scripts/lib/copilot.sh" ]]; then test_pass; else test_fail "copilot.sh not found"; fi
}

test_copilot_in_doctor() {
    test_case "doctor.sh checks Copilot CLI"
    if grep -q 'copilot-cli' "$PROJECT_ROOT/scripts/lib/doctor.sh"; then test_pass; else test_fail "missing copilot doctor check"; fi
}

test_copilot_in_providers_health() {
    test_case "providers.sh includes copilot health check"
    if grep -q 'copilot)' "$PROJECT_ROOT/scripts/lib/providers.sh"; then test_pass; else test_fail "missing copilot health check"; fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Run all tests
# ═══════════════════════════════════════════════════════════════════════════════

# Debate flags
test_mcp_debate_uses_post_flags
test_oc_debate_uses_post_flags
test_mcp_has_post_flags_param
test_oc_has_post_flags_param
test_mcp_args_include_post_flags
test_oc_args_include_post_flags
test_oc_no_dash_d_flag

# Quality threshold
test_mcp_forwards_quality_threshold
test_oc_forwards_quality_threshold

# Env vars
test_mcp_forwards_anthropic_base_url
test_mcp_forwards_anthropic_auth_token
test_oc_forwards_anthropic_base_url
test_oc_forwards_perplexity_key
test_mcp_forwards_copilot_token
test_oc_forwards_copilot_token
test_mcp_forwards_gh_token

# Description
test_oc_debate_says_four_way
test_oc_debate_has_mode_param

# Council adapters
test_mcp_exposes_council_tool
test_oc_exposes_council_tool
test_oc_manifest_allows_council_workflow
test_cursor_has_council_command

# Copilot wiring
test_copilot_in_available_agents
test_copilot_in_dispatch
test_copilot_shim_nonint_flags
test_copilot_lib_exists
test_copilot_in_doctor
test_copilot_in_providers_health

test_summary
