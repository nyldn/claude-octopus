#!/usr/bin/env bash
# Internal project writes; discovery-handoff.py owns the lock and rollback journal.
set -euo pipefail
SYNTHESIS_FILE="${1:?verified synthesis snapshot required}"
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
SUMMARY_DIR=".octo/phases"
SUMMARY_FILE="$SUMMARY_DIR/phase-1-summary.md"
[[ ! -L .octo && ! -L "$SUMMARY_DIR" && ! -L "$SUMMARY_FILE" && ! -d "$SUMMARY_FILE" && ! -L .octo/STATE.md ]] || exit 1
mkdir -p "$SUMMARY_DIR"
SUMMARY_TEMP=$(mktemp "${SUMMARY_FILE}.tmp.XXXXXX")
trap 'rm -f "$SUMMARY_TEMP"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
cp "$SYNTHESIS_FILE" "$SUMMARY_TEMP"
mv "$SUMMARY_TEMP" "$SUMMARY_FILE"
"$PLUGIN_ROOT/scripts/octo-state.sh" update_state --status complete --history "Discover phase completed"
