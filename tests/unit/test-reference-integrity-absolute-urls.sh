#!/usr/bin/env bash
# Regression: server-root-absolute asset URLs must not be reported as missing files.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/octopus-refint-$$}"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "reference integrity absolute urls"

run_hook_in() {
    local workspace="$1"
    local fake_home="$TEST_TMP_DIR/home"
    mkdir -p "$fake_home/.claude-octopus/results"
    printf '## Status: PASS\n' > "$fake_home/.claude-octopus/results/tangle-validation-test.md"
    ( cd "$workspace" && HOME="$fake_home" bash "$PROJECT_ROOT/hooks/quality-gate.sh" \
        <<<'{"tool_input":{"command":"bash orchestrate.sh"}}' 2>&1 || true )
}

test_case "server-absolute refs served by a web framework are not flagged"
workspace="$TEST_TMP_DIR/absolute"
mkdir -p "$workspace/src/app/static"
printf '<html><head><link rel="stylesheet" href="/static/styles.css"></head><body><script src="/static/app.js"></script></body></html>\n' \
    > "$workspace/src/app/static/index.html"
printf 'body{}\n' > "$workspace/src/app/static/styles.css"
printf 'void 0;\n' > "$workspace/src/app/static/app.js"
output="$(run_hook_in "$workspace")"
assert_not_contains "$output" "references missing" "server-absolute refs must not be flagged" && test_pass

test_case "genuinely missing relative refs are still flagged"
workspace="$TEST_TMP_DIR/relative"
mkdir -p "$workspace/src/app"
printf '<html><body><script src="nope.js"></script></body></html>\n' > "$workspace/src/app/index.html"
output="$(run_hook_in "$workspace")"
assert_contains "$output" "references missing script: nope.js" "missing relative refs must still be flagged" && test_pass

test_summary
