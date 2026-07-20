#!/usr/bin/env bash
# Tests for Fable 5 mode detection and dispatch guards (lib/fable5.sh, v9.51).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "fable5 mode"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Quiet logger for sourced libs
log() { :; }

source "$PROJECT_ROOT/scripts/lib/fable5.sh"

# ── Detection ──────────────────────────────────────────────────────────────

test_case "inactive with no pins (auto)"
if ! OCTOPUS_FABLE5_MODE=auto OCTOPUS_OPUS_MODEL="" OCTOPUS_CLAUDE_SDK_MODEL="" bash -c "log(){ :; }; source '$PROJECT_ROOT/scripts/lib/fable5.sh'; fable5_mode_active"; then
    test_pass
else
    test_fail "mode active without any pin"
fi

test_case "active with OCTOPUS_OPUS_MODEL pin"
if OCTOPUS_OPUS_MODEL=claude-fable-5 bash -c "log(){ :; }; source '$PROJECT_ROOT/scripts/lib/fable5.sh'; fable5_mode_active"; then
    test_pass
else
    test_fail "opus pin not detected"
fi

test_case "active with OCTOPUS_CLAUDE_SDK_MODEL pin"
if OCTOPUS_CLAUDE_SDK_MODEL=claude-fable-5 bash -c "log(){ :; }; source '$PROJECT_ROOT/scripts/lib/fable5.sh'; fable5_mode_active"; then
    test_pass
else
    test_fail "sdk pin not detected"
fi

test_case "OCTOPUS_FABLE5_MODE=off disables despite pin"
if ! OCTOPUS_FABLE5_MODE=off OCTOPUS_OPUS_MODEL=claude-fable-5 bash -c "log(){ :; }; source '$PROJECT_ROOT/scripts/lib/fable5.sh'; fable5_mode_active"; then
    test_pass
else
    test_fail "off did not disable"
fi

test_case "OCTOPUS_FABLE5_MODE=on forces active without pins"
if OCTOPUS_FABLE5_MODE=on OCTOPUS_OPUS_MODEL="" OCTOPUS_CLAUDE_SDK_MODEL="" bash -c "log(){ :; }; source '$PROJECT_ROOT/scripts/lib/fable5.sh'; fable5_mode_active"; then
    test_pass
else
    test_fail "on did not force active"
fi

# ── Effort clamp ───────────────────────────────────────────────────────────

test_case "clamps xhigh to high with opus pin"
out=$(OCTOPUS_OPUS_MODEL=claude-fable-5 bash -c "log(){ :; }; source '$PROJECT_ROOT/scripts/lib/fable5.sh'; fable5_clamp_effort xhigh" 2>/dev/null)
if [[ "$out" == "high" ]]; then
    test_pass
else
    test_fail "expected high, got '$out'"
fi

test_case "leaves high untouched with opus pin"
out=$(OCTOPUS_OPUS_MODEL=claude-fable-5 bash -c "log(){ :; }; source '$PROJECT_ROOT/scripts/lib/fable5.sh'; fable5_clamp_effort high" 2>/dev/null)
if [[ "$out" == "high" ]]; then
    test_pass
else
    test_fail "expected high, got '$out'"
fi

test_case "does not clamp without opus pin (sdk pin alone)"
out=$(OCTOPUS_OPUS_MODEL="" OCTOPUS_CLAUDE_SDK_MODEL=claude-fable-5 bash -c "log(){ :; }; source '$PROJECT_ROOT/scripts/lib/fable5.sh'; fable5_clamp_effort xhigh" 2>/dev/null)
if [[ "$out" == "xhigh" ]]; then
    test_pass
else
    test_fail "expected xhigh (sdk shim takes no effort flag), got '$out'"
fi

test_case "does not clamp when mode off"
out=$(OCTOPUS_FABLE5_MODE=off OCTOPUS_OPUS_MODEL=claude-fable-5 bash -c "log(){ :; }; source '$PROJECT_ROOT/scripts/lib/fable5.sh'; fable5_clamp_effort xhigh" 2>/dev/null)
if [[ "$out" == "xhigh" ]]; then
    test_pass
else
    test_fail "expected xhigh with mode off, got '$out'"
fi

test_case "get_effort_level override path clamps under pin"
out=$(OCTOPUS_OPUS_MODEL=claude-fable-5 OCTOPUS_EFFORT_OVERRIDE=xhigh SUPPORTS_SDK_MODEL_CAPS=true bash -c "log(){ :; }; source '$PROJECT_ROOT/scripts/lib/fable5.sh'; source '$PROJECT_ROOT/scripts/lib/agents.sh' 2>/dev/null || true; get_effort_level tangle 3" 2>/dev/null)
if [[ "$out" == "high" ]]; then
    test_pass
else
    test_fail "expected high from get_effort_level, got '$out'"
fi

