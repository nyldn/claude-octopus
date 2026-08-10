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

test_case "is_agent_available_v2 fails closed for a truly unknown agent name (#799)"
if ! is_agent_available_v2 "some-future-provider-nobody-registered"; then
    test_pass
else
    test_fail "Unknown agent type was reported available (fail-open regression)"
fi

test_case "is_agent_available_v2 grok arm defers to grok_is_available (#799)"
grok_is_available() { return 0; }
if is_agent_available_v2 "grok"; then
    grok_is_available() { return 1; }
    if ! is_agent_available_v2 "grok"; then
        test_pass
    else
        test_fail "grok reported available despite grok_is_available returning false"
    fi
else
    test_fail "grok reported unavailable despite grok_is_available returning true"
fi
unset -f grok_is_available

VIBE_PREDICATE_HOME="$TEST_TMP_DIR/vibe-predicate-home"
mkdir -p "$VIBE_PREDICATE_HOME/.vibe"

vibe_fixture_available() (
    vibe() { :; }
    resolve_provider_env() { return 1; }
    HOME="$VIBE_PREDICATE_HOME"
    if [[ "${1:-unset}" == "unset" ]]; then
        unset MISTRAL_API_KEY
    else
        export "MISTRAL_API_KEY=${1}"
    fi
    is_agent_available_v2 "${2:-vibe}"
)

test_case "is_agent_available_v2 accepts authenticated Vibe (#799)"
if vibe_fixture_available "fixture-value" "vibe-research"; then
    test_pass
else
    test_fail "authenticated Vibe was rejected"
fi

test_case "is_agent_available_v2 rejects missing and whitespace-only Vibe environment auth (#799)"
rm -f "$VIBE_PREDICATE_HOME/.vibe/.env" "$VIBE_PREDICATE_HOME/.vibe/config.toml"
if ! vibe_fixture_available && ! vibe_fixture_available "   "; then
    test_pass
else
    test_fail "Vibe accepted missing or whitespace-only environment auth"
fi

test_case "is_agent_available_v2 rejects blank Vibe .env assignments (#799)"
printf 'MISTRAL_API_KEY=\nMISTRAL_API_KEY=""\nMISTRAL_API_KEY="" # intentionally blank\n' > "$VIBE_PREDICATE_HOME/.vibe/.env"
if ! vibe_fixture_available; then
    test_pass
else
    test_fail "Vibe accepted a blank .env credential"
fi
rm -f "$VIBE_PREDICATE_HOME/.vibe/.env"

test_case "is_agent_available_v2 rejects blank Vibe TOML assignments and comments (#799)"
printf 'api_key = ""# intentionally blank\n' > "$VIBE_PREDICATE_HOME/.vibe/config.toml"
if ! vibe_fixture_available; then
    test_pass
else
    test_fail "Vibe accepted a quoted-empty TOML credential with an inline comment"
fi

test_case "is_agent_available_v2 preserves hash characters inside valid quoted Vibe auth (#799)"
printf 'api_key = "fixture#value" # valid comment\n' > "$VIBE_PREDICATE_HOME/.vibe/config.toml"
if vibe_fixture_available; then
    test_pass
else
    test_fail "Vibe rejected a nonempty quoted credential containing a hash"
fi

atlascloud_fixture_available() (
    resolve_provider_env() { return 1; }
    unset ATLASCLOUD_API_KEY ATLASCLOUD_MODEL OCTOPUS_ATLASCLOUD_MODEL OPENAI_COMPAT_MODEL
    octo_fixture_value="fixture-value"
    export "ATLASCLOUD_API_KEY=${octo_fixture_value}"
    [[ "${1:-missing}" == "configured" ]] && export OCTOPUS_ATLASCLOUD_MODEL="vendor/model"
    is_agent_available_v2 "atlascloud"
)

test_case "is_agent_available_v2 rejects Atlas Cloud without a model (#799)"
if ! atlascloud_fixture_available; then
    test_pass
else
    test_fail "Atlas Cloud was accepted without a dispatchable model"
fi

test_case "is_agent_available_v2 accepts Atlas Cloud with API key and model (#799)"
if atlascloud_fixture_available "configured"; then
    test_pass
else
    test_fail "Atlas Cloud was rejected despite API key and model"
fi

test_summary
