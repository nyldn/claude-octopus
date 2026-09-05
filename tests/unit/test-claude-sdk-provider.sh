#!/usr/bin/env bash
# Tests for the claude-sdk provider shim and its dispatch wiring.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "claude-sdk provider"

SHIM="$PROJECT_ROOT/scripts/helpers/claude-sdk-exec.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

test_case "shim refuses to run without CLAUDE_SDK_API_KEY"
set +e
out=$(printf 'hello' | env -u CLAUDE_SDK_API_KEY bash "$SHIM" 2>&1)
rc=$?
set -e
if [[ $rc -eq 78 && "$out" == *"CLAUDE_SDK_API_KEY is not set"* ]]; then
    test_pass
else
    test_fail "expected exit 78 without key, got rc=$rc out=$out"
fi

test_case "shim refuses empty stdin prompt"
set +e
out=$(printf '   ' | CLAUDE_SDK_API_KEY=test-key bash "$SHIM" 2>&1)
rc=$?
set -e
if [[ $rc -eq 64 && "$out" == *"no prompt provided on stdin"* ]]; then
    test_pass
else
    test_fail "expected exit 64 for empty prompt, got rc=$rc out=$out"
fi

test_case "shim prefers claude-agent SDK CLI and passes model + key"
cat > "$TMP_DIR/claude-agent" <<'STUB'
#!/usr/bin/env bash
echo "argv:$*"
echo "key:${ANTHROPIC_API_KEY:-unset}"
echo "nested:${CLAUDECODE:-unset}"
cat
STUB
chmod +x "$TMP_DIR/claude-agent"
out=$(printf 'test prompt' | PATH="$TMP_DIR:$PATH" CLAUDECODE=1 CLAUDE_SDK_API_KEY=sk-sdk-test bash "$SHIM")
if [[ "$out" == *"--model claude-opus-5"* \
   && "$out" == *"key:sk-sdk-test"* \
   && "$out" == *"nested:unset"* \
   && "$out" == *"test prompt"* ]]; then
    test_pass
else
    test_fail "SDK CLI invocation wrong: $out"
fi

test_case "OCTOPUS_CLAUDE_SDK_MODEL overrides the default model"
out=$(printf 'p' | PATH="$TMP_DIR:$PATH" CLAUDE_SDK_API_KEY=k OCTOPUS_CLAUDE_SDK_MODEL=claude-fable-5 bash "$SHIM")
if [[ "$out" == *"--model claude-fable-5"* ]]; then
    test_pass
else
    test_fail "model override ignored: $out"
fi

test_case "Fable 5.1 SDK pins retain refusal recovery"
retry_dir="$TMP_DIR/fable-retry"
retry_log="$TMP_DIR/fable-retry.log"
mkdir -p "$retry_dir"
cat > "$retry_dir/claude-agent" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$OCTOPUS_TEST_CAPTURE"
if [[ "$*" == *claude-fable-5-1* ]]; then
    exit 0
fi
printf '%s\n' 'opus recovery'
STUB
chmod +x "$retry_dir/claude-agent"
out=$(printf 'p' | PATH="$retry_dir:/usr/bin:/bin" CLAUDE_SDK_API_KEY=k \
    OCTOPUS_TEST_CAPTURE="$retry_log" OCTOPUS_CLAUDE_SDK_MODEL=claude-fable-5-1 bash "$SHIM" 2>/dev/null)
if [[ "$out" == "opus recovery" ]] && grep -Fq -- '--model claude-fable-5-1' "$retry_log" &&
   grep -Fq -- '--model claude-opus-5' "$retry_log"; then
    test_pass
else
    test_fail "Fable 5.1 did not recover through Opus: out=$out"
fi

test_case "claude CLI fallback receives the configured output-token limit"
CLI_DIR="$TMP_DIR/claude-only"
mkdir -p "$CLI_DIR"
cat > "$CLI_DIR/claude" <<'STUB'
#!/usr/bin/env bash
echo "argv:$*"
echo "max:${CLAUDE_CODE_MAX_OUTPUT_TOKENS:-unset}"
cat
STUB
chmod +x "$CLI_DIR/claude"
out=$(printf 'fallback prompt' | env "PATH=$CLI_DIR:/usr/bin:/bin" \
    "CLAUDE_SDK_API_KEY=k" "OCTOPUS_CLAUDE_SDK_MAX_TOKENS=777" bash "$SHIM")
if [[ "$out" == *"--model claude-opus-5"* \
   && "$out" == *"max:777"* \
   && "$out" == *"fallback prompt"* ]]; then
    test_pass
else
    test_fail "Claude CLI token limit missing: $out"
fi

test_case "dispatch resolves claude-sdk identity through the canonical registry"
source "$PROJECT_ROOT/scripts/lib/provider-registry.sh"
if grep -q 'octo_provider_canonical "$agent_executor"' "$PROJECT_ROOT/scripts/lib/dispatch.sh" \
   && [[ "$(octo_provider_canonical claude-sdk-agent)" == "claude-sdk" ]] \
   && [[ "$(octo_provider_canonical claude-sonnet)" == "claude" ]]; then
    test_pass
else
    test_fail "registry-backed dispatch did not preserve distinct claude-sdk identity"
fi

test_case "dispatch routes claude-sdk agent types to the shim"
if grep -q 'claude-sdk-exec.sh' "$PROJECT_ROOT/scripts/lib/dispatch.sh"; then
    test_pass
else
    test_fail "dispatch.sh does not reference claude-sdk-exec.sh"
fi

test_case "provider registry exposes claude-sdk for model configuration"
source "$PROJECT_ROOT/scripts/lib/provider-routing.sh"
if octo_provider_has_capability claude-sdk model-config && octo_model_config_provider_valid claude-sdk; then
    test_pass
else
    test_fail "claude-sdk must be accepted through the provider registry"
fi

test_case "provider detection reports claude-sdk when key is set"
if grep -q 'CLAUDE_SDK_API_KEY' "$PROJECT_ROOT/scripts/lib/providers.sh"; then
    test_pass
else
    test_fail "providers.sh does not detect CLAUDE_SDK_API_KEY"
fi

test_summary
