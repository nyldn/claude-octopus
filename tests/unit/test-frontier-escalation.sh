#!/usr/bin/env bash
# Bounded premium-tier escalation for explicit-only frontier models.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Bounded frontier escalation"

export HOME="$TEST_TMP_DIR/home"
export OCTOPUS_PROVIDERS_CONFIG="$HOME/.claude-octopus/config/providers.json"
# The suite owns routing state. Developer shell overrides must not replace the
# temporary providers.json values used to exercise Standard and Premium modes.
unset OCTOPUS_COST_MODE OCTOPUS_CODEX_MODEL OCTOPUS_CODEX_ALLOWED_MODELS \
    OCTOPUS_CLAUDE_MODEL OCTOPUS_OPUS_MODEL CLAUDE_MODEL OCTOPUS_CLAUDE_BIN
mkdir -p "$(dirname "$OCTOPUS_PROVIDERS_CONFIG")"

write_frontier_config() {
    local mode="$1" provider="$2" model="$3"
    jq -n --arg mode "$mode" --arg provider "$provider" --arg model "$model" '
      {
        version: "3.0",
        cost_mode: $mode,
        routing: {frontier: {($provider): {model: $model}}}
      }
    ' >"$OCTOPUS_PROVIDERS_CONFIG"
}

fake_bin="$TEST_TMP_DIR/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/codex" <<'EOF'
#!/usr/bin/env bash
printf 'codex-cli %s\n' "${OCTOPUS_TEST_CODEX_VERSION:-0.153.1}"
EOF
cat >"$fake_bin/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s (Claude Code)\n' "${OCTOPUS_TEST_CLAUDE_VERSION:-2.1.255}"
EOF
chmod +x "$fake_bin/codex" "$fake_bin/claude"
export PATH="$fake_bin:$PATH"

source "$PROJECT_ROOT/scripts/lib/provider-registry.sh"
source "$PROJECT_ROOT/scripts/lib/models.sh"
source "$PROJECT_ROOT/scripts/lib/provider-versions.sh"
source "$PROJECT_ROOT/scripts/lib/frontier-escalation.sh"

run_contract_root="$TEST_TMP_DIR/run-contract"
octo_run_contract_dir() {
    printf '%s\n' "$run_contract_root"
}

test_case "premium tier stores frontier models as bounded escalation policy"
config_home="$TEST_TMP_DIR/config-home"
mkdir -p "$config_home"
if HOME="$config_home" bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" \
      tier premium codex gpt-6-astra >/dev/null 2>&1 &&
   HOME="$config_home" bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" \
      tier premium claude claude-fable-5-1 >/dev/null 2>&1; then
    config_file="$config_home/.claude-octopus/config/providers.json"
    if jq -e '
        .routing.frontier.codex.model == "gpt-6-astra" and
        .routing.frontier.claude.model == "claude-fable-5-1" and
        .tiers.premium.codex == "default" and
        .tiers.premium.claude == "opus"
      ' "$config_file" >/dev/null; then
        test_pass
    else
        test_fail "premium frontier policy replaced literal tier routes"
    fi
else
    test_fail "premium tier rejected a bounded frontier target"
fi

test_case "legacy config migration preserves a newly saved frontier policy"
legacy_home="$TEST_TMP_DIR/legacy-home"
mkdir -p "$legacy_home/.claude-octopus/config"
jq -n '{version:"2.0", providers:{codex:{default:"gpt-5.6-sol"}}, routing:{}, tiers:{premium:{codex:"default"}}, overrides:{}}' \
    >"$legacy_home/.claude-octopus/config/providers.json"
if HOME="$legacy_home" bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" \
      tier premium codex gpt-6-astra >/dev/null 2>&1 &&
   HOME="$legacy_home" bash -c 'source "$1/scripts/lib/provider-routing.sh"; log() { :; }; migrate_provider_config' _ "$PROJECT_ROOT" >/dev/null 2>&1 &&
   jq -e '.version == "3.0" and .routing.frontier.codex.model == "gpt-6-astra"' \
      "$legacy_home/.claude-octopus/config/providers.json" >/dev/null; then
    test_pass
else
    test_fail "legacy migration discarded the saved frontier policy"
fi

test_case "frontier mismatch guidance names the target provider"
mismatch_output="$(HOME="$config_home" bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" \
    tier premium claude gpt-6-astra 2>&1 || true)"
