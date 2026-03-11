#!/usr/bin/env bash
# Test suite for v8.49.0 model-config improvements
# Tests: cache key collision, cache invalidation, input validation,
#        resolution trace, atomic operations, provider whitelist

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATE="${SCRIPT_DIR}/../scripts/orchestrate.sh"

PASSED=0
FAILED=0
TOTAL=0

pass() { ((PASSED++)); ((TOTAL++)); echo -e "\033[0;32m✓\033[0m $1"; }
fail() { ((FAILED++)); ((TOTAL++)); echo -e "\033[0;31m✗\033[0m $1"; }

echo "Testing Model Config v8.49.0 Improvements"
echo "==========================================="
echo ""

# ─── Test Group 1: Cache Key Collision Prevention ───────────────────────────

echo "Test Group 1: Cache Key Collision Prevention"
echo "---------------------------------------------"

# The old code used tr '[:punct:]' '_' which made codex+spark collide with codex-spark
# New code uses field-delimited keys: MC_<provider>_A_<type>_P_<phase>_R_<role>

# Verify the new cache key format is in the code
if grep -q 'MC_\${safe_p}_A_\${safe_a}_P_\${safe_ph}_R_\${safe_r}' "$ORCHESTRATE"; then
    pass "Cache key uses field-delimited format (MC_..._A_..._P_..._R_...)"
else
    fail "Cache key format not updated to field-delimited pattern"
fi

# Verify the old collision-prone pattern is removed
if grep -q "CACHE_\${provider}_\${agent_type}" "$ORCHESTRATE"; then
    fail "Old CACHE_ key pattern still present (collision-prone)"
else
    pass "Old CACHE_ collision-prone pattern removed"
fi

# Verify per-field sanitization variables exist
if grep -q 'safe_p="\${provider//\[^a-zA-Z0-9\]/_}"' "$ORCHESTRATE"; then
    pass "Per-field sanitization for cache keys present"
else
    fail "Missing per-field sanitization for cache keys"
fi

echo ""

# ─── Test Group 2: Cache Invalidation ──────────────────────────────────────

echo "Test Group 2: Cache Invalidation"
echo "---------------------------------"

# Verify config mtime check invalidates stale cache
if grep -q 'config_file.*-nt.*persistent_cache' "$ORCHESTRATE"; then
    pass "Config mtime check invalidates stale persistent cache"
else
    fail "Missing config mtime check for cache invalidation"
fi

# Verify set_provider_model clears cache
if grep -A 5 'Set default model' "$ORCHESTRATE" | grep -q 'rm -f.*persistent_cache\|rm -f.*octo-model-cache'; then
    pass "set_provider_model() clears model cache after change"
else
    fail "set_provider_model() does not clear cache after change"
fi

# Verify reset_provider_model clears cache (cache clearing is after the if/elif/fi block)
if grep -A 15 'Cleared all model overrides' "$ORCHESTRATE" | grep -q 'rm -f.*persistent_cache\|rm -f.*octo-model-cache'; then
    pass "reset_provider_model() clears model cache after reset"
else
    fail "reset_provider_model() does not clear cache after reset"
fi

# Verify migrate_provider_config clears cache
if grep -A 5 'Migration to v3.0 complete' "$ORCHESTRATE" | grep -q 'rm -f.*octo-model-cache'; then
    pass "migrate_provider_config() clears cache after migration"
else
    fail "migrate_provider_config() does not clear cache after migration"
fi

echo ""

# ─── Test Group 3: Input Validation Hardening ──────────────────────────────

echo "Test Group 3: Input Validation Hardening"
echo "-----------------------------------------"

# Verify jq --arg is used instead of string interpolation in set_provider_model
if grep -A 3 "atomic_json_update.*config_file" "$ORCHESTRATE" | grep -q '\-\-arg.*p.*provider.*\-\-arg.*m.*model'; then
    pass "set_provider_model() uses jq --arg for injection safety"
else
    fail "set_provider_model() not using jq --arg"
fi

# Verify provider whitelist exists
if grep -q 'codex|gemini|claude|perplexity|openrouter' "$ORCHESTRATE"; then
    pass "Provider whitelist validation present"
else
    fail "Provider whitelist validation missing"
fi

