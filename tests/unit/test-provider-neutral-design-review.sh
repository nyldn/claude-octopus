#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Provider-neutral design review ceremony"

TMP_HOME="$TEST_TMP_DIR/provider-neutral-design-review"
CHECKER="$TMP_HOME/check-providers.sh"
mkdir -p "$TMP_HOME/.claude-octopus/config"
cat >"$CHECKER" <<'EOF'
#!/bin/sh
cat <<'STATUS'
PROVIDER_CHECK_START
codex:available
commandcode:available
agy:missing
perplexity:missing
openrouter:missing
PROVIDER_CHECK_END
STATUS
EOF
chmod +x "$CHECKER"
cat >"$TMP_HOME/.claude-octopus/config/providers.json" <<'EOF'
{
  "version":"3.0",
  "providers": {
    "codex": {"default":"gpt-5.6-sol"},
    "commandcode": {
      "default":"deepseek/deepseek-v4-flash",
      "roles": {
        "researcher":"minimaxai/minimax-m3",
        "code-reviewer":"minimaxai/minimax-m3",
        "synthesizer":"minimaxai/minimax-m3"
      }
    },
    "claude": {"default":"claude-sonnet-5"}
  },
  "routing":{"phases":{},"roles":{}},
  "tiers":{},
  "overrides":{}
}
EOF

export HOME="$TMP_HOME"
export "OCTOPUS_PROVIDERS_CONFIG=$TMP_HOME/.claude-octopus/config/providers.json"
export OCTOPUS_PROVIDER_CHECKER="$CHECKER"
export OCTO_ALLOWED_PROVIDERS="codex commandcode claude"
export PLUGIN_DIR="$PROJECT_ROOT"
export WORKSPACE_DIR="$TMP_HOME/workspace"
mkdir -p "$WORKSPACE_DIR"
source "$PROJECT_ROOT/scripts/lib/quality.sh"

test_case "design review defaults use the provider-neutral council pool"
defaults="$(design_review_default_agents test)"
if [[ "$defaults" == $'claude-sonnet\ncodex\ncommandcode\nclaude-sonnet' ]]; then
  test_pass
else
  test_fail "expected exact admitted provider sequence, got: $(tr '\n' '|' <<< "$defaults")"
fi

test_case "design review defaults fail closed when the allowlist admits no available provider"
defaults=""
if defaults="$(OCTO_ALLOWED_PROVIDERS=agy design_review_default_agents test)"; then
  test_fail "provider discovery unexpectedly succeeded with no admitted provider: $defaults"
elif [[ -z "$defaults" ]]; then
  test_pass
else
  test_fail "failed discovery emitted an unadmitted fallback: $defaults"
fi

test_case "invalid council provider policy prevents design review defaults"
defaults=""
if defaults="$(OCTOPUS_COUNCIL_DEFAULT_PROVIDERS=codex,codex design_review_default_agents test)"; then
  test_fail "invalid duplicate provider policy unexpectedly succeeded: $defaults"
elif [[ -z "$defaults" ]]; then
  test_pass
else
  test_fail "invalid policy emitted fallback providers: $defaults"
fi

test_case "design review assigns providers independently from semantic roles"
CAPTURE="$TMP_HOME/design-review.calls"
: > "$CAPTURE"
DRY_RUN=false
OCTOPUS_CEREMONIES=true
CYAN="" GREEN="" NC="" _BOX_TOP="" _BOX_BOT=""
log() { :; }
octo_provider_identity_label() { printf '%s / fixture\n' "$1"; }
write_structured_decision() { :; }
run_agent_sync_consultative() {
  printf '%s|%s|%s\n' "$1" "$4" "$5" >> "$CAPTURE"
  printf '%s\n' '- Architecture: keep boundaries explicit and preserve existing contracts.' '- Risks: validate edge cases, dependency failures, and integration behavior.' '- Testing: run focused unit coverage plus end-to-end verification before delivery.'
}
design_review_ceremony "test" >/dev/null
roles="$(cut -d'|' -f2 "$CAPTURE" | tr '\n' '|')"
captured_providers="$(cut -d'|' -f1 "$CAPTURE" | tr '\n' '|')"
expected_calls=$'claude-sonnet|design-feasibility-reviewer|ceremony\ncodex|design-research-reviewer|ceremony\ncommandcode|design-code-reviewer|ceremony\nclaude-sonnet|design-synthesizer|ceremony'
if [[ "$(<"$CAPTURE")" == "$expected_calls" ]]; then
  test_pass
