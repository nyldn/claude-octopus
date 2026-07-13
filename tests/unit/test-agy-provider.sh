#!/bin/bash
# tests/unit/test-agy-provider.sh
# Tests Antigravity CLI (agy) provider configuration and integration.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../helpers/test-framework.sh"

test_suite "Antigravity CLI Provider"

test_agy_config_exists() {
    test_case "Provider config file exists at config/providers/agy/CLAUDE.md"

    if [[ -f "$PROJECT_ROOT/config/providers/agy/CLAUDE.md" ]]; then
        test_pass
    else
        test_fail "missing config/providers/agy/CLAUDE.md"
    fi
}

test_agy_available_agent() {
    test_case "AVAILABLE_AGENTS includes agy aliases"

    if grep 'AVAILABLE_AGENTS=' "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -q ' agy ' && \
       grep 'AVAILABLE_AGENTS=' "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -q 'agy-research' && \
       grep 'AVAILABLE_AGENTS=' "$PROJECT_ROOT/scripts/orchestrate.sh" | grep -q 'antigravity'; then
        test_pass
    else
        test_fail "agy, agy-research, and antigravity should be available agents"
    fi
}

test_agy_dispatch_native_flags() {
    test_case "dispatch.sh uses native agy helper"

    # The adapter builds flags incrementally from a bare `agy` and appends
    # --print LAST with the prompt as its argument — current agy ignores stdin
    # in print mode, and a leading --print would eat the next flag as the
    # message.
    if grep -q 'scripts/helpers/agy-exec.sh' "$PROJECT_ROOT/scripts/lib/dispatch.sh" && \
       grep -q 'cmd=(agy)' "$PROJECT_ROOT/scripts/helpers/agy-exec.sh" && \
       grep -q -- '--print "$prompt_content"' "$PROJECT_ROOT/scripts/helpers/agy-exec.sh"; then
        test_pass
    else
        test_fail "agy dispatch should use scripts/helpers/agy-exec.sh with the prompt as --print's argument"
    fi
}


