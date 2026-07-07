#!/usr/bin/env bash
# lib/heuristics.sh — Result scoring, ranking, aggregation, and synthesis
# Extracted from orchestrate.sh (v9.5.0+)
# Sourced by orchestrate.sh — do not run directly.

if ! type probe_result_file_status >/dev/null 2>&1; then
    _octo_probe_results_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/probe-results.sh"
    [[ -f "$_octo_probe_results_lib" ]] && source "$_octo_probe_results_lib"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# RESULT RANKING (v8.49.0)
# Ranks result files by quality signals WITHOUT deleting any content.
# Inspired by Crawl4AI's content filtering but adapted for multi-AI synthesis:
# rank by signals, present best first, let the synthesis LLM do the weighting.
# ═══════════════════════════════════════════════════════════════════════════════

# Score a single result file by quality signals (higher = more valuable)
# Returns score on stdout. Factors:
#   - Word count (log scale, max 40 pts): longer ≠ better, but extremely short = low value
#   - Code block count (max 20 pts): concrete examples signal actionable content
#   - Specificity (max 20 pts): named files/functions/URLs vs vague prose
#   - Structure (max 20 pts): headers, lists, tables signal organized thinking
# `grep -c` prints 0 AND exits 1 on no-match; naive `$(grep -c ... || echo 0)` concatenates a 2nd zero and breaks arithmetic.
safe_count() {
    local pattern="$1"
    local content="$2"
    local extra="${3:-}"
    local n
    if [[ "$extra" == "-E" ]]; then
        n=$(grep -cE -- "$pattern" <<<"$content" 2>/dev/null) || n=0
    else
        n=$(grep -c -- "$pattern" <<<"$content" 2>/dev/null) || n=0
    fi
    printf '%s' "${n:-0}"
}

score_result_file() {
    local file="$1"
    [[ ! -f "$file" ]] && echo "0" && return

    local content
    content=$(<"$file")
    local score=0

    # Factor 1: Word count (log scale, 0-40 pts)
    # 100 words=20pts, 500=30pts, 2000=40pts; <50 words=5pts
    local word_count
    word_count=$(wc -w <<< "$content" | tr -d ' ')
    if [[ $word_count -lt 50 ]]; then
        score=$((score + 5))
    elif [[ $word_count -lt 200 ]]; then
        score=$((score + 20))
    elif [[ $word_count -lt 1000 ]]; then
        score=$((score + 30))
    else
        score=$((score + 40))
    fi

    local code_blocks block_count
    code_blocks=$(safe_count '```' "$content")
    block_count=$(( code_blocks / 2 ))
    [[ $block_count -gt 4 ]] && block_count=4
    score=$((score + block_count * 5))

    local specifics
    specifics=$(safe_count '\.(ts|js|py|sh|rs|go|md|json)[ :\)]|/[a-z]+/' "$content" -E)
    [[ $specifics -gt 20 ]] && specifics=20
    score=$((score + specifics))

    local structure=0 headers bullets
    headers=$(safe_count '^#' "$content")
    [[ $headers -gt 5 ]] && headers=5
    structure=$((structure + headers * 2))
    bullets=$(safe_count '^[[:space:]]*[-*]' "$content")
    [[ $bullets -gt 5 ]] && bullets=5
    structure=$((structure + bullets * 2))
    [[ $structure -gt 20 ]] && structure=20
    score=$((score + structure))

    # Factor 5: Contract compliance (0-20 pts) — structured status markers from Output Contract
    local contract=0
    if grep -qE '\*\*Return status:\*\*|COMPLETE|BLOCKED|PARTIAL' <<< "$content" 2>/dev/null; then
        contract=$((contract + 10))
    fi
    if grep -qE 'Key Findings|Findings|Root Cause|Threat Model|Architecture|Components Implemented|Tests Written|Documentation Content|Data Model|Performance Baselines|Architecture Design' <<< "$content" 2>/dev/null; then
        contract=$((contract + 5))
    fi
    if grep -qE 'Confidence: \[?[0-9]' <<< "$content" 2>/dev/null; then
        contract=$((contract + 5))
    fi
    score=$((score + contract))

    echo "$score"
}

