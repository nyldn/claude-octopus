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
        && grep -q -- '--json state,headRefOid,mergeCommit' <<< "$merge_block" \
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

    if grep -q -- '--json state,headRefOid,mergeCommit' <<< "$merge_block" \
        && grep -q 'mergeCommit\.oid // ""' <<< "$merge_block" \
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

test_release_merge_pins_reviewed_head() {
    test_case "release merge is pinned to the reviewed PR head"

    local release_flow pin_line ci_line compare_line merge_line
    release_flow=$(awk '/# --- 4\. Create PR/,/if ! MERGE_SHA=/' "$RELEASE_SH")
    pin_line=$(grep -n 'PR_HEAD_SHA=.*headRefOid' <<< "$release_flow" | head -1 | cut -d: -f1)
    ci_line=$(grep -n '5/8 Waiting for CI' <<< "$release_flow" | head -1 | cut -d: -f1)
    compare_line=$(grep -n 'CURRENT_PR_HEAD_SHA.*PR_HEAD_SHA' <<< "$release_flow" | head -1 | cut -d: -f1)
    merge_line=$(grep -n -- '--match-head-commit "\$PR_HEAD_SHA"' <<< "$release_flow" | head -1 | cut -d: -f1)

    if [[ "$pin_line" =~ ^[0-9]+$ && "$ci_line" =~ ^[0-9]+$ &&
          "$compare_line" =~ ^[0-9]+$ && "$merge_line" =~ ^[0-9]+$ ]] &&
       [[ "$pin_line" -lt "$ci_line" && "$ci_line" -lt "$compare_line" &&
          "$compare_line" -lt "$merge_line" ]]; then
        test_pass
    else
        test_fail "release.sh does not pin the PR head before CI, recheck it, and bind the merge"
    fi
}

test_release_rejects_concurrently_changed_merged_head() {
    test_case "release rejects a merged PR whose head changed after review"

    if octo_release_merge_matches_reviewed_head $'MERGED\tbefore' before \
        && ! octo_release_merge_matches_reviewed_head $'MERGED\tafter' before \
        && ! octo_release_merge_matches_reviewed_head $'OPEN\tbefore' before \
        && ! octo_release_merge_matches_reviewed_head 'MERGED' before; then
        test_pass
    else
        test_fail "release merge validation accepted a changed, open, or malformed PR snapshot"
    fi
}

test_release_notes_use_private_file() {
    test_case "release notes are passed through a private file, never inline"

    local merge_block
    merge_block=$(awk '/# --- 6\. Merge \+ Release/,/^# --- 7\. Sync shared marketplace/' "$RELEASE_SH")

    if grep -q 'umask 077.*mktemp' <<< "$merge_block" \
        && grep -q "trap 'release_notes_interrupted 130' INT" <<< "$merge_block" \
        && grep -q "trap 'release_notes_interrupted 143' TERM" <<< "$merge_block" \
        && grep -q "trap - EXIT INT TERM" <<< "$merge_block" \
        && grep -q -- '--notes-file "\$RELEASE_NOTES_FILE"' <<< "$merge_block" \
        && ! grep -q -- '--notes "' <<< "$merge_block"; then
        test_pass
    else
        test_fail "release.sh still passes generated release notes inline or without a private file"
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

# Exercise aggregate review, thread, and pinned-head approval requirements.
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

    if octo_release_review_gate APPROVED 0 true \
        && ! octo_release_review_gate "" 0 true \
        && ! octo_release_review_gate REVIEW_REQUIRED 0 true \
        && ! octo_release_review_gate CHANGES_REQUESTED 0 true \
        && ! octo_release_review_gate APPROVED 1 true \
        && ! octo_release_review_gate APPROVED 0 false \
        && ! octo_release_review_gate APPROVED 0 \
        && [[ "$unresolved" == "2" ]] \
        && grep -q 'CURRENT_HEAD_APPROVED=$(octo_release_current_head_approval' "$RELEASE_SH" \
        && grep -Fq 'octo_release_review_gate "$REVIEW_DECISION" "$UNRESOLVED_THREADS" "$CURRENT_HEAD_APPROVED"' "$RELEASE_SH"; then
        test_pass
    else
        test_fail "release review gate accepted an unapproved or unresolved state"
    fi
}

