#!/usr/bin/env bash
# Focused contract coverage for install readiness and lightweight hook profiles.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
# shellcheck source=tests/helpers/test-framework.sh
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Install readiness and lightweight profiles"

LIFECYCLE_LIB="$PROJECT_ROOT/scripts/lib/lifecycle.sh"
CAPABILITIES="$PROJECT_ROOT/scripts/capabilities.sh"
CACHE_CHECK="$PROJECT_ROOT/scripts/cache-check.sh"
REPAIR="$PROJECT_ROOT/scripts/repair.sh"
SECURITY_AUDIT="$PROJECT_ROOT/scripts/security-audit.sh"
PROFILE="$PROJECT_ROOT/scripts/profile.sh"
HANDOFF="$PROJECT_ROOT/scripts/handoff.sh"

portable_file_mode() {
    local path="$1" value=""
    if value="$(stat -f '%Lp' "$path" 2>/dev/null)"; then
        printf '%s\n' "$value"
        return 0
    fi
    if value="$(stat -c '%a' "$path" 2>/dev/null)"; then
        printf '%s\n' "$value"
        return 0
    fi
    return 1
}

test_case "lifecycle state keeps Claude and Codex records separate"
home="$TEST_TMP_DIR/lifecycle-home"
state="$home/.claude-octopus/install-state.json"
mkdir -p "$home"
if HOME="$home" OCTOPUS_INSTALL_STATE_FILE="$state" bash -c '
    set -euo pipefail
    source "$1"
    OCTOPUS_HOST=claude CLAUDE_PLUGIN_ROOT="$2" OCTOPUS_INSTALL_SCOPE=user \
        octo_lifecycle_record_install
    OCTOPUS_HOST=codex CODEX_PLUGIN_ROOT="$2" OCTOPUS_INSTALL_SCOPE=project \
        octo_lifecycle_record_install
' _ "$LIFECYCLE_LIB" "$PROJECT_ROOT" 2>/dev/null &&
   jq -e '.schema == 2 and .hosts.claude.install_scope == "user" and
          .hosts.codex.install_scope == "project"' "$state" >/dev/null; then
    test_pass
else
    test_fail "host-scoped lifecycle state was not preserved"
fi

test_case "lifecycle state becomes stale when the loaded root changes"
root_a="$TEST_TMP_DIR/root-a"
root_b="$TEST_TMP_DIR/root-b"
mkdir -p "$root_a/.claude-plugin" "$root_b/.claude-plugin"
printf '%s\n' '{"version":"1.0.0"}' > "$root_a/.claude-plugin/plugin.json"
printf '%s\n' '{"version":"1.0.0"}' > "$root_b/.claude-plugin/plugin.json"
stale_result="$(HOME="$home" OCTOPUS_INSTALL_STATE_FILE="$state" OCTOPUS_HOST=claude \
    CLAUDE_PLUGIN_ROOT="$root_b" bash -c 'source "$1"; if octo_lifecycle_state_valid; then echo valid; else echo stale; fi' \
    _ "$LIFECYCLE_LIB" 2>/dev/null || true)"
if [[ "$stale_result" == "stale" ]]; then test_pass; else test_fail "changed root remained valid: $stale_result"; fi

test_case "lifecycle state detects version, scope, and profile changes"
fresh_home="$TEST_TMP_DIR/freshness-home"
fresh_root="$TEST_TMP_DIR/freshness-root"
fresh_state="$fresh_home/.claude-octopus/install-state.json"
mkdir -p "$fresh_home" "$fresh_root/.claude-plugin"
printf '%s\n' '{"version":"1.0.0"}' > "$fresh_root/.claude-plugin/plugin.json"
freshness_failures=0
HOME="$fresh_home" OCTOPUS_INSTALL_STATE_FILE="$fresh_state" OCTOPUS_HOST=claude \
    CLAUDE_PLUGIN_ROOT="$fresh_root" OCTOPUS_INSTALL_SCOPE=user OCTOPUS_CONTEXT_PROFILE=core \
    bash -c 'source "$1"; octo_lifecycle_record_install' _ "$LIFECYCLE_LIB" 2>/dev/null || \
    freshness_failures=$((freshness_failures + 1))
