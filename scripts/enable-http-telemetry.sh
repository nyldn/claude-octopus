#!/usr/bin/env bash
# Enable HTTP-based telemetry hooks (Claude Code v2.1.63+)
# Replaces shell-based telemetry-webhook.sh with native HTTP POST hooks
# for faster execution and better sandboxing.
#
# Usage: enable-http-telemetry.sh <webhook-url> [bearer-token]
#
# v8.41.0: Feature adoption — HTTP hooks for telemetry (planning doc #6)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"

WEBHOOK_URL="${1:-}"
BEARER_TOKEN="${2:-}"

if [[ -z "$WEBHOOK_URL" ]]; then
    echo "Usage: enable-http-telemetry.sh <webhook-url> [bearer-token]"
    echo ""
    echo "Replaces shell-based telemetry with native HTTP hooks (CC v2.1.63+)."
    echo "The webhook URL will receive POST requests with phase completion data."
    echo ""
    echo "Example:"
    echo "  ./enable-http-telemetry.sh https://hooks.example.com/octopus my-secret-token"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required. Install with: brew install jq" >&2
    exit 1
fi

# Version guard: HTTP hooks require Claude Code v2.1.63+
CC_VERSION=""
if command -v claude &>/dev/null; then
    CC_VERSION=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
fi

if [[ -n "$CC_VERSION" ]]; then
    CC_MINOR=$(echo "$CC_VERSION" | cut -d. -f2)
    CC_PATCH=$(echo "$CC_VERSION" | cut -d. -f3)
    if [[ "$CC_MINOR" -lt 1 ]] || { [[ "$CC_MINOR" -eq 1 ]] && [[ "$CC_PATCH" -lt 63 ]]; }; then
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
