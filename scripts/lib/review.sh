#!/usr/bin/env bash
_agent_spec_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_agent_spec_lib_dir}/agent-spec.sh" 2>/dev/null || true
# Claude Octopus — Code Review Pipeline
# Extracted from orchestrate.sh
# Source-safe: no main execution block.

# ═══════════════════════════════════════════════════════════════════════════
# CODE REVIEW PIPELINE (v8.50.0)
# review_run() — multi-LLM competitor to CC Code Review managed service
# ═══════════════════════════════════════════════════════════════════════════

# parse_review_md: reads REVIEW.md from repo root, outputs directive vars
# WHY: CC Code Review supports REVIEW.md for customization; we match that
# convention so repos already configured for CC work with /octo:review too.
# shellcheck disable=SC2120 # repo_root is optional by design; callers rely on
# the git-toplevel default. Older ShellCheck releases flag this.
parse_review_md() {
    local repo_root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
    local review_md="$repo_root/REVIEW.md"

    REVIEW_ALWAYS_CHECK=""
    REVIEW_STYLE_RULES=""
    REVIEW_SKIP_PATTERNS=""

    [[ ! -f "$review_md" ]] && return 0

    local section=""
    while IFS= read -r line; do
        case "$line" in
            "## Always check"|"## Always Check") section="always" ;;
            "## Style")                          section="style" ;;
            "## Skip")                           section="skip" ;;
            "## "*)                              section="" ;;
            "- "*)
                local item="${line#- }"
                case "$section" in
                    always) REVIEW_ALWAYS_CHECK+="${item}"$'\n' ;;
                    style)  REVIEW_STYLE_RULES+="${item}"$'\n' ;;
                    skip)   REVIEW_SKIP_PATTERNS+="${item}"$'\n' ;;
                esac
                ;;
        esac
    done < "$review_md"

    log DEBUG "parse_review_md: always=$(echo "$REVIEW_ALWAYS_CHECK" | wc -l) style=$(echo "$REVIEW_STYLE_RULES" | wc -l) skip=$(echo "$REVIEW_SKIP_PATTERNS" | wc -l)"
}

# _review_fleet_from_config (v9.31.0): build fleet from routing.features.review
# in providers.json. /octo:model-config wizard already writes a "Review providers"
# array to this path; before this change there was no consumer, so the wizard's
# selection had no effect. Returns empty when config absent/empty so callers fall
# back to the cascade.
# Output: agent_type:role:specialty triples, newline-separated.
_review_fleet_from_config() {
    local config_file="${HOME}/.claude-octopus/config/providers.json"
    [[ ! -f "$config_file" ]] && return 0
    command -v jq >/dev/null 2>&1 || return 0

    local participants
    participants=$(jq -r '
        (.routing.features.review // [])
        | if type == "array" then .[] else empty end
    ' "$config_file" 2>/dev/null)
    [[ -z "$participants" ]] && return 0

    local fleet=""
    local has_logic=false has_security=false has_arch=false has_cve=false has_diversity=false

    while IFS= read -r provider; do
        [[ -z "$provider" ]] && continue
        case "$provider" in
            codex|codex-*)
                if [[ "$has_logic" == "false" ]]; then
                    fleet+="${provider}:implementation-logic-reviewer:correctness and logic bugs, edge cases, regressions"$'\n'
                    has_logic=true
                fi
                ;;
            opencode|opencode-*)
                if [[ "$has_logic" == "false" ]]; then
                    fleet+="${provider}:implementation-logic-reviewer:correctness and logic bugs, edge cases, regressions"$'\n'
                    has_logic=true
                fi
                ;;
            agy|agy-*|antigravity|gemini|gemini-*)
                if [[ "$has_security" == "false" ]]; then
                    fleet+="agy:implementation-security-reviewer:OWASP vulnerabilities, injection, auth flaws, data exposure"$'\n'
                    has_security=true
                fi
                ;;
            claude|claude-sonnet|claude-opus)
                if [[ "$has_arch" == "false" ]]; then
                    local agent="${provider}"
                    [[ "$provider" == "claude" ]] && agent="claude-sonnet"
                    fleet+="${agent}:implementation-architecture-reviewer:architecture, integration, API contracts, breaking changes"$'\n'
                    has_arch=true
                fi
                ;;
            perplexity|perplexity-*)
                if [[ "$has_cve" == "false" ]]; then
                    fleet+="${provider}:implementation-cve-reviewer:known CVEs, library advisories, live web search"$'\n'
                    has_cve=true
                fi
                ;;
            openrouter|openrouter-*)
                if [[ "$has_diversity" == "false" ]]; then
                    fleet+="${provider}:implementation-diversity-reviewer:cross-family perspective on logic, missed assumptions, training-data divergence from primary providers"$'\n'
                    has_diversity=true
                fi
                ;;
            openai-compatible|openai-tools|openai-compatible-agent*)
                if [[ "$has_logic" == "false" ]]; then
                    fleet+="${provider}:implementation-logic-reviewer:correctness and logic bugs, edge cases, regressions"$'\n'
                    has_logic=true
                elif [[ "$has_diversity" == "false" ]]; then
                    fleet+="${provider}:implementation-diversity-reviewer:OpenAI-compatible independent review path"$'\n'
                    has_diversity=true
                fi
                ;;
            qwen|qwen-*)
                if [[ "$has_security" == "false" ]]; then
                    fleet+="${provider}:implementation-security-reviewer:OWASP vulnerabilities, injection, auth flaws, data exposure"$'\n'
                    has_security=true
                elif [[ "$has_diversity" == "false" ]]; then
                    fleet+="${provider}:implementation-diversity-reviewer:cross-family perspective on logic and assumptions"$'\n'
                    has_diversity=true
                fi
                ;;
            copilot|copilot-*)
                if [[ "$has_cve" == "false" ]]; then
                    fleet+="${provider}:implementation-cve-reviewer:known CVEs via web search, library advisories"$'\n'
                    has_cve=true
                elif [[ "$has_diversity" == "false" ]]; then
                    fleet+="${provider}:implementation-diversity-reviewer:cross-perspective review"$'\n'
                    has_diversity=true
                fi
                ;;
        esac
    done <<< "$participants"

    [[ -z "$fleet" ]] && return 0

    # Anchor: always include arch-reviewer (claude-sonnet) if config didn't supply one.
    # Architecture context bridges per-finding noise from the specialist agents.
    if [[ "$has_arch" == "false" ]]; then
        fleet+="claude-sonnet:implementation-architecture-reviewer:architecture, integration, API contracts, breaking changes"$'\n'
    fi

    log INFO "review fleet: config-driven (.routing.features.review)"
    echo "$fleet"
}

# build_review_fleet: builds active agent list. Config-driven if
# .routing.features.review is set in ~/.claude-octopus/config/providers.json
# (the path /octo:model-config writes to); otherwise falls back to the original
# command -v cascade so existing installations are unchanged.
# Returns a newline-separated list of "agent_type:role:specialty" triples.
# NOTE: Uses command -v for provider detection — safe with set -euo pipefail.
review_single_provider_override() {
    local provider="${OCTOPUS_REVIEW_SINGLE_PROVIDER:-}"
    [[ -n "$provider" ]] || return 1
    [[ "$provider" =~ ^[A-Za-z0-9_-]+$ ]] || {
        log ERROR "Invalid OCTOPUS_REVIEW_SINGLE_PROVIDER: $provider"
        return 2
    }
    if [[ -n "${AVAILABLE_AGENTS:-}" && " $AVAILABLE_AGENTS " != *" $provider "* ]]; then
        log ERROR "Unknown OCTOPUS_REVIEW_SINGLE_PROVIDER: $provider"
        return 2
    fi
    printf '%s\n' "$provider"
}

review_phase_provider() {
    local default_provider="$1"
    local override=""
    if [[ -n "${OCTOPUS_REVIEW_SINGLE_PROVIDER:-}" ]]; then
        override="$(review_single_provider_override)" || return $?
        printf '%s\n' "$override"
    else
        printf '%s\n' "$default_provider"
    fi
}

build_review_fleet() {
    local fleet=""

    if [[ -n "${OCTOPUS_REVIEW_SINGLE_PROVIDER:-}" ]]; then
        local override_provider
        override_provider="$(review_single_provider_override)" || return $?
        printf '%s:%s:%s\n' \
            "$override_provider" \
            "general-reviewer" \
            "correctness, security, architecture, API contracts, regressions, and dependency risks"
        return 0
    fi

    # v9.31.0: honor wizard-configured participants if present
    fleet=$(_review_fleet_from_config)
    if [[ -n "$fleet" ]]; then
        echo "$fleet"
        return 0
    fi

    # ── Cascade fallback (original behavior — no config or empty config) ──

    # logic-reviewer: Codex (OpenAI) → OpenCode → Copilot → claude-sonnet fallback
    if command -v codex >/dev/null 2>&1; then
        fleet+="codex:implementation-logic-reviewer:correctness and logic bugs, edge cases, regressions"$'\n'
    elif command -v opencode >/dev/null 2>&1; then
        fleet+="opencode:implementation-logic-reviewer:correctness and logic bugs, edge cases, regressions"$'\n'
    elif command -v copilot >/dev/null 2>&1; then
        fleet+="copilot:implementation-logic-reviewer:correctness and logic bugs, edge cases, regressions"$'\n'
    else
        fleet+="claude-sonnet:implementation-logic-reviewer:correctness and logic bugs, edge cases, regressions"$'\n'
    fi

    # security-reviewer: AGY (Google) → Qwen → Copilot → claude-sonnet fallback
    # Prefer different family from logic-reviewer for diversity
    if command -v agy >/dev/null 2>&1; then
        fleet+="agy:implementation-security-reviewer:OWASP vulnerabilities, injection, auth flaws, data exposure"$'\n'
    elif command -v qwen >/dev/null 2>&1; then
        fleet+="qwen:implementation-security-reviewer:OWASP vulnerabilities, injection, auth flaws, data exposure"$'\n'
    elif command -v copilot >/dev/null 2>&1; then
        fleet+="copilot:implementation-security-reviewer:OWASP vulnerabilities, injection, auth flaws, data exposure"$'\n'
    else
        fleet+="claude-sonnet:implementation-security-reviewer:OWASP vulnerabilities, injection, auth flaws, data exposure"$'\n'
    fi

    # arch-reviewer: claude-sonnet (always available — best at holistic analysis)
    fleet+="claude-sonnet:implementation-architecture-reviewer:architecture, integration, API contracts, breaking changes"$'\n'

    # cve-reviewer: Perplexity → AGY → Copilot → Qwen → claude WebSearch
    if command -v perplexity >/dev/null 2>&1 || [[ -n "${PERPLEXITY_API_KEY:-}" ]]; then
        fleet+="perplexity:implementation-cve-reviewer:known CVEs, library advisories, live web search"$'\n'
    elif command -v agy >/dev/null 2>&1; then
        fleet+="agy:implementation-cve-reviewer:known CVEs and library advisories"$'\n'
        log INFO "CVE lookup: Perplexity unavailable, using AGY"
    elif command -v copilot >/dev/null 2>&1; then
        fleet+="copilot:implementation-cve-reviewer:known CVEs via web search, library advisories"$'\n'
        log INFO "CVE lookup: Perplexity+AGY unavailable, using Copilot"
    elif command -v qwen >/dev/null 2>&1; then
        fleet+="qwen:implementation-cve-reviewer:known CVEs via web search, library advisories"$'\n'
        log INFO "CVE lookup: Perplexity+AGY unavailable, using Qwen"
    else
        fleet+="claude-sonnet:implementation-cve-reviewer:known CVEs via WebSearch tool, library advisories"$'\n'
        log WARN "CVE lookup: no dedicated web-search provider, using Claude WebSearch (degraded)"
    fi

    echo "$fleet"
}

review_file_mtime_epoch() {
    local file="$1"
    stat -c '%Y' "$file" 2>/dev/null || stat -f '%m' "$file" 2>/dev/null || echo 0
}

review_hash_stdin() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    else
        cksum | awk '{print $1}'
    fi
}