printf '%s\n' '{"version":"2.0.0"}' > "$fresh_root/.claude-plugin/plugin.json"
HOME="$fresh_home" OCTOPUS_INSTALL_STATE_FILE="$fresh_state" OCTOPUS_HOST=claude \
    CLAUDE_PLUGIN_ROOT="$fresh_root" OCTOPUS_INSTALL_SCOPE=user OCTOPUS_CONTEXT_PROFILE=core \
    bash -c 'source "$1"; ! octo_lifecycle_state_valid' _ "$LIFECYCLE_LIB" 2>/dev/null || \
    freshness_failures=$((freshness_failures + 1))
printf '%s\n' '{"version":"1.0.0"}' > "$fresh_root/.claude-plugin/plugin.json"
HOME="$fresh_home" OCTOPUS_INSTALL_STATE_FILE="$fresh_state" OCTOPUS_HOST=claude \
    CLAUDE_PLUGIN_ROOT="$fresh_root" OCTOPUS_INSTALL_SCOPE=project OCTOPUS_CONTEXT_PROFILE=core \
    bash -c 'source "$1"; ! octo_lifecycle_state_valid' _ "$LIFECYCLE_LIB" 2>/dev/null || \
    freshness_failures=$((freshness_failures + 1))
HOME="$fresh_home" OCTOPUS_INSTALL_STATE_FILE="$fresh_state" OCTOPUS_HOST=claude \
    CLAUDE_PLUGIN_ROOT="$fresh_root" OCTOPUS_INSTALL_SCOPE=user OCTOPUS_CONTEXT_PROFILE=orchestration \
    bash -c 'source "$1"; ! octo_lifecycle_state_valid' _ "$LIFECYCLE_LIB" 2>/dev/null || \
    freshness_failures=$((freshness_failures + 1))
if [[ "$freshness_failures" -eq 0 ]]; then test_pass; else test_fail "$freshness_failures freshness checks failed"; fi

test_case "SessionStart refreshes stale install metadata without blocking"
mkdir -p "$home/.claude-octopus"
printf '%s\n' '{}' > "$home/.claude-octopus/.setup-complete"
printf '%s\n' '{"schema":2,"hosts":{"claude":{"plugin_root":"/stale"}}}' > "$state"
HOME="$home" OCTOPUS_INSTALL_STATE_FILE="$state" OCTOPUS_HOST=claude \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" OCTOPUS_CONTEXT_PROFILE=core \
    bash "$PROJECT_ROOT/hooks/session-start-memory.sh" <<< '{"session_id":"readiness-session"}' >/dev/null 2>&1 || true
if jq -e --arg root "$PROJECT_ROOT" '.hosts.claude.plugin_root == $root' "$state" >/dev/null; then
    test_pass
else
    test_fail "SessionStart left stale install metadata"
fi

test_case "repair dry-run reports a broken stable link without changing it"
repair_home="$TEST_TMP_DIR/repair-home"
mkdir -p "$repair_home/.claude-octopus"
ln -s "$repair_home/missing-version" "$repair_home/.claude-octopus/plugin"
before="$(readlink "$repair_home/.claude-octopus/plugin")"
repair_json="$(HOME="$repair_home" OCTOPUS_STABLE_PLUGIN_ROOT="$repair_home/.claude-octopus/plugin" \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" "$REPAIR" --dry-run --json 2>/dev/null || true)"
after="$(readlink "$repair_home/.claude-octopus/plugin")"
if [[ "$before" == "$after" ]] && [[ "$(jq -r '.status' <<<"$repair_json" 2>/dev/null)" == "broken" ]]; then
    test_pass
else
    test_fail "dry-run mutated or misclassified the broken link"
fi

test_case "repair apply replaces a broken stable link through the shared root helper"
if HOME="$repair_home" OCTOPUS_STABLE_PLUGIN_ROOT="$repair_home/.claude-octopus/plugin" \
      OCTOPUS_INSTALL_STATE_FILE="$repair_home/.claude-octopus/install-state.json" \
      CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" "$REPAIR" --apply --json >/dev/null 2>&1 &&
   [[ "$(cd "$repair_home/.claude-octopus/plugin" && pwd -P)" == "$PROJECT_ROOT" ]]; then
    test_pass
else
    test_fail "broken stable link was not repaired"