else
  test_fail "expected exact provider/role ceremony sequence; roles=$roles providers=$captured_providers calls=$(tr '\n' ';' < "$CAPTURE")"
fi

test_case "explicit design-review override cannot bypass the provider allowlist"
: > "$CAPTURE"
override_rc=0
OCTO_ALLOWED_PROVIDERS=codex \
OCTOPUS_DESIGN_REVIEW_RESEARCHER_AGENT=agy \
  design_review_ceremony "test" >/dev/null 2>&1 || override_rc=$?
if [[ "$override_rc" -ne 0 && ! -s "$CAPTURE" ]]; then
  test_pass
else
  test_fail "disallowed override was dispatched or ceremony did not fail closed: rc=$override_rc calls=$(tr '\n' ';' < "$CAPTURE")"
fi

test_case "provider-local model keeps provider identity separate from role model"
log() { :; }
export OCTOPUS_PLATFORM=Linux
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
expected_model="$(jq -r '.providers.commandcode.roles.researcher' "$TMP_HOME/.claude-octopus/config/providers.json")"
model="$(resolve_octopus_model commandcode commandcode ceremony researcher)"
if [[ "$model" == "$expected_model" ]]; then
  test_pass
else
  test_fail "expected provider-local researcher model '$expected_model', got '$model'"
fi

test_case "design review retries the same model before falling back"
CALLS="$TMP_HOME/retry.calls"
: > "$CALLS"
log() { :; }
design_review_candidate_agents() { printf '%s\n' 'commandcode:stealth/ox-alpha' 'codex:gpt-5.6-luna'; }
run_agent_sync_consultative() {
  printf '%s\n' "$1" >> "$CALLS"
  if [[ "$(wc -l < "$CALLS" | tr -d ' ')" == "1" ]]; then
    printf '%s\n' 'PROJECT_DOCUMENTATION_PATH: /tmp/repo'
  else
    printf '%s\n' '- Architecture: preserve current contracts and isolate the change behind a narrow interface.' '- Risks: validate provider failures and malformed outputs without reducing review coverage.' '- Testing: exercise retry, fallback, and successful synthesis paths with deterministic fixtures.'
  fi
}
retry_out=""; retry_agent=""
design_review_run_seat_with_recovery 'commandcode:minimaxai/minimax-m3' 'code-reviewer' 'prompt' 0   'commandcode:minimaxai/minimax-m3 codex:gpt-5.6-luna' retry_out retry_agent
if [[ "$retry_agent" == 'commandcode:minimaxai/minimax-m3' ]] && [[ "$(wc -l < "$CALLS" | tr -d ' ')" == "2" ]]; then
  test_pass
else
  test_fail "same-seat retry did not recover: agent=$retry_agent calls=$(tr '\n' '|' < "$CALLS")"
fi

