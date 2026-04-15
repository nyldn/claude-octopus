#!/usr/bin/env bash
# lib/heuristics.sh — Result scoring, ranking, aggregation, and synthesis
# Extracted from orchestrate.sh (v9.5.0+)
# Sourced by orchestrate.sh — do not run directly.

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

        local score
        score=$(score_result_file "$result")
        scored+=("${score}|${result}")
    done

    # Sort descending by score, output paths only
    printf '%s\n' "${scored[@]}" | sort -t'|' -k1 -rn | cut -d'|' -f2
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
    ranked_files=$(rank_results_by_signals "$RESULTS_DIR" "$filter")

    if [[ -z "$ranked_files" ]]; then
        # Fallback: no ranked results, use original glob order
        for result in "$RESULTS_DIR"/*.md; do
            [[ -f "$result" ]] || continue
            [[ "$result" == *aggregate* ]] && continue
            [[ "$result" == *.raw-concat* ]] && continue
            [[ -n "$filter" && "$result" != *"$filter"* ]] && continue
            ranked_files+="$result"$'\n'
        done
    fi

    while IFS= read -r result; do
        [[ -z "$result" ]] && continue
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
    if [[ $result_count -gt 1 ]] && command -v gemini &> /dev/null && [[ "$DRY_RUN" != "true" ]]; then
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
- The output must stand alone — a reader should get the complete picture without seeing the inputs

Structure the output as:
1. **Key Findings** — Top 3-5 actionable insights
2. **Detailed Analysis** — Organized by topic, not by source
3. **Conflicts & Trade-offs** — Where sources disagreed and why
4. **Recommendations** — Prioritized next steps

Subtask results:
$(<"$raw_concat")"

        local synthesis_result
        if synthesis_result=$(printf '%s' "$synthesis_prompt" | run_with_timeout "$TIMEOUT" gemini 2>/dev/null) && [[ -n "$synthesis_result" ]]; then
            echo "# Claude Octopus - Synthesized Results" > "$aggregate_file"
            echo "" >> "$aggregate_file"
            echo "Generated: $(date)" >> "$aggregate_file"
            echo "Sources: $result_count subtask outputs (ranked by quality)" >> "$aggregate_file"
            [[ -n "$user_query" ]] && echo "Query: $user_query" >> "$aggregate_file"
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

    # v7.19.0 P1.1: Gather all probe results with size filtering
    local results=""
    local result_count=0
    local total_content_size=0
    for result in "$RESULTS_DIR"/*-probe-${task_group}-*.md; do
        [[ -f "$result" ]] || continue

        # Check if file has meaningful content (>500 bytes of actual content)
        local file_size
        file_size=$(wc -c < "$result" 2>/dev/null || echo "0")

        if [[ $file_size -gt 500 ]]; then
            results+="$(<"$result")\n\n---\n\n"
            ((result_count++)) || true
            total_content_size=$((total_content_size + file_size))
        else
            log DEBUG "Skipping $result (too small: ${file_size}B)"
        fi
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

    # v8.49.0: Rank results by quality signals before synthesis
    # Re-collect results in ranked order so the synthesis LLM sees best content first
    local ranked_results=""
    local ranked_file
    while IFS= read -r ranked_file; do
        [[ -z "$ranked_file" ]] && continue
        [[ ! -f "$ranked_file" ]] && continue
        local file_size
        file_size=$(wc -c < "$ranked_file" 2>/dev/null || echo "0")
        [[ $file_size -le 500 ]] && continue
        local score
        score=$(score_result_file "$ranked_file")
        ranked_results+="--- [Quality: ${score}/100] ---\n$(<"$ranked_file")\n\n"
    done < <(rank_results_by_signals "$RESULTS_DIR" "probe-${task_group}")
    # Use ranked results if available, fall back to original collection
    [[ -n "$ranked_results" ]] && results="$ranked_results"

    # Use Gemini for intelligent synthesis
    # v8.49.0: Enhanced prompt with structured output, minority opinion preservation,
    # and relevance-aware weighting (inspired by Crawl4AI content filtering patterns)
    local synthesis_prompt="Synthesize these research findings into a coherent discovery summary.

Original Question: $original_prompt

Sources are pre-ranked by quality score (best first). However:
- Short but specific findings may be MORE valuable than lengthy general analysis
- Minority opinions and dissenting views MUST be preserved — they often contain critical insights
- Concrete examples (code, file paths, commands) outweigh abstract discussion

Structure your synthesis as:
1. **Key Findings** — Top 3-5 actionable insights, ranked by relevance to the original question
2. **Patterns & Consensus** — Where multiple sources agree
3. **Conflicts & Trade-offs** — Where sources disagree, with your reasoned resolution
4. **Gaps** — What's still unknown and needs more research
5. **Priority Matrix** — Rank findings by impact (High/Medium/Low) and effort (Low/Medium/High) in a table
6. **Recommended Approach** — Specific next steps based on findings

Research findings:
$results"

    local synthesis
    synthesis=$(run_agent_sync "gemini" "$synthesis_prompt" 180) || {
        log WARN "Synthesis failed, using concatenation fallback"
        synthesis="[Auto-synthesis failed - raw findings below]\n\n$results"
    }

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

    echo ""
    echo -e "${GREEN}✓${NC} Probe synthesis saved to: $synthesis_file"
    echo -e "${CYAN}♻️${NC}  Cached for 1 hour (reuse if prompt unchanged)"
    echo ""
    guard_output "$(<"$synthesis_file")" "probe-synthesis"
}