review_progress_fingerprint_since() {
    local since_epoch="$1"
    local results_dir="${2:-${RESULTS_DIR:-${HOME}/.claude-octopus/results}}"
    # Optional filename pattern scopes the fingerprint to one agent's artifacts.
    # Without it, any concurrent activity in the shared RESULTS_DIR resets the
    # stall timer for every agent, so a genuinely hung provider never trips it.
    local name_pattern="${3:-*}"
    [[ -d "$results_dir" ]] || { echo "empty"; return 0; }
    find "$results_dir" -maxdepth 1 -type f -name "$name_pattern" 2>/dev/null | while IFS= read -r file; do
        local mtime size
        mtime=$(review_file_mtime_epoch "$file")
        [[ "$mtime" =~ ^[0-9]+$ ]] || mtime=0
        [[ "$mtime" -ge "$since_epoch" ]] || continue
        size=$(wc -c < "$file" 2>/dev/null || echo 0)
        size=${size//[[:space:]]/}
        printf '%s %s %s\n' "$file" "${size:-0}" "$mtime"
    done | sort | review_hash_stdin
}

# Enumerate direct children portably. procps pgrep is preferred, while the ps
# fallback covers minimal Linux images and macOS without adding a dependency.
review_child_pids() {
    local parent_pid="$1" child_pid child_parent process_rows=""
    if command -v pgrep >/dev/null 2>&1; then
        if pgrep -P "$parent_pid" 2>/dev/null; then
            return 0
        fi
    fi
    command -v ps >/dev/null 2>&1 || return 0
    process_rows=$(ps -A -o pid= -o ppid= 2>/dev/null) \
        || process_rows=$(ps -ax -o pid= -o ppid= 2>/dev/null) \
        || process_rows=""
    while read -r child_pid child_parent; do
        [[ "$child_parent" == "$parent_pid" ]] && printf '%s\n' "$child_pid"
    done <<< "$process_rows"
    return 0
}

# Snapshot descendants depth-first before signaling. Re-walking after TERM is
# unsafe because a TERM-ignoring child can be reparented when its wrapper exits,
# making it invisible to the later KILL pass.
review_process_tree_depth_first() {
    local pid="$1" child
    [[ "$pid" =~ ^[0-9]+$ ]] || return 0
    while IFS= read -r child; do
        [[ "$child" =~ ^[0-9]+$ ]] || continue
        review_process_tree_depth_first "$child"
    done < <(review_child_pids "$pid")
    printf '%s\n' "$pid"
}

# kill -0 still succeeds for unreaped zombies on macOS, so also inspect state.
review_process_is_running() {
    local pid="$1"
    local process_stat
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    process_stat=$(ps -o stat= -p "$pid" 2>/dev/null) || return 1
    [[ "$process_stat" != *Z* ]]
}

review_terminate_process_tree() {
    local root_pid="$1"
    local grace_secs="${2:-5}"
    local process_tree target_pid
    [[ "$grace_secs" =~ ^[0-9]+$ ]] || grace_secs=5
    grace_secs=$((10#$grace_secs))
    process_tree="$(review_process_tree_depth_first "$root_pid")"
    [[ -n "$process_tree" ]] || return 0

    while IFS= read -r target_pid; do
        [[ "$target_pid" =~ ^[0-9]+$ ]] || continue
        kill -TERM "$target_pid" 2>/dev/null || true
    done <<< "$process_tree"
    sleep "$grace_secs"
    while IFS= read -r target_pid; do
        [[ "$target_pid" =~ ^[0-9]+$ ]] || continue
        kill -KILL "$target_pid" 2>/dev/null || true
    done <<< "$process_tree"
}

# Strict v10 teardown wrapper. Snapshot first so descendants remain verifiable
# even if their parent exits and they are reparented during TERM handling.
octo_terminate_process_tree() {
    local root_pid="${1:-}" grace_secs="${2:-1}" process_tree="" target_pid
    OCTO_PROCESS_CLEANUP_RESULT="no-process"
    [[ "$root_pid" =~ ^[1-9][0-9]*$ && "$root_pid" != "1" ]] || return 0

    if ! review_process_is_running "$root_pid"; then
        OCTO_PROCESS_CLEANUP_RESULT="already-exited"
        return 0
    fi

    process_tree="$(review_process_tree_depth_first "$root_pid")"
    review_terminate_process_tree "$root_pid" "$grace_secs"
    wait "$root_pid" 2>/dev/null || true

    # SIGKILL delivery and reaping are asynchronous for descendants that were
    # reparented when the root exited. Allow a bounded settle window before
    # deciding that any member survived.
    local settle_tick any_running
    for settle_tick in $(seq 1 50); do
        any_running=false
        while IFS= read -r target_pid; do
            [[ "$target_pid" =~ ^[0-9]+$ ]] || continue
            if review_process_is_running "$target_pid"; then
                any_running=true
                break
            fi
        done <<< "$process_tree"
        [[ "$any_running" == false ]] && break
        sleep 0.1
    done

    while IFS= read -r target_pid; do
        [[ "$target_pid" =~ ^[0-9]+$ ]] || continue
        if review_process_is_running "$target_pid"; then
            OCTO_PROCESS_CLEANUP_RESULT="survived"
            return 1
        fi
    done <<< "$process_tree"

    # shellcheck disable=SC2034 # output contract consumed by cancellation callers
    OCTO_PROCESS_CLEANUP_RESULT="terminated"
    return 0
}

# Cancellation is stricter than ordinary timeout cleanup. Freeze each root
# before walking it so a shell cannot advance to another provider attempt while
# teardown is enumerating descendants, then kill the frozen tree bottom-up.
review_kill_process_tree_frozen() {
    local root_pid="$1" child children current_pgid=""
    [[ "$root_pid" =~ ^[1-9][0-9]*$ ]] || return 0
    [[ "$root_pid" != "1" ]] || return 0

    current_pgid=$(ps -o pgid= -p "$$" 2>/dev/null | tr -d '[:space:]') \
        || current_pgid=""
    if [[ "$root_pid" == "$$" ]] \
       || [[ -n "$current_pgid" && "$root_pid" == "$current_pgid" ]]; then
        return 0
    fi

    # Snapshot legacy children before signaling. If the wrapper exits during
    # the group probe or STOP, this preserves every descendant that was still
    # discoverable while the wrapper was alive.
    children="$(review_child_pids "$root_pid")"

    # spawn_agent places each worker in a dedicated process group whose PGID is
    # the recorded worker PID. Signaling the group is atomic and still works if
    # the group leader exited after spawning a provider child. Legacy callers
    # are not group leaders, so a missing -PGID safely falls through to the
    # portable descendant walk below.
    if kill -STOP -- "-$root_pid" 2>/dev/null; then
        kill -KILL -- "-$root_pid" 2>/dev/null || true
        return 0
    fi

    kill -STOP "$root_pid" 2>/dev/null || true
    while IFS= read -r child; do
        [[ "$child" =~ ^[0-9]+$ ]] || continue
        review_kill_process_tree_frozen "$child"
    done <<< "$children"
    kill -KILL "$root_pid" 2>/dev/null || true
}

review_kill_descendants_frozen() {
    local root_pid="$1" child children
    [[ "$root_pid" =~ ^[0-9]+$ ]] || return 0
    children="$(review_child_pids "$root_pid")"
    while IFS= read -r child; do
        [[ "$child" =~ ^[0-9]+$ ]] || continue
        kill -STOP "$child" 2>/dev/null || true
    done <<< "$children"
    while IFS= read -r child; do
        [[ "$child" =~ ^[0-9]+$ ]] || continue
        review_kill_process_tree_frozen "$child"
    done <<< "$children"
}

review_process_has_active_descendant() {
    local root_pid="$1" child
    [[ "$root_pid" =~ ^[0-9]+$ ]] || return 1
    while IFS= read -r child; do
        [[ "$child" =~ ^[0-9]+$ ]] || continue
        review_process_is_running "$child" && return 0
        review_process_has_active_descendant "$child" && return 0
    done < <(review_child_pids "$root_pid")
    return 1
}

review_run_agent_sync_progress() {
    local agent_type="$1"
    local prompt="$2"
    local role="$3"
    local phase="$4"
    local label="${5:-sync}"
    local results_dir="${RESULTS_DIR:-${HOME}/.claude-octopus/results}"
    local stall_window="${OCTOPUS_REVIEW_STALL_WINDOW:-1800}"
    local poll_secs="${OCTOPUS_REVIEW_POLL_SECS:-30}"
    [[ "$stall_window" =~ ^[0-9]+$ ]] || stall_window=1800
    [[ "$poll_secs" =~ ^[0-9]+$ ]] || poll_secs=30
    stall_window=$((10#$stall_window))
    poll_secs=$((10#$poll_secs))
    [[ "$poll_secs" -lt 1 ]] && poll_secs=1
    mkdir -p "$results_dir" 2>/dev/null || true

    local start_epoch out_file rc_file pid rc last_progress last_fp current_fp now
    start_epoch=$(date +%s)
    out_file="${results_dir}/.tmp-review-sync-${label}-$$-${RANDOM}.out"
    rc_file="${out_file}.rc"
    : > "$out_file"
    rm -f "$rc_file" 2>/dev/null || true

    (
        run_agent_sync "$agent_type" "$prompt" 0 "$role" "$phase" > "$out_file" 2>&1
        echo "$?" > "$rc_file"
    ) &
    pid=$!
    last_progress=$(date +%s)
    local own_pattern
    own_pattern="$(basename "$out_file")*"
    last_fp=$(review_progress_fingerprint_since "$start_epoch" "$results_dir" "$own_pattern")

    while review_process_is_running "$pid"; do
        sleep "$poll_secs"
        now=$(date +%s)
        current_fp=$(review_progress_fingerprint_since "$start_epoch" "$results_dir" "$own_pattern")
        if [[ "$current_fp" != "$last_fp" ]]; then
            last_fp="$current_fp"
            last_progress="$now"
            log INFO "review_run: ${label} progress observed"
        elif [[ "$stall_window" -gt 0 && $((now - last_progress)) -ge "$stall_window" ]]; then
            log WARN "review_run: ${label} stalled after ${stall_window}s with no observable progress — stopping provider and preserving partial output"
            review_terminate_process_tree "$pid" 5
            break
        fi
    done

    wait "$pid" 2>/dev/null || true
    rc=1
    [[ -f "$rc_file" ]] && rc=$(cat "$rc_file" 2>/dev/null || echo 1)
    cat "$out_file" 2>/dev/null || true
    rm -f "$out_file" "$rc_file" 2>/dev/null || true
    return "$rc"
}

# review_openai_compat_empty_output_retryable: returns true for transient OpenAI-compatible adapter
# review failures where the CLI exited with Empty output after reconnects. These
# are usually provider-side transient stream/session failures rather than review
# conclusions, so Round 1 may retry them once after backoff.
review_openai_compat_empty_output_retryable() {
    local result_file="$1"
    local agent_type="$2"
    [[ "$agent_type" == codex* ]] || return 1
    [[ -f "$result_file" ]] || return 1
    local empty_count reconnect_count
    empty_count=$(grep -cE '^## Status: FAILED \(Empty output\)' "$result_file" 2>/dev/null || true)
    empty_count=${empty_count:-0}
    reconnect_count=$(grep -c 'Reconnecting' "$result_file" 2>/dev/null || true)
    reconnect_count=${reconnect_count:-0}
    [[ "${empty_count%%$'\n'*}" -gt 0 ]] || return 1
    [[ "${reconnect_count%%$'\n'*}" -gt 0 ]] || return 1
}

review_result_has_terminal_status() {
    local result_file="$1"
    local terminal_count
    [[ -f "$result_file" ]] || return 1
    terminal_count=$(grep -cE '^## Status: (SUCCESS|FAILED|TIMEOUT)([[:space:](]|$)' "$result_file" 2>/dev/null || true)
    [[ "${terminal_count:-0}" -gt 0 ]]
}

review_result_completed_successfully() {
    local result_file="$1"
    local final_status
    [[ -f "$result_file" ]] || return 1
    final_status=$(awk '
        /^## Status: (SUCCESS|FAILED|TIMEOUT)([[:space:](]|$)/ {
            status = $0
            sub(/^## Status: /, "", status)
            sub(/[[:space:](].*$/, "", status)
        }
        END { print status }
    ' "$result_file" 2>/dev/null || true)
    [[ "$final_status" == "SUCCESS" ]]
}

# Return the first meaningful provider failure. Prefer real Output, then scan
# Error Log for the last actionable line when the provider produced no stdout.
# Keep the status-file delimiter out of the detail and cap pathological output,
# while retaining enough text for an actionable CI comment (#893).
review_result_failure_detail() {
    local result_file="$1"
    [[ -f "$result_file" ]] || return 1
    awk '
        function clean(line) {
            gsub(/\|/, "/", line)
            gsub(/\033\[[0-9;]*[[:alpha:]]/, "", line)
            return substr(line, 1, 240)
        }
        /^## Output$/ { section="output"; next }
        /^## Error Log$/ { section="error"; next }
        /^## / { section=""; next }
        section != "" {
            line=$0
            if (line ~ /^```/ || line ~ /^[[:space:]]*$/) next
            line=clean(line)
            if (section == "output") {
                if (line !~ /^\(no output captured/) {
                    print line
                    found=1
                    exit
                }
                output_fallback=line
            } else {
                lower=tolower(line)
                if (lower ~ /(error|failed|denied|forbidden|unauthor|quota|limit|retir|unavailable|http [0-9])/) {
                    error_match=line
                } else if (error_fallback == "") {
                    error_fallback=line
                }
            }
        }
        END {
            if (!found) {
                if (error_match != "") print error_match
                else if (error_fallback != "") print error_fallback
                else if (output_fallback != "") print output_fallback
            }
        }
    ' "$result_file" 2>/dev/null
}

review_provider_key_from_agent_type() {
    case "${1:-}" in
        openai-compatible*|openai-tools*) echo "openai-compatible" ;;
        claude-sdk*) echo "claude" ;;
        claude*) echo "claude" ;;
        copilot*) echo "copilot" ;;
        codex*) echo "codex" ;;
        agy*|antigravity|gemini*) echo "agy" ;;
        perplexity*) echo "perplexity" ;;
        *) printf '%s\n' "${1%%[-_]*}" ;;
    esac
}

# review_wait_for_result_status: waits for one result file to become terminal,
# using the same progress-stall semantics as Round 1. No wall-clock cap.
review_wait_for_result_status() {
    local result_file="$1"
    local pid="$2"
    local label="$3"
    local results_dir="${4:-${RESULTS_DIR:-${HOME}/.claude-octopus/results}}"
    local stall_window="${5:-${OCTOPUS_REVIEW_STALL_WINDOW:-1800}}"
    local poll_secs="${6:-${OCTOPUS_REVIEW_POLL_SECS:-30}}"
    local poll_start last_progress last_fp current_fp
    [[ "$stall_window" =~ ^[0-9]+$ ]] || stall_window=1800
    [[ "$poll_secs" =~ ^[0-9]+$ ]] || poll_secs=30
    stall_window=$((10#$stall_window))
    poll_secs=$((10#$poll_secs))
    [[ "$poll_secs" -lt 1 ]] && poll_secs=1
    poll_start=$(date +%s)
    last_progress="$poll_start"
    local own_pattern
    own_pattern="$(basename "$result_file")*"
    last_fp=$(review_progress_fingerprint_since "$poll_start" "$results_dir" "$own_pattern")
    while true; do
        if review_result_has_terminal_status "$result_file"; then
            break
        fi
        if ! review_process_is_running "$pid"; then
            log WARN "review_run: ${label} exited without a terminal status"
            break
        fi
        current_fp=$(review_progress_fingerprint_since "$poll_start" "$results_dir" "$own_pattern")
        if [[ "$current_fp" != "$last_fp" ]]; then
            last_fp="$current_fp"
            last_progress=$(date +%s)
            log INFO "review_run: ${label} progress observed"
        elif [[ "$stall_window" -gt 0 && $(( $(date +%s) - last_progress )) -ge "$stall_window" ]]; then
            log WARN "review_run: ${label} stalled after ${stall_window}s — stopping retry"
            review_terminate_process_tree "$pid" 5
            break
        fi
        sleep "$poll_secs"
    done
    wait "$pid" 2>/dev/null || true
}

# review_supervise_round1: monitor each Round 1 provider independently so
# progress from one provider cannot keep a stalled peer alive. The round1_*
# arrays are intentionally resolved through Bash's dynamic function scope;
# review_run owns them, while unit tests can supply a minimal observable fleet.
# shellcheck disable=SC2154
review_supervise_round1() {
    local review_stall_window="$1"
    local review_poll_secs="$2"
    local results_dir="$3"
    local _poll_start _now _idx _rf _pid _current_fp _round1_active
    local round1_last_progress=()
    local round1_last_fp=()
    local round1_settled=()

    [[ "$review_stall_window" =~ ^[0-9]+$ ]] || review_stall_window=1800
    [[ "$review_poll_secs" =~ ^[0-9]+$ ]] || review_poll_secs=30
    review_stall_window=$((10#$review_stall_window))
    review_poll_secs=$((10#$review_poll_secs))
    [[ "$review_poll_secs" -lt 1 ]] && review_poll_secs=1

    _poll_start=$(date +%s)
    _idx=0
    while [[ "$_idx" -lt "${#round1_files[@]}" ]]; do
        _rf="${round1_files[$_idx]}"
        round1_last_progress[$_idx]="$_poll_start"
        round1_last_fp[$_idx]=$(review_progress_fingerprint_since "$_poll_start" "$results_dir" "$(basename "$_rf")*")
        round1_settled[$_idx]=false
        ((_idx++)) || true
    done

    while true; do
        _round1_active=false
        _now=$(date +%s)
        _idx=0
        while [[ "$_idx" -lt "${#round1_files[@]}" ]]; do
            if [[ "${round1_settled[$_idx]:-false}" == "true" ]]; then
                ((_idx++)) || true
                continue
            fi

            _rf="${round1_files[$_idx]}"
            _pid="${round1_pids[$_idx]}"
            if review_result_has_terminal_status "$_rf"; then
                round1_settled[$_idx]=true
                ((_idx++)) || true
                continue
            fi
            if ! review_process_is_running "$_pid"; then
                log WARN "review_run: Round 1 ${round1_agent_types[$_idx]}/${round1_roles[$_idx]} exited without a terminal status"
                round1_settled[$_idx]=true
                ((_idx++)) || true
                continue
            fi

            _current_fp=$(review_progress_fingerprint_since "$_poll_start" "$results_dir" "$(basename "$_rf")*")
            if [[ "$_current_fp" != "${round1_last_fp[$_idx]}" ]]; then
                round1_last_fp[$_idx]="$_current_fp"
                round1_last_progress[$_idx]="$_now"
                log INFO "review_run: Round 1 ${round1_agent_types[$_idx]}/${round1_roles[$_idx]} progress observed"
            elif [[ "$review_stall_window" -gt 0 && $((_now - ${round1_last_progress[$_idx]})) -ge "$review_stall_window" ]]; then
                log WARN "review_run: Round 1 ${round1_agent_types[$_idx]}/${round1_roles[$_idx]} stalled after ${review_stall_window}s — collecting partial result"
                review_terminate_process_tree "$_pid" 5
                round1_settled[$_idx]=true
                ((_idx++)) || true
                continue
            fi

            _round1_active=true
            ((_idx++)) || true
        done

        [[ "$_round1_active" == "false" ]] && break
        sleep "$review_poll_secs"
    done
    for _pid in "${round1_pids[@]}"; do wait "$_pid" 2>/dev/null || true; done
}

# review_extract_output_text: print only the Output block associated with the final artifact status boundary.
review_extract_output_text() {
    local review_md="$1"
    [[ -f "$review_md" ]] || return 1
    awk '''
        /^## Output$/ { in_output=1; candidate=""; next }
        /^## Status:/ { if (in_output) selected=candidate; in_output=0; next }
        /^## / { in_output=0; next }
        in_output && !/^```(json|JSON)?$/ { candidate = candidate (candidate == "" ? "" : "\n") $0 }
        END { if (selected != "") print selected }
    ''' "$review_md" 2>/dev/null
}

review_output_has_finding_signal() {
    local output_text="$1"
    [[ -n "$output_text" ]] || return 1
    printf '%s' "$output_text" | grep -Eq '''(^|[^[:alnum:]_])"?severity"?[[:space:]]*:'''
}

review_extract_findings_text() {
    local output_text="$1"
    local direct_json
    [[ -n "$output_text" ]] || { echo "[]"; return 1; }
    direct_json=$(printf '%s' "$output_text" | jq -cs '[.[] | objects | .findings | select(type == "array" and length > 0)] | last // []' 2>/dev/null || true)
    if [[ -n "$direct_json" && "$direct_json" != "null" ]]; then
        printf '%s\n' "$direct_json"
        return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$output_text" | python3 -c '
import json, sys
text = sys.stdin.read()
decoder = json.JSONDecoder()
best = None
idx = 0
while True:
    idx = text.find("{", idx)
    if idx < 0:
        break
    try:
        obj, end = decoder.raw_decode(text[idx:])
    except Exception:
        idx += 1
        continue
    if isinstance(obj, dict) and isinstance(obj.get("findings"), list):
        if obj["findings"]:
            best = obj["findings"]
        elif best is None:
            best = obj["findings"]
    idx += max(1, end)
if best is None:
    print("[]")
    sys.exit(1)
print(json.dumps(best, separators=(",", ":")))
'
        return $?
    fi
    echo "[]"
    return 1
}

review_extract_findings_array() {
    local review_md="$1"
    local output_text
    [[ -f "$review_md" ]] || { echo "[]"; return 1; }
    output_text=$(review_extract_output_text "$review_md" 2>/dev/null || true)
    review_extract_findings_text "$output_text"
}

review_recover_malformed_findings() {
    local agent_type="$1"
    local role="$2"
    local malformed_output="$3"
    local label="${4:-malformed-output-recovery}"
    local max_chars="${OCTOPUS_REVIEW_MALFORMED_RECOVERY_CHARS:-20000}"
    [[ "$max_chars" =~ ^[1-9][0-9]*$ ]] || max_chars=20000
    max_chars=$((10#$max_chars))
    malformed_output="${malformed_output:0:$max_chars}"

    local recovery_prompt="Your previous code-review response completed successfully, but its Output could not be parsed as valid JSON.

The text below is your own previous response. Do NOT re-review the code. Do NOT add new findings, remove findings, or reinterpret severity or meaning. Reformat exactly the same findings into ONE valid JSON object with this shape:

{\"findings\":[{\"file\":\"...\",\"line\":1,\"severity\":\"normal|nit|pre-existing\",\"category\":\"...\",\"title\":\"...\",\"detail\":\"...\",\"confidence\":0.9}]}

Return JSON only. No Markdown fences, prose, commentary, or extra keys.

PREVIOUS_REVIEW_OUTPUT:
-----
${malformed_output}
-----"

    local recovery_output=""
    if ! recovery_output=$(review_run_agent_sync_progress "$agent_type" "$recovery_prompt" "$role" "review" "$label" 2>/dev/null); then
        return 1
    fi
    local recovered
    recovered=$(review_extract_findings_text "$recovery_output" 2>/dev/null || true)
    [[ -n "$recovered" && "$recovered" != "[]" ]] || return 1
    printf '%s\n' "$recovered"
}

# Provider output is untrusted and may contain multiple top-level JSON values.
# Canonicalize exactly one findings document before any arithmetic, rendering,
# or persistence. Multiple documents are rejected rather than concatenated,
# and exact duplicate findings collapse to one deterministic entry.
review_normalize_findings_json() {
    jq -cse '
        if length == 1
           and (.[0] | type == "object")
           and (.[0].findings | type == "array")
           and all(.[0].findings[]; type == "object")
        then .[0]
             | .findings |= (
                 reduce .[] as $finding
                   ({seen:{}, ordered:[]};
                    ($finding | [
                      (.file // ""),
                      ((.line // 0) | tostring),
                      (.category // ""),
                      (.title // .message // "")
                    ] | @json) as $key
                    | if .seen[$key]
                      then .
                      else .seen[$key] = true | .ordered += [$finding]
                      end)
                 | .ordered
               )
        else error("expected exactly one object with a findings array")
        end
    '
}

# Print exactly one validated non-negative integer for a canonical findings
# document. Invalid or multi-document input fails with no stdout so callers can
# choose an explicit fail-closed behavior without creating a `0\n0` scalar.
review_findings_count() {
    local findings_json="$1"
    printf '%s' "$findings_json" | jq -er -s '
        if length == 1
           and (.[0] | type == "object")
           and (.[0].findings | type == "array")
           and all(.[0].findings[]; type == "object")
        then (.[0].findings | length)
        else error("invalid findings document")
        end
    ' 2>/dev/null
}

review_local_synthesis_json() {
    local findings_json="$1"
    local warning="${2:-}"
    local sort_filter='def severity_rank: if .severity == "normal" then 0 elif .severity == "nit" then 1 elif .severity == "pre-existing" then 2 else 3 end; if all(.[]; type == "object") then to_entries | reduce .[] as $entry ({seen:{}, ordered:[]}; ($entry.value | [(.file // ""), ((.line // 0) | tostring), (.category // ""), (.title // .message // "")] | @json) as $key | if .seen[$key] then . else .seen[$key] = true | .ordered += [$entry] end) | .ordered | sort_by([(.value | severity_rank), .key]) | map(.value) else error("expected object findings entries") end'
    if [[ -n "$warning" ]]; then
        printf '%s' "$findings_json" | jq -c --arg warning "$warning" "{findings:(. // [] | ${sort_filter}), warning:\$warning}" 2>/dev/null \
            || printf '{"findings":[],"warning":%s}\n' "$(printf '%s' "$warning" | jq -R .)"
    else
        printf '%s' "$findings_json" | jq -c \
            "{findings:(. // [] | ${sort_filter})}" 2>/dev/null \
            || echo '{"findings":[]}'
    fi
}

# review_collect_working_tree_diff: collects tracked and untracked working-tree changes.
review_collect_working_tree_diff() {
    local diff_content=""
    local path=""
    local file_diff=""
    diff_content=$(git diff 2>/dev/null || true)

    while IFS= read -r -d '' path; do
        file_diff=$(git diff --no-index -- /dev/null "$path" 2>/dev/null || true)
        if [[ -n "$file_diff" ]]; then
            [[ -n "$diff_content" ]] && diff_content+=$'\n'
            diff_content+="$file_diff"
        fi
    done < <(git ls-files --others --exclude-standard -z 2>/dev/null)

    printf '%s' "$diff_content"
}

# review_collect_diff: resolves a review target to unified diff content.
# Targets can be built-in scopes (staged, working-tree), a PR number, a git
# pathspec, or an already-generated .diff/.patch file.
review_collect_diff() {
    local target="$1"
    local diff_content=""

    case "$target" in
        staged)       diff_content=$(git diff --cached 2>/dev/null || true) ;;
        working-tree) diff_content=$(review_collect_working_tree_diff) ;;
        [0-9]*)       diff_content=$(gh pr diff "$target" 2>/dev/null || true) ;;
        *)
            if [[ -f "$target" ]] && [[ -r "$target" ]] && head -n 20 "$target" 2>/dev/null | grep -Ec "^(diff --git|--- |\+\+\+ |@@ )" >/dev/null; then
                diff_content=$(cat "$target" 2>/dev/null || true)
            else
                diff_content=$(git diff HEAD -- "$target" 2>/dev/null || true)
            fi
            ;;
    esac

    printf '%s' "$diff_content"
}

# review_run: canonical 3-round multi-LLM code review pipeline
# WHY: replaces the single-model "codex exec review" dispatch with a
# v9.0: Provider report card — prints post-run summary of provider status
# Args: provider_status_file (one line per event: "provider|status|detail")
# WHY: Mid-stream warnings vanish in terminal scroll. This prints AFTER all output,
# making provider failures impossible to miss.
print_provider_report() {
    local status_file="$1"
    local fallback_log="${HOME}/.claude-octopus/provider-fallbacks.log"

    if [[ ! -f "$status_file" ]]; then
        return 0
    fi

    # Determine status per provider
    local codex_status="not used" agy_status="not used" claude_status="not used" perplexity_status="not used" compatible_status="not used" copilot_status="not used"
    local codex_detail="" agy_detail="" claude_detail="" perplexity_detail="" compatible_detail="" copilot_detail=""
    local had_fallback=false

    while IFS='|' read -r provider status detail; do
        case "$provider" in
            codex)
                if [[ "$status" == "ok" ]]; then
                    codex_status="✓ OK"
                elif [[ "$status" == "fallback" ]]; then
                    codex_status="✗ FALLBACK"
                    codex_detail="$detail"
                    had_fallback=true
                elif [[ "$status" == "auth-failed" ]]; then
                    codex_status="✗ AUTH FAILED"
                    codex_detail="$detail"
                    had_fallback=true
                fi
                ;;
            agy|gemini)
                if [[ "$status" == "ok" ]]; then
                    agy_status="✓ OK"
                elif [[ "$status" == "fallback" ]]; then
                    agy_status="✗ FALLBACK"
                    agy_detail="$detail"
                    had_fallback=true
                fi
                ;;
            claude)
                if [[ "$status" == "ok" ]]; then
                    claude_status="✓ OK"
                elif [[ "$status" == "fallback" ]]; then
                    claude_status="✗ FALLBACK"
                    claude_detail="$detail"
                    had_fallback=true
                elif [[ "$status" == "auth-failed" ]]; then
                    claude_status="✗ AUTH FAILED"
                    claude_detail="$detail"
                    had_fallback=true
                fi
                ;;
            perplexity)
                if [[ "$status" == "ok" ]]; then
                    perplexity_status="✓ OK"
                elif [[ "$status" == "fallback" ]]; then
                    perplexity_status="✗ FALLBACK"
                    perplexity_detail="$detail"
                    had_fallback=true
                fi
                ;;
            openai-compatible|openai-tools|openai-compatible-agent)
                if [[ "$status" == "ok" ]]; then
                    compatible_status="✓ OK"
                elif [[ "$status" == "fallback" ]]; then
                    compatible_status="✗ FALLBACK"
                    compatible_detail="$detail"
                    had_fallback=true
                elif [[ "$status" == "auth-failed" ]]; then
                    compatible_status="✗ AUTH FAILED"
                    compatible_detail="$detail"
                    had_fallback=true
                fi
                ;;
            copilot)
                if [[ "$status" == "ok" ]]; then
                    copilot_status="✓ OK"
                elif [[ "$status" == "fallback" ]]; then
                    copilot_status="✗ FALLBACK"
                    copilot_detail="$detail"
                    had_fallback=true
                elif [[ "$status" == "auth-failed" ]]; then
                    copilot_status="✗ AUTH FAILED"
                    copilot_detail="$detail"
                    had_fallback=true
                fi
                ;;
        esac
    done < "$status_file"

    # Always print the report card
    echo ""
    echo "┌─────────────────────────────────────────────┐"
    echo "│ 🐙 Provider Status                          │"
    echo "│                                             │"
    printf "│ 🔴 Codex:      %-28s│\n" "$codex_status"
    [[ -n "$codex_detail" ]] && printf "│    → %-38.38s│\n" "$codex_detail"
    printf "│ 🧭 AGY:        %-28s│\n" "$agy_status"
    [[ -n "$agy_detail" ]] && printf "│    → %-38.38s│\n" "$agy_detail"
    printf "│ 🔵 Claude:     %-28s│\n" "$claude_status"
    [[ -n "$claude_detail" ]] && printf "│    → %-38.38s│\n" "$claude_detail"
    printf "│ 🟣 Perplexity: %-28s│\n" "$perplexity_status"
    [[ -n "$perplexity_detail" ]] && printf "│    → %-38.38s│\n" "$perplexity_detail"
    printf "│ 🟢 Compatible:  %-25s│\n" "$compatible_status"
    [[ -n "$compatible_detail" ]] && printf "│    → %-38.38s│\n" "$compatible_detail"
    printf "│ 🟡 Copilot:     %-27s│\n" "$copilot_status"
    [[ -n "$copilot_detail" ]] && printf "│    → %-38.38s│\n" "$copilot_detail"
    if [[ "$had_fallback" == "true" ]]; then
        echo "│                                             │"
        echo "│ ⚠ Some providers failed — run octopus doctor│"
    fi
    echo "└─────────────────────────────────────────────┘"

    if [[ "$had_fallback" == "true" ]]; then
        echo ""
        echo "Provider failure details:"
        while IFS='|' read -r provider status detail; do
            if [[ "$status" == "fallback" || "$status" == "auth-failed" ]]; then
                printf -- '- %s: %s\n' "$provider" "$detail"
            fi
        done < "$status_file"
    fi

    # Persist a bounded local history of review-provider failures.
    if [[ "$had_fallback" == "true" ]]; then
        mkdir -p "$(dirname "$fallback_log")"
        local ts
        ts=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
        while IFS='|' read -r provider status detail; do
            if [[ "$status" == "fallback" || "$status" == "auth-failed" ]]; then
                echo "[$ts] provider=$provider status=$status detail=$detail" >> "$fallback_log"
            fi
        done < "$status_file"
        # Keep only last 50 entries
        if [[ -f "$fallback_log" ]] && [[ $(wc -l < "$fallback_log") -gt 50 ]]; then
            tail -50 "$fallback_log" > "${fallback_log}.tmp" && mv "${fallback_log}.tmp" "$fallback_log"
        fi
    fi

    rm -f "$status_file"
}

# parallel fleet (Round 1) + verification (Round 2) + synthesis (Round 3)
# that competes with CC Code Review's managed service.
#
# Args: JSON profile string with fields:
#   target, focus, provenance, autonomy, publish, debate
review_run() {
    local _ts; _ts=$(date +%s)
    local profile_json="${1:-"{}"}"

    # Parse profile fields (with defaults)
    local target focus provenance autonomy publish debate history context_file context_text context_label
    target=$(echo "$profile_json"       | jq -r '.target       // "staged"')
    focus=$(echo "$profile_json"        | jq -r '.focus        // ["correctness","security","architecture","tdd"]  | join(",")')
    provenance=$(echo "$profile_json"   | jq -r '.provenance   // "unknown"')
    autonomy=$(echo "$profile_json"     | jq -r '.autonomy     // "supervised"')
    publish=$(echo "$profile_json"      | jq -r '.publish      // "ask"')
    debate=$(echo "$profile_json"       | jq -r '.debate       // "auto"')
    history=$(echo "$profile_json"      | jq -r '.history      // "auto"')
    context_file=$(echo "$profile_json" | jq -r '.contextFile  // .context_file  // empty')
    context_text=$(echo "$profile_json" | jq -r '.contextText  // .context_text  // empty')
    context_label=$(echo "$profile_json"| jq -r '.contextLabel // .context_label // "Review context / task contract"')
    if [[ "$target" == "fresh" ]]; then
        target="working-tree"
        history="fresh"
    fi

    # v9.0: Provider status tracking for post-run report card
    local provider_status_file
    provider_status_file=$(mktemp "${TMPDIR:-/tmp}/octopus-provider-status.XXXXXX")

    # v9.0: Preflight — check Codex auth before review pipeline. A deliberate
    # single-provider run keeps all phases on that provider and should not emit
    # unrelated Codex installation/auth warnings.
    if [[ -n "${OCTOPUS_REVIEW_SINGLE_PROVIDER:-}" ]]; then
        review_single_provider_override >/dev/null || {
            rm -f "$provider_status_file"
            return 1
        }
    elif command -v codex >/dev/null 2>&1; then
        if ! check_codex_auth_freshness 2>/dev/null; then
            log "WARN" "review_run: Codex auth may be stale — review fleet may fall back to claude-sonnet"
            log "USER" "⚠ Codex auth check failed. Run 'codex auth' or 'octopus doctor' to fix. Falling back to claude-sonnet for Codex roles."
            echo "codex|auth-failed|Run: codex auth" >> "$provider_status_file"
        fi
    else
        echo "codex|not-installed|Install: npm i -g @openai/codex" >> "$provider_status_file"
    fi

    local timestamp="$_ts"
    local results_dir="${RESULTS_DIR:-$HOME/.claude-octopus/results}"
    # Sync RESULTS_DIR global so spawn_agent writes to the same directory
    RESULTS_DIR="$results_dir"
    local findings_file="$results_dir/review-findings-${timestamp}.json"
    mkdir -p "$results_dir"

    local proof_dir=""
    if declare -F octo_proof_init >/dev/null 2>&1 && octo_proof_enabled; then
        proof_dir=$(octo_proof_init "review" "target=${target} focus=${focus}" "$profile_json" 2>/dev/null || true)
    fi

    local review_contract_context=""
    local review_context_chars="${OCTOPUS_REVIEW_CONTEXT_CHARS:-20000}"
    [[ "$review_context_chars" =~ ^[0-9]+$ ]] || review_context_chars=20000
    review_context_chars=$((10#$review_context_chars))
    [[ "$review_context_chars" -lt 1000 ]] && review_context_chars=1000

    local context_truncated="false"
    if [[ -n "$context_file" ]]; then
        local review_root=""
        local context_file_resolved=""
        review_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)
        review_root=$(cd "$review_root" 2>/dev/null && pwd -P || printf '%s' "$review_root")
        context_file_resolved=$(realpath "$context_file" 2>/dev/null || true)
        if [[ -z "$context_file_resolved" || ! -r "$context_file_resolved" ]]; then
            log ERROR "review_run: contextFile is not readable: $context_file"
            echo '{"findings":[],"warning":"contextFile is not readable"}' > "$findings_file"
            if [[ -n "$proof_dir" ]]; then
                octo_proof_artifact "$proof_dir" "review-findings" "$findings_file" "contextFile not readable"
                octo_proof_capture_provider_status "$proof_dir" "$provider_status_file"
                octo_proof_finalize "$proof_dir" "fail" "contextFile is not readable: $context_file"
            fi
            rm -f "$provider_status_file"
            render_terminal_report "$findings_file"
            return 1
        fi
        case "$context_file_resolved" in
            "$review_root"|"$review_root"/*) ;;
            *)
                log ERROR "review_run: contextFile escapes workspace root: $context_file"
                echo '{"findings":[],"warning":"contextFile escapes workspace root"}' > "$findings_file"
                if [[ -n "$proof_dir" ]]; then
                    octo_proof_artifact "$proof_dir" "review-findings" "$findings_file" "contextFile escapes workspace root"
                    octo_proof_capture_provider_status "$proof_dir" "$provider_status_file"
                    octo_proof_finalize "$proof_dir" "fail" "contextFile escapes workspace root: $context_file"
                fi
                rm -f "$provider_status_file"
                render_terminal_report "$findings_file"
                return 1
                ;;
        esac
        context_file="$context_file_resolved"
        local context_file_bytes="0"
        context_file_bytes=$(wc -c < "$context_file" 2>/dev/null | tr -d '[:space:]' || echo 0)
        context_text=$(head -c "$review_context_chars" "$context_file" 2>/dev/null || true)
        if [[ "$context_file_bytes" =~ ^[0-9]+$ && "$context_file_bytes" -gt "$review_context_chars" ]]; then
            context_truncated="true"
        fi
    elif [[ -n "$context_text" ]]; then
        if [[ ${#context_text} -gt $review_context_chars ]]; then
            context_truncated="true"
        fi
        context_text=$(printf '%s' "$context_text" | head -c "$review_context_chars")
    fi
    if [[ "$context_truncated" == "true" ]]; then
        context_text="${context_text}
...[truncated]"
    fi

    if [[ -n "$context_text" ]]; then
        review_contract_context="Additional review context / task contract (${context_label}):
\`\`\`
${context_text}
\`\`\`

Use this context as the requested behavior and constraints. Flag severity=normal when the diff is plausible code but fails the supplied task contract, misses acceptance criteria, violates constraints, changes unrelated areas, or omits required work."
    fi

    log INFO "review_run: target=$target focus=$focus provenance=$provenance autonomy=$autonomy history=$history context=$([[ -n "$review_contract_context" ]] && echo supplied || echo none)"

    # ── REVIEW.md ────────────────────────────────────────────────────────────
    parse_review_md
    local review_context=""
    if [[ -n "$REVIEW_ALWAYS_CHECK" || -n "$REVIEW_STYLE_RULES" ]]; then
        review_context="Repository review rules (from REVIEW.md):\nAlways check:\n${REVIEW_ALWAYS_CHECK}\nStyle:\n${REVIEW_STYLE_RULES}"
    fi

    # Graphify companion context is passive: use an existing graph report when
    # present, but never build or refresh a graph from /octo:review itself.
    local graphify_context=""
    if declare -F octo_graphify_context_for_prompt >/dev/null 2>&1; then
        local graphify_root
        graphify_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
        graphify_context=$(octo_graphify_context_for_prompt "$graphify_root" 12000 2>/dev/null || true)
    fi

    # ── Collect diff ─────────────────────────────────────────────────────────
    local diff_content=""
    diff_content=$(review_collect_diff "$target")

    if [[ -z "$diff_content" ]]; then
        log WARN "review_run: no diff found for target=$target"
        echo '{"findings":[],"warning":"No changes found to review","message":"No changes found to review"}' > "$findings_file"
        if [[ -n "$proof_dir" ]]; then
            octo_proof_artifact "$proof_dir" "review-findings" "$findings_file" "no changes found"
            octo_proof_claim "$proof_dir" "No changes found to review" "verified" "$findings_file"
            octo_proof_capture_provider_status "$proof_dir" "$provider_status_file"
            octo_proof_finalize "$proof_dir" "no_changes" "No changes found to review."
            echo "Proof packet: $proof_dir"
        fi
        rm -f "$provider_status_file"
        render_terminal_report "$findings_file"
        return 1
    fi

    # Apply skip patterns from REVIEW.md (pre-filter before spending tokens)
    if [[ -n "$REVIEW_SKIP_PATTERNS" ]]; then
        while IFS= read -r pattern; do
            [[ -z "$pattern" ]] && continue
            diff_content=$(echo "$diff_content" | grep -v "$pattern" || true)
        done <<< "$REVIEW_SKIP_PATTERNS"
    fi

    # ── Round-aware PR review state (#322) ───────────────────────────────────
    # OCTOPUS_PR_HISTORY=0 disables all local history read/write.
    local review_pr_number="" review_repo="" review_host="github.com" review_head_sha=""
    local review_state_file="" review_previous_findings="[]" review_history_context="" review_timeline=""
    if declare -F pr_review_state_enabled >/dev/null 2>&1 && pr_review_state_enabled; then
        if [[ "$target" =~ ^[0-9]+$ ]]; then
            review_pr_number="$target"
            review_head_sha=$(gh pr view "$target" --json headRefOid -q .headRefOid 2>/dev/null || true)
        else
            review_pr_number=$(gh pr view --json number -q .number 2>/dev/null || true)
            review_head_sha=$(gh pr view --json headRefOid -q .headRefOid 2>/dev/null || true)
        fi
        [[ -z "$review_head_sha" ]] && review_head_sha=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

        if [[ -n "$review_pr_number" ]]; then
            local repo_json
            repo_json=$(gh repo view --json nameWithOwner,url 2>/dev/null || echo '{}')
            review_repo=$(echo "$repo_json" | jq -r '.nameWithOwner // empty')
            review_host=$(echo "$repo_json" | jq -r '(.url // "") | sub("^https?://";"") | split("/")[0] // "github.com"')
            [[ -z "$review_host" || "$review_host" == "null" ]] && review_host="github.com"

            if [[ -n "$review_repo" ]]; then
                review_state_file=$(pr_review_state_path "$review_host" "$review_repo" "$review_pr_number")
                if [[ "$history" != "fresh" ]] && pr_review_state_validate "$review_state_file"; then
                    local previous_round previous_head since_last_round_diff
                    previous_round=$(pr_review_state_previous_round "$review_state_file" 2>/dev/null || true)
                    previous_head=$(echo "$previous_round" | jq -r '.head_sha // empty' 2>/dev/null || true)
                    review_previous_findings=$(echo "$previous_round" | jq -c '.findings // []' 2>/dev/null || echo "[]")
                    if [[ -n "$previous_head" && "$previous_head" != "unknown" ]]; then
                        since_last_round_diff=$(pr_review_state_diff_since "$previous_head" "$review_head_sha" 2>/dev/null || true)
                    fi
                    review_history_context=$(pr_review_state_context_for_prompt "$review_state_file" "$since_last_round_diff" 12000)
                fi
            fi
        fi
    fi

    # ── Progress-supervised review execution ────────────────────────────────
    local diff_lines
    diff_lines=$(echo "$diff_content" | wc -l | tr -d ' ')
    local review_stall_window="${OCTOPUS_REVIEW_STALL_WINDOW:-1800}"
    local review_poll_secs="${OCTOPUS_REVIEW_POLL_SECS:-30}"
    [[ "$review_stall_window" =~ ^[0-9]+$ ]] || review_stall_window=1800
    [[ "$review_poll_secs" =~ ^[0-9]+$ ]] || review_poll_secs=30
    review_stall_window=$((10#$review_stall_window))
    review_poll_secs=$((10#$review_poll_secs))
    [[ "$review_poll_secs" -lt 1 ]] && review_poll_secs=1
    export TIMEOUT=0

    if [[ -n "$proof_dir" ]]; then
        octo_proof_event "$proof_dir" "review_scope" "$(jq -n \
            --arg target "$target" \
            --arg focus "$focus" \
            --arg provenance "$provenance" \
            --arg autonomy "$autonomy" \
            --arg publish "$publish" \
            --arg debate "$debate" \
            --arg history "$history" \
            --arg contextFile "$context_file" \
            --arg contextLabel "$context_label" \
            --argjson contextSupplied "$([[ -n "$review_contract_context" ]] && echo true || echo false)" \
            --argjson diff_lines "$diff_lines" \
            '{target:$target, focus:$focus, provenance:$provenance, autonomy:$autonomy, publish:$publish, debate:$debate, history:$history, contextFile:$contextFile, contextLabel:$contextLabel, contextSupplied:$contextSupplied, diff_lines:$diff_lines}')"
    fi

    # ── ROUND 1: Parallel agent fleet ────────────────────────────────────────
    log INFO "review_run: Round 1 — parallel specialist fleet (no wall timeout, stall_window=${review_stall_window}s, diff=${diff_lines} lines)"
    local fleet
    fleet=$(build_review_fleet)

    if [[ -n "$proof_dir" ]]; then
        octo_proof_event "$proof_dir" "provider_fleet" "$(printf '%s\n' "$fleet" | jq -R -s 'split("\n")[:-1]')"
    fi

    local agent_prompt_base
    agent_prompt_base="You are a code reviewer. Review the following diff and return ONLY a JSON object with a 'findings' array.

Each finding must have: file (string), line (integer), severity (normal|nit|pre-existing), category (string), title (string), detail (string), confidence (0.0-1.0).

Severity guide:
- normal: bug that should be fixed before merging (red)
- nit: minor issue, not blocking (yellow)
- pre-existing: bug not introduced by this PR (purple)

${review_context}
${review_contract_context}
${review_history_context}
${graphify_context}

Focus areas for this review: ${focus}
Provenance: ${provenance}
$(if [[ "$provenance" == "autonomous" || "$provenance" == "ai-assisted" ]]; then echo "ELEVATED RIGOR: Check for TDD evidence, placeholder logic, unwired components, speculative abstractions."; fi)
$(if [[ "$autonomy" == "autonomous" ]]; then echo "AUTONOMOUS MODE: Apply maximum rigor. Flag every potential issue with full detail."; fi)

Diff to review:
\`\`\`
${diff_content}
\`\`\`

CRITICAL OUTPUT FORMAT: Return ONLY a valid JSON object. No markdown, no prose, no explanations, no code blocks wrapping the JSON. Start with { and end with }. If you cannot parse the diff or find no issues, return: {\"findings\": []}"

    local round1_files=()
    local round1_agent_types=()
    local round1_roles=()
    local round1_task_ids=()
    local round1_prompts=()
    local round1_pids=()

    fleet_dispatch_begin
    while IFS=: read -r agent_type role specialty; do
        [[ -z "$agent_type" ]] && continue
        local task_id="review-r1-${role}-${timestamp}"
        # Use spawn_agent's actual output path convention: ${RESULTS_DIR}/$(octo_agent_spec_slug "$agent_type")-${task_id}.md
        local result_file
        result_file="${RESULTS_DIR}/$(octo_agent_spec_slug "$agent_type")-${task_id}.md"
        round1_files+=("$result_file")
        round1_agent_types+=("$agent_type")
        round1_roles+=("$role")
        round1_task_ids+=("$task_id")

        local agent_prompt="You are the ${role} specialist. Focus on: ${specialty}.

${agent_prompt_base}"
        round1_prompts+=("$agent_prompt")

        # A single provider failing PID capture (e.g. a huge diff pushes prompt
        # summarization past the wait budget) must not abort the whole round via
        # `set -e` — that skips every remaining fleet member and leaves
        # state.json stuck at status "running" forever (#736). Treat it the same
        # as any other Round 1 agent that produced no result file: the existing
        # missing-result accounting below already counts it toward
        # round1_partial_count / _r1_failed and drives octo_proof_finalize.
        local round1_pid=""
        if ! round1_pid=$(spawn_agent_capture_pid "$agent_type" "$agent_prompt" "$task_id" "$role" "review"); then
            log WARN "review_run: spawn_agent_capture_pid failed for ${agent_type}/${role}; continuing Round 1 with remaining fleet"
            round1_pid=""
        fi
        round1_pids+=("$round1_pid")
    done <<< "$fleet"

    fleet_dispatch_end

    # A healthy provider or unrelated RESULTS_DIR activity must not reset a
    # hung peer's timer.
    review_supervise_round1 "$review_stall_window" "$review_poll_secs" "$RESULTS_DIR"

    # Retry transient OpenAI-compatible adapter Empty output failures once after backoff. We
    # only do this for Round 1 review specialists and only when the artifact shows
    # reconnects, because provider-side 180s empty responses can be recoverable
    # after a short pause.
    local openai_compat_empty_retry_max="${OCTOPUS_REVIEW_OPENAI_COMPAT_EMPTY_RETRY_MAX:-1}"
    local openai_compat_empty_retry_backoff="${OCTOPUS_REVIEW_OPENAI_COMPAT_EMPTY_RETRY_BACKOFF_SECS:-90}"
    [[ "$openai_compat_empty_retry_max" =~ ^[0-9]+$ ]] || openai_compat_empty_retry_max=1
    [[ "$openai_compat_empty_retry_backoff" =~ ^[0-9]+$ ]] || openai_compat_empty_retry_backoff=90
    openai_compat_empty_retry_max=$((10#$openai_compat_empty_retry_max))
    openai_compat_empty_retry_backoff=$((10#$openai_compat_empty_retry_backoff))
    if [[ "$openai_compat_empty_retry_max" -gt 0 ]]; then
        local retry_idx=0
        while [[ "$retry_idx" -lt "${#round1_files[@]}" ]]; do
            local retry_file="${round1_files[$retry_idx]}"
            local retry_agent_type="${round1_agent_types[$retry_idx]}"
            if review_openai_compat_empty_output_retryable "$retry_file" "$retry_agent_type"; then
                local reconnect_count retry_role retry_task_id retry_prompt retry_result_file retry_pid archived_file
                reconnect_count=$(grep -c 'Reconnecting' "$retry_file" 2>/dev/null || true)
                reconnect_count=${reconnect_count:-0}
                reconnect_count=${reconnect_count%%$'\n'*}
                retry_role="${round1_roles[$retry_idx]}"
                retry_task_id="${round1_task_ids[$retry_idx]}-retry1"
                retry_result_file="${RESULTS_DIR}/$(octo_agent_spec_slug "$retry_agent_type")-${retry_task_id}.md"
                archived_file="${retry_file}.attempt1"
                mv "$retry_file" "$archived_file" 2>/dev/null || true
                log WARN "review_run: ${retry_agent_type}/${retry_role} ended Empty output after ${reconnect_count} reconnect(s); retrying once after ${openai_compat_empty_retry_backoff}s (artifact=$(basename "$archived_file"))"
                sleep "$openai_compat_empty_retry_backoff"
                retry_prompt="RETRY NOTICE: the previous ${retry_agent_type}/${retry_role} review attempt ended with Empty output after adapter reconnects. Review only the supplied diff/context; do not inspect the workspace unless strictly necessary. Return ONLY the required JSON object.

${round1_prompts[$retry_idx]}"
                spawn_agent "$retry_agent_type" "$retry_prompt" "$retry_task_id" "$retry_role" "review" &
                retry_pid="$!"
                review_wait_for_result_status "$retry_result_file" "$retry_pid" "Round 1 ${retry_agent_type}/${retry_role} retry" "$RESULTS_DIR" "$review_stall_window" "$review_poll_secs"
                round1_files[$retry_idx]="$retry_result_file"
                local retry_success_count
                retry_success_count=$(grep -cE '^## Status: SUCCESS' "$retry_result_file" 2>/dev/null || true)
                retry_success_count=${retry_success_count:-0}
                if [[ -f "$retry_result_file" ]] && [[ "${retry_success_count%%$'\n'*}" -gt 0 ]]; then
                    log INFO "review_run: ${retry_agent_type}/${retry_role} retry recovered after Empty output"
                else
                    log WARN "review_run: ${retry_agent_type}/${retry_role} retry did not recover; continuing with partial Round 1"
                fi
            fi
            ((retry_idx++)) || true
        done
    fi

    log INFO "review_run: Round 1 complete"

    # Collect Round 1 findings — robustly extract the last JSON object with a
    # findings array. Some providers echo the full prompt before the final JSON;
    # a strict jq of the whole ## Output block silently loses those findings.
    local all_findings="[]"
    local idx=0
    local round1_partial_count=0
    local round1_parse_miss_count=0
    for f in "${round1_files[@]}"; do
        local atype="${round1_agent_types[$idx]}"
        local provider_key
        provider_key="$(review_provider_key_from_agent_type "$atype")"
        if [[ ! -f "$f" ]]; then
            ((round1_partial_count++)) || true
            echo "${provider_key}|fallback|Round 1 agent missing result" >> "$provider_status_file"
            ((idx++)) || true
            continue
        fi
        local agent_findings
        if ! agent_findings=$(review_extract_findings_array "$f" 2>/dev/null); then
            agent_findings="[]"
        fi
        local severity_count
        local provider_output_text
        provider_output_text=$(review_extract_output_text "$f" 2>/dev/null || true)
        if review_output_has_finding_signal "$provider_output_text"; then
            severity_count=1
        else
            severity_count=0
        fi
        if [[ "$agent_findings" == "[]" ]] && [[ "$severity_count" -gt 0 ]] && review_result_completed_successfully "$f"; then
            local recovered_findings=""
            log WARN "review_run: malformed findings output in $(basename "$f"); attempting one format-only recovery with ${atype}/${round1_roles[$idx]}"
            if recovered_findings=$(review_recover_malformed_findings "$atype" "${round1_roles[$idx]}" "$provider_output_text" "Round 1 ${atype}/${round1_roles[$idx]} malformed-output recovery"); then
                agent_findings="$recovered_findings"
                log INFO "review_run: ${atype}/${round1_roles[$idx]} malformed-output recovery succeeded"
            else
                ((round1_parse_miss_count++)) || true
                log WARN "review_run: possible findings in $(basename "$f") but extractor and format-only recovery returned no usable findings"
            fi
        elif [[ "$agent_findings" == "[]" ]] && [[ "$severity_count" -gt 0 ]]; then
            ((round1_parse_miss_count++)) || true
            log WARN "review_run: possible findings in $(basename "$f") but extractor returned empty array"
        fi
        all_findings=$(printf '%s\n%s' "$all_findings" "$agent_findings" |             jq -s 'add' 2>/dev/null || echo "$all_findings")

        # v9.3.1: Write provider status for Round 1 agents (#187)
        # #498: emit one review.finding lifecycle event per Round 1 finding, while
        # per-provider attribution is still in scope (it is dropped after the merge
        # above). round="1" lets consumers filter pre-verification noise.
        if [[ "$agent_findings" != "[]" ]] && declare -f octo_event_emit >/dev/null 2>&1; then
            while IFS=$'\t' read -r _rf_sev _rf_title; do
                [[ -z "${_rf_sev}${_rf_title}" ]] && continue
                octo_event_emit "review.finding" provider="$provider_key" provider_label_kind="legacy-alias" executor_alias="$atype" configured_provider="$(octo_provider_identity_from_agent_type "${atype:-unknown}")" configured_model="$(get_agent_model "$atype" "review" "${round1_roles[$idx]}" 2>/dev/null || echo unresolved)" runtime_provider="unknown" runtime_model="unknown" role="${round1_roles[$idx]}" severity="${_rf_sev:-unknown}" message="${_rf_title:-}" round="1" || true
            done < <(printf '%s' "$agent_findings" | jq -r '.[]? | [(.severity // "unknown"), (.title // .message // "")] | @tsv' 2>/dev/null)
        fi
        if ! review_result_completed_successfully "$f"; then
            ((round1_partial_count++)) || true
            local failure_detail
            failure_detail="$(review_result_failure_detail "$f" 2>/dev/null || true)"
            failure_detail="${failure_detail:-Round 1 agent did not complete successfully}"
            echo "${provider_key}|fallback|${failure_detail}" >> "$provider_status_file"
        else
            echo "${provider_key}|ok|Round 1 completed" >> "$provider_status_file"
        fi
        ((idx++)) || true
    done

    local round1_findings_file="${results_dir}/review-round1-findings-${timestamp}.json"
    local round1_warning=""
    if [[ "$round1_partial_count" -gt 0 || "$round1_parse_miss_count" -gt 0 ]]; then
        round1_warning="Round 1 was partial: ${round1_partial_count} provider(s) missing/failed/timed out, ${round1_parse_miss_count} provider output(s) had possible unparsed findings."
    fi
    review_local_synthesis_json "$all_findings" "$round1_warning" > "$round1_findings_file"
    log INFO "review_run: Round 1 findings snapshot saved to $round1_findings_file"

    # v9.20.1: Detect total fleet failure — all providers crashed/timed out (#255)
    local _r1_total=${#round1_files[@]}
    local _r1_failed=0
    for _rf in "${round1_files[@]}"; do
        if [[ ! -f "$_rf" ]]; then
            ((_r1_failed++)) || true
            continue
        fi
        local _rf_failed_status_count _rf_status_count
        _rf_failed_status_count=$(grep -cE '^## Status: (FAILED|TIMEOUT)' "$_rf" 2>/dev/null || true)
        _rf_failed_status_count=${_rf_failed_status_count:-0}
        _rf_status_count=$(grep -c '^## Status:' "$_rf" 2>/dev/null || true)
        _rf_status_count=${_rf_status_count:-0}
        if [[ "${_rf_failed_status_count%%$'\n'*}" -gt 0 ]] || [[ "${_rf_status_count%%$'\n'*}" -eq 0 ]]; then
            ((_r1_failed++)) || true
        fi
    done
    if [[ $_r1_failed -ge $_r1_total ]] && [[ $_r1_total -gt 0 ]]; then
        log ERROR "review_run: ALL Round 1 providers failed ($_r1_failed/$_r1_total). Review output is unreliable."
        echo "{\"findings\":[],\"warning\":\"All $_r1_total review providers failed. No code was actually reviewed. Run octopus doctor to diagnose provider issues.\"}" > "$findings_file"
        if [[ -n "$proof_dir" ]]; then
            octo_proof_artifact "$proof_dir" "review-findings" "$findings_file" "all providers failed"
            octo_proof_claim "$proof_dir" "Code was reviewed by at least one provider" "contradicted" "$findings_file"
            octo_proof_capture_provider_status "$proof_dir" "$provider_status_file"
            octo_proof_finalize "$proof_dir" "fail" "All ${_r1_total} Round 1 review providers failed."
            echo "Proof packet: $proof_dir"
        fi
        render_terminal_report "$findings_file"
        print_provider_report "$provider_status_file"
        return 1
    fi

    # ── ROUND 2: Verification ─────────────────────────────────────────────────
    log INFO "review_run: Round 2 — verification"
    local verifier_prompt
    verifier_prompt="You are a code review verifier. For each finding below, check whether it is a real bug (confirmed), a false positive, or needs debate (uncertain/conflicting).

Return ONLY JSON: same findings array with an added 'verdict' field: confirmed|false-positive|needs-debate.
Also add 'pre_existing_newly_reachable': true if a pre-existing finding becomes reachable via this PR changes.

${review_contract_context}

Diff:
\`\`\`
${diff_content}
\`\`\`

Findings to verify:
$(echo "$all_findings" | jq -c '.')

Return ONLY valid JSON with 'findings' array including verdict field."

    local verified_findings verifier_provider verifier_provider_key
    verifier_provider="$(review_phase_provider "codex")" || return 1
    verifier_provider_key="$(review_provider_key_from_agent_type "$verifier_provider")"
    if [[ -n "${OCTOPUS_REVIEW_SINGLE_PROVIDER:-}" ]]; then
        verified_findings=$(review_run_agent_sync_progress "$verifier_provider" "$verifier_prompt" "implementation-verifier" "review" "verifier-${verifier_provider}") && {
            echo "${verifier_provider_key}|ok|Round 2 verification" >> "$provider_status_file"
        } || {
            log WARN "review_run: ${verifier_provider} verification failed, using all findings as confirmed"
            echo "${verifier_provider_key}|fallback|Round 2 verification failed; preserving Round 1 findings" >> "$provider_status_file"
            verified_findings=$(printf '{"findings":%s}' "$(
                echo "$all_findings" | jq 'map(. + {"verdict":"confirmed"})' 2>/dev/null || echo "[]"
            )")
        }
    else
        verified_findings=$(review_run_agent_sync_progress "codex" "$verifier_prompt" "implementation-verifier" "review" "verifier-codex") && {
            echo "codex|ok|Round 2 verification" >> "$provider_status_file"
        } || {
            log WARN "review_run: codex verifier failed, falling back to claude-sonnet"
            log "USER" "⚠ Round 2: Codex unavailable → claude-sonnet (fallback). Codex API usage will NOT change."
            echo "codex|fallback|Round 2 → claude-sonnet" >> "$provider_status_file"
            verified_findings=$(review_run_agent_sync_progress "claude-sonnet" "$verifier_prompt" "implementation-verifier" "review" "verifier-claude-sonnet") || {
                log WARN "review_run: verification failed entirely, using all findings as confirmed"
                verified_findings=$(printf '{"findings":%s}' "$(
                    echo "$all_findings" | jq 'map(. + {"verdict":"confirmed"})' 2>/dev/null || echo "[]"
                )")
            }
        }
    fi
    # v9.3.1: Strip markdown fences that LLMs wrap around JSON responses (#188)
    verified_findings=$(echo "$verified_findings" | sed '/^```json$/d; /^```JSON$/d; /^```$/d')
    local normalized_verified_findings
    if normalized_verified_findings=$(printf '%s' "$verified_findings" | review_normalize_findings_json 2>/dev/null); then
        verified_findings="$normalized_verified_findings"
    else
        log WARN "review_run: verification returned invalid or multi-document findings JSON; preserving Round 1 findings"
        verified_findings=$(printf '{"findings":%s}' "$(
            echo "$all_findings" | jq 'map(. + {"verdict":"confirmed"})' 2>/dev/null || echo "[]"
        )")
    fi

    # Filter false positives
    local confirmed_findings
    confirmed_findings=$(echo "$verified_findings" | \
        jq '.findings | map(select(.verdict != "false-positive"))' 2>/dev/null || \
        echo "$all_findings")

    # ── Debate gate (if enabled) ──────────────────────────────────────────────
    if [[ "$debate" != "off" ]]; then
        local debate_candidates
        debate_candidates=$(echo "$confirmed_findings" | \
            jq '[.[] | select(.verdict == "needs-debate")]' 2>/dev/null || echo "[]")
        local debate_count
        if ! debate_count=$(printf '{"findings":%s}' "$debate_candidates" | review_findings_count); then
            log WARN "review_run: invalid debate candidates; skipping debate gate and preserving confirmed findings"
            debate_count=0
        fi
        if [[ "$debate_count" -gt 0 ]]; then
            log INFO "review_run: debating $debate_count contested findings"
            local debate_prompt="Challenge these $debate_count contested code review findings. For each, state whether it is a real bug (include) or false positive (exclude). Be adversarial.
Findings: $(echo "$debate_candidates" | jq -c '.')
Return JSON: {\"include\": [...finding titles...], \"exclude\": [...finding titles...]}"
            local debate_result debate_provider debate_provider_key
            debate_provider="$(review_phase_provider "codex")" || return 1
            debate_provider_key="$(review_provider_key_from_agent_type "$debate_provider")"
            debate_result=$(review_run_agent_sync_progress "$debate_provider" "$debate_prompt" "implementation-debater" "review" "debate-${debate_provider}") && {
                echo "${debate_provider_key}|ok|Round 3 debate" >> "$provider_status_file"
            } || {
                log WARN "review_run: ${debate_provider} debate agent failed, including all contested findings"
                log "USER" "⚠ Round 3: ${debate_provider} debate gate unavailable — including all contested findings without debate."
                echo "${debate_provider_key}|fallback|Round 3 debate → skipped" >> "$provider_status_file"
                debate_result="{\"include\":[],\"exclude\":[]}"
            }
            # v9.3.1: Strip markdown fences from debate result (#188)
            debate_result=$(echo "$debate_result" | sed '/^```json$/d; /^```JSON$/d; /^```$/d')
            local exclude_titles
            exclude_titles=$(echo "$debate_result" | jq -r '.exclude // [] | .[]' 2>/dev/null || true)
            if [[ -n "$exclude_titles" ]]; then
                while IFS= read -r title; do
                    confirmed_findings=$(echo "$confirmed_findings" | \
                        jq --arg t "$title" '[.[] | select(.title != $t)]' 2>/dev/null || \
                        echo "$confirmed_findings")
                done <<< "$exclude_titles"
            fi
        fi
    fi

    # ── ROUND 3: Synthesis ────────────────────────────────────────────────────
    log INFO "review_run: Round 3 — synthesis"
    local synthesis_prompt
    synthesis_prompt="Deduplicate and rank these code review findings by severity (normal first, then nit, then pre-existing). Merge duplicate findings (same bug from multiple agents) into one entry, preserving all agent perspectives in the detail field.

Findings: $(echo "$confirmed_findings" | jq -c '.')

Return ONLY JSON: {\"findings\": [...ranked, deduplicated findings...]}"

    local final_json synth_ok="true" synthesis_provider synthesis_provider_key
    synthesis_provider="$(review_phase_provider "claude-sonnet")" || return 1
    synthesis_provider_key="$(review_provider_key_from_agent_type "$synthesis_provider")"
    final_json=$(review_run_agent_sync_progress "$synthesis_provider" "$synthesis_prompt" "implementation-synthesizer" "review" "synthesis-${synthesis_provider}") || {
        synth_ok="false"
        log WARN "review_run: ${synthesis_provider} synthesis failed, using confirmed findings sorted as-is"
        echo "${synthesis_provider_key}|fallback|Round 3 synthesis failed; using local deterministic fallback" >> "$provider_status_file"
        final_json="$(review_local_synthesis_json "$confirmed_findings" "$round1_warning")"
    }

    # v9.3.1: Strip markdown fences from synthesis result (#188)
    final_json=$(echo "$final_json" | sed '/^```json$/d; /^```JSON$/d; /^```$/d')
    local normalized_final_json
    if ! normalized_final_json=$(printf '%s' "$final_json" | review_normalize_findings_json 2>/dev/null); then
        log WARN "review_run: synthesis returned invalid or multi-document findings JSON, using local fallback"
        final_json=$(review_local_synthesis_json "$confirmed_findings" "$round1_warning")
        synth_ok="false"
    else
        final_json="$normalized_final_json"
    fi
    if [[ -n "$round1_warning" ]]; then
        local warned_final_json
        if warned_final_json=$(printf '%s' "$final_json" | \
            jq -c --arg warning "$round1_warning" '. + {warning:$warning}' 2>/dev/null); then
            final_json="$warned_final_json"
        else
            final_json=$(review_local_synthesis_json "$confirmed_findings" "$round1_warning")
            synth_ok="false"
        fi
    fi

    # Write findings file
    printf '%s\n' "$final_json" > "$findings_file"
    log INFO "review_run: findings saved to $findings_file"

    # #498: emit a synthesis lifecycle event when Round 3 synthesis succeeds.
    # Only on the success branch — the fallback above reassigns the provider, so
    # attribution would be wrong there (per design-review verification).
    if [[ "$synth_ok" == "true" ]] && declare -f octo_event_emit >/dev/null 2>&1; then
        local _synth_count
        if ! _synth_count=$(review_findings_count "$final_json"); then
            _synth_count=0
        fi
        octo_event_emit "synthesis" phase="review" provider="$synthesis_provider" provider_label_kind="legacy-alias" executor_alias="$synthesis_provider" configured_provider="$(octo_provider_identity_from_agent_type "$synthesis_provider")" configured_model="$(get_agent_model "$synthesis_provider" "review" "implementation-synthesizer" 2>/dev/null || echo unresolved)" runtime_provider="unknown" runtime_model="unknown" council_role="implementation-synthesizer" synthesis_strategy="review" count="${_synth_count:-0}" || true
    fi

    if [[ -n "$proof_dir" ]]; then
        octo_proof_artifact "$proof_dir" "review-findings" "$findings_file" "final review findings"
    fi

    if [[ -n "$review_state_file" ]] && declare -F pr_review_state_append_round >/dev/null 2>&1; then
        local final_findings classification providers_json
        final_findings=$(echo "$final_json" | jq -c '.findings // []' 2>/dev/null || echo "[]")
        classification=$(pr_review_state_classify_findings "$review_previous_findings" "$final_findings" 2>/dev/null || echo '{"addressed":0,"persistent":0,"new":0,"regressed":0}')
        providers_json=$(printf '%s\n' "${round1_agent_types[@]}" | jq -R -s 'split("\n")[:-1]' 2>/dev/null || echo "[]")
        local current_round
        current_round=$(pr_review_state_next_round "$review_state_file")
        review_timeline=$(pr_review_state_render_timeline "$review_state_file" "$review_head_sha" "$classification" "$current_round" 2>/dev/null || true)
        if pr_review_state_append_round "$review_state_file" "$review_host" "$review_repo" "$review_pr_number" "$review_head_sha" "$providers_json" "$final_findings" "$classification" 2>/dev/null; then
            log INFO "review_run: round-aware state saved to $review_state_file"
            if [[ -n "$proof_dir" ]]; then
                octo_proof_artifact "$proof_dir" "review-history-state" "$review_state_file" "round-aware PR review state"
            fi
        fi
    fi

    # ── Output ────────────────────────────────────────────────────────────────
    local pr_number="${review_pr_number:-}"
    if [[ -z "$pr_number" ]]; then
        pr_number=$(gh pr view --json number -q .number 2>/dev/null || true)
    fi

    if [[ -n "$pr_number" && "$publish" != "never" ]]; then
        local avg_confidence
        avg_confidence=$(jq '[.findings[].confidence] | if length > 0 then add/length else 0 end' \
            "$findings_file" 2>/dev/null | head -n 1)
        [[ -z "$avg_confidence" ]] && avg_confidence="0"
        if [[ "$publish" == "auto" ]] && awk "BEGIN{exit !($avg_confidence >= 0.85)}"; then
            log INFO "review_run: auto-publishing to PR #$pr_number (confidence=$avg_confidence)"
            post_inline_comments "$pr_number" "$findings_file" || render_terminal_report "$findings_file"
        elif [[ "$publish" == "auto" ]]; then
            log INFO "review_run: avg_confidence=$avg_confidence below 0.85 auto-publish gate; rendering terminal report instead."
            render_terminal_report "$findings_file"
        elif [[ "$publish" == "ask" ]]; then
            render_terminal_report "$findings_file"
            echo ""
            echo "PR #$pr_number is open. Post findings as inline comments? (y/N)"
            read -r response
            if [[ "$response" =~ ^[Yy] ]]; then
                post_inline_comments "$pr_number" "$findings_file" || \
                    log WARN "review_run: PR posting was incomplete; terminal report was already shown"
            fi
        fi
    else
        render_terminal_report "$findings_file"
    fi

    if [[ -n "$review_timeline" ]]; then
        echo ""
        echo "$review_timeline"
    fi

    if [[ -n "$proof_dir" ]]; then
        local proof_finding_count proof_warning proof_verdict proof_summary
        if ! proof_finding_count=$(review_findings_count "$(<"$findings_file")"); then
            proof_finding_count=0
        fi
        proof_warning=$(jq -r '.warning // empty' "$findings_file" 2>/dev/null || true)
        if [[ -n "$proof_warning" ]]; then
            proof_verdict="fail"
        elif [[ "$proof_finding_count" -gt 0 ]]; then
            proof_verdict="findings"
        else
            proof_verdict="pass"
        fi
        proof_summary="/octo:review completed with ${proof_finding_count} finding(s)."
        octo_proof_claim "$proof_dir" "Review findings were written to disk" "verified" "$findings_file"
        octo_proof_capture_provider_status "$proof_dir" "$provider_status_file"
        octo_proof_finalize "$proof_dir" "$proof_verdict" "$proof_summary"
        echo ""
        echo "Proof packet: $proof_dir"
    fi

    # v9.0: Print provider report card — always last, impossible to miss
    print_provider_report "$provider_status_file"
}

# review_post_safe_body: stream generated text to the shared helper, which
# snapshots it privately and applies the credential gate before any GitHub write.
review_post_safe_body() {
    local repo="$1"
    local body="$2"
    local operation="$3"
    shift 3

    local plugin_root="${CLAUDE_PLUGIN_ROOT:-${PLUGIN_DIR:-}}"
    if [[ -z "$plugin_root" || ! -d "$plugin_root/scripts" ]]; then
        plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    fi

    local safe_post="$plugin_root/scripts/safe-gh-comment.sh"
    if [[ ! -x "$safe_post" ]]; then
        log ERROR "review_post_safe_body: safe GitHub posting helper is unavailable"
        return 1
    fi

    local post_rc=0
    "$safe_post" --repo "$repo" "$operation" "$@" - <<< "$body" || post_rc=$?
    return "$post_rc"
}

# post_inline_comments: posts findings as inline PR comments via the validated
# JSON path. Inline line-level comments match CC Code Review UX exactly.
post_inline_comments() {
    local pr_number="$1"
    local findings_file="$2"
    local findings_json
    if ! findings_json=$(review_normalize_findings_json < "$findings_file" 2>/dev/null); then
        log ERROR "post_inline_comments: invalid findings artifact: $findings_file"
        return 1
    fi

    local repo=""
    repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
    if [[ -z "$repo" ]]; then
        log ERROR "post_inline_comments: could not determine repo (is gh auth configured?)"
        return 1
    fi

    local commit_id=""
    commit_id=$(gh pr view "$pr_number" --json headRefOid -q .headRefOid 2>/dev/null || true)

    if [[ -z "$commit_id" ]]; then
        log WARN "post_inline_comments: could not determine commit SHA for PR #$pr_number — posting summary comment only"
        local summary
        summary=$(render_review_summary "$findings_file")
        local summary_rc=0
        review_post_safe_body "$repo" "$summary" pr-review "$pr_number" || summary_rc=$?
        if [[ "$summary_rc" -eq 65 ]]; then
            log ERROR "post_inline_comments: summary body blocked by the credential-safety gate"
        elif [[ "$summary_rc" -ne 0 ]]; then
            log WARN "post_inline_comments: failed to post summary comment"
        fi
        if [[ "$summary_rc" -eq 0 ]]; then
            return 0
        fi
        return 1
    fi

    local summary
    summary=$(render_review_summary "$findings_file")
    local post_failed=0
    local summary_rc=0
    review_post_safe_body "$repo" "$summary" pr-review "$pr_number" || summary_rc=$?
    if [[ "$summary_rc" -eq 65 ]]; then
        log ERROR "post_inline_comments: summary body blocked by the credential-safety gate"
        post_failed=1
    elif [[ "$summary_rc" -ne 0 ]]; then
        log WARN "post_inline_comments: failed to post summary comment; continuing with inline findings"
        post_failed=1
    fi

    local finding_count
    if ! finding_count=$(review_findings_count "$findings_json"); then
        log ERROR "post_inline_comments: invalid findings count: $findings_file"
        return 1
    fi
    log INFO "post_inline_comments: posting $finding_count inline comments to PR #$pr_number"

    while IFS= read -r finding; do
        local file line severity title detail
        file=$(echo "$finding"     | jq -r '.file')
        line=$(echo "$finding"     | jq -r '.line')
        severity=$(echo "$finding" | jq -r '.severity')
        title=$(echo "$finding"    | jq -r '.title')
        detail=$(echo "$finding"   | jq -r '.detail')

        local icon
        case "$severity" in
            normal)       icon="[NORMAL]" ;;
            nit)          icon="[NIT]" ;;
            pre-existing) icon="[PRE-EXISTING]" ;;
            *)            icon="[INFO]" ;;
        esac

        local body="${icon} **${title}**

${detail}

_Reviewed by /octo:review (multi-LLM fleet)_"

        local post_rc=0
        review_post_safe_body "$repo" "$body" review-line \
            "$pr_number" "$commit_id" "$file" "$line" || post_rc=$?
        if [[ "$post_rc" -eq 65 ]]; then
            log ERROR "post_inline_comments: outbound body blocked by the credential-safety gate on $file:$line; continuing"
            post_failed=1
        elif [[ "$post_rc" -ge 64 && "$post_rc" -le 70 ]]; then
            log ERROR "post_inline_comments: invalid or unavailable outbound posting path on $file:$line; continuing"
            post_failed=1
        elif [[ "$post_rc" -ne 0 ]]; then
            log WARN "post_inline_comments: failed to post comment on $file:$line; continuing"
            post_failed=1
        fi
    done < <(printf '%s' "$findings_json" | jq -c '.findings[]' 2>/dev/null)

    if [[ "$post_failed" -eq 0 ]]; then
        return 0
    fi
    return 1
}

# render_terminal_report: formats findings for terminal display
# Emit one review.finding event per structured finding (oco-aek).
#
# Guarded by a per-file sentinel: render_terminal_report is also the fallback
# path when inline PR comments cannot be posted, so it can run twice for one
# review and would otherwise double-count every finding in the event stream.
# Detail text is deliberately NOT emitted — it can be long and can quote source.
review_emit_finding_events() {
    local findings_file="$1"
    declare -f octo_event_emit >/dev/null 2>&1 || return 0
    [[ -f "$findings_file" ]] || return 0
    local findings_json
    findings_json=$(review_normalize_findings_json < "$findings_file" 2>/dev/null) || return 1

    local sentinel="${findings_file}.events-emitted"
    [[ -e "$sentinel" ]] && return 0
    : > "$sentinel" 2>/dev/null || true

    printf '%s' "$findings_json" | jq -c '.findings[]?' 2>/dev/null | while IFS= read -r _rf; do
        octo_event_emit "review.finding" \
            severity="$(printf '%s' "$_rf" | jq -r '.severity // "unknown"')" \
            file="$(printf '%s' "$_rf" | jq -r '.file // "unknown"')" \
            line="$(printf '%s' "$_rf" | jq -r '(.line // 0) | tostring')" \
            category="$(printf '%s' "$_rf" | jq -r '.category // "unspecified"')" \
            confidence="$(printf '%s' "$_rf" | jq -r '(.confidence // "") | tostring')" \
            title="$(printf '%s' "$_rf" | jq -r '.title // ""')" || true
    done
}

render_terminal_report() {
    local findings_file="$1"
    local findings_json="" finding_count="0"
    local findings_valid=true
    if ! findings_json=$(review_normalize_findings_json < "$findings_file" 2>/dev/null); then
        findings_valid=false
    elif ! finding_count=$(review_findings_count "$findings_json"); then
        findings_valid=false
        finding_count=0
    fi

    echo ""
    echo "+-----------------------------------------------------------------+"
    echo "|  /octo:review - Multi-LLM Code Review Results                  |"
    echo "+-----------------------------------------------------------------+"
    echo ""

    if [[ "$findings_valid" != "true" ]]; then
        echo "WARNING: invalid findings artifact; expected exactly one JSON document."
        echo "Review output was not rendered."
        return 1
    fi

    review_emit_finding_events "$findings_file" || true

    if [[ "$finding_count" -eq 0 ]]; then
        # v9.20.1: Distinguish "clean review" from "all providers failed" (#255)
        local warning_msg
        warning_msg=$(printf '%s' "$findings_json" | jq -r '.warning // empty' 2>/dev/null)
        if [[ -n "$warning_msg" ]]; then
            echo "⚠️  WARNING: $warning_msg"
            echo ""
            echo "This is NOT a clean review — zero providers returned results."
            echo "Do not merge based on this output."
        else
            echo "No issues found."
        fi
        return 0
    fi

    echo "Found $finding_count issue(s):"
    echo ""

    printf '%s' "$findings_json" | jq -c '.findings[]' 2>/dev/null | while IFS= read -r finding; do
        local severity title file line detail
        severity=$(echo "$finding" | jq -r '.severity')
        title=$(echo "$finding"    | jq -r '.title')
        file=$(echo "$finding"     | jq -r '.file')
        line=$(echo "$finding"     | jq -r '.line')
        detail=$(echo "$finding"   | jq -r '.detail')

        local icon
        case "$severity" in
            normal)       icon="[NORMAL]" ;;
            nit)          icon="[NIT]" ;;
            pre-existing) icon="[PRE-EXISTING]" ;;
            *)            icon="[INFO]" ;;
        esac

        echo "${icon} ${title}"
        echo "   ${file}:${line}"
        echo "   ${detail}"
        echo ""
    done
}

# render_review_summary: short markdown summary for PR-level comment
render_review_summary() {
    local findings_file="$1"
    local findings_json
    if ! findings_json=$(review_normalize_findings_json < "$findings_file" 2>/dev/null); then
        echo "## /octo:review - Invalid findings artifact"
        echo ""
        echo "Review output was not published because it was not exactly one valid JSON document."
        return 1
    fi
    local normal_count nit_count preexisting_count
    normal_count=$(printf '%s' "$findings_json" | jq '[.findings[] | select(.severity=="normal")] | length')
    nit_count=$(printf '%s' "$findings_json" | jq '[.findings[] | select(.severity=="nit")] | length')
    preexisting_count=$(printf '%s' "$findings_json" | jq '[.findings[] | select(.severity=="pre-existing")] | length')

    echo "## /octo:review - Multi-LLM Code Review"
    echo ""
    echo "| Severity | Count |"
    echo "|----------|-------|"
    echo "| Normal | $normal_count |"
    echo "| Nit | $nit_count |"
    echo "| Pre-existing | $preexisting_count |"
    echo ""
    echo "_Reviewed by Codex + Antigravity + Claude + Perplexity fleet_"
    echo "_See inline comments for details_"
}