test_agy_dynamic_model_validation() {
    test_case "explicit agy model pins validate against agy models"

    local tmp_bin="$TEST_TMP_DIR/agy-dynamic-model-bin"
    local capture="$TEST_TMP_DIR/agy-argv.txt"
    mkdir -p "$tmp_bin"
    cat > "$tmp_bin/agy" <<'MOCK_AGY'
#!/usr/bin/env bash
if [[ "${1:-}" == "models" ]]; then
    printf '%s\n' \
        'Gemini 3.5 Flash (Low)' \
        'Gemini 3.5 Flash (Medium)' \
        'Claude Sonnet 4.6 (Thinking)'
    exit 0
fi
printf '%s\n' "$@" > "${AGY_ARG_CAPTURE:?}"
exit 0
MOCK_AGY
    chmod +x "$tmp_bin/agy"

    local old_path="$PATH"
    local old_home="$HOME"
    local had_log=0
    PATH="$tmp_bin:$PATH"
    AGY_ARG_CAPTURE="$capture"
    export AGY_ARG_CAPTURE

    if declare -F log >/dev/null 2>&1; then
        had_log=1
        eval "$(declare -f log | sed '1s/^log/__octo_saved_log/')"
    fi

    restore_agy_dynamic_model_env() {
        PATH="$old_path"
        HOME="$old_home"
        unset AGY_ARG_CAPTURE
        unset -f log 2>/dev/null || true
        if [[ "$had_log" == "1" ]] && declare -F __octo_saved_log >/dev/null 2>&1; then
            eval "$(declare -f __octo_saved_log | sed '1s/^__octo_saved_log/log/')"
            unset -f __octo_saved_log 2>/dev/null || true
        fi
    }

    log() { :; }
    source "$PROJECT_ROOT/scripts/lib/model-resolver.sh"

    if ! validate_agy_model_name 'Gemini 3.5 Flash (Low)'; then
        restore_agy_dynamic_model_env
        test_fail "real agy labels from agy models should be accepted"
        return
    fi
    if validate_model_name 'Gemini 3.5 Flash (Low)'; then
        restore_agy_dynamic_model_env
        test_fail "generic model validator should remain strict for shell-token providers"
        return
    fi
    if validate_agy_model_name 'Gemini 9 Unknown (Low)' >/dev/null 2>&1; then
        restore_agy_dynamic_model_env
        test_fail "agy labels absent from agy models should be rejected"
        return
    fi

    local resolved=""
    OCTOPUS_AGY_MODEL='Gemini 3.5 Flash (Low)'
    if ! resolved="$(resolve_octopus_model agy agy tangle decomposer)"; then
        unset OCTOPUS_AGY_MODEL
        restore_agy_dynamic_model_env
        test_fail "resolver failed for explicit agy label"
        return
    fi
    unset OCTOPUS_AGY_MODEL
    if [[ "$resolved" != 'Gemini 3.5 Flash (Low)' ]]; then
        restore_agy_dynamic_model_env
        test_fail "resolver should return explicit agy labels validated from agy models"
        return
    fi

    OCTOPUS_AGY_MODEL='Gemini 3.5 Flash (Low)'
    if ! resolved="$(resolve_octopus_model agy-research agy tangle decomposer)"; then
        unset OCTOPUS_AGY_MODEL
        restore_agy_dynamic_model_env
        test_fail "resolver failed for explicit agy-research label"
        return
    fi
    unset OCTOPUS_AGY_MODEL
    if [[ "$resolved" != 'Gemini 3.5 Flash (Low)' ]]; then
        restore_agy_dynamic_model_env
        test_fail "agy-research should use agy-specific env validation"
        return
    fi

    local config_dir="$TEST_TMP_DIR/agy-config-home"
    mkdir -p "$config_dir/.claude-octopus/config"
    cat > "$config_dir/.claude-octopus/config/providers.json" <<'JSON'
{"providers":{"agy":{"default":"Gemini 3.5 Flash (Medium)"}}}
JSON
    HOME="$config_dir"
    if ! resolved="$(resolve_octopus_model agy-research agy tangle decomposer)"; then
        HOME="$old_home"
        restore_agy_dynamic_model_env
        test_fail "resolver failed for config-resolved agy-research label"
        return
    fi
    HOME="$old_home"
    if [[ "$resolved" != 'Gemini 3.5 Flash (Medium)' ]]; then
        restore_agy_dynamic_model_env
        test_fail "config-resolved agy-research labels should use agy-specific provider lookups"
        return
    fi

    # The adapter refuses promptless dispatch (a promptless print-mode agy
    # answers from its own instruction-file context — the degenerate-seat
    # failure), so every invocation must pipe a prompt. Whitespace-only stdin
    # must count as promptless too: $(<file) strips trailing whitespace, so a
    # byte-size check alone would pass '\n' through as an empty --print value.
    : > "$capture"
    local ws_rc=0
    printf '\n  \n' | bash "$PROJECT_ROOT/scripts/helpers/agy-exec.sh" 2>/dev/null || ws_rc=$?
    if [[ "$ws_rc" -ne 2 || -s "$capture" ]]; then
        restore_agy_dynamic_model_env
        test_fail "whitespace-only stdin should be refused as promptless (rc=$ws_rc)"
        return
    fi

    printf 'ping' | OCTOPUS_AGY_MODEL='agy/default' bash "$PROJECT_ROOT/scripts/helpers/agy-exec.sh"
    if grep -q -- '--model' "$capture"; then
        restore_agy_dynamic_model_env
        test_fail "agy/default should not be passed to agy --model"
        return
    fi

    printf 'ping' | OCTOPUS_AGY_MODEL='Gemini 3.5 Flash (Low)' bash "$PROJECT_ROOT/scripts/helpers/agy-exec.sh"
    # 'ping' appearing in argv is the discriminating check for prompt-as-argument
    # delivery: pre-fix, the prompt went to stdin (which agy ignores) and never
    # reached argv, so this fails on the pre-fix adapter.
    if grep -Fxq -- '--model' "$capture" && grep -Fxq -- 'Gemini 3.5 Flash (Low)' "$capture" && \
       grep -Fxq -- '--print' "$capture" && grep -Fxq -- 'ping' "$capture"; then
        restore_agy_dynamic_model_env
        test_pass
    else
        restore_agy_dynamic_model_env
        test_fail "explicit agy model labels should be one --model argument and the prompt must reach argv via --print"
    fi
}
test_agy_command_validation() {
    test_case "command validator allows agy dispatch"

    if grep -q 'scripts/helpers/agy-exec.sh' "$PROJECT_ROOT/scripts/lib/utils.sh"; then
        test_pass
    else
        test_fail "utils.sh should allow agy command dispatch"
    fi
}

