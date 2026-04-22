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

# build_review_fleet: builds active agent list based on available providers
# WHY: fleet is dynamic — if Perplexity is not configured, fall back to
# Gemini search; if Codex is unavailable, fall back to claude-sonnet.
# Returns a newline-separated list of "agent_type:role:specialty" triples.
# NOTE: Uses command -v for provider detection — safe with set -euo pipefail.
build_review_fleet() {
    local fleet=""

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
    local target focus provenance autonomy publish debate
    target=$(echo "$profile_json"     | jq -r '.target     // "staged"')
    focus=$(echo "$profile_json"      | jq -r '.focus      // ["correctness","security","architecture","tdd"]  | join(",")')
    provenance=$(echo "$profile_json" | jq -r '.provenance // "unknown"')
    autonomy=$(echo "$profile_json"   | jq -r '.autonomy   // "supervised"')
    publish=$(echo "$profile_json"    | jq -r '.publish    // "ask"')
    debate=$(echo "$profile_json"     | jq -r '.debate     // "auto"')

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

    log INFO "review_run: target=$target focus=$focus provenance=$provenance autonomy=$autonomy"

    # ── REVIEW.md ────────────────────────────────────────────────────────────
    parse_review_md
    local review_context=""
    if [[ -n "$REVIEW_ALWAYS_CHECK" || -n "$REVIEW_STYLE_RULES" ]]; then
        review_context="Repository review rules (from REVIEW.md):\nAlways check:\n${REVIEW_ALWAYS_CHECK}\nStyle:\n${REVIEW_STYLE_RULES}"
    fi

    # ── Collect diff ─────────────────────────────────────────────────────────
    local diff_content=""
    case "$target" in
        staged)       diff_content=$(git diff --cached 2>/dev/null || true) ;;
        working-tree) diff_content=$(git diff 2>/dev/null || true) ;;
        [0-9]*)       diff_content=$(gh pr diff "$target" 2>/dev/null || true) ;;
        *)            diff_content=$(git diff HEAD -- "$target" 2>/dev/null || true) ;;
    esac

    if [[ -z "$diff_content" ]]; then
        log WARN "review_run: no diff found for target=$target"
        echo '{"findings":[],"message":"No changes found to review"}' > "$findings_file"
        render_terminal_report "$findings_file"
        return 0
    fi

    # Apply skip patterns from REVIEW.md (pre-filter before spending tokens)
    if [[ -n "$REVIEW_SKIP_PATTERNS" ]]; then
        while IFS= read -r pattern; do
            [[ -z "$pattern" ]] && continue
            diff_content=$(echo "$diff_content" | grep -v "$pattern" || true)
        done <<< "$REVIEW_SKIP_PATTERNS"
    fi

    # ── Scale timeout by diff size (#303) ───────────────────────────────────
    local diff_lines
    diff_lines=$(echo "$diff_content" | wc -l | tr -d ' ')
    local review_timeout="${OCTOPUS_REVIEW_TIMEOUT:-480}"
    if [[ "$review_timeout" -eq 480 ]]; then
        if [[ "$diff_lines" -gt 5000 ]]; then
            review_timeout=900
        elif [[ "$diff_lines" -gt 2000 ]]; then
            review_timeout=600
        fi
    fi
    export TIMEOUT="$review_timeout"

    # ── ROUND 1: Parallel agent fleet ────────────────────────────────────────
    log INFO "review_run: Round 1 — parallel specialist fleet (timeout=${review_timeout}s, diff=${diff_lines} lines)"
    local fleet
    fleet=$(build_review_fleet)

    local agent_prompt_base
    agent_prompt_base="You are a code reviewer. Review the following diff and return ONLY a JSON object with a 'findings' array.

Each finding must have: file (string), line (integer), severity (normal|nit|pre-existing), category (string), title (string), detail (string), confidence (0.0-1.0).

Severity guide:
- normal: bug that should be fixed before merging (red)
- nit: minor issue, not blocking (yellow)
- pre-existing: bug not introduced by this PR (purple)

${review_context}

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

    fleet_dispatch_begin
    while IFS=: read -r agent_type role specialty; do
        [[ -z "$agent_type" ]] && continue
        local task_id="review-r1-${role}-${timestamp}"
        # Use spawn_agent's actual output path convention: ${RESULTS_DIR}/${agent_type}-${task_id}.md
        local result_file="${RESULTS_DIR}/${agent_type}-${task_id}.md"
        round1_files+=("$result_file")
        round1_agent_types+=("$agent_type")

        local agent_prompt="You are the ${role} specialist. Focus on: ${specialty}.

