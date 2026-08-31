#!/usr/bin/env bash
# Claude Octopus — Environment Doctor Diagnostics
# Extracted from orchestrate.sh
# Source-safe: no main execution block, and no `set -e`/`set -o pipefail` —
# shell options set here would leak into the sourcing shell and persist.

if ! declare -f _is_cursor_agent_binary >/dev/null 2>&1; then
    _doctor_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${_doctor_lib_dir}/cursor-agent.sh" 2>/dev/null || true
fi

if ! declare -f octo_graphify_status_json >/dev/null 2>&1; then
    _doctor_lib_dir="${_doctor_lib_dir:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
    source "${_doctor_lib_dir}/graphify.sh" 2>/dev/null || true
fi

if ! declare -f qwen_auth_method >/dev/null 2>&1; then
    _doctor_lib_dir="${_doctor_lib_dir:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
    source "${_doctor_lib_dir}/auth.sh" 2>/dev/null || true
    source "${_doctor_lib_dir}/qwen.sh" 2>/dev/null || true
fi

if ! declare -f octo_plugin_update_load >/dev/null 2>&1; then
    _doctor_lib_dir="${_doctor_lib_dir:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
    source "${_doctor_lib_dir}/plugin-update.sh" 2>/dev/null || true
fi

if ! declare -f _octo_bare_auth_probe >/dev/null 2>&1; then
    _doctor_lib_dir="${_doctor_lib_dir:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
    source "${_doctor_lib_dir}/providers.sh" 2>/dev/null || true
fi

if ! declare -f octo_provider_readiness_result >/dev/null 2>&1; then
    _doctor_lib_dir="${_doctor_lib_dir:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
    source "${_doctor_lib_dir}/preflight.sh" 2>/dev/null || true
fi

# ═══════════════════════════════════════════════════════════════════════════════
# MODULAR DOCTOR SYSTEM (v8.16.0)
# 14 check categories, structured results, category filtering, JSON output
# ═══════════════════════════════════════════════════════════════════════════════

# Result accumulator (parallel arrays for bash 3.x compat)
DOCTOR_RESULTS_NAME=()
DOCTOR_RESULTS_CAT=()
DOCTOR_RESULTS_STATUS=()   # pass|warn|fail
DOCTOR_RESULTS_MSG=()
DOCTOR_RESULTS_DETAIL=()
DOCTOR_AGY_LIVE_AUTH_STATUS="not-run"
DOCTOR_PROVIDER_READINESS=()
DOCTOR_PROVIDER_READINESS_KIND=""

doctor_add() {
    local name="$1" cat="$2" status="$3" msg="$4" detail="${5:-}"
    DOCTOR_RESULTS_NAME+=("$name")
    DOCTOR_RESULTS_CAT+=("$cat")
    DOCTOR_RESULTS_STATUS+=("$status")
    DOCTOR_RESULTS_MSG+=("$msg")
    DOCTOR_RESULTS_DETAIL+=("$detail")
}

_doctor_collect_provider_readiness() {
    local check_kind="static" result
    [[ "${DOCTOR_LIVE_PROBE:-false}" == "true" ]] && check_kind="live"
    if [[ "$DOCTOR_PROVIDER_READINESS_KIND" == "$check_kind" && ${#DOCTOR_PROVIDER_READINESS[@]} -gt 0 ]]; then
        return 0
    fi
    DOCTOR_PROVIDER_READINESS=()
    while IFS= read -r result; do
        [[ -n "$result" ]] && DOCTOR_PROVIDER_READINESS+=("$result")
    done < <(octo_provider_readiness_all "$check_kind")
    DOCTOR_PROVIDER_READINESS_KIND="$check_kind"
}

_doctor_provider_result_name() {
    case "$1" in
        codex) printf '%s\n' "codex-cli" ;;
        agy) printf '%s\n' "agy-cli" ;;
        perplexity) printf '%s\n' "perplexity-api" ;;
        ollama) printf '%s\n' "ollama" ;;
        copilot) printf '%s\n' "copilot-cli" ;;
        qwen) printf '%s\n' "qwen-cli" ;;
        cursor-agent) printf '%s\n' "cursor-agent" ;;
        grok) printf '%s\n' "grok" ;;
        vibe) printf '%s\n' "vibe-cli" ;;
        opencode) printf '%s\n' "opencode-cli" ;;
        *) printf '%s-readiness\n' "$1" ;;
    esac
}

doctor_check_plugin_validation() {
    local plugin_root="${1:-${PLUGIN_DIR:-}}" output="" help_output="" rc=0 detail=""
    local strict_flag="" probe_timeout term_timeout kill_grace=0
    [[ -n "$plugin_root" ]] || plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

    if ! command -v claude >/dev/null 2>&1; then
        doctor_add "plugin-validation" "config" "info" \
            "Strict Claude plugin validation unavailable" "Install Claude Code to run: claude plugin validate $plugin_root"
        return 0
    fi

    probe_timeout="$(_octo_bare_probe_timeout "${OCTOPUS_PLUGIN_VALIDATE_TIMEOUT:-20}")"
    term_timeout="$probe_timeout"
    if [[ "$probe_timeout" -gt 2 ]]; then
        kill_grace=2
        term_timeout=$((probe_timeout - kill_grace))
    fi
    help_output="$(_octo_run_bare_probe_with_timeout \
        "$probe_timeout" "$term_timeout" "$kill_grace" \
        claude plugin validate --help </dev/null 2>&1 || true)"
    [[ "$help_output" == *"--strict"* ]] && strict_flag="--strict"
    if [[ -n "$strict_flag" ]]; then
        output="$(_octo_run_bare_probe_with_timeout \
            "$probe_timeout" "$term_timeout" "$kill_grace" \
            claude plugin validate "$strict_flag" "$plugin_root" </dev/null 2>&1)" || rc=$?
    else
        output="$(_octo_run_bare_probe_with_timeout \
            "$probe_timeout" "$term_timeout" "$kill_grace" \
            claude plugin validate "$plugin_root" </dev/null 2>&1)" || rc=$?
    fi
    detail="$(printf '%s\n' "$output" | sed -n '1,5p')"
    if [[ "$rc" -eq 0 ]]; then
        doctor_add "plugin-validation" "config" "pass" \
            "Strict plugin validation passed" "${detail:-claude plugin validate accepted $plugin_root}"
    else
        doctor_add "plugin-validation" "config" "fail" \
            "Strict plugin validation failed (exit $rc)" "${detail:-Run: claude plugin validate $plugin_root}"
    fi
}

_doctor_iso_epoch() {
    local timestamp="${1:-}" epoch=""
    [[ -n "$timestamp" ]] || { printf '0\n'; return; }
    epoch="$(date -u -d "$timestamp" +%s 2>/dev/null)" || epoch=""
    if [[ ! "$epoch" =~ ^[0-9]+$ ]]; then
        epoch="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$timestamp" +%s 2>/dev/null)" || epoch=""
    fi
    [[ "$epoch" =~ ^[0-9]+$ ]] && printf '%s\n' "$epoch" || printf '0\n'
}

