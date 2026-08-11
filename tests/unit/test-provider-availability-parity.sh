#!/usr/bin/env bash
# Regression coverage for the remaining #799 provider-status gaps. The banner
# and fleet builder must share one auth-aware admission result, and every
# registered dispatch seat needs an explicit banner state.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=tests/helpers/test-framework.sh
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Provider availability parity (#799)"

CHECK_PROVIDERS="$PROJECT_ROOT/scripts/helpers/check-providers.sh"
BUILD_FLEET="$PROJECT_ROOT/scripts/helpers/build-fleet.sh"
FAKE_HOME="$TEST_TMP_DIR/home"
FAKE_BIN="$TEST_TMP_DIR/bin"
mkdir -p "$FAKE_HOME" "$FAKE_BIN"

for provider_bin in claude-agent vibe codex; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_BIN/$provider_bin"
    chmod +x "$FAKE_BIN/$provider_bin"
done

provider_state() {
    local provider="$1"
    shift
    (
        unset CLAUDE_SDK_API_KEY MISTRAL_API_KEY OPENAI_API_KEY
        unset OPENAI_COMPAT_API_KEY OPENAI_COMPAT_API_KEY_ENV OPENAI_COMPAT_BASE_URL
        env \
            "HOME=$FAKE_HOME" \
            "PATH=$FAKE_BIN:/usr/bin:/bin" \
            "OCTO_ALLOWED_PROVIDERS=$provider" \
            "$@" \
            bash "$CHECK_PROVIDERS" 2>/dev/null \
            | grep "^${provider}:" | tail -1
    )
}

test_case "Claude SDK binary without its API key is degraded"
if [[ "$(provider_state claude-sdk)" == "claude-sdk:degraded" ]]; then
    test_pass
else
    test_fail "Claude SDK binary-only state was not reported as degraded"
fi

test_case "Claude SDK key plus executable shim is available"
if [[ "$(provider_state claude-sdk CLAUDE_SDK_API_KEY=fixture-key)" == "claude-sdk:available" ]]; then
    test_pass
else
    test_fail "Claude SDK authenticated state was not reported as available"
fi

mkdir -p "$FAKE_HOME/.vibe"
printf 'api_key = "" # intentionally blank\n' > "$FAKE_HOME/.vibe/config.toml"
test_case "Vibe rejects a blank credential file value"
if [[ "$(provider_state vibe)" == "vibe:degraded" ]]; then
    test_pass
else
    test_fail "Vibe trusted a blank config credential"
fi

printf 'export MISTRAL_API_KEY=profile-fixture-key\n' > "$FAKE_HOME/.profile"
test_case "Vibe resolves a profile-backed credential before admission"
if [[ "$(provider_state vibe)" == "vibe:available" ]]; then
    test_pass
else
    test_fail "Vibe ignored a profile-backed credential"
fi
rm -f "$FAKE_HOME/.profile"

printf 'api_key = "fixture#value" # valid quoted hash\n' > "$FAKE_HOME/.vibe/config.toml"
test_case "Vibe accepts a nonblank quoted credential"
if [[ "$(provider_state vibe)" == "vibe:available" ]]; then
    test_pass
else
    test_fail "Vibe did not recognize a valid config credential"
fi

test_case "partial OpenAI-compatible configuration is degraded"
if [[ "$(provider_state openai-compatible OPENAI_COMPAT_BASE_URL=https://example.test/v1)" == "openai-compatible:degraded" ]]; then
    test_pass
else
    test_fail "partial OpenAI-compatible configuration was not degraded"
fi

test_case "complete OpenAI-compatible configuration is available"
if [[ "$(provider_state openai-compatible OPENAI_COMPAT_BASE_URL=https://example.test/v1 OPENAI_COMPAT_API_KEY=fixture-key)" == "openai-compatible:available" ]]; then
    test_pass
else
    test_fail "complete OpenAI-compatible configuration was not available"
fi

test_case "OpenAI-compatible provider rejects whitespace-only configuration"
whitespace_states="$(
    provider_state openai-compatible OPENAI_COMPAT_BASE_URL='   ' OPENAI_COMPAT_API_KEY=fixture-key
    provider_state openai-compatible OPENAI_COMPAT_BASE_URL=https://example.test/v1 OPENAI_COMPAT_API_KEY='   '
    provider_state openai-compatible OPENAI_COMPAT_BASE_URL=https://example.test/v1 OPENAI_COMPAT_API_KEY_ENV=CUSTOM_KEY CUSTOM_KEY='   '
)"
if [[ "$(grep -c '^openai-compatible:degraded$' <<< "$whitespace_states")" -eq 3 ]]; then
    test_pass
else
    test_fail "whitespace-only OpenAI-compatible settings were admitted: $whitespace_states"
