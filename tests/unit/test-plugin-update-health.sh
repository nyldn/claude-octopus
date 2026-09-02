#!/usr/bin/env bash
# Regression coverage for issue #851: stale installs must be visible without
# allowing SessionStart hooks to run package managers, network clients, or auth.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=tests/helpers/test-framework.sh
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Plugin update health (#851)"

LIB="$PROJECT_ROOT/scripts/lib/plugin-update.sh"
HOOK="$PROJECT_ROOT/hooks/plugin-update-advisory.sh"

test_case "plugin update library exists"
if [[ -r "$LIB" ]]; then test_pass; else test_fail "$LIB is missing"; fi

test_case "plugin update advisory hook is executable"
if [[ -x "$HOOK" ]]; then test_pass; else test_fail "$HOOK is not executable"; fi

# shellcheck source=/dev/null
source "$LIB"

PLUGIN_ROOT="$TEST_TMP_DIR/plugin"
CURRENT_PLUGIN_ROOT="$TEST_TMP_DIR/current-plugin"
CLAUDE_DIR="$TEST_TMP_DIR/claude"
CODEX_DIR="$TEST_TMP_DIR/codex"
STATE_DIR="$TEST_TMP_DIR/state"
CURRENT_STATE_DIR="$TEST_TMP_DIR/current-state"
FAKE_BIN="$TEST_TMP_DIR/bin"
CALL_LOG="$TEST_TMP_DIR/forbidden-calls.log"
mkdir -p "$PLUGIN_ROOT/.claude-plugin" "$CURRENT_PLUGIN_ROOT/.claude-plugin" \
    "$CLAUDE_DIR/plugins/marketplaces/nyldn-plugins/.claude-plugin" \
    "$CLAUDE_DIR/plugins/cache/nyldn-plugins/octo/1.1.0" \
    "$CLAUDE_DIR/plugins/cache/nyldn-plugins/octo/1.2.0" \
    "$CODEX_DIR/plugins/marketplaces/nyldn-plugins/.claude-plugin" \
    "$CODEX_DIR/plugins/cache/nyldn-plugins/claude-octopus/1.1.0" \
    "$STATE_DIR" "$CURRENT_STATE_DIR" "$FAKE_BIN"

printf '{"version":"1.0.0"}\n' > "$PLUGIN_ROOT/.claude-plugin/plugin.json"
printf '{"version":"1.2.0"}\n' > "$CURRENT_PLUGIN_ROOT/.claude-plugin/plugin.json"
printf '%s\n' '{"plugins":{"octo@nyldn-plugins":[{"scope":"user","version":"1.1.0"}]}}' \
    > "$CLAUDE_DIR/plugins/installed_plugins.json"
printf '%s\n' '{"plugins":[{"name":"octo","version":"1.2.0"}]}' \
    > "$CLAUDE_DIR/plugins/marketplaces/nyldn-plugins/.claude-plugin/marketplace.json"
printf '%s\n' '{"plugins":{"claude-octopus@nyldn-plugins":[{"scope":"user","version":"1.1.0"}]}}' \
    > "$CODEX_DIR/plugins/installed_plugins.json"
printf '%s\n' '{"plugins":[{"name":"claude-octopus","version":"1.2.0"}]}' \
    > "$CODEX_DIR/plugins/marketplaces/nyldn-plugins/.claude-plugin/marketplace.json"

write_marketplace_state() {
    printf '%s\n' "$1" > "$CLAUDE_DIR/plugins/known_marketplaces.json"
}

write_marketplace_state '{"nyldn-plugins":{"autoUpdate":false}}'
OCTOPUS_CLAUDE_DIR="$CLAUDE_DIR"
export OCTOPUS_CLAUDE_DIR
octo_plugin_update_load "$PLUGIN_ROOT" claude

test_case "detects disabled third-party auto-update"
if assert_equals "disabled" "$OCTO_PLUGIN_AUTO_UPDATE"; then test_pass; fi
test_case "reads loaded plugin version"
if assert_equals "1.0.0" "$OCTO_PLUGIN_LOADED_VERSION"; then test_pass; fi
test_case "reads installed plugin version"
if assert_equals "1.1.0" "$OCTO_PLUGIN_INSTALLED_VERSION"; then test_pass; fi
test_case "reads locally refreshed catalog version"
if assert_equals "1.2.0" "$OCTO_PLUGIN_CATALOG_VERSION"; then test_pass; fi
test_case "finds newest cached version portably"
if assert_equals "1.2.0" "$OCTO_PLUGIN_CACHE_VERSION"; then test_pass; fi
test_case "selects newest locally known version"
if assert_equals "1.2.0" "$OCTO_PLUGIN_NEWEST_VERSION"; then test_pass; fi
test_case "flags locally known newer version"
if assert_equals "true" "$OCTO_PLUGIN_UPDATE_AVAILABLE"; then test_pass; fi
test_case "flags installed version newer than loaded session"
if assert_equals "true" "$OCTO_PLUGIN_RELOAD_REQUIRED"; then test_pass; fi

write_marketplace_state '{"nyldn-plugins":{"autoUpdate":true}}'
octo_plugin_update_load "$PLUGIN_ROOT" claude
test_case "detects enabled auto-update"
if assert_equals "enabled" "$OCTO_PLUGIN_AUTO_UPDATE"; then test_pass; fi

write_marketplace_state '{"nyldn-plugins":{"source":{"source":"git"}}}'
octo_plugin_update_load "$PLUGIN_ROOT" claude
test_case "detects missing auto-update preference"
if assert_equals "missing" "$OCTO_PLUGIN_AUTO_UPDATE"; then test_pass; fi

printf '{not-json\n' > "$CLAUDE_DIR/plugins/known_marketplaces.json"
octo_plugin_update_load "$PLUGIN_ROOT" claude
test_case "detects malformed marketplace state"
if assert_equals "malformed" "$OCTO_PLUGIN_AUTO_UPDATE"; then test_pass; fi

test_case "detects Claude host from installed path"
if assert_equals "claude" "$(octo_plugin_detect_host "/tmp/user/.claude/plugins/cache/nyldn-plugins/octo/1.0.0")"; then test_pass; fi
test_case "detects Codex host from installed path"
if assert_equals "codex" "$(octo_plugin_detect_host "/tmp/user/.codex/plugins/cache/nyldn-plugins/claude-octopus/1.0.0")"; then test_pass; fi

# Every executable that a SessionStart hook must never call records a marker.
# The selected host CLIs also update fixture metadata during explicit updates.
cat > "$FAKE_BIN/update-fixture-metadata" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
host="$1"
case "$host" in
    claude)
        root="$OCTOPUS_CLAUDE_DIR"
        name="octo"
        key="octo@nyldn-plugins"
        ;;
    codex)
        root="$OCTOPUS_CODEX_DIR"
        name="claude-octopus"
        key="claude-octopus@nyldn-plugins"
        ;;
    *) exit 64 ;;
