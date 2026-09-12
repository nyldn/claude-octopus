#!/usr/bin/env bash
# Export a small, redacted checkpoint for another supported host.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/lifecycle.sh
source "$SCRIPT_DIR/lib/lifecycle.sh"

action="export"
output=""
json=false
action_seen=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        export|show)
            [[ "$action_seen" == false ]] || { printf 'Choose one handoff action\n' >&2; exit 2; }
            action="$1"; action_seen=true
            ;;
        --json) json=true ;;
        --out)
            [[ -n "${2:-}" ]] || { printf '%s requires a path\n' "$1" >&2; exit 2; }
            output="$2"; shift
            ;;
        --help|-h)
            printf 'Usage: %s [export|show] [--json] [--out path]\n' "$(basename "$0")"
            exit 0
            ;;
        *) printf 'Unknown handoff option: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done
command -v jq >/dev/null 2>&1 || { printf 'handoff requires jq\n' >&2; exit 1; }

project_root="${OCTOPUS_PROJECT_DIR:-$PWD}"
handoff_dir="${OCTOPUS_HANDOFF_DIR:-${HOME}/.claude-octopus/handoffs}"
file="${output:-$handoff_dir/$(octo_lifecycle_handoff_id "$project_root").json}"

if [[ "$action" == show ]]; then
    [[ -f "$file" && ! -L "$file" ]] || { printf 'handoff not found: %s\n' "$file" >&2; exit 1; }
    if [[ "$json" == true ]]; then cat "$file"; else jq . "$file"; fi
    exit 0
fi

[[ ! -L "$file" ]] || { printf 'refusing to replace a symlink: %s\n' "$file" >&2; exit 1; }
session_file="${CLAUDE_PLUGIN_DATA:-${OCTOPUS_WORKSPACE:-${HOME}/.claude-octopus}}/session.json"
session='{}'
if [[ -f "$session_file" && ! -L "$session_file" ]]; then
    session="$(jq -c 'if type == "object" then . else {} end' "$session_file" 2>/dev/null || printf '{}')"
fi
mkdir -p "$(dirname "$file")"
chmod 700 "$(dirname "$file")" 2>/dev/null || true
tmp="$(mktemp "$(dirname "$file")/.handoff.XXXXXX")"
chmod 600 "$tmp" 2>/dev/null || true
jq -cn --arg project_id "$(octo_lifecycle_handoff_id "$project_root")" \
    --arg project_name "$(basename "$project_root")" \
    --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson session "$session" '
    def redact:
      tostring |
      gsub("(?i)(api[_-]?key|token|secret|password|authorization|bearer)[[:space:]]*[:=][[:space:]]*[^[:space:],;}]+"; "[REDACTED]") |
      gsub("(sk|pk|ghp|github_pat|xai|pplx|r8)[_-][A-Za-z0-9_-]+"; "[REDACTED]");
    {schema:1,generated_at:$generated_at,project_id:$project_id,project_name:$project_name,
     workflow:($session.workflow // "none"),phase:($session.current_phase // $session.phase // "none"),
     status:($session.status // "unknown"),autonomy:($session.autonomy // "supervised"),
     completed_phases:($session.completed_phases // 0),total_phases:($session.total_phases // 4),
     decisions:(($session.decisions // [])[:5] | map(redact)),
     blockers:(($session.blockers // [])[:5] | map(redact)),resume_command:"/octo:resume"}
  ' > "$tmp" || { rm -f "$tmp"; exit 1; }
mv -f "$tmp" "$file"
chmod 600 "$file" 2>/dev/null || true

if [[ "$json" == true ]]; then
    cat "$file"
else
    printf 'handoff exported: %s\n' "$file"
    jq -r '"  workflow: \(.workflow) / \(.phase)\n  status: \(.status)\n  resume: \(.resume_command)"' "$file"
fi