if [[ "$mismatch_output" == *"tier premium codex gpt-6-astra"* ]]; then
    test_pass
else
    test_fail "mismatch guidance suggested the wrong provider: $mismatch_output"
fi

test_case "non-premium and literal routing surfaces still reject frontier models"
if HOME="$config_home" bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" \
      tier standard codex gpt-6-astra >/dev/null 2>&1 ||
   HOME="$config_home" bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" \
      tier budget claude claude-fable-5-1 >/dev/null 2>&1 ||
   HOME="$config_home" bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" \
      route review codex:gpt-6-astra >/dev/null 2>&1 ||
   HOME="$config_home" bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" \
      route-role architect codex:gpt-6-astra >/dev/null 2>&1; then
    test_fail "a literal automatic route admitted an explicit-only frontier model"
else
    test_pass
fi

test_case "model-config lists the bounded frontier policy and pin warning"
list_output="$(HOME="$config_home" OCTOPUS_CODEX_MODEL=gpt-6-astra \
    bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" list 2>/dev/null)"
if [[ "$list_output" == *"Bounded Frontier Escalation"* &&
      "$list_output" == *"codex: gpt-6-astra (1 dispatch/run"* &&
      "$list_output" == *"provider-wide pin disables bounded escalation"* ]]; then
    test_pass
else
    test_fail "model-config did not disclose frontier policy and pin interaction: $list_output"
fi

test_case "provider reset removes its bounded frontier policy"
if HOME="$config_home" bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" \
      reset codex >/dev/null 2>&1 &&
   ! jq -e '.routing.frontier.codex' "$config_file" >/dev/null; then
    test_pass
else
    test_fail "provider reset left the bounded Codex frontier policy active"
fi

test_case "Astra escalates one premium judgment dispatch and then falls back"
write_frontier_config premium codex gpt-6-astra
first_model="$(OCTOPUS_RUN_ID=astra-once OCTOPUS_MAX_COST_USD=5 OCTOPUS_TEST_CODEX_VERSION=0.153.1 \
    octo_frontier_maybe_escalate codex gpt-5.6-sol architect codex define 4000)"
second_model="$(OCTOPUS_RUN_ID=astra-once OCTOPUS_MAX_COST_USD=5 OCTOPUS_TEST_CODEX_VERSION=0.153.1 \
    octo_frontier_maybe_escalate codex gpt-5.6-sol strategist codex define 4000)"
if [[ "$first_model" == gpt-6-astra && "$second_model" == gpt-5.6-sol ]]; then
    test_pass
else
    test_fail "bounded Astra result: first=$first_model second=$second_model"
fi

test_case "Astra requires premium mode, a cost ceiling, and a supported CLI"
write_frontier_config standard codex gpt-6-astra
standard_model="$(OCTOPUS_RUN_ID=astra-standard OCTOPUS_MAX_COST_USD=5 \
    octo_frontier_maybe_escalate codex gpt-5.6-sol architect codex define 4000)"
write_frontier_config premium codex gpt-6-astra
uncapped_model="$(OCTOPUS_RUN_ID=astra-uncapped \
    octo_frontier_maybe_escalate codex gpt-5.6-sol architect codex define 4000)"
old_cli_model="$(OCTOPUS_RUN_ID=astra-old OCTOPUS_MAX_COST_USD=5 OCTOPUS_TEST_CODEX_VERSION=0.153.0 \
    octo_frontier_maybe_escalate codex gpt-5.6-sol architect codex define 4000)"
restricted_model="$(OCTOPUS_RUN_ID=astra-restricted OCTOPUS_MAX_COST_USD=5 \
    OCTOPUS_CODEX_ALLOWED_MODELS=gpt-5.6-sol \
    octo_frontier_maybe_escalate codex gpt-5.6-sol architect codex define 4000)"
if [[ "$standard_model" == gpt-5.6-sol && "$uncapped_model" == gpt-5.6-sol &&
      "$old_cli_model" == gpt-5.6-sol && "$restricted_model" == gpt-5.6-sol ]]; then
    test_pass
else
    test_fail "Astra admission leaked: standard=$standard_model uncapped=$uncapped_model old=$old_cli_model restricted=$restricted_model"
fi

