#!/usr/bin/env bash
# tests/unit/test-release-sh-worktree-flow.sh
# Regression tests for the release.sh worktree/branch/remote flow (issue #603).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RELEASE_SH="$PROJECT_ROOT/scripts/release.sh"
CI_LIB="$PROJECT_ROOT/scripts/lib/release-ci.sh"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
# shellcheck source=scripts/lib/release-ci.sh
source "$CI_LIB"

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

    local preflight_block
    preflight_block="$(grep -A 4 'CURRENT_BRANCH="\$(git branch --show-current)"' "$RELEASE_SH" || true)"

    if grep -q '"\$CURRENT_BRANCH" != "main" && "\$CURRENT_BRANCH" != "\$BRANCH"' <<< "$preflight_block"; then
        test_pass
    else
        test_fail "preflight branch check no longer allows the worktree-flow release branch"
    fi
}

test_plugin_manifest_staged() {
    test_case "plugin-manifest.json is version-bumped and staged"

    if grep -q "plugin-manifest.json" "$RELEASE_SH" \
        && grep -qE '^git add.*plugin-manifest\.json' "$RELEASE_SH"; then
        test_pass
    else
        test_fail "plugin-manifest.json is not bumped/staged by the version-update step"
    fi
}

test_post_merge_skips_checkout_on_release_branch() {
    test_case "post-merge step fetches instead of checking out main when already on the release branch"

    local merge_block checkout_context
    merge_block=$(awk '/# --- 6\. Merge \+ Release/,/^gh release create/' "$RELEASE_SH")
    checkout_context="$(grep -B2 'git checkout main' <<< "$merge_block" || true)"

    if grep -q 'ON_RELEASE_BRANCH" == "true"' <<< "$merge_block" \
        && grep -q 'git fetch --quiet "\$REMOTE" main' <<< "$merge_block" \
        && grep -q -- '--json state,mergeCommit' <<< "$merge_block" \
        && ! grep -q 'ON_RELEASE_BRANCH" == "true"' <<< "$checkout_context"; then
        test_pass
    else
        test_fail "post-merge step still unconditionally checks out main (breaks when main is checked out in another worktree)"
    fi
}

test_release_tags_merge_sha() {
    test_case "release creates and pushes an annotated tag on the resolved merge SHA"

    local merge_block
    merge_block=$(awk '/# --- 6\. Merge \+ Release/,/^# --- 7\. Sync shared marketplace/' "$RELEASE_SH")

    if grep -q -- '--json state,mergeCommit' <<< "$merge_block" \
        && grep -q 'mergeCommit\.oid // empty' <<< "$merge_block" \
        && grep -q 'MERGE_SHA" =~ \^\[0-9a-fA-F\]' <<< "$merge_block" \
        && grep -q 'git merge-base --is-ancestor "\$MERGE_SHA" FETCH_HEAD' <<< "$merge_block" \
        && grep -q 'git tag -a "\$TAG_NAME" "\$MERGE_SHA"' <<< "$merge_block" \
        && grep -q 'git push --quiet "\$REMOTE" "\$TAG_NAME"' <<< "$merge_block" \
        && grep -q -- '--verify-tag' <<< "$merge_block"; then
        test_pass
    else
        test_fail "release does not push and verify an annotated tag on MERGE_SHA"
    fi
}

test_release_uses_squash_merge() {
    test_case "release PR follows the repository squash-merge convention"

    local merge_commands
    merge_commands=$(grep -E '^[[:space:]]*gh pr merge "\$PR_NUM"' "$RELEASE_SH" || true)

    if grep -q -- '--squash' <<< "$merge_commands" \
        && ! grep -q -- '--merge' <<< "$merge_commands" \
        && ! grep -q -- '--rebase' <<< "$merge_commands"; then
        test_pass
    else
        test_fail "release.sh merge commands must use --squash exclusively"
    fi
}

test_release_ci_timeout_covers_macos() {
    test_case "release CI timeout defaults to 900, accepts overrides, and rejects invalid values"

    local default_trace override_trace invalid_output
    default_trace=$(OCTO_RELEASE_REMOTE=__missing_release_test_remote__ \
        bash -x "$RELEASE_SH" 9.99.0 "test release" 2>&1 || true)
    override_trace=$(OCTO_RELEASE_REMOTE=__missing_release_test_remote__ \
        OCTO_RELEASE_CI_TIMEOUT_SECONDS=1200 \
        bash -x "$RELEASE_SH" 9.99.0 "test release" 2>&1 || true)

    if invalid_output=$(OCTO_RELEASE_CI_TIMEOUT_SECONDS=invalid \
        bash "$RELEASE_SH" 9.99.0 "test release" 2>&1); then
        test_fail "release.sh accepted an invalid CI timeout"
        return
    fi

    if grep -q '^+ CI_TIMEOUT_SECONDS=900$' <<< "$default_trace" \
        && grep -q '^+ CI_TIMEOUT_SECONDS=1200$' <<< "$override_trace" \
        && grep -q 'must be a positive integer' <<< "$invalid_output"; then
        test_pass
    else
        test_fail "release.sh timeout default, override, or validation behavior is incorrect"
    fi
}