# ── Security reroute ───────────────────────────────────────────────────────

test_case "reroutes security role off Fable 5"
out=$(OCTOPUS_OPUS_MODEL=claude-fable-5 bash -c "log(){ :; }; source '$PROJECT_ROOT/scripts/lib/fable5.sh'; fable5_maybe_reroute claude-fable-5 security-auditor claude-opus ink" 2>/dev/null)
if [[ "$out" == "claude-opus-4.8" ]]; then
    test_pass
else
    test_fail "expected claude-opus-4.8, got '$out'"
fi

test_case "reroutes squeeze phase off Fable 5"
out=$(OCTOPUS_OPUS_MODEL=claude-fable-5 bash -c "log(){ :; }; source '$PROJECT_ROOT/scripts/lib/fable5.sh'; fable5_maybe_reroute claude-fable-5 '' claude-opus squeeze" 2>/dev/null)
if [[ "$out" == "claude-opus-4.8" ]]; then
    test_pass
else
    test_fail "expected claude-opus-4.8, got '$out'"
fi

test_case "non-security dispatch keeps Fable 5"
out=$(OCTOPUS_OPUS_MODEL=claude-fable-5 bash -c "log(){ :; }; source '$PROJECT_ROOT/scripts/lib/fable5.sh'; fable5_maybe_reroute claude-fable-5 architect claude-opus tangle" 2>/dev/null)
if [[ "$out" == "claude-fable-5" ]]; then
    test_pass
else
    test_fail "expected claude-fable-5, got '$out'"
fi

test_case "non-Fable model passes through security dispatch untouched"
out=$(OCTOPUS_OPUS_MODEL=claude-fable-5 bash -c "log(){ :; }; source '$PROJECT_ROOT/scripts/lib/fable5.sh'; fable5_maybe_reroute claude-opus-4.8 security-auditor claude-opus ink" 2>/dev/null)
if [[ "$out" == "claude-opus-4.8" ]]; then
    test_pass
else
    test_fail "expected pass-through, got '$out'"
fi

test_case "mode off keeps Fable 5 on security dispatch"
out=$(OCTOPUS_FABLE5_MODE=off OCTOPUS_OPUS_MODEL=claude-fable-5 bash -c "log(){ :; }; source '$PROJECT_ROOT/scripts/lib/fable5.sh'; fable5_maybe_reroute claude-fable-5 security-auditor claude-opus ink" 2>/dev/null)
if [[ "$out" == "claude-fable-5" ]]; then
    test_pass
else
    test_fail "expected claude-fable-5 with mode off, got '$out'"
fi

# ── Resolver integration ───────────────────────────────────────────────────

