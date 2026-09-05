#!/usr/bin/env bash
# Replay audit regressions against local contracts only. No provider is called.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
CORPUS="${1:-$PROJECT_ROOT/data/evals/audit-failure-corpus.json}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/octopus-contract-evals.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

[[ -r "$CORPUS" ]] || { printf 'missing corpus: %s\n' "$CORPUS" >&2; exit 2; }
jq -e '.schema_version == 1 and (.cases | type == "array" and length > 0)' "$CORPUS" >/dev/null

log() { :; }
source "$PROJECT_ROOT/scripts/lib/models.sh"
source "$PROJECT_ROOT/scripts/lib/provider-registry.sh"
source "$PROJECT_ROOT/scripts/lib/agent-spec.sh"
source "$PROJECT_ROOT/scripts/lib/validation.sh"
source "$PROJECT_ROOT/scripts/lib/fallback-chain.sh"
source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
source "$PROJECT_ROOT/scripts/lib/council.sh"
source "$PROJECT_ROOT/scripts/lib/dispatch.sh"

eval_native_worktree() {
    jq -e '(.hooks | has("WorktreeCreate") | not) and (.hooks | has("WorktreeRemove") | not)' \
        "$PROJECT_ROOT/hooks/hooks.json" >/dev/null
}

eval_frontier_fallback() {
    ! octo_fallback_admit_automatic_spec 'codex:gpt-6-astra' '' &&
        octo_fallback_admit_automatic_spec 'codex:gpt-6-astra' 'gpt-6-astra'
}

eval_strict_verdict() {
    printf '%s\n' 'VERDICT: APPROVE after the defect is fixed' > "$TMP_ROOT/verdict.md"
    [[ "$(council_response_verdict "$TMP_ROOT/verdict.md")" == REVISE ]]
}

eval_provider_isolation() {
    export OPENAI_API_KEY='fixture-key'
    export OCTOPUS_AUDIT_SENTINEL='must-not-cross'
    _octo_build_openai_tool_loop_env openai-compatible-agent OPENAI_API_KEY
    local joined=" ${PROVIDER_ENV_ARRAY[*]-} "
    [[ "$joined" == *' OPENAI_API_KEY=fixture-key '* && "$joined" != *OCTOPUS_AUDIT_SENTINEL* ]]
}

eval_process_tree_timeout() {
    OCTO_EVAL_HELPER="$PROJECT_ROOT/scripts/helpers/openai-compatible-agent.py" \
    OCTO_EVAL_TMP="$TMP_ROOT" python3 - <<'PY'
import importlib.util
import os
import subprocess
import time
from pathlib import Path

path = Path(os.environ["OCTO_EVAL_HELPER"])
spec = importlib.util.spec_from_file_location("octopus_openai_helper", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
marker = Path(os.environ["OCTO_EVAL_TMP"]) / "late-write"
command = f"(sleep 1; printf late > '{marker}') & wait"
try:
    module.run_bounded_process(command, marker.parent, 0.1, shell=True, output_limit=1024)
except subprocess.TimeoutExpired:
    pass
else:
    raise SystemExit("timeout was not raised")
time.sleep(1.2)
if marker.exists():
    raise SystemExit("descendant survived timeout")
PY
}

eval_codex_effective_credential() {
    local config="$TMP_ROOT/codex.toml"
    printf '%s\n' \
        'model_provider = "router"' \
        '[model_providers.openai]' \
        'env_key = "OPENAI_API_KEY"' \
        '[model_providers.router]' \
        'env_key = "ROUTER_API_KEY"' > "$config"
    [[ "$(python3 "$PROJECT_ROOT/scripts/helpers/read-codex-config.py" "$config")" == ROUTER_API_KEY ]]
}

eval_usage_reconciliation() {
    local ledger="$TMP_ROOT/usage.jsonl" helper="$PROJECT_ROOT/scripts/helpers/usage-ledger.py"
    python3 "$helper" append --file "$ledger" --state reserved --call-id call-1 \
        --agent codex --model gpt-5.6-sol --total-tokens 100 --cost 1 >/dev/null
    python3 "$helper" append --file "$ledger" --state completed --call-id call-1 \
        --agent codex --model gpt-5.6-sol --input-tokens 10 --output-tokens 10 \
        --total-tokens 20 --cost 0.2 >/dev/null
    python3 "$helper" append --file "$ledger" --state completed --call-id call-1 \
        --agent codex --model gpt-5.6-sol --total-tokens 999 --cost 9 >/dev/null
    python3 "$helper" report --file "$ledger" --format json |
        jq -e '.totals.calls == 1 and .totals.tokens == 20 and .totals.cost_usd == 0.2' >/dev/null
}

eval_package_allowlist() {
    jq -e '.files | index("commands/") != null' "$PROJECT_ROOT/package.json" >/dev/null &&
        jq -e '.commands | length > 0' "$PROJECT_ROOT/.claude-plugin/plugin.json" >/dev/null
}

eval_model_context_ceiling() {
    local limit
    limit="$(OCTOPUS_CLAUDE_SDK_CONTEXT_BUDGET=1000000 \
        OCTOPUS_CONTEXT_OUTPUT_RESERVE_TOKENS=0 OCTOPUS_CONTEXT_OVERHEAD_TOKENS=0 \
        get_provider_context_limit 'claude-sdk:claude-haiku-4.5')"
    [[ "$limit" == 200000 ]]
}

run_contract() {
    case "$1" in
        native-worktree) eval_native_worktree ;;
        frontier-fallback) eval_frontier_fallback ;;
        strict-verdict) eval_strict_verdict ;;
        provider-isolation) eval_provider_isolation ;;
        process-tree-timeout) eval_process_tree_timeout ;;
        codex-effective-credential) eval_codex_effective_credential ;;
        usage-reconciliation) eval_usage_reconciliation ;;
        package-allowlist) eval_package_allowlist ;;
        model-context-ceiling) eval_model_context_ceiling ;;
        *) return 2 ;;
    esac
}

results='[]'
while IFS= read -r encoded; do
    item="$(printf '%s' "$encoded" | base64 --decode 2>/dev/null || printf '%s' "$encoded" | base64 -D)"
    id="$(jq -r '.id' <<< "$item")"
    contract="$(jq -r '.contract' <<< "$item")"
    expected="$(jq -r '.expected' <<< "$item")"
    actual=fail
    run_contract "$contract" >/dev/null 2>&1 && actual=pass
    results="$(jq -cn --argjson results "$results" --arg id "$id" \
        --arg contract "$contract" --arg expected "$expected" --arg actual "$actual" \
        '$results + [{id:$id,contract:$contract,expected:$expected,actual:$actual,matched:($expected==$actual)}]')"
done < <(jq -r '.cases[] | @base64' "$CORPUS")

jq -cn --argjson results "$results" '
    {schema_version:1,total:($results|length),
     passed:([$results[]|select(.matched)]|length),
     failed:([$results[]|select(.matched|not)]|length),results:$results}'
[[ "$(jq '[.[] | select(.matched | not)] | length' <<< "$results")" == 0 ]]