test_agy_dispatch_not_gemini_wrapper() {
    test_case "agy dispatch does not use Gemini-specific flags"

    local agy_block
    agy_block="$(sed -n '/agy|agy-research|antigravity)/,/;;/p' "$PROJECT_ROOT/scripts/lib/dispatch.sh")"$'\n'"$(cat "$PROJECT_ROOT/scripts/helpers/agy-exec.sh")"

    if [[ "$agy_block" != *"gemini-exec.sh"* ]] && \
       [[ "$agy_block" != *"-o text"* ]] && \
       [[ "$agy_block" != *"--approval-mode yolo"* ]]; then
        test_pass
    else
        test_fail "agy should not be wrapped as Gemini CLI"
    fi
}

test_agy_provider_detection() {
    test_case "provider detection includes agy"

    if grep -q 'octo_provider_allowed agy' "$PROJECT_ROOT/scripts/lib/providers.sh" && \
       grep -q 'command -v agy' "$PROJECT_ROOT/scripts/lib/providers.sh" && \
       grep -q 'agy:cli' "$PROJECT_ROOT/scripts/lib/providers.sh"; then
        test_pass
    else
        test_fail "providers.sh should detect agy"
    fi
}

test_agy_inherits_environment() {
    test_case "provider routing isolates agy by default with full-env opt-in"

    local agy_block
    agy_block="$(sed -n '/agy\*|antigravity)/,/;;/p' "$PROJECT_ROOT/scripts/lib/provider-routing.sh")"

    if [[ "$agy_block" == *"OCTOPUS_ALLOW_FULL_AGY_ENV"* ]] && \
       [[ "$agy_block" == *"PROVIDER_ENV_ARRAY=(env -i"* ]] && \
       [[ "$agy_block" == *"AGY_AUTH_TOKEN"* ]] && \
       [[ "$agy_block" == *"AGY_CONFIG"* ]] && \
       [[ "$agy_block" == *"ANTIGRAVITY_API_KEY"* ]] && \
       [[ "$agy_block" == *"PROVIDER_ENV_ARRAY=()"* ]]; then
        test_pass
    else
        test_fail "agy should isolate by default and support OCTOPUS_ALLOW_FULL_AGY_ENV=true"
    fi
}

test_agy_spawn_bypasses_timeout_wrapper() {
    test_case "spawn enforces timeout wrapper for agy"

    if grep -q 'agent_type.*agy' "$PROJECT_ROOT/scripts/lib/spawn.sh" && \
       sed -n '/agent_type.*agy/,/elif printf/p' "$PROJECT_ROOT/scripts/lib/spawn.sh" | grep -q 'run_with_timeout'; then
        test_pass
    else
        test_fail "spawn.sh should wrap agy in run_with_timeout"
    fi
}

test_agy_sync_bypasses_timeout_wrapper() {
    test_case "sync dispatch enforces timeout wrapper for agy"

    if grep -q 'agent_type.*agy' "$PROJECT_ROOT/scripts/lib/agent-sync.sh" && \
       sed -n '/agent_type.*agy/,/elif.*gemini/p' "$PROJECT_ROOT/scripts/lib/agent-sync.sh" | grep -q 'run_with_timeout'; then
        test_pass
    else
        test_fail "agent-sync.sh should wrap agy in run_with_timeout"
    fi
}

test_agy_spawn_cli_uses_sync_dispatch() {
    test_case "orchestrate spawn routes agy through sync dispatch"

    if grep -q 'Antigravity CLI print mode does not emit output from background jobs' "$PROJECT_ROOT/scripts/orchestrate.sh" && \
       grep -q 'run_agent_sync "$1" "$2" "$TIMEOUT" "none" "spawn"' "$PROJECT_ROOT/scripts/orchestrate.sh"; then
        test_pass
    else
        test_fail "orchestrate.sh spawn should run agy synchronously"
    fi
}

