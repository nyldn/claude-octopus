#!/usr/bin/env bash
# Tests for Codex marketplace icon metadata.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Codex plugin icon"

PLUGIN_JSON="$PROJECT_ROOT/.codex-plugin/plugin.json"

test_case "Codex plugin manifest has valid JSON"
if jq empty "$PLUGIN_JSON"; then
    test_pass
else
    test_fail ".codex-plugin/plugin.json is invalid JSON"
fi

test_case "composerIcon points to a packaged SVG asset"
icon_path=$(jq -r '.interface.composerIcon // empty' "$PLUGIN_JSON")
icon_file="$PROJECT_ROOT/${icon_path#./}"
if [[ "$icon_path" == ./assets/*.svg ]] &&
   [[ -f "$icon_file" ]] &&
   grep -q '<svg' "$icon_file"; then
    test_pass
else
    test_fail "composerIcon should point to an existing SVG under assets/"
fi

test_case "package includes assets directory"
if jq -e '.files[] | select(. == "assets/")' "$PROJECT_ROOT/package.json" >/dev/null; then
    test_pass
else
    test_fail "package.json files should include assets/"
fi

test_summary
