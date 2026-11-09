#!/usr/bin/env bash
# Inert fixtures for the workflow efficiency changes.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Command and workflow efficiency"
test_case "completion, retries, metadata, usage, context, and convergence behavior"
if python3 "$SCRIPT_DIR/test-command-workflow-efficiency.py"; then
    test_pass
else
    test_fail "workflow efficiency regressions failed"
fi
test_summary