fi

failing_checker="$TEST_TMP_DIR/failing-provider-checker.sh"
printf '#!/usr/bin/env bash\nexit 23\n' > "$failing_checker"
chmod +x "$failing_checker"
test_case "fleet fails closed when the shared provider checker fails"
if checker_error=$(env \
    "HOME=$FAKE_HOME" \
    "PATH=$FAKE_BIN:/usr/bin:/bin" \
    "OCTOPUS_PROVIDER_CHECKER=$failing_checker" \
    "$BUILD_FLEET" research quick fixture 2>&1); then
    test_fail "fleet ignored a failed provider admission gate"
elif grep -q 'provider admission check failed' <<< "$checker_error"; then
    test_pass
else
    test_fail "fleet failed without reporting the provider gate: $checker_error"
fi

test_case "fleet rejects an installed but unauthenticated Codex seat"
unauth_fleet=$(
    env \
        "HOME=$FAKE_HOME" \
        "PATH=$FAKE_BIN:/usr/bin:/bin" \
        "OCTO_ALLOWED_PROVIDERS=codex" \
        "$BUILD_FLEET" review standard fixture 2>/dev/null
)
if ! grep -q '^codex|' <<<"$unauth_fleet"; then
    test_pass
else
    test_fail "fleet bypassed the banner auth gate: $unauth_fleet"
fi

mkdir -p "$FAKE_HOME/.codex"
printf '{}\n' > "$FAKE_HOME/.codex/auth.json"
test_case "fleet admits Codex after the shared auth gate passes"
auth_fleet=$(
    env \
        "HOME=$FAKE_HOME" \
        "PATH=$FAKE_BIN:/usr/bin:/bin" \
        "OCTO_ALLOWED_PROVIDERS=codex" \
        "$BUILD_FLEET" review standard fixture 2>/dev/null
)
if grep -q '^codex|' <<<"$auth_fleet"; then
    test_pass
else
    test_fail "fleet dropped authenticated Codex: $auth_fleet"
fi

test_case "fleet can seat an authenticated registered Vibe provider"
vibe_fleet=$(
    env \
        "HOME=$FAKE_HOME" \
        "PATH=$FAKE_BIN:/usr/bin:/bin" \
        "OCTO_ALLOWED_PROVIDERS=vibe" \
        "$BUILD_FLEET" research quick fixture 2>/dev/null
)
if grep -q '^vibe|' <<<"$vibe_fleet"; then
    test_pass
else
    test_fail "authenticated Vibe was absent from the fleet: $vibe_fleet"
fi

test_case "fleet can seat an authenticated Claude SDK provider"
claude_sdk_fleet=$(
    env \
        "HOME=$FAKE_HOME" \
        "PATH=$FAKE_BIN:/usr/bin:/bin" \
        "OCTO_ALLOWED_PROVIDERS=claude-sdk" \
        "CLAUDE_SDK_API_KEY=fixture-key" \
        "$BUILD_FLEET" research quick fixture 2>/dev/null
)
if grep -q '^claude-sdk|' <<<"$claude_sdk_fleet"; then
    test_pass
else
    test_fail "authenticated Claude SDK was absent from the fleet: $claude_sdk_fleet"
fi

test_case "fleet can seat a configured OpenAI-compatible provider"
openai_compatible_fleet=$(
    env \
        "HOME=$FAKE_HOME" \
        "PATH=$FAKE_BIN:/usr/bin:/bin" \
        "OCTO_ALLOWED_PROVIDERS=openai-compatible" \
        "OPENAI_COMPAT_BASE_URL=https://example.test/v1" \
        "OPENAI_COMPAT_API_KEY=fixture-key" \
        "$BUILD_FLEET" research quick fixture 2>/dev/null
)
if grep -q '^openai-compatible|' <<<"$openai_compatible_fleet"; then
    test_pass
else
    test_fail "configured OpenAI-compatible seat was absent from the fleet: $openai_compatible_fleet"
fi

test_case "fleet maps configured Atlas Cloud to its executable agent type"
atlascloud_fleet=$(
    env \
        "HOME=$FAKE_HOME" \
        "PATH=$FAKE_BIN:/usr/bin:/bin" \
        "OCTO_ALLOWED_PROVIDERS=atlascloud" \
        "ATLASCLOUD_API_KEY=fixture-key" \
        "ATLASCLOUD_MODEL=fixture/model" \
        "$BUILD_FLEET" research quick fixture 2>/dev/null
)
if grep -q '^atlascloud-agent|' <<<"$atlascloud_fleet"; then
    test_pass
else
    test_fail "Atlas Cloud did not map to atlascloud-agent: $atlascloud_fleet"
fi

test_summary
