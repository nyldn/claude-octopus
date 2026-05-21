#!/usr/bin/env bash
# Unit tests for shared agent/provider predicate helpers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROUTING="$PROJECT_ROOT/scripts/lib/routing.sh"
AGENT_SYNC="$PROJECT_ROOT/scripts/lib/agent-sync.sh"
MODEL_RESOLVER="$PROJECT_ROOT/scripts/lib/model-resolver.sh"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "shared agent predicates"

test_case "is_claude_agent_type recognizes every Claude agent variant"
# shellcheck source=/dev/null
source "$ROUTING"
if declare -f is_claude_agent_type >/dev/null 2>&1 && \
   is_claude_agent_type "claude" && \
   is_claude_agent_type "claude-sonnet" && \
   is_claude_agent_type "claude-opus" && \
   is_claude_agent_type "claude-opus-fast" && \
   is_claude_agent_type "claude-opus-legacy"; then
    test_pass
else
    test_fail "Claude predicate did not accept all supported Claude agent variants"
fi

test_case "is_claude_agent_type rejects non-Claude and empty values"
if ! is_claude_agent_type "" && \
   ! is_claude_agent_type "codex" && \
   ! is_claude_agent_type "gemini" && \
   ! is_claude_agent_type "my-claude-wrapper"; then
    test_pass
else
    test_fail "Claude predicate accepted a non-Claude agent value"
fi

test_case "Agent Teams dispatch uses the shared Claude predicate"
if awk '
    /should_use_agent_teams\(\)/, /^}/ {
        if ($0 ~ /is_claude_agent_type "\$agent_type"/) found=1
    }
    END { exit(found ? 0 : 1) }
' "$AGENT_SYNC"; then
    test_pass
else
    test_fail "should_use_agent_teams does not use is_claude_agent_type"
fi

test_case "Claude agent availability uses the shared predicate for fast variants"
# shellcheck source=/dev/null
source "$MODEL_RESOLVER"
PROVIDER_CODEX_INSTALLED=false
PROVIDER_CLAUDE_INSTALLED=false
if ! is_agent_available_v2 "claude-opus-fast"; then
    PROVIDER_CLAUDE_INSTALLED=true
    if is_agent_available_v2 "claude-opus-fast"; then
        test_pass
    else
        test_fail "claude-opus-fast was unavailable despite Claude provider being installed"
    fi
else
    test_fail "claude-opus-fast bypassed Claude provider availability"
fi

test_summary
