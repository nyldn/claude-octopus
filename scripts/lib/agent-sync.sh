#!/usr/bin/env bash
_agent_sync_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_agent_sync_lib_dir}/agent-spec.sh" 2>/dev/null || true
source "${_agent_sync_lib_dir}/provider-registry.sh" || { echo "agent-sync: failed to load provider-registry.sh" >&2; return 1 2>/dev/null || exit 1; }
source "${_agent_sync_lib_dir}/fallback-chain.sh" 2>/dev/null || true
# ═══════════════════════════════════════════════════════════════════════════════
# agent-sync.sh — Agent synchronous dispatch & Agent Teams routing
# Extracted from orchestrate.sh (v9.7.4)
# ═══════════════════════════════════════════════════════════════════════════════

# ── Fleet dispatch guards ─────────────────────────────────────────────────────
# orchestrate.sh runs as a Bash tool subprocess. Agent Teams dispatch writes
# AGENT_TEAMS_DISPATCH: signals to stdout that CC's host never sees in that
# context, leaving all result files empty (issue #289, #288).
#
# Every parallel spawn loop MUST call fleet_dispatch_begin before the first
# spawn_agent call and fleet_dispatch_end after the last one. The smoke test
# tests/smoke/test-fleet-dispatch-guard.sh enforces this statically.
_octopus_agent_sync_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! type start_quota_watcher >/dev/null 2>&1; then
    source "${_octopus_agent_sync_lib_dir}/quota-watcher.sh" 2>/dev/null || true
fi
if ! type is_claude_agent_type >/dev/null 2>&1; then
    source "${_octopus_agent_sync_lib_dir}/routing.sh" 2>/dev/null || true
fi
if ! type run_contract_transition >/dev/null 2>&1; then
    source "${_octopus_agent_sync_lib_dir}/run-contract.sh" 2>/dev/null || true
fi
if ! type classify_agent_output >/dev/null 2>&1; then
    source "${_octopus_agent_sync_lib_dir}/error-tracking.sh" 2>/dev/null || true
fi

fleet_dispatch_begin() {
    export OCTOPUS_FORCE_LEGACY_DISPATCH=true
}

quota_watcher_kill_sync_dispatch() {
    local dispatch_pid="$1"
    pkill -KILL -P "$dispatch_pid" 2>/dev/null || true
    kill -KILL "$dispatch_pid" 2>/dev/null || true
}

fleet_dispatch_end() {
    unset OCTOPUS_FORCE_LEGACY_DISPATCH
}

# Bind a resolved AGY model to the exact argv environment used by agy-exec.
# This keeps provider execution aligned with lifecycle and cost records, while
# preserving model labels containing spaces as one environment argument.
octopus_sync_bind_resolved_model() {
    local agent_type="${1:-}" model="${2:-}" provider="" entry
    local -a filtered_env
    provider="$(octo_agent_spec_provider "$agent_type" 2>/dev/null || true)"
    [[ "$provider" == "agy" && -n "$model" ]] || return 0

    filtered_env=()
    if [[ ${#PROVIDER_ENV_ARRAY[@]} -gt 0 ]]; then
        for entry in "${PROVIDER_ENV_ARRAY[@]}"; do
            [[ "$entry" == OCTOPUS_AGY_MODEL=* ]] && continue
            filtered_env+=("$entry")
        done
    fi
    if [[ ${#filtered_env[@]} -eq 0 ]]; then
        filtered_env=(env)
    fi
    filtered_env+=("OCTOPUS_AGY_MODEL=$model")
    PROVIDER_ENV_ARRAY=("${filtered_env[@]}")
}

# Claude Code's native Agent Teams API does not expose a provider PID or a
# timeout/cancellation handle to plugin scripts. A positive Octopus timeout
# therefore cannot be enforced on that path: Claude Code documents that team
# shutdown waits for the teammate's current request/tool call. Keep native
# dispatch only for explicitly unlimited work; bounded work uses the supervised
# provider subprocess where run_with_timeout owns the process tree.
octopus_agent_teams_can_honor_timeout() {
    local effective_timeout="${1:-}"
    [[ "$effective_timeout" =~ ^[0-9]+$ ]] || return 1
    [[ "$effective_timeout" -eq 0 ]]
}

# Return the integer timeout for one synchronous attempt within a fixed
# wall-clock deadline. Retried attempts reserve one second because date(1) and
# run_with_timeout both operate at whole-second precision; without that margin,
# differing fractional start times can extend the original budget by <1s.
octopus_sync_attempt_timeout() {
    local deadline="$1"
    local now="$2"
    local retry_count="${3:-0}"
    local remaining

    [[ "$deadline" =~ ^[0-9]+$ && "$now" =~ ^[0-9]+$ && "$retry_count" =~ ^[0-9]+$ ]] || return 1
    remaining=$((deadline - now))
    if [[ "$retry_count" -gt 0 ]]; then
        remaining=$((remaining - 1))
    fi
    [[ "$remaining" -gt 0 ]] || return 1
    printf '%s\n' "$remaining"
}

# Check if an agent should use Agent Teams dispatch
# Returns 0 (true) if agent should use native teams, 1 (false) for legacy bash
should_use_agent_teams() {
    local agent_type="$1"

    # Keep every caller (including retry/resume routing) consistent with
    # spawn_agent(): a bounded task needs the subprocess watchdog and PID tree.
    if ! octopus_agent_teams_can_honor_timeout "${TIMEOUT:-0}"; then
        log "DEBUG" "Bounded dispatch (${TIMEOUT}s) requires the supervised provider subprocess"
        return 1
    fi

    # Native dispatch returns before a provider process can report completion.
    # Older Claude Code builds have stable Agent Teams but no
    # last_assistant_message hook, so those tasks would remain "running"
    # forever. Route them through the supervised subprocess instead.
    if [[ "${SUPPORTS_HOOK_LAST_MESSAGE:-false}" != "true" ]]; then
        log "DEBUG" "Native Agent Teams requires SubagentStop result capture; using supervised dispatch for $agent_type"
        return 1
    fi

    # P0-B fix: When orchestrate.sh runs as a Bash tool subprocess (not inside
    # Claude Code's native context), Agent Teams JSON instruction files are never
    # picked up and SubagentStop hooks never fire.  Probe phase sets this flag
    # before spawning agents in parallel background subshells.
    if [[ "${OCTOPUS_FORCE_LEGACY_DISPATCH:-}" == "true" ]]; then
        log "DEBUG" "Force legacy dispatch active — skipping Agent Teams for $agent_type"
        return 1
    fi

    # User override: force legacy mode
    if [[ "$OCTOPUS_AGENT_TEAMS" == "legacy" ]]; then
        return 1
    fi

    # User override: force native for Claude agents
    if [[ "$OCTOPUS_AGENT_TEAMS" == "native" ]]; then
        if is_claude_agent_type "$agent_type"; then
            if [[ "$SUPPORTS_STABLE_AGENT_TEAMS" == "true" ]]; then
                return 0
            else
                log "WARN" "Agent Teams forced but SUPPORTS_STABLE_AGENT_TEAMS not available"
                return 1
            fi
        fi

        # Non-Claude agents always use legacy (external CLIs)
        return 1
    fi

    # Auto mode: use teams for Claude agents when stable teams are available
    if [[ "$SUPPORTS_STABLE_AGENT_TEAMS" == "true" ]] && is_claude_agent_type "$agent_type"; then
        return 0
    fi

    return 1
}

_octopus_repository_env_names() {
    printf '%s\n' \
        GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
        GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE \
        GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM \
        GIT_IMPLICIT_WORK_TREE GIT_PREFIX GIT_SUPER_PREFIX GIT_INTERNAL_SUPER_PREFIX \
        GIT_GRAFT_FILE GIT_SHALLOW_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS \
        GIT_CONFIG GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM \
        GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_QUARANTINE_PATH GIT_DEFAULT_HASH \
        GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_ICASE_PATHSPECS
}

_octopus_clear_repository_env() {
    local git_env_name clear_failed=false

    while IFS= read -r git_env_name; do
        unset "$git_env_name" 2>/dev/null || clear_failed=true
    done < <(_octopus_repository_env_names)

    # Git's command-scope config protocol uses numbered variable names. Clear
    # every inherited pair even when GIT_CONFIG_COUNT itself is malformed or
    # absent. Trace and redirect variables can write to absolute paths, so they
    # must not cross the advisory boundary either.
    while IFS= read -r git_env_name; do
        case "$git_env_name" in
            GIT_CONFIG_KEY_*|GIT_CONFIG_VALUE_*|GIT_TRACE*|GIT_REDIRECT_STDIN|GIT_REDIRECT_STDOUT|GIT_REDIRECT_STDERR)
                unset "$git_env_name" 2>/dev/null || clear_failed=true
                ;;
        esac
    done < <(compgen -v)

    [[ "$clear_failed" == "false" ]]
}

# Repository-selection environment variables override `git -C`. Clear them for
# workspace discovery so an exported GIT_DIR, config, or index path cannot
# redirect reads or writes to another checkout.
_octopus_git_without_repository_env() (
    local git_env_name
    local -a clean_env

    clean_env=()
    while IFS= read -r git_env_name; do
        clean_env+=( -u "$git_env_name" )
    done < <(_octopus_repository_env_names)
    while IFS= read -r git_env_name; do
        case "$git_env_name" in
            GIT_CONFIG_KEY_*|GIT_CONFIG_VALUE_*|GIT_TRACE*|GIT_REDIRECT_STDIN|GIT_REDIRECT_STDOUT|GIT_REDIRECT_STDERR)
                clean_env+=( -u "$git_env_name" )
                ;;
        esac
    done < <(compgen -v)
    command env "${clean_env[@]}" git "$@"
)

_octopus_source_has_git_marker() {
    local current="$1"

    while :; do
        [[ -e "$current/.git" || -L "$current/.git" ]] && return 0
        [[ "$current" == "/" ]] && return 1
        current="${current%/*}"
        [[ -n "$current" ]] || current="/"
    done
}

# Print git-work-tree or non-git. Any other discovery result is an error.
_octopus_classify_git_source() {
    local source_root="$1"
    local discovery_result discovery_rc

    if discovery_result="$(_octopus_git_without_repository_env -C "$source_root" rev-parse --is-inside-work-tree 2>/dev/null)"; then
        [[ "$discovery_result" == "true" ]] || return 1
        printf 'git-work-tree\n'
        return 0
    else
        discovery_rc=$?
    fi

    # Git uses 128 when no repository exists. A marker in the ancestry means
    # that the same status came from a broken or unreadable repository instead.
    [[ "$discovery_rc" -eq 128 ]] || return 1
    _octopus_source_has_git_marker "$source_root" && return 1
    printf 'non-git\n'
}

_octopus_source_path_has_safe_ancestry() {
    local source_root="$1"
    local rel="$2"
    local identity_result_var="${3:-}"
    local current="$source_root"
    local remaining="$rel"
    local component component_identity captured_identities=""

    if [[ -n "$identity_result_var" ]]; then
        [[ "$identity_result_var" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1
    fi

    case "$rel" in
        ""|/*) return 1 ;;
    esac

    while [[ "$remaining" == */* ]]; do
        component="${remaining%%/*}"
        case "$component" in
            ""|.|..) return 1 ;;
        esac
        current="${current}/${component}"
        [[ -d "$current" && ! -L "$current" ]] || return 1
        if [[ -n "$identity_result_var" ]]; then
            component_identity="$(_octopus_directory_identity "$current")" || return 1
            captured_identities="${captured_identities}${captured_identities:+ }${component_identity}"
        fi
        remaining="${remaining#*/}"
    done

    case "$remaining" in
        ""|.|..) return 1 ;;
    esac
    if [[ -n "$identity_result_var" ]]; then
        printf -v "$identity_result_var" '%s' "$captured_identities"
    fi
}

_octopus_relative_symlink_target_is_confined() {
    local rel="$1"
    local link_target="$2"
    local base combined remaining component
    local depth=0

    case "$link_target" in
        ""|/*) return 1 ;;
    esac

    base="${rel%/*}"
    [[ "$base" == "$rel" ]] && base=""
    combined="${base:+$base/}${link_target}"
    remaining="$combined"

    while :; do
        component="${remaining%%/*}"
        case "$component" in
            ""|.) ;;
            ..)
                [[ "$depth" -gt 0 ]] || return 1
                depth=$((depth - 1))
                ;;
            *) depth=$((depth + 1)) ;;
        esac
        [[ "$remaining" == */* ]] || break
        remaining="${remaining#*/}"
    done
}