esac
catalog="$root/plugins/marketplaces/nyldn-plugins/.claude-plugin/marketplace.json"
version="$(jq -r --arg name "$name" '.plugins[] | select(.name == $name) | .version' "$catalog")"
printf '{"plugins":{"%s":[{"scope":"user","version":"%s"}]}}\n' "$key" "$version" \
    > "$root/plugins/installed_plugins.json"
mkdir -p "$root/plugins/cache/nyldn-plugins/$name/$version"
EOF
chmod +x "$FAKE_BIN/update-fixture-metadata"

for command_name in claude codex curl wget npm npx git; do
    cat > "$FAKE_BIN/$command_name" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$0 $*" >> "$OCTO_TEST_CALL_LOG"
if [[ "${OCTO_TEST_UPDATE_MODE:-apply}" == "apply" ]]; then
    case "${0##*/}:$*" in
        "claude:plugin update octo@nyldn-plugins")
            "$OCTO_TEST_METADATA_UPDATER" claude
            ;;
        "codex:plugin add claude-octopus@nyldn-plugins")
            "$OCTO_TEST_METADATA_UPDATER" codex
            ;;
    esac
fi
exit 0
EOF
    chmod +x "$FAKE_BIN/$command_name"
done

cat > "$FAKE_BIN/ps" <<'EOF'
#!/usr/bin/env bash
format="$2"
pid="$4"
case "${OCTO_TEST_PS_MODE:-}:$pid:$format" in
    codex-tree:410:comm=) printf '/bin/zsh\n' ;;
    codex-tree:410:ppid=) printf '420\n' ;;
    codex-tree:420:comm=) printf '  /usr/local/bin/codex  \n' ;;
    codex-tree:420:ppid=) printf '1\n' ;;
    terminal-tree:410:comm=) printf '/bin/zsh\n' ;;
    terminal-tree:410:ppid=) printf '420\n' ;;
    terminal-tree:420:comm=) printf '/usr/sbin/sshd\n' ;;
    terminal-tree:420:ppid=) printf '1\n' ;;
    empty-comm:410:comm=) printf '   \n' ;;
    terminal-any:*:comm=) printf '/bin/zsh\n' ;;
    terminal-any:*:ppid=) printf '1\n' ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$FAKE_BIN/ps"