doctor_check_v10_state_health() {
    local workspace="${WORKSPACE_DIR:-${HOME}/.claude-octopus}" cache_dir=""
    local now stale_after snapshot seat_id timestamp _transition epoch
    local running_ids="" running_count=0 stale_count=0 invalid_snapshot_count=0
    local snapshot_rows=""
    local pid_file="${PID_FILE:-${workspace}/pids}" pid _agent task
    local orphan_count=0 stale_pid_count=0

    if type octo_probe_cache_dir >/dev/null 2>&1; then
        cache_dir="$(octo_probe_cache_dir 2>/dev/null || true)"
    fi
    [[ -n "$cache_dir" ]] || cache_dir="${workspace%/}/.cache/probe-results"
    if [[ -d "$cache_dir" && -w "$cache_dir" ]]; then
        doctor_add "probe-cache-writable" "state" "pass" "Probe cache writable" "$cache_dir"
    elif [[ ! -e "$cache_dir" && -d "$workspace" && -w "$workspace" ]]; then
        doctor_add "probe-cache-writable" "state" "pass" "Probe cache can be created" "$cache_dir"
    else
        doctor_add "probe-cache-writable" "state" "fail" "Probe cache is not writable" "$cache_dir"
    fi

    now="$(date +%s)"
    stale_after="${OCTOPUS_RUNNING_STALE_SECONDS:-900}"
    [[ "$stale_after" =~ ^[0-9]+$ ]] || stale_after=900
    if command -v jq >/dev/null 2>&1 && [[ -d "$workspace/runs" ]]; then
        for snapshot in "$workspace"/runs/*/seats.json; do
            [[ -f "$snapshot" ]] || continue
            if ! snapshot_rows="$(jq -r '.seats[]? | select(.transition | IN("contributed", "degraded", "skipped", "failed", "timeout", "cancelled") | not) | [.seat_id, .transition, (.timestamp // "")] | @tsv' "$snapshot" 2>/dev/null)"; then
                ((invalid_snapshot_count++)) || true
                continue
            fi
            while IFS=$'\t' read -r seat_id _transition timestamp; do
                [[ -n "$seat_id" ]] || continue
                ((running_count++)) || true
                running_ids="${running_ids}${running_ids:+$'\n'}${seat_id}"
                epoch="$(_doctor_iso_epoch "$timestamp")"
                if [[ "$epoch" -eq 0 || $((now - epoch)) -gt "$stale_after" ]]; then
                    ((stale_count++)) || true
                fi
            done <<< "$snapshot_rows"
        done
    fi
    if [[ "$invalid_snapshot_count" -gt 0 ]]; then
        doctor_add "invalid-run-snapshots" "state" "warn" \
            "$invalid_snapshot_count unreadable or malformed run snapshot(s)" \
            "Inspect ${workspace}/runs; malformed state was excluded from stale-run analysis"
    fi
    if [[ "$stale_count" -gt 0 ]]; then
        doctor_add "stale-running-records" "state" "warn" \
            "$stale_count stale non-terminal run record(s)" \
            "Inspect ${workspace}/runs; resume or cancel explicitly before retrying"
    else
        doctor_add "stale-running-records" "state" "pass" \
            "No stale non-terminal run records" "${running_count} active non-terminal record(s)"
    fi

    if [[ -f "$pid_file" ]]; then
        while IFS=: read -r pid _agent task; do
            [[ "$pid" =~ ^[0-9]+$ ]] || continue
            if kill -0 "$pid" 2>/dev/null; then
                if ! grep -Fxc "spawn-${task}" <<< "$running_ids" >/dev/null && \
                   ! grep -Fxc "$task" <<< "$running_ids" >/dev/null; then
                    ((orphan_count++)) || true
                fi
            else
                ((stale_pid_count++)) || true
            fi
        done < "$pid_file"
    fi
    if [[ "$orphan_count" -gt 0 ]]; then
        doctor_add "orphan-processes" "state" "warn" \
            "$orphan_count live provider process(es) lack a matching run record" \
            "Inspect $pid_file and cancel by recorded PID only after confirming ownership"
    else
        doctor_add "orphan-processes" "state" "pass" "No orphan provider process evidence" "$pid_file"
    fi
    if [[ "$stale_pid_count" -gt 0 ]]; then
        doctor_add "stale-pid-records" "state" "warn" \
            "$stale_pid_count stale PID record(s)" \
            "Repair proposal: remove dead entries from $pid_file after explicit confirmation; preserve the original until an atomic replacement succeeds"
    fi
}

doctor_check_agy_live() {
    local octo_root="$1"
    local probe_timeout term_timeout kill_grace catalog="" model="" output=""
    local catalog_rc=0 model_rc=0 dispatch_rc=0

    DOCTOR_AGY_LIVE_AUTH_STATUS="fail"
    if ! command -v agy >/dev/null 2>&1; then
        doctor_add "agy-live-install" "providers" "warn" \
            "AGY live probe skipped because the CLI is not installed" \
            "Install Antigravity CLI, then rerun: octopus doctor providers --live"
        return
    fi

    probe_timeout="$(_octo_bare_probe_timeout "${OCTOPUS_AGY_HEALTH_TIMEOUT:-30}")"
    term_timeout="$probe_timeout"
    kill_grace=0
    if [[ "$probe_timeout" -gt 2 ]]; then
        kill_grace=2
        term_timeout=$((probe_timeout - kill_grace))
    fi

    catalog="$(_octo_run_bare_probe_with_timeout \
        "$probe_timeout" "$term_timeout" "$kill_grace" \
        agy models </dev/null 2>&1)" || catalog_rc=$?
    if [[ "$catalog_rc" -ne 0 || ! "$catalog" =~ [^[:space:]] ]]; then
        doctor_add "agy-live-catalog" "providers" "warn" \
            "AGY catalog/keyring authentication failed (exit ${catalog_rc})" \
            "Launch plain 'agy' in a terminal and finish its browser sign-in. On macOS, if access is denied, open Keychain Access, find the Antigravity CLI item, and allow agy under Access Control."
        return
    fi
    doctor_add "agy-live-catalog" "providers" "pass" \
        "AGY catalog and keyring authentication succeeded" \
        "agy models returned a live catalog within ${probe_timeout}s"
    DOCTOR_AGY_LIVE_AUTH_STATUS="pass"

    if ! declare -f resolve_octopus_model >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        source "${octo_root}/scripts/lib/model-resolver.sh" 2>/dev/null || true
    fi
    if ! declare -f log >/dev/null 2>&1; then
        log() { :; }
    fi
    if declare -f resolve_octopus_model >/dev/null 2>&1; then
        model="$(OCTOPUS_AGY_MODELS_TIMEOUT="$probe_timeout" \
            resolve_octopus_model agy agy doctor health 2>/dev/null)" || model_rc=$?
    else
        model_rc=127
    fi
    if [[ "$model_rc" -ne 0 || ! "$model" =~ [^[:space:]] ]]; then
        doctor_add "agy-live-model" "providers" "warn" \
            "AGY configured model did not resolve against the live catalog" \
            "Run 'agy models', then set OCTOPUS_AGY_MODEL to an exact returned ID or label; use 'default' for AGY's service-selected model."
        return
    fi
    doctor_add "agy-live-model" "providers" "pass" \
        "AGY configured model resolved: ${model}" \
        "Validated against the live agy models catalog"

    output="$(_octo_run_bare_probe_with_timeout \
        "$probe_timeout" "$term_timeout" "$kill_grace" \
        env "OCTOPUS_AGY_MODEL=${model}" \
            "OCTOPUS_AGY_PRINT_TIMEOUT=${probe_timeout}s" \
            "OCTOPUS_AGY_NO_RETRY=1" \
            bash "${octo_root}/scripts/helpers/agy-exec.sh" \
        <<'AGY_HEALTH_PROMPT' 2>&1
Return these two tokens in your response:
OCTOPUS_AGY_HEALTH_OK
LOCAL_PROVIDER_DISPATCH_WORKS
AGY_HEALTH_PROMPT
    )" || dispatch_rc=$?

    if [[ "$dispatch_rc" -eq 0 && "$output" == *"OCTOPUS_AGY_HEALTH_OK"* && \
          "$output" == *"LOCAL_PROVIDER_DISPATCH_WORKS"* ]]; then
        doctor_add "agy-live-dispatch" "providers" "pass" \
            "AGY print-mode dispatch returned substantive output" \
            "Model ${model}; bounded to ${probe_timeout}s"
    else
        doctor_add "agy-live-dispatch" "providers" "warn" \
            "AGY print-mode dispatch failed or returned incomplete output (exit ${dispatch_rc})" \
            "Run plain 'agy' to repair authentication, confirm the model with 'agy models', then rerun: octopus doctor providers --live"
    fi
}

# --- Category 1: Providers ---
# v8.39.0: Update external CLI dependencies to latest versions
cmd_update_clis() {
    echo -e "${CYAN}🐙 Claude Octopus — CLI Update${NC}"
    echo ""

    local updated=0 failed=0

    # Update Codex CLI
    echo -e "  ${YELLOW}→${NC} Updating Codex CLI (@openai/codex)..."
    if npm install -g @openai/codex 2>&1 | sed 's/^/    /'; then
        local codex_ver
        codex_ver=$(codex --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        echo -e "  ${GREEN}✓${NC} Codex CLI updated to v${codex_ver}"
        ((updated++))
    else
        echo -e "  ${RED}✗${NC} Codex CLI update failed. Try manually: npm install -g @openai/codex"
        ((failed++))
    fi
    echo ""

    # Update Antigravity CLI (the sole Google seat)
    echo -e "  ${YELLOW}→${NC} Updating Antigravity CLI..."
    if command -v agy >/dev/null 2>&1 && agy update 2>&1 | sed 's/^/    /'; then
        local agy_ver
        agy_ver=$(agy --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        echo -e "  ${GREEN}✓${NC} Antigravity CLI updated to v${agy_ver}"
        ((updated++))
    else
        echo -e "  ${RED}✗${NC} Antigravity CLI update failed or agy is not installed. Try manually: agy update"
        ((failed++))
    fi
    echo ""

    # Summary
    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}✅ All CLIs updated successfully (${updated} packages)${NC}"
    else
        echo -e "${YELLOW}⚠ ${updated} updated, ${failed} failed${NC}"
    fi
}

doctor_check_providers() {
    local readiness provider status reason remediation result_name doctor_status check_kind
    local _doctor_lib_dir _octo_root
    _doctor_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _octo_root="${OCTO_ROOT:-$(cd "${_doctor_lib_dir}/../.." && pwd)}"
    check_kind="static"
    [[ "${DOCTOR_LIVE_PROBE:-false}" == "true" ]] && check_kind="live"

    _doctor_collect_provider_readiness
    for readiness in "${DOCTOR_PROVIDER_READINESS[@]}"; do
        provider="$(jq -r '.provider' <<<"$readiness")"
        status="$(jq -r '.status' <<<"$readiness")"
        reason="$(jq -r '.reason_code' <<<"$readiness")"
        remediation="$(jq -r '.remediation' <<<"$readiness")"
        result_name="$(_doctor_provider_result_name "$provider")"
        case "$status" in
            available) doctor_status="pass" ;;
            degraded) doctor_status="warn" ;;
            *) doctor_status="info" ;;
        esac
        doctor_add "$result_name" "providers" "$doctor_status" \
            "$provider is $status ($reason; $check_kind check)" "$remediation"
    done

    # AGY's explicit live Doctor stages provide catalog, model, and deterministic
    # dispatch evidence beyond the generic registry health handler.
    if [[ "${DOCTOR_LIVE_PROBE:-false}" == "true" ]]; then
        doctor_check_agy_live "$_octo_root"
    fi
    return 0
}

# --- Category 1b: Optional companions ---
doctor_check_companions() {
    if ! declare -f octo_graphify_status_json >/dev/null 2>&1; then
        doctor_add "graphify-companion" "companions" "info" \
            "Graphify companion unavailable" "scripts/lib/graphify.sh not loaded"
        return 0
    fi

    local project_root status installed version bin graph_exists report_exists needs_update out_dir hook_status
    project_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
    status=$(octo_graphify_status_json "$project_root" 2>/dev/null || true)
    if [[ -z "$status" ]]; then
        doctor_add "graphify-companion" "companions" "info" \
            "Graphify companion disabled" "Set OCTOPUS_GRAPHIFY=1 to re-enable"
        return 0
    fi

    installed=$(printf '%s' "$status" | jq -r '.installed')
    version=$(printf '%s' "$status" | jq -r '.version')
    bin=$(printf '%s' "$status" | jq -r '.bin')
    graph_exists=$(printf '%s' "$status" | jq -r '.graph_exists')
    report_exists=$(printf '%s' "$status" | jq -r '.report_exists')
    needs_update=$(printf '%s' "$status" | jq -r '.needs_update')
    out_dir=$(printf '%s' "$status" | jq -r '.out_dir')
    hook_status=$(printf '%s' "$status" | jq -r '.hook_status // ""')

    if [[ "$installed" == "true" ]]; then
        doctor_add "graphify-cli" "companions" "pass" \
            "Graphify CLI installed (v${version})" "$bin"
    else
        doctor_add "graphify-cli" "companions" "info" \
            "Graphify CLI not installed (optional)" "uv tool install graphifyy"
    fi

    if [[ "$graph_exists" == "true" && "$report_exists" == "true" ]]; then
        doctor_add "graphify-graph" "companions" "pass" \
            "Graphify graph available" "$out_dir"
    elif [[ "$graph_exists" == "true" || "$report_exists" == "true" ]]; then
        doctor_add "graphify-graph" "companions" "warn" \
            "Graphify output incomplete" "Expected both graph.json and GRAPH_REPORT.md under $out_dir"
    else
        doctor_add "graphify-graph" "companions" "info" \
            "No Graphify graph for this project" "Run graphify extract . when a graph map would help"
    fi

    if [[ "$needs_update" == "true" ]]; then
        doctor_add "graphify-freshness" "companions" "warn" \
            "Graphify graph may be stale" "needs_update flag present under $out_dir"
    elif [[ "$graph_exists" == "true" ]]; then
        doctor_add "graphify-freshness" "companions" "pass" \
            "No Graphify stale flag found" "$out_dir"
    else
        doctor_add "graphify-freshness" "companions" "info" \
            "Graphify freshness not applicable" "No graphify-out graph found"
    fi

    if [[ "$installed" == "true" && -n "$hook_status" ]]; then
        doctor_add "graphify-hooks" "companions" "info" \
            "Graphify hook status checked" "$hook_status"
    fi
}

# --- Category 2: Auth ---
doctor_check_auth() {
    local readiness provider status remediation any_auth=false result_name doctor_status
    _doctor_collect_provider_readiness
    for readiness in "${DOCTOR_PROVIDER_READINESS[@]}"; do
        provider="$(jq -r '.provider' <<<"$readiness")"
        status="$(jq -r '.status' <<<"$readiness")"
        remediation="$(jq -r '.remediation' <<<"$readiness")"
        case "$provider" in
            codex) result_name="codex-auth" ;;
            agy) result_name="agy-auth" ;;
            cursor-agent) result_name="cursor-agent-auth" ;;
            perplexity) result_name="perplexity-auth" ;;
            *) continue ;;
        esac

        if [[ "$provider" == "agy" && "${DOCTOR_LIVE_PROBE:-false}" == "true" &&
              "$DOCTOR_AGY_LIVE_AUTH_STATUS" != "pass" ]]; then
            doctor_status="fail"
            status="not verified by the live catalog"
            remediation="Launch plain 'agy' and complete browser sign-in; on macOS, allow agy to access the Antigravity CLI item in Keychain Access"
        elif [[ "$status" == "available" ]]; then
            doctor_status="pass"
            any_auth=true
        elif [[ "$status" == "degraded" ]]; then
            doctor_status="fail"
        else
            continue
        fi
        doctor_add "$result_name" "auth" "$doctor_status" \
            "$provider authentication is $status" "$remediation"
    done

    if [[ "$any_auth" == "true" ]]; then
        doctor_add "any-provider-auth" "auth" "pass" \
            "At least one provider credential is configured" ""
    else
        doctor_add "any-provider-auth" "auth" "fail" \
            "No provider authenticated" "Configure one provider with /octo:setup."
    fi

    local backend="${OCTOPUS_BACKEND:-api}"
    if [[ "$backend" != "api" ]]; then
        doctor_add "enterprise-backend" "auth" "pass" "Enterprise backend: $backend" ""
    fi
    return 0
}

# --- Category 3: Config ---
doctor_check_config() {
    local plugin_json="$SCRIPT_DIR/../.claude-plugin/plugin.json"

    # Plugin version
    local plugin_ver
    plugin_ver=$(jq -r '.version' "$plugin_json" 2>/dev/null || echo "unknown")
    if [[ "$plugin_ver" != "unknown" ]]; then
        doctor_add "plugin-version" "config" "pass" \
            "Plugin v${plugin_ver}" ""
    else
        doctor_add "plugin-version" "config" "fail" \
            "Cannot read plugin version" "$plugin_json"
    fi

    # Install scope
    local scope="unknown"
    if [[ "$PLUGIN_DIR" == "$HOME/.claude/plugins/"* ]]; then
        scope="user"
    elif [[ "$PLUGIN_DIR" == *"/.claude/plugins/"* ]]; then
        scope="project"
    else
        scope="manual/dev"
    fi
    doctor_add "install-scope" "config" "pass" \
        "Install scope: $scope" "$PLUGIN_DIR"

    # Feature flag / CC version consistency
    local cc_ver="${CLAUDE_CODE_VERSION:-}"
    if [[ -n "$cc_ver" ]]; then
        # Check SUPPORTS_SONNET_46 should be true on v2.1.45+
        if version_compare "$cc_ver" "2.1.45" ">=" 2>/dev/null && [[ "$SUPPORTS_SONNET_46" != "true" ]]; then
            doctor_add "flag-sonnet-46" "config" "warn" \
                "SUPPORTS_SONNET_46 is false on CC v${cc_ver}" \
                "Expected true for v2.1.45+; feature detection may have failed"
        fi
        # Check SUPPORTS_STABLE_BG_AGENTS should be true on v2.1.47+
        if version_compare "$cc_ver" "2.1.47" ">=" 2>/dev/null && [[ "$SUPPORTS_STABLE_BG_AGENTS" != "true" ]]; then
            doctor_add "flag-stable-bg" "config" "warn" \
                "SUPPORTS_STABLE_BG_AGENTS is false on CC v${cc_ver}" \
                "Expected true for v2.1.47+; feature detection may have failed"
        fi
        # Check SUPPORTS_CONFIG_CHANGE_HOOK should be true on v2.1.49+
        if version_compare "$cc_ver" "2.1.49" ">=" 2>/dev/null && [[ "$SUPPORTS_CONFIG_CHANGE_HOOK" != "true" ]]; then
            doctor_add "flag-config-change" "config" "warn" \
                "SUPPORTS_CONFIG_CHANGE_HOOK is false on CC v${cc_ver}" \
                "Expected true for v2.1.49+; feature detection may have failed"
        fi
        # Check SUPPORTS_WORKTREE_ISOLATION should be true on v2.1.50+
        if version_compare "$cc_ver" "2.1.50" ">=" 2>/dev/null && [[ "$SUPPORTS_WORKTREE_ISOLATION" != "true" ]]; then
            doctor_add "flag-worktree" "config" "warn" \
                "SUPPORTS_WORKTREE_ISOLATION is false on CC v${cc_ver}" \
                "Expected true for v2.1.50+; feature detection may have failed"
        fi
        # Check SUPPORTS_HTTP_HOOKS should be true on v2.1.63+
        if version_compare "$cc_ver" "2.1.63" ">=" 2>/dev/null && [[ "$SUPPORTS_HTTP_HOOKS" != "true" ]]; then
            doctor_add "flag-http-hooks" "config" "warn" \
                "SUPPORTS_HTTP_HOOKS is false on CC v${cc_ver}" \
                "Expected true for v2.1.63+; feature detection may have failed"
        fi

        # v2.1.78+ checks
        if version_compare "$cc_ver" "2.1.78" ">=" 2>/dev/null; then
            if [[ "$SUPPORTS_STOP_FAILURE_HOOK" != "true" ]]; then
                doctor_add "flag-stop-failure" "config" "warn" \
                    "SUPPORTS_STOP_FAILURE_HOOK is false on CC v${cc_ver}" \
                    "Expected true for v2.1.78+; StopFailure hook enables API error telemetry"
            fi
            if [[ -z "${CLAUDE_PLUGIN_DATA:-}" ]]; then
                doctor_add "plugin-data-dir" "config" "info" \
                    "CLAUDE_PLUGIN_DATA not set — using legacy ~/.claude-octopus/" \
                    "CC v2.1.78+ provides persistent plugin state via \${CLAUDE_PLUGIN_DATA}"
            fi
        fi

        # v2.1.83+ checks
        if version_compare "$cc_ver" "2.1.83" ">=" 2>/dev/null; then
            if [[ "$SUPPORTS_CWD_CHANGED_HOOK" != "true" ]]; then
                doctor_add "flag-cwd-changed" "config" "warn" \
                    "SUPPORTS_CWD_CHANGED_HOOK is false on CC v${cc_ver}" \
                    "Expected true for v2.1.83+; CwdChanged enables automatic context re-detection"
            fi
        fi
    fi

    # Agent Teams enable check
    if [[ "${SUPPORTS_AGENT_TEAMS:-false}" == "true" && "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-0}" != "1" ]]; then
        doctor_add "agent-teams-disabled" "config" "info" \
            "Agent Teams supported but not enabled" \
            "Set CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 in settings.json env to enable CC native agent teams for /octo:parallel"
    fi

    # v9.13: Circuit breaker state check
    local _cb_dir="${CLAUDE_PLUGIN_DATA:-${WORKSPACE_DIR:-${HOME}/.claude-octopus}}/provider-state"
    if [[ -d "$_cb_dir" ]]; then
        local _open_circuits=""
        for _sf in "$_cb_dir"/*.state; do
            [[ -f "$_sf" ]] || continue
            local _prov _state
            _prov=$(basename "$_sf" .state)
            _state=$(<"$_sf" 2>/dev/null)
            if [[ "$_state" == "open" ]]; then
                _open_circuits="${_open_circuits:+$_open_circuits, }$_prov"
            fi
        done
        if [[ -n "$_open_circuits" ]]; then
            doctor_add "circuit-breaker-open" "providers" "warn" \
                "Circuit breaker OPEN for: $_open_circuits" \
                "These providers hit failure thresholds and are temporarily skipped. They auto-recover after cooldown."
        else
            doctor_add "circuit-breaker-state" "providers" "pass" \
                "All provider circuits closed (healthy)" ""
        fi
    fi

    # Legacy plugin name detection (Issue #196)
    # Users who installed as "claude-octopus@nyldn-plugins" (pre-v9.0 name) get
    # "Plugin claude-octopus not found in marketplace" because the marketplace
    # now lists the plugin as "octo". Detect this and provide the fix.
    local legacy_cache_dir="$HOME/.claude/plugins/cache/nyldn-plugins/claude-octopus"
    if [[ -d "$legacy_cache_dir" ]]; then
        doctor_add "legacy-plugin-name" "config" "fail" \
            "Legacy 'claude-octopus' install detected — causes 'not found in marketplace'" \
            "Fix: claude plugin uninstall claude-octopus && claude plugin install octo@nyldn-plugins"
    elif [[ "$PLUGIN_DIR" == *"/claude-octopus"* && "$PLUGIN_DIR" != *"/claude-octopus/"*"octo"* ]]; then
        # Catch installs where the directory name contains the old name
        doctor_add "legacy-plugin-name" "config" "warn" \
            "Plugin path contains legacy name 'claude-octopus'" \
            "If you see 'not found in marketplace': claude plugin uninstall claude-octopus && claude plugin install octo@nyldn-plugins"
    else
        doctor_add "legacy-plugin-name" "config" "pass" \
            "Plugin name: octo (correct)" ""
    fi

    # OCTOPUS_BACKEND correctly detected
    local backend="${OCTOPUS_BACKEND:-api}"
    doctor_add "backend-detection" "config" "pass" \
        "Backend: $backend" ""

    # v9.36: CC v2.1.126-129 compatibility checks
    if [[ "${SUPPORTS_GATEWAY_MODEL_DISCOVERY:-false}" == "true" ]]; then
        if [[ -n "${ANTHROPIC_BASE_URL:-}" && "${CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY:-0}" != "1" ]]; then
            doctor_add "gateway-model-discovery" "config" "warn" \
                "Gateway model discovery is opt-in on current Claude Code" \
                "ANTHROPIC_BASE_URL is set; set CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1 to populate /model from /v1/models"
        elif [[ -n "${ANTHROPIC_BASE_URL:-}" ]]; then
            doctor_add "gateway-model-discovery" "config" "pass" \
                "Gateway model discovery enabled" "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1"
        else
            doctor_add "gateway-model-discovery" "config" "info" \
                "Gateway model discovery available" "Set ANTHROPIC_BASE_URL plus CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1 for compatible gateways"
        fi
    fi

    if [[ "${SUPPORTS_FORCE_SYNC_OUTPUT:-false}" == "true" ]]; then
        if [[ "${CLAUDE_CODE_FORCE_SYNC_OUTPUT:-0}" == "1" ]]; then
            doctor_add "force-sync-output" "config" "pass" \
                "Synchronized terminal output forced" "CLAUDE_CODE_FORCE_SYNC_OUTPUT=1"
        else
            doctor_add "force-sync-output" "config" "info" \
                "CC v2.1.129 CLAUDE_CODE_FORCE_SYNC_OUTPUT available" \
                "Set CLAUDE_CODE_FORCE_SYNC_OUTPUT=1 if your terminal misses synchronized-output auto-detection"
        fi
    fi

    if [[ "${SUPPORTS_PACKAGE_MANAGER_AUTO_UPDATE:-false}" == "true" ]]; then
        if [[ "${CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE:-0}" == "1" ]]; then
            doctor_add "package-manager-auto-update" "config" "pass" \
                "Claude Code package-manager auto-update enabled" "CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE=1"
        else
            doctor_add "package-manager-auto-update" "config" "info" \
                "CC v2.1.129 package-manager auto-update available" \
                "Set CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE=1 for Homebrew/WinGet installs to prompt after background upgrades"
        fi
    fi

    if [[ "${SUPPORTS_EXPERIMENTAL_MANIFEST_KEYS:-false}" == "true" ]] && command -v jq &>/dev/null; then
        if jq -e 'has("themes") or has("monitors")' "$plugin_json" >/dev/null 2>&1; then
            doctor_add "experimental-manifest-keys" "config" "warn" \
                "Plugin manifest still uses top-level themes/monitors" \
                "CC v2.1.129 validates these under experimental.themes / experimental.monitors"
        else
            doctor_add "experimental-manifest-keys" "config" "pass" \
                "No top-level themes/monitors manifest keys" "CC v2.1.129 experimental manifest layout is clean"
        fi
    fi

    if [[ "${SUPPORTS_MCP_WORKSPACE_RESERVED:-false}" == "true" ]] && command -v jq &>/dev/null; then
        local _workspace_mcp_files=""
        local _mcp_file
        for _mcp_file in "$PLUGIN_DIR/.mcp.json" "$PWD/.mcp.json" "$HOME/.claude/settings.json" "$HOME/.claude/settings.local.json"; do
            [[ -f "$_mcp_file" ]] || continue
            if jq -e '.mcpServers.workspace? // empty' "$_mcp_file" >/dev/null 2>&1; then
                _workspace_mcp_files="${_workspace_mcp_files:+$_workspace_mcp_files, }$_mcp_file"
            fi
        done
        if [[ -n "$_workspace_mcp_files" ]]; then
            doctor_add "mcp-workspace-reserved" "config" "warn" \
                "MCP server named 'workspace' will be skipped by Claude Code" \
                "Rename mcpServers.workspace in: $_workspace_mcp_files"
        else
            doctor_add "mcp-workspace-reserved" "config" "pass" \
                "No reserved MCP server name 'workspace' detected" ""
        fi
    fi

    doctor_check_plugin_validation "$PLUGIN_DIR"
}

# --- Plugin update health (issue #851) ---
# Local-only by design. Network/package-manager work is reserved for the
# explicit `update-plugin` command so doctor and SessionStart stay non-blocking.
doctor_check_updates() {
    if ! declare -f octo_plugin_update_load >/dev/null 2>&1; then
        doctor_add "plugin-update-health" "updates" "info" \
            "Plugin update health unavailable" "scripts/lib/plugin-update.sh could not be loaded"
        return
    fi
    if ! command -v jq >/dev/null 2>&1; then
        doctor_add "plugin-update-dependency" "updates" "warn" \
            "Plugin update health unavailable: jq is not installed" \
            "Install jq, then rerun orchestrate.sh doctor updates"
        return
    fi

    local plugin_root="${CLAUDE_PLUGIN_ROOT:-${PLUGIN_DIR:-}}"
    local host="${OCTOPUS_HOST:-}"
    if [[ -z "$plugin_root" ]]; then
        plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    fi
    [[ -n "$host" ]] || host="$(octo_plugin_detect_host "$plugin_root")"
    octo_plugin_update_load "$plugin_root" "$host"

    if [[ "$OCTO_PLUGIN_LOADED_VERSION" == "unknown" ]]; then
        doctor_add "plugin-loaded-version" "updates" "warn" \
            "Loaded Octopus version is unknown" "Expected .claude-plugin/plugin.json under $plugin_root"
    else
        doctor_add "plugin-loaded-version" "updates" "pass" \
            "Loaded Octopus v${OCTO_PLUGIN_LOADED_VERSION}" "$plugin_root"
    fi

    if [[ "$host" == "claude" ]]; then
        case "$OCTO_PLUGIN_AUTO_UPDATE" in
            enabled)
                doctor_add "plugin-auto-update" "updates" "pass" \
                    "nyldn-plugins auto-update enabled" "Claude Code checks the marketplace in the background; reload after an update"
                ;;
            disabled|missing)
                doctor_add "plugin-auto-update" "updates" "warn" \
                    "nyldn-plugins auto-update ${OCTO_PLUGIN_AUTO_UPDATE}" \
                    "Use /plugin → Marketplaces → nyldn-plugins → Enable auto-update"
                ;;
            malformed)
                doctor_add "plugin-auto-update" "updates" "fail" \
                    "Claude marketplace state is malformed" \
                    "Repair ~/.claude/plugins/known_marketplaces.json through /plugin; do not hand-edit it during a session"
                ;;
            *)
                doctor_add "plugin-auto-update" "updates" "info" \
                    "Claude marketplace auto-update state unavailable" "No Claude marketplace state was found"
                ;;
        esac
    else
        doctor_add "plugin-auto-update" "updates" "info" \
            "Host-managed auto-update state is not exposed for ${host}" "Use the ${host} plugin manager and restart after updating"
    fi

    local versions="installed ${OCTO_PLUGIN_INSTALLED_VERSION}; catalog ${OCTO_PLUGIN_CATALOG_VERSION}; cache ${OCTO_PLUGIN_CACHE_VERSION}"
    if [[ "$OCTO_PLUGIN_RELOAD_REQUIRED" == "true" ]]; then
        doctor_add "plugin-reload" "updates" "warn" \
            "Installed Octopus v${OCTO_PLUGIN_INSTALLED_VERSION} is newer than this loaded session" \
            "Run /reload-plugins or restart the host — ${versions}"
    elif [[ "$OCTO_PLUGIN_UPDATE_AVAILABLE" == "true" ]]; then
        doctor_add "plugin-update-available" "updates" "warn" \
            "A newer Octopus version is known locally" \
            "Run orchestrate.sh update-plugin explicitly — ${versions}"
    else
        doctor_add "plugin-update-current" "updates" "pass" \
            "No newer local Octopus version detected" "$versions"
    fi
}

# --- Category 4: State ---
doctor_check_state() {
    local workflow_state_file="${STATE_FILE:-}"
    # state.json integrity
    if [[ -f "$workflow_state_file" ]]; then
        if jq empty "$workflow_state_file" 2>/dev/null; then
            doctor_add "state-json" "state" "pass" \
                "state.json valid" "$workflow_state_file"
        else
            doctor_add "state-json" "state" "fail" \
                "state.json is invalid JSON" "$workflow_state_file cannot be parsed"
        fi
    else
        doctor_add "state-json" "state" "pass" \
            "No project state (normal for new projects)" ""
    fi

    # Stale results files (older than 7 days)
    if [[ -d "${WORKSPACE_DIR}/results" ]]; then
        local stale_count
        stale_count=$(find "${WORKSPACE_DIR}/results" -name "*.md" -type f -mtime +7 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$stale_count" -gt 0 ]]; then
            doctor_add "stale-results" "state" "warn" \
                "${stale_count} result file(s) older than 7 days" \
                "In ${WORKSPACE_DIR}/results — consider cleanup with: orchestrate.sh cleanup"
        else
            doctor_add "stale-results" "state" "pass" \
                "No stale result files" ""
        fi
    fi

    # Workspace dir exists and is writable
    if [[ -d "$WORKSPACE_DIR" && -w "$WORKSPACE_DIR" ]]; then
        doctor_add "workspace-writable" "state" "pass" \
            "Workspace writable" "$WORKSPACE_DIR"
    elif [[ -d "$WORKSPACE_DIR" ]]; then
        doctor_add "workspace-writable" "state" "fail" \
            "Workspace not writable" "$WORKSPACE_DIR"
    else
        doctor_add "workspace-writable" "state" "fail" \
            "Workspace directory missing" "$WORKSPACE_DIR"
    fi

    # Preflight cache staleness
    if [[ -f "$PREFLIGHT_CACHE_FILE" ]]; then
        if preflight_cache_valid; then
            doctor_add "preflight-cache" "state" "pass" \
                "Preflight cache valid" "$PREFLIGHT_CACHE_FILE"
        else
            doctor_add "preflight-cache" "state" "warn" \
                "Preflight cache stale" "Will re-run on next workflow invocation"
        fi
    else
        doctor_add "preflight-cache" "state" "pass" \
            "No preflight cache (will create on first run)" ""
    fi

    doctor_check_v10_state_health
}

# --- Category 5: Hooks ---
doctor_check_hooks() {
    local hooks_json="$SCRIPT_DIR/../hooks/hooks.json"
    if [[ ! -f "$hooks_json" ]]; then
        doctor_add "hooks-file" "hooks" "fail" \
            "hooks.json not found" "$hooks_json"
        return
    fi

    if ! jq empty "$hooks_json" 2>/dev/null; then
        doctor_add "hooks-file" "hooks" "fail" \
            "hooks.json is invalid JSON" "$hooks_json"
        return
    fi

    doctor_add "hooks-file" "hooks" "pass" \
        "hooks.json valid" "$hooks_json"

    # Extract all command paths from hooks.json and verify each exists
    local commands
    commands=$(jq -r '.. | objects | select(.command?) | .command' "$hooks_json" 2>/dev/null | tr -d '\r' || true)
    if [[ -z "$commands" ]]; then
        return
    fi

    local hook_count=0
    local broken_count=0
    while IFS= read -r cmd_path; do
        [[ -z "$cmd_path" ]] && continue
        ((hook_count++)) || true

        # Resolve ${CLAUDE_PLUGIN_ROOT} to actual plugin dir
        local resolved_path="$cmd_path"
        resolved_path="${resolved_path//\$\{CLAUDE_PLUGIN_ROOT\}/$PLUGIN_DIR}"
        resolved_path="${resolved_path//\$CLAUDE_PLUGIN_ROOT/$PLUGIN_DIR}"

        # Handle paths with arguments, env-var prefixes, and bash wrappers
        local script_path
        # Strip leading env-var assignments (KEY=value ...)
        local cleaned="$resolved_path"
        while [[ "$cleaned" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+(.*) ]]; do
            cleaned="${BASH_REMATCH[1]}"
        done
        # Strip leading 'bash ' wrapper
        cleaned="${cleaned#bash }"
        # Remove surrounding quotes
        cleaned="${cleaned#\"}"
        cleaned="${cleaned%\"}"
        script_path=$(echo "$cleaned" | awk '{print $1}')

        if [[ ! -f "$script_path" ]]; then
            doctor_add "hook-script-$(basename "$script_path")" "hooks" "fail" \
                "Hook script missing: $(basename "$script_path")" "$cmd_path -> $script_path"
            ((broken_count++)) || true
        elif [[ ! -x "$script_path" ]]; then
            doctor_add "hook-script-$(basename "$script_path")" "hooks" "warn" \
                "Hook script not executable: $(basename "$script_path")" "$script_path"
            ((broken_count++)) || true
        fi
    done <<< "$commands"

    if [[ $broken_count -eq 0 && $hook_count -gt 0 ]]; then
        doctor_add "hook-scripts-all" "hooks" "pass" \
            "All $hook_count hook scripts valid" ""
    fi
}

# --- Category 6: Scheduler ---
doctor_check_scheduler() {
    local sched_dir="${HOME}/.claude-octopus/scheduler"
    local runtime_dir="${sched_dir}/runtime"
    local pid_file="${runtime_dir}/daemon.pid"
    local jobs_dir="${sched_dir}/jobs"
    local switches_dir="${sched_dir}/switches"

    # Daemon running check
    if [[ -f "$pid_file" ]]; then
        local daemon_pid
        daemon_pid=$(cat "$pid_file" 2>/dev/null)
        if [[ -n "$daemon_pid" ]] && kill -0 "$daemon_pid" 2>/dev/null; then
            doctor_add "scheduler-daemon" "scheduler" "pass" \
                "Scheduler daemon running" "PID $daemon_pid"
        else
            doctor_add "scheduler-daemon" "scheduler" "warn" \
                "Scheduler PID file stale" "PID $daemon_pid not running; start with /octo:scheduler start"
        fi
    else
        doctor_add "scheduler-daemon" "scheduler" "pass" \
            "Scheduler not configured (normal)" "Start with /octo:scheduler start"
    fi

    # Jobs directory
    if [[ -d "$jobs_dir" ]]; then
        local job_count
        job_count=$(find "$jobs_dir" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
        doctor_add "scheduler-jobs" "scheduler" "pass" \
            "${job_count} scheduled job(s)" "$jobs_dir"
    fi

    # Budget gate
    if [[ -n "${OCTOPUS_MAX_COST_USD:-}" ]]; then
        doctor_add "budget-gate" "scheduler" "pass" \
            "Budget gate: \$${OCTOPUS_MAX_COST_USD}/day" ""
    else
        doctor_add "budget-gate" "scheduler" "warn" \
            "No budget gate configured" "Set OCTOPUS_MAX_COST_USD to limit daily spend"
    fi

    # Kill switches
    if [[ -d "$switches_dir" ]]; then
        local kill_files
        kill_files=$(find "$switches_dir" -name "*.kill" -type f 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$kill_files" -gt 0 ]]; then
            doctor_add "kill-switches" "scheduler" "warn" \
                "${kill_files} kill switch(es) active" "Check ${switches_dir}/*.kill"
        else
            doctor_add "kill-switches" "scheduler" "pass" \
                "No kill switches active" ""
        fi
    fi
}

# --- Category 7: Skills ---
doctor_check_skills() {
    local plugin_json="$SCRIPT_DIR/../.claude-plugin/plugin.json"
    if [[ ! -f "$plugin_json" ]]; then
        doctor_add "plugin-json" "skills" "fail" \
            "plugin.json not found" "$plugin_json"
        return
    fi

    # Verify skill files exist
    local skill_total skill_missing=0
    skill_total=$(jq '.skills | length' "$plugin_json" 2>/dev/null || echo "0")
    local i=0
    while [[ $i -lt $skill_total ]]; do
        local skill_path
        skill_path=$(jq -r ".skills[$i]" "$plugin_json" 2>/dev/null)
        # Resolve relative paths from plugin dir
        local resolved="${PLUGIN_DIR}/${skill_path#./}"
        if [[ ! -e "$resolved" ]]; then
            doctor_add "skill-missing-$(basename "$skill_path")" "skills" "fail" \
                "Skill file missing: $(basename "$skill_path")" "$resolved"
            ((skill_missing++)) || true
        fi
        ((i++)) || true
    done
    if [[ $skill_missing -eq 0 ]]; then
        doctor_add "skills-all" "skills" "pass" \
            "All $skill_total skill files present" ""
    fi

    # Verify command files exist
    local cmd_total cmd_missing=0
    cmd_total=$(jq '.commands | length' "$plugin_json" 2>/dev/null || echo "0")
    i=0
    while [[ $i -lt $cmd_total ]]; do
        local cmd_path
        cmd_path=$(jq -r ".commands[$i]" "$plugin_json" 2>/dev/null)
        local resolved="${PLUGIN_DIR}/${cmd_path#./}"
        if [[ ! -f "$resolved" ]]; then
            doctor_add "cmd-missing-$(basename "$cmd_path")" "skills" "fail" \
                "Command file missing: $(basename "$cmd_path")" "$resolved"
            ((cmd_missing++)) || true
        fi
        ((i++)) || true
    done
    if [[ $cmd_missing -eq 0 ]]; then
        doctor_add "commands-all" "skills" "pass" \
            "All $cmd_total command files present" ""
    fi

    # v8.52: Warn about skill deadlock risk on CC < v2.1.73 (50 skill files)
    if [[ "$SUPPORTS_SKILL_DEADLOCK_FIX" != "true" ]]; then
        doctor_add "skill-deadlock-risk" "skills" "warn" \
            "CC < v2.1.73: git pull with $skill_total skills may cause deadlock/freeze" \
            "Upgrade to Claude Code v2.1.73+ to fix the deadlock with large .claude/skills/ directories"
    fi

    # v8.52: Surface modelOverrides setting if CC v2.1.73+ and user may benefit
    if [[ "$SUPPORTS_MODEL_OVERRIDES" == "true" ]] && [[ "$OCTOPUS_BACKEND" != "api" ]]; then
        local settings_file="${HOME}/.claude/settings.json"
        local has_overrides="false"
        if [[ -f "$settings_file" ]] && command -v jq &>/dev/null; then
            has_overrides=$(jq 'has("modelOverrides")' "$settings_file" 2>/dev/null || echo "false")
        fi
        if [[ "$has_overrides" == "true" ]]; then
            doctor_add "model-overrides-active" "skills" "pass" \
                "CC modelOverrides configured (${OCTOPUS_BACKEND} backend)" \
                "Custom model IDs will be used by CC's model picker"
        else
            doctor_add "model-overrides-tip" "skills" "info" \
                "CC v2.1.73 modelOverrides available for ${OCTOPUS_BACKEND} inference profiles" \
                "Set modelOverrides in ~/.claude/settings.json to map model names to Bedrock ARNs/Vertex endpoints"
        fi
    fi

    # v8.56: Surface /context command for context optimization tips
    if [[ "$SUPPORTS_CONTEXT_SUGGESTIONS" == "true" ]]; then
        doctor_add "context-suggestions" "skills" "info" \
            "CC v2.1.74 /context command available for context window diagnostics" \
            "Run /context in Claude Code to get actionable optimization tips for context-heavy sessions"
    fi

    # v8.56: Surface autoMemoryDirectory setting if CC v2.1.74+
    if [[ "$SUPPORTS_AUTO_MEMORY_DIR" == "true" ]]; then
        local settings_file="${HOME}/.claude/settings.json"
        local has_memory_dir="false"
        if [[ -f "$settings_file" ]] && command -v jq &>/dev/null; then
            has_memory_dir=$(jq 'has("autoMemoryDirectory")' "$settings_file" 2>/dev/null || echo "false")
        fi
        if [[ "$has_memory_dir" == "true" ]]; then
            doctor_add "auto-memory-dir" "skills" "pass" \
                "CC autoMemoryDirectory configured (custom auto-memory path)" ""
        fi
    fi

    # v8.57: Surface /effort command availability
    if [[ "$SUPPORTS_EFFORT_COMMAND" == "true" ]]; then
        doctor_add "effort-command" "skills" "info" \
            "CC v2.1.76 /effort command available for mid-session effort adjustment" \
            "Use /effort in Claude Code to change model effort level (low/medium/high) during a session"
    fi

    # v8.57: Surface worktree.sparsePaths for large monorepo optimization
    if [[ "$SUPPORTS_WORKTREE_SPARSE_PATHS" == "true" ]]; then
        local settings_file="${HOME}/.claude/settings.json"
        local has_sparse="false"
        if [[ -f "$settings_file" ]] && command -v jq &>/dev/null; then
            has_sparse=$(jq 'has("worktree") and (.worktree | has("sparsePaths"))' "$settings_file" 2>/dev/null || echo "false")
        fi
        if [[ "$has_sparse" == "true" ]]; then
            doctor_add "worktree-sparse-paths" "skills" "pass" \
                "CC worktree.sparsePaths configured (sparse checkout for --worktree)" ""
        else
            doctor_add "worktree-sparse-paths-tip" "skills" "info" \
                "CC v2.1.76 worktree.sparsePaths available for large monorepo optimization" \
                "Set worktree.sparsePaths in settings to check out only specific directories in --worktree mode"
        fi
    fi

    # v8.57: Surface MCP elicitation + PostCompact hook availability
    if [[ "$SUPPORTS_MCP_ELICITATION" == "true" ]]; then
        doctor_add "mcp-elicitation" "skills" "info" \
            "CC v2.1.76 MCP elicitation available (MCP servers can request structured user input)" \
            "MCP servers can now prompt for structured input mid-task via interactive dialogs"
    fi

    # v8.57: Warn about --plugin-dir behavioral change (one path per flag in v2.1.76+)
    if [[ "$SUPPORTS_PLUGIN_DIR_OVERRIDE" == "true" ]] && version_compare "$CLAUDE_CODE_VERSION" "2.1.76" ">="; then
        doctor_add "plugin-dir-one-path" "skills" "info" \
            "CC v2.1.76 --plugin-dir accepts one path per flag (use repeated flags for multiple)" \
            "If using multiple plugin dirs, change --plugin-dir 'a b' to --plugin-dir a --plugin-dir b"
    fi

    # v9.5: CC v2.1.77+ doctor tips
    if [[ "$SUPPORTS_PLUGIN_VALIDATE_FRONTMATTER" == "true" ]]; then
        doctor_add "plugin-validate" "skills" "info" \
            "CC v2.1.77 claude plugin validate checks frontmatter + hooks.json schema" \
            "Run 'claude plugin validate .' to catch YAML parse errors and schema violations in skills, agents, and hooks"
    fi

    if [[ "$SUPPORTS_ALLOW_READ_SANDBOX" == "true" ]]; then
        doctor_add "allow-read-sandbox" "skills" "info" \
            "CC v2.1.77 allowRead sandbox setting available" \
            "Use allowRead in sandbox settings to re-allow read access within denyRead regions"
    fi

    if [[ "$SUPPORTS_BRANCH_COMMAND" == "true" ]]; then
        doctor_add "branch-command" "skills" "info" \
            "CC v2.1.77 /fork renamed to /branch" \
            "Use /branch to create conversation branches (the /fork alias still works)"
    fi

    if [[ "$SUPPORTS_AGENT_NO_RESUME_PARAM" == "true" ]]; then
        doctor_add "sendmessage-resume" "skills" "pass" \
            "CC v2.1.77 agent resume uses SendMessage (Agent resume param removed)" \
            "Octopus resume commands use SendMessage for agent continuation automatically"
    fi

    if [[ "$SUPPORTS_BG_BASH_5GB_KILL" == "true" ]]; then
        doctor_add "bg-bash-5gb" "skills" "info" \
            "CC v2.1.77 background bash processes killed at 5GB output" \
            "Long-running background Bash tasks producing >5GB will be terminated. Agent tool dispatches are unaffected."
    fi

    # v9.5: Wired medium flags as doctor tips (previously banner-only or dead)
    if [[ "$SUPPORTS_COPY_INDEX" == "true" ]]; then
        doctor_add "copy-index" "skills" "info" \
            "CC v2.1.77 /copy N copies the Nth-latest response" \
            "Use /copy 3 to copy the third-most-recent assistant response to clipboard"
    fi

    if [[ "$SUPPORTS_COMPOUND_BASH_PERMISSION_FIX" == "true" ]]; then
        doctor_add "compound-bash-fix" "skills" "info" \
            "CC v2.1.77 compound bash always-allow applies per sub-command" \
            "Each sub-command in a compound bash expression is checked individually against always-allow rules"
    fi

    if [[ "$SUPPORTS_RESUME_TRUNCATION_FIX" == "true" ]]; then
        doctor_add "resume-truncation-fix" "skills" "info" \
            "CC v2.1.77 --resume no longer truncates history" \
            "Long conversations resumed with --resume now preserve full history instead of truncating"
    fi

    if [[ "$SUPPORTS_PRETOOLUSE_DENY_PRIORITY" == "true" ]]; then
        doctor_add "pretooluse-deny-priority" "skills" "info" \
            "CC v2.1.77 PreToolUse deny rules always take priority" \
            "Enterprise deny rules in PreToolUse hooks now override user allow and skill allowed-tools"
    fi

    if [[ "$SUPPORTS_SENDMESSAGE_AUTO_RESUME" == "true" ]]; then
        doctor_add "sendmessage-auto-resume" "skills" "info" \
            "CC v2.1.77 SendMessage auto-resumes stopped agents" \
            "Stopped agents are automatically resumed when you send them a message via SendMessage"
    fi

    if [[ "$SUPPORTS_PARALLEL_TOOL_RESILIENCE" == "true" ]]; then
        doctor_add "parallel-tool-resilience" "skills" "info" \
            "CC v2.1.72 parallel tool failures handled gracefully" \
            "A failed Read/WebFetch/Glob no longer cancels sibling parallel tool calls"
    fi

    if [[ "$SUPPORTS_BG_PROCESS_CLEANUP" == "true" ]]; then
        doctor_add "bg-process-cleanup" "skills" "info" \
            "CC v2.1.73 background bash auto-cleaned from subagents" \
            "Background bash processes spawned by subagents are automatically cleaned up on agent exit"
    fi

    # ── v9.19.0: CC v2.1.87-92 doctor tips ──────────────────────────────────────

    if [[ "$SUPPORTS_POST_COMPACT_HOOK" == "true" ]]; then
        doctor_add "post-compact-hook" "skills" "pass" \
            "CC v2.1.76 PostCompact hook active — workflow context recovers after compaction" \
            "Pre-compact state is re-injected automatically via PostCompact hook"
    fi

    if [[ "$SUPPORTS_BARE_FLAG" == "true" ]]; then
        if [[ "${OCTOPUS_DISABLE_BARE:-0}" == "1" ]]; then
            doctor_add "bare-flag" "skills" "warn" \
                "--bare flag disabled via OCTOPUS_DISABLE_BARE=1" \
                "Subprocess synthesis falls back to standard claude -p (slower but avoids auth issues)"
        else
            # Probe whether --bare can authenticate (CC v2.1.114 regression,
            # issue #288) without allowing auth or Keychain waits to wedge doctor.
            local _bare_test="" _bare_test_rc=0
            _bare_test=$(_octo_bare_auth_probe 2>/dev/null) || _bare_test_rc=$?
            _bare_test="${_bare_test%%$'\n'*}"
            if [[ "$_bare_test" == *"Not logged in"* || "$_bare_test" == *"Please run /login"* ]]; then
                doctor_add "bare-flag" "skills" "fail" \
                    "--bare flag breaks subprocess auth on this install (issue #288)" \
                    "Set OCTOPUS_DISABLE_BARE=1 in your shell profile or ~/.claude/settings.json env block to fix"
            elif [[ "$_bare_test_rc" -ne 0 ]]; then
                doctor_add "bare-flag" "skills" "warn" \
                    "--bare authentication probe did not complete (exit ${_bare_test_rc})" \
                    "Octopus disabled --bare for this run instead of waiting indefinitely"
            else
                doctor_add "bare-flag" "skills" "pass" \
                    "CC v2.1.87 --bare flag active — subprocess synthesis runs faster" \
                    "Octopus uses --bare for claude -p subprocess calls to skip hooks/LSP loading"
            fi
        fi
    fi

    if [[ "$SUPPORTS_MODEL_CAP_ENV_VARS" == "true" ]]; then
        doctor_add "model-cap-env-vars" "skills" "info" \
            "CC v2.1.87 ANTHROPIC_DEFAULT_*_MODEL_SUPPORTS env vars available" \
            "3rd-party provider capabilities are detected automatically for routing decisions"
    fi

    if [[ "$SUPPORTS_CONSOLE_AUTH" == "true" ]]; then
        doctor_add "console-auth" "skills" "info" \
            "CC v2.1.87 --console auth available (Anthropic Console API billing)" \
            "Use 'claude --console' to authenticate via the Anthropic Console for API-billed usage"
    fi

    if [[ "$SUPPORTS_PLUGIN_EXECUTABLES" == "true" ]]; then
        doctor_add "plugin-executables" "skills" "pass" \
            "CC v2.1.91 plugin executables active — 'octopus' available as bare command" \
            "Run 'octopus doctor' or 'octopus version' directly from the terminal"
    fi

    if [[ "$SUPPORTS_MCP_RESULT_SIZE" == "true" ]]; then
        doctor_add "mcp-result-size" "skills" "info" \
            "CC v2.1.91 MCP result size override available (up to 500K chars)" \
            "MCP tools can use _meta[\"anthropic/maxResultSizeChars\"] for larger results"
    fi

    if [[ "$SUPPORTS_MARKETPLACE_OFFLINE" == "true" ]]; then
        doctor_add "marketplace-offline" "skills" "info" \
            "CC v2.1.90 marketplace offline mode available" \
            "Set CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE=1 for graceful degradation on flaky networks"
    fi

    if [[ "$SUPPORTS_DISABLE_SKILL_SHELL" == "true" ]]; then
        doctor_add "disable-skill-shell" "skills" "info" \
            "CC v2.1.91 disableSkillShellExecution setting available" \
            "When enabled, skills cannot invoke shell commands — orchestrate.sh workflows require this to be false"
    fi

    if [[ "$SUPPORTS_RATE_LIMIT_STATUSLINE" == "true" ]]; then
        doctor_add "rate-limit-hud-fallback" "skills" "pass" \
            "CC v2.1.80 rate_limits field used as HUD fallback" \
            "Octopus HUD uses CC-provided rate limits when OAuth API is unavailable"
    fi

    if [[ "$SUPPORTS_MANAGED_SETTINGS_D" == "true" ]]; then
        local _settings_fragment="${HOME}/.claude/managed-settings.d/octopus-defaults.json"
        if [[ -f "$_settings_fragment" ]]; then
            doctor_add "managed-settings-fragment" "skills" "pass" \
                "CC v2.1.83 managed-settings.d/ fragment installed" \
                "octopus-defaults.json active in ~/.claude/managed-settings.d/ (git instructions off, auto-memory dir set)"
        else
            doctor_add "managed-settings-fragment" "skills" "info" \
                "CC v2.1.83 managed-settings.d/ fragment not yet installed" \
                "Restart session to deploy octopus-defaults.json to ~/.claude/managed-settings.d/"
        fi
    fi

    if [[ "$SUPPORTS_ELICITATION_HOOKS" == "true" ]]; then
        doctor_add "elicitation-hooks" "skills" "pass" \
            "CC v2.1.76 Elicitation/ElicitationResult hooks active" \
            "MCP servers can request structured user input mid-task; events logged to ~/.claude-octopus/logs/elicitation.log"
    fi

    if [[ "$SUPPORTS_SESSION_ID_HEADER" == "true" ]]; then
        doctor_add "session-id-header" "skills" "info" \
            "CC v2.1.89 X-Claude-Code-Session-Id header available" \
            "Proxy servers can aggregate requests by session ID for telemetry and routing"
    fi

    if [[ "$SUPPORTS_DEEP_LINK_5K" == "true" ]]; then
        doctor_add "deep-link-5k" "skills" "info" \
            "CC v2.1.88 deep links expanded to 5,000 chars" \
            "claude-cli://open?q= links can carry longer prompts with scroll-to-review"
    fi

    if [[ "$SUPPORTS_WORKTREE_HTTP_HOOKS" == "true" ]]; then
        doctor_add "worktree-http-hooks" "skills" "info" \
            "CC v2.1.87 WorktreeCreate supports type:http hooks" \
            "Worktree hooks can POST JSON to a URL instead of running a shell command"
    fi

    if [[ "$SUPPORTS_MULTILINE_DEEP_LINKS" == "true" ]]; then
        doctor_add "multiline-deep-links" "skills" "info" \
            "CC v2.1.91 multi-line deep link prompts available" \
            "claude-cli://open?q= supports encoded newlines (%0A) for multi-step prompts"
    fi

    # ── v9.36.0: CC v2.1.126-129 doctor tips ───────────────────────────────────

    if [[ "${SUPPORTS_PROJECT_PURGE:-false}" == "true" ]]; then
        doctor_add "project-purge" "skills" "info" \
            "CC v2.1.126 claude project purge available" \
            "Use 'claude project purge --dry-run .' to inspect stale Claude Code project state before deleting transcripts/tasks/config"
    fi

    if [[ "${SUPPORTS_SKILL_ACTIVATED_OTEL_TRIGGER:-false}" == "true" ]]; then
        doctor_add "skill-activated-otel" "skills" "info" \
            "CC v2.1.126 skill activation telemetry includes invocation_trigger" \
            "claude_code.skill_activated can distinguish user-slash, claude-proactive, and nested-skill activations"
    fi

    if [[ "${SUPPORTS_PLUGIN_ZIP_DIR:-false}" == "true" ]]; then
        doctor_add "plugin-zip-dir" "skills" "info" \
            "CC v2.1.128 --plugin-dir accepts .zip plugin archives" \
            "Release validation can smoke-test the packaged plugin archive, not just the source directory"
    fi

    if [[ "${SUPPORTS_INIT_PLUGIN_ERRORS:-false}" == "true" ]]; then
        doctor_add "init-plugin-errors" "skills" "info" \
            "CC v2.1.128 stream-json init.plugin_errors reports plugin-dir load failures" \
            "Use --output-format stream-json --include-hook-events in release smoke tests to catch plugin load errors"
    fi

    if [[ "${SUPPORTS_PLUGIN_URL:-false}" == "true" ]]; then
        doctor_add "plugin-url" "skills" "info" \
            "CC v2.1.129 --plugin-url can load a plugin zip for the current session" \
            "Use --plugin-url with a release artifact URL to reproduce marketplace/plugin loading without installing"
    fi

    if [[ "${SUPPORTS_SKILL_OVERRIDES:-false}" == "true" ]]; then
        local _settings_file _has_skill_overrides="false"
        for _settings_file in "$PWD/.claude/settings.json" "$HOME/.claude/settings.json" "$HOME/.claude/settings.local.json"; do
            [[ -f "$_settings_file" ]] || continue
            if command -v jq &>/dev/null && jq -e 'has("skillOverrides")' "$_settings_file" >/dev/null 2>&1; then
                _has_skill_overrides="true"
                break
            fi
        done
        if [[ "$_has_skill_overrides" == "true" ]]; then
            doctor_add "skill-overrides" "skills" "pass" \
                "CC v2.1.129 skillOverrides configured" "Use off, user-invocable-only, or name-only to tune Octopus skill context"
        else
            doctor_add "skill-overrides" "skills" "info" \
                "CC v2.1.129 skillOverrides available for reducing Octopus skill context" \
                "Set skillOverrides in Claude settings to hide niche skills or collapse them to name-only"
        fi
    fi

    if [[ "${SUPPORTS_PR_COUNT_MCP_OTEL:-false}" == "true" ]]; then
        doctor_add "pr-count-mcp-otel" "skills" "info" \
            "CC v2.1.129 PR count telemetry includes MCP-created PRs/MRs" \
            "claude_code.pull_request.count now covers GitHub/GitLab MCP creation as well as shell-created PRs"
    fi

    if [[ "${SUPPORTS_BASH_SESSION_ID_ENV:-false}" == "true" ]]; then
        doctor_add "bash-session-id-env" "skills" "pass" \
            "CC v2.1.132 CLAUDE_CODE_SESSION_ID is available in Bash tool subprocesses" \
            "Octopus uses it for Claude-specific careful/freeze state, proof packets, usage files, and session-scoped caches"
    fi

    # v9.42: Surface Claude Code v2.1.154-157 / Opus 4.8 capabilities.
    if [[ "${SUPPORTS_OPUS_4_8:-false}" == "true" ]]; then
        doctor_add "opus-4-8" "skills" "pass" \
            "CC v2.1.154 Opus 4.8 available; claude-opus routes to the current premium model" \
            "Use OCTOPUS_OPUS_MODEL=claude-opus-4.6 only when you need legacy behavior"
    fi

    if [[ "${SUPPORTS_SONNET_5:-false}" == "true" ]]; then
        doctor_add "sonnet-5" "skills" "pass" \
            "CC v2.1.197 Sonnet 5 available for standard Claude seats" \
            "Existing providers.json pins remain unchanged; new configs default to claude-sonnet-5"
    fi

    if [[ "${SUPPORTS_OPUS_5:-false}" == "true" ]]; then
        doctor_add "opus-5" "skills" "pass" \
            "CC v2.1.219 Opus 5 available; claude-opus routes to the current premium lead model" \
            "Pin OCTOPUS_OPUS_MODEL only when you need Fable 5 or a legacy fallback"
    fi

    if [[ "${SUPPORTS_DYNAMIC_WORKFLOWS:-false}" == "true" ]]; then
        doctor_add "dynamic-workflows" "skills" "info" \
            "CC v2.1.154 dynamic workflows available for huge single-Claude migrations" \
            "Prefer native workflows for codebase-scale single-model migrations; use Octopus for multi-provider disagreement, councils, adversarial review, and validation"
    fi

    if [[ "${SUPPORTS_SKILLS_AUTO_PLUGIN_LOAD:-false}" == "true" ]]; then
        doctor_add "skills-auto-plugin-load" "skills" "info" \
            "CC v2.1.157 auto-loads plugins from .claude/skills directories" \
            "Local Octopus development can use .claude/skills without marketplace installation when testing plugin changes"
    fi

    if [[ "${SUPPORTS_ENTER_WORKTREE_SWITCH:-false}" == "true" ]]; then
        doctor_add "enter-worktree-switch" "skills" "info" \
            "CC v2.1.157 EnterWorktree can switch between Claude-managed worktrees mid-session" \
            "Octopus worktree handoff can reuse native switching instead of forcing a fresh checkout"
    fi

    # v9.20.0: Output compression
    if [[ -x "${CLAUDE_PLUGIN_ROOT:-}/hooks/output-compressor.sh" ]]; then
        if [[ "${OCTOPUS_COMPRESS_ENABLED:-true}" == "true" ]]; then
            doctor_add "output-compressor" "skills" "pass" \
                "Output compressor active — large tool results get compressed summaries" \
                "PostToolUse hook injects summaries for JSON arrays, logs, HTML, verbose output >3K chars. Use 'octo-compress stats' to see savings."
        else
            doctor_add "output-compressor" "skills" "info" \
                "Output compressor installed but disabled" \
                "Set OCTOPUS_COMPRESS_ENABLED=true to enable automatic compression of large tool outputs"
        fi
    fi

    if [[ -x "${CLAUDE_PLUGIN_ROOT:-}/bin/octo-compress" ]]; then
        doctor_add "octo-compress-cli" "skills" "pass" \
            "octo-compress CLI available — pipe verbose output for token savings" \
            "Usage: npm install 2>&1 | octo-compress — compresses JSON arrays, logs, HTML, verbose text"
    fi
}

# --- Category 8: Conflicts ---
doctor_check_conflicts() {
    local claude_plugins_dir="$HOME/.claude/plugins"
    local conflicts=0

    if [[ -d "$claude_plugins_dir/oh-my-claude-code" ]]; then
        doctor_add "conflict-oh-my-claude" "conflicts" "warn" \
            "oh-my-claude-code detected" "Has own cost-aware routing — may overlap with Octopus provider selection"
        ((conflicts++)) || true
    fi

    if [[ -d "$claude_plugins_dir/claude-flow" ]]; then
        doctor_add "conflict-claude-flow" "conflicts" "warn" \
            "claude-flow detected" "May spawn competing subagents"
        ((conflicts++)) || true
    fi

    if [[ -d "$claude_plugins_dir/agents" ]] || [[ -d "$claude_plugins_dir/wshobson-agents" ]]; then
        doctor_add "conflict-wshobson-agents" "conflicts" "warn" \
            "wshobson/agents detected" "Large context consumption"
        ((conflicts++)) || true
    fi

    if [[ $conflicts -eq 0 ]]; then
        doctor_add "no-conflicts" "conflicts" "pass" \
            "No conflicting plugins detected" ""
    fi

    # v8.57: Detect companion plugins (complementary, not conflicting)
    local claude_mem_dir=""
    for dir in "$HOME"/.claude/plugins/cache/thedotmack/claude-mem/*/; do
        [[ -d "$dir" ]] && claude_mem_dir="$dir" && break
    done
    if [[ -n "$claude_mem_dir" ]]; then
        local mem_version
        mem_version=$(basename "${claude_mem_dir%/}" 2>/dev/null || echo "unknown")
        doctor_add "companion-claude-mem" "conflicts" "pass" \
            "claude-mem v${mem_version} detected (companion — persistent cross-session memory)" \
            "Octopus workflows can use claude-mem MCP tools (search, timeline, get_observations) for past session context"
    fi

    local agentmemory_dir=""
    for dir in \
        "$HOME"/.claude/plugins/cache/rohitg00/agentmemory/*/ \
        "$HOME"/.claude/plugins/cache/agentmemory/agentmemory/*/ \
        "$HOME"/.codex/plugins/cache/rohitg00/agentmemory/*/ \
        "$HOME"/.codex/plugins/cache/agentmemory/agentmemory/*/; do
        [[ -d "$dir" ]] && agentmemory_dir="$dir" && break
    done
    if [[ -n "$agentmemory_dir" ]]; then
        local agentmemory_version
        agentmemory_version=$(basename "${agentmemory_dir%/}" 2>/dev/null || echo "unknown")
        doctor_add "companion-agentmemory" "conflicts" "pass" \
            "agentmemory v${agentmemory_version} detected (companion — persistent cross-agent memory)" \
            "Octopus memory hooks can use agentmemory through MCP or the local REST bridge"
    elif command -v agentmemory >/dev/null 2>&1; then
        doctor_add "companion-agentmemory" "conflicts" "pass" \
            "agentmemory CLI detected (companion — persistent cross-agent memory)" \
            "$(command -v agentmemory)"
    elif [[ -n "${AGENTMEMORY_URL:-}" ]]; then
        doctor_add "companion-agentmemory" "conflicts" "info" \
            "agentmemory URL configured" "$AGENTMEMORY_URL"
    fi
}

