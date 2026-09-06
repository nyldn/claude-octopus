#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "retired OpenClaw integration"

retired_token_pattern='openclaw|octo-claw|OCTO_CLAW|CLAUDE_OCTOPUS_OPENCLAW'

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
    git grep -n -i -E "$retired_token_pattern" -- \
        ':!CHANGELOG.md' \
        ':!docs/plans/**' \
        ':!docs/superpowers/**' \
        ':!docs/UPGRADING-V11.0.1.md' \
        ':!README.md' \
        ':!.claude-plugin/plugin.json' \
        ':!.claude-plugin/marketplace.json' \
        ':!tests/unit/test-retired-openclaw.sh' \
        ':!tests/unit/test-retired-claw-admin.sh' \
        || true
)"
if [[ -z "$matches" ]]; then
    test_pass
else
    test_fail "retired OpenClaw wiring remains:\n$matches"
fi

test_case "release metadata mentions OpenClaw only as the current-version removal"
current_version="$(node -p "require('$PROJECT_ROOT/package.json').version")"
escaped_current_version="${current_version//./\\.}"
current_version_pattern="v${escaped_current_version}([^0-9.]|$)"
expected_removal_note="Remove the unused OpenClaw integration and simplify MCP setup."
release_note_matches="$({
    cd "$PROJECT_ROOT"
    git grep -n -i -E "$retired_token_pattern" -- \
        README.md \
        .claude-plugin/plugin.json \
        .claude-plugin/marketplace.json \
        || true
})"
release_note_count="$(printf '%s\n' "$release_note_matches" | grep -c . || true)"
unexpected_release_notes=""
while IFS= read -r release_note_line; do
    [[ -n "$release_note_line" ]] || continue
    residual_line="${release_note_line/"$expected_removal_note"/}"
    if ! [[ "$release_note_line" =~ $current_version_pattern ]] ||
       [[ "$release_note_line" != *"$expected_removal_note"* ]] ||
       printf '%s\n' "$residual_line" | grep -qiE "$retired_token_pattern"; then
        unexpected_release_notes+="${release_note_line}"$'\n'
    fi
done <<< "$release_note_matches"
if [[ "$release_note_count" -ge 1 ]] && [[ -z "$unexpected_release_notes" ]]; then
    test_pass
else
    test_fail "release metadata contains active OpenClaw guidance or unexpected removal notes:\n${unexpected_release_notes:-found $release_note_count expected removal notes}"
fi

test_case "release version matching rejects longer version prefixes"
if ! [[ "v${current_version}0" =~ $current_version_pattern ]] &&
   ! [[ "v${current_version}.1" =~ $current_version_pattern ]]; then
    test_pass
else
    test_fail "release version matching accepted a longer version prefix"
fi

test_case "MCP server starts without the retired OpenClaw opt-in variable"
if ! grep -q 'OCTO_CLAW_ENABLED' "$PROJECT_ROOT/mcp-server/src/index.ts"; then
    test_pass
else
    test_fail "mcp-server/src/index.ts still depends on OCTO_CLAW_ENABLED"
fi

test_summary
