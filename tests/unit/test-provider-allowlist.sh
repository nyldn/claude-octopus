#!/usr/bin/env bash
# Unit tests for OCTO_ALLOWED_PROVIDERS filtering.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
export OCTOPUS_CONFIG_DIR="$TEST_TMP_DIR/provider-allowlist-root"
# Isolate the quota-dead marker too. check-providers.sh downgrades a seat marked
# quota/auth-dead to `degraded`, and that marker lives under WORKSPACE_DIR — so
# without this the assertions below read the developer's real provider health
# and fail on any machine where, say, AGY has actually hit its quota limit.
export WORKSPACE_DIR="$TEST_TMP_DIR/provider-allowlist-workspace"
mkdir -p "$WORKSPACE_DIR/state"
unset CLAUDE_CODE_SESSION_ID OCTO_ALLOWED_PROVIDERS
test_suite "Provider allowlist"

ALLOWLIST_LIB="$PROJECT_ROOT/scripts/lib/provider-allowlist.sh"
CHECK_PROVIDERS="$PROJECT_ROOT/scripts/helpers/check-providers.sh"
BUILD_FLEET="$PROJECT_ROOT/scripts/helpers/build-fleet.sh"
SELECT_ADVISORS="$PROJECT_ROOT/scripts/helpers/select-fleet-advisors.sh"
CONSULTATIVE_LIB="$PROJECT_ROOT/scripts/lib/consultative-advisors.sh"
MODEL_CONFIG="$PROJECT_ROOT/scripts/helpers/octo-model-config.sh"

test_case "allowlist helper has valid bash syntax"
if bash -n "$ALLOWLIST_LIB"; then
    test_pass
else
    test_fail "provider-allowlist.sh has syntax errors"
fi

source "$ALLOWLIST_LIB"

test_case "unset allowlist permits every provider"
if unset OCTO_ALLOWED_PROVIDERS && octo_provider_allowed codex && octo_provider_allowed agy && octo_provider_allowed claude-sonnet; then
    test_pass
else
    test_fail "unset allowlist should allow all providers"
fi

test_case "space and comma separated allowlist filters providers"
if OCTO_ALLOWED_PROVIDERS="claude, agy ollama" octo_provider_allowed agy &&
   OCTO_ALLOWED_PROVIDERS="claude, agy ollama" octo_provider_allowed claude-sonnet &&
   ! OCTO_ALLOWED_PROVIDERS="claude, agy ollama" octo_provider_allowed codex; then
    test_pass
else
    test_fail "allowlist did not honor comma/space separated provider names"
fi

# #524: agy (Antigravity) is the Google seat after the Gemini CLI sunset. A legacy
# "google" allowlist must keep authorizing agy during/after migration.
test_case "legacy 'google' allowlist authorizes the AGY Google seat, not codex"
if OCTO_ALLOWED_PROVIDERS="google" octo_provider_allowed agy &&
   OCTO_ALLOWED_PROVIDERS="google" octo_provider_allowed agy-research &&
   OCTO_ALLOWED_PROVIDERS="google" octo_provider_allowed gemini &&
   ! OCTO_ALLOWED_PROVIDERS="google" octo_provider_allowed codex; then
    test_pass
else
    test_fail "'google' alias should authorize AGY and its legacy gemini alias, but not codex"
fi

test_case "legacy 'gemini' allowlist token authorizes AGY"
if OCTO_ALLOWED_PROVIDERS="gemini" octo_provider_allowed gemini &&
   OCTO_ALLOWED_PROVIDERS="gemini" octo_provider_allowed agy; then
    test_pass
else
    test_fail "'gemini' token must canonicalize to AGY"
fi

session_config="$TEST_TMP_DIR/provider-allowlist-config"

test_case "session allowlist file filters providers without env var"
if unset OCTO_ALLOWED_PROVIDERS &&
   OCTOPUS_CONFIG_DIR="$session_config" CLAUDE_CODE_SESSION_ID="session/one" "$MODEL_CONFIG" allow claude agy --session >/dev/null &&
   OCTOPUS_CONFIG_DIR="$session_config" CLAUDE_CODE_SESSION_ID="session/one" octo_provider_allowed claude-sonnet &&
   OCTOPUS_CONFIG_DIR="$session_config" CLAUDE_CODE_SESSION_ID="session/one" octo_provider_allowed agy &&
   ! OCTOPUS_CONFIG_DIR="$session_config" CLAUDE_CODE_SESSION_ID="session/one" octo_provider_allowed codex; then
    test_pass
