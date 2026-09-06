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

test_case "the retirement release records removal without current metadata wiring"
expected_removal_note="Remove the unused OpenClaw integration and simplify MCP setup"
retirement_doc="$(grep -il -m1 'no longer ships the OpenClaw extension' "$PROJECT_ROOT"/docs/UPGRADING-*.md 2>/dev/null | head -n 1)"
retirement_release="$(basename "$retirement_doc" | sed -E 's/^UPGRADING-V([0-9]+\.[0-9]+\.[0-9]+)\.md$/\1/')"
retirement_heading="## [${retirement_release}]"
retirement_section="$(awk -v target="$retirement_heading" '
    /^## \[/ {
        if (in_target) {
            printf "%s", section
            exit
        }
        in_target = (index($0, target) == 1)
        section = in_target ? $0 ORS : ""
        next
    }
    in_target {
        section = section $0 ORS
    }
    END {
        if (in_target) {
            printf "%s", section
        }
    }
' "$PROJECT_ROOT/CHANGELOG.md")"
current_metadata_matches="$({
    cd "$PROJECT_ROOT"
    git grep -n -i -E "$retired_token_pattern" -- \
        README.md \
        .claude-plugin/plugin.json \
        .claude-plugin/marketplace.json \
        || true
})"
if [[ -f "$retirement_doc" ]] &&
   [[ "$retirement_release" != "$(basename "$retirement_doc")" ]] &&
   [[ -n "$retirement_release" ]] &&
   printf '%s\n' "$retirement_section" | grep -qF "$retirement_heading" &&
   printf '%s\n' "$retirement_section" | grep -qF "$expected_removal_note" &&
   [[ -z "$current_metadata_matches" ]]; then
    test_pass
else
    test_fail "retirement release note or current metadata contract is invalid:\n${retirement_section:-missing retirement release section or removal note}\n${current_metadata_matches:-}"
fi

test_case "retirement release version matching rejects longer version prefixes"
escaped_retirement_release="${retirement_release//./\\.}"
retirement_release_pattern="v${escaped_retirement_release}([^0-9.]|$)"
if ! [[ "v${retirement_release}0" =~ $retirement_release_pattern ]] &&
   ! [[ "v${retirement_release}.1" =~ $retirement_release_pattern ]]; then
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