test_case "design review falls back through the shared council order after retry exhaustion"
CALLS="$TMP_HOME/fallback.calls"
: > "$CALLS"
design_review_candidate_agents() {
  printf '%s\n'     'commandcode:minimaxai/minimax-m3'     'commandcode:stealth/ox-alpha'     'codex:gpt-5.6-luna'
}
run_agent_sync_consultative() {
  printf '%s\n' "$1" >> "$CALLS"
  case "$1" in
    commandcode:minimaxai/minimax-m3) printf '%s\n' 'PROJECT_DOCUMENTATION_PATH: /tmp/repo' ;;
    commandcode:stealth/ox-alpha)
      printf '%s\n' '- Architecture: use the existing orchestration path and preserve seat semantics.' '- Risks: recover invalid provider output without silently dropping an independent perspective.' '- Testing: verify model-qualified fallback order and best-effort degradation behavior.' ;;
    *) printf '%s\n' 'unexpected fallback' ;;
  esac
}
fallback_out=""; fallback_agent=""
design_review_run_seat_with_recovery 'commandcode:minimaxai/minimax-m3' 'code-reviewer' 'prompt' 0   'commandcode:minimaxai/minimax-m3 codex:gpt-5.6-luna' fallback_out fallback_agent
if [[ "$fallback_agent" == 'commandcode:stealth/ox-alpha' ]] &&    [[ "$(sed -n '3p' "$CALLS")" == 'commandcode:stealth/ox-alpha' ]]; then
  test_pass
else
  test_fail "fallback order wrong: agent=$fallback_agent calls=$(tr '\n' '|' < "$CALLS")"
fi

test_case "review order supports multiple models from one provider with Ox Alpha before Luna"
order="$(OCTOPUS_PROVIDER_CHECKER="$CHECKER" OCTOPUS_COUNCIL_DEFAULT_PROVIDERS='commandcode:stealth/ox-alpha,commandcode:minimaxai/minimax-m3,commandcode:deepseek/deepseek-v4-flash,codex:gpt-5.6-luna,codex:gpt-5.6-sol' bash "$PROJECT_ROOT/scripts/helpers/build-fleet.sh" review-order standard test 2>/dev/null)"
first_four="$(printf '%s\n' "$order" | sed -n '1,4p')"
if [[ "$first_four" == $'commandcode:stealth/ox-alpha\ncommandcode:minimaxai/minimax-m3\ncommandcode:deepseek/deepseek-v4-flash\ncodex:gpt-5.6-luna' ]]; then
  test_pass
else
  test_fail "model-qualified council order mismatch: $(tr '\n' '|' <<< "$order")"
fi

test_case "wrapped degenerate consultative output is rejected"
wrapped_bad=$'## UNVERIFIED CONSULTATIVE OUTPUT\n\nThis output came from a disposable workspace. It is advisory and non-deliverable. Claimed file changes, test counts, live probes, or completed implementation are not verified evidence and must not be reported as delivered work.\n\nPROJECT_DOCUMENTATION_PATH: /tmp/repo\n\n## END UNVERIFIED CONSULTATIVE OUTPUT'
if design_review_approach_valid "$wrapped_bad"; then
  test_fail "wrapper/disclaimer masked degenerate inner payload"
else
  test_pass
fi

test_case "large wrapped degenerate consultative output is rejected"
large_meta="$(printf 'X%.0s' {1..131072})"
wrapped_large=$'## UNVERIFIED CONSULTATIVE OUTPUT\n\nThis output came from a disposable workspace. It is advisory and non-deliverable. Claimed file changes, test counts, live probes, or completed implementation are not verified evidence and must not be reported as delivered work.\n\nPROJECT_DOCUMENTATION_PATH: /tmp/repo-'"$large_meta"$'\n\n## END UNVERIFIED CONSULTATIVE OUTPUT'
if design_review_approach_valid "$wrapped_large"; then
  test_fail "large wrapper payload bypassed inner-content validation"
else
  test_pass
fi

test_case "lowercase metadata key with dotted path is rejected"
lowercase_path='project_documentation_path: /tmp/repo/README.md with additional metadata words that should never count as substantive review content for this seat'
if design_review_approach_valid "$lowercase_path"; then
  test_fail "lowercase dotted path metadata passed validation"
else
  test_pass
fi

