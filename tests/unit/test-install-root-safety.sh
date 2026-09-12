#!/usr/bin/env bash
# Installation safety acceptance checks on disposable files and real processes.
# Child shell snippets intentionally expand their own variables.
# shellcheck disable=SC2016
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TEST_BASH="${TEST_BASH:-/bin/bash}"
work="$(mktemp -d "${TMPDIR:-/tmp}/octo-install-safety.XXXXXX")"
trap 'rm -rf "$work"' EXIT
passed=0 failed=0
check() {
    if "$@"; then passed=$((passed + 1)); printf 'PASS %s\n' "$*"
    else failed=$((failed + 1)); printf 'FAIL %s\n' "$*"; fi
}
fixture() {
    mkdir -p "$1/.claude-plugin" "$1/.codex-plugin" "$1/scripts" "$1/skills" "$1/commands" "$1/assets"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "fixture runtime\\n"' > "$1/scripts/orchestrate.sh"
    chmod +x "$1/scripts/orchestrate.sh"
    printf 'command\n' > "$1/commands/test.md"
    printf '<svg/>\n' > "$1/assets/icon.svg"
    printf '%s\n' '{"version":"1.0.0","skills":"./skills","commands":["./commands/test.md"]}' > "$1/.claude-plugin/plugin.json"
    printf '%s\n' '{"version":"1.0.0","skills":"./skills","interface":{"composerIcon":"./assets/icon.svg"}}' > "$1/.codex-plugin/plugin.json"
}
run_cli() {
    local command="$1" root="$2" stable="$3" host="${4:-claude}"
    shift 4
    env -u CLAUDE_PLUGIN_ROOT -u CODEX_PLUGIN_ROOT -u CODEX_HOME \
        "HOME=$work/home" "OCTOPUS_HOST=$host" \
        "OCTOPUS_STABLE_PLUGIN_ROOT=$stable" "OCTOPUS_INSTALL_STATE_FILE=$work/state.json" \
        "OCTOPUS_CLAUDE_CACHE_DIR=$work/claude-cache" "OCTOPUS_CODEX_CACHE_DIR=$work/codex-cache" \
        "$(if [[ "$host" == codex ]]; then printf CODEX; else printf CLAUDE; fi)_PLUGIN_ROOT=$root" \
        "$TEST_BASH" "$PROJECT_ROOT/scripts/$command.sh" "$@" > "$work/result.json" 2> "$work/diagnostic.txt"
}
active_check() {
    local kind="$1" host="$2" rc=0
    local root="$work/$kind-$host"
    case "$kind" in
        absent) ;;
        invalid) mkdir -p "$root" ;;
        valid) fixture "$root" ;;
    esac
    run_cli cache-check "$root" "$work/no-stable" "$host" --json || rc=$?
    if [[ "$kind" == valid ]]; then
        [[ "$rc" == 0 ]] && jq -e --arg host "$host" '.checks[] | select(.host==$host and .role=="active" and .status=="pass")' "$work/result.json" >/dev/null
    else
        [[ "$rc" != 0 ]] && jq -e --arg host "$host" '.failures>0 and any(.checks[]; .host==$host and .role=="active" and .status=="fail")' "$work/result.json" >/dev/null
    fi
}
for cache in absent empty; do
    [[ "$cache" == absent ]] || mkdir -p "$work/claude-cache" "$work/codex-cache"
    for host in claude codex; do
        for kind in absent invalid valid; do check active_check "$kind" "$host"; done
    done
done

manifest_check() {
    local problem="$1" host=claude root="$work/manifest-$1" rc=0 manifest
    fixture "$root"
    case "$problem" in icon-*) host=codex ;; esac
    manifest="$root/.$host-plugin/plugin.json"
    case "$problem" in
        skill-file) rmdir "$root/skills"; printf data > "$root/skills" ;;
        command-directory) rm "$root/commands/test.md"; mkdir "$root/commands/test.md" ;;
        traversal) jq '.skills="../outside"' "$manifest" > "$work/edit.json"; mv "$work/edit.json" "$manifest" ;;
        absolute) jq --arg path "$work/outside" '.skills=$path' "$manifest" > "$work/edit.json"; mv "$work/edit.json" "$manifest" ;;
        symlink) rmdir "$root/skills"; ln -s "$work/outside" "$root/skills" ;;
        wrong-type) jq '.skills=42' "$manifest" > "$work/edit.json"; mv "$work/edit.json" "$manifest" ;;
        empty-version) jq '.version=""' "$manifest" > "$work/edit.json"; mv "$work/edit.json" "$manifest" ;;
        json-stream) cat "$manifest" > "$work/edit.json"; cat "$work/edit.json" >> "$manifest" ;;
        runtime-directory) rm "$root/scripts/orchestrate.sh"; mkdir "$root/scripts/orchestrate.sh" ;;
        runtime-symlink) rm "$root/scripts/orchestrate.sh"; ln -s "$work/good/scripts/orchestrate.sh" "$root/scripts/orchestrate.sh" ;;
        icon-missing) rm "$root/assets/icon.svg" ;;
        icon-directory) rm "$root/assets/icon.svg"; mkdir "$root/assets/icon.svg" ;;
        icon-symlink) rm "$root/assets/icon.svg"; ln -s "$work/good/assets/icon.svg" "$root/assets/icon.svg" ;;
        icon-wrong-type) jq '.interface.composerIcon=[]' "$manifest" > "$work/edit.json"; mv "$work/edit.json" "$manifest" ;;
    esac
    mkdir -p "$work/$host-cache"
    ln -s "$root" "$work/$host-cache/1.0.0"
    run_cli cache-check "$root" "$work/no-stable" "$host" --json || rc=$?
    rm "$work/$host-cache/1.0.0"
    [[ "$rc" != 0 ]] && jq -e '.checks[] | select(.role=="active" and .status=="fail")' "$work/result.json" >/dev/null
}
fixture "$work/good"
mkdir "$work/outside"
for problem in skill-file command-directory traversal absolute symlink wrong-type empty-version json-stream runtime-directory runtime-symlink icon-missing icon-directory icon-symlink icon-wrong-type; do
    check manifest_check "$problem"
