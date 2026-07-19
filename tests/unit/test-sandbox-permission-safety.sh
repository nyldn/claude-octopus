#!/usr/bin/env bash
# tests/unit/test-sandbox-permission-safety.sh
# Regression coverage for issue #648 — SessionEnd hooks and event logging
# aborting/leaking stderr when HOME or the resolved workspace root is
# unwritable (e.g. a Claude process nested under a Codex `workspace-write`
# sandbox). All persistence here is optional bookkeeping/telemetry and must
# degrade to a no-op instead of turning a successful run into a failure.
#
# Fixtures below simulate "cannot write here" with a permission-independent
# trick (a plain file where a directory is expected -> ENOTDIR on mkdir -p; a
# directory where a file is expected -> EISDIR on `>>`) rather than chmod,
# because chmod's permission bits do not stop a root-executed test suite (CI
# containers commonly run as root) from writing anyway.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Sandbox/unwritable-path permission safety (issue #648)"

FIXTURE="$(mktemp -d)"
# Safety net: if a lockdown test fails before its own unlock runs, a leftover
# chattr +i / chflags uchg directory would make plain `rm -rf` fail silently.
trap '
    { command -v chattr >/dev/null 2>&1 && chattr -iR "$FIXTURE" 2>/dev/null; } || true
    { command -v chflags >/dev/null 2>&1 && chflags -R nouchg "$FIXTURE" 2>/dev/null; } || true
    rm -rf "$FIXTURE"
' EXIT

# ═══════════════════════════════════════════════════════════════════════════
# octo_event_emit must never leak a bash-level redirection error to stderr,
# and must return without aborting the caller, when the log path can't be
# written.
# ═══════════════════════════════════════════════════════════════════════════

# shellcheck disable=SC1091
source "$PROJECT_ROOT/scripts/lib/events.sh"

test_event_emit_isdir_append_no_stderr_leak() {
    test_case "octo_event_emit stays silent when the log path is a directory (EISDIR on append)"
    local dir="$FIXTURE/events-isdir"
    mkdir -p "$dir/events.jsonl"  # log "file" path is actually a directory
    export OCTO_EVENT_LOG="$dir/events.jsonl"

    local err
    err="$(octo_event_emit "octo.test" k=v 2>&1 >/dev/null)" || true

    if [[ -z "$err" ]]; then test_pass
    else test_fail "expected no stderr, got: $err"; fi
}

test_event_emit_enotdir_mkdir_no_stderr_leak() {
    test_case "octo_event_emit stays silent when the log directory is blocked by a file (ENOTDIR)"
    local blocker="$FIXTURE/events-enotdir-blocker"
    : > "$blocker"  # plain file standing where a directory needs to be created
    export OCTO_EVENT_LOG="$blocker/events.jsonl"

    local err
    err="$(octo_event_emit "octo.test" k=v 2>&1 >/dev/null)" || true

    if [[ -z "$err" ]]; then test_pass
    else test_fail "expected no stderr, got: $err"; fi
}

test_event_emit_succeeds_when_only_directory_is_unwritable() {
    test_case "octo_event_emit does not gate append on directory writability (dir check must only skip locking)"
    # /dev is not writable by a non-root user, but /dev/null itself always is —
    # a directory-writability check must never reject appending to an
    # already-writable file just because its containing directory isn't.
    export OCTO_EVENT_LOG="/dev/null"

    local err rc=0
    err="$(octo_event_emit "octo.test" k=v 2>&1 >/dev/null)" || rc=$?

    if [[ $rc -eq 0 && -z "$err" ]]; then test_pass
    else test_fail "expected rc=0 and no stderr appending to /dev/null, got rc=$rc stderr='$err'"; fi
}

