#!/usr/bin/env bash
# Regression: echoed context may contain an earlier empty ## Output block.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/octo-review-extract.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
RESULT="$TMP_DIR/result.md"

cat > "$RESULT" <<'EOF'
# Prompt
Embedded prior result:
## Output
```
{"findings": []}
```
## Status: SUCCESS

## Output
```
{"findings":[{"title":"real final finding","severity":"normal"}]}
```
## Status: SUCCESS
EOF

source "$ROOT_DIR/scripts/lib/python-runtime.sh"
source "$ROOT_DIR/scripts/lib/review.sh"

findings=$(review_extract_findings_array "$RESULT")
[[ "$(printf '%s' "$findings" | jq -r '.[0].title')" == "real final finding" ]] || {
    echo "FAIL: earlier empty output masked the provider's final findings" >&2
    printf '%s\n' "$findings" >&2
    exit 1
}

echo "PASS: review extraction falls through to the final non-empty findings"