# --- Category 9: Smoke Test (v8.19.0 - Issue #34) ---
doctor_check_smoke() {
    # Cache status
    if [[ -f "$SMOKE_TEST_CACHE_FILE" ]]; then
        local cache_time cache_key cache_status current_time cache_age
        cache_time=$(head -1 "$SMOKE_TEST_CACHE_FILE" 2>/dev/null || echo "0")
        cache_key=$(sed -n '2p' "$SMOKE_TEST_CACHE_FILE" 2>/dev/null || echo "")
        cache_status=$(sed -n '3p' "$SMOKE_TEST_CACHE_FILE" 2>/dev/null || echo "1")
        current_time=$(date +%s)
        cache_age=$((current_time - cache_time))

        if [[ $cache_age -lt $PREFLIGHT_CACHE_TTL && "$cache_key" == "$(smoke_test_cache_key)" ]]; then
            if [[ "$cache_status" == "0" ]]; then
                doctor_add "smoke-cache" "smoke" "pass" \
                    "Smoke test cache valid (passed ${cache_age}s ago)" "$cache_key"
            else
                doctor_add "smoke-cache" "smoke" "fail" \
                    "Smoke test cache valid (FAILED ${cache_age}s ago)" "$cache_key"
            fi
        else
            doctor_add "smoke-cache" "smoke" "warn" \
                "Smoke test cache expired or stale" "Will re-test on next run"
        fi
    else
        doctor_add "smoke-cache" "smoke" "warn" \
            "No smoke test cache found" "Will test on next run"
    fi

    # Current model config
    local codex_model agy_model
    codex_model=$(get_agent_model "codex" 2>/dev/null || echo "not configured")
    agy_model=$(get_agent_model "agy" 2>/dev/null || echo "not configured")

    doctor_add "smoke-codex-model" "smoke" "pass" \
        "Codex model: ${codex_model}" "OCTOPUS_CODEX_MODEL=${OCTOPUS_CODEX_MODEL:-<default>}"
    doctor_add "smoke-agy-model" "smoke" "pass" \
        "Antigravity model: ${agy_model}" "OCTOPUS_AGY_MODEL=${OCTOPUS_AGY_MODEL:-<default>}"

    # Skip flag
    if [[ "$SKIP_SMOKE_TEST" == "true" ]]; then
        doctor_add "smoke-skip" "smoke" "warn" \
            "Smoke test DISABLED (--skip-smoke-test or OCTOPUS_SKIP_SMOKE_TEST=true)" \
            "Not recommended — provider failures will only be caught at runtime"
    fi
}

