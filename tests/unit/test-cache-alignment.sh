#!/usr/bin/env bash
# Tests for cache-aligned prompt structure in spawn.sh, agent-sync.sh, workflows.sh
# Verifies stable content (persona/skill) appears before variable content (timestamps/session state)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "cache-aligned prompt structure in spawn.sh, agent-sync.sh, workflows.sh"


SPAWN_SH="$PROJECT_ROOT/scripts/lib/spawn.sh"
AGENT_SYNC_SH="$PROJECT_ROOT/scripts/lib/agent-sync.sh"
WORKFLOWS_SH="$PROJECT_ROOT/scripts/lib/workflows.sh"
SESSION_SH="$PROJECT_ROOT/scripts/lib/session.sh"
SEMANTIC_CACHE_SH="$PROJECT_ROOT/scripts/lib/semantic-cache.sh"
HEURISTICS_SH="$PROJECT_ROOT/scripts/lib/heuristics.sh"
RUN_CONTRACT_SH="$PROJECT_ROOT/scripts/lib/run-contract.sh"

pass() { test_case "$1"; test_pass; }
fail() { test_case "$1"; test_fail "${2:-$1}"; }

# ── File existence ────────────────────────────────────────────────────────────

for f in "$SPAWN_SH" "$AGENT_SYNC_SH" "$WORKFLOWS_SH"; do
  fname=$(basename "$f")
  if [[ -f "$f" ]]; then
    pass "$fname exists"
  else
    fail "$fname exists" "file not found"
  fi
done

# ── v10 runtime cache truth ──────────────────────────────────────────────────

test_case "session source without WORKSPACE_DIR never resolves a root cache path"
set +e
cache_source_output=$(env -i HOME="$TEST_TMP_DIR/cache-home" PATH="$PATH" \
  bash -c 'set -u; source "$1"; octo_probe_cache_dir' _ "$SESSION_SH" 2>&1)
cache_source_rc=$?
set -e
if [[ "$cache_source_rc" -eq 0 && "$cache_source_output" == "$TEST_TMP_DIR/cache-home/"* && "$cache_source_output" != "/.cache/probe-results" ]]; then
  test_pass
else
  test_fail "rc=$cache_source_rc output=$cache_source_output"
fi