fi

test_case "repair apply replaces a self-referential stable link"
self_home="$TEST_TMP_DIR/self-link-home"
mkdir -p "$self_home/.claude-octopus"
ln -s "$self_home/.claude-octopus/plugin" "$self_home/.claude-octopus/plugin"
if HOME="$self_home" OCTOPUS_STABLE_PLUGIN_ROOT="$self_home/.claude-octopus/plugin" \
      OCTOPUS_INSTALL_STATE_FILE="$self_home/.claude-octopus/install-state.json" \
      CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" "$REPAIR" --apply --json >/dev/null 2>&1 &&
   [[ "$(cd "$self_home/.claude-octopus/plugin" && pwd -P)" == "$PROJECT_ROOT" ]]; then
    test_pass
else
    test_fail "self-referential stable link was not repaired"
fi

test_case "repair detects and refreshes a stale script shim"
shim_home="$TEST_TMP_DIR/stale-shim-home"
shim_old="$TEST_TMP_DIR/stale-shim-old"
shim_root="$shim_home/.claude-octopus/plugin"
mkdir -p "$shim_root/scripts" "$shim_old/scripts"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$shim_old/scripts/orchestrate.sh"
printf -v shim_old_quoted '%q' "$shim_old/scripts/orchestrate.sh"
printf '%s\n' '#!/usr/bin/env bash' "exec $shim_old_quoted \"\$@\"" > "$shim_root/scripts/orchestrate.sh"
chmod +x "$shim_old/scripts/orchestrate.sh" "$shim_root/scripts/orchestrate.sh"
shim_dry_json="$(HOME="$shim_home" OCTOPUS_STABLE_PLUGIN_ROOT="$shim_root" \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" "$REPAIR" --dry-run --json 2>/dev/null || true)"
shim_apply_json="$(HOME="$shim_home" OCTOPUS_STABLE_PLUGIN_ROOT="$shim_root" \
    OCTOPUS_INSTALL_STATE_FILE="$shim_home/.claude-octopus/install-state.json" \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" "$REPAIR" --apply --json 2>/dev/null || true)"
if [[ "$(jq -r '.status' <<<"$shim_dry_json" 2>/dev/null)" == "mismatch" ]] &&
   [[ "$(jq -r '.status' <<<"$shim_apply_json" 2>/dev/null)" == "shim" ]] &&
   grep -F "$PROJECT_ROOT/scripts/orchestrate.sh" "$shim_root/scripts/orchestrate.sh" >/dev/null 2>&1; then
    test_pass
else
    test_fail "stale script shim was not detected and refreshed"
fi

test_case "repair refuses an unowned regular file without changing it"
blocked_home="$TEST_TMP_DIR/blocked-repair-home"
mkdir -p "$blocked_home/.claude-octopus"
printf '%s\n' 'keep this file' > "$blocked_home/.claude-octopus/plugin"
blocked_rc=0
HOME="$blocked_home" OCTOPUS_STABLE_PLUGIN_ROOT="$blocked_home/.claude-octopus/plugin" \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" "$REPAIR" --apply --json \
    > "$TEST_TMP_DIR/blocked-repair.json" 2>/dev/null || blocked_rc=$?
if [[ "$blocked_rc" -ne 0 ]] && [[ "$(cat "$blocked_home/.claude-octopus/plugin")" == "keep this file" ]] &&
   jq -e '.result == "blocked" and .status == "invalid"' \
      "$TEST_TMP_DIR/blocked-repair.json" >/dev/null 2>&1; then
    test_pass
else
    test_fail "repair changed or accepted an unowned regular file (exit=$blocked_rc)"
fi

test_case "repair human output explains install-state write failures"
repair_state_rc=0
repair_state_output="$(HOME="$repair_home" \
    OCTOPUS_STABLE_PLUGIN_ROOT="$repair_home/.claude-octopus/plugin" \
    OCTOPUS_INSTALL_STATE_FILE="/dev/null/install-state.json" \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" "$REPAIR" --apply 2>/dev/null)" || repair_state_rc=$?
if [[ "$repair_state_rc" -ne 0 ]] &&
   grep -Fq 'result: state-write-failed' <<<"$repair_state_output"; then
    test_pass
else
    test_fail "repair hid the state-write-failed result (exit=$repair_state_rc)"