# --- Category 10: Agents (v8.26.0 - Changelog Integration) ---
doctor_check_agents() {
    local config_file="${PLUGIN_DIR}/agents/config.yaml"
    if [[ ! -f "$config_file" ]]; then
        doctor_add "agents-config" "agents" "fail" \
            "agents/config.yaml not found" "Expected at: $config_file"
        return
    fi

    local agent_count
    agent_count=$(grep -c '^\s\{2\}[a-z]' "$config_file" 2>/dev/null) || agent_count=0
    doctor_add "agents-count" "agents" "pass" \
        "${agent_count} agent definitions found" ""

    local worktree_agents
    worktree_agents=$(grep -c 'isolation: worktree' "$config_file" 2>/dev/null) || worktree_agents=0
    doctor_add "agents-worktree" "agents" "pass" \
        "${worktree_agents} agents with worktree isolation" ""

    if [[ "$SUPPORTS_AGENTS_CLI" == "true" ]]; then
        local cli_output
        cli_output=$(claude agents 2>/dev/null | head -20 || echo "")
        if [[ -n "$cli_output" ]]; then
            local cli_count
            cli_count=$(echo "$cli_output" | grep -c "^") || cli_count=0
            doctor_add "agents-cli" "agents" "pass" \
                "Claude agents CLI: ${cli_count} agents registered" ""
        else
            doctor_add "agents-cli" "agents" "warn" \
                "Claude agents CLI returned no data" "Run 'claude agents' manually"
        fi
    else
        doctor_add "agents-cli" "agents" "info" \
            "Claude agents CLI not available (requires v2.1.50+)" ""
    fi

    if [[ -n "${CLAUDE_CODE_VERSION:-}" ]]; then
        if version_compare "$CLAUDE_CODE_VERSION" "2.1.50" "<" 2>/dev/null; then
            doctor_add "agents-version" "agents" "warn" \
                "Claude Code < v2.1.50 — multi-agent memory leaks possible" \
                "Recommend upgrading for worktree isolation and embrace stability"
        else
            doctor_add "agents-version" "agents" "pass" \
                "Claude Code v${CLAUDE_CODE_VERSION} — multi-agent stable" ""
        fi
    fi
}

