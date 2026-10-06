#!/bin/bash
# tests/smoke/test-safety-hooks.sh
# Static analysis tests for scope-lock safety hooks (v9.8.0)
# Validates: hook scripts, command files, plugin.json registration, pattern coverage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

SAFETY_HOOK_STATE_FILES=()
SAFETY_HOOK_STATE_IDENTITIES=()
# Register only a created synthetic regular file containing this probe's expected
# value. Admission of an absent path alone never authorizes subsequent cleanup.
record_safety_hook_state() {
    local identity
    identity=$(python3 - "$1" "$2" <<'PYRECORD'
import os
import stat
import sys
path, expected = sys.argv[1:]
info = os.lstat(path)
if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
        or info.st_nlink != 1):
    raise SystemExit("refused ownership of unsafe safety fixture metadata")
descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
with os.fdopen(descriptor, encoding="utf-8") as stream:
    opened = os.fstat(stream.fileno())
    if (opened.st_dev, opened.st_ino) != (info.st_dev, info.st_ino):
        raise SystemExit("safety fixture changed during ownership check")
    if stream.read() != expected + "\n":
        raise SystemExit("refused ownership of unexpected safety fixture contents")
current = os.lstat(path)
if (current.st_dev, current.st_ino) != (info.st_dev, info.st_ino):
    raise SystemExit("safety fixture replaced during ownership check")
print(str(info.st_dev) + ":" + str(info.st_ino))
PYRECORD
    ) || return
    SAFETY_HOOK_STATE_FILES+=("$1")
    SAFETY_HOOK_STATE_IDENTITIES+=("$identity")
}
cleanup_safety_hook_state() {
    local path index
    for path in "$@"; do
        for index in ${SAFETY_HOOK_STATE_FILES[@]+"${!SAFETY_HOOK_STATE_FILES[@]}"}; do
            [[ "${SAFETY_HOOK_STATE_FILES[$index]}" == "$path" ]] || continue
            python3 - "$path" "${SAFETY_HOOK_STATE_IDENTITIES[$index]}" <<'PYCLEAN' || return
import os
import stat
import sys
path, identity = sys.argv[1:]
try:
    info = os.lstat(path)
except FileNotFoundError:
    raise SystemExit(0)
if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
        or info.st_nlink != 1 or str(info.st_dev) + ":" + str(info.st_ino) != identity):
    raise SystemExit("refused cleanup of replaced safety fixture metadata")
os.unlink(path)
PYCLEAN
            # A retired path is never revisited by the exit trap after PID reuse.
            SAFETY_HOOK_STATE_FILES[$index]=""
        done
    done
}
cleanup_safety_hooks_test() {
    cleanup_safety_hook_state ${SAFETY_HOOK_STATE_FILES[@]+"${SAFETY_HOOK_STATE_FILES[@]}"}
    cleanup_test_environment
}
trap cleanup_safety_hooks_test EXIT

test_suite "Safety Hooks (careful/freeze/guard)"

CAREFUL_HOOK="$PROJECT_ROOT/hooks/careful-check.sh"
FREEZE_HOOK="$PROJECT_ROOT/hooks/freeze-check.sh"
PLUGIN_JSON="$PROJECT_ROOT/.claude-plugin/plugin.json"
HOOKS_JSON="$PROJECT_ROOT/hooks/hooks.json"
COMMANDS_DIR="$PROJECT_ROOT/commands"
SKILL_DEBUG="$PROJECT_ROOT/.claude/skills/skill-debug.md"
if [[ ! -f "$SKILL_DEBUG" ]]; then
    SKILL_DEBUG="$PROJECT_ROOT/.claude/skills/skill-debug/SKILL.md"
fi

# ── Hook script existence and executability ──────────────────────────

test_careful_hook_exists() {
    test_case "careful-check.sh exists and is executable"
    if [[ -x "$CAREFUL_HOOK" ]]; then
        test_pass
    else
        test_fail "careful-check.sh missing or not executable"
    fi
}

test_freeze_hook_exists() {
    test_case "freeze-check.sh exists and is executable"
    if [[ -x "$FREEZE_HOOK" ]]; then
        test_pass
    else
        test_fail "freeze-check.sh missing or not executable"
    fi
}

test_careful_hook_valid_syntax() {
    test_case "careful-check.sh has valid bash syntax"
    if bash -n "$CAREFUL_HOOK" 2>/dev/null; then
        test_pass
    else
        test_fail "careful-check.sh has syntax errors"
    fi
}

