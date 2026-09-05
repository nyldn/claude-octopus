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

test_case "design review seat labels use resolved provider and model identity"
get_agent_model() {
  case "$1:$3" in
    commandcode:implementer) echo "deepseek/deepseek-v4-pro" ;;
    commandcode-research:researcher) echo "minimaxai/minimax-m3" ;;
    *) echo "unresolved" ;;
  esac
}
label=$(octo_provider_identity_label commandcode implementer)
research_label=$(octo_provider_identity_label commandcode-research researcher)
if [[ "$label" == "commandcode / deepseek/deepseek-v4-pro (executor: commandcode)" ]] && \
   [[ "$research_label" == "commandcode / minimaxai/minimax-m3 (executor: commandcode-research)" ]]; then
  test_pass
else
  test_fail "design review labels did not expose resolved runtime identity: $label | $research_label"
fi

run_design_review_dispatch_probe() {
  local mode="$1"
  local dispatch_log="$2"
  local event_log="${3:-${dispatch_log}.events}"
  env "MODE=${mode}" "PROJECT_ROOT=${PROJECT_ROOT}" "DISPATCH_LOG=${dispatch_log}" "EVENT_LOG=${event_log}" \
    "WORKSPACE_DIR=${TEST_TMP_DIR}/workspace-${mode}" "DRY_RUN=false" "OCTOPUS_CEREMONIES=true" \
  bash -c '
    set -e
    mkdir -p "$WORKSPACE_DIR"
    source "$PROJECT_ROOT/scripts/lib/quality.sh"
    if [[ "$MODE" == "role" ]]; then
      export "OCTOPUS_DESIGN_REVIEW_IMPLEMENTER_AGENT=role-implementer"
      export "OCTOPUS_DESIGN_REVIEW_RESEARCHER_AGENT=role-researcher"
      export "OCTOPUS_DESIGN_REVIEW_CODE_REVIEWER_AGENT=role-reviewer"
      export "OCTOPUS_DESIGN_REVIEW_SYNTHESIZER_AGENT=role-synthesizer"
      export "OCTOPUS_DESIGN_REVIEW_CODEX_AGENT=legacy-codex"
      export "OCTOPUS_DESIGN_REVIEW_AGY_AGENT=legacy-agy"
      export "OCTOPUS_DESIGN_REVIEW_CLAUDE_AGENT=legacy-claude"
      export "OCTOPUS_DESIGN_REVIEW_SYNTH_AGENT=legacy-synth"
    else
      unset OCTOPUS_DESIGN_REVIEW_IMPLEMENTER_AGENT OCTOPUS_DESIGN_REVIEW_RESEARCHER_AGENT OCTOPUS_DESIGN_REVIEW_CODE_REVIEWER_AGENT OCTOPUS_DESIGN_REVIEW_SYNTHESIZER_AGENT
      export "OCTOPUS_DESIGN_REVIEW_CODEX_AGENT=legacy-codex"
      if [[ "$MODE" == "gemini" ]]; then
        unset OCTOPUS_DESIGN_REVIEW_AGY_AGENT
        export "OCTOPUS_DESIGN_REVIEW_GEMINI_AGENT=legacy-gemini"
      else
        export "OCTOPUS_DESIGN_REVIEW_AGY_AGENT=legacy-agy"
        unset OCTOPUS_DESIGN_REVIEW_GEMINI_AGENT
      fi
      export "OCTOPUS_DESIGN_REVIEW_CLAUDE_AGENT=legacy-claude"
      export "OCTOPUS_DESIGN_REVIEW_SYNTH_AGENT=legacy-synth"
    fi
    : > "$DISPATCH_LOG"
    : > "$EVENT_LOG"
    # Probe fake seat aliases without inheriting repository/user allowlist policy.
    octo_provider_allowed() { return 0; }
    run_agent_sync_consultative() {
      printf "%s|%s|%s\n" "$1" "$4" "$5" >> "$DISPATCH_LOG"
      printf "%s\n" \
        "- Use a bounded implementation path with explicit dependencies and stable interfaces." \
        "- Preserve runtime identity fields and isolate failures at each review seat boundary." \
        "- Verify dispatch order, lifecycle events, fallback behavior, and synthesis output."
    }
    octo_provider_identity_label() { printf "%s\n" "$1"; }
    octo_provider_identity_from_agent_type() { printf "%s\n" "$1"; }
    get_agent_model() { printf "test-model\n"; }
    octo_event_emit() {
      local event="$1"
      shift
      printf "%s" "$event" >> "$EVENT_LOG"
      local arg
      for arg in "$@"; do printf "|%s" "$arg" >> "$EVENT_LOG"; done
      printf "\n" >> "$EVENT_LOG"
    }
    write_structured_decision() { :; }
    log() { :; }
    design_review_ceremony "test task" >/dev/null 2>&1 || true
  '
}

