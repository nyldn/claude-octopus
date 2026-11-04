#!/usr/bin/env bash
# Table-only quote decoding must stay within a rendered GFM cell.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT/scripts/lib/council.sh"
test_suite "Council table cell quote boundaries"
ROOT="$(mktemp -d "$TEST_TMP_DIR/table-cells.XXXXXX")"
mkdir -p "$ROOT/src"
printf 'export const pattern = /alpha|beta/;\n' > "$ROOT/src/regex-3125.ts"
printf 'export const pattern = /alpha|beta|gamma/;\n' > "$ROOT/src/cell-boundary.ts"
printf 'export const pattern = /alpha| beta/;\n' > "$ROOT/src/multiline-cell.ts"
# Definitive negative grounding requires a readable complete diff.
git -C "$ROOT" init -q
git -C "$ROOT" add src
git -C "$ROOT" -c user.name=Test -c user.email=test@example.invalid \
    -c core.hooksPath=/dev/null commit -qm fixture
unset OCTOPUS_COUNCIL_DIFF_BASE
_resp() { local f; f="$(mktemp "$TEST_TMP_DIR/response.XXXXXX")"; printf '%s\n' "$1" > "$f"; printf '%s\n' "$f"; }
_report() { council_response_quote_verification_json "$1" "$ROOT"; }

# Table escaping is valid only inside one rendered cell, not across cells,
# across rows, or in excess cells discarded by the renderer.
printf 'export const pattern = /alpha|beta|gamma/;\n' > "$ROOT/src/cell-boundary.ts"
test_case "#1224: a code span crossing an unescaped table separator stays literal"
cross_cell="$(_resp '| File | Code | Note |
|---|---|---|
| src/cell-boundary.ts:1 | `export const pattern = /alpha\|beta|gamma/;` |
VERDICT: APPROVE')"
r="$(_report "$cross_cell")"
if jq -e '.quotes_checked == 1 and .quotes_verified == 0 and .fabricated == true' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "#1224: an ignored excess table cell cannot enable pipe decoding"
excess_cell="$(_resp '| File | Note |
|---|---|
| src/regex-3125.ts:1 | note | `export const pattern = /alpha\|beta/;` |
VERDICT: APPROVE')"
r="$(_report "$excess_cell")"
if jq -e '.quotes_checked == 1 and .quotes_verified == 0 and .fabricated == true' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

printf 'export const pattern = /alpha| beta/;\n' > "$ROOT/src/multiline-cell.ts"
test_case "#1224: a code span crossing table rows cannot enable pipe decoding"
cross_row="$(_resp '| File | Code |
|---|---|
src/multiline-cell.ts:1 | `export const pattern = /alpha\|
beta/;` | note
VERDICT: APPROVE')"
r="$(_report "$cross_row")"
if jq -e '.quotes_checked == 1 and .quotes_verified == 0 and .fabricated == true' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "#1224: all pipes escaped inside a single table cell still verify"
single_cell="$(_resp '| File | Code |
|---|---|
| src/cell-boundary.ts:1 | `export const pattern = /alpha\|beta\|gamma/;` |
VERDICT: APPROVE')"
r="$(_report "$single_cell")"
if jq -e '.quotes_checked == 1 and .quotes_verified == 1 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

for wrapper in comment div script cdata instruction declaration; do
    case "$wrapper" in
        comment) opening='<!--'; closing='-->' ;;
        div) opening='<div>'; closing='</div>' ;;
        script) opening='<script>'; closing='</script>' ;;
        cdata) opening='<![CDATA['; closing=']]>' ;;
        instruction) opening='<?target'; closing='?>' ;;
        declaration) opening='<!DOCTYPE'; closing='>' ;;
    esac
    test_case "#1224: table-shaped text in an HTML $wrapper block stays literal"
    html_table="$(_resp "$opening
| File | Code |
|---|---|
| src/regex-3125.ts:1 | \`export const pattern = /alpha\\|beta/;\` |
$closing
VERDICT: APPROVE")"
    r="$(_report "$html_table")"
    if jq -e '.quotes_checked == 1 and .quotes_verified == 0 and .fabricated == true' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi
done

test_case "#1224: a table after an HTML comment terminator still decodes"
closed_html="$(_resp '<!-- comment -->
| File | Code |
|---|---|
| src/regex-3125.ts:1 | `export const pattern = /alpha\|beta/;` |
VERDICT: APPROVE')"
r="$(_report "$closed_html")"
if jq -e '.quotes_checked == 1 and .quotes_verified == 1 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "#1224: a table after a blank-line-terminated HTML block still decodes"
closed_html="$(_resp '<div>raw HTML</div>

| File | Code |
|---|---|
| src/regex-3125.ts:1 | `export const pattern = /alpha\|beta/;` |
VERDICT: APPROVE')"
r="$(_report "$closed_html")"
if jq -e '.quotes_checked == 1 and .quotes_verified == 1 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "#1224: entity-encoded delimiters cannot create a table"
entity_table="$(_resp '| File | Code |
&#124;---&#124;---&#124;
| src/regex-3125.ts:1 | `export const pattern = /alpha\|beta/;` |
VERDICT: APPROVE')"
r="$(_report "$entity_table")"
if jq -e '.quotes_checked == 1 and .quotes_verified == 0 and .fabricated == true' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "#1224: a pipe-free single-column table header is valid"
single_column="$(_resp 'Code
|---|
| src/regex-3125.ts:1 reads `export const pattern = /alpha\|beta/;` |
VERDICT: APPROVE')"
r="$(_report "$single_column")"
if jq -e '.quotes_checked == 1 and .quotes_verified == 1 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "#1224: a nonempty pipe-free body row does not end a table"
pipe_free_body="$(_resp '| File | Code |
|---|---|
continued
| src/regex-3125.ts:1 | `export const pattern = /alpha\|beta/;` |
VERDICT: APPROVE')"
r="$(_report "$pipe_free_body")"
if jq -e '.quotes_checked == 1 and .quotes_verified == 1 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "#1224: entity decoding preserves offsets before a real table quote"
entity_offsets="$(_resp 'Pr\u00e9face &amp; &#x1F419;

| File | Code |
|---|---|
| &amp; src/regex-3125.ts:1 | `export const pattern = /alpha\|beta/;` |
VERDICT: APPROVE')"
r="$(_report "$entity_offsets")"
if jq -e '.quotes_checked == 1 and .quotes_verified == 1 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_case "#1224: an entity pipe inside a real cell does not split it"
entity_cell="$(_resp '| File | Code |
|---|---|
| src/regex-3125.ts:1 | &#124; `export const pattern = /alpha\|beta/;` |
VERDICT: APPROVE')"
r="$(_report "$entity_cell")"
if jq -e '.quotes_checked == 1 and .quotes_verified == 1 and .fabricated == false' <<< "$r" >/dev/null; then test_pass; else test_fail "report: $r"; fi

test_summary