test_release_requires_clean_review_state() {
    test_case "release requires explicit approval and paginates every review thread"

    local unresolved
    gh() {
        if [[ " $* " == *" cursor=NEXT_PAGE "* ]]; then
            printf '%s\n' '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":false}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}'
        else
            printf '%s\n' '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":true},{"isResolved":false}],"pageInfo":{"hasNextPage":true,"endCursor":"NEXT_PAGE"}}}}}}'
        fi
    }
    unresolved=$(octo_release_unresolved_review_threads owner repo 687)
    unset -f gh

    if octo_release_review_gate APPROVED 0 \
        && ! octo_release_review_gate "" 0 \
        && ! octo_release_review_gate REVIEW_REQUIRED 0 \
        && ! octo_release_review_gate CHANGES_REQUESTED 0 \
        && ! octo_release_review_gate APPROVED 1 \
        && [[ "$unresolved" == "2" ]]; then
        test_pass
    else
        test_fail "release review gate accepted an unapproved or unresolved state"
    fi
}

test_release_verifies_main_before_tag() {
    test_case "release verifies the post-squash main commit before tagging"

    local merge_block watch_line tag_line
    merge_block=$(awk '/# --- 6\. Merge \+ Release/,/^# --- 7\. Sync shared marketplace/' "$RELEASE_SH")
    watch_line=$(grep -n 'gh run watch "\$MAIN_RUN_ID"' <<< "$merge_block" | cut -d: -f1)
    tag_line=$(grep -n 'git tag -a "\$TAG_NAME"' <<< "$merge_block" | cut -d: -f1)

    if grep -q -- '--workflow "Test Suite"' <<< "$merge_block" \
        && grep -q 'headSha' <<< "$merge_block" \
        && grep -q 'MERGE_SHA' <<< "$merge_block" \
        && grep -q 'octo_release_run_with_timeout "\$CI_TIMEOUT_SECONDS"' <<< "$merge_block" \
        && [[ -n "$watch_line" && -n "$tag_line" && "$watch_line" -lt "$tag_line" ]]; then
        test_pass
    else
        test_fail "release.sh does not verify the exact main merge SHA before tagging"
    fi
}

test_release_timeout_is_bounded() {
    test_case "release timeout helper terminates a stuck main-run watch"

    local started elapsed
    started=$(date +%s)
    if octo_release_run_with_timeout 1 sleep 5 >/dev/null 2>&1; then
        test_fail "timeout helper accepted a command that exceeded its budget"
        return
    fi
    elapsed=$(( $(date +%s) - started ))

    if [[ "$elapsed" -lt 5 ]] && octo_release_run_with_timeout 2 true; then
        test_pass
    else
        test_fail "timeout helper did not bound the command or rejected a fast command"
    fi
}

# Functional: reproduce the exact worktree scenario from RELEASING.md §0
# (main checked out in one worktree, release/vX.Y.Z cut in another) and prove
# the fetch+FETCH_HEAD approach release.sh now uses succeeds there, while the
# git checkout main it replaced would fail.
test_fetch_head_approach_works_when_main_checked_out_elsewhere() {
    test_case "fetch+FETCH_HEAD resolves the merge SHA without touching main's checkout"

    local sandbox="/tmp/octopus-tests-$$-worktree"
    rm -rf "$sandbox"
    mkdir -p "$sandbox"
    trap 'rm -rf "$sandbox"' RETURN

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
    ) || { test_fail "sandbox setup failed"; return; }

    local expected_sha
    expected_sha=$(git -C "$origin" rev-parse main)

    # This is the exact scenario the review comment flagged: main is
    # checked out in $main_wt, so a checkout in $release_wt must fail.
    if (cd "$release_wt" && git checkout main --quiet) 2>/dev/null; then
        test_fail "test invariant broken: git checkout main unexpectedly succeeded while main was checked out elsewhere"
        return
    fi

    local resolved_sha
    if ! resolved_sha=$(cd "$release_wt" && git fetch --quiet origin main && git rev-parse FETCH_HEAD); then
        test_fail "git fetch + rev-parse FETCH_HEAD failed from the release worktree"
        return
    fi

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
test_release_tags_merge_sha
test_release_uses_squash_merge
test_release_ci_timeout_covers_macos
test_release_requires_clean_review_state
test_release_verifies_main_before_tag
test_release_timeout_is_bounded
test_fetch_head_approach_works_when_main_checked_out_elsewhere

test_summary
