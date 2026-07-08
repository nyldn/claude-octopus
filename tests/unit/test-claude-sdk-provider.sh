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
if [[ "$out" == *"--model claude-opus-4-8"* \
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

test_case "dispatch maps claude-sdk agent types before the claude* glob"
if grep -q 'claude-sdk\*).*provider="claude-sdk"' "$PROJECT_ROOT/scripts/lib/dispatch.sh" \
   && awk '/claude-sdk\*\).*claude-sdk/{sdk=NR} /claude\*\).*provider="claude"/{cl=NR} END{exit !(sdk && cl && sdk<cl)}' "$PROJECT_ROOT/scripts/lib/dispatch.sh"; then
    test_pass
else
    test_fail "claude-sdk* case must exist and precede claude* in dispatch.sh"
fi

test_case "dispatch routes claude-sdk agent types to the shim"
if grep -q 'claude-sdk-exec.sh' "$PROJECT_ROOT/scripts/lib/dispatch.sh"; then
    test_pass
else
    test_fail "dispatch.sh does not reference claude-sdk-exec.sh"
fi

test_case "provider routing whitelists claude-sdk"
count=$(grep -c 'claude-sdk' "$PROJECT_ROOT/scripts/lib/provider-routing.sh" || true)
if (( count >= 2 )); then
    test_pass
else
    test_fail "expected claude-sdk in provider-routing.sh whitelists, found $count references"
fi

test_case "provider detection reports claude-sdk when key is set"
if grep -q 'CLAUDE_SDK_API_KEY' "$PROJECT_ROOT/scripts/lib/providers.sh"; then
    test_pass
else
    test_fail "providers.sh does not detect CLAUDE_SDK_API_KEY"
fi

test_summary