# Rank result files and return them ordered best-first (one path per line)
# Usage: rank_results_by_signals /path/to/results [filter]
rank_results_by_signals() {
    local results_dir="$1"
    local filter="${2:-}"
    local -a scored=()

    for result in "$results_dir"/*.md; do
        [[ -f "$result" ]] || continue
        [[ "$result" == *aggregate* ]] && continue
        [[ "$result" == *.raw-concat* ]] && continue
        [[ "$result" == *.partial-* ]] && continue
        [[ -n "$filter" && "$result" != *"$filter"* ]] && continue
        probe_result_file_is_usable "$result" || continue
        type octo_file_has_provider_rejection >/dev/null 2>&1 && octo_file_has_provider_rejection "$result" && continue

        local score
        score=$(score_result_file "$result")
        scored+=("${score}|${result}")
    done

    # Sort descending by score, output paths only
    printf '%s\n' "${scored[@]}" | sort -t'|' -k1 -rn | cut -d'|' -f2
}

probe_synthesis_sanitize_context() {
    sed \
        -e 's/\[Auto-synthesis failed - raw findings below\]/[Prior auto-synthesis failed; raw fallback omitted from compact probe context]/g' \
        -e 's/\[Synthesis failed - raw results attached\]/[Prior synthesis failed; raw fallback omitted from compact probe context]/g'
}

probe_synthesis_append_excerpt() {
    local file="$1"
    local max_chars="$2"
    local score="${3:-}"
    local size

    [[ -f "$file" ]] || return 0
    size=$(wc -c < "$file" 2>/dev/null | tr -d '[:space:]')
    size="${size:-0}"

    echo "## Source: $(basename "$file")${score:+ [Quality: ${score}/100]}"
    echo "- File: ${file}"
    echo "- Size: ${size} bytes"
    if [[ "$size" =~ ^[0-9]+$ && "$size" -gt "$max_chars" ]]; then
        echo "- Included: first ${max_chars} bytes (truncated)"
    else
        echo "- Included: full file"
    fi
    echo ""
    echo '```markdown'
    if [[ "$size" =~ ^[0-9]+$ && "$size" -gt "$max_chars" ]]; then
        head -c "$max_chars" "$file" 2>/dev/null | probe_synthesis_sanitize_context
        echo ""
        echo "[... truncated by probe synthesis context: original ${size} bytes, included ${max_chars} bytes ...]"
    else
        probe_synthesis_sanitize_context < "$file"
    fi
    echo '```'
    echo ""
}

build_probe_synthesis_context() {
    local task_group="$1"
    local max_file="${OCTOPUS_PROBE_SYNTHESIS_FILE_CHARS:-24000}"
    local max_total="${OCTOPUS_PROBE_SYNTHESIS_CONTEXT_CHARS:-120000}"

    [[ "$max_file" =~ ^[0-9]+$ ]] || max_file=24000
    [[ "$max_total" =~ ^[0-9]+$ ]] || max_total=120000
    max_file=$((10#$max_file))
    max_total=$((10#$max_total))
    [[ "$max_file" -lt 1000 ]] && max_file=1000
    [[ "$max_total" -lt 4000 ]] && max_total=4000

    local tmp_context
    tmp_context=$(mktemp "${TMPDIR:-/tmp}/octo-probe-synthesis.XXXXXX") || return 1

    local result_count=0
    {
        echo "# Compact Probe Synthesis Context"
        echo ""
        echo "This context is bounded before synthesis. Full raw probe artifacts remain on disk in RESULTS_DIR."
        echo ""
        echo "## Context Budget"
        echo "- Max per source file: ${max_file} bytes"
        echo "- Max total context: ${max_total} bytes"
        echo ""

        local ranked_file
        while IFS= read -r ranked_file; do
            [[ -z "$ranked_file" ]] && continue
            [[ ! -f "$ranked_file" ]] && continue
            probe_result_file_is_usable "$ranked_file" || continue
            type octo_file_has_provider_rejection >/dev/null 2>&1 && octo_file_has_provider_rejection "$ranked_file" && continue
            local score
            score=$(score_result_file "$ranked_file")
            probe_synthesis_append_excerpt "$ranked_file" "$max_file" "$score"
            ((result_count++)) || true
        done < <(rank_results_by_signals "$RESULTS_DIR" "probe-${task_group}")
    } > "$tmp_context"

    local total_size
    total_size=$(wc -c < "$tmp_context" 2>/dev/null | tr -d '[:space:]')
    total_size="${total_size:-0}"

    if [[ "$total_size" =~ ^[0-9]+$ && "$total_size" -gt "$max_total" ]]; then
        head -c "$max_total" "$tmp_context" 2>/dev/null
        echo ""
        echo ""
        echo "[... compact probe synthesis context truncated: original ${total_size} bytes, included ${max_total} bytes ...]"
    else
        cat "$tmp_context"
    fi

    rm -f "$tmp_context"
}

build_probe_fallback_synthesis() {
    local original_prompt="$1"
    local result_count="$2"
    local usable_results="$3"
    local total_content_size="$4"
    local compact_context="$5"

    cat <<EOF
Automated probe synthesis unavailable.

## Key Findings
The synthesis provider did not produce a coherent discovery summary. This fallback is intentionally compact and does not attach full raw probe artifacts.

## Source Coverage
- Usable research threads included: ${result_count}
- Usable results reported by probe: ${usable_results}
- Raw source bytes considered: ${total_content_size}
- Full raw artifacts remain available in RESULTS_DIR for manual inspection.

## Original Question
${original_prompt}

## Compact Source Context
${compact_context}
EOF
}

aggregate_results() {
    local _ts; _ts=$(date +%s)
    local filter="${1:-}"
    local user_query="${2:-}"  # v8.49.0: Optional user query for relevance-aware synthesis
    local aggregate_file="${RESULTS_DIR}/aggregate-${_ts}.md"
    local raw_concat="${RESULTS_DIR}/.raw-concat-$$.md"

    log INFO "Aggregating results..."

    # Phase 1: Collect results ranked by quality signals (v8.49.0)
    # Results are ordered best-first so the synthesis LLM sees highest-quality content first
    local result_count=0
    > "$raw_concat"
    local ranked_files
    if type agent_status_output_files >/dev/null 2>&1; then
        ranked_files=$(agent_status_output_files "$filter" 2>/dev/null || true)
    fi
    [[ -z "$ranked_files" ]] && ranked_files=$(rank_results_by_signals "$RESULTS_DIR" "$filter")

    if [[ -z "$ranked_files" ]]; then
        # Fallback: no ranked results, use original glob order
        for result in "$RESULTS_DIR"/*.md; do
            [[ -f "$result" ]] || continue
            [[ "$result" == *aggregate* ]] && continue
            [[ "$result" == *.raw-concat* ]] && continue
            [[ -n "$filter" && "$result" != *"$filter"* ]] && continue
            probe_result_file_is_usable "$result" || continue
            type octo_file_has_provider_rejection >/dev/null 2>&1 && octo_file_has_provider_rejection "$result" && continue
            ranked_files+="$result"$'\n'
        done
    fi

    local agent_summary=""
    if type render_agent_summary >/dev/null 2>&1; then
        agent_summary=$(render_agent_summary 2>/dev/null || true)
    fi

    while IFS= read -r result; do
        [[ -z "$result" ]] && continue
        [[ ! -f "$result" ]] && continue
        probe_result_file_is_usable "$result" || continue
        type octo_file_has_provider_rejection >/dev/null 2>&1 && octo_file_has_provider_rejection "$result" && continue
        local score
        score=$(score_result_file "$result")
        echo "---" >> "$raw_concat"
        echo "## Source: $(basename "$result") [Quality: ${score}/100]" >> "$raw_concat"
        echo "" >> "$raw_concat"
        cat "$result" >> "$raw_concat"
        echo "" >> "$raw_concat"
        ((result_count++)) || true
    done <<< "$ranked_files"

    # Phase 2: Synthesize if we have a provider available and multiple results
    if [[ $result_count -gt 1 ]] && [[ "$DRY_RUN" != "true" ]] && { command -v agy &> /dev/null || command -v claude &> /dev/null; }; then
        log INFO "Synthesizing $result_count results (ranked by quality, not just concatenating)..."

        # v8.49.0: Enhanced synthesis prompt with relevance awareness and structured output
        local query_context=""
        if [[ -n "$user_query" ]]; then
            query_context="
Original User Query: $user_query
Weight content by relevance to this query. Sources are pre-ranked by quality (best first)."
        fi

        local synthesis_prompt
        synthesis_prompt="Synthesize these $result_count subtask results into ONE coherent output.
${query_context}
Rules:
- Sources are ordered by quality score (best first); weight accordingly
- Merge overlapping content; preserve distinct contributions from each source
- Short but critical findings (minority opinions, edge cases, warnings) are EQUALLY important as verbose analysis — do NOT dismiss them for brevity
- If sources conflict, state the conflict and your resolution
- Cite the source provider/file for factual claims; mark uncited interpretation as [inference]
- Treat failed providers as unavailable, not as evidence
- The output must stand alone — a reader should get the complete picture without seeing the inputs

Structure the output as:
1. **Key Findings** — Top 3-5 actionable insights
2. **Detailed Analysis** — Organized by topic, not by source
3. **Conflicts & Trade-offs** — Where sources disagreed and why
4. **Recommendations** — Prioritized next steps

Agent status:
${agent_summary:-No agent status ledger available}

Subtask results:
$(<"$raw_concat")"

        # v9.47: synthesize via agy (sole Google seat), claude-sonnet fallback.
        local synthesis_result
        synthesis_result=$(run_agent_sync "agy" "$synthesis_prompt" "${TIMEOUT:-180}" "synthesizer" "ink" 2>/dev/null) || synthesis_result=""
        if [[ -z "$synthesis_result" ]]; then
            synthesis_result=$(run_agent_sync "claude-sonnet" "$synthesis_prompt" "${TIMEOUT:-180}" "synthesizer" "ink" 2>/dev/null) || synthesis_result=""
        fi
        if [[ -n "$synthesis_result" ]]; then
            echo "# Claude Octopus - Synthesized Results" > "$aggregate_file"
            echo "" >> "$aggregate_file"
            echo "Generated: $(date)" >> "$aggregate_file"
            echo "Sources: $result_count subtask outputs (ranked by quality)" >> "$aggregate_file"
            [[ -n "$user_query" ]] && echo "Query: $user_query" >> "$aggregate_file"
            if [[ -n "$agent_summary" ]]; then
                echo "" >> "$aggregate_file"
                echo "$agent_summary" >> "$aggregate_file"
            fi
            echo "" >> "$aggregate_file"
            echo "$synthesis_result" >> "$aggregate_file"
            rm -f "$raw_concat"
            log INFO "Synthesized $result_count results to: $aggregate_file"
            echo ""
            echo -e "${GREEN}✓${NC} Results synthesized to: $aggregate_file"
            guard_output "$(<"$aggregate_file")" "aggregate-synthesis"
            return
        fi
        log WARN "Synthesis failed, falling back to concatenation"
    fi

    # Fallback: concatenation (single result or no synthesis provider)
    echo "# Claude Octopus - Aggregated Results" > "$aggregate_file"
    echo "" >> "$aggregate_file"
    echo "Generated: $(date)" >> "$aggregate_file"
    if [[ -n "$agent_summary" ]]; then
        echo "" >> "$aggregate_file"
        echo "$agent_summary" >> "$aggregate_file"
    fi
    echo "" >> "$aggregate_file"
    cat "$raw_concat" >> "$aggregate_file"
    echo "" >> "$aggregate_file"
    echo "**Total Results: $result_count**" >> "$aggregate_file"

    rm -f "$raw_concat"
    log INFO "Aggregated $result_count results to: $aggregate_file"
    echo ""
    echo -e "${GREEN}✓${NC} Results aggregated to: $aggregate_file"
    guard_output "$(<"$aggregate_file")" "aggregate-concat"
}

# Synthesize probe results into insights
synthesize_probe_results() {
    local task_group="$1"
    local original_prompt="$2"
    local usable_results="${3:-0}"  # v7.19.0 P1.1: Accept usable result count
    local synthesis_file="${RESULTS_DIR}/probe-synthesis-${task_group}.md"

    log INFO "Synthesizing research findings..."

    # v7.19.0 P1.1: Gather probe result metrics with size filtering.
    # Do not concatenate raw artifacts here; synthesis gets a bounded context below.
    local results=""
    local result_count=0
    local total_content_size=0
    for result in "$RESULTS_DIR"/*-probe-${task_group}-*.md; do
        [[ -f "$result" ]] || continue
        probe_result_file_is_usable "$result" || { log DEBUG "Skipping $result (unusable probe output)"; continue; }
        type octo_file_has_provider_rejection >/dev/null 2>&1 && octo_file_has_provider_rejection "$result" && { log DEBUG "Skipping $result (provider rejection)"; continue; }

        local file_size
        file_size=$(wc -c < "$result" 2>/dev/null || echo "0")
        ((result_count++)) || true
        total_content_size=$((total_content_size + file_size))
    done

    # v7.19.0 P1.1: Graceful degradation - proceed with 2+ results
    if [[ $result_count -eq 0 ]]; then
        # v7.19.0 P1.3: Use enhanced error messaging
        local error_details=()
        error_details+=("All agents either failed, timed out without output, or produced empty results")
        error_details+=("Expected 4 probe results, found 0 with meaningful content")
        error_details+=("Check individual agent status in logs directory")
        enhanced_error "probe_synthesis_no_results" "$task_group" "${error_details[@]}"
        return 1
    elif [[ $result_count -eq 1 ]]; then
        log WARN "Only 1 usable result found (minimum 2 recommended)"
        log WARN "Synthesis quality may be reduced with limited perspectives"
        log WARN "Proceeding anyway..."
    elif [[ $result_count -lt 4 ]]; then
        log WARN "Proceeding with $result_count/$usable_results usable results ($(numfmt --to=iec-i --suffix=B $total_content_size 2>/dev/null || echo "${total_content_size}B"))"
    else
        log INFO "All $result_count results available for synthesis ($(numfmt --to=iec-i --suffix=B $total_content_size 2>/dev/null || echo "${total_content_size}B"))"
    fi

    # v8.49.0: Rank results by quality signals before synthesis.
    # Keep the synthesis prompt bounded; full raw files remain on disk.
    local compact_results
    if compact_results=$(build_probe_synthesis_context "$task_group") && [[ -n "$compact_results" ]]; then
        results="$compact_results"
    else
        results="# Compact Probe Synthesis Context"$'\n\n'"No bounded probe excerpts could be collected. Inspect RESULTS_DIR for raw artifacts."
    fi

    # Use agy for intelligent synthesis
    # v8.49.0: Enhanced prompt with structured output, minority opinion preservation,
    # and relevance-aware weighting (inspired by Crawl4AI content filtering patterns)
    local synthesis_prompt="Synthesize these research findings into a coherent discovery summary.

Original Question: $original_prompt

Agent status:
$(type render_agent_summary >/dev/null 2>&1 && render_agent_summary 2>/dev/null || echo "No agent status ledger available")

Sources are pre-ranked by quality score (best first). However:
- Short but specific findings may be MORE valuable than lengthy general analysis
- Minority opinions and dissenting views MUST be preserved — they often contain critical insights
- Concrete examples (code, file paths, commands) outweigh abstract discussion
- Every factual claim must cite its source provider/file or be explicitly marked [inference]
- Failed or rejected provider outputs were excluded and must not be cited as evidence

Structure your synthesis as:
1. **Key Findings** — Top 3-5 actionable insights, ranked by relevance to the original question
2. **Patterns & Consensus** — Where multiple sources agree
3. **Conflicts & Trade-offs** — Where sources disagree, with your reasoned resolution
4. **Gaps** — What's still unknown and needs more research
5. **Priority Matrix** — Rank findings by impact (High/Medium/Low) and effort (Low/Medium/High) in a table
6. **Recommended Approach** — Specific next steps based on findings

Research findings:
$results"

    # v9.47: synthesize via agy (sole Google seat), claude-sonnet, then compact fallback.
    local synthesis
    synthesis=$(run_agent_sync "agy" "$synthesis_prompt" "${TIMEOUT:-300}" "synthesizer" "probe" 2>/dev/null) || synthesis=""
    if [[ -z "$synthesis" ]]; then
        synthesis=$(run_agent_sync "claude-sonnet" "$synthesis_prompt" "${TIMEOUT:-300}" "synthesizer" "probe" 2>/dev/null) || synthesis=""
    fi
    if [[ -z "$synthesis" ]]; then
        log WARN "Synthesis failed, using compact fallback"
        synthesis=$(build_probe_fallback_synthesis "$original_prompt" "$result_count" "$usable_results" "$total_content_size" "$results")
    fi

    cat > "$synthesis_file" << EOF
# PROBE Phase Synthesis
## Discovery Summary - $(date)
## Original Task: $original_prompt

$synthesis

---
*Synthesized from $result_count research threads (task group: $task_group)*
EOF

    log INFO "Synthesis complete: $synthesis_file"

    # v7.19.0 P2.3: Save to cache for reuse
    local cache_key
    cache_key=$(get_cache_key "$original_prompt")
    save_to_cache "$cache_key" "$synthesis_file"

    local _green="${GREEN:-}"
    local _cyan="${CYAN:-}"
    local _nc="${NC:-}"
    echo ""
    echo -e "${_green}✓${_nc} Probe synthesis saved to: $synthesis_file"
    echo -e "${_cyan}♻️${_nc}  Cached for 1 hour (reuse if prompt unchanged)"
    echo ""
    guard_output "$(<"$synthesis_file")" "probe-synthesis"
}