fi

test_case "capabilities render shared readiness states, not guessed auth booleans"
cap_home="$TEST_TMP_DIR/capabilities-home"
cap_bin="$TEST_TMP_DIR/capabilities-bin"
mkdir -p "$cap_home" "$cap_bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$cap_bin/qwen"
chmod +x "$cap_bin/qwen"
cap_json="$(HOME="$cap_home" PATH="$cap_bin:$PATH" QWEN_API_KEY='' \
    "$CAPABILITIES" --json 2>/dev/null || true)"
if jq -e '.providers[] | select(.id == "qwen") |
          .status == "degraded" and .reason_code == "auth-missing" and
          (has("auth_ready") | not)' <<<"$cap_json" >/dev/null 2>&1; then
    test_pass
else
    test_fail "capability output bypassed provider readiness: ${cap_json:-<empty>}"
fi

test_case "core profile suppresses optional context reinforcement in a real hook run"
hook_home="$TEST_TMP_DIR/hook-home"
mkdir -p "$hook_home/.claude-octopus"
printf '%s\n' '{"host_session_id":"hook-session","status":"active","current_phase":"develop"}' \
    > "$hook_home/.claude-octopus/session.json"
core_output="$(printf '%s' '{"session_id":"hook-session"}' | HOME="$hook_home" \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" OCTOPUS_CONTEXT_PROFILE=core \
    bash "$PROJECT_ROOT/hooks/context-reinforcement.sh" 2>/dev/null || true)"
workflow_output="$(printf '%s' '{"session_id":"hook-session"}' | HOME="$hook_home" \
    CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" OCTOPUS_CONTEXT_PROFILE=orchestration \
    bash "$PROJECT_ROOT/hooks/context-reinforcement.sh" 2>/dev/null || true)"
if [[ -z "$core_output" ]] && jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' \
      <<<"$workflow_output" >/dev/null 2>&1; then
    test_pass
else
    test_fail "profile did not gate real hook execution"
fi

test_case "orchestration profile activates post-tool coordination only for an active workflow"
post_session="profile-post-tool-$$"
post_state="/tmp/octopus-failures-${post_session}.json"
rm -f "$post_state"
post_input="$(jq -cn --arg session "$post_session" \
    '{session_id:$session,tool_name:"Bash",exit_code:1,result:"error: fixture failure"}')"
printf '%s\n' "$post_input" | HOME="$hook_home" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" \
    CLAUDE_SESSION_ID="$post_session" OCTOPUS_CONTEXT_PROFILE=core \
    bash "$PROJECT_ROOT/hooks/post-tool-dispatch.sh" >/dev/null 2>&1 || true
core_created=false
[[ -e "$post_state" ]] && core_created=true
printf '%s\n' "$(jq -cn --arg session "$post_session" \
    '{host_session_id:$session,status:"active",current_phase:"develop"}')" \
    > "$hook_home/.claude-octopus/session.json"
printf '%s\n' "$post_input" | HOME="$hook_home" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" \
    CLAUDE_SESSION_ID="$post_session" OCTOPUS_CONTEXT_PROFILE=orchestration \
    bash "$PROJECT_ROOT/hooks/post-tool-dispatch.sh" >/dev/null 2>&1 || true
if [[ "$core_created" == false ]] &&
   jq -e '.bash.consecutive == 1' "$post_state" >/dev/null 2>&1; then
    test_pass
else
    test_fail "profile did not control real post-tool coordination"
fi
rm -f "$post_state"

test_case "profile-managed hooks fail closed when their registry is unavailable"
missing_profile_config="$TEST_TMP_DIR/missing-hook-profiles.json"
profile_gate_rc=0
HOME="$hook_home" OCTOPUS_CONTEXT_PROFILE=full \
    OCTOPUS_HOOK_PROFILE_CONFIG="$missing_profile_config" \
    bash -c 'source "$1"; octo_hook_profile_allows context-reinforcement' \
    _ "$PROJECT_ROOT/scripts/lib/hook-activation.sh" >/dev/null 2>&1 || profile_gate_rc=$?
if [[ "$profile_gate_rc" -ne 0 ]]; then
    test_pass
else
    test_fail "full profile bypassed the missing registry"
fi