_octopus_validate_copy_source_path() {
    local source_root="$1"
    local rel="$2"
    local copy_scope="${3:-}"
    local ancestor_identity_result_var="${4:-}"
    local entry_path link_target resolved confinement_rel confinement_root

    _octopus_source_path_has_safe_ancestry "$source_root" "$rel" "$ancestor_identity_result_var" || return 1
    entry_path="${source_root}/${rel}"
    [[ -e "$entry_path" || -L "$entry_path" ]] || return 1

    confinement_rel="$rel"
    confinement_root="$(cd "$source_root" 2>/dev/null && pwd -P)" || return 1
    if [[ -n "$copy_scope" ]]; then
        case "$rel" in
            "$copy_scope"/*) confinement_rel="${rel#"$copy_scope"/}" ;;
            *) return 1 ;;
        esac
        confinement_root="$(cd "${source_root}/${copy_scope}" 2>/dev/null && pwd -P)" || return 1
    fi

    if [[ -L "$entry_path" ]]; then
        link_target="$(readlink "$entry_path" 2>/dev/null)" || return 1
        _octopus_relative_symlink_target_is_confined "$confinement_rel" "$link_target" || return 1
        if resolved="$(realpath "$entry_path" 2>/dev/null)"; then
            case "$resolved" in
                "$confinement_root"|"$confinement_root"/*) ;;
                *) return 1 ;;
            esac
        fi
    elif [[ -f "$entry_path" ]]; then
        [[ -r "$entry_path" ]] || return 1
    elif [[ ! -d "$entry_path" ]]; then
        return 1
    fi
}

# Resolve only an absolute path's parent. Appending the final component gives
# the physical location an entered directory must have without dereferencing
# that final component before it is opened.
_octopus_expected_physical_entry_path() {
    local entry_path="$1"
    local parent leaf physical_parent

    case "$entry_path" in
        /) printf '/\n'; return 0 ;;
        /*) ;;
        *) return 1 ;;
    esac
    parent="${entry_path%/*}"
    leaf="${entry_path##*/}"
    [[ -n "$leaf" ]] || return 1
    [[ -n "$parent" ]] || parent="/"
    physical_parent="$(cd "$parent" 2>/dev/null && pwd -P)" || return 1
    printf '%s/%s\n' "${physical_parent%/}" "$leaf"
}

_octopus_print_valid_directory_identity() {
    local identity="$1"
    local device inode

    device="${identity%%:*}"
    inode="${identity#*:}"
    [[ "$inode" != "$identity" ]] || return 1
    case "$device" in ""|*[!0-9]*) return 1 ;; esac
    case "$inode" in ""|*[!0-9]*) return 1 ;; esac
    printf '%s:%s\n' "$device" "$inode"
}

# Print a directory's device and inode using the native stat dialect on macOS
# or Linux. Pathname checks alone cannot distinguish a real-directory swap at
# the same location.
_octopus_directory_identity() {
    local directory="$1"
    local identity

    [[ -d "$directory" && ! -L "$directory" ]] || return 1
    if identity="$(command stat -f '%d:%i' "$directory" 2>/dev/null)" &&
       _octopus_print_valid_directory_identity "$identity"; then
        return 0
    fi
    identity="$(command stat -c '%d:%i' "$directory" 2>/dev/null)" || return 1
    _octopus_print_valid_directory_identity "$identity"
}

_octopus_directory_identity_matches() {
    local directory="$1"
    local expected_identity="$2"
    local current_identity

    [[ -n "$expected_identity" ]] || return 1
    current_identity="$(_octopus_directory_identity "$directory")" || return 1
    [[ "$current_identity" == "$expected_identity" ]]
}

# Pure shell cannot make a pathname lookup and the following operation atomic.
# Revalidate both the original pathname and each entered directory at every
# deterministic reopen boundary, then use paths relative to the entered cwd.
_octopus_revalidate_directory_anchor() {
    local anchor_path="$1"
    local expected_identity="$2"

    _octopus_directory_identity_matches "$anchor_path" "$expected_identity" || return 1
    _octopus_directory_identity_matches . "$expected_identity"
}

# Copy one leaf without ever reopening a validated ancestor by pathname. Each
# directory component becomes the subshell's working directory and is checked
# physically before the next component is entered. `cp -P` preserves a leaf
# symlink instead of following it; destination validation then rejects any
# target that would escape the copied tree.
_octopus_copy_leaf_safely() (
    local source_root="$1"
    local workspace="$2"
    local rel="$3"
    local copy_scope="${4:-}"
    local remaining component physical_dir destination_parent expected_source_root source_is_anchored=false
    local source_anchor_path source_identity ancestor_identities="" ancestor_identity

    if [[ "$source_root" == "." ]]; then
        source_root="$(pwd -P)" || return 1
        source_is_anchored=true
    fi
    source_anchor_path="$source_root"
    source_identity="$(_octopus_directory_identity "$source_anchor_path")" || return 1

    _octopus_validate_copy_source_path "$source_root" "$rel" "$copy_scope" ancestor_identities || return 1
    destination_parent="${rel%/*}"
    [[ "$destination_parent" == "$rel" ]] && destination_parent=""
    if [[ -n "$destination_parent" ]]; then
        mkdir -p "$workspace/$destination_parent" || return 1
    fi

    if [[ "$source_is_anchored" == "true" ]]; then
        [[ "$(pwd -P)" == "$source_root" ]] || return 1
        _octopus_revalidate_directory_anchor "$source_anchor_path" "$source_identity" || return 1
    else
        expected_source_root="$(_octopus_expected_physical_entry_path "$source_root")" || return 1
        cd "$source_root" 2>/dev/null || return 1
        physical_dir="$(pwd -P)" || return 1
        [[ "$physical_dir" == "$expected_source_root" ]] || return 1
        _octopus_revalidate_directory_anchor "$source_anchor_path" "$source_identity" || return 1
        source_root="$physical_dir"
    fi
    remaining="$rel"
    while [[ "$remaining" == */* ]]; do
        component="${remaining%%/*}"
        case "$component" in
            ""|.|..) return 1 ;;
        esac
        case "$ancestor_identities" in
            *" "*)
                ancestor_identity="${ancestor_identities%% *}"
                ancestor_identities="${ancestor_identities#* }"
                ;;
            *)
                ancestor_identity="$ancestor_identities"
                ancestor_identities=""
                ;;
        esac
        [[ -n "$ancestor_identity" ]] || return 1
        _octopus_directory_identity_matches "./$component" "$ancestor_identity" || return 1
        cd "./$component" 2>/dev/null || return 1
        _octopus_directory_identity_matches . "$ancestor_identity" || return 1
        physical_dir="$(pwd -P)" || return 1
        case "$physical_dir" in
            "$source_root"|"$source_root"/*) ;;
            *) return 1 ;;
        esac
        remaining="${remaining#*/}"
    done
    [[ -z "$ancestor_identities" ]] || return 1
    case "$remaining" in
        ""|.|..) return 1 ;;
    esac
    [[ -f "./$remaining" || -L "./$remaining" ]] || return 1
    command cp -pP "./$remaining" "$workspace/$rel" || return 1
    _octopus_directory_identity_matches "$source_anchor_path" "$source_identity" || return 1
    _octopus_validate_copy_source_path "$workspace" "$rel" "$copy_scope"
)

# Enter a nested repository one real directory component at a time, then keep
# that directory as the recursion anchor. Repository discovery and recursive
# copying use `.` from the anchored working directory; they never reopen the
# pathname that identified the nested repository during parent enumeration.
_octopus_copy_nested_git_tree_safely() (
    local source_root="$1"
    local workspace="$2"
    local nested_rel="$3"
    local temp_exclusion_root="${4:-$source_root}"
    local expected_nested_identity="${5:-}"
    local remaining component physical_dir expected_dir nested_top source_is_anchored=false
    local component_identity nested_identity nested_anchor_path

    case "$nested_rel" in
        ""|/*) return 1 ;;
    esac
    if [[ "$temp_exclusion_root" == "." ]]; then
        temp_exclusion_root="$(pwd -P)" || return 1
    fi

    if [[ "$source_root" == "." ]]; then
        source_root="$(pwd -P)" || return 1
        source_is_anchored=true
    fi
    if [[ "$source_is_anchored" == "true" ]]; then
        physical_dir="$(pwd -P)" || return 1
        [[ "$physical_dir" == "$source_root" ]] || return 1
    else
        expected_dir="$(_octopus_expected_physical_entry_path "$source_root")" || return 1
        cd "$source_root" 2>/dev/null || return 1
        physical_dir="$(pwd -P)" || return 1
        [[ "$physical_dir" == "$expected_dir" ]] || return 1
        source_root="$physical_dir"
    fi

    remaining="$nested_rel"
    expected_dir="$source_root"
    while :; do
        component="${remaining%%/*}"
        case "$component" in
            ""|.|..) return 1 ;;
        esac
        [[ -d "./$component" && ! -L "./$component" ]] || return 1
        component_identity="$(_octopus_directory_identity "./$component")" || return 1
        if [[ "$remaining" != */* && -n "$expected_nested_identity" ]]; then
            [[ "$component_identity" == "$expected_nested_identity" ]] || return 1
        fi
        cd "./$component" 2>/dev/null || return 1
        expected_dir="${expected_dir}/${component}"
        physical_dir="$(pwd -P)" || return 1
        [[ "$physical_dir" == "$expected_dir" ]] || return 1
        _octopus_directory_identity_matches . "$component_identity" || return 1
        [[ "$remaining" == */* ]] || break
        remaining="${remaining#*/}"
    done

    nested_anchor_path="$expected_dir"
    nested_identity="$component_identity"
    _octopus_revalidate_directory_anchor "$nested_anchor_path" "$nested_identity" || return 1
    nested_top="$(_octopus_git_without_repository_env -C . rev-parse --show-toplevel 2>/dev/null)" || return 1
    _octopus_revalidate_directory_anchor "$nested_anchor_path" "$nested_identity" || return 1
    nested_top="$(cd "$nested_top" 2>/dev/null && pwd -P)" || return 1
    [[ "$nested_top" == "$physical_dir" ]] || return 1
    mkdir -p "$workspace/$nested_rel" || return 1
    _octopus_copy_git_tracked_tree . "$workspace/$nested_rel" "" "$temp_exclusion_root" "$nested_anchor_path" "$nested_identity"
)

