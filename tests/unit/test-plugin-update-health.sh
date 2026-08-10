#!/usr/bin/env bash
# Regression coverage for issue #851: stale installs must be visible without
# allowing SessionStart hooks to run package managers, network clients, or auth.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$ROOT/scripts/lib/plugin-update.sh"
HOOK="$ROOT/hooks/plugin-update-advisory.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$actual" == "$expected" ]]; then pass "$label"; else fail "$label (expected '$expected', got '$actual')"; fi
}
assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" == *"$needle"* ]]; then pass "$label"; else fail "$label (missing '$needle')"; fi
}

if [[ ! -r "$LIB" ]]; then
    fail "plugin update library exists"
    printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
    exit 1
fi
if [[ ! -x "$HOOK" ]]; then
    fail "plugin update advisory hook is executable"
    printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
    exit 1
fi

# shellcheck source=/dev/null
source "$LIB"

PLUGIN_ROOT="$TMP_DIR/plugin"
CLAUDE_DIR="$TMP_DIR/claude"
STATE_DIR="$TMP_DIR/state"
FAKE_BIN="$TMP_DIR/bin"
CALL_LOG="$TMP_DIR/forbidden-calls.log"
mkdir -p "$PLUGIN_ROOT/.claude-plugin" \
    "$CLAUDE_DIR/plugins/marketplaces/nyldn-plugins/.claude-plugin" \
    "$CLAUDE_DIR/plugins/cache/nyldn-plugins/octo/1.1.0" \
    "$CLAUDE_DIR/plugins/cache/nyldn-plugins/octo/1.2.0" \
    "$STATE_DIR" "$FAKE_BIN"
printf '{"version":"1.0.0"}\n' > "$PLUGIN_ROOT/.claude-plugin/plugin.json"
printf '%s\n' '{"plugins":{"octo@nyldn-plugins":[{"scope":"user","version":"1.1.0"}]}}' \
    > "$CLAUDE_DIR/plugins/installed_plugins.json"
printf '%s\n' '{"plugins":[{"name":"octo","version":"1.2.0"}]}' \
    > "$CLAUDE_DIR/plugins/marketplaces/nyldn-plugins/.claude-plugin/marketplace.json"

write_marketplace_state() {
    printf '%s\n' "$1" > "$CLAUDE_DIR/plugins/known_marketplaces.json"
}

write_marketplace_state '{"nyldn-plugins":{"autoUpdate":false}}'
OCTOPUS_CLAUDE_DIR="$CLAUDE_DIR" octo_plugin_update_load "$PLUGIN_ROOT" claude
assert_eq "disabled" "$OCTO_PLUGIN_AUTO_UPDATE" "detects disabled third-party auto-update"
assert_eq "1.0.0" "$OCTO_PLUGIN_LOADED_VERSION" "reads loaded plugin version"
assert_eq "1.1.0" "$OCTO_PLUGIN_INSTALLED_VERSION" "reads installed plugin version"
assert_eq "1.2.0" "$OCTO_PLUGIN_CATALOG_VERSION" "reads locally refreshed catalog version"
assert_eq "1.2.0" "$OCTO_PLUGIN_CACHE_VERSION" "finds newest cached version portably"
assert_eq "1.2.0" "$OCTO_PLUGIN_NEWEST_VERSION" "selects newest locally known version"
assert_eq "true" "$OCTO_PLUGIN_UPDATE_AVAILABLE" "flags locally known newer version"
assert_eq "true" "$OCTO_PLUGIN_RELOAD_REQUIRED" "flags installed version newer than loaded session"

write_marketplace_state '{"nyldn-plugins":{"autoUpdate":true}}'
OCTOPUS_CLAUDE_DIR="$CLAUDE_DIR" octo_plugin_update_load "$PLUGIN_ROOT" claude
assert_eq "enabled" "$OCTO_PLUGIN_AUTO_UPDATE" "detects enabled auto-update"

write_marketplace_state '{"nyldn-plugins":{"source":{"source":"git"}}}'
OCTOPUS_CLAUDE_DIR="$CLAUDE_DIR" octo_plugin_update_load "$PLUGIN_ROOT" claude
assert_eq "missing" "$OCTO_PLUGIN_AUTO_UPDATE" "detects missing auto-update preference"