test_case "resolve_octopus_model reroutes security role under opus pin"
out=$(cd "$TMP_DIR" && TMPDIR="$TMP_DIR" CLAUDE_CODE_SESSION="fable5-test-$$" \
    OCTOPUS_OPUS_MODEL=claude-fable-5 HOME="$TMP_DIR" bash -c "
    log(){ :; }
    source '$PROJECT_ROOT/scripts/lib/fable5.sh'
    source '$PROJECT_ROOT/scripts/lib/model-resolver.sh'
    resolve_octopus_model claude claude-opus ink security-auditor" 2>/dev/null)
if [[ "$out" == "claude-opus-4.8" ]]; then
    test_pass
else
    test_fail "expected claude-opus-4.8 from resolver, got '$out'"
fi

test_case "resolve_octopus_model keeps Fable 5 for non-security role"
out=$(cd "$TMP_DIR" && TMPDIR="$TMP_DIR" CLAUDE_CODE_SESSION="fable5-test2-$$" \
    OCTOPUS_OPUS_MODEL=claude-fable-5 HOME="$TMP_DIR" bash -c "
    log(){ :; }
    source '$PROJECT_ROOT/scripts/lib/fable5.sh'
    source '$PROJECT_ROOT/scripts/lib/model-resolver.sh'
    resolve_octopus_model claude claude-opus tangle architect" 2>/dev/null)
if [[ "$out" == "claude-fable-5" ]]; then
    test_pass
else
    test_fail "expected claude-fable-5 from resolver, got '$out'"
fi

# ── Dispatch wiring ────────────────────────────────────────────────────────

test_case "dispatch honors Fable 5 pin in claude-opus model flag"
if grep -q 'opus_model_flag="claude-fable-5"' "$PROJECT_ROOT/scripts/lib/dispatch.sh"; then
    test_pass
else
    test_fail "dispatch.sh claude-opus case does not honor the Fable 5 pin"
fi

# ── Shim refusal retry ─────────────────────────────────────────────────────

test_case "shim retries empty Fable 5 output on claude-opus-4-8"
STUB_DIR="$TMP_DIR/bin"
mkdir -p "$STUB_DIR"
CALL_LOG="$TMP_DIR/calls.log"
cat > "$STUB_DIR/claude" <<STUB
#!/usr/bin/env bash
echo "\$@" >> "$CALL_LOG"
if [[ "\$*" == *claude-fable-5* ]]; then
    exit 0   # empty output → triggers retry
fi
echo "opus fallback answer"
STUB
chmod 755 "$STUB_DIR/claude"
out=$(printf 'test prompt' | env PATH="$STUB_DIR:/usr/bin:/bin" \
    CLAUDE_SDK_API_KEY=test-key OCTOPUS_CLAUDE_SDK_MODEL=claude-fable-5 \
    bash "$PROJECT_ROOT/scripts/helpers/claude-sdk-exec.sh" 2>/dev/null)
if [[ "$out" == "opus fallback answer" ]] && grep -q -- "claude-opus-4-8" "$CALL_LOG"; then
    test_pass
else
    test_fail "retry did not reach claude-opus-4-8: out='$out' calls='$(cat "$CALL_LOG" 2>/dev/null)'"
fi

test_case "shim does not retry when Fable 5 output is non-empty"
: > "$CALL_LOG"
cat > "$STUB_DIR/claude" <<STUB
#!/usr/bin/env bash
echo "\$@" >> "$CALL_LOG"
echo "fable answer"
STUB
chmod 755 "$STUB_DIR/claude"
out=$(printf 'test prompt' | env PATH="$STUB_DIR:/usr/bin:/bin" \
    CLAUDE_SDK_API_KEY=test-key OCTOPUS_CLAUDE_SDK_MODEL=claude-fable-5 \
    bash "$PROJECT_ROOT/scripts/helpers/claude-sdk-exec.sh" 2>/dev/null)
if [[ "$out" == "fable answer" && "$(grep -c '' "$CALL_LOG")" == "1" ]]; then
    test_pass
else
    test_fail "unexpected retry: out='$out' calls='$(cat "$CALL_LOG" 2>/dev/null)'"
fi

test_case "shim skips retry with OCTOPUS_FABLE5_NO_RETRY=1"
: > "$CALL_LOG"
cat > "$STUB_DIR/claude" <<STUB
#!/usr/bin/env bash
echo "\$@" >> "$CALL_LOG"
exit 0
STUB
chmod 755 "$STUB_DIR/claude"
out=$(printf 'test prompt' | env PATH="$STUB_DIR:/usr/bin:/bin" \
    CLAUDE_SDK_API_KEY=test-key OCTOPUS_CLAUDE_SDK_MODEL=claude-fable-5 \
    OCTOPUS_FABLE5_NO_RETRY=1 \
    bash "$PROJECT_ROOT/scripts/helpers/claude-sdk-exec.sh" 2>/dev/null; true)
if [[ "$(grep -c '' "$CALL_LOG")" == "1" ]]; then
    test_pass
else
    test_fail "expected single call with retry disabled, calls='$(cat "$CALL_LOG" 2>/dev/null)'"
fi

# ── Hook ───────────────────────────────────────────────────────────────────

test_case "hook stays silent without pins"
out=$(env -u OCTOPUS_OPUS_MODEL -u OCTOPUS_CLAUDE_SDK_MODEL -u OCTOPUS_FABLE5_MODE \
    bash "$PROJECT_ROOT/hooks/fable5-inject.sh" 2>/dev/null)
if [[ -z "$out" ]]; then
    test_pass
else
    test_fail "expected empty stdout, got '$out'"
fi

test_case "hook injects context with opus pin"
out=$(OCTOPUS_OPUS_MODEL=claude-fable-5 bash "$PROJECT_ROOT/hooks/fable5-inject.sh" 2>/dev/null)
if [[ "$out" == *"additionalContext"* && "$out" == *"FABLE 5 MODE ACTIVE"* ]]; then
    test_pass
else
    test_fail "expected injection, got '$out'"
fi

test_case "hook stays silent with OCTOPUS_FABLE5_MODE=off"
out=$(OCTOPUS_FABLE5_MODE=off OCTOPUS_OPUS_MODEL=claude-fable-5 bash "$PROJECT_ROOT/hooks/fable5-inject.sh" 2>/dev/null)
if [[ -z "$out" ]]; then
    test_pass
else
    test_fail "expected empty stdout with mode off, got '$out'"
fi

test_case "hook output is valid JSON"
out=$(OCTOPUS_OPUS_MODEL=claude-fable-5 bash "$PROJECT_ROOT/hooks/fable5-inject.sh" 2>/dev/null)
if printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    test_pass
else
    test_fail "hook output is not valid JSON"
fi

test_case "hook is registered in SessionStart"
if grep -q 'fable5-inject.sh' "$PROJECT_ROOT/hooks/hooks.json"; then
    test_pass
else
    test_fail "fable5-inject.sh not registered in hooks.json"
fi

test_summary
