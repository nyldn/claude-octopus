#!/usr/bin/env bash
# Read-only installation validation shared by diagnostics and repair.
# OCTO_ROOT_VALID_DETAIL is read by callers after validation.
# shellcheck disable=SC2034

_octo_root_path_valid() {
    local root="$1" ref="$2" kind="$3" path parent target hops=0
    # Reject lexical escapes and control characters before resolving symlinks.
    case "$ref" in
        ''|/*|*\\*|*:*|..|../*|*/../*|*/..|*[[:cntrl:]]*) return 1 ;;
    esac
    path="$root/${ref#./}"
    while :; do
        parent="$(cd -P "$(dirname "$path")" 2>/dev/null && pwd -P)" || return 1
        path="$parent/$(basename "$path")"
        case "$path" in "$root"/*) ;; *) return 1 ;; esac
        [[ -L "$path" ]] || break
        hops=$((hops + 1))
        [[ "$hops" -le 40 ]] || return 1
        target="$(readlink "$path")" || return 1
        case "$target" in /*) path="$target" ;; *) path="$parent/$target" ;; esac
    done
    case "$kind" in
        directory)
            [[ -d "$path" ]] || return 1
            path="$(cd -P "$path" 2>/dev/null && pwd -P)" || return 1
            case "$path" in "$root"|"$root"/*) return 0 ;; esac
            return 1 ;;
        file) [[ -f "$path" && -r "$path" ]] ;;
        executable) [[ -f "$path" && -x "$path" && -r "$path" ]] ;;
        *) return 1 ;;
    esac
}

octo_validate_install_root() {
    local root="$1" host="${2:-claude}" manifest refs kind ref
    OCTO_ROOT_VALID_DETAIL="plugin root is missing or inaccessible"
    root="$(cd -P "$root" 2>/dev/null && pwd -P)" || return 1
    case "$host" in
        codex) manifest=.codex-plugin/plugin.json ;;
        *) manifest=.claude-plugin/plugin.json ;;
    esac
    OCTO_ROOT_VALID_DETAIL="manifest is missing, unreadable, or outside the plugin root"
    _octo_root_path_valid "$root" "$manifest" file || return 1
    OCTO_ROOT_VALID_DETAIL="manifest is invalid or has incorrectly typed references"
    # Keep paths encoded until their types and control characters are checked.
    refs="$(jq -esr '
        def path: type == "string" and length > 0 and (test("[[:cntrl:]]") | not);
        def paths: path or (type == "array" and all(.[]; path));
        if length == 1 then .[0] else error("expected one manifest") end |
        if type != "object" then error("manifest must be an object") else . end |
        if (.version | path) and
           (all([.skills?, .commands?, .agents?][]; . == null or paths)) and
           (all([.hooks?, .mcpServers?, .lspServers?][]; . == null or type == "object" or paths)) and
           (.interface == null or (.interface | type == "object")) and
           (all([.interface.composerIcon?, .interface.logo?][]; . == null or path))
        then . else error("invalid manifest fields") end |
        [
          (.skills? | select(. != null) | if type == "array" then .[] else . end | ["directory", .]),
          (.commands?, .agents? | select(. != null) |
            if type == "array" then .[] | ["file", .]
            else [if endswith(".md") then "file" else "directory" end, .] end),
          (.hooks?, .mcpServers?, .lspServers? | select(. != null and type != "object") |
            if type == "array" then .[] else . end | ["file", .]),
          (.interface.composerIcon?, .interface.logo? | select(. != null) | ["file", .])
        ] | map(@tsv) | join("\n")
    ' "$root/$manifest" 2>/dev/null)" || return 1
    OCTO_ROOT_VALID_DETAIL="scripts/orchestrate.sh is missing, not executable, or outside the plugin root"
    _octo_root_path_valid "$root" scripts/orchestrate.sh executable || return 1
    OCTO_ROOT_VALID_DETAIL="manifest references could not be read or validated"
    while IFS=$'\t' read -r kind ref; do
        [[ -n "$kind" ]] || continue
        OCTO_ROOT_VALID_DETAIL="manifest reference must be a contained $kind: $ref"
        _octo_root_path_valid "$root" "$ref" "$kind" || return 1
    done <<< "$refs" || return 1
    OCTO_ROOT_VALID_DETAIL="manifest, runtime, and typed references are valid"
}