test_case "ordinary prose containing a colon is not treated as path metadata"
prose='Recommendation: preserve the existing orchestration contract, validate fallback behavior carefully, and add regression coverage for provider failures before merging the implementation.'
if design_review_approach_valid "$prose"; then
  test_pass
else
  test_fail "substantive prose with colon was rejected as metadata"
fi


test_case "invalid outputs are persisted as bounded diagnostic artifacts"
RESULTS_DIR="$TMP_HOME/diagnostic-results"
export RESULTS_DIR
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"
large_invalid="$(printf 'X%.0s' {1..20000})"
design_review_write_invalid_diagnostic "seat" "code-reviewer" "commandcode:stealth/ox-alpha" "1" "0" "too_few_words" "$large_invalid"
diag_file="$(find "$RESULTS_DIR/design-review-diagnostics" -type f -name 'seat-code-reviewer-*.json' | head -1)"
if [[ -n "$diag_file" ]] && \
   [[ "$(jq -r '.agent_spec' "$diag_file")" == 'commandcode:stealth/ox-alpha' ]] && \
   [[ "$(jq -r '.validation_failure' "$diag_file")" == 'too_few_words' ]] && \
   [[ "$(jq -r '.bytes' "$diag_file")" == '20000' ]] && \
   [[ "$(jq -r '.raw_truncated' "$diag_file")" == 'true' ]] && \
   [[ "$(jq -r '.raw_excerpt | length' "$diag_file")" == '16384' ]]; then
  test_pass
else
  test_fail "bounded diagnostic artifact missing or malformed: file=$diag_file"
fi

test_case "design review synthesis retries the same model before fallback"
RESULTS_DIR="$TMP_HOME/synthesis-retry-results"
export RESULTS_DIR
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"
CALLS="$TMP_HOME/synthesis-retry.calls"
: > "$CALLS"
design_review_candidate_agents() { printf '%s\n' 'commandcode:stealth/ox-alpha' 'codex:gpt-5.6-luna'; }
run_agent_sync_consultative() {
  printf '%s\n' "$1" >> "$CALLS"
  if [[ "$(wc -l < "$CALLS" | tr -d ' ')" == "1" ]]; then
    printf '%s\n' 'PROJECT_DOCUMENTATION_PATH: /tmp/repo'
  else
    printf '%s\n' 'CONFLICTS: The reviewers differ on sequencing but agree on preserving the existing orchestration boundary.' 'GAPS: Failure diagnostics and retry semantics need explicit validation before implementation continues.' 'RESOLUTION: Keep the current architecture, retry the same synthesizer once, then use the shared review pool only if the second response is still invalid.'
  fi
}
synth_out=""; synth_agent=""
design_review_run_synthesis_with_recovery 'commandcode:minimaxai/minimax-m3' 'synthesis prompt' 0 \
  'commandcode:minimaxai/minimax-m3 codex:gpt-5.6-luna' synth_out synth_agent
if [[ "$synth_agent" == 'commandcode:minimaxai/minimax-m3' ]] && \
   [[ "$(wc -l < "$CALLS" | tr -d ' ')" == '2' ]] && \
   [[ "$synth_out" == *'RESOLUTION:'* ]] && \
   find "$RESULTS_DIR/design-review-diagnostics" -type f -name 'synthesis-design-synthesizer-*.json' | grep -q .; then
  test_pass
else
  test_fail "same-model synthesis retry did not recover: agent=$synth_agent calls=$(tr '\n' '|' < "$CALLS")"
fi

