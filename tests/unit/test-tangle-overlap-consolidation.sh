#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_TMP_DIR="${TEST_TMP_DIR:-/tmp/octopus-tests-$$}"
trap 'rm -rf "$TEST_TMP_DIR"' EXIT INT TERM
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "tangle overlap consolidation"
WORKFLOWS="$PROJECT_ROOT/scripts/lib/workflows.sh"
PLUGIN_DIR="$PROJECT_ROOT"
WORKSPACE_DIR="$TEST_TMP_DIR/workspace"
RESULTS_DIR="$TEST_TMP_DIR/results"
mkdir -p "$WORKSPACE_DIR/apps/web/src" "$WORKSPACE_DIR/apps/server/data" "$RESULTS_DIR"
printf '{}\n' > "$WORKSPACE_DIR/apps/web/package.json"
printf '{}\n' > "$WORKSPACE_DIR/apps/server/package.json"
printf 'x\n' > "$WORKSPACE_DIR/apps/web/src/main.jsx"
printf 'x\n' > "$WORKSPACE_DIR/apps/server/data/seed.json"
git -C "$WORKSPACE_DIR" init -q
git -C "$WORKSPACE_DIR" add .
log() { :; }
source "$WORKFLOWS"
PROJECT_ROOT="$WORKSPACE_DIR"

decomposition='1. [CODING] Web baseline — Files: apps/web/package.json, apps/web/src/main.jsx — Task: create the web baseline
2. [CODING] Server — Files: apps/server/package.json, apps/server/data/ — Task: implement the server
3. [CODING] Web integration — Files: apps/web/package.json — Task: wire the web scripts
4. [REASONING] Validate the handoff'

test_case "consolidates only the connected overlapping coding component"
result=$(tangle_consolidate_overlapping_subtasks "$decomposition")
if [[ "$(tangle_parseable_subtask_count "$result")" -eq 3 ]] &&
   [[ "$(tangle_parseable_coding_subtask_count "$result")" -eq 2 ]] &&
   [[ "$result" == *"create the web baseline; wire the web scripts"* ]] &&
   [[ "$result" == *"implement the server"* ]] &&
   [[ "$result" == *"[REASONING] Validate the handoff"* ]] &&
   tangle_validate_parallel_write_scopes "$result" >/dev/null; then
    test_pass
else
    printf '%s\n' "$result"
    test_fail "connected scopes were not consolidated into a safe decomposition"
fi

test_case "preserves already-disjoint decompositions"
disjoint='1. [CODING] Web — Files: apps/web/package.json — Task: web
2. [CODING] Server — Files: apps/server/package.json — Task: server'
result=$(tangle_consolidate_overlapping_subtasks "$disjoint")
if [[ "$(tangle_parseable_coding_subtask_count "$result")" -eq 2 ]] &&
   [[ "$result" == *"Task: web"* ]] &&
   [[ "$result" == *"Task: server"* ]] &&
   tangle_validate_parallel_write_scopes "$result" >/dev/null; then
    test_pass
else
    test_fail "disjoint decomposition changed unsafely"
fi

test_case "consolidates transitive overlaps as one component"
transitive='1. [CODING] Source — Files: apps/web/src/ — Task: source scope
2. [CODING] Bridge — Files: apps/web/src/main.jsx, apps/web/package.json — Task: bridge scope
3. [CODING] Package — Files: apps/web/package.json — Task: package scope'
result=$(tangle_consolidate_overlapping_subtasks "$transitive")
if [[ "$(tangle_parseable_coding_subtask_count "$result")" -eq 1 ]] &&
   [[ "$result" == *"source scope; bridge scope; package scope"* ]] &&
   tangle_validate_parallel_write_scopes "$result" >/dev/null; then
    test_pass
else
    test_fail "transitive overlap component was not fully consolidated"
fi

