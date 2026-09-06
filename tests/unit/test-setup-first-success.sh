#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Setup path to first success"

SETUP="$PROJECT_ROOT/commands/setup.md"
CURSOR_SETUP="$PROJECT_ROOT/.cursor-plugin/commands/octo-setup.md"
setup_text="$(cat "$SETUP")"
default_path="$(sed -n '/^## Default path/,/^## Advanced setup/p' "$SETUP")"
advanced_path="$(sed -n '/^## Advanced setup/,$p' "$SETUP")"
readiness_step="$(sed -n '/^### 2\. Show shared readiness/,/^### 3\./p' "$SETUP")"

test_case "setup accepts a readable non-executable preflight helper"
root_guard_ok=true
fixture_root="$TEST_TMP_DIR/plugin root"
fixture_home="$TEST_TMP_DIR/home"
mkdir -p "$fixture_root/scripts/helpers" "$fixture_home"
: > "$fixture_root/scripts/helpers/preflight.sh"
chmod 0644 "$fixture_root/scripts/helpers/preflight.sh"
for setup_command in "$SETUP" "$CURSOR_SETUP"; do
    resolve_block="$(awk '
      /^### 1\. Resolve the installed plugin$/ {in_step=1; next}
      in_step && /^```bash$/ {in_fence=1; next}
      in_step && in_fence && /^```$/ {exit}
      in_step && in_fence {print}
    ' "$setup_command")"
    resolved_root="$(
      env \
        "CLAUDE_PLUGIN_ROOT=$fixture_root" \
        "HOME=$fixture_home" \
        "LOCALAPPDATA=$TEST_TMP_DIR/local-app-data" \
        "XDG_DATA_HOME=$TEST_TMP_DIR/xdg-data" \
        bash -c "$resolve_block"$'\n''printf "%s\n" "$OCTO_ROOT"'
    )" || root_guard_ok=false
    if [[ "$resolved_root" != "$fixture_root" ]] ||
       grep -Eq '\[\[[^]]*-x[^]]*scripts/helpers/preflight\.sh' "$setup_command" ||
       [[ "$(grep -Ec '\[\[[^]]*-r[^]]*scripts/helpers/preflight\.sh' "$setup_command" || true)" -ne 3 ]] ||
       ! grep -Fq 'bash "${OCTO_ROOT}/scripts/helpers/preflight.sh" --json' "$setup_command"; then
        root_guard_ok=false
    fi
done
if [[ "$root_guard_ok" == true ]]; then
    test_pass
else
    test_fail "setup still requires the bash-invoked preflight helper to be executable"
fi

test_case "fallback search skips an unreadable preflight helper"
fallback_guard_ok=true
unreadable_root="$fixture_home/.claude/plugins/cache/nyldn-plugins/octo/0.0.0"
readable_root="$fixture_home/Library/Application Support/Claude/nyldn-plugins/octo/1.0.0"
mkdir -p "$unreadable_root/scripts/helpers" "$readable_root/scripts/helpers"
: > "$unreadable_root/scripts/helpers/preflight.sh"
: > "$readable_root/scripts/helpers/preflight.sh"
chmod 000 "$unreadable_root/scripts/helpers/preflight.sh"
chmod 0644 "$readable_root/scripts/helpers/preflight.sh"
for setup_command in "$SETUP" "$CURSOR_SETUP"; do
    resolve_block="$(awk '
      /^### 1\. Resolve the installed plugin$/ {in_step=1; next}
      in_step && /^```bash$/ {in_fence=1; next}
      in_step && in_fence && /^```$/ {exit}
      in_step && in_fence {print}
    ' "$setup_command")"
    resolved_root="$(
      env \
        "CLAUDE_PLUGIN_ROOT=$TEST_TMP_DIR/missing-active-root" \
        "HOME=$fixture_home" \
        "LOCALAPPDATA=$TEST_TMP_DIR/local-app-data" \
        "XDG_DATA_HOME=$TEST_TMP_DIR/xdg-data" \
        bash -c "$resolve_block"$'\n''printf "%s\n" "$OCTO_ROOT"'
    )" || fallback_guard_ok=false
    if [[ "$resolved_root" != "$readable_root" ]]; then
        fallback_guard_ok=false
    fi