PROCESS_TEST_PATH="$PATH"
PATH="$FAKE_BIN:$PATH"
OCTO_TEST_PS_MODE=codex-tree
export OCTO_TEST_PS_MODE
test_case "process ancestry detects a running Codex session"
if octo_plugin_running_inside_codex 410; then test_pass; else test_fail "Codex ancestor was not detected"; fi

OCTO_TEST_PS_MODE=terminal-tree
export OCTO_TEST_PS_MODE
test_case "ordinary terminal ancestry is not a Codex session"
terminal_rc=0
octo_plugin_running_inside_codex 410 || terminal_rc=$?
if [[ "$terminal_rc" -eq 1 ]]; then test_pass; else test_fail "expected outside-session rc=1, got $terminal_rc"; fi
unset OCTO_TEST_PS_MODE
PATH="$PROCESS_TEST_PATH"

NO_PS_PATH="$TEST_TMP_DIR/no-ps-bin"
mkdir -p "$NO_PS_PATH"
PATH="$NO_PS_PATH"
missing_ps_rc=0
octo_plugin_running_inside_codex 410 || missing_ps_rc=$?
PATH="$PROCESS_TEST_PATH"
test_case "missing process inspector is reported as unknown"
if [[ "$missing_ps_rc" -eq 2 ]]; then test_pass; else test_fail "expected missing-ps rc=2, got $missing_ps_rc"; fi

ps() { return 127; }
test_case "failed process inspection is reported as unknown"
process_rc=0
octo_plugin_running_inside_codex 410 || process_rc=$?
if [[ "$process_rc" -eq 2 ]]; then test_pass; else test_fail "expected inspection rc=2, got $process_rc"; fi
unset -f ps

OCTO_TEST_PS_MODE=empty-comm
export OCTO_TEST_PS_MODE
empty_process_rc=0
octo_plugin_running_inside_codex 410 || empty_process_rc=$?
test_case "empty process inspection is reported as unknown"
if [[ "$empty_process_rc" -eq 2 ]]; then test_pass; else test_fail "expected empty-process rc=2, got $empty_process_rc"; fi
unset OCTO_TEST_PS_MODE

CODEX_SANDBOX=workspace-write
export CODEX_SANDBOX
test_case "Codex runtime environment identifies an active session"
if octo_plugin_running_inside_codex 410; then test_pass; else test_fail "CODEX_SANDBOX was not detected"; fi
unset CODEX_SANDBOX

write_marketplace_state '{"nyldn-plugins":{"autoUpdate":false}}'
touch "$STATE_DIR/.setup-complete"
HOOK_OUTPUT=$(env \
    "PATH=$FAKE_BIN:$PATH" \
    "CLAUDE_PLUGIN_ROOT=$PROJECT_ROOT" \
    "OCTOPUS_UPDATE_MANIFEST=$PLUGIN_ROOT/.claude-plugin/plugin.json" \
    "OCTOPUS_CLAUDE_DIR=$CLAUDE_DIR" \
    "OCTOPUS_STATE_DIR=$STATE_DIR" \
    "OCTOPUS_UPDATE_NOW=2000000000" \
    "OCTO_TEST_CALL_LOG=$CALL_LOG" \
    bash "$HOOK")

test_case "hook gives host UI remediation"
if assert_contains "$HOOK_OUTPUT" "Enable auto-update"; then test_pass; fi
test_case "hook explains loaded-session refresh"
if assert_contains "$HOOK_OUTPUT" "/reload-plugins"; then test_pass; fi
test_case "hook is user-visible and never directs model action"
if jq -e 'has("systemMessage") and (has("hookSpecificOutput") | not)' <<<"$HOOK_OUTPUT" >/dev/null 2>&1 \
   && ! grep -q 'Ask to run' <<<"$HOOK_OUTPUT"; then
    test_pass