test_event_trim_skipped_without_leak_when_dir_locked_down() {
    test_case "octo_event_emit skips trim (no stderr leak) when an existing log's directory is locked down"
    # Real-world case the /dev/null fix (eb404c9) opened up: an existing,
    # already-writable log file whose directory gets locked down afterward.
    # Appending to it must still work, but _octo_event_trim's sibling tmp
    # file lands in that same (now-blocked) directory — trimming must be
    # skipped there, not attempted and left to leak a redirection error.
    local dir="$FIXTURE/events-lockdown"
    mkdir -p "$dir"
    local log="$dir/events.jsonl"
    export OCTO_EVENT_MAX_LINES=5
    local i
    for i in 1 2 3 4 5 6; do printf 'seed-%s\n' "$i" >> "$log"; done

    # Directory-level immutability is the only lockdown a root-executed test
    # can't bypass (plain chmod is a no-op for root, as seen elsewhere in
    # this file). chattr is Linux-only; chflags is the BSD/macOS analog —
    # this repo's CI runs both. Skip cleanly if neither is available/works.
    local mech=""
    if command -v chattr >/dev/null 2>&1 && chattr +i "$dir" 2>/dev/null; then
        mech="chattr"
    elif command -v chflags >/dev/null 2>&1 && chflags uchg "$dir" 2>/dev/null; then
        mech="chflags"
    fi

    unlock_dir() { case "$mech" in
        chattr) chattr -i "$dir" 2>/dev/null || true ;;
        chflags) chflags nouchg "$dir" 2>/dev/null || true ;;
    esac; }

    if [[ -z "$mech" ]]; then
        test_skip "no directory-lockdown mechanism available (need chattr +i or chflags uchg)"
        unset OCTO_EVENT_MAX_LINES
        return
    fi

    # Confirm the lockdown actually reproduces the real scenario on this
    # platform/filesystem before trusting the result: existing file still
    # appendable, new directory entries blocked. If not, skip rather than
    # assert a result this mechanism didn't actually produce here.
    local append_ok=1 create_blocked=1
    ( : >> "$log" ) 2>/dev/null && append_ok=0
    ( : > "$dir/should-fail" ) 2>/dev/null || create_blocked=0
    rm -f "$dir/should-fail" 2>/dev/null

    if [[ $append_ok -ne 0 || $create_blocked -ne 0 ]]; then
        unlock_dir
        test_skip "lockdown mechanism ($mech) did not produce append-ok/create-blocked semantics here"
        unset OCTO_EVENT_MAX_LINES
        return
    fi

    export OCTO_EVENT_LOG="$log"
    local err rc=0
    err="$(octo_event_emit "octo.test" k=v 2>&1 >/dev/null)" || rc=$?
    unlock_dir
    unset OCTO_EVENT_MAX_LINES

    # Both matter: stderr catches a leaked redirection error from trim itself;
    # rc catches the append being reported as failed just because the
    # (correctly) skipped trim's own writability check was false. A `[[ -w ]]
    # && trim` guard passes the stderr half of this test while still failing
    # the rc half, so check both or the regression can slip back in silently.
    if [[ -z "$err" && $rc -eq 0 ]]; then test_pass
    else test_fail "expected rc=0 and no stderr from skipped trim, got rc=$rc stderr='$err'"; fi
}

test_event_emit_returns_nonzero_but_does_not_crash() {
    test_case "octo_event_emit returns non-zero on a blocked log path without killing the caller"
    local dir="$FIXTURE/events-return-check"
    mkdir -p "$dir/events.jsonl"  # EISDIR on append
    export OCTO_EVENT_LOG="$dir/events.jsonl"

    local rc=0
    octo_event_emit "octo.test" k=v >/dev/null 2>&1 || rc=$?

    # A caller that does `octo_event_emit ... || true` (the established pattern
    # throughout this codebase) must never observe the shell itself dying.
    if [[ $rc -ne 0 ]]; then test_pass
    else test_fail "expected non-zero return, got 0"; fi
}

# ═══════════════════════════════════════════════════════════════════════════
# orchestrate.sh's workspace-root resolution: probe writability, fall back to
# a run-scoped tmp dir instead of silently keeping an unusable root.
# Extracted verbatim (by marker, not line number) so this test tracks the real
# code rather than a duplicated copy that could drift from it.
# ═══════════════════════════════════════════════════════════════════════════

extract_workspace_resolution_snippet() {
    sed -n '/^# Apply workspace path/,/^# Re-derive SESSION_FILE/p' "$PROJECT_ROOT/scripts/orchestrate.sh" | sed '$d'
}

test_workspace_snippet_present() {
    test_case "orchestrate.sh still contains the workspace-resolution block this test targets"
    local snippet
    snippet="$(extract_workspace_resolution_snippet)"
    if [[ -n "$snippet" ]] && grep -q 'WORKSPACE_DIR=' <<<"$snippet"; then test_pass
    else test_fail "marker comments moved/removed — update this test's extraction markers"; fi
}