done
chmod 0644 "$unreadable_root/scripts/helpers/preflight.sh"
if [[ "$fallback_guard_ok" == true ]]; then
    test_pass
else
    test_fail "fallback search stopped at an unreadable preflight helper"
fi

test_case "initial setup renders the shared static readiness contract once"
if [[ "$(grep -c 'setup_readiness_capture' <<<"$readiness_step" || true)" -eq 1 ]] &&
   [[ "$(grep -c '^setup_readiness_capture()' <<<"$default_path" || true)" -eq 1 ]] &&
   grep -q 'scripts/helpers/preflight.sh.*--json' <<<"$default_path" &&
   ! grep -Eq 'command -v (codex|agy|copilot|qwen|opencode|vibe)|PERPLEXITY_API_KEY|curl .*api/tags' <<<"$default_path"; then
    test_pass
else
    test_fail "default setup must consume one shared readiness report without re-detection"
fi

test_case "default path offers Claude-only or one additional provider"
if grep -q 'Use Claude alone' <<<"$default_path" &&
   grep -q 'Configure one provider' <<<"$default_path"; then
    test_pass
else
    test_fail "default setup choices do not establish the first-success path"
fi

test_case "default verification is deterministic and no-billing"
if grep -q 'setup-verification' <<<"$default_path" &&
   grep -qi 'no provider request' <<<"$default_path"; then
    test_pass
else
    test_fail "default setup lacks an explicit no-billing verification"
fi

test_case "setup verification checks every shipped shell file and fails before persistence"
verification_block="$(awk '
  /^### 4\. Run a deterministic no-billing verification/ {in_step=1; next}
  in_step && /^```bash$/ {in_fence=1; next}
  in_step && in_fence && /^```$/ {exit}
  in_step && in_fence {print}
' "$SETUP")"
verification_ok=true
for broken in preflight orchestrate; do
    verify_root="$TEST_TMP_DIR/verify-$broken"
    verify_home="$TEST_TMP_DIR/verify-home-$broken"
    mkdir -p "$verify_root/scripts/helpers" "$verify_root/scripts" "$verify_home"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$verify_root/scripts/helpers/check-providers.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$verify_root/scripts/helpers/preflight.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$verify_root/scripts/orchestrate.sh"
    if [[ "$broken" == preflight ]]; then
        printf '%s\n' '#!/usr/bin/env bash' 'if then' > "$verify_root/scripts/helpers/preflight.sh"
    else
        printf '%s\n' '#!/usr/bin/env bash' 'if then' > "$verify_root/scripts/orchestrate.sh"
    fi
    set +e
    env "HOME=$verify_home" "OCTO_ROOT=$verify_root" \
        "READINESS_JSON={\"results\":[{\"provider\":\"host\"}]}" \
        bash -c "$verification_block" >/dev/null 2>&1
    verify_rc=$?
    set -e
    if [[ "$verify_rc" -eq 0 || -e "$verify_home/.claude-octopus/setup" ]]; then
        verification_ok=false
    fi
done
if [[ "$verification_ok" == true ]]; then
    test_pass
else
    test_fail "a later shell syntax error passed verification or wrote a receipt"
fi

test_case "default completion shows exactly the three next commands"
next_commands="$(awk '
  /^Next commands:/ {in_next=1; next}
  in_next && /^```text$/ {in_fence=1; next}
  in_next && in_fence && /^```$/ {exit}
  in_next && in_fence {print}
' <<<"$default_path" | grep -oE '/octo:[a-z-]+' || true)"
expected=$'/octo:auto\n/octo:skill-doctor\n/octo:setup'
if [[ "$next_commands" == "$expected" ]]; then
    test_pass
else
    test_fail "expected three next commands, got: ${next_commands//$'\n'/, }"
fi

test_case "optional companions and tuning stay in Advanced setup"
if ! grep -Eqi 'RTK|Graphify|memory companion|cost mode|scheduler|model override|project tier' <<<"$default_path" &&
   grep -Eqi 'RTK' <<<"$advanced_path" &&
   grep -Eqi 'Graphify' <<<"$advanced_path" &&
   grep -Eqi 'memory companion' <<<"$advanced_path"; then
    test_pass
