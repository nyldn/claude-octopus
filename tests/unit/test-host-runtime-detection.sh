#!/usr/bin/env bash
# Host runtime detection: runtime markers must outrank the CODEX_HOME config
# hint. An exported CODEX_HOME inside Claude Code made Octopus treat the session
# as a Codex host, so council marked codex seats host-native (same quorum loss
# as #1103) and lifecycle/plugin-update picked Codex behavior.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "host runtime detection"

CLAUDE_INSTALL="/home/u/.claude/plugins/cache/nyldn-plugins/octo/11.9.3"
CODEX_INSTALL="/home/u/.codex/plugins/cache/nyldn-plugins/claude-octopus/11.9.3"
CHECKOUT="/home/u/src/claude-octopus"

# Run one detector in a clean environment. $1 = function, $2 = plugin root,
# remaining args = VAR=value assignments.
detect() {
    local fn="$1" root="$2"
    shift 2
    env -i "PATH=${PATH}" "HOME=${TEST_TMP_DIR}" "$@" bash -c '
        source "$1/scripts/lib/host-runtime.sh"
        source "$1/scripts/lib/lifecycle.sh" >/dev/null 2>&1 || true
        source "$1/scripts/lib/plugin-update.sh" >/dev/null 2>&1 || true
        unset OCTOPUS_HOST OCTOPUS_PLUGIN_HOST
        "$2" "$3"
    ' _ "$PROJECT_ROOT" "$fn" "$root"
}

expect() {
    local want="$1" root="$2"
    shift 2
    local got
    got="$(detect octo_detect_host_runtime "$root" "$@")"
    [[ "$got" == "$want" ]] || { printf 'helper: want %s got %s for %s\n' "$want" "$got" "$*"; return 1; }
}

test_case "an exported CODEX_HOME does not make a Claude install a Codex host"
if expect claude "$CLAUDE_INSTALL" "CODEX_HOME=/home/u/.codex" && \
   expect claude "$CHECKOUT" "CODEX_HOME=/home/u/.codex" "CLAUDE_PLUGIN_ROOT=$CLAUDE_INSTALL"; then
    test_pass
else
    test_fail "CODEX_HOME still outranks Claude signals"
fi

test_case "Codex runtime markers identify a Codex host"
if expect codex "$CLAUDE_INSTALL" "CODEX_THREAD_ID=t-1" && \
   expect codex "$CHECKOUT" "CODEX_SESSION_ID=s-1" && \
   expect codex "$CHECKOUT" "CODEX_SANDBOX=seatbelt" && \
   expect codex "$CHECKOUT" "CODEX_PLUGIN_ROOT=$CODEX_INSTALL"; then
    test_pass
else
    test_fail "a Codex runtime marker was not recognized"
fi

test_case "Codex runtime markers outrank the CLAUDE_PLUGIN_ROOT Codex supplies to hooks"
if expect codex "$CODEX_INSTALL" "CODEX_THREAD_ID=t-1" "CLAUDE_PLUGIN_ROOT=$CODEX_INSTALL"; then
    test_pass
else
    test_fail "a Codex hook with CLAUDE_PLUGIN_ROOT set was detected as Claude"
fi

test_case "a CLAUDE_PLUGIN_ROOT inside a Codex plugin cache means Codex"
# Codex hooks get CLAUDE_PLUGIN_ROOT but may lack the shell-command markers.
if expect codex "" "CLAUDE_PLUGIN_ROOT=$CODEX_INSTALL" && \
   expect codex "" "CODEX_HOME=/srv/codex" "CLAUDE_PLUGIN_ROOT=/srv/codex/plugins/cache/nyldn-plugins/claude-octopus/11.9.3" && \
   expect claude "" "CODEX_HOME=/srv/codex" "CLAUDE_PLUGIN_ROOT=$CLAUDE_INSTALL"; then
    test_pass
else
    test_fail "a Codex plugin-cache root was not recognized, or a Claude root was misread"
fi

test_case "claude seats do not inherit Codex runtime markers"
routing_source="$(cat "$PROJECT_ROOT/scripts/lib/provider-routing.sh")"
if [[ "$routing_source" == *'-u CODEX_THREAD_ID -u CODEX_SESSION_ID -u CODEX_TASK_ID -u CODEX_SANDBOX -u CODEX_PLUGIN_ROOT "OCTOPUS_PROVIDER_CHILD=true"'* ]] && \
   [[ "$routing_source" == *'_octo_is_codex_plugin_cache "${CLAUDE_PLUGIN_ROOT:-}"; then'* ]]; then
    test_pass
else
    test_fail "the claude child environment still carries Codex runtime markers"
fi

