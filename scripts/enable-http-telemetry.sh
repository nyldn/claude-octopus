#!/usr/bin/env bash
# Enable HTTP-based telemetry hooks (Claude Code v2.1.63+)
# Replaces shell-based telemetry-webhook.sh with native HTTP POST hooks
# for faster execution and better sandboxing.
#
# Usage: enable-http-telemetry.sh <webhook-url> [--allow-plaintext-token]
#
# The bearer token is read from OCTOPUS_TELEMETRY_BEARER_TOKEN, never from argv:
# a token on the command line lands in shell history and is visible to every
# local process via `ps`. hooks/hooks.json is tracked by Git, so writing a live
# token into it stages a credential for commit — refused unless the caller opts
# in explicitly with --allow-plaintext-token.
#
# v8.41.0: Feature adoption — HTTP hooks for telemetry (planning doc #6)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"

WEBHOOK_URL=""
ALLOW_PLAINTEXT_TOKEN=false
LEGACY_TOKEN_ARG=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --allow-plaintext-token) ALLOW_PLAINTEXT_TOKEN=true ;;
        -*)
            echo "ERROR: unknown option '$1'" >&2
            exit 1
            ;;
        *)
            if [[ -z "$WEBHOOK_URL" ]]; then
                WEBHOOK_URL="$1"
            else
                LEGACY_TOKEN_ARG=true
            fi
            ;;
    esac
    shift
done

BEARER_TOKEN=${OCTOPUS_TELEMETRY_BEARER_TOKEN:-}

usage() {
    echo "Usage: enable-http-telemetry.sh <webhook-url> [--allow-plaintext-token]"
    echo ""
    echo "Replaces shell-based telemetry with native HTTP hooks (CC v2.1.63+)."
    echo "The webhook URL will receive POST requests with phase completion data."
    echo ""
    echo "Bearer token (optional) is read from the environment, not from argv:"
    echo "  read -rs OCTOPUS_TELEMETRY_BEARER_TOKEN && export OCTOPUS_TELEMETRY_BEARER_TOKEN"
    echo "  ./enable-http-telemetry.sh https://hooks.example.com/octopus"
    echo ""
    echo "Writing a live token into the tracked hooks/hooks.json needs"
    echo "--allow-plaintext-token, and you must keep that change out of commits."
}

if [[ -z "$WEBHOOK_URL" ]]; then
    usage
    exit 1
fi

if [[ "$LEGACY_TOKEN_ARG" == "true" ]]; then
    echo "ERROR: passing the bearer token as an argument is no longer supported." >&2
    echo "  It leaks into shell history and into 'ps' output for every local user." >&2
    echo "  Export OCTOPUS_TELEMETRY_BEARER_TOKEN instead." >&2
    exit 1
fi

# Refuse to stage a credential into a Git-tracked file unless told otherwise.
if [[ -n "$BEARER_TOKEN" && "$ALLOW_PLAINTEXT_TOKEN" != "true" ]]; then
    if git -C "$PLUGIN_ROOT" ls-files --error-unmatch "$HOOKS_JSON" >/dev/null 2>&1; then
        echo "ERROR: $HOOKS_JSON is tracked by Git; writing the bearer token into it" >&2
        echo "  would stage a live credential for commit." >&2
        echo "  Either run without OCTOPUS_TELEMETRY_BEARER_TOKEN set (no auth header)," >&2
        echo "  or re-run with --allow-plaintext-token and keep the change uncommitted." >&2
        exit 1
    fi
fi

if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required. Install with: brew install jq" >&2
    exit 1
fi

# Version guard: HTTP hooks require Claude Code v2.1.63+
CC_VERSION=""
CC_VERSION_OUTPUT=""
if command -v claude &>/dev/null; then
    CC_VERSION_OUTPUT=$(claude --version 2>&1 || true)
    CC_VERSION=$(printf '%s\n' "$CC_VERSION_OUTPUT" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    if [[ -z "$CC_VERSION" ]]; then
        echo "ERROR: HTTP hooks require a numeric Claude Code version (x.y.z)," >&2
        echo "  but 'claude --version' returned no parseable version: ${CC_VERSION_OUTPUT:-<empty>}" >&2
        exit 1
    fi
fi

if [[ -n "$CC_VERSION" ]]; then
    if [[ ! "$CC_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "ERROR: HTTP hooks require a numeric Claude Code version (x.y.z). Detected: v${CC_VERSION}" >&2
        exit 1
    fi
    # Compare all three components. An earlier version of this guard read only
    # minor/patch, so any future major (v3.0.0) was misread as "older than
    # 2.1.63" and rejected outright.
    CC_MAJOR=$(echo "$CC_VERSION" | cut -d. -f1)
    CC_MINOR=$(echo "$CC_VERSION" | cut -d. -f2)
    CC_PATCH=$(echo "$CC_VERSION" | cut -d. -f3)
    # Zero-padded decimal so 2.10.0 sorts above 2.9.0 in one integer compare.
    CC_NUM=$((10#$CC_MAJOR * 1000000 + 10#$CC_MINOR * 1000 + 10#$CC_PATCH))
    if (( CC_NUM < 2 * 1000000 + 1 * 1000 + 63 )); then
        echo "ERROR: HTTP hooks require Claude Code v2.1.63+. Detected: v${CC_VERSION}" >&2
        echo "Please update Claude Code first: claude update" >&2
        exit 1
    fi
else
    echo "WARNING: Could not detect Claude Code version. HTTP hooks require v2.1.63+." >&2
    echo "Proceeding anyway — verify your version supports HTTP hooks." >&2
fi

echo "Enabling HTTP telemetry hook..."
echo "  URL: $WEBHOOK_URL"
[[ -n "$BEARER_TOKEN" ]] && echo "  Auth: Bearer token configured"

# Build the HTTP hook entry
HTTP_HOOK=$(jq -n \
    --arg url "$WEBHOOK_URL" \
    --arg token "$BEARER_TOKEN" \
    '{
        "matcher": {
            "tool": "Bash",
            "pattern": "orchestrate\\.sh.*(probe|grasp|tangle|ink|embrace)"
        },
        "hooks": [
            {
                "type": "http",
                "url": $url,
                "timeout": 10,
                "headers": (if $token != "" then {"Authorization": ("Bearer " + $token)} else {} end)
            }
        ]
    }')

# Replace the shell-based telemetry entry in PostToolUse
TMP="${HOOKS_JSON}.tmp"
jq --argjson http_hook "$HTTP_HOOK" '
    .hooks.PostToolUse = [
        (.hooks.PostToolUse[] | select(.hooks[0].command // "" | test("telemetry") | not)),
        $http_hook
    ]
' "$HOOKS_JSON" > "$TMP" && mv "$TMP" "$HOOKS_JSON"

echo ""
echo "Done. HTTP telemetry hook enabled in hooks.json."
echo "The shell-based telemetry-webhook.sh is now bypassed (kept as fallback)."
echo ""
echo "To revert: git checkout hooks/hooks.json"