# --- Category 11: Failure Recurrence (v8.34.0 — Idea Meritocracy E46/E47) ---
# Parses .octo/decisions.jsonl for repeated failure patterns
doctor_check_recurrence() {
    local jsonl_file="${WORKSPACE_DIR}/.octo/decisions.jsonl"
    if [[ ! -f "$jsonl_file" ]]; then
        doctor_add "recurrence-data" "recurrence" "info" \
            "No decision history yet — recurrence detection starts after first workflow" ""
        return
    fi

    local total_decisions
    total_decisions=$(wc -l < "$jsonl_file" 2>/dev/null | tr -d ' ')
    if [[ "$total_decisions" -eq 0 ]]; then
        doctor_add "recurrence-data" "recurrence" "info" \
            "Decision log empty — no patterns to detect" ""
        return
    fi

    doctor_add "recurrence-data" "recurrence" "pass" \
        "${total_decisions} decisions logged" ""

    # Count quality-gate failures (the most actionable pattern)
    local qg_failures
    qg_failures=$(grep -c '"type":"quality-gate"' "$jsonl_file" 2>/dev/null || true)
    qg_failures="${qg_failures:-0}"
    if [[ "$qg_failures" -ge 3 ]]; then
        doctor_add "recurrence-qg" "recurrence" "warn" \
            "${qg_failures} quality gate failures recorded" \
            "Recurring failures may indicate a systemic issue. Run /octo:issues to review."
    elif [[ "$qg_failures" -gt 0 ]]; then
        doctor_add "recurrence-qg" "recurrence" "info" \
            "${qg_failures} quality gate failure(s) recorded" ""
    fi

    # Check for failures in the last 48 hours
    local cutoff_epoch
    if [[ "$OCTOPUS_PLATFORM" == "Darwin" ]]; then
        cutoff_epoch=$(date -v-2d +%s 2>/dev/null || echo "0")
    else
        cutoff_epoch=$(date -d "2 days ago" +%s 2>/dev/null || echo "0")
    fi

    if [[ "$cutoff_epoch" -gt 0 ]]; then
        local recent_failures=0
        while IFS= read -r line; do
            local ts
            ts=$(echo "$line" | grep -o '"timestamp":"[^"]*"' | sed 's/"timestamp":"//;s/"//' || true)
            if [[ -n "$ts" ]]; then
                local line_epoch
                if [[ "$OCTOPUS_PLATFORM" == "Darwin" ]]; then
                    line_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || echo "0")
                else
                    line_epoch=$(date -d "$ts" +%s 2>/dev/null || echo "0")
                fi
                if [[ "$line_epoch" -ge "$cutoff_epoch" ]]; then
                    ((recent_failures++))
                fi
            fi
        done < <(grep '"type":"quality-gate"' "$jsonl_file" 2>/dev/null || true)

        if [[ "$recent_failures" -ge 3 ]]; then
            doctor_add "recurrence-recent" "recurrence" "warn" \
                "${recent_failures} quality gate failures in last 48h — pattern detected" \
                "Multiple recent failures suggest an active systemic issue"
        elif [[ "$recent_failures" -gt 0 ]]; then
            doctor_add "recurrence-recent" "recurrence" "pass" \
                "${recent_failures} quality gate failure(s) in last 48h" ""
        fi
    fi

    # Check source concentration (same source failing repeatedly)
    local top_source
    top_source=$(grep '"type":"quality-gate"' "$jsonl_file" 2>/dev/null | \
        grep -o '"source":"[^"]*"' | sort | uniq -c | sort -rn | head -1 || true)
    if [[ -n "$top_source" ]]; then
        local count source_name
        count=$(echo "$top_source" | awk '{print $1}')
        source_name=$(echo "$top_source" | grep -o '"source":"[^"]*"' | sed 's/"source":"//;s/"//')
        if [[ "$count" -ge 3 ]]; then
            doctor_add "recurrence-source" "recurrence" "warn" \
                "Recurring failure source: ${source_name} (${count}x)" \
                "Same workflow failing repeatedly — investigate root cause"
        fi
    fi
}

