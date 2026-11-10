#!/usr/bin/env bash
# Compatibility entry point for the skill builder used by make sync.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/gen-skill-docs.sh [--dry-run|--check]

Generate portable skills from their authored entries. Use make sync to refresh
all generated plugin artifacts. --dry-run and --check verify without writing.

GEN_SKILL_DOCS_ROOT selects an isolated plugin root, including its scripts/.
EOF
}

check=false
if [[ $# -gt 1 ]]; then
    usage >&2
    exit 64
fi
case "${1:-}" in
    '') ;;
    --dry-run|--check) check=true ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 64 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${GEN_SKILL_DOCS_ROOT:-$(dirname "$SCRIPT_DIR")}"
builder="$PLUGIN_ROOT/scripts/build-codex-skills.sh"
if [[ ! -x "$builder" ]]; then
    printf 'Missing skill builder: %s\n' "$builder" >&2
    exit 1
fi

if $check; then
    exec "$builder" --check
fi
exec "$builder"
