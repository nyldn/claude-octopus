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

test_case "a path argument continued onto its own line is not flagged as a sourced file"
workspace="$TEST_TMP_DIR/continued-dot-argument"
mkdir -p "$workspace/scripts"
cat > "$workspace/scripts/scan.sh" <<'EOF'
#!/usr/bin/env bash
workspace_paths=$(grep -rn "\.claude-octopus" \
  --include="*.sh" --include="*.js" \
  --exclude-dir=.git --exclude-dir=tests \
  . 2>/dev/null | \
  grep -v "~/" || true)
find \
    . -name '*.md'
grep -rn foo $(git ls-files) \
  . 2>/dev/null
EOF
output="$(run_hook_in "$workspace")"
assert_not_contains "$output" "sources missing file" "a continued '. 2>/dev/null' argument line must not be flagged" && test_pass

test_case "an empty continuation line keeps the continued command's arguments"
workspace="$TEST_TMP_DIR/empty-continuation"
mkdir -p "$workspace/scripts"
cat > "$workspace/scripts/scan.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' \
  \
  . 2>/dev/null
EOF
output="$(run_hook_in "$workspace")"
assert_not_contains "$output" "sources missing file" "'.' after an empty continuation line is still an argument" && test_pass

test_case "a reserved word used as an argument does not start a command"
workspace="$TEST_TMP_DIR/keyword-argument"
mkdir -p "$workspace/scripts"
cat > "$workspace/scripts/scan.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' then \
  . 2>/dev/null
EOF
output="$(run_hook_in "$workspace")"
assert_not_contains "$output" "sources missing file" "'then' as a printf argument must not make '.' a command" && test_pass

test_case "a source statement after a continued command is still flagged"
workspace="$TEST_TMP_DIR/source-after-continuation"
mkdir -p "$workspace/scripts"
printf '%s\n' '#!/usr/bin/env bash' 'grep -rn foo \' '  . 2>/dev/null' 'source ./lib/after-continuation.sh' 'echo trailing\\' '. ./lib/after-escaped-backslash.sh' > "$workspace/scripts/run.sh"
output="$(run_hook_in "$workspace")"
assert_not_contains "$output" "sources missing file: 2" "the continued argument line must not be flagged" || true
assert_contains "$output" "sources missing file: ./lib/after-continuation.sh" "a source after the continued command must be flagged" || true
assert_contains "$output" "after-escaped-backslash.sh" "an escaped trailing backslash must not continue the line" && test_pass

test_case "a source continued after a command separator or keyword is still flagged"
workspace="$TEST_TMP_DIR/source-after-separator"
mkdir -p "$workspace/scripts"
cat > "$workspace/scripts/run.sh" <<'EOF'
#!/usr/bin/env bash
true && \
  source ./lib/after-and.sh
false || \
  source ./lib/after-or.sh
true ; \
  source ./lib/after-semicolon.sh
printf 'x\n' | \
  source ./lib/after-pipe.sh
if true; then \
  . ./lib/after-then.sh
fi
true && \
  \
  source ./lib/after-empty-continuation.sh
FOO=bar \
  source ./lib/after-assignment.sh
stamp=$(date) \
  source ./lib/after-substitution-assignment.sh
case "${1:-}" in
  setup) \
    source ./lib/after-case-pattern.sh ;;
esac
load_helpers() { \
  source ./lib/after-function-definition.sh; }
EOF
output="$(run_hook_in "$workspace")"
assert_contains "$output" "sources missing file: ./lib/after-and.sh" "a source after '&& \\' must be flagged" || true
assert_contains "$output" "sources missing file: ./lib/after-or.sh" "a source after '|| \\' must be flagged" || true
assert_contains "$output" "sources missing file: ./lib/after-semicolon.sh" "a source after '; \\' must be flagged" || true
assert_contains "$output" "sources missing file: ./lib/after-pipe.sh" "a source after '| \\' must be flagged" || true
assert_contains "$output" "sources missing file: ./lib/after-then.sh" "a source after 'then \\' must be flagged" || true
assert_contains "$output" "sources missing file: ./lib/after-empty-continuation.sh" "an empty continuation line must keep the command position" || true
assert_contains "$output" "sources missing file: ./lib/after-assignment.sh" "a source after an assignment prefix must be flagged" || true
assert_contains "$output" "sources missing file: ./lib/after-substitution-assignment.sh" "a source after a command-substitution assignment must be flagged" || true
assert_contains "$output" "sources missing file: ./lib/after-case-pattern.sh" "a source after a case pattern must be flagged" || true
assert_contains "$output" "sources missing file: ./lib/after-function-definition.sh" "a source opening a function body must be flagged" && test_pass

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
