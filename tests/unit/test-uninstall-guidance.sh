#!/usr/bin/env bash
# Public uninstall docs must separate plugin removal from retained user data.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Uninstall guidance"

README="$PROJECT_ROOT/README.md"
DOCS_INDEX="$PROJECT_ROOT/docs/README.md"
TROUBLESHOOTING="$PROJECT_ROOT/docs/TROUBLESHOOTING.md"
PUBLIC_DOCS=("$README" "$DOCS_INDEX" "$TROUBLESHOOTING")

test_case "public docs make no clean-uninstall or no-residue claim"
if ! grep -Eiq 'clean uninstall|uninstalls cleanly|no residual config changes' "${PUBLIC_DOCS[@]}"; then
    test_pass
else
    test_fail "public docs still imply plugin removal deletes retained data"
fi

test_case "README separates plugin uninstall from retained data"
if grep -q 'claude plugin uninstall octo' "$README" &&
   grep -qi 'does not delete' "$README" &&
   grep -q '~/.claude-octopus/results/' "$README" &&
   grep -q '~/.claude-octopus/logs/' "$README" &&
   grep -q '~/.claude-octopus/' "$README" &&
   grep -q '`\.octo/`' "$README"; then
    test_pass
else
    test_fail "README does not state what uninstall preserves"
fi

test_case "troubleshooting gives separate preserve and review procedures"
if grep -q '^## Uninstall the plugin and keep local data$' "$TROUBLESHOOTING" &&
   grep -q '^## Review retained data before manual removal$' "$TROUBLESHOOTING" &&
   grep -qi 'exact paths' "$TROUBLESHOOTING" &&
   grep -qi 'confirmation' "$TROUBLESHOOTING" &&
   grep -qi 'archive' "$TROUBLESHOOTING"; then
    test_pass
else
    test_fail "troubleshooting does not distinguish uninstall from confirmation-gated cleanup"
fi

test_case "retained-state inventory is read-only"
if grep -q 'du -sh "${HOME}/.claude-octopus"' "$TROUBLESHOOTING" &&
   grep -q "find . -maxdepth 3 -type d -name '.octo' -prune -print" "$TROUBLESHOOTING" &&
   ! grep -Eq 'rm -r[fF].*(\.claude-octopus|\.octo)|find .* -delete' "$TROUBLESHOOTING"; then
    test_pass
else
    test_fail "retained-state guidance is missing a read-only inventory or includes automatic deletion"
fi

test_case "docs index routes operators to uninstall guidance"
if grep -q '\[TROUBLESHOOTING.md\](./TROUBLESHOOTING.md).*uninstall' "$DOCS_INDEX"; then
    test_pass
else
    test_fail "docs index does not expose uninstall and retained-data guidance"
fi

test_case "documentation defers an automatic purge command"
if grep -qi 'does not provide an automatic purge command' "$TROUBLESHOOTING"; then
    test_pass
else
    test_fail "docs do not state that retained-data deletion remains manual"
fi

test_summary