test_case "Astra projected list-price usage must fit the configured ceiling"
too_small_model="$(OCTOPUS_RUN_ID=astra-too-small OCTOPUS_MAX_COST_USD=0.01 \
    octo_frontier_maybe_escalate codex gpt-5.6-sol architect codex define 4000)"
large_enough_model="$(OCTOPUS_RUN_ID=astra-large-enough OCTOPUS_MAX_COST_USD=0.12 \
    octo_frontier_maybe_escalate codex gpt-5.6-sol architect codex define 4000)"
if [[ "$too_small_model" == gpt-5.6-sol && "$large_enough_model" == gpt-6-astra ]]; then
    test_pass
else
    test_fail "Astra ceiling was not enforced: too-small=$too_small_model large-enough=$large_enough_model"
fi

test_case "Astra pricing rules reject malformed request multipliers"
invalid_pricing_file="$TEST_TMP_DIR/invalid-pricing.tsv"
printf '%s\n' \
    $'model\tgpt-6-astra\t10\t50' \
    $'request-rule\tgpt-6-astra\t1000\t-1\t1' >"$invalid_pricing_file"
if OCTOPUS_MODEL_PRICING_FILE="$invalid_pricing_file" \
    octo_frontier_projected_cost gpt-6-astra 4000 >/dev/null 2>&1; then
    test_fail "malformed Astra request multipliers were accepted"
else
    test_pass
fi

test_case "Astra requires a measured non-empty prompt before claiming a seat"
unmeasured_model="$(OCTOPUS_RUN_ID=astra-unmeasured OCTOPUS_MAX_COST_USD=5 \
    octo_frontier_maybe_escalate codex gpt-5.6-sol architect codex define 0)"
if [[ "$unmeasured_model" == gpt-5.6-sol ]]; then
    test_pass
else
    test_fail "Astra claimed an unmeasured dispatch: $unmeasured_model"
fi

test_case "Astra excludes security phases even for an eligible role"
security_phase_model="$(OCTOPUS_RUN_ID=astra-security-phase OCTOPUS_MAX_COST_USD=5 \
    octo_frontier_maybe_escalate codex gpt-5.6-sol architect codex security 4000)"
if [[ "$security_phase_model" == gpt-5.6-sol ]]; then
    test_pass
else
    test_fail "Astra entered a security phase: $security_phase_model"
fi

test_case "Astra escalation excludes review, security, implementation, and exact seats"
review_model="$(OCTOPUS_RUN_ID=astra-review OCTOPUS_MAX_COST_USD=5 \
    octo_frontier_maybe_escalate codex gpt-5.6-sol code-reviewer codex review 4000)"
security_model="$(OCTOPUS_RUN_ID=astra-security OCTOPUS_MAX_COST_USD=5 \
    octo_frontier_maybe_escalate codex gpt-5.6-sol security-reviewer codex security 4000)"
implement_model="$(OCTOPUS_RUN_ID=astra-implement OCTOPUS_MAX_COST_USD=5 \
    octo_frontier_maybe_escalate codex gpt-5.6-sol implementer-heavy codex develop 4000)"
exact_model="$(OCTOPUS_RUN_ID=astra-exact OCTOPUS_MAX_COST_USD=5 \
    octo_frontier_maybe_escalate codex gpt-5.6-sol architect codex:gpt-5.6-sol define 4000)"
if [[ "$review_model" == gpt-5.6-sol && "$security_model" == gpt-5.6-sol &&
      "$implement_model" == gpt-5.6-sol && "$exact_model" == gpt-5.6-sol ]]; then
    test_pass
else
    test_fail "Astra escaped the judgment-only boundary"
fi

test_case "premium Claude policy activates the same bounded Fable path"
write_frontier_config premium claude claude-fable-5-1
source "$PROJECT_ROOT/scripts/lib/fable5.sh"
fable_model="$(OCTOPUS_RUN_ID=fable-premium \
    fable5_maybe_escalate claude-opus-5 architect claude-opus define)"
fable_off_model="$(OCTOPUS_RUN_ID=fable-premium-off OCTOPUS_FABLE5_ROUTING=off \
    fable5_maybe_escalate claude-opus-5 architect claude-opus define)"
if [[ "$fable_model" == claude-fable-5-1 && "$fable_off_model" == claude-opus-5 ]]; then
    test_pass