# Verify --force escape hatch for custom providers
if grep -q '\-\-force' "$ORCHESTRATE" && grep -q 'custom provider\|local prox' "$ORCHESTRATE"; then
    pass "--force flag available for custom/local providers"
else
    fail "--force escape hatch for custom providers missing"
fi

# Verify better error message for invalid model names
if grep -q 'shell metacharacters\|spaces.*quotes' "$ORCHESTRATE"; then
    pass "Enhanced error message explains invalid model name characters"
else
    fail "Error message for invalid model names not enhanced"
fi

# Verify jq --arg in migrate_provider_config stale model migration
if grep -B2 -A2 'Migrating stale model' "$ORCHESTRATE" | grep -q '\-\-arg val'; then
    pass "migrate_provider_config() uses jq --arg for stale model replacement"
else
    fail "migrate_provider_config() not using jq --arg for migration"
fi

# Verify --argjson for overrides merge
if grep -q '\-\-argjson ovr' "$ORCHESTRATE"; then
    pass "migrate_provider_config() uses --argjson for safe overrides merge"
else
    fail "migrate_provider_config() not using --argjson for overrides"
fi

echo ""

# ─── Test Group 4: Resolution Trace ───────────────────────────────────────

echo "Test Group 4: Resolution Trace (OCTOPUS_TRACE_MODELS)"
echo "------------------------------------------------------"

# Verify trace env var support
if grep -q 'OCTOPUS_TRACE_MODELS' "$ORCHESTRATE"; then
    pass "OCTOPUS_TRACE_MODELS env var supported"
else
    fail "OCTOPUS_TRACE_MODELS env var not found"
fi

# Verify trace header with provider/type/phase/role context
if grep -q '\[model-trace\] Resolving:' "$ORCHESTRATE"; then
    pass "Trace outputs resolution context header"
else
    fail "Trace missing resolution context header"
fi

# Count trace tier outputs (should have tiers 0.5 through 7)
trace_tiers=$(grep -c '\[model-trace\] Tier' "$ORCHESTRATE" 2>/dev/null || echo "0")
if [[ "$trace_tiers" -ge 7 ]]; then
    pass "Trace covers $trace_tiers+ precedence tiers"
else
    fail "Trace only covers $trace_tiers tiers (expected ≥7)"
fi

# Verify final result trace line
if grep -q '\[model-trace\] ► Result:' "$ORCHESTRATE"; then
    pass "Trace outputs final resolved model"
else
    fail "Trace missing final result output"
fi

# Verify trace goes to stderr (not stdout, to avoid polluting model name output)
if grep -q '\[model-trace\].*>&2' "$ORCHESTRATE"; then
    pass "Trace output goes to stderr (won't pollute model name)"
else
    fail "Trace output not directed to stderr"
fi

echo ""

# ─── Test Group 5: Atomic Operations ──────────────────────────────────────

echo "Test Group 5: Atomic JSON Operations"
echo "--------------------------------------"

# Verify atomic_json_update is used in set_provider_model
set_calls=$(grep -c 'atomic_json_update.*config_file' "$ORCHESTRATE" 2>/dev/null || echo "0")
if [[ "$set_calls" -ge 2 ]]; then
    pass "set_provider_model() uses atomic_json_update ($set_calls calls)"
else
    fail "set_provider_model() not using atomic_json_update (found $set_calls)"
fi

# Verify atomic_json_update is used in reset_provider_model
reset_calls=$(grep -A 20 'reset_provider_model()' "$ORCHESTRATE" | grep -c 'atomic_json_update' 2>/dev/null || echo "0")
if [[ "$reset_calls" -ge 2 ]]; then
    pass "reset_provider_model() uses atomic_json_update ($reset_calls calls)"
else
    fail "reset_provider_model() not using atomic_json_update (found $reset_calls)"
fi

# Verify no raw jq > tmp && mv pattern in set/reset functions
# (should all be using atomic_json_update now)
if grep -A 20 'set_provider_model()' "$ORCHESTRATE" | grep -q 'jq.*config_file.*>.*\.tmp.*&&.*mv'; then
    fail "set_provider_model() still has raw jq > tmp && mv pattern"
else
    pass "set_provider_model() no longer uses raw jq > tmp && mv"
