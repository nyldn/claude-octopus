#!/usr/bin/env bash
# Regression checks for the machine-wide ~/.claude-octopus/plugin link: running
# orchestrate.sh from a development checkout must not take over a working link
# that other live sessions use, and an older installed copy must not move it
# backwards. A missing or broken link is still repaired (#318, #377).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "stable plugin root self-heal"

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/plugin-root.sh"

BASE="$(cd "$TEST_TMP_DIR" && pwd -P)"
# Installed-root detection keys on the host cache locations under HOME.
HOME="$BASE/home"
unset CLAUDE_CONFIG_DIR CODEX_HOME XDG_DATA_HOME LOCALAPPDATA
STABLE="$HOME/.claude-octopus/plugin"
mkdir -p "$(dirname "$STABLE")"

OLD_VER="11.8.1"
CUR_VER="11.9.1"
NEW_VER="11.10.0"
PRE_VER="11.10.0-beta.1"

make_root() {
    local root="$1" version="$2"
    mkdir -p "$root/scripts"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$root/scripts/orchestrate.sh"
    chmod +x "$root/scripts/orchestrate.sh"
    printf '{\n  "name": "claude-octopus",\n  "version": "%s"\n}\n' "$version" > "$root/package.json"
}

CACHE="$HOME/.claude/plugins/cache/nyldn-plugins/octo"
INSTALLED_OLD="$CACHE/$OLD_VER"
INSTALLED_CUR="$CACHE/$CUR_VER"
INSTALLED_NEW="$CACHE/$NEW_VER"
INSTALLED_PRE="$CACHE/$PRE_VER"
INSTALLED_UNKNOWN="$CACHE/unknown"
DEV="$BASE/worktrees/claude-octopus/feature"
LOOKALIKE_DEV="$BASE/src/nyldn-plugins/octo/feature"
make_root "$INSTALLED_OLD" "$OLD_VER"
make_root "$INSTALLED_CUR" "$CUR_VER"
make_root "$INSTALLED_NEW" "$NEW_VER"
make_root "$INSTALLED_PRE" "$PRE_VER"
make_root "$INSTALLED_UNKNOWN" "next"
make_root "$DEV" "$CUR_VER"
make_root "$LOOKALIKE_DEV" "$NEW_VER"

point_at() { rm -rf "$STABLE"; ln -s "$1" "$STABLE"; }
resolved() { (cd "$STABLE" 2>/dev/null && pwd -P) || printf 'missing\n'; }
heal() { octo_self_heal_stable_plugin_root "$1" "$STABLE" >/dev/null 2>&1 || true; }

test_case "installed-root detection matches only real host caches"
mkdir -p "$HOME/.codex/plugins/cache/nyldn-plugins/claude-octopus/$CUR_VER" \
         "$HOME/Library/Application Support/Claude/plugins/nyldn-plugins/octo/$CUR_VER"
if octo_is_installed_plugin_root "$INSTALLED_CUR" && \
   octo_is_installed_plugin_root "$HOME/.codex/plugins/cache/nyldn-plugins/claude-octopus/$CUR_VER" && \
   octo_is_installed_plugin_root "$HOME/Library/Application Support/Claude/plugins/nyldn-plugins/octo/$CUR_VER" && \
   ! octo_is_installed_plugin_root "$DEV" && \
   ! octo_is_installed_plugin_root "$LOOKALIKE_DEV" && \
   ! octo_is_installed_plugin_root ""; then
    test_pass
else
    test_fail "installed-root detection misclassified a cache or checkout path"
fi

test_case "a development checkout does not take over a working link"
point_at "$INSTALLED_CUR"
heal "$DEV"
if [[ "$(resolved)" == "$INSTALLED_CUR" ]]; then
    test_pass
else
    test_fail "working link moved to $(resolved); expected $INSTALLED_CUR"
fi

test_case "a checkout whose path contains nyldn-plugins/octo does not take over"
point_at "$INSTALLED_CUR"
heal "$LOOKALIKE_DEV"
if [[ "$(resolved)" == "$INSTALLED_CUR" ]]; then
    test_pass
else
    test_fail "look-alike checkout took over the link: $(resolved)"
fi

test_case "a development checkout repairs a missing link"
rm -rf "$STABLE"
heal "$DEV"
if [[ "$(resolved)" == "$DEV" ]]; then
    test_pass
else
    test_fail "missing link resolved to $(resolved); expected $DEV"
fi

test_case "a development checkout repairs a broken link"
BROKEN="$BASE/deleted-root"
make_root "$BROKEN" "$CUR_VER"
point_at "$BROKEN"
rm -rf "$BROKEN"
heal "$DEV"
if [[ "$(resolved)" == "$DEV" ]]; then
    test_pass
else
    test_fail "broken link resolved to $(resolved); expected $DEV"
fi

test_case "a newer installed copy moves the link forward"
point_at "$INSTALLED_CUR"
heal "$INSTALLED_NEW"
if [[ "$(resolved)" == "$INSTALLED_NEW" ]]; then
    test_pass
else
    test_fail "link stayed at $(resolved); expected upgrade to $INSTALLED_NEW"
fi

test_case "an older installed copy does not move the link backwards"
point_at "$INSTALLED_CUR"
heal "$INSTALLED_OLD"
if [[ "$(resolved)" == "$INSTALLED_CUR" ]]; then
    test_pass
else
    test_fail "link downgraded to $(resolved); expected $INSTALLED_CUR"
fi

test_case "a prerelease of the current version does not replace the release"
point_at "$INSTALLED_NEW"
heal "$INSTALLED_PRE"
if [[ "$(resolved)" == "$INSTALLED_NEW" ]]; then
    test_pass