# --- Category 12: Plugin cache hygiene (v9.29.0) ---
# Reports stale octo cache versions so users can reclaim disk space.
# Cleanup is interactive — never deletes from this check.
doctor_check_cache() {
    local hygiene_lib="${OCTOPUS_LIB_DIR:-$(dirname "${BASH_SOURCE[0]}")}/cache-hygiene.sh"
    if [[ ! -r "$hygiene_lib" ]]; then
        doctor_add "cache-hygiene-lib" "cache" "info" \
            "cache-hygiene.sh not found — skipping" "$hygiene_lib"
        return
    fi
    # shellcheck disable=SC1090
    source "$hygiene_lib"

    local total stale_count
    total=$(octo_cache_versions | wc -l | tr -d ' ')
    stale_count=$(octo_cache_stale | grep -c . || true)
    stale_count="${stale_count:-0}"

    if [[ "$total" -eq 0 ]]; then
        doctor_add "cache-versions" "cache" "info" \
            "No octo cache directory yet" "$OCTO_CACHE_DIR"
        return
    fi

    local active="${CLAUDE_PLUGIN_ROOT:+$(octo_cache_active_version)}"
    local active_msg=""
    [[ -n "$active" ]] && active_msg=" (active: ${active})"

    if [[ "$stale_count" -eq 0 ]]; then
        doctor_add "cache-versions" "cache" "pass" \
            "${total} octo version(s) cached${active_msg}" "Within keep window (${OCTOPUS_CACHE_KEEP:-2})"
        return
    fi

    local bytes human stale_list
    bytes=$(octo_cache_stale_bytes)
    human=$(octo_cache_format_bytes "$bytes")
    stale_list=$(octo_cache_stale | tr '\n' ',' | sed 's/,$//;s/,/, /g')

    doctor_add "cache-stale-versions" "cache" "warn" \
        "${stale_count} stale octo version(s) — ${human}${active_msg}" \
        "Stale: ${stale_list}. Run: bash \$CLAUDE_PLUGIN_ROOT/scripts/lib/cache-hygiene.sh clean (or set OCTOPUS_AUTO_CLEAN_CACHE=1)"
}

