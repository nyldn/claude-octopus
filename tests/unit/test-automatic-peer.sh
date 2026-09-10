#!/usr/bin/env bash
# Automatic Premium peer policy and receipt contract.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Automatic Premium peer check"

export HOME="$TEST_TMP_DIR/home"
export OCTOPUS_PROVIDERS_CONFIG="$TEST_TMP_DIR/providers.json"
mkdir -p "$HOME"

source "$PROJECT_ROOT/scripts/lib/provider-registry.sh"
source "$PROJECT_ROOT/scripts/lib/models.sh"
source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"
source "$PROJECT_ROOT/scripts/lib/automatic-peer.sh"
source "$PROJECT_ROOT/scripts/lib/heartbeat.sh"

printf '%s\n' '{"cost_mode":"premium"}' > "$OCTOPUS_PROVIDERS_CONFIG"
unset FORCE_TIER OCTOPUS_COST_MODE OCTOPUS_PREMIUM_PEER_CHECK OCTOPUS_AUTO_PEER_ACTIVE OCTOPUS_AUTO_PEER_CHECKED

test_case "Premium config enables the automatic policy without a flag"
if octo_auto_peer_should_run coding standard; then
    test_pass
else
    test_fail "Premium config did not enable the automatic peer policy"
fi

test_case "Budget and Standard do not add an automatic peer"
if for mode in budget standard; do
       OCTOPUS_COST_MODE="$mode" bash -c 'source "$1"; ! octo_auto_peer_should_run coding standard' _ "$PROJECT_ROOT/scripts/lib/automatic-peer.sh"
   done; then
    test_pass
else
    test_fail "non-Premium cost mode enabled the automatic peer policy"
fi
unset OCTOPUS_COST_MODE

test_case "an explicit --premium tier enables Premium when no cost mode is configured"
rm -f "$OCTOPUS_PROVIDERS_CONFIG"
FORCE_TIER=premium
if octo_auto_peer_should_run coding standard; then
    test_pass
else
    test_fail "explicit premium tier did not enable the policy"
fi
unset FORCE_TIER
printf '%s\n' '{"cost_mode":"premium"}' > "$OCTOPUS_PROVIDERS_CONFIG"

test_case "a persisted Budget mode wins over an explicit Premium tier"
printf '%s\n' '{"cost_mode":"budget"}' > "$OCTOPUS_PROVIDERS_CONFIG"
FORCE_TIER=premium
if ! octo_auto_peer_should_run coding standard; then
    test_pass
else
    test_fail "explicit Premium tier overrode the persisted Budget mode"
fi
unset FORCE_TIER
printf '%s\n' '{"cost_mode":"premium"}' > "$OCTOPUS_PROVIDERS_CONFIG"

test_case "an explicit quick tier suppresses the Premium peer"
FORCE_TIER=trivial
if ! octo_auto_peer_should_run coding standard; then
    test_pass
else
    test_fail "explicit quick tier did not suppress the Premium peer"
fi
unset FORCE_TIER

test_case "the automatic addition has one explicit opt-out"
OCTOPUS_PREMIUM_PEER_CHECK=off
if ! octo_auto_peer_should_run coding standard; then
    test_pass
else
    test_fail "automatic peer opt-out was ignored"
fi
unset OCTOPUS_PREMIUM_PEER_CHECK

test_case "the persisted preference disables only the automatic addition"
mkdir -p "$HOME/.claude-octopus"
printf '%s\n' '{"premium_peer_check":"off"}' > "$HOME/.claude-octopus/preferences.json"
if ! octo_auto_peer_should_run coding standard; then
    test_pass
else
    test_fail "persisted Premium peer preference was ignored"
fi
rm -f "$HOME/.claude-octopus/preferences.json"

test_case "quick and specialized routes skip the automatic peer"
skipped=true
for pair in "coding direct" "coding lightweight" "research standard" "diamond-develop standard" "crossfire-squeeze full" "image standard"; do
    set -- $pair
    if octo_auto_peer_should_run "$1" "$2"; then
        skipped=false
    fi
done
if [[ "$skipped" == true ]]; then
    test_pass
else
    test_fail "a quick or specialized route was admitted"
fi