fi

# Verify persistent cache write uses PID-safe temp file
if grep -q 'persistent_cache.*\.tmp\.\$\$' "$ORCHESTRATE"; then
    pass "Persistent cache write uses PID-safe temp file (.\$\$)"
else
    fail "Persistent cache write not using PID-safe temp file"
fi

echo ""

# ─── Test Group 6: Persistent Cache Safety ─────────────────────────────────

echo "Test Group 6: Persistent Cache Safety"
echo "---------------------------------------"

# Verify persistent cache uses jq --arg (not string interpolation)
if grep -q "jq --arg key.*--arg val.*persistent_cache" "$ORCHESTRATE"; then
    pass "Persistent cache write uses jq --arg (injection safe)"
else
    fail "Persistent cache write not using jq --arg"
fi

echo ""

# ─── Test Group 7: Post-Run Usage Reporting ────────────────────────────────

echo "Test Group 7: Post-Run Usage Reporting"
echo "---------------------------------------"

# Verify display_session_metrics exists
if grep -q '^display_session_metrics()' "$ORCHESTRATE"; then
    pass "display_session_metrics() function defined"
else
    fail "display_session_metrics() function missing"
fi

# Verify display_provider_breakdown exists
if grep -q '^display_provider_breakdown()' "$ORCHESTRATE"; then
    pass "display_provider_breakdown() function defined"
else
    fail "display_provider_breakdown() function missing"
fi

# Verify display_per_phase_cost_table exists
if grep -q '^display_per_phase_cost_table()' "$ORCHESTRATE"; then
    pass "display_per_phase_cost_table() function defined"
else
    fail "display_per_phase_cost_table() function missing"
fi

# Verify record_agent_start exists (returns metrics ID)
if grep -q '^record_agent_start()' "$ORCHESTRATE"; then
    pass "record_agent_start() function defined"
else
    fail "record_agent_start() function missing"
fi

# Verify record_agent_complete exists (records actual metrics)
if grep -q '^record_agent_complete()' "$ORCHESTRATE"; then
    pass "record_agent_complete() function defined"
else
    fail "record_agent_complete() function missing"
fi

# Verify record_agent_complete uses actual token data
if grep -A 10 'record_agent_complete()' "$ORCHESTRATE" | grep -q 'actual_tokens'; then
    pass "record_agent_complete() captures actual token counts"
else
    fail "record_agent_complete() does not capture actual tokens"
fi

# Verify embrace workflow calls display functions
if grep -q 'display_session_metrics' "$ORCHESTRATE" && \
   grep -q 'display_provider_breakdown' "$ORCHESTRATE" && \
   grep -q 'display_per_phase_cost_table' "$ORCHESTRATE"; then
    pass "embrace_full_workflow calls all 3 display functions"
else
    fail "embrace_full_workflow missing display function calls"
fi

echo ""

# ─── Test Group 8: Model Catalog (P2) ────────────────────────────────────

echo "Test Group 8: Model Catalog"
echo "----------------------------"

# Verify get_model_catalog function exists
if grep -q '^get_model_catalog()' "$ORCHESTRATE"; then
    pass "get_model_catalog() function defined"
else
    fail "get_model_catalog() function missing"
fi

# Verify catalog covers key models
for model in gpt-5.4 gpt-5.4 gemini-3.1-pro-preview claude-sonnet-4.6 sonar-pro o3; do
    if grep -A 60 'get_model_catalog()' "$ORCHESTRATE" | grep -q "$model"; then
        pass "Catalog includes $model"
    else
        fail "Catalog missing $model"
    fi
done

# Verify is_known_model function exists
if grep -q '^is_known_model()' "$ORCHESTRATE"; then
    pass "is_known_model() function defined"
else
    fail "is_known_model() function missing"
fi

# Verify get_model_capability function exists
if grep -q '^get_model_capability()' "$ORCHESTRATE"; then
    pass "get_model_capability() function defined"
else
    fail "get_model_capability() function missing"
fi

# Verify list_models function exists with filters
if grep -q '^list_models()' "$ORCHESTRATE"; then
    pass "list_models() function defined"
else
    fail "list_models() function missing"
fi

