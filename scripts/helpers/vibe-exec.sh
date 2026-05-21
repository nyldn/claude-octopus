#!/usr/bin/env bash
# Vibe stdin→argv shim. spawn.sh pipes prompts via stdin (Issue #173); vibe's
# programmatic mode (`-p`) only reads the prompt as an argv argument and errors
# with "No prompt provided" if stdin is used. This helper bridges the gap.
#
# Usage: vibe-exec.sh [vibe flags...]
#        prompt content arrives on stdin; -p is appended automatically.

set -euo pipefail

prompt=""
if [[ ! -t 0 ]]; then
    prompt=$(cat)
fi

if [[ -z "${prompt//[[:space:]]/}" ]]; then
    echo "vibe-exec: no prompt provided on stdin" >&2
    exit 64
fi

exec vibe "$@" -p "$prompt"