test_case "design review synthesis falls back through the shared review order"
RESULTS_DIR="$TMP_HOME/synthesis-fallback-results"
export RESULTS_DIR
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"
CALLS="$TMP_HOME/synthesis-fallback.calls"
: > "$CALLS"
design_review_candidate_agents() {
  printf '%s\n' 'commandcode:minimaxai/minimax-m3' 'commandcode:stealth/ox-alpha' 'codex:gpt-5.6-luna'
}
run_agent_sync_consultative() {
  printf '%s\n' "$1" >> "$CALLS"
  case "$1" in
    commandcode:minimaxai/minimax-m3) printf '%s\n' 'PROJECT_DOCUMENTATION_PATH: /tmp/repo' ;;
    commandcode:stealth/ox-alpha)
      printf '%s\n' 'CONFLICTS: The seats disagree on implementation ordering, but not on the desired contract.' 'GAPS: The review needs explicit failure diagnostics and bounded fallback behavior.' 'RESOLUTION: Preserve the admitted review pool, record the failed synthesizer output, and continue with this alternate synthesizer for the final planning summary.' ;;
    *) printf '%s\n' 'unexpected synthesis candidate' ;;
  esac
}
synth_out=""; synth_agent=""
design_review_run_synthesis_with_recovery 'commandcode:minimaxai/minimax-m3' 'synthesis prompt' 0 \
  'commandcode:minimaxai/minimax-m3 codex:gpt-5.6-luna' synth_out synth_agent
if [[ "$synth_agent" == 'commandcode:stealth/ox-alpha' ]] && \
   [[ "$(sed -n '3p' "$CALLS")" == 'commandcode:stealth/ox-alpha' ]] && \
   [[ "$synth_out" == *'RESOLUTION:'* ]]; then
  test_pass
else
  test_fail "synthesis fallback order wrong: agent=$synth_agent calls=$(tr '\n' '|' < "$CALLS")"
fi

test_case "design review synthesis degrades explicitly after exhausting the pool"
RESULTS_DIR="$TMP_HOME/synthesis-degraded-results"
export RESULTS_DIR
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"
CALLS="$TMP_HOME/synthesis-degraded.calls"
: > "$CALLS"
design_review_candidate_agents() { printf '%s\n' 'commandcode:minimaxai/minimax-m3'; }
run_agent_sync_consultative() {
  printf '%s\n' "$1" >> "$CALLS"
  printf '%s\n' 'PROJECT_DOCUMENTATION_PATH: /tmp/repo'
}
synth_out="sentinel"; synth_agent=""
design_review_run_synthesis_with_recovery 'commandcode:minimaxai/minimax-m3' 'synthesis prompt' 0 \
  'commandcode:minimaxai/minimax-m3' synth_out synth_agent
if [[ -z "$synth_out" ]] && \
   [[ "$synth_agent" == 'commandcode:minimaxai/minimax-m3' ]] && \
   [[ "$(wc -l < "$CALLS" | tr -d ' ')" == '2' ]]; then
  test_pass
else
  test_fail "synthesis did not degrade cleanly after pool exhaustion: agent=$synth_agent output=$synth_out calls=$(tr '\n' '|' < "$CALLS")"
fi


test_case "wrapper marker quoted in substantive prose is not unwrapped"
quoted_marker='Recommendation: document the literal marker ## UNVERIFIED CONSULTATIVE OUTPUT as part of the trust-boundary protocol, but preserve this substantive review response and continue validating architecture, retries, diagnostics, and fallback behavior normally.'
if [[ "$(design_review_unwrap_consultative_output "$quoted_marker")" == "$quoted_marker" ]] && design_review_approach_valid "$quoted_marker"; then
  test_pass
else
  test_fail "marker quoted in prose was misclassified as a wrapper header"
fi

test_case "synthesis dispatch scopes supervised execution env without leaking to caller"
RESULTS_DIR="$TMP_HOME/synthesis-env-results"
export RESULTS_DIR
mkdir -p "$RESULTS_DIR"
export OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED='caller-value'
CALL_ENV="$TMP_HOME/synthesis-env.calls"
: > "$CALL_ENV"
design_review_candidate_agents() { printf '%s\n' 'commandcode:stealth/ox-alpha'; }
run_agent_sync_consultative() {
  printf '%s\n' "${OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED:-unset}" >> "$CALL_ENV"
  printf '%s\n' 'CONFLICTS: The approaches differ only in sequencing and all preserve the established runtime boundaries.' 'GAPS: Diagnostics and retry behavior need explicit regression coverage across provider failures.' 'RESOLUTION: Keep the existing architecture, validate the bounded diagnostic artifacts, and use the shared fallback pool only after retrying the same synthesizer.'
}
synth_out=""; synth_agent=""
design_review_run_synthesis_with_recovery 'commandcode:stealth/ox-alpha' 'synthesis prompt' 0 \
  'commandcode:stealth/ox-alpha' synth_out synth_agent