else
    test_fail "session allowlist file should restrict providers"
fi

test_case "disable command removes one provider for current session"
if unset OCTO_ALLOWED_PROVIDERS &&
   OCTOPUS_CONFIG_DIR="$session_config" CLAUDE_CODE_SESSION_ID="session/two" "$MODEL_CONFIG" disable codex --session >/dev/null &&
   ! OCTOPUS_CONFIG_DIR="$session_config" CLAUDE_CODE_SESSION_ID="session/two" octo_provider_allowed codex &&
   OCTOPUS_CONFIG_DIR="$session_config" CLAUDE_CODE_SESSION_ID="session/two" octo_provider_allowed agy; then
    test_pass
else
    test_fail "disable should write a session allowlist excluding codex"
fi

test_case "clear-allowlist restores default provider availability"
if unset OCTO_ALLOWED_PROVIDERS &&
   OCTOPUS_CONFIG_DIR="$session_config" CLAUDE_CODE_SESSION_ID="session/two" "$MODEL_CONFIG" clear-allowlist --session >/dev/null &&
   OCTOPUS_CONFIG_DIR="$session_config" CLAUDE_CODE_SESSION_ID="session/two" octo_provider_allowed codex; then
    test_pass
else
    test_fail "clear-allowlist should restore default availability"
fi

mock_bin="$TEST_TMP_DIR/provider-allowlist-bin"
mkdir -p "$mock_bin"
for cmd in codex agy; do
    cat > "$mock_bin/$cmd" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "$mock_bin/$cmd"
done

test_case "check-providers reports disallowed installed providers as missing"
output=$(PATH="$mock_bin:/usr/bin:/bin" OCTO_ALLOWED_PROVIDERS="gemini" "$CHECK_PROVIDERS")
if assert_contains "$output" "agy:available" "legacy gemini token should authorize AGY" &&
   assert_contains "$output" "codex:missing" "codex should be hidden by allowlist"; then
    test_pass
fi

test_case "build-fleet fails closed when provider allowlist library is missing"
missing_root="$TEST_TMP_DIR/build-fleet-missing-allowlist"
mkdir -p "$missing_root/helpers" "$missing_root/lib"
cp "$BUILD_FLEET" "$missing_root/helpers/build-fleet.sh"
set +e
missing_output=$(bash "$missing_root/helpers/build-fleet.sh" review standard "review target" 2>&1)
missing_rc=$?
set -e
if [[ "$missing_rc" -ne 0 ]] && [[ "$missing_output" == *"required provider allowlist library"* ]]; then
    test_pass
else
    test_fail "build-fleet did not fail closed without provider-allowlist.sh: rc=$missing_rc output=$missing_output"
fi

test_case "build-fleet excludes disallowed providers"
fleet=$(PATH="$mock_bin:/usr/bin:/bin" OCTO_ALLOWED_PROVIDERS="claude gemini" "$BUILD_FLEET" review standard "review target" 2>/dev/null)
if assert_contains "$fleet" "agy|" "legacy gemini token should make AGY eligible" &&
   assert_contains "$fleet" "claude-sonnet|" "claude alias should allow claude-sonnet" &&
   assert_not_contains "$fleet" "codex|" "codex should not be emitted"; then
    test_pass
fi

test_case "build-fleet rejects an available-but-denied candidate set"
denied_checker="$TEST_TMP_DIR/denied-provider-checker.sh"
cat > "$denied_checker" <<'SH'
#!/bin/bash
printf '%s\n' 'codex:available'
SH
chmod +x "$denied_checker"
set +e
fleet=$(OCTOPUS_PROVIDER_CHECKER="$denied_checker" OCTO_ALLOWED_PROVIDERS=agy \
    "$BUILD_FLEET" research quick fixture 2>/dev/null)