else
    test_fail "premium Claude policy or explicit stand-down failed: selected=$fable_model off=$fable_off_model"
fi

test_case "Astra and Fable share one frontier claim per run"
jq -n '
    {version:"3.0", cost_mode:"premium",
     routing:{frontier:{codex:{model:"gpt-6-astra"}, claude:{model:"claude-fable-5-1"}}}}
' >"$OCTOPUS_PROVIDERS_CONFIG"
shared_astra_model="$(OCTOPUS_RUN_ID=frontier-shared-claim OCTOPUS_MAX_COST_USD=5 \
    OCTOPUS_TEST_CODEX_VERSION=0.153.1 \
    octo_frontier_maybe_escalate codex gpt-5.6-sol architect codex define 4000)"
shared_fable_model="$(OCTOPUS_RUN_ID=frontier-shared-claim \
    fable5_maybe_escalate claude-opus-5 architect claude-opus define)"
if [[ "$shared_astra_model" == gpt-6-astra && "$shared_fable_model" == claude-opus-5 ]]; then
    test_pass
else
    test_fail "frontier providers did not share one run claim: Astra=$shared_astra_model Fable=$shared_fable_model"
fi

test_case "premium Fable escalation requires a supported Claude CLI"
fable_old_model="$(OCTOPUS_RUN_ID=fable-old OCTOPUS_TEST_CLAUDE_VERSION=2.1.254 \
    fable5_maybe_escalate claude-opus-5 architect claude-opus define)"
if [[ "$fable_old_model" == claude-opus-5 ]]; then
    test_pass
else
    test_fail "old Claude CLI admitted bounded Fable escalation: $fable_old_model"
fi

test_case "premium Fable version check uses the configured Claude launcher"
cat >"$fake_bin/clarp" <<'EOF'
#!/usr/bin/env bash
printf '%s (Claude Code)\n' "${OCTOPUS_TEST_CLARP_VERSION:-2.1.255}"
EOF
chmod +x "$fake_bin/clarp"
configured_fable_model="$(OCTOPUS_RUN_ID=fable-configured-launcher \
    OCTOPUS_CLAUDE_BIN='clarp --strict-mcp-config' \
    fable5_maybe_escalate claude-opus-5 architect claude-opus define)"
if [[ "$configured_fable_model" == claude-fable-5-1 ]]; then
    test_pass
else
    test_fail "configured Claude launcher was not used for Fable version detection: $configured_fable_model"
fi

test_case "model-config refuses an Astra tier when the Codex CLI is too old"
unavailable_home="$TEST_TMP_DIR/unavailable-codex-home"
mkdir -p "$unavailable_home"
if ! HOME="$unavailable_home" OCTOPUS_TEST_CODEX_VERSION=0.153.0 \
      bash "$PROJECT_ROOT/scripts/helpers/octo-model-config.sh" \
      tier premium codex gpt-6-astra >/dev/null 2>&1 &&
   ! jq -e '.routing.frontier.codex' \
      "$unavailable_home/.claude-octopus/config/providers.json" >/dev/null 2>&1; then
    test_pass
else
    test_fail "model-config saved an Astra policy below the Codex CLI floor"
fi

test_case "Codex command construction applies the bounded escalation decision"
write_frontier_config premium codex gpt-6-astra
PLUGIN_DIR="$PROJECT_ROOT"
log() { :; }
source "$PROJECT_ROOT/scripts/lib/dispatch.sh"
get_agent_model() { printf '%s\n' gpt-5.6-sol; }
octopus_resolve_reasoning_level() { printf '%s\n' high; }
octopus_resolve_reasoning_policy() { printf '%s\n' default; }
octopus_reasoning_cli_fragment() { :; }
first_command="$(OCTOPUS_RUN_ID=astra-dispatch OCTOPUS_MAX_COST_USD=5 \
    get_agent_command codex define architect 100)"
second_command="$(OCTOPUS_RUN_ID=astra-dispatch OCTOPUS_MAX_COST_USD=5 \
    get_agent_command codex define strategist 100)"
if [[ "$first_command" == *"--model gpt-6-astra"* &&
      "$second_command" == *"--model gpt-5.6-sol"* ]]; then
    test_pass
else
    test_fail "dispatch did not apply one bounded Astra seat: first=$first_command second=$second_command"
fi

test_summary