_octopus_validate_materialized_symlinks() (
    local copied_root="$1"
    local copied_path rel

    copied_root="$(cd "$copied_root" 2>/dev/null && pwd -P)" || return 1
    set -o pipefail
    find "$copied_root" -type l -print0 | while IFS= read -r -d '' copied_path; do
        case "$copied_path" in
            "$copied_root"/*) rel="${copied_path#"$copied_root"/}" ;;
            *) return 1 ;;
        esac
        _octopus_validate_copy_source_path "$copied_root" "$rel" || return 1
    done
)

_octopus_replace_literal() {
    local value="$1"
    local needle="$2"
    local replacement="$3"
    local result=""
    local prefix

    [[ -n "$needle" ]] || { printf '%s' "$value"; return 0; }
    while [[ "$value" == *"$needle"* ]]; do
        prefix="${value%%"$needle"*}"
        result="${result}${prefix}${replacement}"
        value="${value#*"$needle"}"
    done
    printf '%s' "${result}${value}"
}

# Print a writable temporary-file parent that is not inside the source scope.
# Physicalize every candidate before comparison so a symlinked TMPDIR cannot
# place control files or the destination back under the tree being copied.
_octopus_temp_parent_outside_source() {
    local source_scope="$1"
    local candidate physical_candidate

    for candidate in "${TMPDIR:-/tmp}" /tmp /var/tmp; do
        [[ -d "$candidate" && -w "$candidate" ]] || continue
        physical_candidate="$(cd "$candidate" 2>/dev/null && pwd -P)" || continue
        case "$physical_candidate" in
            "$source_scope"|"$source_scope"/*) continue ;;
        esac
        printf '%s\n' "$physical_candidate"
        return 0
    done
    return 1
}

# Resolve the full physical Git root for control-file placement. A launch from
# a repository subdirectory must not treat a repository-local TMPDIR as safe.
_octopus_temp_exclusion_root_for_source() {
    local source_root="$1"
    local source_kind git_root

    source_root="$(cd "$source_root" 2>/dev/null && pwd -P)" || return 1
    source_kind="$(_octopus_classify_git_source "$source_root")" || return 1
    if [[ "$source_kind" == "git-work-tree" ]]; then
        git_root="$(_octopus_git_without_repository_env -C "$source_root" rev-parse --show-toplevel 2>/dev/null)" || return 1
        git_root="$(cd "$git_root" 2>/dev/null && pwd -P)" || return 1
        case "$source_root" in
            "$git_root"|"$git_root"/*) ;;
            *) return 1 ;;
        esac
        printf '%s\n' "$git_root"
    else
        printf '%s\n' "$source_root"
    fi
}

_octopus_temp_name_matches() {
    local temp_name="$1"
    local stem="$2"
    local remainder owner_pid owner_nonce suffix

    case "$temp_name" in
        "$stem".??????) return 0 ;;
    esac

    remainder="${temp_name#"$stem".}"
    [[ "$remainder" != "$temp_name" && "$remainder" == *.*.* ]] || return 1
    owner_pid="${remainder%%.*}"
    remainder="${remainder#*.}"
    owner_nonce="${remainder%%.*}"
    suffix="${remainder#*.}"
    [[ "$suffix" != "$remainder" && "$suffix" != *.* ]] || return 1
    case "$owner_pid" in
        ""|*[!0-9]*) return 1 ;;
    esac
    case "$owner_nonce" in
        ""|*[!0-9]*) return 1 ;;
    esac
    case "$suffix" in
        ??????) return 0 ;;
    esac
    return 1
}

# Build a process-owned prefix before mktemp can create anything. Signal
# cleanup can then identify this invocation's directory even while the mktemp
# command substitution has not yet assigned its output.
_octopus_prepare_owned_temp_prefix() {
    local result_var="$1"
    local temp_parent="$2"
    local stem="$3"
    local owner_pid owner_nonce prefix

    [[ "$result_var" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1
    case "$stem" in
        octopus-consultative|octopus-copy-lists) ;;
        *) return 1 ;;
    esac
    [[ "$temp_parent" == /* && -d "$temp_parent" && ! -L "$temp_parent" ]] || return 1
    [[ "$(cd "$temp_parent" 2>/dev/null && pwd -P)" == "$temp_parent" ]] || return 1
    owner_pid="$(/bin/sh -c 'printf "%s\n" "$PPID"')" || return 1
    case "$owner_pid" in
        ""|*[!0-9]*) return 1 ;;
    esac
    owner_nonce="${RANDOM}${RANDOM}"
    prefix="${temp_parent}/${stem}.${owner_pid}.${owner_nonce}"
    printf -v "$result_var" '%s' "$prefix"
}

_octopus_owned_temp_dir_is_safe() {
    local allocation_prefix="$1"
    local candidate="$2"
    local physical_candidate

    [[ -n "$allocation_prefix" && "$allocation_prefix" == /* ]] || return 1
    case "$candidate" in
        "$allocation_prefix".??????) ;;
        *) return 1 ;;
    esac
    [[ -d "$candidate" && ! -L "$candidate" ]] || return 1
    physical_candidate="$(cd "$candidate" 2>/dev/null && pwd -P)" || return 1
    [[ "$physical_candidate" == "$candidate" ]]
}

_octopus_remove_owned_temp_dirs() {
    local allocation_prefix="$1"
    local candidate cleanup_failed=false

    [[ -n "$allocation_prefix" ]] || return 0
    [[ "$allocation_prefix" == /* ]] || return 1
    for candidate in "$allocation_prefix".??????; do
        [[ -e "$candidate" || -L "$candidate" ]] || continue
        if ! _octopus_owned_temp_dir_is_safe "$allocation_prefix" "$candidate"; then
            cleanup_failed=true
            continue
        fi
        command rm -rf "$candidate" || cleanup_failed=true
    done
    [[ "$cleanup_failed" == "false" ]]
}

# Ignore only untracked remnants created by Octopus itself. Tracked paths with
# the same shape remain eligible so repository contents and selected-subtree
# semantics are not weakened.
_octopus_path_is_generated_temp_artifact() {
    local remaining="$1"
    local component

    while :; do
        component="${remaining%%/*}"
        _octopus_temp_name_matches "$component" "octopus-consultative" && return 0
        _octopus_temp_name_matches "$component" "octopus-copy-lists" && return 0
        [[ "$remaining" == */* ]] || break
        remaining="${remaining#*/}"
    done
    return 1
}

