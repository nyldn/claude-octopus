#!/usr/bin/env bash
# Installation safety acceptance checks on disposable files and real processes.
# Child shell snippets intentionally expand their own variables.
# shellcheck disable=SC2016
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TEST_BASH="${TEST_BASH:-/bin/bash}"
# shellcheck source=tests/helpers/test-framework.sh
source "$PROJECT_ROOT/tests/helpers/test-framework.sh"
test_suite "Installation root safety and handoff redaction"
work="$TEST_TMP_DIR/install-safety"
mkdir -p "$work"
check() {
    test_case "$*"
    if "$@"; then test_pass; else test_fail "$*"; fi
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

missing_wrapper() {
    local stable="$work/missing-wrapper" rc=0
    wrapper "$(cd "$work/good" && pwd -P)/scripts/orchestrate.sh" "$stable/scripts/orchestrate.sh"
    run_cli repair "$work/good" "$stable" claude --dry-run --json || return 1
    jq -e '.status=="mismatch"' "$work/result.json" >/dev/null || return 1
    [[ ! -e "$stable/scripts/install-deps.sh" ]] || return 1
    run_cli repair "$work/good" "$stable" claude --apply --json || rc=$?
    [[ "$rc" == 0 && -x "$stable/scripts/install-deps.sh" ]] &&
        "$stable/scripts/install-deps.sh" &&
        jq -e '.result=="ready" and .status=="shim"' "$work/result.json" >/dev/null
}
check missing_wrapper

profile_parity() {
    local origin="$1" value="$2" expected="$3" override="${4:-}" hooks="${5:-$3}"
    local profile_home="$work/profile-$origin-$value-$override" context="$2"
    mkdir -p "$profile_home/.claude-octopus"
    if [[ "$origin" == config ]]; then
        jq -cn --arg value "$value" '{context_profile:$value}' > "$profile_home/.claude-octopus/user-config.json"
        context=""
    fi
    env "HOME=$profile_home" "OCTOPUS_CONTEXT_PROFILE=$context" "OCTOPUS_HOOK_PROFILE=$override" \
        "OCTOPUS_HOST=claude" "CLAUDE_PLUGIN_ROOT=$work/good" \
        "OCTOPUS_INSTALL_STATE_FILE=$profile_home/receipt.json" \
        "$TEST_BASH" -c '
        source "$1/scripts/lib/lifecycle.sh"
        source "$1/scripts/lib/hook-activation.sh"
        [[ "$(octo_lifecycle_profile)" == "$2" && "$(octo_hook_profile)" == "$3" &&
           "$(octo_lifecycle_hook_profile)" == "$3" ]] || exit 1
        octo_lifecycle_record_install && octo_lifecycle_state_valid || exit 1
        jq -e --arg context "$2" --arg hooks "$3" \
            ".hosts.claude | .context_profile==\$context and .hook_profile==\$hooks" "$OCTO_LIFECYCLE_STATE_FILE" >/dev/null
    ' _ "$PROJECT_ROOT" "$expected" "$hooks"
}
for origin in env config; do
    for pair in core:core minimal:core orchestration:orchestration workflow:orchestration full:full all:full invalid:core; do
        check profile_parity "$origin" "${pair%:*}" "${pair#*:}"
    done
    check profile_parity "$origin" workflow orchestration all full
    check profile_parity "$origin" all full minimal core
done

handoff_redaction() {
    local kind="$1" source_kind="$2" sample handoff_home="$work/handoff-$1-$2"
    local state session out safe=$'Keep "SQLite"\nUse https://localhost/db and C:\\data'
    state="$handoff_home/state"; session="$handoff_home/data"; out="$handoff_home/out"
    mkdir -p "$state" "$session" "$out" "$handoff_home/bin"
    case "$kind" in
        aws) sample='AKIA0123456789ABCDEF' ;;
        aws-session) sample='ASIA0123456789ABCDEF' ;;
        github-oauth) sample='gho_synthetic0123456789abcdefghijklmnopqrstuvwxyz' ;;
        gitlab) sample='glpat-synthetic0123456789abcdef' ;;
        slack-bot) sample='xoxb'; sample="${sample}-000000000000-000000000000-syntheticexample" ;;
        slack-user) sample='xoxp'; sample="${sample}-000000000000-000000000000-syntheticexample" ;;
        jwt) sample='eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJzeW50aGV0aWMifQ.c3ludGhldGlj' ;;
        jwt-empty-object) sample='eyJhbGciOiJIUzI1NiJ9.e30.c3ludGhldGlj' ;;
        pem) sample=$'-----BEGIN RSA PRIVATE KEY-----\nU1lOVEhFVElDLUtFWS1EQVRB\n-----END RSA PRIVATE KEY-----' ;;
        pem-partial) sample=$'-----BEGIN OPENSSH PRIVATE KEY-----\nU1lOVEhFVElDLUtFWS1EQVRB' ;;
        postgres) sample='postgres://fixture:synthetic-value@localhost/db' ;;
        postgresql) sample='postgresql://fixture:synthetic-value@localhost/db' ;;
        mysql) sample='mysql://fixture:synthetic-value@localhost/db' ;;
        mongodb) sample='mongodb+srv://fixture:synthetic-value@localhost/db' ;;
        redis) sample='rediss://fixture:synthetic-value@localhost/0' ;;
        https) sample='https://fixture:synthetic%2Fvalue@localhost/' ;;
    esac
    if [[ "$source_kind" == session ]]; then
        jq -cn --arg value "$sample" --arg safe "$safe" '{workflow:$value,current_phase:$value,status:$value,autonomy:$value,
            decisions:[$value,$safe],blockers:[$value]}' > "$session/session.json"
    else
        jq -cn --arg value "$sample" --arg safe "$safe" '{current_workflow:$value,current_phase:$value,
            decisions:[{decision:$value},{decision:$safe}],blockers:[{description:$value,status:"active"}]}' > "$state/state.json"
    fi
    # Inspect the staged export before publication, including JSON delimiters.
    cat > "$handoff_home/bin/mv" <<'EOF'