test_agy_check_providers() {
    test_case "check-providers reports agy"

    if grep -q 'provider_status "agy"' "$PROJECT_ROOT/scripts/helpers/check-providers.sh"; then
        test_pass
    else
        test_fail "check-providers.sh should report agy status"
    fi
}

test_agy_doctor_provider_check() {
    test_case "doctor reports agy provider status"

    if [[ -x "$PROJECT_ROOT/scripts/doctor.sh" ]] && \
       grep -q 'agy-cli' "$PROJECT_ROOT/scripts/lib/doctor.sh" && \
       grep -q 'OCTO_AGY_MIN_VERSION' "$PROJECT_ROOT/scripts/lib/provider-versions.sh" && \
       grep -q 'Antigravity CLI' "$PROJECT_ROOT/.claude/skills/skill-doctor/SKILL.md" && \
       grep -q 'Antigravity CLI' "$PROJECT_ROOT/skills/skill-doctor/SKILL.md"; then
        test_pass
    else
        test_fail "doctor should expose agy provider diagnostics and user-facing guidance"
    fi
}

test_agy_setup_visibility() {
    test_case "setup command shows Antigravity provider"

    if grep -q 'printf "agy:%s' "$PROJECT_ROOT/commands/setup.md" && \
       grep -q 'Antigravity CLI (agy)' "$PROJECT_ROOT/commands/setup.md"; then
        test_pass
    else
        test_fail "setup should detect and offer Antigravity CLI"
    fi
}

test_agy_status_visibility() {
    test_case "status dashboard shows Antigravity provider"

    if grep -q 'PROVIDER_AGY_INSTALLED' "$PROJECT_ROOT/scripts/lib/smoke.sh" && \
       grep -q 'Antigravity:' "$PROJECT_ROOT/scripts/lib/smoke.sh"; then
        test_pass
    else
        test_fail "status should show Antigravity provider"
    fi
}

test_agy_fleet_scoring() {
    test_case "smoke fleet scoring can select agy"

    local scorer_block select_block
    scorer_block="$(sed -n '/score_provider()/,/^}/p' "$PROJECT_ROOT/scripts/lib/smoke.sh")"
    select_block="$(sed -n '/select_provider()/,/^}/p' "$PROJECT_ROOT/scripts/lib/smoke.sh")"

    if [[ "$scorer_block" == *"agy)"* ]] && \
       [[ "$scorer_block" == *"PROVIDER_AGY_INSTALLED"* ]] && \
       [[ "$select_block" == *"codex gemini agy claude opencode openrouter"* ]] && \
       [[ "$select_block" == *'echo "agy"'* ]]; then
        test_pass
    else
        test_fail "score_provider/select_provider should include agy"
    fi
}

test_agy_smoke_defaults() {
    test_case "smoke defaults keep agy and opencode priorities distinct"

    if grep -q 'PROVIDER_AGY_TIER="subscription"' "$PROJECT_ROOT/scripts/lib/smoke.sh" && \
       grep -q 'PROVIDER_AGY_TIER="${PROVIDER_AGY_TIER:-subscription}"' "$PROJECT_ROOT/scripts/lib/smoke.sh" && \
       grep -q 'PROVIDER_AGY_COST_TIER="${PROVIDER_AGY_COST_TIER:-bundled}"' "$PROJECT_ROOT/scripts/lib/smoke.sh" && \
       ! grep -q 'PROVIDER_AGY_TIER="${OCTOPUS_AGY_MODEL' "$PROJECT_ROOT/scripts/lib/smoke.sh" && \
       grep -q 'PROVIDER_OPENCODE_PRIORITY="${PROVIDER_OPENCODE_PRIORITY:-5}"' "$PROJECT_ROOT/scripts/lib/smoke.sh"; then
        test_pass
    else
        test_fail "smoke defaults should use agy subscription tier and opencode priority 5"
    fi
}

test_agy_preflight_visibility() {
    test_case "preflight reports Antigravity provider"

    if grep -q 'AGY_STATUS=ok' "$PROJECT_ROOT/scripts/lib/preflight.sh" && \
       grep -q 'Antigravity: Installed' "$PROJECT_ROOT/scripts/lib/preflight.sh"; then
        test_pass
    else
        test_fail "preflight should report Antigravity provider"
    fi
}

