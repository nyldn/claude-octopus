#!/usr/bin/env bash
# Constrain judge seats before using the shared synchronous dispatch primitive.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ $# -ne 5 ]]; then
    printf '%s\n' 'Usage: refinement-judge.sh PROVIDER TIMEOUT PROMPT_FILE TASK_ID OUTPUT_DIR' >&2
    exit 2
fi
provider="$1"
executor="${provider%%:*}"
case "$executor" in
    codex|codex-standard|codex-max|codex-mini|codex-general|codex-spark|codex-reasoning|codex-large-context|claude|claude-opus|claude-opus-fast|claude-sonnet) ;;
    *) printf 'ERROR: no enforced read-only refinement boundary for %s\n' "$executor" >&2; exit 2 ;;
esac
if [[ ! "$2" =~ ^[0-9]{1,4}$ ]] || [[ "$((10#$2))" -lt 1 || "$((10#$2))" -gt 3600 ]]; then
    printf '%s\n' 'ERROR: judge timeout must be 1..3600 seconds' >&2
    exit 2
fi
if [[ ! -f "$3" || ! -r "$3" || ! -s "$3" || -z "$4" || ! -d "$5" || ! -w "$5" ]]; then
    printf '%s\n' 'ERROR: readable nonempty prompt, task ID, and writable output directory required' >&2
    exit 2
fi
# --tools limits the available built-in tools even if routing selects a write
# role. No ambient MCP servers may supply another route to shell or file writes.
if [[ "${OCTOPUS_CLAUDE_BIN:-}" == *--mcp-config* ]]; then
    printf '%s\n' 'ERROR: refinement rejects a Claude launcher with explicit MCP configuration' >&2
    exit 2
fi
claude_bin="${OCTOPUS_CLAUDE_BIN:-claude} --tools Read,Glob,Grep --strict-mcp-config"
exec env OCTOPUS_REFINEMENT_JUDGE=true OCTOPUS_AUTH_RETRIES=0 OCTOPUS_CODEX_SANDBOX=read-only \
    CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1 OCTOPUS_CLAUDE_ADVISOR=off \
    OCTOPUS_AGENT_TIMEOUT="$((10#$2))" \
    OCTOPUS_CLAUDE_BIN="$claude_bin" \
    "$SCRIPT_DIR/orchestrate.sh" --timeout "$((10#$2))" \
    probe-single "$provider" --perspective-file "$3" "$4" --output-dir "$5"