test_case "profile reports failure when its setting cannot be persisted"
profile_rc=0
HOME=/dev/null "$PROFILE" orchestration >/dev/null 2>&1 || profile_rc=$?
if [[ "$profile_rc" -ne 0 ]]; then test_pass; else test_fail "profile claimed an impossible write succeeded"; fi

test_case "security audit exits nonzero when the hook manifest fails"
audit_root="$TEST_TMP_DIR/audit-root"
mkdir -p "$audit_root/hooks" "$audit_root/scripts"
printf '%s\n' '{invalid' > "$audit_root/hooks/hooks.json"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$audit_root/scripts/ok.sh"
audit_rc=0
OCTOPUS_SECURITY_AUDIT_ROOT="$audit_root" "$SECURITY_AUDIT" --json \
    > "$TEST_TMP_DIR/audit.json" 2>/dev/null || audit_rc=$?
if [[ "$audit_rc" -ne 0 ]] && jq -e '.checks[] | select(.name == "hooks-manifest" and .status == "fail")' \
      "$TEST_TMP_DIR/audit.json" >/dev/null 2>&1; then
    test_pass
else
    test_fail "invalid hook manifest did not fail the audit (exit=$audit_rc)"
fi

test_case "security audit rejects malformed present Cursor and Factory manifests"
adapter_audit_failures=0
for adapter_manifest in .cursor-plugin/plugin.json .factory-plugin/plugin.json; do
    adapter_root="$TEST_TMP_DIR/audit-${adapter_manifest%%/*}"
    mkdir -p "$adapter_root/hooks" "$adapter_root/scripts" \
        "$adapter_root/$(dirname "$adapter_manifest")"
    printf '%s\n' '{"hooks":{}}' > "$adapter_root/hooks/hooks.json"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$adapter_root/scripts/ok.sh"
    printf '%s\n' '{invalid' > "$adapter_root/$adapter_manifest"
    adapter_rc=0
    OCTOPUS_SECURITY_AUDIT_ROOT="$adapter_root" "$SECURITY_AUDIT" --json \
        > "$adapter_root/audit.json" 2>/dev/null || adapter_rc=$?
    if [[ "$adapter_rc" -eq 0 ]] ||
       ! jq -e '.checks[] | select(.name == "plugin-manifests" and .status == "fail")' \
           "$adapter_root/audit.json" >/dev/null 2>&1; then
        adapter_audit_failures=$((adapter_audit_failures + 1))
    fi
done
if [[ "$adapter_audit_failures" -eq 0 ]]; then
    test_pass
else
    test_fail "$adapter_audit_failures adapter manifest audit(s) accepted malformed JSON"
fi

test_case "cache check validates the active cache rather than only the newest directory"
cache_home="$TEST_TMP_DIR/cache-home"
claude_cache="$cache_home/.claude/plugins/cache/nyldn-plugins/octo"
codex_cache="$cache_home/.codex/plugins/cache/nyldn-plugins/claude-octopus"
mkdir -p "$claude_cache/1.0.0/.claude-plugin" "$claude_cache/2.0.0/.claude-plugin" "$codex_cache"
printf '%s\n' '{invalid' > "$claude_cache/1.0.0/.claude-plugin/plugin.json"
printf '%s\n' '{"version":"2.0.0","commands":[],"skills":[]}' > "$claude_cache/2.0.0/.claude-plugin/plugin.json"
mkdir -p "$claude_cache/2.0.0/scripts"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$claude_cache/2.0.0/scripts/orchestrate.sh"
chmod +x "$claude_cache/2.0.0/scripts/orchestrate.sh"
cache_rc=0
HOME="$cache_home" CLAUDE_PLUGIN_ROOT="$claude_cache/1.0.0" \
    OCTOPUS_STABLE_PLUGIN_ROOT="$cache_home/.claude-octopus/plugin" \
    "$CACHE_CHECK" --json > "$TEST_TMP_DIR/cache.json" 2>/dev/null || cache_rc=$?
if [[ "$cache_rc" -ne 0 ]] && jq -e '
      any(.checks[]; .host == "claude" and .version == "1.0.0" and
          .role == "active" and .status == "fail") and
      any(.checks[]; .host == "claude" and .version == "2.0.0" and
          .role == "newest" and .status == "pass")' \
      "$TEST_TMP_DIR/cache.json" >/dev/null 2>&1; then
    test_pass
