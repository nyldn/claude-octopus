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
STABLE="$BASE/home/.claude-octopus/plugin"
mkdir -p "$(dirname "$STABLE")"

make_root() {
    local root="$1" version="$2"
    mkdir -p "$root/scripts"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$root/scripts/orchestrate.sh"
    chmod +x "$root/scripts/orchestrate.sh"
    printf '{\n  "name": "claude-octopus",\n  "version": "%s"\n}\n' "$version" > "$root/package.json"
}

CACHE="$BASE/home/.claude/plugins/cache/nyldn-plugins/octo"
INSTALLED_OLD="$CACHE/11.8.1"
INSTALLED_CUR="$CACHE/11.9.1"
INSTALLED_NEW="$CACHE/11.10.0"
DEV="$BASE/worktrees/claude-octopus/feature"
make_root "$INSTALLED_OLD" 11.8.1
make_root "$INSTALLED_CUR" 11.9.1
make_root "$INSTALLED_NEW" 11.10.0
make_root "$DEV" 11.9.1

point_at() { rm -f "$STABLE"; ln -s "$1" "$STABLE"; }
resolved() { (cd "$STABLE" 2>/dev/null && pwd -P) || printf 'missing\n'; }

test_case "installed-root detection separates caches from checkouts"
if octo_is_installed_plugin_root "$INSTALLED_CUR" && \
   octo_is_installed_plugin_root "$HOME/.codex/plugins/cache/nyldn-plugins/claude-octopus/11.9.1" && \
   ! octo_is_installed_plugin_root "$DEV" && \
   ! octo_is_installed_plugin_root ""; then
    test_pass
else
    test_fail "installed-root detection misclassified a cache or checkout path"
fi

test_case "a development checkout does not take over a working link"
point_at "$INSTALLED_CUR"
octo_self_heal_stable_plugin_root "$DEV" "$STABLE" >/dev/null 2>&1 || true
if [[ "$(resolved)" == "$INSTALLED_CUR" ]]; then
    test_pass
else
    test_fail "working link moved to $(resolved); expected $INSTALLED_CUR"
fi

test_case "a development checkout repairs a missing link"
rm -f "$STABLE"
octo_self_heal_stable_plugin_root "$DEV" "$STABLE" >/dev/null 2>&1 || true
if [[ "$(resolved)" == "$DEV" ]]; then
    test_pass
else
    test_fail "missing link resolved to $(resolved); expected $DEV"
fi

test_case "a development checkout repairs a broken link"
BROKEN="$BASE/deleted-root"
make_root "$BROKEN" 11.9.1
point_at "$BROKEN"
rm -rf "$BROKEN"
octo_self_heal_stable_plugin_root "$DEV" "$STABLE" >/dev/null 2>&1 || true
if [[ "$(resolved)" == "$DEV" ]]; then
    test_pass
else
    test_fail "broken link resolved to $(resolved); expected $DEV"
fi

test_case "a newer installed copy moves the link forward"
point_at "$INSTALLED_CUR"
octo_self_heal_stable_plugin_root "$INSTALLED_NEW" "$STABLE" >/dev/null 2>&1 || true
if [[ "$(resolved)" == "$INSTALLED_NEW" ]]; then
    test_pass
else
    test_fail "link stayed at $(resolved); expected upgrade to $INSTALLED_NEW"
fi

test_case "an older installed copy does not move the link backwards"
point_at "$INSTALLED_CUR"
octo_self_heal_stable_plugin_root "$INSTALLED_OLD" "$STABLE" >/dev/null 2>&1 || true
if [[ "$(resolved)" == "$INSTALLED_CUR" ]]; then
    test_pass
else
    test_fail "link downgraded to $(resolved); expected $INSTALLED_CUR"
fi

test_case "an installed copy takes over a link held by a checkout"
point_at "$DEV"
octo_self_heal_stable_plugin_root "$INSTALLED_CUR" "$STABLE" >/dev/null 2>&1 || true
if [[ "$(resolved)" == "$INSTALLED_CUR" ]]; then
    test_pass
else
    test_fail "link stayed at $(resolved); expected $INSTALLED_CUR"
fi

test_case "version comparison is numeric per field"
if _octo_version_lt 11.8.1 11.9.1 && _octo_version_lt 11.9.1 11.10.0 && \
   _octo_version_lt 11.09.0 11.10.0 && ! _octo_version_lt 11.9.1 11.9.1 && \
   ! _octo_version_lt 11.10.0 11.9.1; then
    test_pass
else
    test_fail "dotted version comparison is not numeric per field"
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