test_case "Claude Code runtime markers outrank the CODEX_HOME hint"
# Claude Code's Bash tool sets these but not CLAUDE_PLUGIN_ROOT, so a run from a
# development checkout (no host path) must not fall through to CODEX_HOME.
if expect claude "$CHECKOUT" "CODEX_HOME=/home/u/.codex" "CLAUDE_CODE_SESSION_ID=c-1" && \
   expect claude "$CHECKOUT" "CODEX_HOME=/home/u/.codex" "CLAUDECODE=1" && \
   expect claude "$CHECKOUT" "CODEX_HOME=/home/u/.codex" "CLAUDE_CODE_ENTRYPOINT=cli" && \
    expect codex "$CHECKOUT" "CLAUDECODE=1" "CODEX_THREAD_ID=t-1"; then
    test_pass
else
    test_fail "CODEX_HOME outranked Claude Code runtime markers, or Claude markers outranked Codex"
fi

test_case "Claude Code runtime markers outrank a shared plugin pointing into the Codex cache (#1175)"
if expect claude "$CODEX_INSTALL" "CLAUDECODE=1" && \
   expect claude "$CODEX_INSTALL" "CLAUDE_CODE_ENTRYPOINT=cli" && \
   expect claude "$CODEX_INSTALL" "CLAUDE_CODE_SESSION_ID=c-1" && \
   expect codex "$CODEX_INSTALL" "CLAUDECODE=1" "CODEX_THREAD_ID=t-1"; then
    test_pass
else
    test_fail "the cached install path outranked the active runtime, or a Codex runtime marker was lost"
fi

test_case "install paths and CODEX_HOME remain fallbacks"
if expect codex "$CODEX_INSTALL" && expect claude "$CLAUDE_INSTALL" && \
   expect codex "$CHECKOUT" "CODEX_HOME=/home/u/.codex" && \
   expect standalone "$CHECKOUT" && \
   expect factory "$CHECKOUT" "DROID_PLUGIN_ROOT=/home/u/.factory/x" "CODEX_THREAD_ID=t-1"; then
    test_pass
else
    test_fail "fallback ordering changed"
fi

test_case "lifecycle and plugin-update use the same detection"
lc="$(detect octo_lifecycle_host "" "CODEX_HOME=/home/u/.codex" "CLAUDE_PLUGIN_ROOT=$CLAUDE_INSTALL")"
pu="$(detect octo_plugin_detect_host "$CLAUDE_INSTALL" "CODEX_HOME=/home/u/.codex")"
pu_codex="$(detect octo_plugin_detect_host "$CHECKOUT" "CODEX_THREAD_ID=t-1")"
if [[ "$lc" == "claude" && "$pu" == "claude" && "$pu_codex" == "codex" ]]; then
    test_pass
else
    test_fail "lifecycle=$lc plugin-update=$pu plugin-update(codex)=$pu_codex; expected claude claude codex"
fi

test_case "lifecycle host detection uses its own install path before OCTOPUS_HOST is set"
# A Claude install run from a terminal (no CLAUDE_PLUGIN_ROOT, no runtime
# markers) with CODEX_HOME exported must still report claude.
lc_install="$TEST_TMP_DIR/home/.claude/plugins/cache/nyldn-plugins/octo/9.9.9"
mkdir -p "$lc_install/scripts/lib"
cp "$PROJECT_ROOT/scripts/lib/host-runtime.sh" "$PROJECT_ROOT/scripts/lib/lifecycle.sh" "$lc_install/scripts/lib/"
lc_host="$(env -i "PATH=${PATH}" "HOME=${TEST_TMP_DIR}" "CODEX_HOME=/home/u/.codex" bash -c '
    source "$1/scripts/lib/lifecycle.sh" >/dev/null 2>&1 || true
    unset OCTOPUS_HOST
    octo_lifecycle_host
' _ "$lc_install")"
if [[ "$lc_host" == "claude" ]]; then
    test_pass
else
    test_fail "lifecycle reported ${lc_host:-nothing} for a Claude install with CODEX_HOME exported"
fi

test_case "orchestrate.sh sets OCTOPUS_HOST through the shared helper"
orchestrate_source="$(cat "$PROJECT_ROOT/scripts/orchestrate.sh")"
if [[ "$orchestrate_source" == *'OCTOPUS_HOST="$(octo_detect_host_runtime "$PLUGIN_DIR")"'* ]] && \
   [[ "$orchestrate_source" != *'elif [[ -n "${CODEX_HOME:-}" || -n "${CODEX_SANDBOX:-}"'* ]]; then
    test_pass
else
    test_fail "orchestrate.sh still carries its own CODEX_HOME-first host detection"
fi

test_summary
