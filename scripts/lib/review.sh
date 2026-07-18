#!/usr/bin/env bash
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
                    fleet+="${provider}:logic-reviewer:correctness and logic bugs, edge cases, regressions"$'\n'
                    has_logic=true
                fi
                ;;
            opencode|opencode-*)
                if [[ "$has_logic" == "false" ]]; then
                    fleet+="${provider}:logic-reviewer:correctness and logic bugs, edge cases, regressions"$'\n'
                    has_logic=true
                fi
                ;;
            gemini|gemini-*)
                if [[ "$has_security" == "false" ]]; then
                    fleet+="${provider}:security-reviewer:OWASP vulnerabilities, injection, auth flaws, data exposure"$'\n'
                    has_security=true
                fi
                ;;
            claude|claude-sonnet|claude-opus)
                if [[ "$has_arch" == "false" ]]; then
                    local agent="${provider}"
                    [[ "$provider" == "claude" ]] && agent="claude-sonnet"
                    fleet+="${agent}:arch-reviewer:architecture, integration, API contracts, breaking changes"$'\n'
                    has_arch=true
                fi
                ;;
            perplexity|perplexity-*)
                if [[ "$has_cve" == "false" ]]; then
                    fleet+="${provider}:cve-reviewer:known CVEs, library advisories, live web search"$'\n'
                    has_cve=true
                fi
                ;;
            openrouter|openrouter-*)
                if [[ "$has_diversity" == "false" ]]; then
                    fleet+="${provider}:diversity-reviewer:cross-family perspective on logic, missed assumptions, training-data divergence from primary providers"$'\n'
                    has_diversity=true
                fi
                ;;
            openai-compatible|openai-tools|openai-compatible-agent)
                if [[ "$has_logic" == "false" ]]; then
                    fleet+="${provider}:logic-reviewer:correctness and logic bugs, edge cases, regressions"$'\n'
                    has_logic=true
                elif [[ "$has_diversity" == "false" ]]; then
                    fleet+="${provider}:diversity-reviewer:OpenAI-compatible independent review path"$'\n'
                    has_diversity=true
                fi
                ;;
            qwen|qwen-*)
                if [[ "$has_security" == "false" ]]; then
                    fleet+="${provider}:security-reviewer:OWASP vulnerabilities, injection, auth flaws, data exposure"$'\n'
                    has_security=true
                elif [[ "$has_diversity" == "false" ]]; then
                    fleet+="${provider}:diversity-reviewer:cross-family perspective on logic and assumptions"$'\n'
                    has_diversity=true
                fi
                ;;
            copilot|copilot-*)
                if [[ "$has_cve" == "false" ]]; then
                    fleet+="${provider}:cve-reviewer:known CVEs via web search, library advisories"$'\n'
                    has_cve=true
                elif [[ "$has_diversity" == "false" ]]; then
                    fleet+="${provider}:diversity-reviewer:cross-perspective review"$'\n'
                    has_diversity=true
                fi
                ;;
        esac
    done <<< "$participants"

    [[ -z "$fleet" ]] && return 0

    # Anchor: always include arch-reviewer (claude-sonnet) if config didn't supply one.
    # Architecture context bridges per-finding noise from the specialist agents.
    if [[ "$has_arch" == "false" ]]; then
        fleet+="claude-sonnet:arch-reviewer:architecture, integration, API contracts, breaking changes"$'\n'
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
build_review_fleet() {
    local fleet=""

    # v9.31.0: honor wizard-configured participants if present
    fleet=$(_review_fleet_from_config)
    if [[ -n "$fleet" ]]; then
        echo "$fleet"
        return 0
    fi

    # ── Cascade fallback (original behavior — no config or empty config) ──

    # logic-reviewer: Codex (OpenAI) → OpenCode → Copilot → claude-sonnet fallback
    if command -v codex >/dev/null 2>&1; then
        fleet+="codex:logic-reviewer:correctness and logic bugs, edge cases, regressions"$'\n'
    elif command -v opencode >/dev/null 2>&1; then
        fleet+="opencode:logic-reviewer:correctness and logic bugs, edge cases, regressions"$'\n'
    elif command -v copilot >/dev/null 2>&1; then
        fleet+="copilot:logic-reviewer:correctness and logic bugs, edge cases, regressions"$'\n'
    else
        fleet+="claude-sonnet:logic-reviewer:correctness and logic bugs, edge cases, regressions"$'\n'
    fi

    # security-reviewer: Gemini (Google) → Qwen → Copilot → claude-sonnet fallback
    # Prefer different family from logic-reviewer for diversity
    if command -v gemini >/dev/null 2>&1; then
        fleet+="gemini:security-reviewer:OWASP vulnerabilities, injection, auth flaws, data exposure"$'\n'
    elif command -v qwen >/dev/null 2>&1; then
        fleet+="qwen:security-reviewer:OWASP vulnerabilities, injection, auth flaws, data exposure"$'\n'
    elif command -v copilot >/dev/null 2>&1; then
        fleet+="copilot:security-reviewer:OWASP vulnerabilities, injection, auth flaws, data exposure"$'\n'
    else
        fleet+="claude-sonnet:security-reviewer:OWASP vulnerabilities, injection, auth flaws, data exposure"$'\n'
    fi

    # arch-reviewer: claude-sonnet (always available — best at holistic analysis)
    fleet+="claude-sonnet:arch-reviewer:architecture, integration, API contracts, breaking changes"$'\n'

    # cve-reviewer: Perplexity → Gemini search → Copilot → Qwen → claude WebSearch
    if command -v perplexity >/dev/null 2>&1 || [[ -n "${PERPLEXITY_API_KEY:-}" ]]; then
        fleet+="perplexity:cve-reviewer:known CVEs, library advisories, live web search"$'\n'
    elif command -v gemini >/dev/null 2>&1; then
        fleet+="gemini:cve-reviewer:known CVEs via web search, library advisories"$'\n'
        log INFO "CVE lookup: Perplexity unavailable, using Gemini search"
    elif command -v copilot >/dev/null 2>&1; then
        fleet+="copilot:cve-reviewer:known CVEs via web search, library advisories"$'\n'
        log INFO "CVE lookup: Perplexity+Gemini unavailable, using Copilot"
    elif command -v qwen >/dev/null 2>&1; then
        fleet+="qwen:cve-reviewer:known CVEs via web search, library advisories"$'\n'
        log INFO "CVE lookup: Perplexity+Gemini unavailable, using Qwen"
    else
        fleet+="claude-sonnet:cve-reviewer:known CVEs via WebSearch tool, library advisories"$'\n'
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

# Snapshot descendants depth-first before signaling. Re-walking after TERM is
# unsafe because a TERM-ignoring child can be reparented when its wrapper exits,
# making it invisible to the later KILL pass.
review_process_tree_depth_first() {
    local pid="$1" child
    [[ "$pid" =~ ^[0-9]+$ ]] || return 0
    while IFS= read -r child; do
        [[ "$child" =~ ^[0-9]+$ ]] || continue
        review_process_tree_depth_first "$child"
    done < <(pgrep -P "$pid" 2>/dev/null || true)
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

# review_extract_findings_array: returns a JSON array of findings from a Round 1
# markdown result file. Providers sometimes echo the full prompt or wrap JSON in
# prose; prefer the exact ## Output jq path, then fall back to scanning the file
# for the last JSON object with a findings array.
review_extract_findings_array() {
    local review_md="$1"
    local output_text direct_json
    [[ -f "$review_md" ]] || { echo "[]"; return 1; }

    output_text=$(awk '/^## Output$/{found=1;next} /^## /{if(found)exit} found && !/^```(json|JSON)?$/{print}' "$review_md" 2>/dev/null || true)
    if [[ -n "$output_text" ]]; then
        direct_json=$(printf '%s' "$output_text" | jq -cs '[.[] | objects | .findings | select(type == "array" and length > 0)] | last // []' 2>/dev/null || true)
        if [[ -n "$direct_json" && "$direct_json" != "null" ]]; then
            printf '%s\n' "$direct_json"
            return 0
        fi
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$review_md" <<'PYEXTRACT'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text(errors='ignore')
decoder = json.JSONDecoder()
best = None
idx = 0
while True:
    idx = text.find('{', idx)
    if idx < 0:
        break
    try:
        obj, end = decoder.raw_decode(text[idx:])
    except Exception:
        idx += 1
        continue
    if isinstance(obj, dict) and isinstance(obj.get('findings'), list):
        # Prefer the last NON-EMPTY findings array. The Round 1 prompt embeds
        # {"findings": []} as a format example; a provider that echoes the
        # prompt after its real answer must not have its findings replaced by
        # the echoed empty example.
        if obj.get('findings'):
            best = obj.get('findings')
        elif best is None:
            best = obj.get('findings')
    idx += max(1, end)
if best is None:
    print('[]')
    sys.exit(1)
print(json.dumps(best, separators=(',', ':')))
PYEXTRACT
        return $?
    fi

    echo "[]"
    return 1
}

review_local_synthesis_json() {
    local findings_json="$1"
    local warning="${2:-}"
    local sort_filter='def severity_rank: if .severity == "normal" then 0 elif .severity == "nit" then 1 elif .severity == "pre-existing" then 2 else 3 end; sort_by(severity_rank)'
    if [[ -n "$warning" ]]; then
        printf '%s' "$findings_json" | jq -c --arg warning "$warning" "{findings:(. // [] | ${sort_filter}), warning:\$warning}" 2>/dev/null \
            || printf '{"findings":[],"warning":%s}\n' "$(printf '%s' "$warning" | jq -R .)"
    else
        printf '%s' "$findings_json" | jq -c \
            "{findings:(. // [] | ${sort_filter})}" 2>/dev/null \
            || echo '{"findings":[]}'
    fi
}

# review_collect_diff: resolves a review target to unified diff content.
# Targets can be built-in scopes (staged, working-tree), a PR number, a git
# pathspec, or an already-generated .diff/.patch file.
review_collect_diff() {
    local target="$1"
    local diff_content=""

    case "$target" in
        staged)       diff_content=$(git diff --cached 2>/dev/null || true) ;;
        working-tree) diff_content=$(git diff 2>/dev/null || true) ;;
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
    local codex_status="not used" gemini_status="not used" claude_status="✓ OK" perplexity_status="not used"
    local codex_detail="" gemini_detail="" perplexity_detail=""
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
            gemini)
                if [[ "$status" == "ok" ]]; then
                    gemini_status="✓ OK"
                elif [[ "$status" == "fallback" ]]; then
                    gemini_status="✗ FALLBACK"
                    gemini_detail="$detail"
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
        esac
    done < "$status_file"

    # Always print the report card
    echo ""
    echo "┌─────────────────────────────────────────────┐"
    echo "│ 🐙 Provider Status                          │"
    echo "│                                             │"
    printf "│ 🔴 Codex:      %-28s│\n" "$codex_status"
    [[ -n "$codex_detail" ]] && printf "│    → %-38s│\n" "$codex_detail"
    printf "│ 🟡 Gemini:     %-28s│\n" "$gemini_status"
    [[ -n "$gemini_detail" ]] && printf "│    → %-38s│\n" "$gemini_detail"
    printf "│ 🔵 Claude:     %-28s│\n" "$claude_status"
    printf "│ 🟣 Perplexity: %-28s│\n" "$perplexity_status"
    [[ -n "$perplexity_detail" ]] && printf "│    → %-38s│\n" "$perplexity_detail"
    if [[ "$had_fallback" == "true" ]]; then
        echo "│                                             │"
        echo "│ ⚠ Some providers failed — run /octo:doctor  │"
    fi
    echo "└─────────────────────────────────────────────┘"

    # Persist failures for /octo:doctor
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

    # v9.0: Preflight — check Codex auth before review pipeline
    if command -v codex >/dev/null 2>&1; then
        if ! check_codex_auth_freshness 2>/dev/null; then
            log "WARN" "review_run: Codex auth may be stale — review fleet may fall back to claude-sonnet"
            log "USER" "⚠ Codex auth check failed. Run 'codex auth' or /octo:doctor to fix. Falling back to claude-sonnet for Codex roles."
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
        # Use spawn_agent's actual output path convention: ${RESULTS_DIR}/${agent_type}-${task_id}.md
        local result_file="${RESULTS_DIR}/${agent_type}-${task_id}.md"
        round1_files+=("$result_file")
        round1_agent_types+=("$agent_type")
        round1_roles+=("$role")
        round1_task_ids+=("$task_id")

        local agent_prompt="You are the ${role} specialist. Focus on: ${specialty}.