else
    test_fail "optional setup leaked into the default path or is absent from Advanced setup"
fi

test_case "setup removes stale migration and retired Doctor guidance"
if ! grep -q 'v9.29 Migration' <<<"$setup_text" &&
   ! grep -q '/octo:doctor' <<<"$setup_text" &&
   grep -q '/octo:skill-doctor' <<<"$setup_text" &&
   grep -q 'octopus doctor' <<<"$setup_text"; then
    test_pass
else
    test_fail "setup still exposes stale migration or retired Doctor guidance"
fi

test_case "default path writes only after explicit confirmation"
first_question_line="$(grep -n 'AskUserQuestion' <<<"$default_path" | head -1 | cut -d: -f1 || true)"
first_write_line="$(grep -nE 'octo_(config|pref)_write|npm install|brew install|uv tool install' <<<"$default_path" | head -1 | cut -d: -f1 || true)"
if [[ -n "$first_question_line" ]] && { [[ -z "$first_write_line" ]] || (( first_write_line > first_question_line )); }; then
    test_pass
else
    test_fail "default setup can mutate state before the user chooses an option"
fi

test_case "resume preserves an existing selection and completion verifies preference readback"
if grep -Fq 'SETUP_EXISTING_FLOW' <<<"$default_path" &&
   grep -Fq 'SETUP_EXISTING_PROVIDER' <<<"$default_path" &&
   grep -Fq 'setup_record selected null' <<<"$default_path" &&
   grep -Fq '.auto_router_mode == "suggest" or .auto_router_mode == "off" or .auto_router_mode == "invoke"' <<<"$default_path" &&
   grep -Fq 'The resume receipt remains incomplete' <<<"$default_path"; then
    test_pass
else
    test_fail "setup cannot resume an existing selection or verify preference persistence"
fi

state_block="$(awk '
  /^### 1\.5 Read resumable setup state/ {in_step=1; next}
  in_step && /^```bash$/ {in_fence=1; next}
  in_step && in_fence && /^```$/ {exit}
  in_step && in_fence {print}
' "$SETUP")"
selection_block="$(awk '
  /^Set `SETUP_FLOW=one-provider`/ {in_step=1}
  in_step && /^```bash$/ {in_fence=1; next}
  in_step && in_fence && /^```$/ {exit}
  in_step && in_fence {print}
' "$SETUP")"
verification_block="$(awk '
  /^### 4\. Run a deterministic no-billing verification/ {in_step=1; next}
  in_step && /^```bash$/ {in_fence=1; next}
  in_step && in_fence && /^```$/ {exit}
  in_step && in_fence {print}
' "$SETUP")"
completion_block="$(awk '
  /^Only after the user selected a completion path/ {in_step=1}
  in_step && /^```bash$/ {in_fence=1; next}
  in_step && in_fence && /^```$/ {exit}
  in_step && in_fence {print}
' "$SETUP")"

readiness_block="$(awk '
  /^### 2\. Show shared readiness/ {in_step=1; next}
  in_step && /^```bash$/ {in_fence=1; next}
  in_step && in_fence && /^```$/ {exit}
  in_step && in_fence {print}
' "$SETUP")"

complete_host_only() {
    local target_home="$1"
    env HOME="$target_home" OCTO_ROOT="$PROJECT_ROOT" CODEX_SANDBOX=workspace-write \
        bash -c "$state_block"$'\n'"$readiness_block"$'\n''SETUP_FLOW=host-only'$'\n''SETUP_PROVIDER='"''"$'\n'"$selection_block"$'\n'"$verification_block"$'\n'"$completion_block" \
        >/dev/null 2>&1
}

test_case "documented host-only sequence initializes and completes its receipt"
host_home="$TEST_TMP_DIR/host-only-home"
mkdir -p "$host_home"
host_sequence_ok=true
if ! complete_host_only "$host_home"; then
    host_sequence_ok=false
