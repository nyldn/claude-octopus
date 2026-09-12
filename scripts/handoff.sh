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

[[ ! -L "$file" && ( ! -e "$file" || -f "$file" ) ]] || { printf 'output must be a regular file: %s\n' "$file" >&2; exit 1; }
session_file="${CLAUDE_PLUGIN_DATA:-${CLAUDE_OCTOPUS_WORKSPACE:-${HOME}/.claude-octopus}}/session.json"
session='{}'
if [[ -f "$session_file" && ! -L "$session_file" ]]; then
    session="$(jq -c 'if type == "object" then . else {} end' "$session_file" 2>/dev/null)" || {
        printf 'Unable to read handoff session JSON\n' >&2; exit 1;
    }
fi
state_file="$(OCTOPUS_STATE_PROJECT_ROOT="$project_root" bash "$SCRIPT_DIR/state-manager.sh" state_path)"
project_state='{}'
if [[ -f "$state_file" && ! -L "$state_file" ]]; then
    project_state="$(jq -c 'if type == "object" then . else {} end' "$state_file" 2>/dev/null)" || {
        printf 'Unable to read handoff project state JSON\n' >&2; exit 1;
    }
fi
umask 077
mkdir -p "$(dirname "$file")"
tmp="$(mktemp "$(dirname "$file")/.handoff.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Redact decoded strings before serialization. Text sanitizers can consume JSON
# delimiters; only the completed, redacted object may reach the temporary file.
jq -cn --arg project_id "$(octo_lifecycle_handoff_id "$project_root")" \
    --arg project_name "$(basename "$project_root")" \
    --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson session "$session" --argjson state "$project_state" '
    def redact:
      if test("(?i)(api[_-]?key|token|secret|password|authorization|bearer)") or
         test("(AKIA|ASIA)[A-Z0-9]{16}") or
         test("eyJ[A-Za-z0-9_-]*\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]*") or
         test("-----BEGIN[A-Z ]*PRIVATE KEY-----") or
         test("[A-Za-z][A-Za-z0-9+.-]*://[^\\s/@]+@")
      then "[REDACTED]" else . end |
      gsub("(sk|pk|ghp|github_pat|xai|pplx|r8)[_-][A-Za-z0-9_-]+"; "[REDACTED]");
    def summary($default): if type == "string" then redact | .[:512] else $default end;
    def count($default): if type == "number" and . >= 0 and . == floor then . else $default end;
    def notes: if type == "array" then [.[:5][] | select(type == "string") | redact | .[:512]] else [] end;
    {schema:1,generated_at:$generated_at,project_id:$project_id,project_name:($project_name | redact),
     workflow:(($state.current_workflow // $session.workflow) | summary("none")),phase:(($state.current_phase // $session.current_phase // $session.phase) | summary("none")),
     status:($session.status | summary("unknown")),autonomy:($session.autonomy | summary("supervised")),
     completed_phases:($session.completed_phases | count(0)),total_phases:($session.total_phases | count(4)),
     decisions:(if ($state.decisions | type) == "array" then [$state.decisions[] | select(type == "object") | .decision] else $session.decisions end | notes),
     blockers:(if ($state.blockers | type) == "array" then [$state.blockers[] | select(type == "object" and .status == "active") | .description] else $session.blockers end | notes)}
  ' > "$tmp" || { rm -f "$tmp"; exit 1; }
mv -f "$tmp" "$file"
chmod 600 "$file" 2>/dev/null || true

if [[ "$json" == true ]]; then
    cat "$file"
else
    printf 'handoff exported: %s\n' "$file"
    jq -r '"  workflow: \(.workflow) / \(.phase)\n  status: \(.status)"' "$file"
fi