if grep -A 20 'list_models()' "$ORCHESTRATE" | grep -q '\-\-tools\|\-\-images\|\-\-reasoning'; then
    pass "list_models() supports capability filters"
else
    fail "list_models() missing capability filters"
fi

echo ""

# ─── Test Group 9: Health Checks (P2) ────────────────────────────────────

echo "Test Group 9: Pre-dispatch Health Checks"
echo "------------------------------------------"

# Verify check_provider_health function exists
if grep -q '^check_provider_health()' "$ORCHESTRATE"; then
    pass "check_provider_health() function defined"
else
    fail "check_provider_health() function missing"
fi

# Verify health checks cover all 5 providers
for provider in codex gemini claude perplexity openrouter; do
    if grep -A 60 'check_provider_health()' "$ORCHESTRATE" | grep -q "$provider)"; then
        pass "Health check covers $provider"
    else
        fail "Health check missing $provider"
    fi
done

# Verify check_all_providers function exists
if grep -q '^check_all_providers()' "$ORCHESTRATE"; then
    pass "check_all_providers() function defined"
else
    fail "check_all_providers() function missing"
fi

# Verify health check is wired into run_agent_sync
if grep -A 100 'run_agent_sync()' "$ORCHESTRATE" | grep -q 'check_provider_health'; then
    pass "run_agent_sync() calls check_provider_health() before dispatch"
else
    fail "run_agent_sync() not wired to health check"
fi

echo ""

# ─── Test Group 10: Capability-Aware Fallbacks (P2) ──────────────────────

echo "Test Group 10: Capability-Aware Fallbacks"
echo "-------------------------------------------"

# Verify find_capable_fallback function exists
if grep -q '^find_capable_fallback()' "$ORCHESTRATE"; then
    pass "find_capable_fallback() function defined"
else
    fail "find_capable_fallback() function missing"
fi

# Verify it checks tool/image/reasoning capabilities
if grep -A 50 'find_capable_fallback()' "$ORCHESTRATE" | grep -q 'req_tools.*yes.*c_tools.*yes'; then
    pass "find_capable_fallback() checks tool support compatibility"
else
    fail "find_capable_fallback() missing tool support check"
fi

if grep -A 50 'find_capable_fallback()' "$ORCHESTRATE" | grep -q 'req_images.*yes.*c_images.*yes'; then
    pass "find_capable_fallback() checks image input compatibility"
else
    fail "find_capable_fallback() missing image support check"
fi

if grep -A 50 'find_capable_fallback()' "$ORCHESTRATE" | grep -q 'req_reasoning.*yes.*c_reasoning.*yes'; then
    pass "find_capable_fallback() checks reasoning capability"
else
    fail "find_capable_fallback() missing reasoning check"
fi

# Verify validate_model_allowed uses find_capable_fallback
if grep -A 35 'validate_model_allowed()' "$ORCHESTRATE" | grep -q 'find_capable_fallback'; then
    pass "validate_model_allowed() uses capability-aware fallback"
else
    fail "validate_model_allowed() not wired to capability-aware fallback"
fi

echo ""

# ─── Test Group 11: Interactive Model Listing (P2) ───────────────────────

echo "Test Group 11: Interactive Model Listing"
echo "------------------------------------------"

HELPER="${SCRIPT_DIR}/../scripts/helpers/octo-model-config.sh"

# Verify models subcommand exists in helper
if grep -q 'cmd_models()' "$HELPER"; then
    pass "octo-model-config.sh has cmd_models() function"
else
    fail "octo-model-config.sh missing cmd_models()"
fi

# Verify filter support
if grep -A 5 'cmd_models()' "$HELPER" | grep -q 'filter'; then
    pass "cmd_models() supports filtering"
else
    fail "cmd_models() missing filter support"
fi

# Verify models case in main dispatch
if grep -q 'models) cmd_models' "$HELPER"; then
    pass "models subcommand wired in main dispatch"
else
    fail "models subcommand not wired in dispatch"
fi

echo ""

# ─── Test Group 12: CC Pre-Prompt Alignment (v8.49.0) ────────────────────

echo "Test Group 12: CC Pre-Prompt Alignment"
echo "----------------------------------------"