test_agy_fleet_builder() {
    test_case "build-fleet includes agy as distinct provider family"

    if grep -q 'google-antigravity' "$PROJECT_ROOT/scripts/helpers/build-fleet.sh" && \
       grep -q 'AVAILABLE_CLI+=(agy)' "$PROJECT_ROOT/scripts/helpers/build-fleet.sh"; then
        test_pass
    else
        test_fail "build-fleet.sh should include agy provider family and availability"
    fi
}

test_agy_allowlist_alias() {
    test_case "provider allowlist accepts agy and antigravity"

    if grep -q 'agy|antigravity' "$PROJECT_ROOT/scripts/lib/provider-allowlist.sh"; then
        test_pass
    else
        test_fail "provider allowlist should accept agy and antigravity"
    fi
}

test_agy_routing_resolver() {
    test_case "routing resolver accepts agy debate participants"

    if grep -q 'agy|agy-research|antigravity' "$PROJECT_ROOT/scripts/lib/routing.sh" && \
       grep -q 'Antigravity' "$PROJECT_ROOT/scripts/lib/routing.sh"; then
        test_pass
    else
        test_fail "routing.sh should resolve agy debate participants"
    fi
}

test_agy_external_output_wrapped() {
    test_case "agy output is wrapped as untrusted external CLI output"

    if grep -q 'agy.*antigravity' "$PROJECT_ROOT/scripts/lib/validation.sh"; then
        test_pass
    else
        test_fail "validation.sh should wrap agy output"
    fi
}

test_agy_issue_reference() {
    test_case "agy provider config references issue #423"

    if grep -q '#423' "$PROJECT_ROOT/config/providers/agy/CLAUDE.md"; then
        test_pass
    else
        test_fail "provider config should reference #423"
    fi
}

test_agy_docs_cost_and_marker() {
    test_case "docs show agy cost controls and distinct provider marker"

    if grep -q 'OCTOPUS_AGY_MODEL' "$PROJECT_ROOT/CLAUDE.md" && \
       grep -q 'Five providers cost nothing extra' "$PROJECT_ROOT/README.md" && \
       grep -q '🧭 Antigravity CLI (`agy`)' "$PROJECT_ROOT/README.md" && \
       ! grep -q '🟢 Antigravity CLI (`agy`)' "$PROJECT_ROOT/README.md"; then
        test_pass
    else
        test_fail "docs should document agy cost/model behavior and use a distinct provider marker"
    fi
}

test_agy_slash_command_visibility() {
    test_case "commands and skills include agy in provider-facing prompts"

    if grep -q 'Codex, Gemini, and Antigravity' "$PROJECT_ROOT/commands/security.md" && \
       grep -q 'command -v agy' "$PROJECT_ROOT/commands/plan.md" && \
       grep -q 'command -v agy' "$PROJECT_ROOT/commands/review.md" && \
       grep -q 'command -v agy' "$PROJECT_ROOT/commands/factory.md" && \
       grep -q 'command -v agy' "$PROJECT_ROOT/commands/auto.md" && \
       grep -q 'checkCommandAvailable.*agy' "$PROJECT_ROOT/commands/multi.md" && \
       grep -q 'Antigravity CLI' "$PROJECT_ROOT/commands/brainstorm.md" && \
       grep -q 'Antigravity (agy)' "$PROJECT_ROOT/commands/model-config.md" && \
       grep -q 'claude,codex,gemini,agy' "$PROJECT_ROOT/commands/council.md" && \
       grep -q 'Antigravity CLI' "$PROJECT_ROOT/commands/debate.md" && \
       grep -q 'Antigravity CLI' "$PROJECT_ROOT/.claude/skills/flow-discover/SKILL.md" && \
       grep -q 'Antigravity CLI' "$PROJECT_ROOT/.claude/skills/flow-develop/SKILL.md" && \
       grep -q 'Antigravity CLI' "$PROJECT_ROOT/.claude/skills/flow-define/SKILL.md" && \
       grep -q 'Antigravity CLI' "$PROJECT_ROOT/.claude/skills/flow-deliver/SKILL.md" && \
       grep -q 'Antigravity CLI' "$PROJECT_ROOT/.claude/skills/skill-debate/SKILL.md" && \
       grep -q 'Antigravity CLI' "$PROJECT_ROOT/docs/COMMAND-REFERENCE.md" && \
       grep -q 'Antigravity CLI' "$PROJECT_ROOT/SECURITY.md" && \
       grep -q 'up to 9 AI CLIs' "$PROJECT_ROOT/PRODUCT.md" && \
       grep -q 'Six providers can cost nothing extra' "$PROJECT_ROOT/PRODUCT.md" && \
       grep -q 'codex gemini agy' "$PROJECT_ROOT/tests/test-fleet-diversity.sh" && \
       grep -q 'codex, gemini, agy' "$PROJECT_ROOT/tests/unit/test-research-fanout-static.sh"; then
        test_pass
    else
        test_fail "provider-facing commands, skills, and docs should expose agy alongside other external providers"
    fi
}