else
    test_fail "update advisory should be a passive systemMessage: $HOOK_OUTPUT"
fi
test_case "SessionStart advisory performs no CLI or network calls"
if [[ ! -s "$CALL_LOG" ]]; then test_pass; else test_fail "advisory invoked forbidden tools"; fi

HOOK_OUTPUT_2=$(env \
    "PATH=$FAKE_BIN:$PATH" \
    "CLAUDE_PLUGIN_ROOT=$PROJECT_ROOT" \
    "OCTOPUS_UPDATE_MANIFEST=$PLUGIN_ROOT/.claude-plugin/plugin.json" \
    "OCTOPUS_CLAUDE_DIR=$CLAUDE_DIR" \
    "OCTOPUS_STATE_DIR=$STATE_DIR" \
    "OCTOPUS_UPDATE_NOW=2000000001" \
    "OCTO_TEST_CALL_LOG=$CALL_LOG" \
    bash "$HOOK")
test_case "unchanged advisory is suppressed during cooldown"
if assert_equals "" "$HOOK_OUTPUT_2"; then test_pass; fi

# Fully current, auto-updating installs stay quiet even without cooldown state.
printf '%s\n' '{"plugins":{"octo@nyldn-plugins":[{"scope":"user","version":"1.2.0"}]}}' \
    > "$CLAUDE_DIR/plugins/installed_plugins.json"
write_marketplace_state '{"nyldn-plugins":{"autoUpdate":true}}'
touch "$CURRENT_STATE_DIR/.setup-complete"
CURRENT_OUTPUT=$(env \
    "PATH=$FAKE_BIN:$PATH" \
    "CLAUDE_PLUGIN_ROOT=$PROJECT_ROOT" \
    "OCTOPUS_UPDATE_MANIFEST=$CURRENT_PLUGIN_ROOT/.claude-plugin/plugin.json" \
    "OCTOPUS_CLAUDE_DIR=$CLAUDE_DIR" \
    "OCTOPUS_STATE_DIR=$CURRENT_STATE_DIR" \
    "OCTOPUS_UPDATE_NOW=2000000000" \
    "OCTO_TEST_CALL_LOG=$CALL_LOG" \
    bash "$HOOK")
test_case "current auto-updating install gets no startup advisory"
if assert_equals "" "$CURRENT_OUTPUT"; then test_pass; fi

# Explicit updates are allowed to call only the selected host package manager.
printf '%s\n' '{"plugins":{"octo@nyldn-plugins":[{"scope":"user","version":"1.1.0"}]}}' \
    > "$CLAUDE_DIR/plugins/installed_plugins.json"
: > "$CALL_LOG"
ORIGINAL_PATH="$PATH"
PATH="$FAKE_BIN:$PATH"
OCTOPUS_CODEX_DIR="$CODEX_DIR"
OCTO_TEST_CALL_LOG="$CALL_LOG"
OCTO_TEST_METADATA_UPDATER="$FAKE_BIN/update-fixture-metadata"
OCTO_TEST_UPDATE_MODE="apply"
export PATH OCTOPUS_CODEX_DIR OCTO_TEST_CALL_LOG OCTO_TEST_METADATA_UPDATER OCTO_TEST_UPDATE_MODE

octo_plugin_update_run "$PLUGIN_ROOT" claude >/dev/null
CLAUDE_CALLS="$(cat "$CALL_LOG")"
test_case "explicit Claude update refreshes marketplace"
if assert_contains "$CLAUDE_CALLS" "plugin marketplace update nyldn-plugins"; then test_pass; fi
test_case "explicit Claude update refreshes plugin"
if assert_contains "$CLAUDE_CALLS" "plugin update octo@nyldn-plugins"; then test_pass; fi
test_case "Claude update does not invoke Codex"
if assert_not_contains "$CLAUDE_CALLS" "/codex "; then test_pass; fi
test_case "Claude update metadata confirms the installed version"
octo_plugin_update_load "$PLUGIN_ROOT" claude
if assert_equals "1.2.0" "$OCTO_PLUGIN_INSTALLED_VERSION"; then test_pass; fi

: > "$CALL_LOG"
OCTOPUS_CODEX_ACTIVE_SESSION=true
export OCTOPUS_CODEX_ACTIVE_SESSION
CODEX_ACTIVE_OUTPUT=""
test_case "active Codex session refuses cache-replacing update"
if CODEX_ACTIVE_OUTPUT="$(octo_plugin_update_run "$PLUGIN_ROOT" codex 2>&1)"; then
    test_fail "active Codex session unexpectedly replaced its loaded plugin"