test_case "the automatic check records one independent peer result"
export RESULTS_DIR="$TEST_TMP_DIR/results"
export OCTOPUS_COST_MODE=premium
export OCTOPUS_AUTO_PEER_RUN_ID=automatic-peer-test
export OCTOPUS_AUTO_PEER_CHECKED=false
peer_calls_file="$TEST_TMP_DIR/peer-calls"
rm -f "$peer_calls_file"
octo_agent_spec_provider() {
    case "$1" in
        codex*) printf '%s\n' codex ;;
        claude*) printf '%s\n' claude ;;
        *) printf '%s\n' unknown ;;
    esac
}
get_agent_model() {
    case "$1" in
        codex*) printf '%s\n' gpt-5.6-sol ;;
        claude*) printf '%s\n' claude-opus-5 ;;
        *) return 1 ;;
    esac
}
is_agent_available_v2() { return 0; }
run_agent_sync() {
    printf '%s\n' call >> "$peer_calls_file"
    printf '%s\n' 'peer finding: inspect the changed error path'
}
octo_auto_peer_run coding standard "implement the error-path change" codex-standard "owner completed the implementation"
receipt="$RESULTS_DIR/automatic-peer-test.automatic-peer.json"
if [[ "$(wc -l < "$peer_calls_file" | tr -d ' ')" -eq 1 ]] &&
   jq -e '.status == "reviewed" and .attempts == 1 and .independent == true and .owner.output_sha256 != "" and .peer.output_sha256 != ""' "$receipt" >/dev/null; then
    test_pass
else
    test_fail "expected one independent peer attempt and a hashed receipt"
fi

test_case "repeated calls in one workflow are idempotent"
octo_auto_peer_run coding standard "implement the error-path change" codex-standard "owner completed the implementation"
if [[ "$(wc -l < "$peer_calls_file" | tr -d ' ')" -eq 1 ]]; then
    test_pass
else
    test_fail "automatic peer ran more than once for one workflow"
fi

test_case "same-family peer output is not claimed as independent"
rm -f "$RESULTS_DIR/.same-family.automatic-peer.claim" "$RESULTS_DIR/same-family.automatic-peer.json"
export OCTOPUS_AUTO_PEER_RUN_ID=same-family
export OCTOPUS_AUTO_PEER_CHECKED=false
get_agent_model() {
    case "$1" in
        codex*) printf '%s\n' gpt-5.6-sol ;;
        claude*) printf '%s\n' gpt-5.6-sol ;;
        *) return 1 ;;
    esac
}
octo_auto_peer_run coding standard "same-family test" codex-standard "owner result"
if jq -e '.status == "skipped" and .independent == false and .attempts == 0' "$RESULTS_DIR/same-family.automatic-peer.json" >/dev/null; then
    test_pass
else
    test_fail "same-family result was dispatched or marked independent"
fi

test_case "an unknown concrete model family is not inferred from its executor"
rm -f "$RESULTS_DIR/.unknown-family.automatic-peer.claim" "$RESULTS_DIR/unknown-family.automatic-peer.json"
export OCTOPUS_AUTO_PEER_RUN_ID=unknown-family
export OCTOPUS_AUTO_PEER_CHECKED=false
get_agent_model() {
    case "$1" in
        codex*) printf '%s\n' tenant-deployment ;;
        claude*) printf '%s\n' tenant-peer ;;
        *) return 1 ;;
    esac
}
is_agent_available_v2() { return 0; }
octo_auto_peer_run coding standard "unknown family test" codex-standard "owner result"
if jq -e '.status == "skipped" and .independent == false and .attempts == 0' "$RESULTS_DIR/unknown-family.automatic-peer.json" >/dev/null; then
    test_pass
else
    test_fail "unknown model family was inferred from an executor alias"
fi

test_case "an unavailable peer is never counted as independent"
rm -f "$RESULTS_DIR/.unavailable.automatic-peer.claim" "$RESULTS_DIR/unavailable.automatic-peer.json"
export OCTOPUS_AUTO_PEER_RUN_ID=unavailable
export OCTOPUS_AUTO_PEER_CHECKED=false
get_agent_model() {
    case "$1" in
        codex*) printf '%s\n' gpt-5.6-sol ;;
        claude*) printf '%s\n' claude-opus-5 ;;
        *) return 1 ;;
    esac
}
is_agent_available_v2() { return 1; }
octo_auto_peer_run coding standard "unavailable test" codex-standard "owner result"
if jq -e '.status == "skipped" and .independent == false and .attempts == 0' "$RESULTS_DIR/unavailable.automatic-peer.json" >/dev/null; then
    test_pass
