#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "OpenCode CLI compatibility"
test_case "v1/v2 dispatch, discovery, live login and failure contracts"
if python3 "$SCRIPT_DIR/test-opencode-v2.py"; then test_pass; else test_fail "OpenCode compatibility regression"; fi
test_summary