test_agy_slash_command_no_stale_three_provider_copy() {
    test_case "commands, skills, and docs avoid stale Codex/Gemini-only multi-LLM copy"

    local stale
    stale=$(grep -R -nE 'Claude \+ Codex \+ Gemini|Codex \+ Gemini \+ Claude|Codex \+ Gemini|Codex/Gemini|Codex and Gemini|all three AI|all three providers|three-model|four-way debate|four-way debates|configure Codex and Gemini|2/3 providers|Providers: 🔴 Codex \| 🟡 Gemini \| 🔵 Claude|Providers: Codex \| Gemini \| Claude|\(🔴 🟡 🔵\)' \
        "$PROJECT_ROOT/commands" "$PROJECT_ROOT/.claude/skills" "$PROJECT_ROOT/docs" "$PROJECT_ROOT/README.md" "$PROJECT_ROOT/.claude-plugin/README.md" "$PROJECT_ROOT/SECURITY.md" "$PROJECT_ROOT/PRODUCT.md" "$PROJECT_ROOT/tests/test-fleet-diversity.sh" "$PROJECT_ROOT/tests/unit/test-research-fanout-static.sh" \
        | grep -v 'commands/resume.md' \
        | grep -v 'commands/extract.md:.*Extract all 8 features' \
        | grep -v 'docs/superpowers/specs/' \
        | grep -v 'docs/superpowers/plans/' \
        | grep -v 'docs/COMMAND-REFERENCE.md:.*transcripts' || true)

    if [[ -z "$stale" ]]; then
        test_pass
    else
        test_fail "stale provider copy remains: $stale"
    fi
}

test_agy_debate_skill_uses_runtime_advisors() {
    test_case "debate skill uses runtime advisor routing instead of hardcoded Gemini"

    local debate_files=(
        "$PROJECT_ROOT/.claude/skills/skill-debate/SKILL.md"
        "$PROJECT_ROOT/skills/skill-debate/SKILL.md"
    )
    local stale
    stale=$(grep -nE 'ADVISORS="gemini,codex"|Consult Gemini|gemini -p|r001_gemini|GEMINI_RESPONSE|Gemini/Codex CLI|Codex/Gemini|codex exec --skip-git-repo-check|when available when available' "${debate_files[@]}" || true)

    if [[ -z "$stale" ]] && \
       grep -q 'orchestrate.sh" spawn "$advisor"' "$PROJECT_ROOT/.claude/skills/skill-debate/SKILL.md" && \
       grep -q 'command -v agy' "$PROJECT_ROOT/.claude/skills/skill-debate/SKILL.md" && \
       grep -q 'claude\*|codex\*|gemini\*|agy\*' "$PROJECT_ROOT/.claude/skills/skill-debate/SKILL.md" && \
       grep -q 'orchestrate.sh" spawn "$advisor"' "$PROJECT_ROOT/skills/skill-debate/SKILL.md" && \
       grep -q 'command -v agy' "$PROJECT_ROOT/skills/skill-debate/SKILL.md" && \
       grep -q 'claude\*|codex\*|gemini\*|agy\*' "$PROJECT_ROOT/skills/skill-debate/SKILL.md"; then
        test_pass
    else
        test_fail "debate skill should dispatch runtime advisors through orchestrate.sh and include agy fallback; stale copy: $stale"
    fi
}

