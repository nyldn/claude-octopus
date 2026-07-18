#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "runtime provider labels"

test_case "external CLI wrapper marks provider as legacy alias"
source "$PROJECT_ROOT/scripts/lib/validation.sh" 2>/dev/null
out=$(wrap_cli_output codex "model: deepseek-ai/DeepSeek-V4-Pro
provider: pioneer")
if grep -q 'provider="codex"' <<<"$out" && grep -q 'executor-alias="codex"' <<<"$out" && grep -q 'provider-label-kind="legacy-alias"' <<<"$out" && grep -q 'provider: pioneer' <<<"$out"; then
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

test_case "correction log avoids ambiguous with-provider wording"
if grep -q 'with executor alias=${correction_agent}, configured model=${correction_model}' "$PROJECT_ROOT/scripts/lib/workflows.sh" && ! grep -q 'with ${correction_agent}...' "$PROJECT_ROOT/scripts/lib/workflows.sh"; then
  test_pass
else
  test_fail "correction log still uses ambiguous provider wording"
fi

test_summary