# --- Output: Human-readable ---
doctor_output_human() {
    local verbose="${1:-false}"
    local total=${#DOCTOR_RESULTS_NAME[@]}
    local pass_count=0 warn_count=0 fail_count=0
    local current_cat=""

    for ((i=0; i<total; i++)); do
        local status="${DOCTOR_RESULTS_STATUS[$i]}"
        case "$status" in
            pass) ((++pass_count)) ;;
            warn) ((++warn_count)) ;;
            fail) ((++fail_count)) ;;
        esac
    done

    for ((i=0; i<total; i++)); do
        local name="${DOCTOR_RESULTS_NAME[$i]}"
        local cat="${DOCTOR_RESULTS_CAT[$i]}"
        local status="${DOCTOR_RESULTS_STATUS[$i]}"
        local msg="${DOCTOR_RESULTS_MSG[$i]}"
        local detail="${DOCTOR_RESULTS_DETAIL[$i]}"

        # Skip passing checks in non-verbose mode
        if [[ "$verbose" != "true" && "$status" == "pass" ]]; then
            continue
        fi

        # Print category header on change
        if [[ "$cat" != "$current_cat" ]]; then
            current_cat="$cat"
            echo -e "\n${BOLD}${BLUE}[$cat]${NC}"
        fi

        # Status icon
        local icon
        case "$status" in
            pass) icon="${GREEN}✓${NC}" ;;
            info) icon="${BLUE}ℹ${NC}" ;;
            warn) icon="${YELLOW}⚠${NC}" ;;
            fail) icon="${RED}✗${NC}" ;;
            *) icon="${RED}?${NC}" ;;
        esac

        echo -e "  ${icon} ${msg}"
        # Always show detail for warn/fail (it contains the actionable fix).
        # Only gate detail behind --verbose for passing checks.
        if [[ -n "$detail" ]]; then
            if [[ "$status" == "warn" || "$status" == "fail" || "$verbose" == "true" ]]; then
                echo -e "    ${DIM}${detail}${NC}"
            fi
        fi
    done

    # All-clear message in non-verbose mode
    if [[ "$verbose" != "true" && $warn_count -eq 0 && $fail_count -eq 0 ]]; then
        echo -e "\n  ${GREEN}✓${NC} All checks passed. Use ${DIM}--verbose${NC} to see details."
    fi

    # Summary line
    echo ""
    local summary="${BOLD}Summary:${NC} ${GREEN}${pass_count} passed${NC}"
    [[ $warn_count -gt 0 ]] && summary+=", ${YELLOW}${warn_count} warning(s)${NC}"
    [[ $fail_count -gt 0 ]] && summary+=", ${RED}${fail_count} failure(s)${NC}"
    echo -e "$summary"

    if [[ $fail_count -gt 0 ]]; then
        return 1
    fi
    return 0
}