# Copy only tracked plus untracked-but-not-ignored files from a Git work tree.
# An optional root-relative scope limits enumeration while paths remain rooted at
# the repository for validation and destination placement.
# Nested repositories are detected during parent enumeration and copied from an
# anchored working directory under their own ignore rules. Every path ancestor
# must be a real directory. Symlink leaves must stay lexically within the copied
# tree, and resolved targets must remain in the source. Any failure is fatal for
# a Git source.
_octopus_copy_git_tracked_tree() (
    local source_root="$1"
    local workspace="$2"
    local copy_scope="${3:-}"
    local temp_exclusion_root="${4:-$source_root}"
    local source_anchor_path="${5:-}"
    local source_identity="${6:-}"
    local list_dir filelist untrackedlist copylist entry rel entry_path
    local nested_stage nested_entry_identity scope_pathspec temp_parent list_dir_prefix expected_source_root

    _octopus_cleanup_copy_list_dir() {
        local cleanup_rc="$1"
        trap - EXIT INT TERM
        if ! _octopus_remove_owned_temp_dirs "$list_dir_prefix"; then
            [[ "$cleanup_rc" -ne 0 ]] || cleanup_rc=1
        fi
        exit "$cleanup_rc"
    }

    case "$source_root" in
        .)
            expected_source_root="$(pwd -P)" || return 1
            [[ -n "$source_anchor_path" ]] || source_anchor_path="$expected_source_root"
            ;;
        /*)
            expected_source_root="$(_octopus_expected_physical_entry_path "$source_root")" || return 1
            [[ -n "$source_anchor_path" ]] || source_anchor_path="$source_root"
            ;;
        *) return 1 ;;
    esac
    [[ -n "$source_identity" ]] || source_identity="$(_octopus_directory_identity "$source_anchor_path")" || return 1
    cd "$source_root" 2>/dev/null || return 1
    source_root="$(pwd -P)" || return 1
    [[ "$source_root" == "$expected_source_root" ]] || return 1
    _octopus_revalidate_directory_anchor "$source_anchor_path" "$source_identity" || return 1
    _octopus_git_without_repository_env -C . rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
    _octopus_revalidate_directory_anchor "$source_anchor_path" "$source_identity" || return 1
    workspace="$(cd "$workspace" 2>/dev/null && pwd -P)" || return 1
    temp_exclusion_root="$(cd "$temp_exclusion_root" 2>/dev/null && pwd -P)" || return 1
    case "$source_root" in
        "$temp_exclusion_root"|"$temp_exclusion_root"/*) ;;
        *) return 1 ;;
    esac
    if [[ -n "$copy_scope" ]]; then
        _octopus_source_path_has_safe_ancestry . "$copy_scope" || return 1
        [[ -d "./$copy_scope" && ! -L "./$copy_scope" ]] || return 1
        scope_pathspec=":(literal,top)${copy_scope}"
    fi

    temp_parent="$(_octopus_temp_parent_outside_source "$temp_exclusion_root")" || return 1
    list_dir=""
    list_dir_prefix=""
    # The handler owns the unique prefix before mktemp can create its directory.
    trap '_octopus_cleanup_copy_list_dir "$?"' EXIT
    trap '_octopus_cleanup_copy_list_dir 130' INT
    trap '_octopus_cleanup_copy_list_dir 143' TERM
    _octopus_prepare_owned_temp_prefix list_dir_prefix "$temp_parent" "octopus-copy-lists" || return 1
    list_dir="$(mktemp -d "${list_dir_prefix}.XXXXXX")" || return 1
    _octopus_owned_temp_dir_is_safe "$list_dir_prefix" "$list_dir" || return 1
    filelist="${list_dir}/tracked"
    untrackedlist="${list_dir}/untracked"
    copylist="${list_dir}/copy"
    : > "$filelist" && : > "$untrackedlist" && : > "$copylist" || return 1
    _octopus_revalidate_directory_anchor "$source_anchor_path" "$source_identity" || return 1
    if [[ -n "$copy_scope" ]]; then
        _octopus_git_without_repository_env -C . ls-files -z --cached -- "$scope_pathspec" >"$filelist" 2>/dev/null || {
            return 1
        }
        _octopus_revalidate_directory_anchor "$source_anchor_path" "$source_identity" || return 1
        _octopus_git_without_repository_env -C . \
            ls-files -z --others --exclude-standard -- "$scope_pathspec" \
            >"$untrackedlist" 2>/dev/null || return 1
    else
        _octopus_git_without_repository_env -C . ls-files -z --cached >"$filelist" 2>/dev/null || {
            return 1
        }
        _octopus_revalidate_directory_anchor "$source_anchor_path" "$source_identity" || return 1
        _octopus_git_without_repository_env -C . \
            ls-files -z --others --exclude-standard \
            >"$untrackedlist" 2>/dev/null || return 1
    fi
    _octopus_revalidate_directory_anchor "$source_anchor_path" "$source_identity" || return 1
    while IFS= read -r -d '' entry; do
        _octopus_path_is_generated_temp_artifact "${entry%/}" && continue
        printf '%s\0' "$entry" >> "$filelist" || return 1
    done < "$untrackedlist"

    while IFS= read -r -d '' entry; do
        _octopus_revalidate_directory_anchor "$source_anchor_path" "$source_identity" || return 1
        rel="${entry%/}"
        [[ -n "$rel" ]] || continue
        if [[ -n "$copy_scope" ]]; then
            case "$rel" in
                "$copy_scope"|"$copy_scope"/*) ;;
                *) return 1 ;;
            esac
        fi
        entry_path="./${rel}"

        # Deleted tracked paths remain in the index but have no bytes to copy.
        [[ -e "$entry_path" || -L "$entry_path" ]] || continue
        _octopus_validate_copy_source_path . "$rel" "$copy_scope" || {
            return 1
        }

        if [[ -d "$entry_path" && ! -L "$entry_path" ]]; then
            nested_entry_identity="$(_octopus_directory_identity "$entry_path")" || return 1
            # Nested repositories appear as directory entries. An exact .git
            # marker catches embedded and untracked repositories; index mode
            # 160000 still identifies a registered gitlink if its marker broke.
            nested_stage=""
            if [[ ! -e "$entry_path/.git" && ! -L "$entry_path/.git" ]]; then
                _octopus_revalidate_directory_anchor "$source_anchor_path" "$source_identity" || return 1
                nested_stage="$(_octopus_git_without_repository_env -C . ls-files --stage -- ":(literal,top)${rel}" 2>/dev/null)" || {
                    return 1
                }
                _octopus_revalidate_directory_anchor "$source_anchor_path" "$source_identity" || return 1
            fi
            if [[ -e "$entry_path/.git" || -L "$entry_path/.git" || "$nested_stage" == 160000\ * ]]; then
                _octopus_revalidate_directory_anchor "$source_anchor_path" "$source_identity" || return 1
                _octopus_copy_nested_git_tree_safely . "$workspace" "$rel" "$temp_exclusion_root" "$nested_entry_identity" || return 1
                _octopus_revalidate_directory_anchor "$source_anchor_path" "$source_identity" || return 1
                continue
            fi
        fi

        printf '%s\0' "$rel" >> "$copylist" || return 1
    done < "$filelist"

    while IFS= read -r -d '' rel; do
        _octopus_revalidate_directory_anchor "$source_anchor_path" "$source_identity" || return 1
        _octopus_copy_leaf_safely . "$workspace" "$rel" "$copy_scope" || return 1
        _octopus_revalidate_directory_anchor "$source_anchor_path" "$source_identity" || return 1
    done < "$copylist"
    _octopus_revalidate_directory_anchor "$source_anchor_path" "$source_identity"

)

# Prepare an isolated copy-on-write workspace for advisory agents.
# Git sources fail closed if their selective copy fails. Non-Git directories
# retain the original private whole-tree copy because they have no ignore index.
_octopus_prepare_consultative_workspace() {
    local source_root="$1"
    local workspace_result_var="${2:-}"
    local temp_root_result_var="${3:-}"
    local prepared_temp_root prepared_temp_root_raw prepared_workspace git_root source_prefix git_source_kind temp_parent temp_root_prefix temp_exclusion_root
    local source_identity git_root_identity

    if [[ -n "$workspace_result_var" || -n "$temp_root_result_var" ]]; then
        [[ "$workspace_result_var" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1
        [[ "$temp_root_result_var" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1
    fi

    source_root="$(cd "$source_root" 2>/dev/null && pwd -P)" || return 1
    source_identity="$(_octopus_directory_identity "$source_root")" || return 1
    git_source_kind="$(_octopus_classify_git_source "$source_root")" || return 1
    _octopus_directory_identity_matches "$source_root" "$source_identity" || return 1

    temp_exclusion_root="$source_root"
    if [[ "$git_source_kind" == "git-work-tree" ]]; then
        git_root="$(_octopus_git_without_repository_env -C "$source_root" rev-parse --show-toplevel 2>/dev/null)" || return 1
        git_root="$(cd "$git_root" 2>/dev/null && pwd -P)" || return 1
        git_root_identity="$(_octopus_directory_identity "$git_root")" || return 1
        _octopus_directory_identity_matches "$source_root" "$source_identity" || return 1
        case "$source_root" in
            "$git_root"|"$git_root"/*) ;;
            *) return 1 ;;
        esac
        temp_exclusion_root="$git_root"
    fi

    temp_parent="$(_octopus_temp_parent_outside_source "$temp_exclusion_root")" || return 1
    temp_root_prefix=""
    _octopus_prepare_owned_temp_prefix temp_root_prefix "$temp_parent" "octopus-consultative" || return 1
    if [[ -n "${4:-}" ]]; then
        [[ "$4" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1
        # Publish ownership before mktemp so the caller's signal trap can clean
        # a directory whose command substitution has not returned yet.
        printf -v "$4" '%s' "$temp_root_prefix"
    fi
    prepared_temp_root_raw="$(mktemp -d "${temp_root_prefix}.XXXXXX")" || {
        _octopus_remove_owned_temp_dirs "$temp_root_prefix" >/dev/null 2>&1 || true
        return 1
    }
    _octopus_owned_temp_dir_is_safe "$temp_root_prefix" "$prepared_temp_root_raw" || {
        _octopus_remove_owned_temp_dirs "$temp_root_prefix" >/dev/null 2>&1 || true
        return 1
    }
    prepared_temp_root="$prepared_temp_root_raw"
    prepared_workspace="${prepared_temp_root}/workspace"
    if [[ -n "$workspace_result_var" && -n "$temp_root_result_var" ]]; then
        printf -v "$workspace_result_var" '%s' "$prepared_workspace"
        printf -v "$temp_root_result_var" '%s' "$prepared_temp_root"
    fi
    prepared_temp_root="$(cd "$prepared_temp_root_raw" 2>/dev/null && pwd -P)" || {
        rm -rf "$prepared_temp_root_raw"
        return 1
    }
    prepared_workspace="${prepared_temp_root}/workspace"
    mkdir -p "$prepared_workspace" || { rm -rf "$prepared_temp_root"; return 1; }

    if [[ "$git_source_kind" == "git-work-tree" ]]; then
        case "$source_root" in
            "$git_root") source_prefix="" ;;
            "$git_root"/*) source_prefix="${source_root#"$git_root"/}" ;;
            *)
                rm -rf "$prepared_temp_root"
                return 1
                ;;
        esac

        _octopus_copy_git_tracked_tree "$git_root" "$prepared_workspace" "$source_prefix" "$git_root" "$git_root" "$git_root_identity" || {
            rm -rf "$prepared_temp_root"
            return 1
        }
        if [[ -n "$source_prefix" ]]; then
            mkdir -p "${prepared_workspace}/${source_prefix}" || {
                rm -rf "$prepared_temp_root"
                return 1
            }
            prepared_workspace="${prepared_workspace}/${source_prefix}"
        fi
    elif [[ "$git_source_kind" == "non-git" ]]; then
        if ! cp -a --reflink=auto "${source_root}/." "${prepared_workspace}/" 2>/dev/null; then
            rm -rf "$prepared_workspace"
            mkdir -p "$prepared_workspace" || { rm -rf "$prepared_temp_root"; return 1; }
            cp -a "${source_root}/." "${prepared_workspace}/" || { rm -rf "$prepared_temp_root"; return 1; }
        fi
        _octopus_validate_materialized_symlinks "$prepared_workspace" || {
            rm -rf "$prepared_temp_root"
            return 1
        }
    else
        rm -rf "$prepared_temp_root"
        return 1
    fi

    if [[ -n "$workspace_result_var" && -n "$temp_root_result_var" ]]; then
        printf -v "$workspace_result_var" '%s' "$prepared_workspace"
        printf -v "$temp_root_result_var" '%s' "$prepared_temp_root"
    else
        printf '%s\n' "$prepared_workspace"
    fi
}

_octopus_consultative_temp_root_is_safe() {
    local temp_root="$1"
    local workspace="$2"
    local physical_temp_root temp_name

    [[ "$temp_root" == /* && -d "$temp_root" && ! -L "$temp_root" ]] || return 1
    physical_temp_root="$(cd "$temp_root" 2>/dev/null && pwd -P)" || return 1
    [[ "$physical_temp_root" == "$temp_root" ]] || return 1
    temp_name="$(basename "$temp_root")"
    _octopus_temp_name_matches "$temp_name" "octopus-consultative" || return 1
    case "$workspace" in
        "$temp_root/workspace"|"$temp_root/workspace"/*) ;;
        *) return 1 ;;
    esac
}

_octopus_remove_consultative_temp_root() {
    local temp_root="$1"
    local workspace="$2"

    if [[ ! -e "$temp_root" && ! -L "$temp_root" ]]; then
        return 0
    fi
    _octopus_consultative_temp_root_is_safe "$temp_root" "$workspace" || return 1
    rm -rf "$temp_root"
}

# Ask Bash's job table whether a PID still names an unreaped child owned by
# this shell. Numeric PID probes can match an unrelated process after reuse.
_octopus_shell_owns_job() {
    local target_pid="$1"
    local job_pid job_state

    case "$target_pid" in ""|*[!0-9]*) return 1 ;; esac
    for job_state in -pr -ps; do
        while IFS= read -r job_pid; do
            [[ "$job_pid" == "$target_pid" ]] && return 0
        done < <(jobs "$job_state")
    done
    return 1
}

# Run a synchronous agent in a strictly consultative context.
#
# Council seats and pre-implementation design reviews are advisory. Native
# read-only sandboxing is not portable across all Codex runtimes (notably
# Landlock-restricted hosts), so advisory agents run with the functional
# danger-full-access mode inside a private disposable workspace. Relative-path
# writes made during normal advisory work are discarded with that workspace.
# This is mutation isolation for accidental workspace edits, not a security
# boundary against deliberate access to absolute paths outside the workspace.
_octopus_run_agent_sync_consultative_impl() (
    local old_security_set="${OCTOPUS_SECURITY_V870+x}"
    local old_security="${OCTOPUS_SECURITY_V870:-}"
    local old_agy_sandbox_set="${OCTOPUS_AGY_SANDBOX+x}"
    local old_agy_sandbox="${OCTOPUS_AGY_SANDBOX:-}"
    local old_codex_sandbox_set="${OCTOPUS_CODEX_SANDBOX+x}"
    local old_codex_sandbox="${OCTOPUS_CODEX_SANDBOX:-}"
    local old_autonomy_set="${CLAUDE_OCTOPUS_AUTONOMY+x}"
    local old_autonomy="${CLAUDE_OCTOPUS_AUTONOMY:-}"
    local source_root source_root_logical workspace temp_root temp_root_prefix rc original_prompt isolated_prompt agent_output cleanup_note
    local agent_pid agent_output_file agent_job_owned=false
    local -a consultative_args

    _octopus_handle_consultative_signal() {
        local signal_rc="$1"
        local cleanup_failed=false

        # Do not let a second foreground signal interrupt validated cleanup.
        trap '' INT TERM
        if [[ "$agent_job_owned" == "true" ]] && _octopus_shell_owns_job "$agent_pid"; then
            agent_job_owned=false
            kill -TERM -- "-$agent_pid" 2>/dev/null || true
            kill -TERM "$agent_pid" 2>/dev/null || true
            /bin/sleep 1
            kill -KILL -- "-$agent_pid" 2>/dev/null || true
            kill -KILL "$agent_pid" 2>/dev/null || true
            wait "$agent_pid" 2>/dev/null || true
            agent_pid=""
        fi
        if [[ -n "$temp_root" ]]; then
            _octopus_remove_consultative_temp_root "$temp_root" "$workspace" 2>/dev/null || cleanup_failed=true
        else
            _octopus_remove_owned_temp_dirs "$temp_root_prefix" 2>/dev/null || cleanup_failed=true
        fi
        if [[ "$cleanup_failed" == "true" ]]; then
            if declare -F log >/dev/null 2>&1; then
                log WARN "Failed to remove consultative workspace after signal: $temp_root"
            else
                printf 'WARN: failed to remove consultative workspace after signal: %s\n' "$temp_root" >&2
            fi
        fi
        if [[ -n "${_octopus_consultative_completion_file:-}" ]]; then
            printf 'done\n' > "$_octopus_consultative_completion_file" 2>/dev/null || true
        fi
        exit "$signal_rc"
    }

    source_root_logical="$PWD"
    source_root="$(pwd -P)"
    workspace=""
    temp_root=""
    temp_root_prefix=""
    agent_pid=""
    agent_output_file=""
    trap '_octopus_handle_consultative_signal 130' INT
    trap '_octopus_handle_consultative_signal 143' TERM
    _octopus_prepare_consultative_workspace "$source_root" workspace temp_root temp_root_prefix || {
        _octopus_remove_consultative_temp_root "$temp_root" "$workspace" 2>/dev/null || true
        log ERROR "Failed to prepare disposable consultative workspace from: $source_root"
        return 1
    }
    _octopus_consultative_temp_root_is_safe "$temp_root" "$workspace" || {
        log ERROR "Refusing unsafe consultative workspace paths"
        return 1
    }

    consultative_args=("$@")
    original_prompt="${consultative_args[1]:-}"
    isolated_prompt="$(_octopus_replace_literal "$original_prompt" "$source_root" "$workspace")"
    if [[ "$source_root_logical" != "$source_root" ]]; then
        isolated_prompt="$(_octopus_replace_literal "$isolated_prompt" "$source_root_logical" "$workspace")"
    fi
    isolated_prompt="${isolated_prompt}

## Consultative Workspace Boundary
Work only inside this disposable workspace: ${workspace}
Treat ${workspace} as the working copy for this advisory task. Any relative-path workspace changes are exploratory and will be discarded. Return analysis and recommendations only.
This copy intentionally contains no Git control-plane metadata. Inspect the copied working-tree files directly."
    consultative_args[1]="$isolated_prompt"

    unset OCTOPUS_SECURITY_V870
    unset OCTOPUS_AGY_SANDBOX
    unset CLAUDE_OCTOPUS_AUTONOMY
    export OCTOPUS_CODEX_SANDBOX="danger-full-access"

    agent_output_file="$temp_root/agent-output"
    set -m
    (
        _octopus_clear_repository_env || exit 125
        export GIT_CEILING_DIRECTORIES="$temp_root"
        cd "$workspace" && run_agent_sync "${consultative_args[@]}"
    ) >"$agent_output_file" &
    agent_pid=$!
    agent_job_owned=true
    set +m
    if wait "$agent_pid"; then
        rc=0
    else
        rc=$?
    fi
    trap '' INT TERM
    agent_job_owned=false
    agent_pid=""
    agent_output="$(cat "$agent_output_file" 2>/dev/null || true)"
    rm -f "$agent_output_file" 2>/dev/null || true

    cleanup_note="Octopus deleted the workspace before returning."
    if ! _octopus_remove_consultative_temp_root "$temp_root" "$workspace" 2>/dev/null; then
        cleanup_note="Octopus attempted cleanup before returning but could not confirm deletion."
        [[ "$rc" -ne 0 ]] || rc=1
        if declare -F log >/dev/null 2>&1; then
            log WARN "Failed to remove consultative workspace: $temp_root"
        else
            printf 'WARN: failed to remove consultative workspace: %s\n' "$temp_root" >&2
        fi
    fi

    if [[ -n "$old_security_set" ]]; then export OCTOPUS_SECURITY_V870="$old_security"; else unset OCTOPUS_SECURITY_V870; fi
    if [[ -n "$old_agy_sandbox_set" ]]; then export OCTOPUS_AGY_SANDBOX="$old_agy_sandbox"; else unset OCTOPUS_AGY_SANDBOX; fi
    if [[ -n "$old_autonomy_set" ]]; then export CLAUDE_OCTOPUS_AUTONOMY="$old_autonomy"; else unset CLAUDE_OCTOPUS_AUTONOMY; fi
    if [[ -n "$old_codex_sandbox_set" ]]; then
        export OCTOPUS_CODEX_SANDBOX="$old_codex_sandbox"
    else
        unset OCTOPUS_CODEX_SANDBOX
    fi

    if [[ -n "$agent_output" ]]; then
        cat <<EOF
## UNVERIFIED CONSULTATIVE OUTPUT

This output came from a disposable workspace. ${cleanup_note} It is advisory and non-deliverable. Claimed file changes, test counts, live probes, or completed implementation are not verified evidence and must not be reported as delivered work.

${agent_output}

## END UNVERIFIED CONSULTATIVE OUTPUT
EOF
    fi

    if [[ -n "${_octopus_consultative_completion_file:-}" ]]; then
        printf 'done\n' > "$_octopus_consultative_completion_file" 2>/dev/null || true
    fi

    return "$rc"
)

# Keep the signal trap in the caller's shell while the isolated implementation
# runs as a background job. Bash defers traps while waiting for a foreground
# subshell or command substitution, but `wait` on a background job is
# interruptible. Monitor mode gives the implementation a private process group
# so cancellation reaches its cleanup handler and all wrapper descendants.
run_agent_sync_consultative() {
    local implementation_pid="" implementation_wait_pid="" rc=0 interrupted_rc=""
    local implementation_job_owned=false
    local monitor_was_enabled=false old_int_trap old_term_trap
    local cleanup_waits completion_parent completion_state completion_owner completion_exclusion_root
    local _octopus_consultative_completion_file=""

    completion_exclusion_root="$(_octopus_temp_exclusion_root_for_source "$(pwd -P)")" || return 1
    completion_parent="$(_octopus_temp_parent_outside_source "$completion_exclusion_root")" || return 1
    completion_owner="$(/bin/sh -c 'printf "%s\n" "$PPID"')" || return 1
    case "$completion_owner" in
        ""|*[!0-9]*) return 1 ;;
    esac
    _octopus_consultative_completion_file="$completion_parent/.octopus-consultative-completion.${completion_owner}.${RANDOM}${RANDOM}"
    (umask 077; set -o noclobber; printf 'running\n' > "$_octopus_consultative_completion_file") 2>/dev/null || {
        rm -f "$_octopus_consultative_completion_file" 2>/dev/null || true
        return 1
    }
    old_int_trap="$(trap -p INT)"
    old_term_trap="$(trap -p TERM)"
    trap 'interrupted_rc=130; trap "" INT TERM; if [[ "$implementation_job_owned" == "true" ]] && _octopus_shell_owns_job "$implementation_pid"; then kill -INT -- "-$implementation_pid" 2>/dev/null || kill -INT "$implementation_pid" 2>/dev/null || true; fi' INT
    trap 'interrupted_rc=143; trap "" INT TERM; if [[ "$implementation_job_owned" == "true" ]] && _octopus_shell_owns_job "$implementation_pid"; then kill -TERM -- "-$implementation_pid" 2>/dev/null || kill -TERM "$implementation_pid" 2>/dev/null || true; fi' TERM
    [[ "$-" == *m* ]] && monitor_was_enabled=true
    set -m
    _octopus_run_agent_sync_consultative_impl "$@" &
    implementation_pid=$!
    implementation_job_owned=true
    set +m
    if [[ "$interrupted_rc" == "130" ]]; then
        if _octopus_shell_owns_job "$implementation_pid"; then
            kill -INT -- "-$implementation_pid" 2>/dev/null || kill -INT "$implementation_pid" 2>/dev/null || true
        fi
    elif [[ "$interrupted_rc" == "143" ]]; then
        if _octopus_shell_owns_job "$implementation_pid"; then
            kill -TERM -- "-$implementation_pid" 2>/dev/null || kill -TERM "$implementation_pid" 2>/dev/null || true
        fi
    fi
    if wait "$implementation_pid"; then
        rc=0
    else
        rc=$?
    fi
    implementation_wait_pid="$implementation_pid"
    trap '' INT TERM
    implementation_job_owned=false
    implementation_pid=""
    if [[ -n "$interrupted_rc" ]]; then
        # The first wait returns as soon as the trap runs. Reap the isolated
        # implementation so its signal handler finishes provider and workspace
        # cleanup before cancellation is reported to the caller.
        cleanup_waits=0
        while [[ "$cleanup_waits" -lt 60 ]]; do
            completion_state="$(cat "$_octopus_consultative_completion_file" 2>/dev/null || true)"
            [[ "$completion_state" == "done" ]] && break
            /bin/sleep 0.05
            cleanup_waits=$((cleanup_waits + 1))
        done
        # Do not signal the numeric PID again after the initial wait. If the
        # implementation exited without writing its completion marker, that
        # PID could already have been reused by an unrelated process.
        wait "$implementation_wait_pid" 2>/dev/null || true
    fi

    if [[ -n "$old_int_trap" ]]; then eval "$old_int_trap"; else trap - INT; fi
    if [[ -n "$old_term_trap" ]]; then eval "$old_term_trap"; else trap - TERM; fi
    [[ "$monitor_was_enabled" == "true" ]] && set -m
    rm -f "$_octopus_consultative_completion_file" 2>/dev/null || true
    [[ -n "$interrupted_rc" ]] && return "$interrupted_rc"
    return "$rc"
}

# Synchronous agent execution (for sequential steps within phases)
run_agent_sync() {
    local agent_type="$1"
    local prompt="$2"
    local timeout_secs="${3:-120}"
    local role="${4:-}"   # Optional role override
    local phase="${5:-}"  # Optional phase context

    # OCTOPUS_AGENT_TIMEOUT env var overrides all caller-hardcoded values.
    # Without this, callers passing explicit values (e.g. 300, 600) bypass the
    # dynamic path and the env var has no effect — making it dead code (#410).
    if [[ -n "${OCTOPUS_AGENT_TIMEOUT:-}" && "${OCTOPUS_AGENT_TIMEOUT}" =~ ^[0-9]+$ ]]; then
        timeout_secs="$OCTOPUS_AGENT_TIMEOUT"
    elif [[ "$timeout_secs" -eq 120 ]]; then
        # v8.19.0: Dynamic timeout calculation (when caller uses default 120)
        local task_type_for_timeout
        task_type_for_timeout=$(classify_task "$prompt" 2>/dev/null) || task_type_for_timeout="standard"
        timeout_secs=$(compute_dynamic_timeout "$task_type_for_timeout" "$prompt")
    fi

    # Determine role if not provided
    if [[ -z "$role" ]]; then
        local task_type
        task_type=$(classify_task "$prompt")
        role=$(get_role_for_context "$agent_type" "$task_type" "$phase")
    fi

    local _progress_unique
    if declare -F _octopus_next_spawn_task_id >/dev/null 2>&1; then
        _progress_unique="$(_octopus_next_spawn_task_id)"
    else
        local _sync_unique_dir
        _sync_unique_dir="$(mktemp -d "${TMPDIR:-/tmp}/octopus-sync-id.XXXXXX")" || return 74
        _progress_unique="$(basename "$_sync_unique_dir")-$$"
        rmdir "$_sync_unique_dir" 2>/dev/null || true
    fi
    local _sync_seat_id
    _sync_seat_id="sync-${phase:-unknown}-$(octo_agent_spec_slug "$agent_type")-${_progress_unique}"
    local _contract_provider _contract_requested_model
    _contract_provider="$(octo_agent_spec_contract_provider "$agent_type")" || return 74
    _contract_requested_model="$(octo_agent_spec_contract_model "$agent_type" "${OCTOPUS_REQUESTED_MODEL:-}")" || return 74
    if [[ "${OCTOPUS_PERSISTENCE_AVAILABLE:-true}" == "false" ]]; then
        log ERROR "Persistence unavailable; refusing untracked provider dispatch for $agent_type"
    fi
    run_contract_transition "$_sync_seat_id" planned \
        "requested_provider=$_contract_provider" \
        "requested_model=$_contract_requested_model" \
        "requested_effort=${OCTOPUS_REQUESTED_EFFORT:-}" \
        "phase=${phase:-unknown}" "role=${role:-none}" \
        "attempt_id=${_sync_seat_id}-attempt-1" || return 74

    # ═══════════════════════════════════════════════════════════════════════════
    # Cache-aligned prompt structure: stable prefix first, variable suffix last
    # This enables Claude's cached-token discount on repeated prefix content
    # ═══════════════════════════════════════════════════════════════════════════

    # ── STABLE PREFIX ─────────────────────────────────────────────────────────

    # Apply persona to prompt (v8.53.0: empty agent_name — readonly not enforced in sync agents)
    local enhanced_prompt
    enhanced_prompt=$(apply_persona "$role" "$prompt" "false" "")

    # v8.21.0: Check for persona pack override (run_agent_sync)
    if type get_persona_override &>/dev/null 2>&1 && [[ "${OCTOPUS_PERSONA_PACKS:-auto}" != "off" ]]; then
        local persona_override_file
        persona_override_file=$(get_persona_override "$agent_type" 2>/dev/null)
        if [[ -n "$persona_override_file" && -f "$persona_override_file" ]]; then
            local pack_persona
            pack_persona=$(cat "$persona_override_file" 2>/dev/null)
            if [[ -n "$pack_persona" ]]; then
                enhanced_prompt="${pack_persona}

---

${enhanced_prompt}"
                log "INFO" "Applied persona pack override from: $persona_override_file"
            fi
        fi
    fi

    # v8.18.0: Inject earned skills context (STABLE — changes rarely within a project)
    local earned_skills_ctx
    earned_skills_ctx=$(load_earned_skills 2>/dev/null)
    if [[ -n "$earned_skills_ctx" ]]; then
        if [[ ${#earned_skills_ctx} -gt 1500 ]]; then
            earned_skills_ctx="${earned_skills_ctx:0:1500}..."
        fi
        enhanced_prompt="${enhanced_prompt}

---

## Earned Project Skills
${earned_skills_ctx}"
    fi

    # ── VARIABLE SUFFIX ───────────────────────────────────────────────────────

    # v8.18.0: Inject per-provider history context (VARIABLE — changes each run)
    local provider_ctx
    provider_ctx=$(build_provider_context "$agent_type")
    if [[ -n "$provider_ctx" ]]; then
        # v8.41.0: Wrap file-sourced provider history in anti-injection nonce
        provider_ctx=$(sanitize_external_content "$provider_ctx" "provider-history")
        enhanced_prompt="${enhanced_prompt}

---

${provider_ctx}"
    fi

    # v9.37.0: Enforce prompt budget after all sync-agent injections, including
    # the Codex subagent preamble. This catches oversized prompts before a
    # provider burns time and exits with a context-length error.
    if [[ "$agent_type" == codex* && "$agent_type" != "codex-review" ]]; then
        enhanced_prompt="${CODEX_SUBAGENT_PREAMBLE}${enhanced_prompt}"
    fi
    local tokens_in
    tokens_in=$(( ${#enhanced_prompt} / 4 ))
    enhanced_prompt=$(enforce_context_budget "$enhanced_prompt" "$role" "$agent_type")
    local _budget_rc=$?
    if [[ $_budget_rc -ne 0 ]]; then
        run_contract_transition "$_sync_seat_id" failed \
            "reason=Prompt exceeded context budget" >/dev/null 2>&1 || true
        type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "failed" "$tokens_in" 0 "Prompt exceeded context budget" 0 "" "$role" "$_sync_seat_id" failed none || true
        return "$_budget_rc"
    fi

    log DEBUG "run_agent_sync: agent=$agent_type, role=${role:-none}, phase=${phase:-none}"

    if declare -f octo_routing_policy >/dev/null 2>&1 &&
       [[ "$(octo_routing_policy 2>/dev/null || printf '%s' off)" == "eval" ]] &&
       declare -f octo_route_task_class >/dev/null 2>&1; then
        local OCTOPUS_TASK_CLASS
        OCTOPUS_TASK_CLASS="$(octo_route_task_class "$enhanced_prompt" "$role" "$phase")"
        export OCTOPUS_TASK_CLASS
    fi

    # Resolve the baseline seat before provider preflight so failures retain the
    # v10 planned → starting lifecycle. Fable's atomic claim happens later,
    # during command construction, only after health and persistence succeed.
    local model
    if ! model=$(get_agent_model "$agent_type" "$phase" "$role"); then
        run_contract_transition "$_sync_seat_id" failed \
            "reason=Model resolution failed" >/dev/null 2>&1 || true
        return 1
    fi
    local _progress_task_id
    _progress_task_id="$_sync_seat_id"
    local _estimated_cost="0.000000"
    if type estimate_agent_call_cost >/dev/null 2>&1; then
        _estimated_cost=$(estimate_agent_call_cost "$agent_type" "$model" "$enhanced_prompt")
    fi
    run_contract_transition "$_sync_seat_id" starting \
        "resolved_provider=$_contract_provider" "resolved_model=$model" \
        "resolved_effort=${OCTOPUS_RESOLVED_EFFORT:-${OCTOPUS_REQUESTED_EFFORT:-}}" \
        "estimated_cost_usd=$_estimated_cost" || return 74

    # v8.49.0: Pre-dispatch health check — verify provider is reachable.
    local _provider_for_health="" _health_handler="none"
    _provider_for_health="$(octo_provider_canonical "$(octo_agent_spec_executor "$agent_type")" 2>/dev/null || true)"
    if [[ -n "$_provider_for_health" ]]; then
        _health_handler="$(octo_provider_health_handler "$_provider_for_health" 2>/dev/null || printf '%s' none)"
    fi
    if [[ "$_health_handler" != "none" ]]; then
        local _health_diag="" _health_failed=false
        if ! declare -f "$_health_handler" >/dev/null 2>&1; then
            _health_diag="registry health handler unavailable: $_health_handler"
            _health_failed=true
        elif ! _health_diag=$("$_health_handler" "$_provider_for_health" 2>&1); then
            _health_failed=true
        fi
        if [[ "$_health_failed" == true ]]; then
            log WARN "Provider '$_provider_for_health' health check failed: $_health_diag"
            log WARN "Skipping agent dispatch for $agent_type (provider unavailable)"
            type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "failed" "$tokens_in" 0 "Provider unavailable: $_health_diag" 0 "" "$role" "$_sync_seat_id" failed none || true
            run_contract_transition "$_sync_seat_id" failed \
                "reason=Provider unavailable: $_health_diag" >/dev/null 2>&1 || true
            echo "[Provider $_provider_for_health unavailable: $_health_diag]"
            return 1
        fi
    fi

    run_contract_transition "$_sync_seat_id" authenticated || return 74

    if [[ "${OCTOPUS_PERSISTENCE_AVAILABLE:-true}" == "false" ]]; then
        run_contract_transition "$_sync_seat_id" failed \
            "reason=Persistence unavailable" >/dev/null 2>&1 || true
        return 74
    fi

    local cmd _prompt_bytes
    if ! _prompt_bytes=$(octo_prompt_byte_length "$enhanced_prompt"); then
        run_contract_transition "$_sync_seat_id" failed \
            "reason=Prompt byte measurement failed" >/dev/null 2>&1 || true
        return 1
    fi
    if ! cmd=$(get_agent_command "$agent_type" "$phase" "$role" "$_prompt_bytes"); then
        run_contract_transition "$_sync_seat_id" failed \
            "reason=Provider command unavailable" >/dev/null 2>&1 || true
        return 1
    fi
    if declare -f octo_dispatch_command_model >/dev/null 2>&1; then
        model="$(octo_dispatch_command_model "$cmd" "$model")"
    fi

    record_agent_call "$agent_type" "$model" "$enhanced_prompt" "${phase:-unknown}" "${role:-none}" "0"

    # v7.25.0: Record metrics start
    local metrics_id=""
    if command -v record_agent_start &> /dev/null; then
        metrics_id=$(record_agent_start "$agent_type" "$model" "$enhanced_prompt" "${phase:-unknown}") || true
    fi

    # SECURITY: Use array-based execution to prevent word-splitting vulnerabilities
    local -a cmd_array
    local -a inner_cmd_array
    build_provider_env "$agent_type"
    octopus_sync_bind_resolved_model "$agent_type" "$model"
    read -ra inner_cmd_array <<< "$cmd"
    if [[ ${#PROVIDER_ENV_ARRAY[@]} -gt 0 ]]; then
        cmd_array=("${PROVIDER_ENV_ARRAY[@]}" "${inner_cmd_array[@]}")
        log "DEBUG" "Credential isolation active for $agent_type"
    else
        cmd_array=("${inner_cmd_array[@]}")
    fi

    # Capture output and exit code separately
    local output
    local exit_code
    local temp_err="${RESULTS_DIR}/.tmp-agent-error-${_progress_unique}.err"
    local temp_out="${RESULTS_DIR}/.tmp-agent-out-${_progress_unique}.out"

    # -p "" triggers headless mode for CLIs that require it while prompt content
    # comes via stdin to avoid OS argument limits. Qwen and Cursor Agent follow
    # the same headless contract; Copilot parity is
    # maintained with spawn/workflows dispatch paths.
    if [[ "$agent_type" == copilot* || "$agent_type" == qwen* || "$agent_type" == cursor-agent* ]]; then
        cmd_array+=(-p "")
    fi

    # v9.2.2: All agents use stdin to avoid ARG_MAX "Argument list too long" on large diffs (Issue #173)
    # Captured for partial-writes detection on timeout.
    local _dispatch_start _dispatch_cwd _sync_timeout_deadline=0
    _dispatch_start=$(date +%s)
    _dispatch_cwd=$(pwd)
    if [[ "$timeout_secs" =~ ^[0-9]+$ ]] && [[ "$timeout_secs" -gt 0 ]]; then
        _sync_timeout_deadline=$((_dispatch_start + timeout_secs))
    fi

    local _quota_watcher_pid=""

    # Always init temp files so readers never fail on missing file.
    mkdir -p "${RESULTS_DIR}" 2>/dev/null || true
    : > "$temp_err"
    : > "$temp_out"
    type update_agent_status >/dev/null 2>&1 && update_agent_status \
        "$agent_type" "running" 0 "$_estimated_cost" "$timeout_secs" \
        "$_progress_task_id" "${phase:-unknown}" "" || true
    run_contract_transition "$_sync_seat_id" running \
        "resolved_model=$model" || return 74

    # AGY has an intermittent native SIGSEGV under heterogeneous orchestration
    # (#943). Retry that provider exactly once, while keeping both attempts
    # inside the caller's original wall-clock budget. Signal stderr is retained
    # for every provider so terminal crashes remain diagnosable from run data.
    local _sync_retry_count=0
    local _sync_sigsegv_retries=0
    local _sync_recovered_sigsegv=false
    local _sync_signal_artifact=""
    case "$agent_type" in
        agy*|antigravity) _sync_sigsegv_retries=1 ;;
    esac

    while true; do
        local _attempt_timeout="$timeout_secs"
        if [[ "$_sync_timeout_deadline" -gt 0 ]]; then
            local _attempt_now
            _attempt_now=$(date +%s)
            if ! _attempt_timeout=$(octopus_sync_attempt_timeout \
                "$_sync_timeout_deadline" "$_attempt_now" "$_sync_retry_count"); then
                exit_code=124
                break
            fi
        fi

        if printf '%s' "$enhanced_prompt" | OCTOPUS_PRESERVE_CALLER_PROCESS_GROUP="true" \
            run_with_timeout "$_attempt_timeout" "${cmd_array[@]}" 2>"$temp_err" >"$temp_out"; then
            exit_code=0
        else
            exit_code=$?
        fi

        if [[ "$exit_code" -ge 128 && "$exit_code" -le 192 ]]; then
            local _signal_attempt=$((_sync_retry_count + 1))
            _sync_signal_artifact="${RESULTS_DIR}/sync-failure-${_progress_unique}-attempt-${_signal_attempt}.stderr.log"
            if (umask 077; cp "$temp_err" "$_sync_signal_artifact") 2>/dev/null; then
                chmod 600 "$_sync_signal_artifact" 2>/dev/null || true
            else
                _sync_signal_artifact=""
            fi
        fi

        if [[ "$exit_code" -eq 139 && "$_sync_retry_count" -lt "$_sync_sigsegv_retries" ]]; then
            _sync_retry_count=$((_sync_retry_count + 1))
            log WARN "Agent $agent_type exited 139 (SIGSEGV); retrying once within the original ${timeout_secs}s budget (stderr: ${_sync_signal_artifact:-unavailable})"
            : > "$temp_err"
            : > "$temp_out"
            continue
        fi
        [[ "$exit_code" -eq 0 && "$_sync_retry_count" -gt 0 ]] && _sync_recovered_sigsegv=true
        break
    done
    stop_quota_watcher "$_quota_watcher_pid"
    local _sync_output_truncated=false

    local _elapsed_ms
    _elapsed_ms=$(( ($(date +%s) - _dispatch_start) * 1000 ))

    # Check exit code and handle errors
    if [[ $exit_code -ne 0 ]]; then
        log ERROR "Agent $agent_type failed with exit code $exit_code (role=$role, phase=$phase)"
        if [[ -s "$temp_err" ]]; then
            log ERROR "Error details: $(cat "$temp_err")"
        fi
        # Hint callers when codex wrote deliverables under workspace-write
        # before SIGTERM — a bare "TIMEOUT" banner otherwise hides that work.
        if [[ $exit_code -eq 124 || $exit_code -eq 143 ]]; then
            # -newermt is GNU findutils only; skip silently on BSD find (macOS).
            if find /dev/null -newermt "@0" >/dev/null 2>&1; then
                # Single-pass while-read avoids `find | head` SIGPIPE under
                # inherited pipefail and counts every match instead of capping
                # at the head budget. -maxdepth bounds traversal on monorepos.
                local _n_changed=0
                local _samples=()
                local _line
                while IFS= read -r _line; do
                    _n_changed=$((_n_changed + 1))
                    [[ ${#_samples[@]} -lt 5 ]] && _samples+=("$_line")
                done < <(find "$_dispatch_cwd" -maxdepth "${OCTOPUS_PARTIAL_WRITES_DEPTH:-4}" \
                            -type f -newermt "@${_dispatch_start}" \
                            -not -path '*/.git/*' -not -path '*/node_modules/*' \
                            2>/dev/null)
                if [[ $_n_changed -gt 0 ]]; then
                    local _ts
                    _ts=$(date -d "@${_dispatch_start}" '+%H:%M:%S' 2>/dev/null \
                          || date -r "${_dispatch_start}" '+%H:%M:%S' 2>/dev/null \
                          || echo "dispatch")
                    log WARN "Timeout with ${_n_changed} file(s) modified in $_dispatch_cwd since dispatch — provider may have written deliverables. Inspect before retrying."
                    log INFO "Partial writes detected (${_n_changed} files changed since ${_ts})"
                    local _s
                    for _s in "${_samples[@]}"; do log INFO "   $_s"; done
                    [[ $_n_changed -gt 5 ]] && log INFO "   ... (+$((_n_changed - 5)) more)"
                fi
            fi
        fi
        local _sync_status="failed"
        local _sync_reason="Exit code $exit_code"
        if [[ $exit_code -eq 124 || $exit_code -eq 143 ]]; then
            _sync_status="timeout"
            _sync_reason="Timed out before completion"
        fi
        run_contract_transition "$_sync_seat_id" "$_sync_status" \
            "reason=$_sync_reason" "stderr_file=$_sync_signal_artifact" \
            "duration_ms=$_elapsed_ms" >/dev/null 2>&1 || true
        type update_agent_status >/dev/null 2>&1 && update_agent_status \
            "$agent_type" "$_sync_status" "$_elapsed_ms" "$_estimated_cost" "$timeout_secs" \
            "$_progress_task_id" "${phase:-unknown}" "$_sync_signal_artifact" || true
        type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "$_sync_status" "$tokens_in" "$(octo_estimate_tokens_for_file "$temp_out" 2>/dev/null || echo 0)" "$_sync_reason" "$_elapsed_ms" "$_sync_signal_artifact" "$role" "$_sync_seat_id" "$_sync_status" none || true
        rm -f "$temp_err" "$temp_out"
        return $exit_code
    fi

    if type classify_agent_output >/dev/null 2>&1; then
        local _classification _sync_status _sync_reason
        _classification=$(classify_agent_output "$temp_out" "$exit_code" "$agent_type" "$temp_err")
        _sync_status="${_classification%%:*}"
        _sync_reason="${_classification#*:}"
        if [[ "$_sync_status" == "failed" ]]; then
            # Oversize rejections are a provider-input-size mismatch, not a hard
            # run failure. Return 0 with empty output so multi-provider dispatch
            # loops continue to gather perspectives from remaining providers (#410).
            if [[ "$_sync_reason" == *"oversize"* || "$_sync_reason" == *"Prompt rejected by provider"* ]]; then
                log WARN "Agent $agent_type prompt rejected as oversized — skipping provider (reduce session context or lower OCTOPUS_CONTEXT_BUDGET)"
                type update_agent_status >/dev/null 2>&1 && update_agent_status \
                    "$agent_type" "skipped" "$_elapsed_ms" 0 "$timeout_secs" \
                    "$_progress_task_id" "${phase:-unknown}" "$_sync_signal_artifact" || true
                type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "skipped" "$tokens_in" 0 "Prompt rejected by provider (oversize)" "$_elapsed_ms" "$_sync_signal_artifact" "$role" "$_sync_seat_id" skipped none || true
                run_contract_transition "$_sync_seat_id" skipped \
                    "reason=Prompt rejected by provider (oversize)" \
                    "duration_ms=$_elapsed_ms" >/dev/null 2>&1 || true
                rm -f "$temp_err" "$temp_out"
                echo ""
                return 0
            fi
            log ERROR "Agent $agent_type returned unusable output: $_sync_reason"
            type update_agent_status >/dev/null 2>&1 && update_agent_status \
                "$agent_type" "failed" "$_elapsed_ms" "$_estimated_cost" "$timeout_secs" \
                "$_progress_task_id" "${phase:-unknown}" "$_sync_signal_artifact" || true
            type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "failed" "$tokens_in" "$(octo_estimate_tokens_for_file "$temp_out" 2>/dev/null || echo 0)" "$_sync_reason" "$_elapsed_ms" "$_sync_signal_artifact" "$role" "$_sync_seat_id" failed none || true
            run_contract_transition "$_sync_seat_id" failed \
                "reason=$_sync_reason" "stderr_file=$_sync_signal_artifact" \
                "duration_ms=$_elapsed_ms" >/dev/null 2>&1 || true
            rm -f "$temp_err" "$temp_out"
            return 1
        fi
        if [[ "$_sync_recovered_sigsegv" == "true" ]]; then
            _sync_status="degraded"
            if [[ -n "$_sync_reason" ]]; then
                _sync_reason="Recovered after AGY exit 139; ${_sync_reason}"
            else
                _sync_reason="Recovered after AGY exit 139"
            fi
        fi
        local _sync_artifact_source="$temp_out"
        if ! _octo_run_output_usable_file "$_sync_artifact_source" && \
           [[ "$_sync_status" == degraded ]] && \
           octo_file_has_codex_recoverable_stderr "$temp_err"; then
            _sync_artifact_source="$temp_err"
        fi

        # Apply the byte cap after selecting stdout or recoverable stderr so
        # both the returned text and durable artifact obey the same contract.
        local _max_bytes="${OCTOPUS_AGENT_MAX_OUTPUT_BYTES:-262144}"
        local _orig_bytes _banner _banner_bytes _budget _head_bytes _tail_bytes
        local _head_chunk="" _tail_chunk=""
        _orig_bytes="$(wc -c < "$_sync_artifact_source" 2>/dev/null | tr -d ' ')"
        [[ "$_orig_bytes" =~ ^[0-9]+$ ]] || _orig_bytes=0
        output="$(cat "$_sync_artifact_source")"
        if [[ "$_max_bytes" =~ ^[0-9]+$ && "$_max_bytes" -gt 0 && "$_orig_bytes" -gt "$_max_bytes" ]]; then
            _banner=$'\n\n--- OUTPUT TRUNCATED: '"${_orig_bytes}"$' bytes captured ---\n(override with OCTOPUS_AGENT_MAX_OUTPUT_BYTES=<bytes>; 0 disables cap)\n\n'
            _banner_bytes="$(printf '%s' "$_banner" | wc -c | tr -d ' ')"
            _budget=$((_max_bytes - _banner_bytes))
            if [[ "$_budget" -le 0 ]]; then
                output="${_banner:0:$_max_bytes}"
            else
                _head_bytes=$((_budget / 8))
                [[ "$_head_bytes" -gt 4096 ]] && _head_bytes=4096
                _tail_bytes=$((_budget - _head_bytes))
                _head_chunk="$(head -c "$_head_bytes" "$_sync_artifact_source" 2>/dev/null)"
                _tail_chunk="$(tail -c "$_tail_bytes" "$_sync_artifact_source" 2>/dev/null)"
                output="${_head_chunk}${_banner}${_tail_chunk}"
            fi
            log WARN "Agent $agent_type output truncated: ${_orig_bytes}B (cap=${_max_bytes}B)"
            _sync_output_truncated=true
        fi
        if [[ "$_sync_output_truncated" == "true" ]]; then
            _sync_status="degraded"
            if [[ -n "$_sync_reason" ]]; then
                _sync_reason="${_sync_reason}; output truncated"
            else
                _sync_reason="Output truncated"
            fi
        fi
        local _sync_result_artifact="${RESULTS_DIR}/sync-result-${_progress_unique}.md"
        local _sync_result_tmp
        _sync_result_tmp="$(mktemp "${_sync_result_artifact}.tmp.XXXXXX")" || {
            run_contract_transition "$_sync_seat_id" failed \
                "reason=Unable to allocate durable result artifact" >/dev/null 2>&1 || true
            rm -f "$temp_err" "$temp_out"
            return 1
        }
        local _sync_result_write_rc=0
        if [[ "$_sync_output_truncated" == true ]]; then
            (umask 077; printf '%s' "$output" > "$_sync_result_tmp") 2>/dev/null || _sync_result_write_rc=$?
        else
            (umask 077; cp "$_sync_artifact_source" "$_sync_result_tmp") 2>/dev/null || _sync_result_write_rc=$?
        fi
        if [[ "$_sync_result_write_rc" -ne 0 ]] || \
           ! mv "$_sync_result_tmp" "$_sync_result_artifact" 2>/dev/null; then
            rm -f "$_sync_result_tmp" "$temp_err" "$temp_out"
            run_contract_transition "$_sync_seat_id" failed \
                "reason=Unable to publish durable result artifact" >/dev/null 2>&1 || true
            return 1
        fi

        local _sync_stderr_artifact="$_sync_signal_artifact"
        if [[ -z "$_sync_stderr_artifact" && -s "$temp_err" ]]; then
            _sync_stderr_artifact="${RESULTS_DIR}/sync-stderr-${_progress_unique}.log"
            local _sync_stderr_tmp
            _sync_stderr_tmp="$(mktemp "${_sync_stderr_artifact}.tmp.XXXXXX")" || {
                run_contract_transition "$_sync_seat_id" failed \
                    "reason=Unable to allocate durable stderr artifact" >/dev/null 2>&1 || true
                rm -f "$temp_err" "$temp_out"
                return 1
            }
            if ! (umask 077; cp "$temp_err" "$_sync_stderr_tmp") 2>/dev/null || \
               ! mv "$_sync_stderr_tmp" "$_sync_stderr_artifact" 2>/dev/null; then
                rm -f "$_sync_stderr_tmp" "$temp_err" "$temp_out"
                run_contract_transition "$_sync_seat_id" failed \
                    "reason=Unable to publish durable stderr artifact" >/dev/null 2>&1 || true
                return 1
            fi
        fi

        run_contract_transition "$_sync_seat_id" output_received \
            "output_file=$_sync_result_artifact" "stderr_file=$_sync_stderr_artifact" \
            "attempt_id=${_sync_seat_id}-attempt-$((_sync_retry_count + 1))" \
            "tokens_out=$(octo_estimate_tokens_for_file "$_sync_result_artifact" 2>/dev/null || echo 0)" \
            "duration_ms=$_elapsed_ms" || {
                run_contract_transition "$_sync_seat_id" failed \
                    "reason=Unable to record received output" >/dev/null 2>&1 || true
                rm -f "$temp_err" "$temp_out"
                return 1
            }
        run_contract_transition "$_sync_seat_id" validated \
            "contribution=eligible" || {
                run_contract_transition "$_sync_seat_id" failed \
                    "reason=Unable to validate provider output" >/dev/null 2>&1 || true
                rm -f "$temp_err" "$temp_out"
                return 1
            }
        if [[ "$_sync_status" == degraded ]]; then
            run_contract_transition "$_sync_seat_id" degraded \
                "contribution=eligible-with-warning" "reason=$_sync_reason" || {
                    run_contract_transition "$_sync_seat_id" failed \
                        "reason=Unable to record degraded contribution" >/dev/null 2>&1 || true
                    rm -f "$temp_err" "$temp_out"
                    return 1
                }
        else
            run_contract_transition "$_sync_seat_id" contributed \
                "contribution=eligible" || {
                    run_contract_transition "$_sync_seat_id" failed \
                        "reason=Unable to record successful contribution" >/dev/null 2>&1 || true
                    rm -f "$temp_err" "$temp_out"
                    return 1
                }
        fi
        local _sync_projection_transition=contributed
        local _sync_projection_contribution=eligible
        if [[ "$_sync_status" == degraded ]]; then
            _sync_projection_transition=degraded
            _sync_projection_contribution=eligible-with-warning
        fi
        type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "$_sync_status" "$tokens_in" "$(octo_estimate_tokens_for_file "$_sync_result_artifact" 2>/dev/null || echo 0)" "$_sync_reason" "$_elapsed_ms" "$_sync_result_artifact" "$role" "$_sync_seat_id" "$_sync_projection_transition" "$_sync_projection_contribution" || true
        type update_agent_status >/dev/null 2>&1 && update_agent_status \
            "$agent_type" "$_sync_status" "$_elapsed_ms" "$_estimated_cost" "$timeout_secs" \
            "$_progress_task_id" "${phase:-unknown}" "$_sync_signal_artifact" || true
    else
        local _unclassified_status="completed"
        local _unclassified_reason=""
        if [[ "$_sync_recovered_sigsegv" == "true" ]]; then
            _unclassified_status="degraded"
            _unclassified_reason="Recovered after AGY exit 139"
        fi
        type write_agent_status >/dev/null 2>&1 && write_agent_status "$agent_type" "$_unclassified_status" "$tokens_in" "$(octo_estimate_tokens_for_file "$temp_out" 2>/dev/null || echo 0)" "$_unclassified_reason" "$_elapsed_ms" "$_sync_signal_artifact" "$role" || true
        type update_agent_status >/dev/null 2>&1 && update_agent_status \
            "$agent_type" "$_unclassified_status" "$_elapsed_ms" "$_estimated_cost" "$timeout_secs" \
            "$_progress_task_id" "${phase:-unknown}" "$_sync_signal_artifact" || true
    fi

    # v8.7.0: Wrap external CLI output with trust markers
    case "$agent_type" in codex*|gemini*|agy*|antigravity|perplexity*|cursor-agent*)
        output=$(wrap_cli_output "$agent_type" "$output") ;; esac

    # Check if output is suspiciously empty or placeholder
    if [[ -z "$output" || "$output" == "Provider available" ]]; then
        log WARN "Agent $agent_type returned empty or placeholder output (role=$role, phase=$phase)"
        if [[ -s "$temp_err" ]]; then
            log WARN "Possible issue: $(cat "$temp_err")"
        fi
    fi

    rm -f "$temp_err" "$temp_out"

    # v7.25.0: Record metrics completion
    if [[ -n "$metrics_id" ]] && command -v record_agent_complete &> /dev/null; then
        # v8.6.0: Pass native metrics from Task tool output
        parse_task_metrics "$output"
        record_agent_complete "$metrics_id" "$agent_type" "$model" "$output" "${phase:-unknown}" \
            "$_PARSED_TOKENS" "$_PARSED_TOOL_USES" "$_PARSED_DURATION_MS" 2>/dev/null || true
    fi

    echo "$output"
    return 0
}
