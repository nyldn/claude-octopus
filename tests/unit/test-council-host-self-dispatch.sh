#!/usr/bin/env bash
# Regression checks for #1103: a Claude host must dispatch its council seats
# instead of marking them host-native, while Codex-within-Codex and Windows/Git
# Bash keep the recursion guard from #444.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "council host self-dispatch"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/plugin-root.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/council.sh"

# Stub provider CLIs so detection sees them installed.
STUB_BIN="$TEST_TMP_DIR/bin"
mkdir -p "$STUB_BIN"
for cli in claude codex agy; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_BIN/$cli"
    chmod +x "$STUB_BIN/$cli"
done
PATH="$STUB_BIN:$PATH"

status_of() {
    jq -r --arg p "$1" '.[$p] // "missing"' <<< "$COUNCIL_PROVIDER_STATUS_JSON"
}

test_case "a Claude host dispatches claude seats instead of marking them host-native"
OCTOPUS_HOST="claude" COUNCIL_PROVIDERS="claude,codex,agy" council_detect_providers
if [[ "$(status_of claude)" == "available" && "$(status_of codex)" == "available" ]]; then
    test_pass
else
    test_fail "claude=$(status_of claude) codex=$(status_of codex); expected both available"
fi

test_case "a Codex host keeps the host-native guard for codex (#444)"
OCTOPUS_HOST="codex" COUNCIL_PROVIDERS="claude,codex,agy" council_detect_providers
if [[ "$(status_of codex)" == "host-native" && "$(status_of claude)" == "available" ]]; then
    test_pass
else
    test_fail "codex=$(status_of codex) claude=$(status_of claude); expected codex host-native"
fi

test_case "Windows/Git Bash keeps the host-native guard for a Claude host"
octo_is_windows_git_bash() { return 0; }
OCTOPUS_HOST="claude" COUNCIL_PROVIDERS="claude,codex,agy" council_detect_providers
if [[ "$(status_of claude)" == "host-native" ]]; then
    test_pass
else
    test_fail "claude=$(status_of claude) on Windows/Git Bash; expected host-native"
fi
octo_is_windows_git_bash() { return 1; }

test_case "extra seats prefer a responsive provider over a host-native one"
COUNCIL_PROVIDERS="codex,agy"
COUNCIL_PROVIDER_STATUS_JSON='{"codex":"host-native","agy":"available"}'
# Every model family already has a seat, so the pick falls through to the
# fill loops that previously returned the first listed (host-native) provider.
council_roster_has_model_family() { return 0; }
picked="$(council_pick_provider "codex")"
if [[ "$picked" == "agy" ]]; then
    test_pass
else
    test_fail "extra seat went to '$picked'; expected the responsive provider agy"
fi

test_case "a host-native provider is still used when it is the only one available"
COUNCIL_PROVIDERS="codex"
COUNCIL_PROVIDER_STATUS_JSON='{"codex":"host-native"}'
picked="$(council_pick_provider "codex")"
if [[ "$picked" == "codex" ]]; then
    test_pass
else
    test_fail "sole host-native provider was not picked: '$picked'"
fi

test_summary
