#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "retired OpenClaw integration"

assert_absent() {
    local relative_path="$1"
    test_case "$relative_path does not ship"
    if [[ ! -e "$PROJECT_ROOT/$relative_path" ]]; then
        test_pass
    else
        test_fail "$relative_path must be removed"
    fi
}

for relative_path in \
    openclaw \
    scripts/build-openclaw.sh \
    tests/validate-openclaw.sh \
    tests/unit/test-openclaw-compat.sh \
    tests/unit/test-openclaw-integration.sh; do
    assert_absent "$relative_path"
done

test_case "active product files contain no OpenClaw integration wiring"
matches="$(
    cd "$PROJECT_ROOT"
    git grep -n -i -E 'openclaw|octo-claw|OCTO_CLAW|CLAUDE_OCTOPUS_OPENCLAW' -- \
        ':!CHANGELOG.md' \
        ':!docs/plans/**' \
        ':!docs/superpowers/**' \
        ':!docs/UPGRADING-V11.0.1.md' \
        ':!tests/unit/test-retired-openclaw.sh' \
        ':!tests/unit/test-retired-claw-admin.sh' \
        || true
)"
if [[ -z "$matches" ]]; then
    test_pass
else
    test_fail "retired OpenClaw wiring remains:\n$matches"
fi

test_case "MCP server starts without the retired OpenClaw opt-in variable"
if ! grep -q 'OCTO_CLAW_ENABLED' "$PROJECT_ROOT/mcp-server/src/index.ts"; then
    test_pass
else
    test_fail "mcp-server/src/index.ts still depends on OCTO_CLAW_ENABLED"
fi

test_summary