else
    test_fail "unavailable peer was counted as independent"
fi

test_case "nested automatic peer calls are suppressed"
export OCTOPUS_AUTO_PEER_ACTIVE=true
if ! octo_auto_peer_should_run coding standard; then
    test_pass
else
    test_fail "nested automatic peer call was admitted"
fi

test_case "the native /octo:auto command uses the shared automatic runtime"
if rg -q 'scripts/orchestrate\.sh" auto' "$PROJECT_ROOT/commands/auto.md"; then
    test_pass
else
    test_fail "native /octo:auto does not invoke orchestrate.sh auto"
fi

source "$PROJECT_ROOT/scripts/lib/routing.sh"
test_case "explicit parallel intent remains owned by the parallel workflow"
if [[ "$(classify_task 'decompose this into parallel work packages')" == parallel ]]; then
    test_pass
else
    test_fail "parallel intent fell through to a single-owner route"
fi

test_case "explicit native intents do not fall into the automatic peer path"
native_routing_ok=true
for pair in \
    "run the complete lifecycle for this feature:native-embrace" \
    "write unit tests for the payment adapter:native-tdd" \
    "add unit tests for the payment adapter:native-tdd" \
    "create a pitch deck for the board:native-deck" \
    "create a deck for the board:native-deck" \
    "use all providers for this assessment:native-multi" \
    "debug the authentication crash:native-debug" \
    "fix the payment bug:native-debug" \
    "prototype a queue adapter to measure throughput:native-plan" \
    "write tests for both payment adapters in parallel:parallel"; do
    native_prompt="${pair%%:*}"
    native_type="${pair##*:}"
    [[ "$(classify_task "$native_prompt")" == "$native_type" ]] || native_routing_ok=false
done
if [[ "$native_routing_ok" == true ]] &&
   ! octo_auto_peer_should_run general standard "run the complete lifecycle for this feature" &&
   ! octo_auto_peer_should_run coding standard "write unit tests for the payment adapter" &&
   ! octo_auto_peer_should_run coding standard "add unit tests for the payment adapter" &&
   ! octo_auto_peer_should_run general standard "create a pitch deck for the board" &&
   ! octo_auto_peer_should_run general standard "create a deck for the board" &&
   ! octo_auto_peer_should_run coding standard "fix the payment bug" &&
   ! octo_auto_peer_should_run coding standard "write tests in parallel" &&
   ! octo_auto_peer_should_run design standard "prototype a queue adapter to measure throughput"; then
    test_pass
else
    test_fail "an explicit native intent was classified or peer-admitted as generic work"
fi