test_user_facing_docs_route_external_provider_dispatch() {
    test_case "user-facing commands and skills route external provider dispatch through Octopus"

    local stale
    stale=$(grep -R -nE 'codex exec --skip-git-repo-check|gemini -p "" -o text|ADVISORS="gemini,codex"|GEMINI_RESPONSE|r001_gemini|Gemini/Codex CLI|Codex/Gemini' \
        "$PROJECT_ROOT/commands" \
        "$PROJECT_ROOT/.claude/skills" \
        "$PROJECT_ROOT/.cursor-plugin/commands" \
        "$PROJECT_ROOT/skills" \
        | grep -v 'codex --full-auto' \
        | grep -v 'codex -q' \
        | grep -v 'codex -y' \
        | grep -v 'gemini -y' || true)

    if [[ -z "$stale" ]]; then
        test_pass
    else
        test_fail "direct provider dispatch remains in user-facing docs: $stale"
    fi
}

test_provider_aware_commands_show_core_provider_status() {
    test_case "provider-aware slash commands show Codex, Gemini, Antigravity, and Perplexity status"

    local missing=""
    local commands=(
        auto
        brainstorm
        embrace
        factory
        plan
        review
    )

    local command
    for command in "${commands[@]}"; do
        local claude_file="$PROJECT_ROOT/commands/${command}.md"
        local cursor_file="$PROJECT_ROOT/.cursor-plugin/commands/octo-${command}.md"
        if [[ ! -f "$cursor_file" && "$command" == "auto" ]]; then
            cursor_file="$PROJECT_ROOT/.cursor-plugin/commands/octo.md"
        fi

        for file in "$claude_file" "$cursor_file"; do
            if [[ ! -f "$file" ]]; then
                missing+="${file}: file missing"$'\n'
                continue
            fi

            grep -q 'Codex CLI: \[Available ✓ / Not installed ✗\]' "$file" || missing+="${file}: missing Codex status"$'\n'
            grep -q 'Gemini CLI: \[Available ✓ / Not installed ✗\]' "$file" || missing+="${file}: missing Gemini status"$'\n'
            grep -q 'Antigravity CLI: \[Available ✓ / Not installed ✗\]' "$file" || missing+="${file}: missing Antigravity status"$'\n'
            grep -q 'Perplexity: \[Configured ✓ / Not configured ✗\]' "$file" || missing+="${file}: missing Perplexity status"$'\n'
        done
    done

    if [[ -z "$missing" ]]; then
        test_pass
    else
        test_fail "provider-aware slash command banners must show core provider statuses: $missing"
    fi
}

test_review_command_generates_antigravity_banner() {
    test_case "review command renders Antigravity status from provider probe"

    local missing=""
    local files=(
        "$PROJECT_ROOT/commands/review.md"
        "$PROJECT_ROOT/.cursor-plugin/commands/octo-review.md"
    )

    local file
    for file in "${files[@]}"; do
        grep -q 'Do not hand-write or summarize this banner' "$file" || missing+="${file}: missing generated-banner instruction"$'\n'
        grep -q 'agy_status="$(status_cli agy)"' "$file" || missing+="${file}: missing agy status assignment"$'\n'
        grep -q '🧭 Antigravity CLI: ${agy_status}' "$file" || missing+="${file}: missing rendered Antigravity status line"$'\n'
    done

    if [[ -z "$missing" ]]; then
        test_pass
    else
        test_fail "review command must render Antigravity in the provider banner: $missing"
    fi
}