fi
host_receipt="$(find "$host_home/.claude-octopus/setup" -type f -name '*.json' -print -quit 2>/dev/null || true)"
if [[ -z "$host_receipt" ]] ||
   ! jq -e '.status? == null and .flow == "host-only" and .provider == "" and .stage == "verified" and .completed == true and .verification.result == "passed"' \
      "$host_receipt" >/dev/null 2>&1 ||
   ! jq -e '.setup_complete == true' "$host_home/.claude-octopus/user-config.json" >/dev/null 2>&1; then
    host_sequence_ok=false
fi
if [[ "$host_sequence_ok" == true ]]; then
    test_pass
else
    test_fail "the documented host-only path did not reach a completed receipt"
fi

test_case "completed setup is invalidated by initial readiness and local verification failures"
failure_root="$TEST_TMP_DIR/setup-failure-provider"
mkdir -p "$failure_root/scripts/helpers"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'case "${PREFLIGHT_MODE:-failed}" in' \
  '  failed) exit 9 ;;' \
  '  malformed) printf '\''%s\n'\'' '\''{"unexpected":true}'\'' ;;' \
  '  duplicate) printf '\''%s\n'\'' '\''{"check_kind":"static","results":[{"provider":"codex","status":"missing","reason_code":"first","reason_code":"second","checked_at":"now","duration_ms":1,"remediation":"login"}]}'\'' ;;' \
  '  multiple) printf '\''%s\n%s\n'\'' '\''{"check_kind":"static","results":[{"provider":"codex","status":"missing","reason_code":"first","checked_at":"now","duration_ms":1,"remediation":"login"}]}'\'' '\''{"check_kind":"static","results":[{"provider":"codex","status":"missing","reason_code":"second","checked_at":"now","duration_ms":1,"remediation":"login"}]}'\'' ;;' \
  '  nul) printf '\''{"check_kind":"static","results":[{"provider":"codex","status":"avail\0able","reason_code":"ready","checked_at":"now","duration_ms":1,"remediation":"login"}]}\n'\'' ;;' \
  '  surrogate) printf '\''%s\n'\'' '\''{"check_kind":"static","results":[{"provider":"codex","status":"missing","reason_code":"\ud800","checked_at":"now","duration_ms":1,"remediation":"login"}]}'\'' ;;' \
  '  nested) printf '\''{"check_kind":"static","results":[{"provider":"codex","status":"missing","reason_code":"ready","checked_at":"now","duration_ms":1,"remediation":"login"}],"extra":'\''; printf '\''%.0s['\'' {1..300}; printf 0; printf '\''%.0s]'\'' {1..300}; printf '\''}\n'\'' ;;' \
  'esac' \
  > "$failure_root/scripts/helpers/preflight.sh"
failure_paths_ok=true
for mode in failed malformed duplicate multiple nul surrogate nested; do
    failure_home="$TEST_TMP_DIR/initial-$mode-home"
    mkdir -p "$failure_home"
    complete_host_only "$failure_home" || failure_paths_ok=false
    set +e
    env HOME="$failure_home" OCTO_ROOT="$PROJECT_ROOT" CODEX_SANDBOX=workspace-write \
        PREFLIGHT_MODE="$mode" FAILURE_ROOT="$failure_root" \
        bash -c "$state_block"$'\n''OCTO_ROOT="$FAILURE_ROOT"'$'\n'"$readiness_block" \
        >/dev/null 2>&1
    failure_rc=$?
    set -e
    failure_receipt="$(find "$failure_home/.claude-octopus/setup" -type f -name '*.json' -print -quit 2>/dev/null || true)"
    expected_reason=initial-readiness-check-failed
    if [[ "$failure_rc" -eq 0 || -z "$failure_receipt" ]] ||
       ! jq -e --arg reason "$expected_reason" \
          '.completed == false and .stage == "rechecked" and .verification.result == "failed" and .verification.reason_code == $reason' \
          "$failure_receipt" >/dev/null 2>&1; then
        failure_paths_ok=false
    fi
done

local_failure_home="$TEST_TMP_DIR/local-verification-failure-home"
mkdir -p "$local_failure_home"
complete_host_only "$local_failure_home" || failure_paths_ok=false
set +e
env HOME="$local_failure_home" OCTO_ROOT="$PROJECT_ROOT" CODEX_SANDBOX=workspace-write \
    SETUP_FLOW=host-only SETUP_PROVIDER='' READINESS_JSON='{"results":[]}' \
    bash -c "$state_block"$'\n'"$verification_block" >/dev/null 2>&1