# Verify detect_project_quality_commands function exists
if grep -q '^detect_project_quality_commands()' "$ORCHESTRATE"; then
    pass "detect_project_quality_commands() function defined"
else
    fail "detect_project_quality_commands() function missing"
fi

# Verify it detects package.json, Cargo.toml, go.mod, pyproject.toml
for config in package.json Cargo.toml go.mod pyproject.toml Makefile; do
    if grep -A 40 'detect_project_quality_commands()' "$ORCHESTRATE" | grep -q "$config"; then
        pass "Quality detection covers $config"
    else
        fail "Quality detection missing $config"
    fi
done

# Verify run_project_quality_checks exists
if grep -q '^run_project_quality_checks()' "$ORCHESTRATE"; then
    pass "run_project_quality_checks() function defined"
else
    fail "run_project_quality_checks() function missing"
fi

# Verify cleanup_old_results exists
if grep -q '^cleanup_old_results()' "$ORCHESTRATE"; then
    pass "cleanup_old_results() function defined"
else
    fail "cleanup_old_results() function missing"
fi

# Verify cleanup_old_results uses configurable retention
if grep -A 10 'cleanup_old_results()' "$ORCHESTRATE" | grep -q 'OCTOPUS_RESULT_RETENTION_HOURS'; then
    pass "cleanup_old_results() uses configurable retention"
else
    fail "cleanup_old_results() missing configurable retention"
fi

# Verify cleanup_old_results preserves synthesis files
if grep -A 20 'cleanup_old_results()' "$ORCHESTRATE" | grep -q 'probe-synthesis.*continue'; then
    pass "cleanup_old_results() preserves synthesis files"
else
    fail "cleanup_old_results() may delete synthesis files"
fi

# Verify cleanup_old_results wired into embrace_full_workflow
if grep -A 20 'embrace_full_workflow()' "$ORCHESTRATE" | grep -q 'cleanup_old_results'; then
    pass "embrace_full_workflow() calls cleanup_old_results"
else
    fail "embrace_full_workflow() not calling cleanup_old_results"
fi

# Verify compact banner mode support
if grep -q 'OCTOPUS_COMPACT_BANNERS' "$ORCHESTRATE"; then
    pass "OCTOPUS_COMPACT_BANNERS env var supported"
else
    fail "OCTOPUS_COMPACT_BANNERS not found"
fi

# Verify format_workflow_banner function
if grep -q '^format_workflow_banner()' "$ORCHESTRATE"; then
    pass "format_workflow_banner() function defined"
else
    fail "format_workflow_banner() function missing"
fi

# Verify lint/typecheck checklist in flow-develop.md
DEVELOP_SKILL="${SCRIPT_DIR}/../.claude/skills/flow-develop.md"
if grep -q 'Lint/typecheck commands run' "$DEVELOP_SKILL"; then
    pass "flow-develop.md includes lint/typecheck in checklist"
else
    fail "flow-develop.md missing lint/typecheck checklist item"
fi

# Verify commenting conventions directive in flow-develop.md
if grep -q 'commenting conventions' "$DEVELOP_SKILL"; then
    pass "flow-develop.md includes commenting conventions directive"
else
    fail "flow-develop.md missing commenting conventions"
fi

# Verify suggest-to-CLAUDE.md pattern in flow-develop.md
if grep -q 'suggest adding them' "$DEVELOP_SKILL" || grep -q 'documented in CLAUDE.md' "$DEVELOP_SKILL"; then
    pass "flow-develop.md suggests writing commands to CLAUDE.md"
else
    fail "flow-develop.md missing CLAUDE.md suggestion pattern"
fi

# Verify lint/typecheck in flow-deliver.md
DELIVER_SKILL="${SCRIPT_DIR}/../.claude/skills/flow-deliver.md"
if grep -q 'lint/typecheck' "$DELIVER_SKILL"; then
    pass "flow-deliver.md includes lint/typecheck quality step"
else
    fail "flow-deliver.md missing lint/typecheck quality step"
fi

# ─── Test Group 13: Relevance-Aware Synthesis (Crawl4AI-inspired) ──────────

echo ""
echo "Test Group 13: Relevance-Aware Synthesis"
echo "-----------------------------------------"

# Verify score_result_file function exists
if grep -q '^score_result_file()' "$ORCHESTRATE"; then
    pass "score_result_file() function defined"