test_case "design review role overrides win over legacy provider-named overrides at runtime"
role_log="$TEST_TMP_DIR/role-precedence.log"
run_design_review_dispatch_probe role "$role_log"
if grep -q '^role-implementer|design-feasibility-reviewer|ceremony$' "$role_log" &&
   grep -q '^role-researcher|design-research-reviewer|ceremony$' "$role_log" &&
   grep -q '^role-reviewer|design-code-reviewer|ceremony$' "$role_log" &&
   grep -q '^role-synthesizer|design-synthesizer|ceremony$' "$role_log" &&
   ! grep -q 'legacy-' "$role_log"; then
  test_pass
else
  test_fail "semantic role override did not take precedence over legacy provider override"
fi

test_case "legacy provider-named design review overrides remain runtime fallbacks"
legacy_log="$TEST_TMP_DIR/legacy-fallback.log"
run_design_review_dispatch_probe legacy "$legacy_log"
if grep -q '^legacy-codex|design-feasibility-reviewer|ceremony$' "$legacy_log" &&
   grep -q '^legacy-agy|design-research-reviewer|ceremony$' "$legacy_log" &&
   grep -q '^legacy-claude|design-code-reviewer|ceremony$' "$legacy_log" &&
   grep -q '^legacy-synth|design-synthesizer|ceremony$' "$legacy_log"; then
  test_pass
else
  test_fail "legacy provider override did not remain a functional fallback"
fi

test_case "legacy GEMINI design review override remains secondary researcher fallback"
gemini_log="$TEST_TMP_DIR/gemini-fallback.log"
run_design_review_dispatch_probe gemini "$gemini_log"
if grep -q '^legacy-gemini|design-research-reviewer|ceremony$' "$gemini_log" &&
   ! grep -q '^legacy-agy|design-research-reviewer|ceremony$' "$gemini_log"; then
  test_pass
else
  test_fail "legacy GEMINI override did not remain the secondary researcher fallback"
fi

event_has_field() {
  local event="$1" expected="$2"
  case "|${event}|" in
    *"|${expected}|"*) return 0 ;;
    *) return 1 ;;
  esac
}

test_case "design review synthesis events carry stable executor and role identity"
synthesis_dispatch_log="$role_log"
synthesis_event_log="${role_log}.events"
start_count="$(grep -Fc 'synthesis.start|' "$synthesis_event_log" || true)"
end_count="$(grep -Fc 'synthesis.end|' "$synthesis_event_log" || true)"
start_line="$(grep -Fn 'synthesis.start|' "$synthesis_event_log" | cut -d: -f1)"
end_line="$(grep -Fn 'synthesis.end|' "$synthesis_event_log" | cut -d: -f1)"
start_event="$(grep -F 'synthesis.start|' "$synthesis_event_log")"
end_event="$(grep -F 'synthesis.end|' "$synthesis_event_log")"
if [[ "$start_count" == 1 ]] &&
   [[ "$end_count" == 1 ]] &&
   [[ "$start_line" =~ ^[0-9]+$ ]] && [[ "$end_line" =~ ^[0-9]+$ ]] &&
   [[ "$start_line" -lt "$end_line" ]] &&
   event_has_field "$start_event" "executor_alias=role-synthesizer" &&
   event_has_field "$start_event" "configured_provider=role-synthesizer" &&
   event_has_field "$start_event" "configured_model=test-model" &&
   event_has_field "$start_event" "runtime_provider=unknown" &&
   event_has_field "$start_event" "runtime_model=unknown" &&
   event_has_field "$start_event" "role=design-synthesizer" &&
   event_has_field "$end_event" "executor_alias=role-synthesizer" &&
   event_has_field "$end_event" "configured_provider=role-synthesizer" &&
   event_has_field "$end_event" "configured_model=test-model" &&
   event_has_field "$end_event" "runtime_provider=unknown" &&
   event_has_field "$end_event" "runtime_model=unknown" &&
   event_has_field "$end_event" "role=design-synthesizer"; then
  test_pass
else
  test_fail "design review synthesis events lack stable lifecycle identity fields: start=$start_event end=$end_event"
fi

test_case "design review synthesis prompt no longer uses historical provider headings"
if ! grep -q '^CODEX APPROACH:' "$PROJECT_ROOT/scripts/lib/quality.sh" && \
   ! grep -q '^GEMINI APPROACH:' "$PROJECT_ROOT/scripts/lib/quality.sh" && \
   ! grep -q '^SONNET APPROACH:' "$PROJECT_ROOT/scripts/lib/quality.sh" && \
   grep -q 'SEAT 1 - ${seat_1_label}:' "$PROJECT_ROOT/scripts/lib/quality.sh"; then
  test_pass
else
  test_fail "historical provider headings remain in the design review synthesis prompt"
fi

test_summary