printf '{not-json\n' > "$CLAUDE_DIR/plugins/known_marketplaces.json"
OCTOPUS_CLAUDE_DIR="$CLAUDE_DIR" octo_plugin_update_load "$PLUGIN_ROOT" claude
assert_eq "malformed" "$OCTO_PLUGIN_AUTO_UPDATE" "detects malformed marketplace state"
assert_eq "claude" "$(octo_plugin_detect_host "/tmp/user/.claude/plugins/cache/nyldn-plugins/octo/1.0.0")" "detects Claude host from installed path"
assert_eq "codex" "$(octo_plugin_detect_host "/tmp/user/.codex/plugins/cache/nyldn-plugins/claude-octopus/1.0.0")" "detects Codex host from installed path"

# Every executable that a SessionStart hook must never call records a marker.
for command_name in claude codex curl wget npm npx git; do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$0 $*" >> "%s"\n' "$CALL_LOG" > "$FAKE_BIN/$command_name"
    chmod +x "$FAKE_BIN/$command_name"
done

write_marketplace_state '{"nyldn-plugins":{"autoUpdate":false}}'
touch "$STATE_DIR/.setup-complete"
HOOK_OUTPUT=$(PATH="$FAKE_BIN:$PATH" \
    CLAUDE_PLUGIN_ROOT="$ROOT" \
    OCTOPUS_UPDATE_MANIFEST="$PLUGIN_ROOT/.claude-plugin/plugin.json" \
    OCTOPUS_CLAUDE_DIR="$CLAUDE_DIR" \
    OCTOPUS_STATE_DIR="$STATE_DIR" \
    OCTOPUS_UPDATE_NOW=2000000000 \
    bash "$HOOK")
assert_contains "$HOOK_OUTPUT" "Enable auto-update" "hook gives host UI remediation"
assert_contains "$HOOK_OUTPUT" "/reload-plugins" "hook explains loaded-session refresh"
if [[ ! -s "$CALL_LOG" ]]; then pass "SessionStart advisory performs no CLI or network calls"; else fail "SessionStart advisory invoked forbidden tools"; fi

HOOK_OUTPUT_2=$(PATH="$FAKE_BIN:$PATH" \
    CLAUDE_PLUGIN_ROOT="$ROOT" \
    OCTOPUS_UPDATE_MANIFEST="$PLUGIN_ROOT/.claude-plugin/plugin.json" \
    OCTOPUS_CLAUDE_DIR="$CLAUDE_DIR" \
    OCTOPUS_STATE_DIR="$STATE_DIR" \
    OCTOPUS_UPDATE_NOW=2000000001 \
    bash "$HOOK")
assert_eq "" "$HOOK_OUTPUT_2" "unchanged advisory is suppressed during cooldown"

# Fully current, auto-updating installs stay quiet even without cooldown state.
CURRENT_PLUGIN_ROOT="$TMP_DIR/current-plugin"
CURRENT_STATE_DIR="$TMP_DIR/current-state"
mkdir -p "$CURRENT_PLUGIN_ROOT/.claude-plugin" "$CURRENT_STATE_DIR"
printf '{"version":"1.2.0"}\n' > "$CURRENT_PLUGIN_ROOT/.claude-plugin/plugin.json"
printf '%s\n' '{"plugins":{"octo@nyldn-plugins":[{"scope":"user","version":"1.2.0"}]}}' \
    > "$CLAUDE_DIR/plugins/installed_plugins.json"
write_marketplace_state '{"nyldn-plugins":{"autoUpdate":true}}'
touch "$CURRENT_STATE_DIR/.setup-complete"
CURRENT_OUTPUT=$(PATH="$FAKE_BIN:$PATH" \
    CLAUDE_PLUGIN_ROOT="$ROOT" \
    OCTOPUS_UPDATE_MANIFEST="$CURRENT_PLUGIN_ROOT/.claude-plugin/plugin.json" \
    OCTOPUS_CLAUDE_DIR="$CLAUDE_DIR" \
    OCTOPUS_STATE_DIR="$CURRENT_STATE_DIR" \
    OCTOPUS_UPDATE_NOW=2000000000 \
    bash "$HOOK")