${agent_prompt_base}"

        spawn_agent "$agent_type" "$agent_prompt" "$task_id" "$role" "review" &
    done <<< "$fleet"

    fleet_dispatch_end

    # Wait for all Round 1 agents
    # v9.3.1: wait only catches direct children; spawn_agent's actual CLI runs as
    # grandchild processes. Poll result files for ## Status markers instead (#190).
    wait  # Wait for spawn_agent setup to finish
    local _poll_start
    _poll_start=$(date +%s)
    while true; do
        local _all_done=true
        for _rf in "${round1_files[@]}"; do
            if [[ ! -f "$_rf" ]] || [[ $(grep -cE '^## Status:' "$_rf" 2>/dev/null || true) -eq 0 ]]; then
                _all_done=false
                break
            fi
        done
        [[ "$_all_done" == "true" ]] && break
        if [[ $(( $(date +%s) - _poll_start )) -ge $review_timeout ]]; then
            log WARN "review_run: Round 1 timed out after ${review_timeout}s — collecting partial results"
            break
        fi
        sleep 2
    done
    log INFO "review_run: Round 1 complete"

    # Collect Round 1 findings — extract ## Output section, strip markdown fences, parse JSON
    local all_findings="[]"
    local idx=0
    for f in "${round1_files[@]}"; do
        [[ ! -f "$f" ]] && continue
        local agent_findings
        # v9.20.1: Extract content from ## Output section (portable awk, fixes BSD sed #255)
        agent_findings=$(awk '/^## Output$/{found=1;next} /^## /{if(found)exit} found && !/^```(json|JSON)?$/{print}' "$f" | \
            jq -r '.findings // []' 2>/dev/null || echo "[]")
        all_findings=$(printf '%s\n%s' "$all_findings" "$agent_findings" | \
            jq -s 'add' 2>/dev/null || echo "$all_findings")

        # v9.3.1: Write provider status for Round 1 agents (#187)
        local atype="${round1_agent_types[$idx]}"
        local provider_key="${atype%%[-_]*}"
        if [[ $(grep -c "Status: FAILED" "$f" 2>/dev/null || true) -gt 0 ]]; then
            echo "${provider_key}|fallback|Round 1 agent failed" >> "$provider_status_file"
        elif [[ "$agent_findings" != "[]" ]]; then
            echo "${provider_key}|ok|Round 1 findings" >> "$provider_status_file"
        fi
        ((idx++)) || true
    done

    # v9.20.1: Detect total fleet failure — all providers crashed/timed out (#255)
    local _r1_total=${#round1_files[@]}
    local _r1_failed=0
    for _rf in "${round1_files[@]}"; do
        if [[ ! -f "$_rf" ]] || \
           grep -qE '^## Status: (FAILED|TIMEOUT)' "$_rf" 2>/dev/null || \
           [[ $(grep -c '^## Status:' "$_rf" 2>/dev/null || true) -eq 0 ]]; then
            ((_r1_failed++)) || true
        fi
    done
    if [[ $_r1_failed -ge $_r1_total ]] && [[ $_r1_total -gt 0 ]]; then
        log ERROR "review_run: ALL Round 1 providers failed ($_r1_failed/$_r1_total). Review output is unreliable."
        echo "{\"findings\":[],\"warning\":\"All $_r1_total review providers failed. No code was actually reviewed. Run /octo:doctor to diagnose provider issues.\"}" > "$findings_file"
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

Diff:
\`\`\`
${diff_content}
\`\`\`

Findings to verify:
$(echo "$all_findings" | jq -c '.')

Return ONLY valid JSON with 'findings' array including verdict field."

    local verified_findings
    verified_findings=$(run_agent_sync "codex" "$verifier_prompt" 180 "code-reviewer" "review") && {
        echo "codex|ok|Round 2 verification" >> "$provider_status_file"
    } || {
        log WARN "review_run: codex verifier failed, falling back to claude-sonnet"
        log "USER" "⚠ Round 2: Codex unavailable → claude-sonnet (fallback). Codex API usage will NOT change."
        echo "codex|fallback|Round 2 → claude-sonnet" >> "$provider_status_file"
        verified_findings=$(run_agent_sync "claude-sonnet" "$verifier_prompt" 180 "code-reviewer" "review") || {
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
            debate_result=$(run_agent_sync "codex" "$debate_prompt" 120 "code-reviewer" "review") && {
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

    local final_json
    final_json=$(run_agent_sync "claude-sonnet" "$synthesis_prompt" 120 "code-reviewer" "review") || {
        log WARN "review_run: synthesis failed, using confirmed findings sorted as-is"
        final_json="{\"findings\":$(echo "$confirmed_findings" | jq -c 'sort_by(.severity)' 2>/dev/null || echo "[]")}"
    }

    # v9.3.1: Strip markdown fences from synthesis result (#188)
    final_json=$(echo "$final_json" | sed '/^```json$/d; /^```JSON$/d; /^```$/d')

    # Write findings file
    echo "$final_json" > "$findings_file"
    log INFO "review_run: findings saved to $findings_file"

    # ── Output ────────────────────────────────────────────────────────────────
    local pr_number=""
    pr_number=$(gh pr view --json number -q .number 2>/dev/null || true)

    if [[ -n "$pr_number" && "$publish" != "never" ]]; then
        local avg_confidence
        avg_confidence=$(jq '[.findings[].confidence] | if length > 0 then add/length else 0 end' \
            "$findings_file" 2>/dev/null || echo "0")
        if [[ "$publish" == "auto" ]] && awk "BEGIN{exit !($avg_confidence >= 0.85)}"; then
            log INFO "review_run: auto-publishing to PR #$pr_number (confidence=$avg_confidence)"
            post_inline_comments "$pr_number" "$findings_file" || render_terminal_report "$findings_file"
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
