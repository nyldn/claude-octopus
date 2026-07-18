#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/validation.sh"
source "$PROJECT_ROOT/scripts/lib/spawn.sh"
source "$PROJECT_ROOT/scripts/lib/workflows.sh"
TEST_TMP_DIR="/tmp/octopus-tests-$$"
mkdir -p "$TEST_TMP_DIR"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT
test_suite "runtime provider labels"

test_case "native OpenAI-compatible runtime identity is captured in artifacts"
tmp="$TEST_TMP_DIR/native-runtime"
mkdir -p "$tmp"
printf '%s\n' 'provider=generic base_url=https://example.invalid/v1 model=deepseek-ai/DeepSeek-V4-Pro cwd=/tmp/project' > "$tmp/raw.out"
: > "$tmp/result.md"
octo_append_runtime_identity "$tmp/result.md" openai-compatible deepseek-ai/DeepSeek-V4-Pro "$tmp/raw.out"
if grep -q -- '- Configured provider: openai-compatible' "$tmp/result.md" && grep -q -- '- Runtime provider: openai-compatible' "$tmp/result.md" && grep -q -- '- Runtime model: deepseek-ai/DeepSeek-V4-Pro' "$tmp/result.md" && grep -q -- '- Routing mismatch: false' "$tmp/result.md"; then
  test_pass
else
  test_fail "native OpenAI-compatible provider/model identity was not captured"
fi

test_case "spawn result header function emits concrete identity values"
header="$TEST_TMP_DIR/header.md"
write_agent_result_header "$header" openai-compatible deepseek-ai/DeepSeek-V4-Pro task-1 reviewer review legacy
if grep -q '^# Executor alias: openai-compatible$' "$header" && grep -q '^# Configured provider: openai-compatible$' "$header" && grep -q '^# Configured model: deepseek-ai/DeepSeek-V4-Pro$' "$header" && grep -q '^# Role: reviewer$' "$header"; then
  test_pass
else
  test_fail "spawn header helper did not emit concrete runtime identity"
fi

test_case "correction log helper interpolates stable identity values"
msg=$(tangle_correction_identity_message 2 delta 1800 openai-compatible deepseek-ai/DeepSeek-V4-Pro)
if [[ "$msg" == *"round=2"* && "$msg" == *"executor_alias=openai-compatible"* && "$msg" == *"configured_provider=openai-compatible"* && "$msg" == *"configured_model=deepseek-ai/DeepSeek-V4-Pro"* ]]; then
  test_pass
else
  test_fail "correction identity message did not interpolate concrete values: $msg"
fi

test_case "runtime identity artifact detects routing mismatch"
tmp="$TEST_TMP_DIR/mismatch"
mkdir -p "$tmp"
printf '%s\n' 'provider=generic base_url=https://example.invalid/v1 model=deepseek-ai/DeepSeek-V4-Pro cwd=/tmp/project' > "$tmp/raw.out"
: > "$tmp/result.md"
octo_append_runtime_identity "$tmp/result.md" openai-compatible gpt-5.5 "$tmp/raw.out"
if grep -q -- '- Configured provider: openai-compatible' "$tmp/result.md" && grep -q -- '- Runtime provider: openai-compatible' "$tmp/result.md" && grep -q -- '- Runtime model: deepseek-ai/DeepSeek-V4-Pro' "$tmp/result.md" && grep -q -- '- Routing mismatch: true' "$tmp/result.md"; then
  test_pass
else
  test_fail "runtime identity did not preserve reported provider/model and mismatch"
fi

test_case "unknown runtime identity is explicit rather than inferred"
out=$(wrap_cli_output codex "plain response without identity metadata")
if grep -q 'runtime-provider="codex"' <<<"$out" && grep -q 'runtime-model="unknown"' <<<"$out"; then
  test_pass
else
  test_fail "missing runtime identity was inferred or omitted"
fi

test_case "all central role events use stable identity fields"
missing=0
for file in spawn.sh council.sh debate.sh parallel.sh review.sh; do
  grep -q 'executor_alias=' "$PROJECT_ROOT/scripts/lib/$file" || missing=1
  grep -q 'runtime_provider=' "$PROJECT_ROOT/scripts/lib/$file" || missing=1
  grep -q 'runtime_model=' "$PROJECT_ROOT/scripts/lib/$file" || missing=1
done
if [[ "$missing" -eq 0 ]] && grep -q 'council_role="chair"' "$PROJECT_ROOT/scripts/lib/council.sh" && grep -q 'synthesis_strategy="debate"' "$PROJECT_ROOT/scripts/lib/debate.sh"; then
  test_pass
else
  test_fail "one or more role events still lack stable identity/role fields"
fi

test_summary
