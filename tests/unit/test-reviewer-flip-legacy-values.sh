#!/usr/bin/env bash
set -euo pipefail

# tests/unit/test-reviewer-flip-legacy-values.sh
# Regression test for #720: _octo_reviewer_flip_active() documented legacy
# truthy/falsy OCTOPUS_REVIEWER_FLIP values (1/on/true/yes/0/off/false/no) as
# honoured, but octo_features_choice() only passes an env value through when
# it matches a declared choice ("claude"/"codex") for the codex-reviewer-flip
# feature. On the normal path (features.sh sourced, as orchestrate.sh does),
# the legacy values were silently dropped and resolution fell through to the
# ledger/manifest default instead. This must be run with features.sh sourced
# to exercise the real path — asserting on the case arms in isolation passes
# while the underlying bug is present.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/octopus-tests-$$}"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM
tmp_bin="$TEST_TMP_DIR/bin"
tmp_home="$TEST_TMP_DIR/home"
mkdir -p "$tmp_bin" "$tmp_home"
cat > "$tmp_bin/codex" <<'MOCK_CODEX'
#!/usr/bin/env bash
exit 0
MOCK_CODEX
chmod +x "$tmp_bin/codex"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Reviewer flip legacy env values (#720)"

run_reviewer_flip() {
    local value="$1"
    env "HOME=$tmp_home" "PATH=$tmp_bin:$PATH" "OCTOPUS_REVIEWER_FLIP=$value" "OCTOPUS_LEGACY_ROLES=0" \
        bash -c '
            set -euo pipefail
            export PLUGIN_DIR="$1"
            source "$1/scripts/lib/features.sh"
            source "$1/scripts/lib/agent-utils.sh"
            mapping="$(get_role_mapping reviewer)"
            case "$mapping" in
                claude-opus:*) echo FLIPPED ;;
                codex-review:*) echo not-flipped ;;
                *) printf "unexpected reviewer mapping: %s\n" "$mapping" >&2; exit 1 ;;
            esac
        ' bash "$PROJECT_ROOT"
}

for value in claude 1 on true yes; do
    test_case "OCTOPUS_REVIEWER_FLIP=$value flips review to claude"
    got="$(run_reviewer_flip "$value")"
    if [[ "$got" == "FLIPPED" ]]; then
        test_pass
    else
        test_fail "expected FLIPPED, got $got"
    fi
done

for value in codex 0 off false no; do
    test_case "OCTOPUS_REVIEWER_FLIP=$value keeps review on codex"
    got="$(run_reviewer_flip "$value")"
    if [[ "$got" == "not-flipped" ]]; then
        test_pass
    else
        test_fail "expected not-flipped, got $got"
    fi
done

test_summary
