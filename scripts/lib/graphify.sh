#!/usr/bin/env bash
# Optional Graphify companion helpers.
#
# Graphify is not an Octopus provider. These helpers detect an existing local
# knowledge graph and pass a compact orientation packet into escalated workflows.

octo_graphify_enabled() {
    case "${OCTOPUS_GRAPHIFY:-1}" in
        0|false|FALSE|off|OFF|no|NO) return 1 ;;
    esac
    command -v jq >/dev/null 2>&1
}

octo_graphify_bin() {
    if [[ -n "${OCTOPUS_GRAPHIFY_BIN:-}" ]]; then
        [[ -x "$OCTOPUS_GRAPHIFY_BIN" ]] || return 1
        printf '%s\n' "$OCTOPUS_GRAPHIFY_BIN"
        return 0
    fi
    command -v graphify 2>/dev/null
}

octo_graphify_out_dir() {
    local project_root="${1:-$(pwd)}"
    local out="${GRAPHIFY_OUT:-graphify-out}"
    case "$out" in
        /*) printf '%s\n' "$out" ;;
        *) printf '%s/%s\n' "${project_root%/}" "$out" ;;
    esac
}

octo_graphify_install_hint() {
    cat <<'EOF'
Install Graphify with:
  uv tool install graphifyy

Then, inside a project:
  graphify extract .
  graphify claude install
  graphify codex install
  graphify hook install
EOF
}

_octo_graphify_version() {
    local bin="$1"
    local raw version
    raw=$("$bin" --version 2>&1 | head -1 || true)
    version=$(printf '%s' "$raw" | grep -oE '[0-9]+(\.[0-9]+){1,3}' | head -1 || true)
    printf '%s\n' "${version:-unknown}"
}

_octo_graphify_hook_status() {
    local bin="$1"
    "$bin" hook status 2>/dev/null | head -20 || true
}

octo_graphify_status_json() {
    local project_root="${1:-$(pwd)}"
    local enabled="false"
    octo_graphify_enabled && enabled="true"

    local bin="" installed="false" version="missing" hook_status=""
    if [[ "$enabled" == "true" ]]; then
        bin=$(octo_graphify_bin 2>/dev/null || true)
        if [[ -n "$bin" ]]; then
            installed="true"
            version=$(_octo_graphify_version "$bin")
            hook_status=$(_octo_graphify_hook_status "$bin")
        fi
    fi

    local out_dir graph_path report_path wiki_path needs_update_path
    local graph_exists="false" report_exists="false" wiki_exists="false" needs_update="false"
    out_dir=$(octo_graphify_out_dir "$project_root")
    graph_path="$out_dir/graph.json"
    report_path="$out_dir/GRAPH_REPORT.md"
    wiki_path="$out_dir/wiki/index.md"
    needs_update_path=""

    [[ -f "$graph_path" ]] && graph_exists="true"
    [[ -f "$report_path" ]] && report_exists="true"
    [[ -f "$wiki_path" ]] && wiki_exists="true"
    if [[ -e "$out_dir/needs_update" ]]; then
        needs_update="true"
        needs_update_path="$out_dir/needs_update"
    elif [[ -e "$out_dir/.needs_update" ]]; then
        needs_update="true"
        needs_update_path="$out_dir/.needs_update"
    fi

    jq -n \
        --argjson enabled "$enabled" \
        --argjson installed "$installed" \
        --arg bin "$bin" \
        --arg version "$version" \
        --arg out_dir "$out_dir" \
        --arg graph_path "$graph_path" \
        --arg report_path "$report_path" \
        --arg wiki_path "$wiki_path" \
        --arg needs_update_path "$needs_update_path" \
        --arg hook_status "$hook_status" \
        --argjson graph_exists "$graph_exists" \
        --argjson report_exists "$report_exists" \
        --argjson wiki_exists "$wiki_exists" \
        --argjson needs_update "$needs_update" \
        '{
          enabled: $enabled,
          installed: $installed,
          bin: $bin,
          version: $version,
          out_dir: $out_dir,
          graph_path: $graph_path,
          report_path: $report_path,
          wiki_path: $wiki_path,
          graph_exists: $graph_exists,
          report_exists: $report_exists,
          wiki_exists: $wiki_exists,
          needs_update: $needs_update,
          needs_update_path: $needs_update_path,
          hook_status: $hook_status
        }'
}

octo_graphify_context_for_prompt() {
    local project_root="${1:-$(pwd)}"
    local max_chars="${2:-12000}"

    octo_graphify_enabled || return 0

    local graphify_status report_path graph_path needs_update installed version hook_status
    graphify_status=$(octo_graphify_status_json "$project_root" 2>/dev/null || true)
    [[ -n "$graphify_status" ]] || return 0

    report_path=$(printf '%s' "$graphify_status" | jq -r '.report_path')
    graph_path=$(printf '%s' "$graphify_status" | jq -r '.graph_path')
    needs_update=$(printf '%s' "$graphify_status" | jq -r '.needs_update')
    installed=$(printf '%s' "$graphify_status" | jq -r '.installed')
    version=$(printf '%s' "$graphify_status" | jq -r '.version')
    hook_status=$(printf '%s' "$graphify_status" | jq -r '.hook_status // ""')

    [[ -f "$report_path" ]] || return 0

    local freshness="current"
    [[ "$needs_update" == "true" ]] && freshness="needs_update flag present"

    {
        echo "Graphify companion context (optional; existing local graph only)"
        echo "Source report: $report_path"
        echo "Graph JSON: $graph_path"
        echo "Graphify CLI: installed=${installed} version=${version}"
        echo "Freshness: $freshness"
        if [[ -n "$hook_status" ]]; then
            echo "Hook status: $(printf '%s' "$hook_status" | tr '\n' ';' | sed 's/;$//')"
        fi
        echo ""
        echo "Use this as an orientation map, not a replacement for exact source reads."
        echo "For cross-module relationship questions, prefer graphify query/path/explain when the CLI is installed."
        echo "Do not build or refresh graphs unless the user explicitly asked for Graphify work or graph maintenance is already in scope."
        echo ""
        echo "Report excerpt:"
        echo '```markdown'
        sed -n '1,220p' "$report_path"
        echo '```'
    } | cut -c "1-${max_chars}"
}