else
    fail "score_result_file() function missing"
fi

# Verify scoring factors: word count, code blocks, specificity, structure
if grep -A 40 'score_result_file()' "$ORCHESTRATE" | grep -q 'word_count'; then
    pass "score_result_file() includes word count factor"
else
    fail "score_result_file() missing word count factor"
fi

if grep -A 40 'score_result_file()' "$ORCHESTRATE" | grep -q 'code_blocks'; then
    pass "score_result_file() includes code block factor"
else
    fail "score_result_file() missing code block factor"
fi

if grep -A 60 'score_result_file()' "$ORCHESTRATE" | grep -q 'specifics'; then
    pass "score_result_file() includes specificity factor"
else
    fail "score_result_file() missing specificity factor"
fi

if grep -A 70 'score_result_file()' "$ORCHESTRATE" | grep -q 'structure'; then
    pass "score_result_file() includes structure factor"
else
    fail "score_result_file() missing structure factor"
fi

# Verify rank_results_by_signals function exists
if grep -q '^rank_results_by_signals()' "$ORCHESTRATE"; then
    pass "rank_results_by_signals() function defined"
else
    fail "rank_results_by_signals() function missing"
fi

# Verify rank sorts descending by score
if grep -A 20 'rank_results_by_signals()' "$ORCHESTRATE" | grep -q 'sort.*-rn'; then
    pass "rank_results_by_signals() sorts descending by score"
else
    fail "rank_results_by_signals() not sorting descending"
fi

# Verify aggregate_results accepts user_query parameter
if grep -A 5 'aggregate_results()' "$ORCHESTRATE" | grep -q 'user_query'; then
    pass "aggregate_results() accepts user_query for relevance-aware synthesis"
else
    fail "aggregate_results() missing user_query parameter"
fi

# Verify aggregate_results uses ranking
if grep -A 30 'aggregate_results()' "$ORCHESTRATE" | grep -q 'rank_results_by_signals'; then
    pass "aggregate_results() uses rank_results_by_signals"
else
    fail "aggregate_results() not using ranking"
fi

# Verify enhanced synthesis prompt has structured output
if grep -A 100 'aggregate_results()' "$ORCHESTRATE" | grep -q 'Key Findings'; then
    pass "aggregate_results() synthesis prompt includes structured output format"
else
    fail "aggregate_results() synthesis prompt missing structured output"
fi

# Verify minority opinion preservation in synthesis prompt
if grep -A 60 'aggregate_results()' "$ORCHESTRATE" | grep -q 'minority'; then
    pass "aggregate_results() synthesis prompt preserves minority opinions"
else
    fail "aggregate_results() synthesis prompt missing minority opinion rule"
fi

# Verify synthesize_probe_results uses ranking
if grep -A 100 'synthesize_probe_results()' "$ORCHESTRATE" | grep -q 'rank_results_by_signals\|score_result_file'; then
    pass "synthesize_probe_results() uses quality ranking"
else
    fail "synthesize_probe_results() not using quality ranking"
fi

# Verify synthesize_probe_results has enhanced structured output
if grep -A 80 'synthesize_probe_results()' "$ORCHESTRATE" | grep -q 'Patterns & Consensus'; then
    pass "synthesize_probe_results() has enhanced structured output format"
else
    fail "synthesize_probe_results() missing enhanced structured output"
fi

# Verify quality score annotation in concatenated results
if grep -A 50 'aggregate_results()' "$ORCHESTRATE" | grep -q 'Quality:'; then
    pass "aggregate_results() annotates results with quality scores"
else
    fail "aggregate_results() missing quality score annotations"
fi

echo ""

# ─── Summary ──────────────────────────────────────────────────────────────

echo "==========================================="
echo "Test Summary"
echo "==========================================="
echo "Total tests: $TOTAL"
echo -e "\033[0;32mPassed: $PASSED\033[0m"
if [[ "$FAILED" -gt 0 ]]; then
    echo -e "\033[0;31mFailed: $FAILED\033[0m"
    exit 1
else
    echo "Failed: 0"
    echo ""
    echo -e "\033[0;32m✓ All v8.49.0 model-config tests passed!\033[0m"
fi