test_case "cache write failure propagates without publishing partial entries"
cache_failure_root="$TEST_TMP_DIR/cache-parent-file"
printf 'not a directory\n' > "$cache_failure_root"
cache_source_file="$TEST_TMP_DIR/cache-source.md"
printf 'usable synthesis\n' > "$cache_source_file"
set +e
cache_failure_output=$(WORKSPACE_DIR="$cache_failure_root" CACHE_TTL=3600 bash -c '
  log() { :; }
  source "$1"
  save_to_cache fixture "$2"
' _ "$SEMANTIC_CACHE_SH" "$cache_source_file" 2>&1)
cache_failure_rc=$?
set -e
if [[ "$cache_failure_rc" -ne 0 && ! -e "$cache_failure_root/.cache/probe-results/fixture.md" && ! -e "$cache_failure_root/.cache/probe-results/fixture.meta" ]]; then
  test_pass
else
  test_fail "rc=$cache_failure_rc output=$cache_failure_output"
fi

test_case "a failed metadata install removes the uncommitted cache result"
partial_root="$TEST_TMP_DIR/cache-partial"
mkdir -p "$partial_root/.cache/probe-results"
set +e
partial_output=$(WORKSPACE_DIR="$partial_root" CACHE_TTL=3600 bash -c '
  log() { :; }
  source "$1"
  mv() {
    [[ "${2:-}" == *.meta ]] && return 1
    command mv "$@"
  }
  save_to_cache fixture "$2"
' _ "$SEMANTIC_CACHE_SH" "$cache_source_file" 2>&1)
partial_rc=$?
set -e
if [[ "$partial_rc" -ne 0 && ! -e "$partial_root/.cache/probe-results/fixture.md" && ! -e "$partial_root/.cache/probe-results/fixture.meta" ]]; then
  test_pass
else
  test_fail "rc=$partial_rc files=$(find "$partial_root/.cache/probe-results" -maxdepth 1 -type f -print | tr '\n' ' ') output=$partial_output"
fi

test_case "semantic lookup ignores orphaned bigram sidecars"
orphan_root="$TEST_TMP_DIR/cache-orphan"
mkdir -p "$orphan_root/.cache/probe-results"
printf '%s\n' 'same prompt' > "$orphan_root/.cache/probe-results/orphan.bigrams"
set +e
orphan_output=$(WORKSPACE_DIR="$orphan_root" OCTOPUS_SEMANTIC_CACHE=true \
  bash -c '
    log() { :; }
    source "$1"
    bigram_similarity() { printf "1\n"; }
    check_cache_semantic "same prompt"
  ' _ "$SEMANTIC_CACHE_SH" 2>&1)
orphan_rc=$?
set -e
if [[ "$orphan_rc" -ne 0 && -z "$orphan_output" ]]; then
  test_pass
else
  test_fail "rc=$orphan_rc output=$orphan_output"
fi

test_case "cache expiry removes semantic sidecars"
expired_root="$TEST_TMP_DIR/cache-expired"
mkdir -p "$expired_root/.cache/probe-results"
printf '%s\n' 'expired result' > "$expired_root/.cache/probe-results/expired.md"
printf '%s\n' '0' > "$expired_root/.cache/probe-results/expired.meta"
printf '%s\n' 'expired prompt' > "$expired_root/.cache/probe-results/expired.bigrams"
WORKSPACE_DIR="$expired_root" CACHE_TTL=1 bash -c '
  log() { :; }
  source "$1"
  cleanup_cache
' _ "$SEMANTIC_CACHE_SH"
if [[ ! -e "$expired_root/.cache/probe-results/expired.md" && \
      ! -e "$expired_root/.cache/probe-results/expired.meta" && \
      ! -e "$expired_root/.cache/probe-results/expired.bigrams" ]]; then
  test_pass
else
  test_fail "expired cache entry left semantic sidecars"
fi

test_case "failed probe persistence is non-fatal and never claims a cache hit"
cache_report_manifest="$TEST_TMP_DIR/cache-report-manifest"
set +e
cache_report_output=$(WORKSPACE_DIR="$cache_report_manifest" OCTOPUS_RUN_ID="cache-report" bash -c '
  log() { :; }
  save_to_cache() { return 73; }
  source "$1"
  report_probe_cache_result fixture "$2"
' _ "$HEURISTICS_SH" "$cache_source_file" 2>&1)
cache_report_rc=$?
set -e
if [[ "$cache_report_rc" -eq 0 && "$cache_report_output" == *"not cached"* && "$cache_report_output" != *"Cached for 1 hour"* ]] &&
   jq -e '.events[-1].event == "cache.write.failed"' \
      "$cache_report_manifest/runs/cache-report/seats.json" >/dev/null 2>&1; then
  test_pass
else
  test_fail "rc=$cache_report_rc output=$cache_report_output"
fi

test_case "run manifest records cache.write.failed"
manifest_root="$TEST_TMP_DIR/cache-manifest"
set +e
manifest_output=$(WORKSPACE_DIR="$manifest_root" OCTOPUS_RUN_ID="cache-failure" bash -c '
  source "$1"
  run_contract_record_event cache.write.failed "artifact=/tmp/synthesis.md" "reason=mkdir failed"
  run_contract_snapshot
' _ "$RUN_CONTRACT_SH" 2>&1)
manifest_rc=$?
set -e
if [[ "$manifest_rc" -eq 0 ]] && jq -e '
  .events[-1].event == "cache.write.failed" and
  .events[-1].attributes.artifact == "/tmp/synthesis.md"
' <<< "$manifest_output" >/dev/null 2>&1; then
  test_pass
else
  test_fail "rc=$manifest_rc output=$manifest_output"
fi

# ── Syntax check ──────────────────────────────────────────────────────────────

for f in "$SPAWN_SH" "$AGENT_SYNC_SH" "$WORKFLOWS_SH"; do
  fname=$(basename "$f")
  if bash -n "$f" 2>/dev/null; then
    pass "$fname has valid bash syntax"
  else
    fail "$fname has valid bash syntax" "syntax error"
  fi
done

# ── Cache-alignment comment block present ─────────────────────────────────────

for f in "$SPAWN_SH" "$AGENT_SYNC_SH" "$WORKFLOWS_SH"; do
  fname=$(basename "$f")
  if grep -q "Cache-aligned prompt structure" "$f"; then
    pass "$fname has cache-alignment comment block"
  else
    fail "$fname has cache-alignment comment block" "comment not found"
  fi
done

# ── STABLE PREFIX marker present ──────────────────────────────────────────────

for f in "$SPAWN_SH" "$AGENT_SYNC_SH" "$WORKFLOWS_SH"; do
  fname=$(basename "$f")
  if grep -q "STABLE PREFIX" "$f"; then
    pass "$fname has STABLE PREFIX section marker"
  else
    fail "$fname has STABLE PREFIX section marker" "marker not found"
  fi
done

# ── VARIABLE SUFFIX marker present ───────────────────────────────────────────

for f in "$SPAWN_SH" "$AGENT_SYNC_SH" "$WORKFLOWS_SH"; do
  fname=$(basename "$f")
  if grep -q "VARIABLE SUFFIX" "$f"; then
    pass "$fname has VARIABLE SUFFIX section marker"
  else
    fail "$fname has VARIABLE SUFFIX section marker" "marker not found"
  fi
done

# ── spawn.sh: apply_persona appears before checkpoint/memory/provider_ctx ────

spawn_content=$(<"$SPAWN_SH")

# Get line numbers for key sections
line_persona=$(grep -n "apply_persona" "$SPAWN_SH" | head -1 | cut -d: -f1)
line_skill=$(grep -n "Agent Skill Context" "$SPAWN_SH" | head -1 | cut -d: -f1)
line_earned=$(grep -n "Earned Project Skills" "$SPAWN_SH" | head -1 | cut -d: -f1)

# Use the injection point (## Previous Attempt Context), not the loading code
line_checkpoint=$(grep -n "## Previous Attempt Context" "$SPAWN_SH" | head -1 | cut -d: -f1)
line_memory=$(grep -n "Previous Context (from" "$SPAWN_SH" | head -1 | cut -d: -f1)
line_provider_hist=$(grep -n "provider history context" "$SPAWN_SH" | head -1 | cut -d: -f1)
line_heuristic=$(grep -n "File Heuristics" "$SPAWN_SH" | head -1 | cut -d: -f1)

# Persona (stable) must appear before checkpoint (variable)
if [[ -n "$line_persona" && -n "$line_checkpoint" ]] && [[ $line_persona -lt $line_checkpoint ]]; then
  pass "spawn.sh: persona appears before checkpoint context"
else
  fail "spawn.sh: persona appears before checkpoint context" \
    "persona=$line_persona, checkpoint=$line_checkpoint"
fi

# Skill context (stable) must appear before memory (variable)
if [[ -n "$line_skill" && -n "$line_memory" ]] && [[ $line_skill -lt $line_memory ]]; then
  pass "spawn.sh: skill context appears before memory context"
else
  fail "spawn.sh: skill context appears before memory context" \
    "skill=$line_skill, memory=$line_memory"
fi

# Earned skills (stable) must appear before provider history (variable)
if [[ -n "$line_earned" && -n "$line_provider_hist" ]] && [[ $line_earned -lt $line_provider_hist ]]; then
  pass "spawn.sh: earned skills appear before provider history"
else
  fail "spawn.sh: earned skills appear before provider history" \
    "earned=$line_earned, provider_hist=$line_provider_hist"
fi

# Earned skills (stable) must appear before heuristic context (variable)
if [[ -n "$line_earned" && -n "$line_heuristic" ]] && [[ $line_earned -lt $line_heuristic ]]; then
  pass "spawn.sh: earned skills appear before heuristic context"
else
  fail "spawn.sh: earned skills appear before heuristic context" \
    "earned=$line_earned, heuristic=$line_heuristic"
fi

# ── spawn.sh: no timestamps or session IDs in stable prefix ───────────────────

# Extract the stable prefix section (between STABLE PREFIX and VARIABLE SUFFIX markers)
stable_section=$(awk '/STABLE PREFIX/,/VARIABLE SUFFIX/' "$SPAWN_SH")

# Check that no date/timestamp calls leak into the stable section
if echo "$stable_section" | grep -qE 'date \+%|Started:|session_id|CLAUDE_SESSION_ID'; then
  fail "spawn.sh: no timestamps/session IDs in stable prefix" \
    "found date/session reference in stable section"
else
  pass "spawn.sh: no timestamps/session IDs in stable prefix"
fi

# ── agent-sync.sh: earned skills (stable) before provider history (variable) ──

line_earned_sync=$(grep -n "Earned Project Skills" "$AGENT_SYNC_SH" | head -1 | cut -d: -f1)
line_provider_sync=$(grep -n "provider history context\|build_provider_context" "$AGENT_SYNC_SH" | head -1 | cut -d: -f1)

if [[ -n "$line_earned_sync" && -n "$line_provider_sync" ]] && [[ $line_earned_sync -lt $line_provider_sync ]]; then
  pass "agent-sync.sh: earned skills appear before provider history"
else
  fail "agent-sync.sh: earned skills appear before provider history" \
    "earned=$line_earned_sync, provider=$line_provider_sync"
fi

# ── agent-sync.sh: no timestamps in stable prefix ────────────────────────────

stable_sync=$(awk '/STABLE PREFIX/,/VARIABLE SUFFIX/' "$AGENT_SYNC_SH")
if echo "$stable_sync" | grep -qE 'date \+%|Started:|session_id'; then
  fail "agent-sync.sh: no timestamps/session IDs in stable prefix" \
    "found date/session reference in stable section"
else
  pass "agent-sync.sh: no timestamps/session IDs in stable prefix"
fi

# ── workflows.sh: persona before budget enforcement ──────────────────────────

line_persona_wf=$(grep -n "apply_persona" "$WORKFLOWS_SH" | head -1 | cut -d: -f1)
line_budget_wf=$(grep -n "enforce_context_budget" "$WORKFLOWS_SH" | head -1 | cut -d: -f1)

if [[ -n "$line_persona_wf" && -n "$line_budget_wf" ]] && [[ $line_persona_wf -lt $line_budget_wf ]]; then
  pass "workflows.sh: persona appears before context budget enforcement"
else
  fail "workflows.sh: persona appears before context budget enforcement" \
    "persona=$line_persona_wf, budget=$line_budget_wf"
fi

# ── workflows.sh: no timestamps in stable prefix ─────────────────────────────

stable_wf=$(awk '/STABLE PREFIX/,/VARIABLE SUFFIX/' "$WORKFLOWS_SH")
if echo "$stable_wf" | grep -qE 'date \+%|Started:|session_id'; then
  fail "workflows.sh: no timestamps/session IDs in stable prefix" \
    "found date/session reference in stable section"
else
  pass "workflows.sh: no timestamps/session IDs in stable prefix"
fi

# ── spawn.sh: prompt construction function exists ─────────────────────────────

if grep -q "^spawn_agent()" "$SPAWN_SH"; then
  pass "spawn_agent() function exists in spawn.sh"
else
  fail "spawn_agent() function exists in spawn.sh" "function not found"
fi

# ── agent-sync.sh: prompt construction function exists ────────────────────────

if grep -q "run_agent_sync" "$AGENT_SYNC_SH"; then
  pass "run_agent_sync() function exists in agent-sync.sh"
else
  fail "run_agent_sync() function exists in agent-sync.sh" "function not found"
fi

# ── No attribution references ────────────────────────────────────────────────

for f in "$SPAWN_SH" "$AGENT_SYNC_SH" "$WORKFLOWS_SH"; do
  fname=$(basename "$f")
  content=$(<"$f")
  if echo "$content" | grep -qiE 'gsd|temm1e'; then
    fail "no attribution references in $fname" "found banned pattern"
  else
    pass "no attribution references in $fname"
  fi
done
test_summary