else
    test_fail "active invalid cache was not reported (exit=$cache_rc)"
fi

test_case "portable mode lookup discards output from a failed stat probe"
stat_bin="$TEST_TMP_DIR/stat-bin"
mkdir -p "$stat_bin"
# shellcheck disable=SC2016 # Keep parameter expansion inside the generated fixture.
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ "$1" == -f ]]; then printf "filesystem details\\n"; exit 1; fi' \
    'if [[ "$1" == -c ]]; then printf "600\\n"; exit 0; fi' \
    'exit 2' > "$stat_bin/stat"
chmod +x "$stat_bin/stat"
mode="$(PATH="$stat_bin:$PATH" portable_file_mode "$TEST_TMP_DIR/unused")"
if [[ "$mode" == "600" ]]; then
    test_pass
else
    test_fail "failed stat probe polluted fallback mode: $mode"
fi

test_case "portable handoff export is structured, private, and redacted"
handoff_home="$TEST_TMP_DIR/handoff-home"
mkdir -p "$handoff_home/data"
printf '%s\n' '{"workflow":"develop","current_phase":"build","status":"running","decisions":["OPENAI_API_KEY=do-not-export"]}' \
    > "$handoff_home/data/session.json"
handoff_file="$TEST_TMP_DIR/portable-handoff.json"
handoff_json="$(HOME="$handoff_home" CLAUDE_PLUGIN_DATA="$handoff_home/data" \
    OCTOPUS_PROJECT_DIR="$PROJECT_ROOT" "$HANDOFF" export --json --out "$handoff_file" \
    2>/dev/null || true)"
mode="$(portable_file_mode "$handoff_file" || true)"
if jq -e '.workflow == "develop" and .phase == "build" and
          (tostring | contains("do-not-export") | not)' <<<"$handoff_json" >/dev/null 2>&1 &&
   [[ "$mode" == "600" ]]; then
    test_pass
else
    test_fail "portable handoff was missing, unredacted, or not private"
fi

test_case "handoff project ID follows the lifecycle producer contract"
expected_handoff_id="$(bash -c 'source "$1"; octo_lifecycle_handoff_id "$2"' \
    _ "$LIFECYCLE_LIB" "$PROJECT_ROOT")"
if jq -e --arg expected "$expected_handoff_id" '.project_id == $expected' \
      <<<"$handoff_json" >/dev/null 2>&1; then
    test_pass
else
    test_fail "handoff project ID diverged from octo_lifecycle_handoff_id"
fi

test_case "handoff preserves existing output directory permissions"
handoff_out="$TEST_TMP_DIR/shared-output"
mkdir -p "$handoff_out"
chmod 755 "$handoff_out"
HOME="$handoff_home" CLAUDE_PLUGIN_DATA="$handoff_home/data" \
    "$HANDOFF" export --out "$handoff_out/checkpoint.json" >/dev/null 2>&1
mode="$(portable_file_mode "$handoff_out")"
if [[ "$mode" == 755 ]]; then test_pass; else test_fail "changed existing directory permissions to $mode"; fi

test_case "handoff rejects a directory as the output file"
handoff_rc=0
HOME="$handoff_home" "$HANDOFF" export --out "$handoff_out" >/dev/null 2>&1 || handoff_rc=$?
if [[ "$handoff_rc" -ne 0 ]]; then test_pass; else test_fail "directory destination was accepted"; fi

test_case "handoff validates summary field types and redacts every exported string"
printf '%s\n' '{"workflow":{"token":"private-value"},"status":"token=private-status","decisions":"unexpected","blockers":[{"token":"private-object"}]}' \
    > "$handoff_home/data/session.json"
handoff_json="$(HOME="$handoff_home" CLAUDE_PLUGIN_DATA="$handoff_home/data" \
    "$HANDOFF" export --json 2>/dev/null || true)"
if jq -e '.workflow == "none" and .decisions == [] and .blockers == [] and
    (tostring | contains("private-") | not)' <<<"$handoff_json" >/dev/null 2>&1; then
    test_pass
else
    test_fail "invalid or sensitive summary fields escaped the export schema"
fi