else
    test_fail "prerelease replaced the release: $(resolved)"
fi

test_case "an installed copy with an unreadable version keeps the working link"
point_at "$INSTALLED_CUR"
heal "$INSTALLED_UNKNOWN"
if [[ "$(resolved)" == "$INSTALLED_CUR" ]]; then
    test_pass
else
    test_fail "unorderable installed copy replaced the link: $(resolved)"
fi

test_case "a link on an installed copy with an unreadable version is kept"
point_at "$INSTALLED_UNKNOWN"
heal "$INSTALLED_NEW"
if [[ "$(resolved)" == "$INSTALLED_UNKNOWN" ]]; then
    test_pass
else
    test_fail "link moved off an unorderable installed copy to $(resolved)"
fi

test_case "an installed copy takes over a link held by a checkout"
point_at "$DEV"
heal "$INSTALLED_CUR"
if [[ "$(resolved)" == "$INSTALLED_CUR" ]]; then
    test_pass
else
    test_fail "link stayed at $(resolved); expected $INSTALLED_CUR"
fi

test_case "a busy lock leaves the link unchanged"
point_at "$INSTALLED_CUR"
mkdir "$STABLE.lock"
heal "$INSTALLED_NEW"
busy_result="$(resolved)"
rmdir "$STABLE.lock" 2>/dev/null || true
if [[ "$busy_result" == "$INSTALLED_CUR" ]]; then
    test_pass
else
    test_fail "link changed to $busy_result while another process held the lock"
fi

test_case "an abandoned lock is recovered"
point_at "$INSTALLED_CUR"
mkdir "$STABLE.lock"
touch -t 200001010000 "$STABLE.lock"
heal "$INSTALLED_NEW"
if [[ "$(resolved)" == "$INSTALLED_NEW" && ! -d "$STABLE.lock" ]]; then
    test_pass
else
    test_fail "stale lock blocked the upgrade: link=$(resolved) lock=$([[ -d "$STABLE.lock" ]] && echo present || echo gone)"
fi

test_case "a wrapper-directory stable root is not downgraded"
rm -rf "$STABLE"
mkdir -p "$STABLE/scripts"
_octo_stable_wrapper "$INSTALLED_CUR/scripts/orchestrate.sh" > "$STABLE/scripts/orchestrate.sh"
chmod +x "$STABLE/scripts/orchestrate.sh"
heal "$INSTALLED_OLD"
wrapper_target="$(octo_stable_shim_source "$STABLE/scripts/orchestrate.sh" "scripts/orchestrate.sh" 2>/dev/null || true)"
rm -rf "$STABLE"
if [[ "$wrapper_target" == "$INSTALLED_CUR/scripts/orchestrate.sh" ]]; then
    test_pass
else
    test_fail "wrapper now targets ${wrapper_target:-nothing}; expected $INSTALLED_CUR"
fi

test_case "package.json versions parse across layouts"
MULTILINE="$BASE/multiline-root"
mkdir -p "$MULTILINE"
printf '{\n  "name": "claude-octopus",\n  "version":\n    "%s"\n}\n' "$NEW_VER" > "$MULTILINE/package.json"
if [[ "$(_octo_plugin_root_version "$INSTALLED_PRE")" == "$PRE_VER" ]] && \
   [[ "$(_octo_plugin_root_version "$INSTALLED_CUR")" == "$CUR_VER" ]] && \
   [[ -z "$(_octo_plugin_root_version "$INSTALLED_UNKNOWN")" ]] && \
   { ! command -v jq >/dev/null 2>&1 || [[ "$(_octo_plugin_root_version "$MULTILINE")" == "$NEW_VER" ]]; }; then
    test_pass
else
    test_fail "version parsing failed for prerelease, release, invalid or multi-line package.json"
fi

test_case "version comparison is numeric per field and orders prereleases"
LEADING_ZERO_VER="11.09.0"
if _octo_version_lt "$OLD_VER" "$CUR_VER" && _octo_version_lt "$CUR_VER" "$NEW_VER" && \
   _octo_version_lt "$LEADING_ZERO_VER" "$NEW_VER" && ! _octo_version_lt "$CUR_VER" "$CUR_VER" && \
   ! _octo_version_lt "$NEW_VER" "$CUR_VER" && _octo_version_lt "$PRE_VER" "$NEW_VER" && \
   ! _octo_version_lt "$NEW_VER" "$PRE_VER" && _octo_version_lt "$CUR_VER" "$PRE_VER"; then
    test_pass
else
    test_fail "version comparison is not numeric per field or misorders prereleases"
fi

test_case "orchestrate.sh self-heals through the guarded helper"
orchestrate_source="$(cat "$PROJECT_ROOT/scripts/orchestrate.sh")"
if [[ "$orchestrate_source" == *'octo_self_heal_stable_plugin_root "$PLUGIN_DIR"'* ]] && \
   [[ "$orchestrate_source" != *'    octo_ensure_stable_plugin_root "$PLUGIN_DIR" >/dev/null 2>&1 || true'* ]]; then
    test_pass
else
    test_fail "orchestrate.sh still repoints the stable link unconditionally"
fi

test_case "session-manager only claims the link for a host-supplied root"
session_source="$(cat "$PROJECT_ROOT/scripts/session-manager.sh")"
if [[ "$session_source" == *'if [[ -z "${CLAUDE_PLUGIN_ROOT:-}" ]] && declare -f octo_self_heal_stable_plugin_root'* ]]; then
    test_pass
else
    test_fail "session-manager.sh claims the link even when it inferred the root itself"
fi

test_summary
