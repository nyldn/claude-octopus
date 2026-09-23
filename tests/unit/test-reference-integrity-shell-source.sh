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
		. as [$first, $second]
		| select($first != null)
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
printf '#!/usr/bin/env bash\nsource ./lib/common.sh\n. helpers.sh\n. bootstrap\n. as\n' > "$workspace/scripts/run.sh"
output="$(run_hook_in "$workspace")"
assert_contains "$output" "sources missing file: ./lib/common.sh" "missing ./lib/common.sh must still be flagged" && test_pass

test_case "missing dot-sourced file with an extension is still flagged"
assert_contains "$output" "helpers.sh" "missing helpers.sh must still be flagged" && test_pass

test_case "missing extensionless dot-sourced files are still flagged"
assert_contains "$output" "sources missing file: bootstrap" "missing extensionless bootstrap must still be flagged" && test_pass

test_case "dot-sourced file named as is not mistaken for a jq binder"
assert_contains "$output" "sources missing file: as" "plain '. as' must still be treated as shell sourcing" && test_pass

test_case "dot-sourced file named as with arguments is not mistaken for a jq binder"
workspace="$TEST_TMP_DIR/as-with-argument"
mkdir -p "$workspace/scripts"
printf '#!/usr/bin/env bash\n. as "$item"\n' > "$workspace/scripts/run.sh"
output="$(run_hook_in "$workspace")"
assert_contains "$output" "sources missing file: as" "'. as \$item' must still be treated as shell sourcing" && test_pass

test_case "existing sourced files are not flagged"
workspace="$TEST_TMP_DIR/present-source"
mkdir -p "$workspace/scripts/lib" "$workspace/scripts/shared files"
printf 'true\n' > "$workspace/scripts/lib/common.sh"
printf 'true\n' > "$workspace/scripts/bootstrap"
printf 'true\n' > "$workspace/scripts/shared files/double quoted.sh"
printf 'true\n' > "$workspace/scripts/shared files/single quoted.sh"
printf '#!/usr/bin/env bash\nsource lib/common.sh first-argument\n. bootstrap second-argument\nsource "shared files/double quoted.sh"\n. '\''shared files/single quoted.sh'\'' first-argument\n' > "$workspace/scripts/run.sh"
output="$(run_hook_in "$workspace")"
assert_not_contains "$output" "sources missing file" "present sourced files must not be flagged" && test_pass

test_case "adjacent text after a quoted source target remains part of the path"
workspace="$TEST_TMP_DIR/quoted-suffix"
mkdir -p "$workspace/scripts/shared files"
printf 'true\n' > "$workspace/scripts/shared files/double quoted.sh"
printf 'true\n' > "$workspace/scripts/shared files/single quoted.sh"
printf '#!/usr/bin/env bash\nsource "shared files/double quoted.sh".bak\n. '\''shared files/single quoted.sh'\''.bak\n' > "$workspace/scripts/run.sh"
output="$(run_hook_in "$workspace")"
assert_contains "$output" "sources missing file: shared files/double quoted.sh.bak" "double-quoted adjacent suffix must be retained" || true
assert_contains "$output" "sources missing file: shared files/single quoted.sh.bak" "single-quoted adjacent suffix must be retained" && test_pass

test_summary
