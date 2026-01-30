#!/usr/bin/env bash
# Compatibility wrapper for Makefile targets.
# Historical Makefile targets call: ./tests/run-all.sh <category>
#
# Supported categories:
#   unit | integration | e2e | live | performance | regression | all | smoke

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

category="${1:-all}"

case "$category" in
  smoke)       exec "$SCRIPT_DIR/run-all-tests.sh" --smoke ;;
  unit)        exec "$SCRIPT_DIR/run-all-tests.sh" --unit ;;
  integration) exec "$SCRIPT_DIR/run-all-tests.sh" --integration ;;
  e2e)         exec "$SCRIPT_DIR/run-all-tests.sh" --e2e ;;
  live)        exec "$SCRIPT_DIR/run-all-tests.sh" --live ;;
  performance) exec "$SCRIPT_DIR/run-all-tests.sh" --performance ;;
  regression)  exec "$SCRIPT_DIR/run-all-tests.sh" --regression ;;
  all)         exec "$SCRIPT_DIR/run-all-tests.sh" --all ;;
  *)
    echo "Usage: $(basename "$0") {smoke|unit|integration|e2e|live|performance|regression|all}" >&2
    exit 2
    ;;
esac

