#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../helpers/test-framework.sh"
source "$PROJECT_ROOT_REPO/scripts/lib/workflows.sh"

test_suite "tangle explicit new scope preservation"

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/apps/server/src" "$fixture/apps/web/src"
printf 'root\n' > "$fixture/README.md"
printf '{}\n' > "$fixture/package.json"
printf 'server\n' > "$fixture/apps/server/src/index.js"
printf 'web\n' > "$fixture/apps/web/src/main.jsx"
git -C "$fixture" init -q
git -C "$fixture" config user.email test@example.com
git -C "$fixture" config user.name Test
git -C "$fixture" add .
git -C "$fixture" commit -qm init
export PROJECT_ROOT="$fixture"

test_case "preserves existing tracked file"
if tangle_scope_is_known_or_explicit_new_file "README.md"; then test_pass; else test_fail "tracked file rejected"; fi

test_case "preserves invented development directory under existing ancestor"
if tangle_scope_is_known_or_explicit_new_file "apps/server/src/development-scope/"; then test_pass; else test_fail "new anchored directory rejected"; fi

test_case "preserves invented new file under existing ancestor"
if tangle_scope_is_known_or_explicit_new_file "apps/server/src/development-scope/handler.js"; then test_pass; else test_fail "new anchored file rejected"; fi

test_case "rejects unanchored top-level invented tree"
if tangle_scope_is_known_or_explicit_new_file "totally-invented-tree/deep/file.js"; then test_fail "unanchored tree accepted"; else test_pass; fi

test_case "rejects traversal"
if tangle_scope_is_known_or_explicit_new_file "apps/server/../../outside.js"; then test_fail "traversal accepted"; else test_pass; fi

test_case "rejects absolute path"
if tangle_scope_is_known_or_explicit_new_file "/tmp/outside.js"; then test_fail "absolute path accepted"; else test_pass; fi

test_case "rejects glob scope"
if tangle_scope_is_known_or_explicit_new_file "apps/server/src/**"; then test_fail "glob accepted"; else test_pass; fi

# macOS APFS/HFS+ is case-insensitive by default and is this project's primary
# platform, so a literal `.git` match let these through — and `.GIT/hooks/*`
# resolves to the real hook directory, making it arbitrary code execution on the
# next commit. A guard whose suite never tries a case variant passes while the
# hole is open, which is what happened here.
test_case "rejects .git"
if tangle_scope_is_known_or_explicit_new_file ".git/config"; then test_fail ".git accepted"; else test_pass; fi

for variant in ".GIT/config" ".Git/hooks/pre-commit" ".gIt/HOOKS/pre-commit"; do
    test_case "rejects case variant $variant"
    if tangle_scope_is_known_or_explicit_new_file "$variant"; then
        test_fail "$variant accepted — resolves into .git on a case-insensitive filesystem"
    else
        test_pass
    fi
done

test_case "rejects a whitespace-only scope"
if tangle_scope_is_known_or_explicit_new_file "  "; then test_fail "whitespace-only scope accepted"; else test_pass; fi

test_case "explicit new scope does not fall back to README heuristic"
subtasks='1. [CODING] Docs — Files: README.md — Task: Update documentation and acceptance notes.
2. [CODING] Development scope — Files: apps/server/src/development-scope/ — Task: Implement a new development-only server module and tests.'
if tangle_validate_parallel_write_scopes "$subtasks"; then
    test_pass
else
    test_fail "valid new scope falsely overlapped README.md"
fi

test_case "new parent and child scopes still overlap"
subtasks='1. [CODING] Parent — Files: apps/server/src/development-scope/ — Task: Implement parent module.
2. [CODING] Child — Files: apps/server/src/development-scope/child.js — Task: Implement child module.'
if reason=$(tangle_validate_parallel_write_scopes "$subtasks"); then
    test_fail "parent/child overlap was accepted"
elif [[ "$reason" == *"overlaps"* ]]; then
    test_pass
else
    test_fail "unexpected overlap reason: $reason"
fi

test_summary