# --- Output: JSON ---
doctor_json_escape() {
    local value="${1:-}"
    if command -v jq >/dev/null 2>&1; then
        jq -Rrn --arg value "$value" '$value | tojson | .[1:-1]' && return 0
    fi

    local LC_ALL=C
    local out="" ch ord escaped i
    for ((i=0; i<${#value}; i++)); do
        ch="${value:i:1}"
        case "$ch" in
            '"') out="${out}\\\"" ;;
            \\) out="${out}\\\\" ;;
            $'\b') out="${out}\\b" ;;
            $'\f') out="${out}\\f" ;;
            $'\n') out="${out}\\n" ;;
            $'\r') out="${out}\\r" ;;
            $'\t') out="${out}\\t" ;;
            *)
                if [[ "$ch" == [[:cntrl:]] ]]; then
                    LC_ALL=C printf -v ord '%d' "'$ch"
                    printf -v escaped '\\u%04x' "$ord"
                    out="${out}${escaped}"
                else
                    out="${out}${ch}"
                fi
                ;;
        esac
    done
    printf '%s' "$out"
}

doctor_output_json() {
    local total=${#DOCTOR_RESULTS_NAME[@]}
    local pass_count=0 warn_count=0 fail_count=0 info_count=0 exit_code=0
    local json="["
    for ((i=0; i<total; i++)); do
        [[ $i -gt 0 ]] && json+=","
        local name cat status msg detail
        name="$(doctor_json_escape "${DOCTOR_RESULTS_NAME[$i]}")"
        cat="$(doctor_json_escape "${DOCTOR_RESULTS_CAT[$i]}")"
        status="$(doctor_json_escape "${DOCTOR_RESULTS_STATUS[$i]}")"
        msg="$(doctor_json_escape "${DOCTOR_RESULTS_MSG[$i]}")"
        detail="$(doctor_json_escape "${DOCTOR_RESULTS_DETAIL[$i]}")"
        case "${DOCTOR_RESULTS_STATUS[$i]}" in
            pass) ((++pass_count)) ;;
            warn) ((++warn_count)) ;;
            fail) ((++fail_count)) ;;
            *) ((++info_count)) ;;
        esac
        json+="{\"name\":\"$name\",\"category\":\"$cat\",\"status\":\"$status\",\"message\":\"$msg\",\"detail\":\"$detail\"}"
    done
    json+="]"
    [[ $fail_count -gt 0 ]] && exit_code=1
    printf '{"schema_version":"10.0","summary":{"passed":%d,"warnings":%d,"failures":%d,"info":%d,"total":%d,"exit_code":%d},"results":%s}\n' \
        "$pass_count" "$warn_count" "$fail_count" "$info_count" "$total" "$exit_code" "$json"
    return "$exit_code"
}

doctor_usage() {
    cat <<'EOF'
Usage: octopus doctor [CATEGORY] [--verbose] [--json] [--live]

Categories:
  providers companions auth config updates state smoke hooks scheduler
  skills conflicts agents recurrence cache

Options:
  -v, --verbose  Include details for passing checks
  --json         Emit the Doctor 2.0 JSON contract
  --live         Run bounded live provider probes (also enables verbose output)
  -h, --help     Show this help
EOF
}

# --- Main Doctor Runner ---
do_doctor() {
    local category_filter=""
    local verbose=false
    local json_output=false
    local DOCTOR_LIVE_PROBE=false
    local categories="providers companions auth config updates state smoke hooks scheduler skills conflicts agents recurrence cache"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose|-v) verbose=true ;;
            --json) json_output=true ;;
            --live) DOCTOR_LIVE_PROBE=true; verbose=true ;;
            --help|-h) doctor_usage; return 0 ;;
            -*)
                printf 'Unknown doctor option: %s\n' "$1" >&2
                doctor_usage >&2
                return 2
                ;;
            *)
                case " $categories " in
                    *" $1 "*) ;;
                    *)
                        printf 'Unknown doctor category: %s\n' "$1" >&2
                        doctor_usage >&2
                        return 2
                        ;;
                esac
                if [[ -n "$category_filter" ]]; then
                    printf 'Only one doctor category may be selected (got %s and %s).\n' "$category_filter" "$1" >&2
                    doctor_usage >&2
                    return 2
                fi
                category_filter="$1"
                ;;
        esac
        shift
    done

    # Reset results
    DOCTOR_RESULTS_NAME=()
    DOCTOR_RESULTS_CAT=()
    DOCTOR_RESULTS_STATUS=()
    DOCTOR_RESULTS_MSG=()
    DOCTOR_RESULTS_DETAIL=()
    DOCTOR_AGY_LIVE_AUTH_STATUS="not-run"
    DOCTOR_PROVIDER_READINESS=()
    DOCTOR_PROVIDER_READINESS_KIND=""

    # Run checks (filtered if category specified)
    local cat
    for cat in $categories; do
        if [[ -z "$category_filter" || "$category_filter" == "$cat" ]]; then
            "doctor_check_${cat}"
        fi
    done

    # Output
    if [[ "$json_output" == "true" ]]; then
        doctor_output_json
    else
        echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
        echo -e "${MAGENTA}  Claude Octopus Doctor${NC}"
        echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
        doctor_output_human "$verbose"
    fi
}