done

repair_invalid() {
    local mode="$1" rc=0 root="$work/bad-target-$1"
    fixture "$root"
    printf '{invalid\n' > "$root/.claude-plugin/plugin.json"
    printf keep > "$root/user-data"
    run_cli repair "$root" "$root" claude "$mode" --json || rc=$?
    [[ "$rc" != 0 && "$(cat "$root/user-data")" == keep ]] &&
        [[ ! -e "$work/state.json" ]] && jq -e '.result=="blocked"' "$work/result.json" >/dev/null
}
check repair_invalid --dry-run
check repair_invalid --apply

unreadable_root() {
    local command="$1" root="$work/claude-cache/3.0.0" rc=0 valid=0
    fixture "$root"
    chmod 000 "$root"
    run_cli "$command" "$root" "$work/no-stable" claude --json || rc=$?
    chmod 700 "$root"
    if [[ "$command" == repair ]]; then
        [[ "$rc" != 0 ]] && jq -e '.result=="blocked"' "$work/result.json" >/dev/null || valid=1
    else
        [[ "$rc" != 0 ]] && jq -e '.failures>0' "$work/result.json" >/dev/null || valid=1
    fi
    rm -rf "$root"
    return "$valid"
}
check unreadable_root cache-check
check unreadable_root repair

wrapper() {
    local quoted
    mkdir -p "$(dirname "$2")"
    printf -v quoted '%q' "$1"
    printf '#!/usr/bin/env bash\nexec %s "$@"\n' "$quoted" > "$2"
    chmod +x "$2"
}
shim_preserved() {
    local kind="$1" stable="$work/shim-$1" rc=0
    wrapper "$work/old/scripts/orchestrate.sh" "$stable/scripts/orchestrate.sh"
    case "$kind" in
        appended) printf 'printf user-customization\n' >> "$stable/scripts/orchestrate.sh" ;;
        blank-line) printf '\n' >> "$stable/scripts/orchestrate.sh" ;;
        secondary) printf 'user script\n' > "$stable/scripts/install-deps.sh" ;;
        symlink) mv "$stable/scripts" "$work/external-scripts"; ln -s "$work/external-scripts" "$stable/scripts" ;;
    esac
    cp "$stable/scripts/orchestrate.sh" "$work/before"
    run_cli repair "$work/good" "$stable" claude --apply --json || rc=$?
    [[ "$rc" != 0 ]] && cmp -s "$work/before" "$stable/scripts/orchestrate.sh" &&
        jq -e '.result=="blocked"' "$work/result.json" >/dev/null &&
        { [[ "$kind" != secondary ]] || [[ "$(cat "$stable/scripts/install-deps.sh")" == 'user script' ]]; }
}
printf '#!/usr/bin/env bash\nexit 0\n' > "$work/good/scripts/install-deps.sh"
chmod +x "$work/good/scripts/install-deps.sh"
for kind in appended blank-line secondary symlink; do check shim_preserved "$kind"; done

repair_owned() {
    local kind="$1" stable="$work/owned-$1"
    if [[ "$kind" == shim ]]; then wrapper "$work/old with space/scripts/orchestrate.sh" "$stable/scripts/orchestrate.sh"
    else ln -s "$work/missing" "$stable"; fi
    run_cli repair "$work/good" "$stable" claude --apply --json &&
        jq -e '.result=="ready"' "$work/result.json" >/dev/null &&
        [[ "$("$stable/scripts/orchestrate.sh")" == 'fixture runtime' ]]
}
check repair_owned shim
check repair_owned link

record() {
    env "HOME=$work/home" "OCTOPUS_INSTALL_STATE_FILE=$1" "OCTOPUS_HOST=$2" \
        "CLAUDE_PLUGIN_ROOT=$work/good" "CODEX_PLUGIN_ROOT=$work/good" \
        "$TEST_BASH" -c 'source "$1"; octo_lifecycle_record_install' _ "$PROJECT_ROOT/scripts/lib/lifecycle.sh"
}
receipt_directory() {
    local state="$work/directory-state" rc=0 intact=0
    mkdir "$state"
    printf keep > "$state/user-data"
    record "$state" claude || rc=$?
    # A broken writer may chmod the directory; restore fixture access for cleanup.
    chmod 700 "$state"
    [[ "$rc" != 0 && "$(ls -A "$state")" == user-data && "$(cat "$state/user-data")" == keep ]] || intact=1
    return "$intact"
}
check receipt_directory