fleet_rc=$?
set -e
if [[ "$fleet_rc" -ne 0 && -z "$fleet" ]]; then
    test_pass
else
    test_fail "denied candidates must produce a failed empty fleet: rc=$fleet_rc fleet='$fleet'"
fi

test_case "quick research never emits a disallowed Claude fallback"
codex_only_checker="$TEST_TMP_DIR/codex-only-checker.sh"
cat > "$codex_only_checker" <<'SH'
#!/bin/bash
printf '%s\n' 'codex:available'
SH
chmod +x "$codex_only_checker"
fleet=$(OCTOPUS_PROVIDER_CHECKER="$codex_only_checker" OCTO_ALLOWED_PROVIDERS=codex \
    "$BUILD_FLEET" research quick fixture 2>/dev/null)
if [[ "$fleet" == *'codex|'* && "$fleet" != *'claude'* ]]; then
    test_pass
else
    test_fail "quick research escaped its allowlist: fleet='$fleet'"
fi

advisor_builder="$TEST_TMP_DIR/advisor-builder.sh"

test_case "advisor selection propagates fleet construction failure"
cat > "$advisor_builder" <<'SH'
#!/bin/bash
printf '%s\n' 'codex|Debater|must not escape a failed fleet'
exit 42
SH
chmod +x "$advisor_builder"
set +e
advisor_output=$(OCTOPUS_FLEET_BUILDER="$advisor_builder" "$SELECT_ADVISORS" debate standard fixture 2>/dev/null)
advisor_rc=$?
set -e
if [[ "$advisor_rc" -eq 42 && -z "$advisor_output" ]]; then
    test_pass
else
    test_fail "advisor selector must propagate fleet failure without output: rc=$advisor_rc output='$advisor_output'"
fi

test_case "advisor selection rejects an empty successful fleet"
cat > "$advisor_builder" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$advisor_builder"
set +e
advisor_output=$(OCTOPUS_FLEET_BUILDER="$advisor_builder" "$SELECT_ADVISORS" research standard fixture 2>/dev/null)
advisor_rc=$?
set -e
if [[ "$advisor_rc" -ne 0 && -z "$advisor_output" ]]; then
    test_pass
else
    test_fail "advisor selector must reject an empty fleet: rc=$advisor_rc output='$advisor_output'"
fi

test_case "advisor selection rejects a Kimi-only consultative fleet"
cat > "$advisor_builder" <<'SH'
#!/bin/bash
printf '%s\n' 'kimi|Debater|unsafe consultative seat'
SH
chmod +x "$advisor_builder"
set +e
advisor_output=$(OCTOPUS_FLEET_BUILDER="$advisor_builder" OCTO_ALLOWED_PROVIDERS=kimi \
    "$SELECT_ADVISORS" debate standard fixture 2>/dev/null)
advisor_rc=$?
set -e
if [[ "$advisor_rc" -ne 0 && -z "$advisor_output" ]]; then
    test_pass
else
    test_fail "advisor selector must reject Kimi-only fleets: rc=$advisor_rc output='$advisor_output'"
fi

test_case "advisor selection emits only allowlisted fleet providers"
cat > "$advisor_builder" <<'SH'
#!/bin/bash
printf '%s\n' \
    'codex|Debater|OpenAI view' \
    'agy|Debater|Google view' \
    'claude-sonnet|Moderator|host view'
SH
chmod +x "$advisor_builder"
advisor_output=$(OCTOPUS_FLEET_BUILDER="$advisor_builder" OCTO_ALLOWED_PROVIDERS=agy \
    "$SELECT_ADVISORS" debate standard fixture 2>/dev/null)
if [[ "$advisor_output" == "agy" ]]; then
    test_pass
else
    test_fail "advisor selector escaped the provider allowlist: output='$advisor_output'"
fi

test_case "brainstorm and debate consumers use fail-closed advisor selection"
consumer_errors=""
for consumer in \
    "$PROJECT_ROOT/commands/brainstorm.md" \
    "$PROJECT_ROOT/.cursor-plugin/commands/octo-brainstorm.md" \
    "$PROJECT_ROOT/.claude/skills/skill-debate/SKILL.md" \
    "$PROJECT_ROOT/skills/skill-debate/SKILL.md"; do
    grep -q 'select-fleet-advisors.sh' "$consumer" || consumer_errors+="$consumer: missing advisor selector"$'\n'
    if grep -q 'fallback_advisors' "$consumer"; then
        consumer_errors+="$consumer: retains provider fallback"$'\n'
    fi