local_failure_rc=$?
set -e
local_failure_receipt="$(find "$local_failure_home/.claude-octopus/setup" -type f -name '*.json' -print -quit 2>/dev/null || true)"
if [[ "$local_failure_rc" -eq 0 || -z "$local_failure_receipt" ]] ||
   ! jq -e '.completed == false and .stage == "rechecked" and .verification == {checked_at:.verification.checked_at,reason_code:"local-readiness-contract-invalid",result:"failed"}' \
      "$local_failure_receipt" >/dev/null 2>&1; then
    failure_paths_ok=false
fi
if [[ "$failure_paths_ok" == true ]]; then
    test_pass
else
    test_fail "a failed setup recheck left stale completion intact"
fi

test_case "documented provider recheck persists fresh success and clears stale completion on failure"
recheck_block="$(awk '
  /^After the selected provider is configured/ {in_step=1}
  in_step && /^```bash$/ {in_fence=1; next}
  in_step && in_fence && /^```$/ {exit}
  in_step && in_fence {print}
' "$SETUP")"
preaction_block="$(awk '
  /^Before showing provider instructions/ {in_step=1}
  in_step && /^```bash$/ {in_fence=1; next}
  in_step && in_fence && /^```$/ {exit}
  in_step && in_fence {print}
' "$SETUP")"
recheck_root="$TEST_TMP_DIR/recheck-provider"
recheck_home="$TEST_TMP_DIR/recheck-home"
mkdir -p "$recheck_root/scripts/helpers" "$recheck_home"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'status="${PREFLIGHT_STATUS:-missing}"' \
  'provider="${PREFLIGHT_PROVIDER:-codex}"' \
  'if [[ "$status" == available ]]; then reason=ready; else reason=auth-missing; fi' \
  'if [[ "${PREFLIGHT_MALFORMED_FIELD:-false}" == true ]]; then printf -v reason '\''%257s'\'' '\'''\''; reason="${reason// /x}"; fi' \
  'jq -cn --arg provider "$provider" --arg status "$status" --arg reason "$reason" '\''{check_kind:"static",results:[{provider:$provider,status:$status,reason_code:$reason,checked_at:"2026-09-06T02:00:00Z",duration_ms:1,remediation:"run codex login"}]}'\''' \
  > "$recheck_root/scripts/helpers/preflight.sh"
recheck_ok=true
complete_one_provider='setup_record verified "$SETUP_VERIFICATION" >/dev/null || exit $?
COMPLETE_REQUEST="$(jq -cn --arg host "$SETUP_HOST" --arg root "$SETUP_ROOT" --argjson revision "$SETUP_REVISION" '"'"'{schema_version:1,action:"complete",host:$host,plugin_root:$root,expected_revision:$revision}'"'"')"
printf '"'"'%s\n'"'"' "$COMPLETE_REQUEST" | python3 "$SETUP_STATE_HELPER" --input - >/dev/null'
complete_test_provider() {
    local target_home="$1"
    env HOME="$target_home" OCTO_ROOT="$PROJECT_ROOT" CODEX_SANDBOX=workspace-write \
        PREFLIGHT_STATUS=available RECHECK_ROOT="$recheck_root" \
        bash -c "$state_block"$'\n''SETUP_FLOW=one-provider'$'\n''SETUP_PROVIDER=codex'$'\n'"$selection_block"$'\n''OCTO_ROOT="$RECHECK_ROOT"'$'\n'"$recheck_block"$'\n'"$complete_one_provider" \
        >/dev/null 2>&1
}
preaction_home="$TEST_TMP_DIR/preaction-home"
mkdir -p "$preaction_home"
complete_test_provider "$preaction_home" || recheck_ok=false
preaction_readiness="$(PREFLIGHT_STATUS=missing bash "$recheck_root/scripts/helpers/preflight.sh" --json |
  python3 "$PROJECT_ROOT/scripts/helpers/readiness-contract.py" --input -)" || recheck_ok=false
