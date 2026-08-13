#!/usr/bin/env bash
# Stable plugin entrypoint must advance to the version loaded by the host.
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Stable plugin root follows the loaded version"

TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/octo-plugin-root.XXXXXX")"
trap 'rm -rf "$TEST_HOME"' EXIT
OLD_ROOT="$TEST_HOME/cache/9.63.0"
NEW_ROOT="$TEST_HOME/cache/9.64.0"
mkdir -p "$OLD_ROOT/scripts" "$NEW_ROOT/scripts" "$TEST_HOME/.claude-octopus"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$OLD_ROOT/scripts/orchestrate.sh"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$NEW_ROOT/scripts/orchestrate.sh"
chmod +x "$OLD_ROOT/scripts/orchestrate.sh" "$NEW_ROOT/scripts/orchestrate.sh"
ln -s "$OLD_ROOT" "$TEST_HOME/.claude-octopus/plugin"
NEW_ROOT_PHYSICAL="$(cd "$NEW_ROOT" && pwd -P)"

test_case "a valid but stale symlink advances to CLAUDE_PLUGIN_ROOT"
HOME="$TEST_HOME" CLAUDE_PLUGIN_ROOT="$NEW_ROOT" \
    bash "$PROJECT_ROOT/scripts/helpers/ensure-plugin-root.sh" >/dev/null 2>&1 || true
resolved="$(cd "$TEST_HOME/.claude-octopus/plugin" 2>/dev/null && pwd -P || true)"
if [[ "$resolved" == "$NEW_ROOT_PHYSICAL" ]]; then
    test_pass
else
    test_fail "stable root still resolves to ${resolved:-missing}; expected $NEW_ROOT_PHYSICAL"
fi

test_case "the refreshed stable entrypoint remains executable"
if [[ -x "$TEST_HOME/.claude-octopus/plugin/scripts/orchestrate.sh" ]]; then
    test_pass
else
    test_fail "refreshed stable root has no executable orchestrator"
fi

test_summary