#!/bin/bash
if ! "$REAL_JQ" -e --arg value "$SYNTHETIC_VALUE" \
    'type=="object" and ([.. | strings] | all(contains($value) | not))' "$2" >/dev/null; then exit 99; fi
exec /bin/mv "$@"
EOF
    chmod +x "$handoff_home/bin/mv"
    env "HOME=$handoff_home" "CLAUDE_PLUGIN_DATA=$session" "OCTOPUS_WORKFLOW_STATE_DIR=$state" \
        "OCTOPUS_PROJECT_DIR=$handoff_home/project-AKIA0123456789ABCDEF" "PATH=$handoff_home/bin:$PATH" \
        "REAL_JQ=$(command -v jq)" "SYNTHETIC_VALUE=$sample" \
        "$TEST_BASH" "$PROJECT_ROOT/scripts/handoff.sh" export --json --out "$out/export.json" \
        > "$handoff_home/stdout" 2> "$handoff_home/stderr" || return 1
    cmp -s "$out/export.json" "$handoff_home/stdout" &&
        jq -e --arg value "$sample" --arg safe "$safe" --arg source "$source_kind" '
            .schema==1 and .workflow=="[REDACTED]" and .phase=="[REDACTED]" and
            .project_name=="[REDACTED]" and .decisions==["[REDACTED]",$safe] and .blockers==["[REDACTED]"] and
            .status==(if $source=="session" then "[REDACTED]" else "unknown" end) and
            .autonomy==(if $source=="session" then "[REDACTED]" else "supervised" end) and
            ([.. | strings] | all(contains($value) | not))' "$out/export.json" >/dev/null
}
for kind in aws aws-session github-oauth gitlab slack-bot slack-user jwt jwt-empty-object pem pem-partial postgres postgresql mysql mongodb redis https; do
    for source_kind in session state; do check handoff_redaction "$kind" "$source_kind"; done
done

handoff_failure() {
    local kind="$1" root="$work/handoff-failure-$1" rc=0
    mkdir -p "$root/data" "$root/state" "$root/out" "$root/bin"
    printf '{"keep":"existing export"}\n' > "$root/out/export.json"
    cp "$root/out/export.json" "$root/before"
    case "$kind" in
        session) printf '{invalid' > "$root/data/session.json" ;;
        state) printf '{invalid' > "$root/state/state.json" ;;
        sanitizer)
            cat > "$root/bin/jq" <<'EOF'
#!/bin/bash
for arg in "$@"; do [[ "$arg" != project_id ]] || exit 42; done
exec "$REAL_JQ" "$@"
EOF
            chmod +x "$root/bin/jq"
            ;;
    esac
    env "HOME=$root" "CLAUDE_PLUGIN_DATA=$root/data" "OCTOPUS_WORKFLOW_STATE_DIR=$root/state" \
        "OCTOPUS_PROJECT_DIR=$root/project" "REAL_JQ=$(command -v jq)" "PATH=$root/bin:$PATH" \
        "$TEST_BASH" "$PROJECT_ROOT/scripts/handoff.sh" export --json --out "$root/out/export.json" \
        > "$root/stdout" 2> "$root/stderr" || rc=$?
    [[ "$rc" != 0 && ! -s "$root/stdout" && "$(ls -A "$root/out")" == export.json ]] &&
        cmp -s "$root/before" "$root/out/export.json"
}
for kind in session state sanitizer; do check handoff_failure "$kind"; done

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
    local root="$work/no-temp-root"
    fixture "$root"
    sandbox-exec -p '(version 1)(allow default)(deny file-write*)(allow file-write* (literal "/dev/null"))' /bin/bash -c '
        source "$1"
        if octo_validate_install_root "$2" claude; then exit 1; fi
    ' _ "$PROJECT_ROOT/scripts/lib/install-root.sh" "$root" 2>/dev/null
}
test_case "reference_input_failure"
if [[ "$(uname -s)" != Darwin ]] || ! command -v sandbox-exec >/dev/null 2>&1; then
    test_skip "Native Bash temporary-file denial requires macOS sandbox-exec"
elif ! sandbox-exec -p '(version 1)(allow default)' /usr/bin/true 2>/dev/null; then
    test_skip "macOS sandbox-exec cannot start in this environment"
elif reference_input_failure; then
    test_pass
else
    test_fail "Native Bash temporary-file denial was not rejected"
fi
test_summary