if ! env HOME="$preaction_home" OCTO_ROOT="$PROJECT_ROOT" CODEX_SANDBOX=workspace-write \
    SETUP_FLOW=one-provider SETUP_PROVIDER=codex READINESS_JSON="$preaction_readiness" \
    bash -c "$state_block"$'\n'"$selection_block"$'\n'"$preaction_block" >/dev/null 2>&1; then
    recheck_ok=false
fi
preaction_receipt="$(find "$preaction_home/.claude-octopus/setup" -type f -name '*.json' -print -quit 2>/dev/null || true)"
if [[ -z "$preaction_receipt" ]] ||
   ! jq -e '.completed == false and .stage == "rechecked" and .verification.result == "failed" and .verification.reason_code == "auth-missing"' \
      "$preaction_receipt" >/dev/null 2>&1; then
    recheck_ok=false
fi

for menu_case in missing absent; do
    menu_home="$TEST_TMP_DIR/menu-$menu_case-home"
    mkdir -p "$menu_home"
    complete_test_provider "$menu_home" || recheck_ok=false
    menu_status=missing
    menu_provider=codex
    expected_menu_reason=auth-missing
    if [[ "$menu_case" == absent ]]; then
        menu_status=available
        menu_provider=agy
        expected_menu_reason=provider-absent-from-readiness-report
    fi
    if ! env HOME="$menu_home" OCTO_ROOT="$PROJECT_ROOT" CODEX_SANDBOX=workspace-write \
        PREFLIGHT_STATUS="$menu_status" PREFLIGHT_PROVIDER="$menu_provider" RECHECK_ROOT="$recheck_root" \
        bash -c "$state_block"$'\n''OCTO_ROOT="$RECHECK_ROOT"'$'\n'"$readiness_block" >/dev/null 2>&1; then
        recheck_ok=false
    fi
    menu_receipt="$(find "$menu_home/.claude-octopus/setup" -type f -name '*.json' -print -quit 2>/dev/null || true)"
    if [[ -z "$menu_receipt" ]] ||
       ! jq -e --arg reason "$expected_menu_reason" \
          '.completed == false and .stage == "rechecked" and .verification.result == "failed" and .verification.reason_code == $reason' \
          "$menu_receipt" >/dev/null 2>&1; then
        recheck_ok=false
    fi
done
if ! complete_test_provider "$recheck_home"; then
    recheck_ok=false
fi
set +e
env HOME="$recheck_home" OCTO_ROOT="$PROJECT_ROOT" CODEX_SANDBOX=workspace-write \
    PREFLIGHT_STATUS=missing RECHECK_ROOT="$recheck_root" \
    bash -c "$state_block"$'\n''SETUP_FLOW=one-provider'$'\n''SETUP_PROVIDER=codex'$'\n'"$selection_block"$'\n''OCTO_ROOT="$RECHECK_ROOT"'$'\n'"$recheck_block" \
    >/dev/null 2>&1
failed_recheck_rc=$?
set -e
recheck_receipt="$(find "$recheck_home/.claude-octopus/setup" -type f -name '*.json' -print -quit 2>/dev/null || true)"
if [[ "$failed_recheck_rc" -eq 0 || -z "$recheck_receipt" ]] ||
   ! jq -e '.flow == "one-provider" and .provider == "codex" and .stage == "rechecked" and .completed == false and .verification == {checked_at:"2026-09-06T02:00:00Z",reason_code:"auth-missing",result:"failed"}' \
      "$recheck_receipt" >/dev/null 2>&1; then
    recheck_ok=false
fi

malformed_recheck_home="$TEST_TMP_DIR/malformed-recheck-home"
mkdir -p "$malformed_recheck_home"
complete_test_provider "$malformed_recheck_home" || recheck_ok=false
set +e
env HOME="$malformed_recheck_home" OCTO_ROOT="$PROJECT_ROOT" CODEX_SANDBOX=workspace-write \
    PREFLIGHT_STATUS=available PREFLIGHT_MALFORMED_FIELD=true RECHECK_ROOT="$recheck_root" \
    bash -c "$state_block"$'\n''SETUP_FLOW=one-provider'$'\n''SETUP_PROVIDER=codex'$'\n'"$selection_block"$'\n''OCTO_ROOT="$RECHECK_ROOT"'$'\n'"$recheck_block" \
    >/dev/null 2>&1
