#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "runtime provider labels"

test_case "external CLI wrapper marks provider as legacy alias"
source "$PROJECT_ROOT/scripts/lib/validation.sh" 2>/dev/null
out=$(wrap_cli_output codex "OCTOPUS_RUNTIME_ADAPTER=openai-compatible
OCTOPUS_RUNTIME_PROVIDER=deepseek
OCTOPUS_RUNTIME_MODEL=deepseek-ai/DeepSeek-V4-Pro
response body")
if grep -q 'provider="codex"' <<<"$out" && grep -q 'executor-alias="codex"' <<<"$out" && grep -q 'provider-label-kind="legacy-alias"' <<<"$out" && grep -q 'runtime-adapter="openai-compatible"' <<<"$out" && grep -q 'runtime-provider="deepseek"' <<<"$out" && grep -q 'runtime-model="deepseek-ai/DeepSeek-V4-Pro"' <<<"$out"; then
  test_pass
else
  test_fail "wrapper did not distinguish alias from runtime provider"
fi

test_case "spawn result headers identify executor alias and configured model"
if grep -q '# Executor alias: $agent_type' "$PROJECT_ROOT/scripts/lib/spawn.sh" && grep -q '# Configured model: ${model:-unresolved}' "$PROJECT_ROOT/scripts/lib/spawn.sh"; then
  test_pass
else
  test_fail "spawn headers missing explicit executor/model labels"
fi

test_case "correction log uses stable runtime identity field names"
if grep -q 'executor_alias=${correction_agent}, configured_adapter=unknown, configured_model=${correction_model}, runtime_adapter=unknown, runtime_provider=unknown, runtime_model=unknown' "$PROJECT_ROOT/scripts/lib/workflows.sh" && ! grep -q 'with ${correction_agent}...' "$PROJECT_ROOT/scripts/lib/workflows.sh"; then
  test_pass
else
  test_fail "correction log still uses ambiguous provider wording"
fi


test_case "runtime identity artifact detects routing mismatch"
tmp=$(mktemp -d)
printf '%s\n' 'OCTOPUS_RUNTIME_ADAPTER=openai-compatible' 'OCTOPUS_RUNTIME_PROVIDER=deepseek' 'OCTOPUS_RUNTIME_MODEL=deepseek-ai/DeepSeek-V4-Pro' > "$tmp/raw.out"
: > "$tmp/result.md"
octo_append_runtime_identity "$tmp/result.md" codex gpt-5.5 "$tmp/raw.out"
if grep -q -- '- Runtime adapter: openai-compatible' "$tmp/result.md" && grep -q -- '- Runtime provider: deepseek' "$tmp/result.md" && grep -q -- '- Runtime model: deepseek-ai/DeepSeek-V4-Pro' "$tmp/result.md" && grep -q -- '- Routing mismatch: true' "$tmp/result.md"; then
  test_pass
else
  test_fail "runtime identity did not preserve reported provider/model and mismatch"
fi
rm -rf "$tmp"

test_case "unknown runtime identity is explicit rather than inferred"
out=$(wrap_cli_output codex "plain response without identity metadata")
if grep -q 'runtime-provider="unknown"' <<<"$out" && grep -q 'runtime-model="unknown"' <<<"$out"; then
  test_pass
else
  test_fail "missing runtime identity was inferred or omitted"
fi

test_case "all central role events use stable identity fields"
missing=0
for file in spawn.sh council.sh debate.sh parallel.sh review.sh; do
  grep -q 'executor_alias=' "$PROJECT_ROOT/scripts/lib/$file" || missing=1
  grep -q 'runtime_adapter=' "$PROJECT_ROOT/scripts/lib/$file" || missing=1
  grep -q 'runtime_provider=' "$PROJECT_ROOT/scripts/lib/$file" || missing=1
  grep -q 'runtime_model=' "$PROJECT_ROOT/scripts/lib/$file" || missing=1
done
if [[ "$missing" -eq 0 ]] && grep -q 'council_role="chair"' "$PROJECT_ROOT/scripts/lib/council.sh" && grep -q 'synthesis_strategy="debate"' "$PROJECT_ROOT/scripts/lib/debate.sh"; then
  test_pass
else
  test_fail "one or more role events still lack stable identity/role fields"
fi

test_summary
