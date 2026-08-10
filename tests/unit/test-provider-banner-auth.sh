#!/usr/bin/env bash
# Regression coverage for #799: installed provider binaries are not usable
# seats until the banner path can also find authentication.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=tests/helpers/test-framework.sh
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Provider banner authentication"

FAKE_HOME="$TEST_TMP_DIR/home"
FAKE_BIN="$TEST_TMP_DIR/bin"
mkdir -p "$FAKE_HOME" "$FAKE_BIN"

for provider_bin in codex opencode copilot; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_BIN/$provider_bin"
    chmod +x "$FAKE_BIN/$provider_bin"
done
printf '#!/usr/bin/env bash\nexit 1\n' > "$FAKE_BIN/gh"
chmod +x "$FAKE_BIN/gh"
printf '#!/usr/bin/env bash\nshift\nexec "$@"\n' > "$FAKE_BIN/timeout"
chmod +x "$FAKE_BIN/timeout"

provider_state() {
    local provider="$1"
    (
        unset OPENAI_API_KEY COPILOT_GITHUB_TOKEN GH_TOKEN GITHUB_TOKEN
        HOME="$FAKE_HOME" \
        PATH="$FAKE_BIN:$PATH" \
        OCTO_ALLOWED_PROVIDERS="$provider" \
        bash "$PROJECT_ROOT/scripts/helpers/check-providers.sh" 2>/dev/null \
            | grep "^${provider}:" | tail -1
    )
}

test_case "installed Codex without auth is degraded"
if [[ "$(provider_state codex)" == "codex:degraded" ]]; then test_pass; else test_fail "Codex binary alone must not be available"; fi

mkdir -p "$FAKE_HOME/.codex"
printf '{}\n' > "$FAKE_HOME/.codex/auth.json"
test_case "Codex auth file makes the installed provider available"
if [[ "$(provider_state codex)" == "codex:available" ]]; then test_pass; else test_fail "Codex auth file was not recognized"; fi

test_case "installed OpenCode without auth is degraded"
if [[ "$(provider_state opencode)" == "opencode:degraded" ]]; then test_pass; else test_fail "OpenCode binary alone must not be available"; fi

mkdir -p "$FAKE_HOME/.local/share/opencode"
printf '{}\n' > "$FAKE_HOME/.local/share/opencode/auth.json"
test_case "OpenCode auth file plus successful auth check is available"
if [[ "$(provider_state opencode)" == "opencode:available" ]]; then test_pass; else test_fail "OpenCode auth was not recognized"; fi

test_case "installed Copilot without auth is degraded"
if [[ "$(provider_state copilot)" == "copilot:degraded" ]]; then test_pass; else test_fail "Copilot binary alone must not be available"; fi

test_case "Copilot token makes the installed provider available"
COPILOT_STATE=$(
    HOME="$FAKE_HOME" PATH="$FAKE_BIN:$PATH" OCTO_ALLOWED_PROVIDERS="copilot" \
    COPILOT_GITHUB_TOKEN="test-token" \
    bash "$PROJECT_ROOT/scripts/helpers/check-providers.sh" 2>/dev/null \
        | grep '^copilot:' | tail -1
)
if [[ "$COPILOT_STATE" == "copilot:available" ]]; then test_pass; else test_fail "Copilot token was not recognized"; fi

test_summary
