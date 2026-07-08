#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "model-config role routing"

HELPER="$SCRIPT_DIR/../../scripts/helpers/octo-model-config.sh"
TMP_HOME="$(mktemp -d)"
TMP_OUT="$TMP_HOME/model-config-role-route.out"
TMP_ERR="$TMP_HOME/model-config-bad-role.out"
trap 'rm -rf "$TMP_HOME"' EXIT

run_helper() {
    HOME="$TMP_HOME" "$HELPER" "$@"
}

test_case "route-role writes routing.roles override"
run_helper route-role qa-reviewer codex:council >"$TMP_OUT"
if jq -e '.routing.roles["qa-reviewer"] == "codex:council"' "$TMP_HOME/.claude-octopus/config/providers.json" >/dev/null; then
    test_pass
else
    test_fail "route-role did not write expected role override"
fi

test_case "show roles displays explicit overrides"
run_helper route-role researcher agy:default >"$TMP_OUT"
if run_helper show roles | grep -c 'researcher.*agy:default' >/dev/null; then
    test_pass
else
    test_fail "show roles did not display role override"
fi

test_case "unroute-role removes override"
run_helper unroute-role qa-reviewer >"$TMP_OUT"
if jq -e '.routing.roles["qa-reviewer"] == null' "$TMP_HOME/.claude-octopus/config/providers.json" >/dev/null; then
    test_pass
else
    test_fail "unroute-role did not remove role override"
fi

test_case "invalid role name is rejected"
if run_helper route-role 'bad role' codex:default >"$TMP_ERR" 2>&1; then
    test_fail "invalid role name unexpectedly succeeded"
elif grep -c 'Invalid role' "$TMP_ERR" >/dev/null; then
    test_pass
else
    test_fail "invalid role error message missing"
fi

test_summary
