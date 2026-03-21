#!/usr/bin/env bash
# Dispatcher that checks hook profile before executing the actual hook
# Usage: run-with-profile.sh <hook-name> <actual-hook-script> [args...]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/hook-profile.sh"

hook_name="$1"
shift
hook_script="$1"
shift

if ! is_hook_enabled "$hook_name"; then
  # Pass through stdin to stdout unchanged (graceful skip)
  cat
  exit 0
fi

# Execute the actual hook
exec bash "$hook_script" "$@"
