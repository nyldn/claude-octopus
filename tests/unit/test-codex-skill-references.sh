#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Codex skill references"
test_case "generated routes and host registration retain valid skill targets"
if python3 "$PROJECT_ROOT/tests/fixtures/native-skills/codex-references.py" "$PROJECT_ROOT"; then
    test_pass
else
    test_fail "Codex reference adaptation failed"
fi

while read -r tree route; do
    test_case "$tree uses its installed route in the parallel migration example"
    example=$(awk '
        /^### Example: Migration/ { migration = 1; next }
        /^### / && migration { exit }
        migration && /^User: / { print; exit }
    ' "$PROJECT_ROOT/$tree/flow-parallel/SKILL.md")
    if [[ "$example" == "User: $route migrate "* ]]; then
        test_pass
    else
        test_fail "Expected $route, found: $example"
    fi
done <<'ROUTES'
skills /octo:parallel
.claude/skills /octo:parallel
codex-skills $flow-parallel
ROUTES

test_summary