assert_eq "" "$CURRENT_OUTPUT" "current auto-updating install gets no startup advisory"

# Explicit updates are allowed to call only the selected host package manager.
: > "$CALL_LOG"
OCTOPUS_CLAUDE_DIR="$CLAUDE_DIR" PATH="$FAKE_BIN:$PATH" \
    octo_plugin_update_run "$PLUGIN_ROOT" claude >/dev/null
CLAUDE_CALLS=$(cat "$CALL_LOG")
assert_contains "$CLAUDE_CALLS" "plugin marketplace update nyldn-plugins" "explicit Claude update refreshes marketplace"
assert_contains "$CLAUDE_CALLS" "plugin update octo@nyldn-plugins" "explicit Claude update refreshes plugin"
if [[ "$CLAUDE_CALLS" != *"/codex "* ]]; then pass "Claude update does not invoke Codex"; else fail "Claude update invoked Codex"; fi

: > "$CALL_LOG"
OCTOPUS_CLAUDE_DIR="$CLAUDE_DIR" PATH="$FAKE_BIN:$PATH" \
    octo_plugin_update_run "$PLUGIN_ROOT" codex >/dev/null
CODEX_CALLS=$(cat "$CALL_LOG")
assert_contains "$CODEX_CALLS" "plugin marketplace upgrade nyldn-plugins" "explicit Codex update refreshes marketplace"
assert_contains "$CODEX_CALLS" "plugin add claude-octopus@nyldn-plugins" "explicit Codex update refreshes plugin"
if [[ "$CODEX_CALLS" != *"/claude "* ]]; then pass "Codex update does not invoke Claude"; else fail "Codex update invoked Claude"; fi

: > "$CALL_LOG"
if OCTOPUS_CLAUDE_DIR="$CLAUDE_DIR" PATH="$FAKE_BIN:$PATH" \
    octo_plugin_update_run "$PLUGIN_ROOT" factory >/dev/null 2>&1; then
    fail "unsupported host update fails closed"
else
    pass "unsupported host update fails closed"
fi
if [[ ! -s "$CALL_LOG" ]]; then pass "unsupported host invokes no package manager"; else fail "unsupported host invoked a package manager"; fi

if jq -e '.hooks.SessionStart[].hooks[] | select(.command == "${CLAUDE_PLUGIN_ROOT}/hooks/plugin-update-advisory.sh")' \
    "$ROOT/hooks/hooks.json" >/dev/null 2>&1; then
    pass "SessionStart registers update advisory"
else
    fail "SessionStart registers update advisory"
fi
if grep -q 'source.*lib/plugin-update.sh' "$ROOT/scripts/orchestrate.sh" \
    && grep -q 'update-plugin)' "$ROOT/scripts/orchestrate.sh"; then
    pass "orchestrator exposes explicit update-plugin command"
else
    fail "orchestrator exposes explicit update-plugin command"
fi

# shellcheck source=/dev/null
source "$ROOT/scripts/lib/doctor.sh"
if declare -f doctor_check_updates >/dev/null 2>&1; then
    DOCTOR_RESULTS_NAME=()
    DOCTOR_RESULTS_CAT=()
    DOCTOR_RESULTS_STATUS=()
    DOCTOR_RESULTS_MSG=()
    DOCTOR_RESULTS_DETAIL=()
    export OCTOPUS_CLAUDE_DIR="$CLAUDE_DIR"
    export OCTOPUS_UPDATE_MANIFEST="$PLUGIN_ROOT/.claude-plugin/plugin.json"
    export OCTOPUS_HOST=claude
    doctor_check_updates
    if printf '%s\n' "${DOCTOR_RESULTS_CAT[@]}" | grep -qx 'updates'; then
        pass "doctor exposes plugin update health category"
    else
        fail "doctor exposes plugin update health category"
    fi
    unset OCTOPUS_CLAUDE_DIR OCTOPUS_UPDATE_MANIFEST OCTOPUS_HOST
    if [[ ! -s "$CALL_LOG" ]]; then pass "doctor update health performs no CLI or network calls"; else fail "doctor update health invoked forbidden tools"; fi
else
    fail "doctor exposes plugin update health category"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