done
if [[ -z "$consumer_errors" ]]; then
    test_pass
else
    test_fail "workflow consumers must preserve fleet admission failures: $consumer_errors"
fi

test_case "consultative consumer contract launches every selected provider family"
if [[ ! -r "$CONSULTATIVE_LIB" ]]; then
    test_fail "missing consultative advisor contract: $CONSULTATIVE_LIB"
else
    source "$CONSULTATIVE_LIB"
    launch_orchestrator="$TEST_TMP_DIR/launch-orchestrator.sh"
    launch_log="$TEST_TMP_DIR/launch-advisors.log"
    cat > "$launch_orchestrator" <<'SH'
#!/bin/bash
[[ "${1:-}" == spawn ]] || exit 64
printf '%s\n' "$2" >> "$OCTO_LAUNCH_LOG"
[[ "${OCTO_ORCH_FAIL:-false}" == true ]] && exit 9
printf 'response from %s\n' "$2"
SH
    chmod +x "$launch_orchestrator"
    launch_errors=""
    for provider in openrouter commandcode; do
        cat > "$advisor_builder" <<SH
#!/bin/bash
printf '%s\n' '$provider|Problem Analysis|consumer fixture'
SH
        chmod +x "$advisor_builder"
        selected=$(OCTOPUS_FLEET_BUILDER="$advisor_builder" \
            OCTO_ALLOWED_PROVIDERS="$provider claude" \
            "$SELECT_ADVISORS" research standard fixture 2>/dev/null) || selected="failed"
        : > "$launch_log"
        output_dir="$TEST_TMP_DIR/launch-$provider"
        mkdir -p "$output_dir"
        count=$(OCTO_LAUNCH_LOG="$launch_log" OCTO_ALLOWED_PROVIDERS="$provider claude" \
            octo_launch_advisors "$launch_orchestrator" "$selected" "$output_dir" response- \
                'Review as {{advisor}}' 1 2>/dev/null) || count="failed"
        [[ "$selected" == "$provider" ]] || launch_errors+="$provider selector=$selected"$'\n'
        [[ "$count" == 1 ]] || launch_errors+="$provider count=$count"$'\n'
        [[ "$(< "$launch_log")" == "$provider" ]] || launch_errors+="$provider was not launched"$'\n'
    done
    if [[ -z "$launch_errors" ]]; then
        test_pass
    else
        test_fail "selected providers did not reach the orchestrator: $launch_errors"
    fi
fi

test_case "consultative consumer gates host Claude and enforces provider count"
if [[ ! -r "$CONSULTATIVE_LIB" ]]; then
    test_fail "missing consultative advisor contract: $CONSULTATIVE_LIB"
else
    source "$CONSULTATIVE_LIB"
    host_rc=0
    OCTO_ALLOWED_PROVIDERS=codex octo_consultative_host_allowed || host_rc=$?
    required=$(OCTO_ALLOWED_PROVIDERS=codex octo_consultative_required_external_count)
    output_dir="$TEST_TMP_DIR/host-disallowed"
    mkdir -p "$output_dir"
    launch_rc=0
    OCTO_LAUNCH_LOG="$launch_log" OCTO_ALLOWED_PROVIDERS=codex \
        octo_launch_advisors "$launch_orchestrator" codex "$output_dir" response- \
            'Review as {{advisor}}' "$required" >/dev/null 2>&1 || launch_rc=$?
    total_without_host=0
    total_with_host=0
    octo_consultative_provider_count_is_sufficient 1 0 || total_without_host=$?
    OCTO_ALLOWED_PROVIDERS=codex octo_consultative_provider_count_is_sufficient 1 1 || total_with_host=$?
    if [[ "$host_rc" -ne 0 && "$required" -eq 2 && "$launch_rc" -ne 0 && \
          "$total_without_host" -ne 0 && "$total_with_host" -ne 0 ]]; then
        test_pass
    else
        test_fail "host-disabled run must require two external successes: host=$host_rc required=$required launch=$launch_rc totals=$total_without_host/$total_with_host"
    fi