test_case "the nested-peer guard survives isolated provider environments"
guard_result=$(OCTOPUS_AUTO_PEER_ACTIVE=true OCTOPUS_AUTO_PEER_RUN_ID=guard-test \
    bash -c '
        source "$1/scripts/lib/provider-routing.sh"
        build_provider_env codex
        "${PROVIDER_ENV_ARRAY[@]}" bash -c '\''printf "%s %s\\n" "${OCTOPUS_AUTO_PEER_ACTIVE:-missing}" "${OCTOPUS_AUTO_PEER_RUN_ID:-missing}"'\''
    ' _ "$PROJECT_ROOT")
if [[ "$guard_result" == "true guard-test" ]]; then
    test_pass
else
    test_fail "isolated provider environment dropped the nested-peer guard (got: $guard_result)"
fi

test_case "dispatch marker failure prevents an unaccounted provider launch"
marker_target="$TEST_TMP_DIR/missing-marker-dir/dispatch"
marker_called="$TEST_TMP_DIR/marker-called"
rm -rf "${marker_target%/*}" "$marker_called"
marker_rc=0
if OCTOPUS_AUTO_PEER_DISPATCH_MARKER="$marker_target" \
    run_with_timeout 1 bash -c 'printf launched > "$1"' _ "$marker_called" >/dev/null 2>&1; then
    marker_rc=0
else
    marker_rc=$?
fi
if [[ "$marker_rc" -eq 74 && ! -e "$marker_called" ]]; then
    test_pass
else
    test_fail "provider command remained reachable after marker persistence failed"
fi

test_case "/octo:auto runs the owner and one peer without --peer"
unset OCTOPUS_AUTO_PEER_ACTIVE
export OCTOPUS_AUTO_PEER_CHECKED=false
export OCTOPUS_AUTO_PEER_RUN_ID=auto-route-test
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"
rm -f "$peer_calls_file"
source "$PROJECT_ROOT/scripts/lib/auto-route.sh"
MAGENTA='' BLUE='' YELLOW='' CYAN='' GREEN='' RED='' NC=''
FORCE_TIER='' FORCE_BRANCH='' VERBOSE=false DRY_RUN=false KNOWLEDGE_WORK_MODE=false CI=''
classify_task() { printf '%s\n' coding; }
estimate_complexity() { printf '%s\n' 2; }
get_tier_name() { printf '%s\n' standard; }
evaluate_branch_condition() { printf '%s\n' standard; }
get_branch_display() { printf '%s\n' standard; }
detect_context() { printf '%s\n' code:local; }
get_context_display() { printf '%s\n' local; }
get_context_info() { :; }
classify_cynefin() { printf '%s\n' complicated; }
detect_response_mode() { printf '%s\n' standard; }
load_user_config() { :; }
get_tiered_agent() { printf '%s\n' codex-standard; }
get_agent_command() { printf '%s\n' 'codex --model gpt-5.6-sol'; }
log() { :; }
record_task_metric() { :; }
octo_agent_spec_provider() {
    case "$1" in
        codex*) printf '%s\n' codex ;;
        claude*) printf '%s\n' claude ;;
        *) printf '%s\n' unknown ;;
    esac
}
get_agent_model() {
    case "$1" in
        codex*) printf '%s\n' gpt-5.6-sol ;;
        claude*) printf '%s\n' claude-opus-5 ;;
        *) return 1 ;;
    esac
}
is_agent_available_v2() { return 0; }
octo_provider_allowed() { return 0; }
run_agent_sync() {
    printf '%s\n' "$5" >> "$peer_calls_file"
    if [[ "$5" == auto-route ]]; then
        # The owner is executed with the nested-peer guard set. This nested
        # attempt must not claim the root workflow's peer slot.
        OCTOPUS_AUTO_PEER_RUN_ID=auto-route-test \
            octo_auto_peer_run coding standard "nested owner route" codex-standard "nested owner result"
        printf '%s\n' 'owner result'
    else
        printf '%s\n' 'peer result'
    fi
}
spawn_agent() {
    [[ "${DRY_RUN:-false}" == true ]] || printf '%s\n' 'unexpected async dispatch' >> "$peer_calls_file"
}

test_case "parallel intent is not short-circuited by direct response mode"
parallel_route_file="$TEST_TMP_DIR/parallel-route"
rm -f "$parallel_route_file"
_BOX_TOP='' _BOX_BOT=''
classify_task() { printf '%s\n' parallel; }
detect_response_mode() { printf '%s\n' direct; }
parallel_execute() { printf '%s\n' dispatched > "$parallel_route_file"; }
detect_trivial_task() { printf '%s\n' trivial; }
handle_trivial_task() { printf '%s\n' swallowed > "$parallel_route_file"; }
export OCTOPUS_COST_TIER=balanced
if auto_route "decompose this into parallel work packages" >/dev/null &&
   [[ "$(<"$parallel_route_file")" == dispatched ]]; then
    test_pass
else
    test_fail "parallel intent was swallowed by the direct response shortcut"
fi
unset OCTOPUS_COST_TIER
unset -f detect_trivial_task handle_trivial_task

classify_task() { printf '%s\n' coding; }
detect_response_mode() { printf '%s\n' standard; }
if auto_route "implement the error-path change"; then
    route_receipt="$RESULTS_DIR/auto-route-test.automatic-peer.json"
    if [[ "$(wc -l < "$peer_calls_file" | tr -d ' ')" -eq 2 ]] &&
       jq -e '.status == "reviewed" and .independent == true and .owner.model == "gpt-5.6-sol"' "$route_receipt" >/dev/null; then
        test_pass
    else
        test_fail "auto route did not run exactly one owner and one independent peer"
    fi
else
    test_fail "auto route returned a failure"
fi

test_case "dry-run Premium auto routing launches no owner or peer"
export DRY_RUN=true
export OCTOPUS_AUTO_PEER_CHECKED=false
rm -f "$peer_calls_file"
auto_route "implement the error-path change"
if [[ ! -s "$peer_calls_file" ]]; then
    test_pass
