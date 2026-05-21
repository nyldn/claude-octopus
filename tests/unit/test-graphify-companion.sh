#!/usr/bin/env bash
# Unit tests for optional Graphify companion integration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GRAPHIFY_LIB="$PROJECT_ROOT/scripts/lib/graphify.sh"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Graphify companion"

if [[ -f "$GRAPHIFY_LIB" ]]; then
    # shellcheck source=/dev/null
    source "$GRAPHIFY_LIB"
fi

assert_function_exists() {
    local fn="$1"
    test_case "function exists: $fn"
    if declare -F "$fn" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "missing function: $fn"
    fi
}

test_case "graphify.sh has valid bash syntax"
if [[ -f "$GRAPHIFY_LIB" ]] && bash -n "$GRAPHIFY_LIB" 2>/dev/null; then
    test_pass
else
    test_fail "missing or invalid $GRAPHIFY_LIB"
fi

for fn in \
    octo_graphify_enabled \
    octo_graphify_bin \
    octo_graphify_out_dir \
    octo_graphify_status_json \
    octo_graphify_context_for_prompt \
    octo_graphify_install_hint
do
    assert_function_exists "$fn"
done

test_case "OCTOPUS_GRAPHIFY=0 disables companion"
if declare -F octo_graphify_enabled >/dev/null 2>&1; then
    if OCTOPUS_GRAPHIFY=0 octo_graphify_enabled; then
        test_fail "expected Graphify companion to be disabled"
    else
        test_pass
    fi
else
    test_fail "octo_graphify_enabled is not defined"
fi

test_case "status reports missing CLI and missing graph"
if declare -F octo_graphify_status_json >/dev/null 2>&1; then
    tmp_root=$(mktemp -d)
    status=$(OCTOPUS_GRAPHIFY_BIN="$tmp_root/missing-graphify" octo_graphify_status_json "$tmp_root")
    if jq -e '.installed == false and .graph_exists == false and .report_exists == false and .enabled == true' <<< "$status" >/dev/null; then
        test_pass
    else
        test_fail "unexpected status for missing CLI/graph: $status"
    fi
    rm -rf "$tmp_root"
else
    test_fail "octo_graphify_status_json is not defined"
fi

test_case "status reports installed CLI, graph, report, hook, and stale flag"
if declare -F octo_graphify_status_json >/dev/null 2>&1; then
    tmp_root=$(mktemp -d)
    mock_bin="$tmp_root/graphify"
    cat > "$mock_bin" <<'MOCK'
#!/usr/bin/env bash
case "${1:-}" in
  --version) echo "graphify 0.7.7" ;;
  hook)
    if [[ "${2:-}" == "status" ]]; then
      echo "post-commit: installed"
      echo "post-checkout: installed"
    fi
    ;;
  *) echo "Usage: graphify <command>" ;;
esac
MOCK
    chmod +x "$mock_bin"
    mkdir -p "$tmp_root/graphify-out"
    echo '{"nodes":[],"edges":[]}' > "$tmp_root/graphify-out/graph.json"
    echo "# Graph Report" > "$tmp_root/graphify-out/GRAPH_REPORT.md"
    : > "$tmp_root/graphify-out/needs_update"
    status=$(OCTOPUS_GRAPHIFY_BIN="$mock_bin" octo_graphify_status_json "$tmp_root")
    if jq -e '.installed == true and .version == "0.7.7" and .graph_exists == true and .report_exists == true and .needs_update == true and (.hook_status | test("post-commit: installed"))' <<< "$status" >/dev/null; then
        test_pass
    else
        test_fail "unexpected status for installed CLI/graph: $status"
    fi
    rm -rf "$tmp_root"
else
    test_fail "octo_graphify_status_json is not defined"
fi

test_case "context prompt includes report excerpt and avoids auto-build guidance"
if declare -F octo_graphify_context_for_prompt >/dev/null 2>&1; then
    tmp_root=$(mktemp -d)
    mock_bin="$tmp_root/graphify"
    printf '#!/usr/bin/env bash\necho "graphify 0.7.7"\n' > "$mock_bin"
    chmod +x "$mock_bin"
    mkdir -p "$tmp_root/graphify-out"
    echo '{"nodes":[],"edges":[]}' > "$tmp_root/graphify-out/graph.json"
    cat > "$tmp_root/graphify-out/GRAPH_REPORT.md" <<'REPORT'
# Graph Report

## God Nodes
- Review Pipeline

## Suggested Questions
- How does review state connect to provider fallback handling?
REPORT
    context=$(OCTOPUS_GRAPHIFY_BIN="$mock_bin" octo_graphify_context_for_prompt "$tmp_root" 2000)
    if grep -q "Graphify companion context" <<< "$context" \
       && grep -q "Review Pipeline" <<< "$context" \
       && grep -q "Use this as an orientation map" <<< "$context" \
       && ! grep -q "graphify extract" <<< "$context"; then
        test_pass
    else
        test_fail "context prompt was unexpected: $context"
    fi
    rm -rf "$tmp_root"
else
    test_fail "octo_graphify_context_for_prompt is not defined"
fi

test_case "context helper can be sourced from zsh shells"
if command -v zsh >/dev/null 2>&1; then
    tmp_root=$(mktemp -d)
    mock_bin="$tmp_root/graphify"
    printf '#!/usr/bin/env bash\necho "graphify 0.7.7"\n' > "$mock_bin"
    chmod +x "$mock_bin"
    mkdir -p "$tmp_root/graphify-out"
    echo '{"nodes":[],"edges":[]}' > "$tmp_root/graphify-out/graph.json"
    echo "# Graph Report" > "$tmp_root/graphify-out/GRAPH_REPORT.md"
    context=$(
        TMP_ROOT="$tmp_root" \
        MOCK_BIN="$mock_bin" \
        GRAPHIFY_LIB="$GRAPHIFY_LIB" \
        zsh -fc 'source "$GRAPHIFY_LIB"; OCTOPUS_GRAPHIFY_BIN="$MOCK_BIN" octo_graphify_context_for_prompt "$TMP_ROOT" 2000'
    )
    if grep -q "Graphify companion context" <<< "$context"; then
        test_pass
    else
        test_fail "zsh-sourced context prompt was unexpected: $context"
    fi
    rm -rf "$tmp_root"
else
    test_skip "zsh not installed"
fi

test_case "context prompt is empty when graph report is absent"
if declare -F octo_graphify_context_for_prompt >/dev/null 2>&1; then
    tmp_root=$(mktemp -d)
    context=$(OCTOPUS_GRAPHIFY_BIN="$tmp_root/missing-graphify" octo_graphify_context_for_prompt "$tmp_root" 2000)
    if [[ -z "$context" ]]; then
        test_pass
    else
        test_fail "expected empty context without graph report, got: $context"
    fi
    rm -rf "$tmp_root"
else
    test_fail "octo_graphify_context_for_prompt is not defined"
fi

test_summary
