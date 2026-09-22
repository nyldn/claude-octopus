#!/usr/bin/env bash
# Regression: jq/awk program lines such as `. as $x` inside a shell script are not `source` statements.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_TMP_DIR="/tmp/octopus-tests-$$"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "reference integrity shell source"

run_hook_in() {
    local workspace="$1"
    local fake_home="$TEST_TMP_DIR/home"
    mkdir -p "$fake_home/.claude-octopus/results"
    printf '## Status: PASS\n' > "$fake_home/.claude-octopus/results/tangle-validation-test.md"
    ( cd "$workspace" && HOME="$fake_home" bash "$PROJECT_ROOT/hooks/quality-gate.sh" \
        <<<'{"tool_input":{"command":"bash orchestrate.sh"}}' 2>&1 )
}

test_case "jq filter lines starting with a dot are not flagged as sourced files"
workspace="$TEST_TMP_DIR/jq-dot"
mkdir -p "$workspace/scripts"
cat > "$workspace/scripts/report.sh" <<'EOF'
#!/usr/bin/env bash
jq '
	.items[]
	|
		. as $item
		| select(. != null)
' input.json
awk '
  . ~ /x/ { print }
' input.txt
EOF
output="$(run_hook_in "$workspace")"
assert_not_contains "$output" "sources missing file" "jq '. as \$x' lines must not be flagged" && test_pass

test_case "genuinely missing relative sourced files are still flagged"
workspace="$TEST_TMP_DIR/missing-source"
mkdir -p "$workspace/scripts"
printf '#!/usr/bin/env bash\nsource ./lib/common.sh\n. helpers.sh\n' > "$workspace/scripts/run.sh"
output="$(run_hook_in "$workspace")"
assert_contains "$output" "sources missing file: ./lib/common.sh" "missing ./lib/common.sh must still be flagged" && test_pass

test_case "missing dot-sourced file with an extension is still flagged"
assert_contains "$output" "helpers.sh" "missing helpers.sh must still be flagged" && test_pass

test_case "existing sourced files are not flagged"
workspace="$TEST_TMP_DIR/present-source"
mkdir -p "$workspace/scripts/lib"
printf 'true\n' > "$workspace/scripts/lib/common.sh"
printf '#!/usr/bin/env bash\nsource lib/common.sh\n' > "$workspace/scripts/run.sh"
output="$(run_hook_in "$workspace")"
assert_not_contains "$output" "sources missing file" "present sourced files must not be flagged" && test_pass

test_summary
