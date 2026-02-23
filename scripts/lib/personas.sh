#!/usr/bin/env bash
# Claude Octopus - Persona Packs Library (v8.21.0)
# Provides: community persona pack discovery, loading, and management
#
# Sourced by orchestrate.sh. Persona packs allow users to customize
# agent personas without modifying core plugin code.

# Source guard — prevent double-loading
[[ -n "${_PERSONAS_LOADED:-}" ]] && return 0
_PERSONAS_LOADED=1

# ═══════════════════════════════════════════════════════════════════════════════
# PERSONA PACK DISCOVERY
# ═══════════════════════════════════════════════════════════════════════════════

# Discover persona packs from standard search paths
# Returns newline-separated list of pack directories
# Usage: discover_persona_packs [additional_paths]
discover_persona_packs() {
    local extra_paths="${1:-}"
    local found=""

    # Standard search paths (in priority order)
    local search_paths=(
        "${PROJECT_ROOT:-.}/.octopus/personas"    # Project-local
        "${HOME}/.claude-octopus/personas"          # User-global
    )

    # Add custom paths from env var (colon-separated)
    if [[ -n "${OCTOPUS_PERSONA_PACKS:-}" && "${OCTOPUS_PERSONA_PACKS}" != "auto" && "${OCTOPUS_PERSONA_PACKS}" != "off" ]]; then
        IFS=':' read -ra custom_paths <<< "$OCTOPUS_PERSONA_PACKS"
        search_paths+=("${custom_paths[@]}")
    fi

    # Add any extra paths passed as argument
    if [[ -n "$extra_paths" ]]; then
        IFS=':' read -ra extra <<< "$extra_paths"
        search_paths+=("${extra[@]}")
    fi

    for search_dir in "${search_paths[@]}"; do
        [[ -d "$search_dir" ]] || continue
        # Look for pack.yaml files
        while IFS= read -r -d '' pack_file; do
            local pack_dir
            pack_dir=$(dirname "$pack_file")
            found+="$pack_dir"$'\n'
        done < <(find "$search_dir" -maxdepth 2 -name "pack.yaml" -print0 2>/dev/null)
    done

    echo "$found" | sed '/^$/d' | sort -u
}

# ═══════════════════════════════════════════════════════════════════════════════
# PERSONA PACK LOADING
# ═══════════════════════════════════════════════════════════════════════════════

# Load and parse a persona pack manifest
# Returns pack metadata as key=value pairs
# Usage: load_persona_pack <pack_dir>
load_persona_pack() {
    local pack_dir="$1"
    local manifest="$pack_dir/pack.yaml"

    [[ -f "$manifest" ]] || { echo ""; return 1; }

    # Extract fields from YAML using awk (no yq dependency)
    local name version author description
    name=$(awk '/^name:/ { gsub(/^name:[[:space:]]*"?|"?$/, ""); print }' "$manifest" 2>/dev/null)
    version=$(awk '/^version:/ { gsub(/^version:[[:space:]]*"?|"?$/, ""); print }' "$manifest" 2>/dev/null)
    author=$(awk '/^author:/ { gsub(/^author:[[:space:]]*"?|"?$/, ""); print }' "$manifest" 2>/dev/null)
    description=$(awk '/^description:/ { gsub(/^description:[[:space:]]*"?|"?$/, ""); print }' "$manifest" 2>/dev/null)

    # Validate required fields
    if [[ -z "$name" ]]; then
        log "WARN" "Persona pack at $pack_dir missing 'name' field" 2>/dev/null || true
        return 1
    fi

    # Count persona files
    local persona_count=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*file: ]]; then
            ((persona_count++))
        fi
    done < "$manifest"

    # Also count .md files in the directory as fallback
    if [[ $persona_count -eq 0 ]]; then
        persona_count=$(find "$pack_dir" -maxdepth 1 -name "*.md" ! -name "README.md" -print 2>/dev/null | wc -l | tr -d ' ')
    fi

    echo "name=$name"
    echo "version=${version:-1.0.0}"
    echo "author=${author:-unknown}"
    echo "description=${description:-}"
    echo "persona_count=$persona_count"
    echo "pack_dir=$pack_dir"
}

