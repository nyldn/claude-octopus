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

test_case "model syntax rejection leaves configuration unchanged across commands"
cp "$TMP_HOME/.claude-octopus/config/providers.json" "$TMP_HOME/config-before.json"
unsafe_models=(
    '/absolute/model' 'bad;model' 'bad|model' 'bad&model' 'bad$model'
    'bad`model`' "bad'model" 'bad"model' 'bad<model' 'bad>model'
    'bad!model' 'bad*model' 'bad?model' 'bad[model' 'bad]model'
    'bad{model' 'bad}model' 'bad\model' 'bad$(model)' $'bad\nmodel' $'bad\tmodel'
    $'bad\rmodel' ' ( )'
)
validation_failed=false
for model in "${unsafe_models[@]}"; do
    for command in set tier route route-role; do
        case "$command" in
            set) args=(set agy "$model") ;;
            tier) args=(tier standard agy "$model") ;;
            route) args=(route research "agy:$model") ;;
            route-role) args=(route-role researcher "agy:$model") ;;
        esac
        if run_helper "${args[@]}" >"$TMP_ERR" 2>&1 ||
           ! grep -q 'Invalid' "$TMP_ERR" ||
           grep -q 'invalid regular expression' "$TMP_ERR" ||
           ! cmp -s "$TMP_HOME/config-before.json" "$TMP_HOME/.claude-octopus/config/providers.json"; then
            test_fail "$command did not reject unsafe model [$model] without changing config"
            validation_failed=true
            break 2
        fi
    done
done
[[ "$validation_failed" == true ]] || test_pass

test_case "standard model IDs remain valid without regex errors"
if run_helper set codex gpt-5.6-sol >"$TMP_OUT" 2>"$TMP_ERR" &&
   run_helper set opencode openai/gpt-5 >"$TMP_OUT" 2>>"$TMP_ERR" &&
   [[ ! -s "$TMP_ERR" ]]; then
    test_pass
else
    test_fail "valid model IDs failed or printed validation errors"
fi

test_case "Antigravity display labels work in all model configuration commands"
label='Gemini 3.1 Pro (High)'
if run_helper set agy "$label" >"$TMP_OUT" 2>"$TMP_ERR" &&
   run_helper tier standard agy "$label" >"$TMP_OUT" 2>>"$TMP_ERR" &&
   run_helper route research "agy:$label" >"$TMP_OUT" 2>>"$TMP_ERR" &&
   run_helper route-role researcher "agy:$label" >"$TMP_OUT" 2>>"$TMP_ERR" &&
   [[ ! -s "$TMP_ERR" ]] &&
   jq -e --arg label "$label" '
       .providers.agy.default == $label and
       .tiers.standard.agy == $label and
       .routing.phases.research == ("agy:" + $label) and
       .routing.roles.researcher == ("agy:" + $label)
   ' "$TMP_HOME/.claude-octopus/config/providers.json" >/dev/null; then
    test_pass
else
    test_fail "Antigravity display labels were rejected, corrupted, or printed regex errors"
fi

test_case "display-name exceptions do not apply to other providers"
cp "$TMP_HOME/.claude-octopus/config/providers.json" "$TMP_HOME/config-before.json"
if run_helper set opencode 'custom model (High)' >"$TMP_ERR" 2>&1 ||
   ! grep -q 'Invalid model name' "$TMP_ERR" ||
   ! cmp -s "$TMP_HOME/config-before.json" "$TMP_HOME/.claude-octopus/config/providers.json"; then
    test_fail "a non-Antigravity model bypassed syntax validation"
else
    test_pass
fi

test_summary
