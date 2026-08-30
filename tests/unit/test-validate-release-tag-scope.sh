#!/usr/bin/env bash
# Feature branches may validate release contents without impersonating a release commit.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATE_RELEASE="$PROJECT_ROOT/scripts/validate-release.sh"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "validate-release tag mismatch scope"

load_tag_scope_helper() {
    local helper
    helper=$(awk '
        /^tag_mismatch_is_fatal\(\)/ { capture = 1 }
        capture { print }
        capture && /^}/ { exit }
    ' "$VALIDATE_RELEASE")
    [[ -n "$helper" ]] || return 1
    eval "$helper"
}

test_case "tag scope helper is available"
if load_tag_scope_helper; then
    test_pass
else
    test_fail "tag_mismatch_is_fatal helper not found"
fi

test_case "tag mismatch remains fatal on main"
CURRENT_BRANCH=main
if tag_mismatch_is_fatal; then
    test_pass
else
    test_fail "main could ignore a mismatched release tag"
fi

test_case "tag mismatch remains fatal on a release branch"
CURRENT_BRANCH=release/v10.1.0
if tag_mismatch_is_fatal; then
    test_pass
else
    test_fail "release branch could ignore a mismatched release tag"
fi

test_case "tag mismatch remains fatal on detached HEAD"
CURRENT_BRANCH=
if tag_mismatch_is_fatal; then
    test_pass
else
    test_fail "detached HEAD could ignore a mismatched release tag"
fi

test_case "ordinary feature branch treats an existing release tag as validation-only"
CURRENT_BRANCH=feat/simplify-install-setup-use
if ! tag_mismatch_is_fatal; then
    test_pass
else
    test_fail "feature branch incorrectly requires the existing release tag at HEAD"
fi

test_case "mismatched-tag branch is guarded by the tag scope helper"
tag_block=$(sed -n '/if git tag -l/,/^    fi$/p' "$VALIDATE_RELEASE")
if grep -q 'tag_mismatch_is_fatal' <<< "$tag_block"; then
    test_pass
else
    test_fail "tag mismatch handling does not consult tag scope"
fi

test_summary