# Check every review page using inert current, stale, and malformed API records.
test_release_requires_approval_on_expected_head() {
    test_case "release approval requires the expected commit and validates every review page"

    if python3 - "$CI_LIB" "$TEST_TMP_DIR" <<'APPROVALS'
import json
import os
from pathlib import Path
import subprocess
import sys

head = 'a' * 40
old_head = 'b' * 40

def review(state='APPROVED', oid=head):
    """Build a review fixture with a valid SHA or an explicit null commit."""
    return {'state': state, 'commit': {'oid': oid} if oid else None}

def page(nodes, more=False, cursor=None):
    """Wrap review records and cursors in the GraphQL response shape."""
    return json.dumps({'data': {'repository': {'pullRequest': {'reviews': {
        'nodes': nodes, 'pageInfo': {'hasNextPage': more, 'endCursor': cursor}}}}}})

script = '''
source "$1"
gh() {
    [[ "$1" == api && "$2" == graphql ]] || return 90
    printf '%s\\n' called >> "$FIXTURE_CALLS"
    if [[ -n "${FIXTURE_HISTORY_PAGE:-}" ]]; then
        if [[ " $* " == *"reviews(first:100,"* ]]; then
            printf '%s\\n' "$FIXTURE_HISTORY_PAGE"
            return
        fi
        [[ " $* " == *"latestOpinionatedReviews(first:100,"* ]] || return 91
    fi
    if [[ " $* " == *" cursor=NEXT_PAGE "* ]]; then
        [[ "$FIXTURE_API_FAILURE" != second ]] || return 1
        printf '%s\\n' "$FIXTURE_SECOND_PAGE"
    else
        [[ "$FIXTURE_API_FAILURE" != first ]] || return 1
        printf '%s\\n' "$FIXTURE_FIRST_PAGE"
    fi
}
octo_release_current_head_approval owner repo 687 "$2"
'''
cases = [
    ('old approval', page([review(oid=old_head)]), '', '', 'false', 1),
    ('current approval', page([review()]), '', '', 'true', 1),
    ('dismissed approval', page([review('DISMISSED')]), '', '', 'false', 1),
    ('pending review', page([review('PENDING', None)]), '', '', 'false', 1),
    ('empty reviews', page([]), '', '', 'false', 1),
    ('null commit approval', page([review(oid=None)]), '', '', 'false', 1),
    ('null then current', page([review(oid=None)], True, 'NEXT_PAGE'), page([review()]), '', 'true', 2),
    ('later approval', page([review(oid=old_head)], True, 'NEXT_PAGE'), page([review()]), '', 'true', 2),
    ('later dismissed', page([], True, 'NEXT_PAGE'), page([review('DISMISSED')]), '', 'false', 2),
    ('first API failure', page([review()]), '', 'first', None, 1),
    ('later API failure', page([review()], True, 'NEXT_PAGE'), page([]), 'second', None, 2),
    ('malformed JSON', '{', '', '', None, 1),
    ('malformed review', page([{'state': 'APPROVED'}]), '', '', None, 1),
    ('malformed SHA', page([review(oid='not-a-commit')]), '', '', None, 1),
    ('unknown state', page([review('UNKNOWN')]), '', '', None, 1),
    ('missing page', '{}', '', '', None, 1),
    ('later malformed page', page([review()], True, 'NEXT_PAGE'), '{}', '', None, 2),
    ('missing cursor', page([review()], True), '', '', None, 1),
    ('repeated cursor', page([review()], True, 'NEXT_PAGE'), page([], True, 'NEXT_PAGE'), '', None, 2),
    ('invalid pagination', page([review()], 'false'), '', '', None, 1),
]
partial = json.loads(page([review()]))
partial['errors'] = [{'message': 'partial response'}]
cases.append(('GraphQL error', json.dumps(partial), '', '', None, 1))
for index, (name, first, second, failure, expected, count) in enumerate(cases):
    calls = Path(sys.argv[2]) / ('approval-calls-' + str(index))
    calls.write_text('')
    env = dict(os.environ, FIXTURE_CALLS=str(calls), FIXTURE_FIRST_PAGE=first,
               FIXTURE_SECOND_PAGE=second, FIXTURE_API_FAILURE=failure)
    result = subprocess.run(['bash', '-c', script, '_', sys.argv[1], head],
                            env=env, capture_output=True, text=True)
    if expected is None:
        assert result.returncode != 0, (name, result.stdout, result.stderr)
    else:
        assert result.returncode == 0 and result.stdout.strip() == expected, (name, result.stdout, result.stderr)
    assert len(calls.read_text().splitlines()) == count, name

# GitHub selects one applicable opinion per reviewer. Historical approvals must
# not be resurrected, while a comment or pending review must not revoke one.
sequences = [
    ('approval superseded by changes and stale approval',
     [review(), review('CHANGES_REQUESTED'), review(oid=old_head)],
     [review(oid=old_head)], 'false'),
    ('approval superseded by changes', [review(), review('CHANGES_REQUESTED')],
     [review('CHANGES_REQUESTED')], 'false'),
    ('approval dismissed', [review(), review('DISMISSED')],
     [review('DISMISSED')], 'false'),
    ('comment preserves approval', [review(), review('COMMENTED')],
     [review()], 'true'),
    ('pending review preserves approval', [review(), review('PENDING', None)],
     [review()], 'true'),
]
for index, (name, history, applicable, expected) in enumerate(sequences):
    calls = Path(sys.argv[2]) / ('applicable-approval-calls-' + str(index))
    calls.write_text('')
    env = dict(os.environ, FIXTURE_CALLS=str(calls), FIXTURE_FIRST_PAGE=page(applicable),
               FIXTURE_SECOND_PAGE='', FIXTURE_API_FAILURE='',
               FIXTURE_HISTORY_PAGE=page(history))
    result = subprocess.run(['bash', '-c', script, '_', sys.argv[1], head],
                            env=env, capture_output=True, text=True)
    assert result.returncode == 0 and result.stdout.strip() == expected, (name, result.stdout, result.stderr)
APPROVALS
    then test_pass; else test_fail "release accepted stale, dismissed, or unverifiable approval"; fi
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
test_release_merge_pins_reviewed_head
test_release_rejects_concurrently_changed_merged_head
test_release_notes_use_private_file
test_release_ci_timeout_covers_macos
test_release_requires_clean_review_state
test_release_requires_approval_on_expected_head
test_release_verifies_main_before_tag
test_release_timeout_is_bounded
test_fetch_head_approach_works_when_main_checked_out_elsewhere

test_summary