${agent_prompt_base}"
        round1_prompts+=("$agent_prompt")

        local round1_pid
        round1_pid=$(spawn_agent_capture_pid "$agent_type" "$agent_prompt" "$task_id" "$role" "review")
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
                retry_result_file="${RESULTS_DIR}/${retry_agent_type}-${retry_task_id}.md"
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
        local provider_key="${atype%%[-_]*}"
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
        severity_count=$(grep -c '"severity"[[:space:]]*:[[:space:]]*"' "$f" 2>/dev/null || true)
        severity_count=${severity_count:-0}
        if [[ "$agent_findings" == "[]" ]] && [[ "${severity_count%%$'\n'*}" -gt 0 ]]; then
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
                octo_event_emit "review.finding" provider="$provider_key" provider_label_kind="legacy-alias" executor_alias="$atype" configured_provider="$(octo_provider_identity_from_agent_type "${atype:-unknown}")" configured_model="$(get_agent_model "$atype" "review" "reviewer" 2>/dev/null || echo unresolved)" runtime_provider="unknown" runtime_model="unknown" role="reviewer" severity="${_rf_sev:-unknown}" message="${_rf_title:-}" round="1" || true
            done < <(printf '%s' "$agent_findings" | jq -r '.[]? | [(.severity // "unknown"), (.title // .message // "")] | @tsv' 2>/dev/null)
        fi
        if ! review_result_completed_successfully "$f"; then
            ((round1_partial_count++)) || true
            echo "${provider_key}|fallback|Round 1 agent did not complete successfully" >> "$provider_status_file"
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
        echo "{\"findings\":[],\"warning\":\"All $_r1_total review providers failed. No code was actually reviewed. Run /octo:doctor to diagnose provider issues.\"}" > "$findings_file"
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

    local verified_findings
    verified_findings=$(review_run_agent_sync_progress "codex" "$verifier_prompt" "code-reviewer" "review" "verifier-codex") && {
        echo "codex|ok|Round 2 verification" >> "$provider_status_file"
    } || {
        log WARN "review_run: codex verifier failed, falling back to claude-sonnet"
        log "USER" "⚠ Round 2: Codex unavailable → claude-sonnet (fallback). Codex API usage will NOT change."
        echo "codex|fallback|Round 2 → claude-sonnet" >> "$provider_status_file"
        verified_findings=$(review_run_agent_sync_progress "claude-sonnet" "$verifier_prompt" "code-reviewer" "review" "verifier-claude-sonnet") || {
            log WARN "review_run: verification failed entirely, using all findings as confirmed"
            verified_findings="{\"findings\":$(echo "$all_findings" | \
                jq 'map(. + {"verdict":"confirmed"})' 2>/dev/null || echo "[]")}"
        }
    }
    # v9.3.1: Strip markdown fences that LLMs wrap around JSON responses (#188)
    verified_findings=$(echo "$verified_findings" | sed '/^```json$/d; /^```JSON$/d; /^```$/d')

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
        debate_count=$(echo "$debate_candidates" | jq 'length' 2>/dev/null || echo "0")
        if [[ "$debate_count" -gt 0 ]]; then
            log INFO "review_run: debating $debate_count contested findings"
            local debate_prompt="Challenge these $debate_count contested code review findings. For each, state whether it is a real bug (include) or false positive (exclude). Be adversarial.