# Get the list of persona entries from a pack manifest
# Returns: lines of "file|mode|target" (mode=replaces|extends, target=agent name)
# Usage: get_pack_personas <pack_dir>
get_pack_personas() {
    local pack_dir="$1"
    local manifest="$pack_dir/pack.yaml"

    [[ -f "$manifest" ]] || return 0

    # Parse personas section from YAML
    awk '
        /^personas:/ { in_personas=1; next }
        in_personas && /^[a-z]/ { in_personas=0 }
        in_personas && /^[[:space:]]*-[[:space:]]*file:/ {
            # Flush previous entry before starting new one
            if (file != "" && target != "") {
                print file "|" mode "|" target
            }
            gsub(/^[[:space:]]*-[[:space:]]*file:[[:space:]]*/, "")
            gsub(/"/, "")
            file=$0
            mode="extends"
            target=""
        }
        in_personas && /replaces:/ {
            gsub(/.*replaces:[[:space:]]*/, "")
            gsub(/"/, "")
            mode="replaces"
            target=$0
        }
        in_personas && /extends:/ {
            gsub(/.*extends:[[:space:]]*/, "")
            gsub(/"/, "")
            mode="extends"
            target=$0
        }
        in_personas && /capabilities:/ { next }
        END {
            if (file != "" && target != "") {
                print file "|" mode "|" target
            }
        }
    ' "$manifest" 2>/dev/null
}

# Apply a persona pack
# Usage: apply_persona_pack <pack_dir>
apply_persona_pack() {
    local pack_dir="$1"
    local active_packs_file="${WORKSPACE_DIR:-.}/.octo/active-packs.json"

    # Load pack metadata
    local pack_info
    pack_info=$(load_persona_pack "$pack_dir")
    [[ -z "$pack_info" ]] && return 1

    local pack_name
    pack_name=$(echo "$pack_info" | grep "^name=" | cut -d= -f2-)
    local persona_count
    persona_count=$(echo "$pack_info" | grep "^persona_count=" | cut -d= -f2-)

    # Register in active packs
    mkdir -p "$(dirname "$active_packs_file")" 2>/dev/null || true

    if command -v jq &>/dev/null && [[ -f "$active_packs_file" ]]; then
        local tmp="${active_packs_file}.tmp.$$"
        jq --arg name "$pack_name" --arg dir "$pack_dir" --arg count "$persona_count" \
            '.[$name] = {dir: $dir, persona_count: ($count|tonumber), loaded_at: now|todate}' \
            "$active_packs_file" > "$tmp" 2>/dev/null && mv "$tmp" "$active_packs_file"
    else
        # Simple JSON creation
        printf '{\n  "%s": {"dir": "%s", "persona_count": %s}\n}\n' \
            "$pack_name" "$pack_dir" "$persona_count" > "$active_packs_file"
    fi

    log "INFO" "Persona pack loaded: $pack_name ($persona_count personas) from $pack_dir" 2>/dev/null || true
    return 0
}

# List active persona packs
# Returns formatted list: "pack_name (N personas) — source"
# Usage: list_active_packs
list_active_packs() {
    local active_packs_file="${WORKSPACE_DIR:-.}/.octo/active-packs.json"

    [[ -f "$active_packs_file" ]] || { echo ""; return 0; }

    if command -v jq &>/dev/null; then
        jq -r 'to_entries[] | "\(.key) (\(.value.persona_count) personas) — \(.value.dir)"' "$active_packs_file" 2>/dev/null
    else
        # Fallback: just show the file exists
        grep -o '"[^"]*":' "$active_packs_file" 2>/dev/null | tr -d '":' | while read -r name; do
            echo "$name (loaded)"
        done
    fi
}

# Unload a persona pack
# Usage: unload_persona_pack <pack_name>
unload_persona_pack() {
    local pack_name="$1"
    local active_packs_file="${WORKSPACE_DIR:-.}/.octo/active-packs.json"

    [[ -f "$active_packs_file" ]] || return 0

    if command -v jq &>/dev/null; then
        local tmp="${active_packs_file}.tmp.$$"
        jq --arg name "$pack_name" 'del(.[$name])' "$active_packs_file" > "$tmp" 2>/dev/null && mv "$tmp" "$active_packs_file"
    fi

    log "INFO" "Persona pack unloaded: $pack_name" 2>/dev/null || true
}

# Get persona override for a specific agent
# Returns the persona file path if an active pack overrides this agent, empty otherwise
# Usage: get_persona_override <agent_name>
get_persona_override() {
    local agent_name="$1"
    local active_packs_file="${WORKSPACE_DIR:-.}/.octo/active-packs.json"

    [[ -f "$active_packs_file" ]] || { echo ""; return 0; }

    # Check each active pack for an override of this agent
    if command -v jq &>/dev/null; then
        local pack_dirs
        pack_dirs=$(jq -r '.[].dir' "$active_packs_file" 2>/dev/null)
        while IFS= read -r pack_dir; do
            [[ -z "$pack_dir" ]] && continue
            local personas
            personas=$(get_pack_personas "$pack_dir")
            while IFS='|' read -r file mode target; do
                if [[ "$target" == "$agent_name" ]]; then
                    echo "$pack_dir/$file"
                    return 0
                fi
            done <<< "$personas"
        done <<< "$pack_dirs"
    fi

    echo ""
}

# Auto-load persona packs from standard paths
# Called during orchestrate.sh initialization
# Usage: auto_load_persona_packs
auto_load_persona_packs() {
    [[ "${OCTOPUS_PERSONA_PACKS:-auto}" == "off" ]] && return 0

    local packs
    packs=$(discover_persona_packs)
    [[ -z "$packs" ]] && return 0

    local count=0
    while IFS= read -r pack_dir; do
        [[ -z "$pack_dir" ]] && continue
        apply_persona_pack "$pack_dir" && ((count++))
    done <<< "$packs"

    if [[ $count -gt 0 ]]; then
        log "INFO" "Auto-loaded $count persona pack(s)" 2>/dev/null || true
    fi
}