test_provider_aware_commands_generate_antigravity_banners() {
    test_case "provider-aware commands generate Antigravity-visible banners"

    local missing=""
    local commands=(
        auto
        brainstorm
        embrace
        factory
        plan
        review
    )

    local command
    for command in "${commands[@]}"; do
        local claude_file="$PROJECT_ROOT/commands/${command}.md"
        local cursor_file="$PROJECT_ROOT/.cursor-plugin/commands/octo-${command}.md"
        for file in "$claude_file" "$cursor_file"; do
            grep -q 'Do not hand-write or summarize this' "$file" || missing+="${file}: missing generated-banner instruction"$'\n'
            grep -q 'agy_status="$(status_cli agy)"' "$file" || missing+="${file}: missing agy status assignment"$'\n'
            grep -q 'Antigravity.*${agy_status}' "$file" || missing+="${file}: missing rendered Antigravity status line"$'\n'
        done
    done

    for file in "$PROJECT_ROOT/commands/setup.md" "$PROJECT_ROOT/.cursor-plugin/commands/octo-setup.md"; do
        grep -q 'Do not hand-write or summarize this provider block' "$file" || missing+="${file}: missing generated setup table instruction"$'\n'
        grep -q 'agy_status="$(status_installed agy)"' "$file" || missing+="${file}: missing setup agy status assignment"$'\n'
        grep -q '🧭 Antigravity:    ${agy_status}' "$file" || missing+="${file}: missing setup Antigravity status line"$'\n'
    done

    if [[ -z "$missing" ]]; then
        test_pass
    else
        test_fail "provider-aware commands must generate Antigravity-visible banners: $missing"
    fi
}

test_provider_workflow_review_regressions() {
    test_case "provider workflow snippets avoid Round 2 review regressions"

    local missing=""
    local brainstorm_files=(
        "$PROJECT_ROOT/commands/brainstorm.md"
        "$PROJECT_ROOT/.cursor-plugin/commands/octo-brainstorm.md"
    )

    local file
    for file in "${brainstorm_files[@]}"; do
        grep -q 'ORCH_HELP="$("$ORCH" 2>&1 || true)"' "$file" || missing+="${file}: missing pipefail-safe orchestrator probe"$'\n'
        grep -q 'trap '\''rm -rf "$RUN_DIR"'\'' EXIT' "$file" || missing+="${file}: missing tempdir cleanup trap"$'\n'
        grep -q 'claude\*|codex\*|gemini\*|agy\*' "$file" || missing+="${file}: missing claude advisor allowlist"$'\n'
    done

    grep -q 'CLAUDE_PLUGIN_ROOT:-' "$PROJECT_ROOT/commands/setup.md" || missing+="commands/setup.md: setup root not plugin-anchored"$'\n'
    grep -q 'CLAUDE_PLUGIN_ROOT:-' "$PROJECT_ROOT/.cursor-plugin/commands/octo-setup.md" || missing+=".cursor-plugin/commands/octo-setup.md: setup root not plugin-anchored"$'\n'

    if grep -R -n '\${agy_status}' "$PROJECT_ROOT/.claude/skills/flow-deliver" "$PROJECT_ROOT/skills/flow-deliver" >/dev/null 2>&1; then
        missing+="flow-deliver: stale agy_status placeholder remains"$'\n'
    fi

    if grep -R -n -- '--rounds 3' "$PROJECT_ROOT/.claude/skills/flow-define" "$PROJECT_ROOT/skills/flow-define" >/dev/null 2>&1; then
        missing+="flow-define: restored debate should not use --rounds 3"$'\n'
    fi

    if [[ -z "$missing" ]]; then
        test_pass
    else
        test_fail "provider workflow review regressions remain: $missing"
    fi
}

test_agy_config_exists
test_agy_available_agent
test_agy_dispatch_native_flags
test_agy_dynamic_model_validation
test_agy_command_validation
test_agy_dispatch_not_gemini_wrapper
test_agy_provider_detection
test_agy_inherits_environment
test_agy_spawn_bypasses_timeout_wrapper
test_agy_sync_bypasses_timeout_wrapper
test_agy_spawn_cli_uses_sync_dispatch
test_agy_check_providers
test_agy_doctor_provider_check
test_agy_setup_visibility
test_agy_status_visibility
test_agy_fleet_scoring
test_agy_smoke_defaults
test_agy_preflight_visibility
test_agy_fleet_builder
test_agy_allowlist_alias
test_agy_routing_resolver
test_agy_external_output_wrapped
test_agy_issue_reference
test_agy_docs_cost_and_marker
test_agy_slash_command_visibility
test_agy_slash_command_no_stale_three_provider_copy
test_agy_debate_skill_uses_runtime_advisors
test_user_facing_docs_route_external_provider_dispatch
test_provider_aware_commands_show_core_provider_status
test_review_command_generates_antigravity_banner
test_provider_aware_commands_generate_antigravity_banners
test_provider_workflow_review_regressions

test_summary