test_freeze_hook_valid_syntax() {
    test_case "freeze-check.sh has valid bash syntax"
    if bash -n "$FREEZE_HOOK" 2>/dev/null; then
        test_pass
    else
        test_fail "freeze-check.sh has syntax errors"
    fi
}

# ── Careful hook: destructive pattern coverage ───────────────────────

test_careful_rm_rf_pattern() {
    test_case "careful-check.sh detects rm -rf"
    if grep -c 'rm.*-[a-zA-Z]*r[a-zA-Z]*f' "$CAREFUL_HOOK" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "rm -rf pattern not found"
    fi
}

test_careful_safe_exceptions() {
    test_case "careful-check.sh has safe rm -rf exceptions"
    local missing=0
    for safe_dir in node_modules dist .next __pycache__ build coverage .turbo; do
        if ! grep -c "$safe_dir" "$CAREFUL_HOOK" >/dev/null 2>&1; then
            echo "  MISSING safe exception: $safe_dir"
            missing=$((missing + 1))
        fi
    done
    if [[ $missing -eq 0 ]]; then
        test_pass
    else
        test_fail "$missing safe exception(s) missing"
    fi
}

test_careful_sql_patterns() {
    test_case "careful-check.sh detects SQL destructive operations"
    local missing=0
    for pattern in "DROP.*TABLE" "DROP.*DATABASE" "TRUNCATE"; do
        if ! grep -c "$pattern" "$CAREFUL_HOOK" >/dev/null 2>&1; then
            echo "  MISSING SQL pattern: $pattern"
            missing=$((missing + 1))
        fi
    done
    if [[ $missing -eq 0 ]]; then
        test_pass
    else
        test_fail "$missing SQL pattern(s) missing"
    fi
}

test_careful_git_force_push() {
    test_case "careful-check.sh detects git push --force"
    if grep -Ec 'git.*push.*--force|git.*push.*-f' "$CAREFUL_HOOK" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "git push --force pattern not found"
    fi
}

test_careful_git_reset_hard() {
    test_case "careful-check.sh detects git reset --hard"
    if grep -c 'git.*reset.*--hard' "$CAREFUL_HOOK" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "git reset --hard pattern not found"
    fi
}

test_careful_git_checkout_dot() {
    test_case "careful-check.sh detects git checkout ./restore ."
    if grep -Ec 'git.*checkout.*\.|git.*restore.*\.' "$CAREFUL_HOOK" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "git checkout ./restore . pattern not found"
    fi
}

test_careful_kubectl_delete() {
    test_case "careful-check.sh detects kubectl delete"
    if grep -c 'kubectl.*delete' "$CAREFUL_HOOK" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "kubectl delete pattern not found"
    fi
}

test_careful_docker_destructive() {
    test_case "careful-check.sh detects docker rm -f and docker system prune"
    local found=0
    grep -c 'docker.*rm.*-f' "$CAREFUL_HOOK" >/dev/null 2>&1 && found=$((found + 1))
    grep -c 'docker.*system.*prune' "$CAREFUL_HOOK" >/dev/null 2>&1 && found=$((found + 1))
    if [[ $found -ge 2 ]]; then
        test_pass
    else
        test_fail "docker destructive patterns incomplete (found $found/2)"
    fi
}

test_careful_reads_state_file() {
    test_case "careful-check.sh reads state file from /tmp/octopus-careful-*"
    if grep -c 'octopus-careful-' "$CAREFUL_HOOK" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "state file path not found"
    fi
}

test_careful_returns_ask_decision() {
    test_case "careful-check.sh returns permissionDecision:ask for destructive commands"
    if grep -c 'permissionDecision.*ask' "$CAREFUL_HOOK" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "permissionDecision:ask not found in output"
    fi
}