fi

test_case "consultative consumer fails when no advisor launch succeeds"
if [[ ! -r "$CONSULTATIVE_LIB" ]]; then
    test_fail "missing consultative advisor contract: $CONSULTATIVE_LIB"
else
    source "$CONSULTATIVE_LIB"
    output_dir="$TEST_TMP_DIR/zero-launch"
    mkdir -p "$output_dir"
    launch_rc=0
    OCTO_ORCH_FAIL=true OCTO_LAUNCH_LOG="$launch_log" OCTO_ALLOWED_PROVIDERS="codex claude" \
        octo_launch_advisors "$launch_orchestrator" codex "$output_dir" response- \
            'Review as {{advisor}}' 1 >/dev/null 2>&1 || launch_rc=$?
    if [[ "$launch_rc" -ne 0 ]]; then
        test_pass
    else
        test_fail "zero successful launches must fail"
    fi
fi

test_case "brainstorm and debate use the executable launch contract and gate Claude"
consumer_errors=""
for consumer in \
    "$PROJECT_ROOT/commands/brainstorm.md" \
    "$PROJECT_ROOT/.cursor-plugin/commands/octo-brainstorm.md" \
    "$PROJECT_ROOT/.claude/skills/skill-debate/SKILL.md" \
    "$PROJECT_ROOT/skills/skill-debate/SKILL.md"; do
    grep -q 'consultative-advisors.sh' "$consumer" || consumer_errors+="$consumer: missing shared launch contract"$'\n'
    grep -q 'octo_launch_advisors' "$consumer" || consumer_errors+="$consumer: missing counted launch"$'\n'
    grep -q 'octo_consultative_host_allowed' "$consumer" || consumer_errors+="$consumer: host Claude is not allowlist-gated"$'\n'
    grep -q 'HOST_ADVISOR_SUCCESS=0' "$consumer" || consumer_errors+="$consumer: host success is not initialized fail-closed"$'\n'
    if grep -q '^wait$' "$consumer"; then
        consumer_errors+="$consumer: retains bare wait"$'\n'
    fi
done
if [[ -z "$consumer_errors" ]]; then
    test_pass
else
    test_fail "workflow consumers do not enforce successful provider count: $consumer_errors"
fi

# ── alias arms must not shadow one another (SC2221/SC2222) ───────────────────
# `cursor|cursor-agent|xai)` used to swallow the dedicated `xai)` arm below it,
# so an xai allowlist authorised cursor-agent but silently denied grok seats.
source "$PROJECT_ROOT/scripts/lib/provider-allowlist.sh"

test_case "xai allowlist authorises grok seats and cursor-agent"
(
    export OCTO_ALLOWED_PROVIDERS="xai"
    ok=true
    for seat in cursor-agent grok grok-4; do
        octo_provider_allowed "$seat" || { echo "denied: $seat"; ok=false; }
    done
    [[ "$ok" == "true" ]]
) && test_pass || test_fail "xai allowlist must authorise cursor-agent, grok and grok-* seats"

test_case "cursor allowlist stays narrow and does not authorise grok"
(
    export OCTO_ALLOWED_PROVIDERS="cursor"
    octo_provider_allowed "cursor-agent" || { echo "cursor-agent denied"; exit 1; }
    octo_provider_allowed "grok" && { echo "grok wrongly allowed"; exit 1; }
    exit 0
) && test_pass || test_fail "cursor allowlist should allow cursor-agent only"

# ── sourced libraries must not leak shell options into their callers ─────────
test_case "sourcing provider-allowlist.sh leaves errexit and pipefail untouched"
leak=$(bash -c '
    set +e +o pipefail
    source "'"$PROJECT_ROOT"'/scripts/lib/provider-allowlist.sh" 2>/dev/null
    case "$-" in *e*) echo "errexit"; esac
    shopt -qo pipefail && echo "pipefail"
    exit 0
')
if [[ -z "$leak" ]]; then
    test_pass
else
    test_fail "sourced lib leaked shell options: $leak"
fi

test_summary