else
    test_fail "dry-run auto routing launched a provider"
fi
unset DRY_RUN

test_case "large owner results are bounded without a pipefail abort"
export OCTOPUS_AUTO_PEER_RUN_ID=large-owner
export OCTOPUS_AUTO_PEER_CHECKED=false
rm -f "$RESULTS_DIR/.large-owner.automatic-peer.claim" "$RESULTS_DIR/large-owner.automatic-peer.json"
large_owner=""
for ((i=0; i<13000; i++)); do large_owner+="x"; done
octo_auto_peer_run coding standard "large owner test" codex-standard "$large_owner"
if jq -e '.status == "reviewed" and .attempts == 1' "$RESULTS_DIR/large-owner.automatic-peer.json" >/dev/null; then
    test_pass
else
    test_fail "large owner result prevented a bounded peer review"
fi

test_case "a pre-dispatch failure is not counted as a provider attempt"
export OCTOPUS_AUTO_PEER_RUN_ID=pre-dispatch-failure
export OCTOPUS_AUTO_PEER_CHECKED=false
rm -f "$RESULTS_DIR/.pre-dispatch-failure.automatic-peer.claim" "$RESULTS_DIR/pre-dispatch-failure.automatic-peer.json"
run_agent_sync() { return 74; }
octo_auto_peer_run coding standard "pre-dispatch failure test" codex-standard "owner result"
if jq -e '.status == "unavailable" and .attempts == 0 and (.reason | startswith("peer dispatch was not started"))' \
    "$RESULTS_DIR/pre-dispatch-failure.automatic-peer.json" >/dev/null; then
    test_pass
else
    test_fail "pre-dispatch failure was counted as a provider attempt"
fi

test_case "a pre-dispatch exit 1 is not counted as a provider attempt"
export OCTOPUS_AUTO_PEER_RUN_ID=pre-dispatch-exit-one
export OCTOPUS_AUTO_PEER_CHECKED=false
rm -f "$RESULTS_DIR/.pre-dispatch-exit-one.automatic-peer.claim" "$RESULTS_DIR/pre-dispatch-exit-one.automatic-peer.json"
run_agent_sync() { return 1; }
octo_auto_peer_run coding standard "pre-dispatch exit one test" codex-standard "owner result"
if jq -e '.status == "unavailable" and .attempts == 0 and (.reason | startswith("peer dispatch was not started"))' \
    "$RESULTS_DIR/pre-dispatch-exit-one.automatic-peer.json" >/dev/null; then
    test_pass
else
    test_fail "pre-dispatch exit 1 was counted as a provider attempt"
fi

test_case "a provider failure after dispatch counts one attempt"
export OCTOPUS_AUTO_PEER_RUN_ID=provider-failure
export OCTOPUS_AUTO_PEER_CHECKED=false
rm -f "$RESULTS_DIR/.provider-failure.automatic-peer.claim" "$RESULTS_DIR/provider-failure.automatic-peer.json"
run_agent_sync() {
    printf '%s\n' started > "$OCTOPUS_AUTO_PEER_DISPATCH_MARKER"
    return 1
}
octo_auto_peer_run coding standard "provider failure test" codex-standard "owner result"
if jq -e '.status == "unavailable" and .attempts == 1 and (.reason | startswith("peer execution failed"))' \
    "$RESULTS_DIR/provider-failure.automatic-peer.json" >/dev/null; then
    test_pass
else
    test_fail "provider failure after dispatch did not count one attempt"
fi

test_case "receipt failures are reported as unrecorded"
export OCTOPUS_AUTO_PEER_RUN_ID=receipt-failure
export OCTOPUS_AUTO_PEER_CHECKED=false
rm -f "$RESULTS_DIR/.receipt-failure.automatic-peer.claim" "$RESULTS_DIR/receipt-failure.automatic-peer.json"
octo_auto_peer_write_receipt() { return 1; }
receipt_output="$(octo_auto_peer_run coding standard "receipt failure test" codex-standard "owner result" 2>&1)"
if [[ "$receipt_output" == *"unrecorded"* ]] && [[ ! -e "$RESULTS_DIR/receipt-failure.automatic-peer.json" ]]; then
    test_pass
else
    test_fail "receipt failure was presented as a recorded result"
fi

test_summary
