

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers/test-framework.sh"
test_suite "Version Consistency"

set +o pipefail  # restore: original did not use pipefail
test_summary
