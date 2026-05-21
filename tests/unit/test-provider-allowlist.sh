#!/usr/bin/env bash
# Unit tests for OCTO_ALLOWED_PROVIDERS filtering.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Provider allowlist"

ALLOWLIST_LIB="$PROJECT_ROOT/scripts/lib/provider-allowlist.sh"
CHECK_PROVIDERS="$PROJECT_ROOT/scripts/helpers/check-providers.sh"
BUILD_FLEET="$PROJECT_ROOT/scripts/helpers/build-fleet.sh"
MODEL_CONFIG="$PROJECT_ROOT/scripts/helpers/octo-model-config.sh"

test_case "allowlist helper has valid bash syntax"
if bash -n "$ALLOWLIST_LIB"; then
    test_pass
else
    test_fail "provider-allowlist.sh has syntax errors"
fi

source "$ALLOWLIST_LIB"

test_case "unset allowlist permits every provider"
if unset OCTO_ALLOWED_PROVIDERS && octo_provider_allowed codex && octo_provider_allowed gemini && octo_provider_allowed claude-sonnet; then
    test_pass
else
    test_fail "unset allowlist should allow all providers"
fi

test_case "space and comma separated allowlist filters providers"
if OCTO_ALLOWED_PROVIDERS="claude, gemini ollama" octo_provider_allowed gemini &&
   OCTO_ALLOWED_PROVIDERS="claude, gemini ollama" octo_provider_allowed claude-sonnet &&
   ! OCTO_ALLOWED_PROVIDERS="claude, gemini ollama" octo_provider_allowed codex; then
    test_pass
else
    test_fail "allowlist did not honor comma/space separated provider names"
fi

session_config="$TEST_TMP_DIR/provider-allowlist-config"

test_case "session allowlist file filters providers without env var"
if unset OCTO_ALLOWED_PROVIDERS &&
   OCTOPUS_CONFIG_DIR="$session_config" CLAUDE_CODE_SESSION_ID="session/one" "$MODEL_CONFIG" allow claude gemini --session >/dev/null &&
   OCTOPUS_CONFIG_DIR="$session_config" CLAUDE_CODE_SESSION_ID="session/one" octo_provider_allowed claude-sonnet &&
   OCTOPUS_CONFIG_DIR="$session_config" CLAUDE_CODE_SESSION_ID="session/one" octo_provider_allowed gemini &&
   ! OCTOPUS_CONFIG_DIR="$session_config" CLAUDE_CODE_SESSION_ID="session/one" octo_provider_allowed codex; then
    test_pass
else
    test_fail "session allowlist file should restrict providers"
fi

test_case "disable command removes one provider for current session"
if unset OCTO_ALLOWED_PROVIDERS &&
   OCTOPUS_CONFIG_DIR="$session_config" CLAUDE_CODE_SESSION_ID="session/two" "$MODEL_CONFIG" disable codex --session >/dev/null &&
   ! OCTOPUS_CONFIG_DIR="$session_config" CLAUDE_CODE_SESSION_ID="session/two" octo_provider_allowed codex &&
   OCTOPUS_CONFIG_DIR="$session_config" CLAUDE_CODE_SESSION_ID="session/two" octo_provider_allowed gemini; then
    test_pass
else
    test_fail "disable should write a session allowlist excluding codex"
fi

test_case "clear-allowlist restores default provider availability"
if unset OCTO_ALLOWED_PROVIDERS &&
   OCTOPUS_CONFIG_DIR="$session_config" CLAUDE_CODE_SESSION_ID="session/two" "$MODEL_CONFIG" clear-allowlist --session >/dev/null &&
   OCTOPUS_CONFIG_DIR="$session_config" CLAUDE_CODE_SESSION_ID="session/two" octo_provider_allowed codex; then
    test_pass
else
    test_fail "clear-allowlist should restore default availability"
fi

mock_bin="$TEST_TMP_DIR/provider-allowlist-bin"
mkdir -p "$mock_bin"
for cmd in codex gemini; do
    cat > "$mock_bin/$cmd" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "$mock_bin/$cmd"
done

test_case "check-providers reports disallowed installed providers as missing"
output=$(PATH="$mock_bin:/usr/bin:/bin" OCTO_ALLOWED_PROVIDERS="gemini" "$CHECK_PROVIDERS")
if assert_contains "$output" "gemini:available" "gemini should remain available" &&
   assert_contains "$output" "codex:missing" "codex should be hidden by allowlist"; then
    test_pass
fi

test_case "build-fleet excludes disallowed providers"
fleet=$(PATH="$mock_bin:/usr/bin:/bin" OCTO_ALLOWED_PROVIDERS="claude gemini" "$BUILD_FLEET" review standard "review target" 2>/dev/null)
if assert_contains "$fleet" "gemini|" "gemini should be eligible" &&
   assert_contains "$fleet" "claude-sonnet|" "claude alias should allow claude-sonnet" &&
   assert_not_contains "$fleet" "codex|" "codex should not be emitted"; then
    test_pass
fi

test_summary