elif [[ -s "$CALL_LOG" ]]; then
    test_fail "active Codex session invoked the host package manager"
elif assert_contains "$CODEX_ACTIVE_OUTPUT" "outside the running Codex session"; then
    test_pass
fi
unset OCTOPUS_CODEX_ACTIVE_SESSION

: > "$CALL_LOG"
OCTOPUS_CODEX_ACTIVE_SESSION=false
CODEX_SANDBOX=workspace-write
export OCTOPUS_CODEX_ACTIVE_SESSION CODEX_SANDBOX
CODEX_MARKER_OUTPUT=""
test_case "active Codex runtime marker overrides a false session override"
if CODEX_MARKER_OUTPUT="$(octo_plugin_update_run "$PLUGIN_ROOT" codex 2>&1)"; then
    test_fail "false override bypassed a definitive Codex runtime marker"
elif [[ -s "$CALL_LOG" ]]; then
    test_fail "marker-proven Codex session invoked the host package manager"
elif assert_contains "$CODEX_MARKER_OUTPUT" "outside the running Codex session"; then
    test_pass
fi
unset OCTOPUS_CODEX_ACTIVE_SESSION CODEX_SANDBOX

: > "$CALL_LOG"
ps() { return 127; }
CODEX_INSPECTION_OUTPUT=""
CODEX_INSPECTION_RC=0
test_case "unknown Codex ancestry refuses cache-replacing update"
CODEX_INSPECTION_OUTPUT="$(octo_plugin_update_run "$PLUGIN_ROOT" codex 2>&1)" || CODEX_INSPECTION_RC=$?
if [[ "$CODEX_INSPECTION_RC" -eq 0 ]]; then
    test_fail "update proceeded without a reliable Codex ancestry check"
elif [[ "$CODEX_INSPECTION_RC" -ne 2 ]]; then
    test_fail "unknown Codex ancestry returned $CODEX_INSPECTION_RC instead of 2"
elif [[ -s "$CALL_LOG" ]]; then
    test_fail "unknown Codex ancestry invoked the host package manager"
elif assert_contains "$CODEX_INSPECTION_OUTPUT" "could not safely determine"; then
    test_pass
fi
unset -f ps

: > "$CALL_LOG"
AUTOMATIC_UPDATE_PATH="$PATH"
PATH="$FAKE_BIN:$PATH"
OCTO_TEST_PS_MODE=terminal-any
export OCTO_TEST_PS_MODE
unset CODEX_SANDBOX CODEX_PLUGIN_ROOT OCTOPUS_CODEX_ACTIVE_SESSION
test_case "automatic ancestry check permits an ordinary terminal update"
if octo_plugin_update_run "$PLUGIN_ROOT" codex >/dev/null && [[ -s "$CALL_LOG" ]]; then
    test_pass
else
    test_fail "ordinary terminal update did not reach the host package manager"
fi
unset OCTO_TEST_PS_MODE
PATH="$AUTOMATIC_UPDATE_PATH"

: > "$CALL_LOG"
OCTOPUS_CODEX_ACTIVE_SESSION=false
export OCTOPUS_CODEX_ACTIVE_SESSION
octo_plugin_update_run "$PLUGIN_ROOT" codex >/dev/null
unset OCTOPUS_CODEX_ACTIVE_SESSION
CODEX_CALLS="$(cat "$CALL_LOG")"
test_case "explicit Codex update refreshes marketplace"
if assert_contains "$CODEX_CALLS" "plugin marketplace upgrade nyldn-plugins"; then test_pass; fi
test_case "explicit Codex update refreshes plugin"
if assert_contains "$CODEX_CALLS" "plugin add claude-octopus@nyldn-plugins"; then test_pass; fi
test_case "Codex update does not invoke Claude"
if assert_not_contains "$CODEX_CALLS" "/claude "; then test_pass; fi
test_case "Codex update metadata confirms the installed version"
octo_plugin_update_load "$PLUGIN_ROOT" codex
if assert_equals "1.2.0" "$OCTO_PLUGIN_INSTALLED_VERSION"; then test_pass; fi