Findings: $(echo "$debate_candidates" | jq -c '.')
Return JSON: {\"include\": [...finding titles...], \"exclude\": [...finding titles...]}"
            local debate_result
            debate_result=$(review_run_agent_sync_progress "codex" "$debate_prompt" "code-reviewer" "review" "debate-codex") && {
                echo "codex|ok|Round 3 debate" >> "$provider_status_file"
            } || {
                log WARN "review_run: debate agent failed, including all contested findings"
                log "USER" "⚠ Round 3: Codex debate gate unavailable — including all contested findings without debate."
                echo "codex|fallback|Round 3 debate → skipped" >> "$provider_status_file"
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

    local final_json synth_ok="true"
    final_json=$(review_run_agent_sync_progress "claude-sonnet" "$synthesis_prompt" "code-reviewer" "review" "synthesis-claude-sonnet") || {
        synth_ok="false"
        log WARN "review_run: synthesis failed, using confirmed findings sorted as-is"
        final_json="$(review_local_synthesis_json "$confirmed_findings" "$round1_warning")"
    }

    # v9.3.1: Strip markdown fences from synthesis result (#188)
    final_json=$(echo "$final_json" | sed '/^```json$/d; /^```JSON$/d; /^```$/d')
    if ! printf '%s' "$final_json" | jq -e '.findings | type == "array"' >/dev/null 2>&1; then
        log WARN "review_run: synthesis returned invalid findings JSON, using local fallback"
        final_json=$(review_local_synthesis_json "$confirmed_findings" "$round1_warning")
        synth_ok="false"
    elif [[ -n "$round1_warning" ]]; then
        final_json=$(printf '%s' "$final_json" | jq -c --arg warning "$round1_warning" '. + {warning:$warning}' 2>/dev/null \
            || review_local_synthesis_json "$confirmed_findings" "$round1_warning")
    fi

    # Write findings file
    echo "$final_json" > "$findings_file"
    log INFO "review_run: findings saved to $findings_file"

    # #498: emit a synthesis lifecycle event when Round 3 synthesis succeeds.
    # Only on the success branch — the fallback above reassigns the provider, so
    # attribution would be wrong there (per design-review verification).
    if [[ "$synth_ok" == "true" ]] && declare -f octo_event_emit >/dev/null 2>&1; then
        local _synth_count
        _synth_count=$(printf '%s' "$final_json" | jq '.findings | length' 2>/dev/null || echo 0)
        octo_event_emit "synthesis" phase="review" provider="claude-sonnet" provider_label_kind="legacy-alias" executor_alias="claude-sonnet" configured_provider="$(octo_provider_identity_from_agent_type "claude-sonnet")" configured_model="$(get_agent_model "claude-sonnet" "review" "synthesizer" 2>/dev/null || echo unresolved)" runtime_provider="unknown" runtime_model="unknown" council_role="synthesizer" synthesis_strategy="review" count="${_synth_count:-0}" || true
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
            [[ "$response" =~ ^[Yy] ]] && { post_inline_comments "$pr_number" "$findings_file" || render_terminal_report "$findings_file"; }
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
        proof_finding_count=$(jq '.findings | length' "$findings_file" 2>/dev/null || echo "0")
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

# post_inline_comments: posts findings as inline PR comments via gh API
# WHY: inline line-level comments match CC Code Review UX exactly.
post_inline_comments() {
    local pr_number="$1"
    local findings_file="$2"

    local repo=""
    repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
    if [[ -z "$repo" ]]; then
        log ERROR "post_inline_comments: could not determine repo (is gh auth configured?)"
        render_terminal_report "$findings_file"
        return 1
    fi

    local commit_id=""
    commit_id=$(gh pr view "$pr_number" --json headRefOid -q .headRefOid 2>/dev/null || true)

    if [[ -z "$commit_id" ]]; then
        log WARN "post_inline_comments: could not determine commit SHA for PR #$pr_number — posting summary comment only"
        local summary
        summary=$(render_review_summary "$findings_file")
        gh pr review "$pr_number" --comment --body "$summary" 2>/dev/null || true
        return 0
    fi

    local summary
    summary=$(render_review_summary "$findings_file")
    gh pr review "$pr_number" --comment --body "$summary" 2>/dev/null || true

    local finding_count
    finding_count=$(jq '.findings | length' "$findings_file" 2>/dev/null || echo "0")
    log INFO "post_inline_comments: posting $finding_count inline comments to PR #$pr_number"

    jq -c '.findings[]' "$findings_file" 2>/dev/null | while IFS= read -r finding; do
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

        gh api "repos/${repo}/pulls/${pr_number}/comments" \
            --method POST \
            -f body="$body" \
            -f commit_id="$commit_id" \
            -f path="$file" \
            -F line="$line" \
            -f side="RIGHT" 2>/dev/null || \
        log WARN "post_inline_comments: failed to post comment on $file:$line"
    done
}

# render_terminal_report: formats findings for terminal display
render_terminal_report() {
    local findings_file="$1"

    local finding_count
    finding_count=$(jq '.findings | length' "$findings_file" 2>/dev/null || echo "0")

    echo ""
    echo "+-----------------------------------------------------------------+"
    echo "|  /octo:review - Multi-LLM Code Review Results                  |"
    echo "+-----------------------------------------------------------------+"
    echo ""

    if [[ "$finding_count" -eq 0 ]]; then
        # v9.20.1: Distinguish "clean review" from "all providers failed" (#255)
        local warning_msg
        warning_msg=$(jq -r '.warning // empty' "$findings_file" 2>/dev/null)
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

    jq -c '.findings[]' "$findings_file" 2>/dev/null | while IFS= read -r finding; do
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
    local normal_count nit_count preexisting_count
    normal_count=$(jq '[.findings[] | select(.severity=="normal")] | length' "$findings_file" 2>/dev/null || echo "0")
    nit_count=$(jq '[.findings[] | select(.severity=="nit")] | length' "$findings_file" 2>/dev/null || echo "0")
    preexisting_count=$(jq '[.findings[] | select(.severity=="pre-existing")] | length' "$findings_file" 2>/dev/null || echo "0")

    echo "## /octo:review - Multi-LLM Code Review"
    echo ""
    echo "| Severity | Count |"
    echo "|----------|-------|"
    echo "| Normal | $normal_count |"
    echo "| Nit | $nit_count |"
    echo "| Pre-existing | $preexisting_count |"
    echo ""
    echo "_Reviewed by Codex + Gemini + Claude + Perplexity fleet_"
    echo "_See inline comments for details_"
}
