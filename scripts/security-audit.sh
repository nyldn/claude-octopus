#!/usr/bin/env bash
# Offline, non-destructive checks for the installed plugin files.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="${OCTOPUS_SECURITY_AUDIT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd -P)}"
OUTPUT=human
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json|json) OUTPUT=json ;;
        --help|-h) printf 'Usage: %s [--json]\n' "$(basename "$0")"; exit 0 ;;
        *) printf 'Unknown security-audit option: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done
command -v jq >/dev/null 2>&1 || { printf 'security-audit requires jq\n' >&2; exit 1; }

checks='[]'
failures=0
add_check() {
    local name="$1" status="$2" detail="$3"
    checks="$(jq -cn --argjson checks "$checks" --arg name "$name" --arg status "$status" \
        --arg detail "$detail" '$checks + [{name:$name,status:$status,detail:$detail}]')"
    [[ "$status" != fail ]] || failures=$((failures + 1))
}

syntax_failures=0
while IFS= read -r -d '' file; do
    bash -n "$file" >/dev/null 2>&1 || syntax_failures=$((syntax_failures + 1))
done < <(find "$ROOT_DIR/hooks" "$ROOT_DIR/scripts" -type f -name '*.sh' -print0 2>/dev/null)
if [[ "$syntax_failures" -eq 0 ]]; then
    add_check shell-syntax pass "all hook and script shell files parse"
else
    add_check shell-syntax fail "$syntax_failures shell file(s) failed bash -n"
fi

if [[ -f "$ROOT_DIR/hooks/hooks.json" ]] && jq -e 'type == "object" and (.hooks | type == "object")' \
      "$ROOT_DIR/hooks/hooks.json" >/dev/null 2>&1; then
    add_check hooks-manifest pass "hook manifest is valid JSON"
else
    add_check hooks-manifest fail "hook manifest is missing, invalid, or lacks a hooks object"
fi

manifest_failures=0
manifest_count=0
for manifest in "$ROOT_DIR/.claude-plugin/plugin.json" "$ROOT_DIR/.codex-plugin/plugin.json"; do
    [[ -e "$manifest" ]] || continue
    manifest_count=$((manifest_count + 1))
    jq -e 'type == "object" and (.name | type == "string") and (.version | type == "string")' \
        "$manifest" >/dev/null 2>&1 || manifest_failures=$((manifest_failures + 1))
done
if [[ "$manifest_failures" -gt 0 ]]; then
    add_check plugin-manifests fail "$manifest_failures plugin manifest(s) are invalid"
elif [[ "$manifest_count" -gt 0 ]]; then
    add_check plugin-manifests pass "$manifest_count plugin manifest(s) are valid"
else
    add_check plugin-manifests warn "no plugin manifests were present in the selected root"
fi

if command -v rg >/dev/null 2>&1; then
    risk_patterns="$(rg -n --hidden --glob '*.sh' --glob '!tests/**' \
        '(^|[[:space:]])eval[[:space:]]|curl[^|]*\|[[:space:]]*(bash|sh)|chmod[[:space:]]+777' \
        "$ROOT_DIR/hooks" "$ROOT_DIR/scripts" 2>/dev/null || true)"
    if [[ -n "$risk_patterns" ]]; then
        add_check shell-risk-patterns warn "reviewable high-risk shell patterns found"
    else
        add_check shell-risk-patterns pass "no high-risk shell patterns found"
    fi

    host_paths="$(rg -n --hidden --glob '*.sh' --glob '!tests/**' \
        --glob '!security-audit.sh' --glob '!validate-no-hardcoded-paths.sh' \
        '(/Users/[^/$[:space:]]+|/home/[^/$[:space:]]+|[A-Za-z]:\\\\Users\\\\[^%$[:space:]]+)' \
        "$ROOT_DIR/hooks" "$ROOT_DIR/scripts" 2>/dev/null || true)"
    if [[ -n "$host_paths" ]]; then
        add_check host-specific-paths warn "host-specific absolute paths found"
    else
        add_check host-specific-paths pass "no host-specific absolute paths found"
    fi
else
    add_check shell-risk-patterns warn "ripgrep is unavailable; shell risk scan was skipped"
    add_check host-specific-paths warn "ripgrep is unavailable; host path scan was skipped"
fi

report="$(jq -cn --argjson checks "$checks" --argjson failures "$failures" \
    '{schema:1,failures:$failures,checks:$checks}')"
if [[ "$OUTPUT" == json ]]; then
    printf '%s\n' "$report"
else
    printf 'Claude Octopus local security audit\n'
    jq -r '.checks[] | "  \(.status)\t\(.name)\t\(.detail)"' <<<"$report"
fi
[[ "$failures" -eq 0 ]]