receipt_preserved() {
    local kind="$1" state="$work/receipt-$1.json" rc=0
    case "$kind" in malformed) printf '{user-data\n' > "$state" ;; unknown) printf '{"user_data":"keep"}\n' > "$state" ;; esac
    cp "$state" "$state.before"
    record "$state" claude || rc=$?
    [[ "$rc" != 0 ]] && cmp -s "$state.before" "$state"
}
check receipt_preserved malformed
check receipt_preserved unknown

receipt_cleanup() {
    local state="$work/cleanup.json"
    record "$state" claude && [[ ! -e "$state.lock" ]]
}
check receipt_cleanup

receipt_diagnostic() {
    local state="$work/diagnostic-state.json" rc=0
    printf '%s\n' '{"schema":2,"hosts":{}}' '{"schema":2,"hosts":{}}' > "$state"
    env "HOME=$work/home" "OCTOPUS_INSTALL_STATE_FILE=$state" "OCTOPUS_HOST=claude" \
        "CLAUDE_PLUGIN_ROOT=$work/good" "$TEST_BASH" -c \
        'source "$1"; octo_lifecycle_state_json' _ "$PROJECT_ROOT/scripts/lib/lifecycle.sh" > "$work/state-diagnostic.json" 2>/dev/null || rc=$?
    [[ "$rc" == 0 ]] && jq -e '.current==false and .recorded==null' "$work/state-diagnostic.json" >/dev/null
}
check receipt_diagnostic

interrupted_writer() {
    local signal="$1" state="$work/interrupted-$1.json" pid launcher rc=0 i
    env "HOME=$work/home" "OCTOPUS_INSTALL_STATE_FILE=$state" "CLAUDE_PLUGIN_ROOT=$work/good" \
        "OCTOPUS_HOST=claude" "$TEST_BASH" -c '
        source "$1"
        marker="$2"
        eval "$(declare -f _octo_lifecycle_lock | sed "1s/_octo_lifecycle_lock/_original_lock/")"
        _octo_lifecycle_lock() {
            _original_lock "$@" || return
            sh -c '\''echo "$PPID"'\'' > "$marker"
            while [[ ! -f "$marker.release" ]]; do sleep 0.02; done
        }
        octo_lifecycle_record_install
    ' _ "$PROJECT_ROOT/scripts/lib/lifecycle.sh" "$state.ready" > "$state.log" 2>&1 &
    launcher=$!
    for ((i=0; i<250; i++)); do [[ -s "$state.ready" ]] && break; sleep 0.02; done
    if [[ ! -s "$state.ready" ]]; then kill "$launcher" 2>/dev/null || true; wait "$launcher" 2>/dev/null || true; return 1; fi
    pid="$(cat "$state.ready")"
    if [[ "$signal" == LIVE ]]; then
        record "$state" codex >/dev/null 2>&1 || rc=$?
        [[ "$rc" != 0 && -d "$state.lock" ]] || rc=0
        touch "$state.ready.release"
        wait "$launcher" || return 1
        [[ "$rc" != 0 ]] || return 1
    else
        kill "-$signal" "$pid"
        wait "$launcher" 2>/dev/null || true
        if [[ "$signal" == TERM && -e "$state.lock" ]]; then return 1; fi
    fi
    record "$state" claude && record "$state" codex &&
        jq -e '.hosts.claude.host=="claude" and .hosts.codex.host=="codex"' "$state" >/dev/null
}
check interrupted_writer TERM
check interrupted_writer KILL
check interrupted_writer LIVE

concurrent_records() {
    local i state="$work/concurrent.json" first second
    for ((i=0; i<5; i++)); do
        rm -f "$state"
        record "$state" claude & first=$!
        record "$state" codex & second=$!
        wait "$first" || return 1
        wait "$second" || return 1
        jq -e '.hosts | has("claude") and has("codex")' "$state" >/dev/null || return 1
    done
}
check concurrent_records
reference_input_failure() {
    if [[ "$(uname -s)" != Darwin ]] || ! command -v sandbox-exec >/dev/null 2>&1; then
        printf 'SKIP native Bash temporary-file denial requires macOS\n'
        return 0
    fi
    local root="$work/no-temp-root"
    fixture "$root"
    sandbox-exec -p '(version 1)(allow default)(deny file-write*)(allow file-write* (literal "/dev/null"))' /bin/bash -c '
        source "$1"
        if octo_validate_install_root "$2" claude; then exit 1; fi
    ' _ "$PROJECT_ROOT/scripts/lib/install-root.sh" "$root" 2>/dev/null
}
check reference_input_failure
printf '%s passed, %s failed\n' "$passed" "$failed"
[[ "$failed" == 0 ]]
