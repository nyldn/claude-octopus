#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "Document renderer selection"
test_case "advertised skills, saved choices, templates and refusal behavior"
if python3 "$SCRIPT_DIR/test-document-renderer.py"; then test_pass; else test_fail "renderer selection regression"; fi
test_summary