malformed_recheck_rc=$?
set -e
malformed_recheck_receipt="$(find "$malformed_recheck_home/.claude-octopus/setup" -type f -name '*.json' -print -quit 2>/dev/null || true)"
if [[ "$malformed_recheck_rc" -eq 0 || -z "$malformed_recheck_receipt" ]] ||
   ! jq -e '.completed == false and .stage == "rechecked" and .verification.result == "failed" and .verification.reason_code == "readiness-check-failed"' \
      "$malformed_recheck_receipt" >/dev/null 2>&1; then
    recheck_ok=false
fi
if [[ "$recheck_ok" == true ]]; then
    test_pass
else
    test_fail "provider recheck used stale evidence or left completion intact"
fi

test_case "interrupted and persistence-failed receipts resume through a legal recheck"
resume_ok=true
for stopped_stage in awaiting-human verified; do
    resume_home="$TEST_TMP_DIR/resume-$stopped_stage"
    mkdir -p "$resume_home"
    common="$(jq -cn --arg root "$PROJECT_ROOT" \
      '{schema_version:1,host:"codex",plugin_root:$root}')"
    receipt="$(jq -c '. + {action:"record",expected_revision:0,flow:"one-provider",provider:"codex",stage:"selected",verification:null}' <<<"$common" |
      HOME="$resume_home" python3 "$PROJECT_ROOT/scripts/helpers/setup-state.py" --input -)" || resume_ok=false
    revision="$(jq -r '.revision' <<<"$receipt")"
    if [[ "$stopped_stage" == awaiting-human ]]; then
        receipt="$(jq -c --argjson revision "$revision" '. + {action:"record",expected_revision:$revision,flow:"one-provider",provider:"codex",stage:"awaiting-human",verification:null}' <<<"$common" |
          HOME="$resume_home" python3 "$PROJECT_ROOT/scripts/helpers/setup-state.py" --input -)" || resume_ok=false
    else
        verification='{"result":"passed","reason_code":"ready","checked_at":"2026-09-06T00:00:00Z"}'
        for stage in rechecked verified; do
            receipt="$(jq -c --arg stage "$stage" --argjson revision "$(jq -r '.revision' <<<"$receipt")" --argjson verification "$verification" \
              '. + {action:"record",expected_revision:$revision,flow:"one-provider",provider:"codex",stage:$stage,verification:$verification}' <<<"$common" |
              HOME="$resume_home" python3 "$PROJECT_ROOT/scripts/helpers/setup-state.py" --input -)" || resume_ok=false
        done
    fi
    before="$(jq -r '.revision' <<<"$receipt")"
    resumed="$(env HOME="$resume_home" SETUP_STATE_HELPER="$PROJECT_ROOT/scripts/helpers/setup-state.py" \
      SETUP_HOST=codex SETUP_ROOT="$PROJECT_ROOT" SETUP_RECEIPT="$receipt" SETUP_REVISION="$before" \
      SETUP_FLOW=one-provider SETUP_PROVIDER=codex \
      bash -c 'eval "$1"; printf "%s\n" "$SETUP_REVISION"' bash "$selection_block")" || resume_ok=false
    if [[ "$resumed" != "$before" ]]; then
        resume_ok=false
    fi
    verification='{"result":"passed","reason_code":"ready","checked_at":"2026-09-06T01:00:00Z"}'
    if ! jq -cn --arg root "$PROJECT_ROOT" --argjson revision "$before" --argjson verification "$verification" \
      '{schema_version:1,action:"record",host:"codex",plugin_root:$root,expected_revision:$revision,flow:"one-provider",provider:"codex",stage:"rechecked",verification:$verification}' |
      HOME="$resume_home" python3 "$PROJECT_ROOT/scripts/helpers/setup-state.py" --input - >/dev/null; then
        resume_ok=false
    fi
done
if [[ "$resume_ok" == true ]]; then
    test_pass
else
    test_fail "an existing receipt was rewritten to selected or could not recheck"
fi

test_summary
