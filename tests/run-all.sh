#!/usr/bin/env bash
# Compatibility wrapper for Makefile targets.
# Historical Makefile targets call: ./tests/run-all.sh <category> [extra flags]
#
# Supported categories:
#   smoke | unit | integration | root | live | symlink-sensitive | all
#
# Removed aliases, each of which ran an existing category under a second name:
#   e2e         -> ran `integration`, so `make test-all` executed the
#                  integration suites twice and the help text advertised a
#                  "15-30min" E2E run that was really the ~1min integration run.
#   performance -> ran `live`, which dispatches real `claude -p` sessions, but
#                  without the "real API calls" warning that `test-live` prints.
#   regression  -> ran `root`, now reachable under that honest name.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

category="${1:-all}"
shift || true

# Extra arguments are forwarded. They previously were not, so `--list` was
# silently discarded and a request to *list* a category ran it instead — which
# for `live` meant billing real provider calls to answer a question about which
# files exist.
case "$category" in
  smoke)       exec "$SCRIPT_DIR/run-all-tests.sh" --smoke "$@" ;;
  unit)        exec "$SCRIPT_DIR/run-all-tests.sh" --unit "$@" ;;
  integration) exec "$SCRIPT_DIR/run-all-tests.sh" --integration "$@" ;;
  root)        exec "$SCRIPT_DIR/run-all-tests.sh" --root "$@" ;;
  live)        exec "$SCRIPT_DIR/run-all-tests.sh" --live "$@" ;;
  symlink-sensitive) exec "$SCRIPT_DIR/run-all-tests.sh" --symlink-sensitive "$@" ;;
  all)         exec "$SCRIPT_DIR/run-all-tests.sh" --all "$@" ;;
  *)
    echo "Usage: $(basename "$0") {smoke|unit|integration|root|live|symlink-sensitive|all} [flags]" >&2
    exit 2
    ;;
esac