if [[ "$(head -1 "$CALL_ENV")" == 'design-review-ceremony' ]] && \
   [[ "$OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED" == 'caller-value' ]] && \
   [[ -n "$synth_out" ]]; then
  test_pass
else
  test_fail "synthesis env scope leaked or was not applied"
fi
unset OCTOPUS_UNBOUNDED_EXECUTION_SUPERVISED

test_case "design council roles do not inherit execution-role model routes"
cat >"$TMP_HOME/.claude-octopus/config/providers.json" <<'EOF'
{
  "version":"3.0",
  "providers": {
    "codex": {"default":"gpt-5.6-sol"},
    "commandcode": {"default":"deepseek/deepseek-v4-flash"},
    "claude": {"default":"claude-sonnet-5"}
  },
  "routing": {
    "phases": {},
    "roles": {
      "implementer": {"provider":"commandcode","model":"deepseek/deepseek-v4-flash"},
      "researcher": {"provider":"commandcode","model":"minimaxai/minimax-m3"},
      "code-reviewer": {"provider":"commandcode","model":"deepseek/deepseek-v4-pro"},
      "synthesizer": {"provider":"commandcode","model":"deepseek/deepseek-v4-pro"}
    }
  },
  "tiers":{},
  "overrides":{}
}
EOF
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
if [[ "$(resolve_octopus_model commandcode commandcode ceremony design-feasibility-reviewer)" == "deepseek/deepseek-v4-flash" ]] && \
   [[ "$(resolve_octopus_model commandcode commandcode ceremony design-research-reviewer)" == "deepseek/deepseek-v4-flash" ]] && \
   [[ "$(resolve_octopus_model commandcode commandcode ceremony design-code-reviewer)" == "deepseek/deepseek-v4-flash" ]]; then
  test_pass
else
  test_fail "namespaced design roles inherited execution-role routing"
fi

test_case "build-fleet keeps multiline prompts in one record per provider"
multiline_prompt=$'line one\r\nPROJECT_DOCUMENTATION_PATH:\r/data/example\nline four'
fleet_output="$(bash "$PROJECT_ROOT/scripts/helpers/build-fleet.sh" review standard "$multiline_prompt" 2>/dev/null)"
record_count="$(printf '%s\n' "$fleet_output" | grep -c '|')"
line_count="$(printf '%s\n' "$fleet_output" | wc -l | tr -d ' ')"
expected_labels=$'Logic Reviewer\nSecurity Reviewer\nArchitecture Reviewer\nCVE Reviewer\nDiversity Reviewer\nVerifier\nDebater\nSynthesizer'
actual_labels="$(printf '%s\n' "$fleet_output" | cut -d'|' -f2)"
expected_count="$(printf '%s\n' "$expected_labels" | wc -l | tr -d ' ')"
if [[ "$record_count" -eq "$expected_count" && "$line_count" -eq "$expected_count" ]] && \
   [[ "$actual_labels" == "$expected_labels" ]] && \
   ! printf '%s\n' "$fleet_output" | grep -q '^PROJECT_DOCUMENTATION_PATH:$' && \
   ! printf '%s' "$fleet_output" | grep -q $'\r'; then
  test_pass
else
  test_fail "review fleet records did not match the eight semantic seats: records=$record_count lines=$line_count labels=[$(tr '\n' ';' <<< "$actual_labels")]"
fi

test_summary