# A host CLI returning zero is not sufficient when its metadata remains behind
# the refreshed catalog.
printf '%s\n' '{"plugins":[{"name":"octo","version":"1.3.0"}]}' \
    > "$CLAUDE_DIR/plugins/marketplaces/nyldn-plugins/.claude-plugin/marketplace.json"
OCTO_TEST_UPDATE_MODE="unchanged"
export OCTO_TEST_UPDATE_MODE
test_case "zero-exit unchanged host state fails update verification"
if octo_plugin_update_run "$PLUGIN_ROOT" claude >/dev/null 2>&1; then
    test_fail "unchanged metadata was accepted as a successful update"
else
    test_pass
fi

: > "$CALL_LOG"
test_case "unsupported host update fails closed"
if octo_plugin_update_run "$PLUGIN_ROOT" factory >/dev/null 2>&1; then
    test_fail "Factory update unexpectedly succeeded"
else
    test_pass
fi
test_case "unsupported host invokes no package manager"
if [[ ! -s "$CALL_LOG" ]]; then test_pass; else test_fail "unsupported host invoked a package manager"; fi

PATH="$ORIGINAL_PATH"
export PATH
unset OCTOPUS_CLAUDE_DIR OCTOPUS_CODEX_DIR OCTO_TEST_CALL_LOG \
    OCTO_TEST_METADATA_UPDATER OCTO_TEST_UPDATE_MODE

test_case "SessionStart registers update advisory"
if jq -e '.hooks.SessionStart[].hooks[] | select(.command == "${CLAUDE_PLUGIN_ROOT}/hooks/plugin-update-advisory.sh")' \
    "$PROJECT_ROOT/hooks/hooks.json" >/dev/null 2>&1; then
    test_pass
else
    test_fail "SessionStart hook registration is missing"
fi

test_case "orchestrator exposes explicit update-plugin command"
if grep -q 'source.*lib/plugin-update.sh' "$PROJECT_ROOT/scripts/orchestrate.sh" \
    && grep -q 'update-plugin)' "$PROJECT_ROOT/scripts/orchestrate.sh"; then
    test_pass
else
    test_fail "update-plugin command is missing"
fi

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/doctor.sh"
DOCTOR_RESULTS_NAME=()
DOCTOR_RESULTS_CAT=()
DOCTOR_RESULTS_STATUS=()
DOCTOR_RESULTS_MSG=()
DOCTOR_RESULTS_DETAIL=()
OCTOPUS_CLAUDE_DIR="$CLAUDE_DIR"
OCTOPUS_UPDATE_MANIFEST="$PLUGIN_ROOT/.claude-plugin/plugin.json"
OCTOPUS_HOST=claude
export OCTOPUS_CLAUDE_DIR OCTOPUS_UPDATE_MANIFEST OCTOPUS_HOST
doctor_check_updates

test_case "doctor exposes plugin update health category"
if printf '%s\n' "${DOCTOR_RESULTS_CAT[@]}" | grep -qx 'updates'; then test_pass; else test_fail "updates category missing"; fi
test_case "doctor update health performs no CLI or network calls"
if [[ ! -s "$CALL_LOG" ]]; then test_pass; else test_fail "doctor invoked forbidden tools"; fi

DOCTOR_RESULTS_NAME=()
DOCTOR_RESULTS_CAT=()
DOCTOR_RESULTS_STATUS=()
DOCTOR_RESULTS_MSG=()
DOCTOR_RESULTS_DETAIL=()
ORIGINAL_PATH="$PATH"
PATH="$FAKE_BIN"
doctor_check_updates
PATH="$ORIGINAL_PATH"
test_case "doctor warns when jq is unavailable"
if [[ "${DOCTOR_RESULTS_NAME[0]:-}" == "plugin-update-dependency" \
   && "${DOCTOR_RESULTS_STATUS[0]:-}" == "warn" \
   && "${DOCTOR_RESULTS_MSG[0]:-}" == *"jq is not installed"* ]]; then
    test_pass
else
    test_fail "missing-jq diagnostic was not emitted"
fi
test_case "doctor does not report current when jq is unavailable"
if ! printf '%s\n' "${DOCTOR_RESULTS_NAME[@]}" | grep -qx 'plugin-update-current'; then
    test_pass
else
    test_fail "missing jq was reported as current"
fi

unset OCTOPUS_CLAUDE_DIR OCTOPUS_UPDATE_MANIFEST OCTOPUS_HOST
test_summary