test_case "consolidation keeps repeated Task segments on one parseable line"
repeated_task='1. [CODING] First — Files: apps/web/package.json — Task: first segment Task: second segment
2. [CODING] Second — Files: apps/web/package.json — Task: third segment'
result=$(tangle_consolidate_overlapping_subtasks "$repeated_task")
if [[ "$(printf '%s\n' "$result" | wc -l | tr -d ' ')" -eq 1 ]] &&
   [[ "$(tangle_parseable_subtask_count "$result")" -eq 1 ]] &&
   [[ "$result" == *"Task: first segment second segment; third segment"* ]]; then
    test_pass
else
    printf '%s\n' "$result"
    test_fail "repeated Task segments produced a multiline consolidated subtask"
fi

test_case "repairs the exact Memory Keeper residual overlap"
mkdir -p "$WORKSPACE_DIR/apps/web/src" "$WORKSPACE_DIR/apps/server/src" "$WORKSPACE_DIR/apps/server/data" "$WORKSPACE_DIR/docs"
touch "$WORKSPACE_DIR/package.json" "$WORKSPACE_DIR/.env.example" "$WORKSPACE_DIR/.gitignore" "$WORKSPACE_DIR/README.md" \
      "$WORKSPACE_DIR/apps/web/package.json" "$WORKSPACE_DIR/apps/web/src/main.jsx" "$WORKSPACE_DIR/apps/web/src/styles.css" "$WORKSPACE_DIR/apps/web/index.html" \
      "$WORKSPACE_DIR/apps/server/package.json" "$WORKSPACE_DIR/apps/server/src/index.js" "$WORKSPACE_DIR/docs/PRODUCT.md"
memory_keeper='1. [CODING] Baseline contracts and test scaffolding — Files: package.json, .env.example, .gitignore, README.md, apps/web/package.json, apps/server/package.json, docs/PRODUCT.md — Task: Audit existing scaffold, lock npm workspace layout (apps/web + apps/server), add repository scripts (test, build, check, lint), define documented API contract section, deterministic synthetic fixtures, and confirm runtime files are gitignored under apps/server/data.
2. [CODING] Server foundation, invitation, consent, prompts, recording, and memory-card — Files: apps/server/src/index.js, apps/server/data/ — Task: Implement HTTP server with health/readiness, JSON error envelope, MIME allowlist, upload limits, MediaStorage interface with local filesystem implementation, file-backed persistence for FamilySpace/Invitation/ConsentRecord/StoryPrompt/Recording/MemoryCard, invitation lifecycle, versioned consent, one-prompt-at-a-time gating, deterministic next-topic suggestion, multipart upload with validation, playback retrieval, deterministic memory-card generation behind interface, idempotent deletion with safe-repeat semantics, and invalid-transition guard tests.
3. [CODING] Web application flow — Files: apps/web/src/main.jsx, apps/web/src/styles.css, apps/web/index.html, apps/web/package.json — Task: Build mobile-first accessible inviter→storyteller→review flow with API client, state machine, MediaRecorder with pause/resume/discard/save, upload progress/retry, unsupported-browser fallback, playback, deletion confirmation, reduced-motion behavior, and keyboard-visible focus.
4. [REASONING] Quality validation and handoff evidence — Task: Run unit, integration, and browser tests (happy path + deletion + unsupported-recording + failed-upload recovery), execute npm test / npm run check / production web build, verify zero external services or secrets, confirm git status is clean outside runtime path, and produce final acceptance checklist with architecture summary, changed components, artifact paths, and documented limitations.'
result=$(tangle_consolidate_overlapping_subtasks "$memory_keeper")
if [[ "$(tangle_parseable_subtask_count "$result")" -eq 3 ]] &&
   [[ "$(tangle_parseable_coding_subtask_count "$result")" -eq 2 ]] &&
   [[ "$result" == *"Audit existing scaffold"* ]] &&
   [[ "$result" == *"Build mobile-first accessible"* ]] &&
   [[ "$result" == *"Implement HTTP server"* ]] &&
   [[ "$result" == *"[REASONING] Quality validation and handoff evidence"* ]] &&
   tangle_validate_parallel_write_scopes "$result" >/dev/null; then
    test_pass
else
    printf '%s\n' "$result"
    test_fail "exact Memory Keeper decomposition was not repaired safely"
fi

test_summary
