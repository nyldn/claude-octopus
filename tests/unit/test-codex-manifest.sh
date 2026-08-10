#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Codex plugin manifest"

test_case "Codex default prompts stay within the host limit of three"
if [[ "$(jq '.interface.defaultPrompt | length' "$PROJECT_ROOT/.codex-plugin/plugin.json")" -le 3 ]]; then
    test_pass
else
    test_fail "Codex supports at most three interface.defaultPrompt entries"
fi

test_summary