test_careful_statement_shape_not_substring() {
    test_case "careful-check.sh gates on executable context and command boundaries"
    # Activate careful mode for a pinned session so the hook and this test resolve the
    # same state-file path (CLAUDE_CODE_SESSION_ID pins octo_session_state_file).
    local sid="octo-careful-fp-$$"
    local sf="/tmp/octopus-careful-${sid}.txt"
    : > "$sf"

    # Returns `fire` (explicit ask decision), `quiet` (exit 0, no decision — the hook's
    # pass-through), or `error:<rc>` when the hook itself exits non-zero. A crashed hook
    # must NOT read as `quiet`, or the negative cases would pass spuriously.
    _cc_decides() {
        local out rc=0
        out=$(jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' \
            | env OCTOPUS_HOST=claude "CLAUDE_CODE_SESSION_ID=${sid}" bash "$CAREFUL_HOOK" 2>/dev/null) || rc=$?
        if (( rc != 0 )); then echo "error:$rc"; return 0; fi
        [[ "$out" == *'"permissionDecision":"ask"'* ]] && echo fire || echo quiet
    }

    local fails=""
    # False positives that must stay QUIET (the reported bug + same-class cases).
    [[ "$(_cc_decides 'grep -n "SelectValue\|truncate\|line-clamp\|overflow" src/ui/select.tsx')" == quiet ]] || fails+=" css-truncate"
    [[ "$(_cc_decides 'grep truncate somefile')"        == quiet ]] || fails+=" grep-truncate"
    [[ "$(_cc_decides 'rg "DROP TABLE" src')"          == quiet ]] || fails+=" rg-drop-table"
    [[ "$(_cc_decides 'rg '\''psql -c "DROP TABLE users"'\'' docs')" == quiet ]] || fails+=" rg-sql-client-example"
    [[ "$(_cc_decides 'printf "TRUNCATE users"')"      == quiet ]] || fails+=" printf-truncate"
    [[ "$(_cc_decides 'TRUNCATE TABLE')"               == quiet ]] || fails+=" truncate-no-target"
    [[ "$(_cc_decides 'psql -c "TRUNCATE TABLE;"')"    == quiet ]] || fails+=" truncate-table-no-target"
    [[ "$(_cc_decides 'DROP TABLE')"                   == quiet ]] || fails+=" drop-table-no-target"
    [[ "$(_cc_decides 'psql -c "DROP DATABASE;')"      == quiet ]] || fails+=" drop-database-no-target"
    [[ "$(_cc_decides 'charm -rf out')"            == quiet ]] || fails+=" charm-rf"
    [[ "$(_cc_decides 'git checkout .gitignore')"  == quiet ]] || fails+=" checkout-dotfile"
    [[ "$(_cc_decides 'git checkout ./.gitignore')" == quiet ]] || fails+=" checkout-slash-dotfile"
    [[ "$(_cc_decides 'git restore ./.env')"       == quiet ]] || fails+=" restore-slash-dotfile"
    [[ "$(_cc_decides 'git checkout ./src')"       == quiet ]] || fails+=" checkout-subpath"
    [[ "$(_cc_decides 'git checkout "./src"')"     == quiet ]] || fails+=" checkout-quoted-subpath"
    # Real destructive ops that must still FIRE (no false negative introduced).
    [[ "$(_cc_decides 'psql -c "TRUNCATE users"')" == fire ]] || fails+=" truncate-sql"
    [[ "$(_cc_decides 'PGPASSWORD=x psql -c "TRUNCATE users"')" == fire ]] || fails+=" assigned-psql"
    [[ "$(_cc_decides 'env PGPASSWORD=x psql -c "TRUNCATE users"')" == fire ]] || fails+=" env-psql"
    [[ "$(_cc_decides 'mysql -e "DROP TABLE users"')" == fire ]] || fails+=" drop-mysql"
    [[ "$(_cc_decides 'psql -c "DROP TABLE users"')"  == fire ]] || fails+=" drop-psql"
    [[ "$(_cc_decides 'mysql -e "DROP DATABASE IF EXISTS sample"')" == fire ]] || fails+=" drop-if-exists"
    [[ "$(_cc_decides 'printf "DROP TABLE users" | sqlite3 app.db')" == fire ]] || fails+=" piped-sqlite"
    [[ "$(_cc_decides 'TRUNCATE TABLE foo')"       == fire ]] || fails+=" truncate-table"
    [[ "$(_cc_decides 'rm -rf /tmp/somewhere')"    == fire ]] || fails+=" rm-rf"
    [[ "$(_cc_decides 'foo; rm -rf /etc')"         == fire ]] || fails+=" rm-rf-chained"
    [[ "$(_cc_decides 'git checkout .')"           == fire ]] || fails+=" checkout-dot"
    [[ "$(_cc_decides 'git checkout ./')"          == fire ]] || fails+=" checkout-dotslash"
    [[ "$(_cc_decides 'git restore .')"            == fire ]] || fails+=" restore-dot"
    [[ "$(_cc_decides 'git restore ./')"           == fire ]] || fails+=" restore-dotslash"
    [[ "$(_cc_decides 'git checkout "."')"         == fire ]] || fails+=" checkout-quoted-dot"
    [[ "$(_cc_decides 'git restore "./"')"         == fire ]] || fails+=" restore-quoted-dotslash"
    [[ "$(_cc_decides 'git checkout -- .')"        == fire ]] || fails+=" checkout-separator-dot"
    [[ "$(_cc_decides 'git restore -- "./"')"      == fire ]] || fails+=" restore-separator-dotslash"
    [[ "$(_cc_decides 'git checkout .; printf done')" == fire ]] || fails+=" checkout-dot-chained"
    [[ "$(_cc_decides 'git restore ./&&printf done')" == fire ]] || fails+=" restore-dotslash-chained"

    rm -f "$sf"
    if [[ -z "$fails" ]]; then
        test_pass
    else
        test_fail "wrong careful decision for:$fails"
    fi
}

# ── Freeze hook: boundary enforcement ────────────────────────────────

test_freeze_reads_state_file() {
    test_case "freeze-check.sh reads state file from /tmp/octopus-freeze-*"
    if grep -c 'octopus-freeze-' "$FREEZE_HOOK" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "state file path not found"
    fi
}

test_freeze_checks_file_path() {
    test_case "freeze-check.sh extracts file_path from input"
    if grep -c 'file_path' "$FREEZE_HOOK" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "file_path extraction not found"
    fi
}

test_freeze_trailing_slash() {
    test_case "freeze-check.sh appends trailing / for prefix safety"
    if grep -c 'FREEZE_DIR.*/' "$FREEZE_HOOK" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "trailing slash logic not found"
    fi
}

test_freeze_gates_edit_write() {
    test_case "freeze-check.sh only gates Edit and Write tools"
    if grep -c '"Edit"' "$FREEZE_HOOK" >/dev/null 2>&1 && \
       grep -c '"Write"' "$FREEZE_HOOK" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "Edit/Write gating not found"
    fi
}

test_freeze_returns_deny_decision() {
    test_case "freeze-check.sh returns permissionDecision:deny for blocked files"
    if grep -c 'permissionDecision.*deny' "$FREEZE_HOOK" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "permissionDecision:deny not found in output"
    fi
}

# ── Command registration ─────────────────────────────────────────────

test_commands_exist() {
    test_case "All 4 safety command files exist"
    local missing=0
    for cmd in careful freeze guard unfreeze; do
        if [[ ! -f "$COMMANDS_DIR/$cmd.md" ]]; then
            echo "  MISSING: $cmd.md"
            missing=$((missing + 1))
        fi
    done
    if [[ $missing -eq 0 ]]; then
        test_pass
    else
        test_fail "$missing command file(s) missing"
    fi
}

test_commands_registered_in_plugin_json() {
    test_case "All 4 commands registered in plugin.json"
    local missing=0
    for cmd in careful freeze guard unfreeze; do
        if ! grep -c "commands/$cmd.md" "$PLUGIN_JSON" >/dev/null 2>&1; then
            echo "  NOT REGISTERED: $cmd.md"
            missing=$((missing + 1))
        fi
    done
    if [[ $missing -eq 0 ]]; then
        test_pass
    else
        test_fail "$missing command(s) not registered in plugin.json"
    fi
}

test_hooks_registered_in_hooks_json() {
    test_case "Hook scripts registered in hooks.json"
    local missing=0
    if ! grep -c 'careful-check.sh' "$HOOKS_JSON" >/dev/null 2>&1; then
        echo "  NOT REGISTERED: careful-check.sh"
        missing=$((missing + 1))
    fi
    if ! grep -c 'freeze-check.sh' "$HOOKS_JSON" >/dev/null 2>&1; then
        echo "  NOT REGISTERED: freeze-check.sh"
        missing=$((missing + 1))
    fi
    if [[ $missing -eq 0 ]]; then
        test_pass
    else
        test_fail "$missing hook(s) not registered in hooks.json"
    fi
}

# ── Skill-debug auto-freeze integration ──────────────────────────────

test_debug_skill_autofreeze() {
    test_case "skill-debug references auto-freeze integration"
    if grep -c 'octopus-freeze' "$SKILL_DEBUG" >/dev/null 2>&1 && \
       grep -c 'unfreeze' "$SKILL_DEBUG" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "auto-freeze integration not found in skill-debug"
    fi
}

activate_safety_hook_fixture() {
    local work="$1" block="$2" sid="$3" sf="$4" pid pid_sf rc
    # Hold the owned child before activation, then admit its actual PID path.
    # exec preserves $! so the historical PID-fallback mutant stays removable.
    mkfifo "$work/activate" || { return 1; }
    (cd "$work" && read -r _activate < "$work/activate" &&
        exec env -u CLAUDE_SESSION_ID OCTOPUS_HOST=claude "CLAUDE_CODE_SESSION_ID=$sid" bash -c "$block") &
    pid=$!
    pid_sf="/tmp/octopus-freeze-${pid}.txt"
    if [[ -e "$pid_sf" || -L "$pid_sf" ]]; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        rm -f "$work/activate"
        echo "PID fixture already exists; refused to touch it" >&2
        return 1
    fi
    if [[ -e "$sf" || -L "$sf" ]]; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        rm -f "$work/activate"
        echo "session fixture already exists; refused to touch it" >&2
        return 1
    fi
    printf '\n' > "$work/activate"
    rc=0; wait "$pid" || rc=$?
    rm -f "$work/activate"
    if [[ -e "$pid_sf" || -L "$pid_sf" ]]; then
        record_safety_hook_state "$pid_sf" "$work/module" || return 1
        cleanup_safety_hook_state "$pid_sf" || return 1
    fi
    return "$rc"
}

test_debug_skill_autofreeze_reaches_hook() {
    test_case "skill-debug auto-freeze writes the state file freeze-check.sh and /octo:unfreeze use, and keeps an existing freeze"
    # Run each skill copy's freeze block the way a Claude Code Bash tool call runs it:
    # CLAUDE_CODE_SESSION_ID exported, CLAUDE_SESSION_ID unset. The hook gets the same
    # session id from its JSON input, so a block keyed on anything else (the shell
    # PID) writes a file the hook never reads and the boundary is silently unenforced.
    local sid sf
    local work fails="" skill label block unfreeze_block rc
    work=$(mktemp -d "$TEST_TMP_DIR/safety-hooks.XXXXXX") || { test_fail "mktemp failed"; return; }
    work=$(cd "$work" && pwd -P) || { test_fail "fixture path resolution failed"; return; }
    sid="octo-debug-freeze-${work##*/}"
    sf="/tmp/octopus-freeze-${sid}.txt"
    if [[ -e "$sf" || -L "$sf" ]]; then
        test_fail "session fixture already exists; refused to touch it"
        return
    fi
    mkdir -p "$work/module" "$work/outside"
    unfreeze_block=$(awk '/^```bash/{b=1;next} b&&/^```/{exit} b' "$COMMANDS_DIR/unfreeze.md")

    # Prints the hook's verdict for an Edit of $1: deny, allow, or error:<rc>.
    _freeze_decides() {
        local out rc=0
        out=$(jq -cn --arg s "$sid" --arg c "$work" --arg f "$1" \
                '{session_id:$s,hook_event_name:"PreToolUse",tool_name:"Edit",cwd:$c,
                  tool_input:{file_path:$f,old_string:"a",new_string:"b"}}' \
            | env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_SESSION_ID -u OCTO_FREEZE_MODE \
                OCTOPUS_HOST=claude bash "$FREEZE_HOOK" 2>/dev/null) || rc=$?
        if (( rc != 0 )); then echo "error:$rc"; return 0; fi
        [[ "$out" == *'"permissionDecision":"deny"'* ]] && echo deny || echo allow
    }

    for skill in "$SKILL_DEBUG" "$PROJECT_ROOT/skills/skill-debug/SKILL.md"; do
        label="${skill#"$PROJECT_ROOT"/}"
        cleanup_safety_hook_state "$sf"
        block=$(awk '/^## Scoped freeze guard/{s=1} s&&/^```bash/{b=1;next} b&&/^```/{exit} b' "$skill")
        if [[ -z "$block" ]]; then fails+=" $label:no-freeze-block"; continue; fi
        block="${block//<module-directory>/$work/module}"
        if ! activate_safety_hook_fixture "$work" "$block" "$sid" "$sf"; then
            fails+=" $label:block-failed"
            continue
        fi
        if [[ ! -f "$sf" ]]; then fails+=" $label:state-file-not-session-keyed"; continue; fi
        record_safety_hook_state "$sf" "$work/module" || { test_fail "session fixture ownership failed"; return; }
        [[ "$(_freeze_decides "$work/outside/x.txt")" == deny ]] || fails+=" $label:outside-edit-not-denied"
        [[ "$(_freeze_decides "$work/module/x.txt")" == allow ]] || fails+=" $label:inside-edit-not-allowed"
        (cd "$work" && env -u CLAUDE_SESSION_ID OCTOPUS_HOST=claude "CLAUDE_CODE_SESSION_ID=$sid" bash -c "$unfreeze_block")
        [[ ! -f "$sf" ]] || fails+=" $label:unfreeze-left-state"
        cleanup_safety_hook_state "$sf"

        # A freeze the user already set (here, on another directory) must survive.
        (set -C; printf '%s\n' "$work/outside" > "$sf") || { test_fail "existing-state fixture creation failed"; return; }
        record_safety_hook_state "$sf" "$work/outside" || { test_fail "existing-state fixture ownership failed"; return; }
        (cd "$work" && env -u CLAUDE_SESSION_ID OCTOPUS_HOST=claude "CLAUDE_CODE_SESSION_ID=$sid" bash -c "$block") >/dev/null
        [[ "$(cat "$sf" 2>/dev/null)" == "$work/outside" ]] || fails+=" $label:replaced-existing-freeze"

        # Empty state is refused for inspection, with the hook still failing closed.
        : > "$sf"
        rc=0
        (cd "$work" && env -u CLAUDE_SESSION_ID OCTOPUS_HOST=claude "CLAUDE_CODE_SESSION_ID=$sid" bash -c "$block") >/dev/null 2>&1 || rc=$?
        (( rc != 0 )) || fails+=" $label:admitted-empty-state"
        [[ -f "$sf" && ! -s "$sf" ]] || fails+=" $label:changed-empty-state"
        [[ "$(_freeze_decides "$work/outside/x.txt")" == deny ]] || fails+=" $label:empty-state-outside-edit-not-denied"
        cleanup_safety_hook_state "$sf"
    done

    cleanup_safety_hook_state "$sf"
    SAFETY_HOOK_STATE_FILES=()
    SAFETY_HOOK_STATE_IDENTITIES=()
    rm -rf "$work"
    if [[ -z "$fails" ]]; then
        test_pass
    else
        test_fail "skill-debug auto-freeze:$fails"
    fi
}

# ── No attribution leaks ─────────────────────────────────────────────

test_no_attribution_leaks() {
    test_case "No forbidden attribution references in safety hook files"
    local leaked=0
    for file in "$CAREFUL_HOOK" "$FREEZE_HOOK" \
                "$COMMANDS_DIR/careful.md" "$COMMANDS_DIR/freeze.md" \
                "$COMMANDS_DIR/guard.md" "$COMMANDS_DIR/unfreeze.md"; do
        for pattern in gstack gsd; do
            if grep -ci "$pattern" "$file" >/dev/null 2>&1; then
                echo "  LEAK in $(basename "$file"): found '$pattern'"
                leaked=$((leaked + 1))
            fi
        done
    done
    if [[ $leaked -eq 0 ]]; then
        test_pass
    else
        test_fail "$leaked attribution leak(s) found"
    fi
}

# ── Run all tests ────────────────────────────────────────────────────

test_careful_hook_exists
test_freeze_hook_exists
test_careful_hook_valid_syntax
test_freeze_hook_valid_syntax

test_careful_rm_rf_pattern
test_careful_safe_exceptions
test_careful_sql_patterns
test_careful_git_force_push
test_careful_git_reset_hard
test_careful_git_checkout_dot
test_careful_kubectl_delete
test_careful_docker_destructive
test_careful_reads_state_file
test_careful_returns_ask_decision
test_careful_statement_shape_not_substring
test_freeze_reads_state_file
test_freeze_checks_file_path
test_freeze_trailing_slash
test_freeze_gates_edit_write
test_freeze_returns_deny_decision

test_commands_exist
test_commands_registered_in_plugin_json
test_hooks_registered_in_hooks_json

test_debug_skill_autofreeze
test_debug_skill_autofreeze_reaches_hook
test_no_attribution_leaks

test_summary