test_case "handoff uses canonical project decisions and suppresses secret-bearing notes"
project_state="$TEST_TMP_DIR/project-state"
mkdir -p "$project_state"
printf '%s\n' '{"current_workflow":"develop","current_phase":"deliver","decisions":[{"decision":"Keep SQLite","rationale":"Fits the workload"},{"decision":"AWS_SECRET_ACCESS_KEY=private-aws"},{"decision":"{\"password\":\"private-pass word\"}"}],"blockers":[{"description":"Need design approval","status":"active"},{"description":"Already resolved","status":"resolved"}]}' > "$project_state/state.json"
handoff_json="$(HOME="$handoff_home" CLAUDE_PLUGIN_DATA="$handoff_home/data" OCTOPUS_WORKFLOW_STATE_DIR="$project_state" \
    "$HANDOFF" export --json 2>/dev/null || true)"
if jq -e '.workflow == "develop" and .phase == "deliver" and
    (.decisions | index("Keep SQLite")) != null and .blockers == ["Need design approval"] and
    (has("resume_command") | not) and (tostring | contains("private-") | not)' <<<"$handoff_json" >/dev/null 2>&1; then
    test_pass
else
    test_fail "handoff missed canonical state or exported sensitive notes"
fi

test_case "explicit hook profile overrides the context profile"
profile_name="$(OCTOPUS_CONTEXT_PROFILE=core OCTOPUS_HOOK_PROFILE=full bash -c 'source "$1"; octo_hook_profile' _ "$PROJECT_ROOT/scripts/lib/hook-activation.sh")"
if [[ "$profile_name" == full ]]; then test_pass; else test_fail "explicit hook profile did not win"; fi

test_case "new diagnostic CLIs reject unknown arguments"
cli_failures=0
for cli in "$CAPABILITIES" "$CACHE_CHECK" "$REPAIR" "$SECURITY_AUDIT" "$PROFILE" "$HANDOFF"; do
    rc=0
    "$cli" --not-a-real-option >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 2 ]] || cli_failures=$((cli_failures + 1))
done
rc=0
"$PROJECT_ROOT/scripts/orchestrate.sh" install-state nonsense >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] || cli_failures=$((cli_failures + 1))
if [[ "$cli_failures" -eq 0 ]]; then test_pass; else test_fail "$cli_failures CLI(s) accepted invalid arguments"; fi

test_case "orchestrator exposes diagnostics without generic workflow initialization"
orchestrator_home="$TEST_TMP_DIR/orchestrator-home"
mkdir -p "$orchestrator_home"
orchestrator_json="$(HOME="$orchestrator_home" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" \
    "$PROJECT_ROOT/scripts/orchestrate.sh" capabilities --json 2>/dev/null || true)"
doctor_json="$(HOME="$orchestrator_home" CLAUDE_PLUGIN_ROOT="$PROJECT_ROOT" \
    "$PROJECT_ROOT/scripts/orchestrate.sh" doctor installation --json 2>/dev/null || true)"
if jq -e '.providers | type == "array"' <<<"$orchestrator_json" >/dev/null 2>&1 &&
   jq -e '.results[] | select(.category == "installation")' <<<"$doctor_json" >/dev/null 2>&1 &&
   [[ ! -d "$orchestrator_home/.claude-octopus/results" ]]; then
    test_pass
else
    test_fail "diagnostic dispatch was missing or initialized workflow state"
fi

test_case "installed octopus CLI exposes the readiness commands and rejects unknown commands"
bin_failures=0
for command in capabilities cache-check repair security-audit handoff profile; do
    bin_help="$("$PROJECT_ROOT/bin/octopus" "$command" --help 2>/dev/null || true)"
    [[ "$bin_help" == *"Usage:"* && "$bin_help" == *"$command"* ]] || bin_failures=$((bin_failures + 1))
done
bin_unknown_rc=0
"$PROJECT_ROOT/bin/octopus" definitely-not-a-command >/dev/null 2>&1 || bin_unknown_rc=$?
if [[ "$bin_failures" -eq 0 && "$bin_unknown_rc" -eq 2 ]]; then
    test_pass
else
    test_fail "CLI dispatch failures=$bin_failures unknown-exit=$bin_unknown_rc"
fi

test_summary