test_workspace_falls_back_when_plugin_data_blocked() {
    test_case "CLAUDE_PLUGIN_DATA blocked by a file falls back to a writable tmp workspace (#648)"
    local blocked_root="$FIXTURE/plugin-data-blocked"
    : > "$blocked_root"  # plain file — mkdir -p over this can never succeed, for anyone

    local snippet
    snippet="$(extract_workspace_resolution_snippet)"

    local fallback_tmp="$FIXTURE/tmp-fallback-root"
    mkdir -p "$fallback_tmp"
    local resolved
    resolved="$(
        CLAUDE_PLUGIN_DATA="$blocked_root" \
        CLAUDE_OCTOPUS_WORKSPACE="" \
        TMPDIR="$fallback_tmp" \
        bash -c "$snippet"$'\necho "$WORKSPACE_DIR"'
    )"

    if [[ "$resolved" != "$blocked_root" && "$resolved" == "$fallback_tmp"/* && -d "$resolved" ]]; then
        test_pass
    else
        test_fail "expected a writable fallback under $fallback_tmp, got: '$resolved'"
    fi
}

test_workspace_unchanged_when_writable() {
    test_case "workspace resolution does not fall back when the primary root is writable"
    local writable_root="$FIXTURE/plugin-data-writable"

    local snippet
    snippet="$(extract_workspace_resolution_snippet)"

    local resolved
    resolved="$(CLAUDE_PLUGIN_DATA="$writable_root" CLAUDE_OCTOPUS_WORKSPACE="" bash -c "$snippet"$'\necho "$WORKSPACE_DIR"')"

    if [[ "$resolved" == "$writable_root" ]]; then test_pass
    else test_fail "expected no fallback, got: '$resolved'"; fi
}

# ═══════════════════════════════════════════════════════════════════════════
# SessionEnd hooks must exit 0 with no stderr when every directory they would
# normally create is blocked, even with an active session that would
# otherwise trigger every write path (mem-dir, learnings file, cross-task
# learning extraction).
# ═══════════════════════════════════════════════════════════════════════════

setup_blocked_home() {
    local home="$1"
    mkdir -p "$home/.claude-octopus/metrics"
    cat > "$home/.claude-octopus/session.json" <<'JSON'
{"workflow":"embrace","current_phase":"tangle","autonomy":"yolo","providers":"codex,gemini","total_agent_calls":5,"errors":[]}
JSON
    # Pre-place plain files at every path the hook would otherwise mkdir -p —
    # this blocks directory creation deterministically regardless of the
    # executing user's privileges (unlike chmod, which root bypasses).
    : > "$home/.claude-octopus/learnings"      # blocks mkdir -p .../learnings

    local project_dir="$home/project"
    mkdir -p "$project_dir"
    : > "$project_dir/memory"                   # blocks mkdir -p $CLAUDE_PROJECT_DIR/memory
    printf '%s\n' "$project_dir"
}

test_session_end_hook_clean_when_dirs_blocked() {
    test_case "session-end.sh exits 0 with no stderr when its target dirs are blocked (#648)"
    local home="$FIXTURE/session-end-home"
    local project_dir
    project_dir="$(setup_blocked_home "$home")"

    local err rc=0
    err="$(
        HOME="$home" \
        CLAUDE_PROJECT_DIR="$project_dir" \
        bash "$PROJECT_ROOT/hooks/session-end.sh" 2>&1 >/dev/null
    )" || rc=$?

    if [[ $rc -eq 0 && -z "$err" ]]; then test_pass
    else test_fail "exit=$rc stderr='$err'"; fi
}

test_workflow_verification_hook_clean_when_dirs_blocked() {
    test_case "workflow-verification.sh exits 0 with no stderr under the same blocked HOME (#648)"
    local home="$FIXTURE/workflow-verification-home"
    setup_blocked_home "$home" >/dev/null

    local err rc=0
    err="$(
        HOME="$home" \
        bash "$PROJECT_ROOT/hooks/workflow-verification.sh" 2>&1 >/dev/null
    )" || rc=$?

    if [[ $rc -eq 0 && -z "$err" ]]; then test_pass
    else test_fail "exit=$rc stderr='$err'"; fi
}

test_session_end_hook_writes_nothing_outside_home_when_blocked() {
    test_case "session-end.sh creates no file outside the supplied HOME/project dir when blocked"
    local home="$FIXTURE/session-end-isolation-home"
    local project_dir
    project_dir="$(setup_blocked_home "$home")"
    local sentinel_parent="$FIXTURE/sentinel-parent"
    mkdir -p "$sentinel_parent"
    local before after
    before="$(find "$sentinel_parent" | sort)"

    (
        HOME="$home" \
        CLAUDE_PROJECT_DIR="$project_dir" \
        bash "$PROJECT_ROOT/hooks/session-end.sh"
    ) >/dev/null 2>&1 || true

    after="$(find "$sentinel_parent" | sort)"
    if [[ "$before" == "$after" ]]; then test_pass
    else test_fail "unexpected files appeared outside HOME/project dir"; fi
}

test_event_emit_isdir_append_no_stderr_leak
test_event_emit_enotdir_mkdir_no_stderr_leak
test_event_emit_succeeds_when_only_directory_is_unwritable
test_event_trim_skipped_without_leak_when_dir_locked_down
test_event_emit_returns_nonzero_but_does_not_crash
test_workspace_snippet_present
test_workspace_falls_back_when_plugin_data_blocked
test_workspace_unchanged_when_writable
test_session_end_hook_clean_when_dirs_blocked
test_workflow_verification_hook_clean_when_dirs_blocked
test_session_end_hook_writes_nothing_outside_home_when_blocked

test_summary
