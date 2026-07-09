#!/bin/bash
# tests/unit/test-release-sh-worktree-flow.sh
# Regression tests for the release.sh worktree/branch/remote flow (issue #603).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RELEASE_SH="$PROJECT_ROOT/scripts/release.sh"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "release.sh worktree/branch/remote flow"

test_remote_configurable() {
    test_case "remote is configurable via OCTO_RELEASE_REMOTE, not hardcoded to origin"

    if grep -q 'REMOTE="\${OCTO_RELEASE_REMOTE:-origin}"' "$RELEASE_SH" \
        && ! grep -qE 'git (pull|push) .*\borigin\b' "$RELEASE_SH"; then
        test_pass
    else
        test_fail "REMOTE var missing, or a git pull/push still hardcodes origin"
    fi
}

test_preflight_accepts_release_branch() {
    test_case "preflight accepts either main or the target release branch"

    if grep -A 4 'CURRENT_BRANCH="\$(git branch --show-current)"' "$RELEASE_SH" \
        | grep -q '"\$CURRENT_BRANCH" != "main" && "\$CURRENT_BRANCH" != "\$BRANCH"'; then
        test_pass
    else
        test_fail "preflight branch check no longer allows the worktree-flow release branch"
    fi
}

test_plugin_manifest_staged() {
    test_case "plugin-manifest.json is version-bumped and staged"

    if grep -q "plugin-manifest.json" "$RELEASE_SH" \
        && grep -q "^git add" "$RELEASE_SH" \
        && grep "^git add" "$RELEASE_SH" | grep -q "plugin-manifest.json"; then
        test_pass
    else
        test_fail "plugin-manifest.json is not bumped/staged by the version-update step"
    fi
}

test_post_merge_skips_checkout_on_release_branch() {
    test_case "post-merge step fetches instead of checking out main when already on the release branch"

    local merge_block
    merge_block=$(awk '/# --- 6\. Merge \+ Release/,/^gh release create/' "$RELEASE_SH")

    if echo "$merge_block" | grep -q 'ON_RELEASE_BRANCH" == "true"' \
        && echo "$merge_block" | grep -q 'git fetch --quiet "\$REMOTE" main' \
        && echo "$merge_block" | grep -q 'MERGE_SHA=\$(git rev-parse FETCH_HEAD)' \
        && ! echo "$merge_block" | grep -B2 'git checkout main' | grep -q 'ON_RELEASE_BRANCH" == "true"'; then
        test_pass
    else
        test_fail "post-merge step still unconditionally checks out main (breaks when main is checked out in another worktree)"
    fi
}

test_release_targets_merge_sha() {
    test_case "gh release create targets the resolved merge SHA"

    if grep -q -- '--target "\$MERGE_SHA"' "$RELEASE_SH"; then
        test_pass
    else
        test_fail "gh release create does not pin --target to MERGE_SHA"
    fi
}

# Functional: reproduce the exact worktree scenario from RELEASING.md §0
# (main checked out in one worktree, release/vX.Y.Z cut in another) and prove
# the fetch+FETCH_HEAD approach release.sh now uses succeeds there, while the
# git checkout main it replaced would fail.
test_fetch_head_approach_works_when_main_checked_out_elsewhere() {
    test_case "fetch+FETCH_HEAD resolves the merge SHA without touching main's checkout"

    local sandbox
    sandbox=$(mktemp -d)
    local origin="$sandbox/origin.git"
    local main_wt="$sandbox/main-worktree"
    local release_wt="$sandbox/release-worktree"

    (
        set -e
        git init --quiet --bare -b main "$origin"
        git clone --quiet "$origin" "$main_wt" 2>/dev/null
        cd "$main_wt"
        git config user.email test@example.com
        git config user.name "Test"
        git commit --quiet --allow-empty -m "init"
        git push --quiet origin main

        # Cut the release branch in a second worktree, as RELEASING.md §0
        # documents, while `main` stays checked out in $main_wt.
        git worktree add --quiet -b release/v9.99.0 "$release_wt" origin/main

        # Simulate the PR merge landing on main via a third clone (a real
        # merge would come from GitHub; a push works the same for this test).
        local merger="$sandbox/merger"
        git clone --quiet "$origin" "$merger"
        cd "$merger"
        git config user.email test@example.com
        git config user.name "Test"
        git commit --quiet --allow-empty -m "chore: release v9.99.0"
        git push --quiet origin main
    ) || { test_fail "sandbox setup failed"; rm -rf "$sandbox"; return; }

    local expected_sha
    expected_sha=$(git -C "$origin" rev-parse main)

    # This is the exact scenario the review comment flagged: main is
    # checked out in $main_wt, so a checkout in $release_wt must fail.
    if (cd "$release_wt" && git checkout main --quiet) 2>/dev/null; then
        test_fail "test invariant broken: git checkout main unexpectedly succeeded while main was checked out elsewhere"
        rm -rf "$sandbox"
        return
    fi

    local resolved_sha
    if ! resolved_sha=$(cd "$release_wt" && git fetch --quiet origin main && git rev-parse FETCH_HEAD); then
        test_fail "git fetch + rev-parse FETCH_HEAD failed from the release worktree"
        rm -rf "$sandbox"
        return
    fi

    rm -rf "$sandbox"

    if [[ "$resolved_sha" == "$expected_sha" ]]; then
        test_pass
    else
        test_fail "resolved SHA ($resolved_sha) != merged main tip ($expected_sha)"
    fi
}

test_remote_configurable
test_preflight_accepts_release_branch
test_plugin_manifest_staged
test_post_merge_skips_checkout_on_release_branch
test_release_targets_merge_sha
test_fetch_head_approach_works_when_main_checked_out_elsewhere

test_summary
