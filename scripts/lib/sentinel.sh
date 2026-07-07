#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# sentinel.sh — Extracted from orchestrate.sh (v9.7.5)
# Contains: sentinel_tick, advise_strategy
# ═══════════════════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════════════════════
# SENTINEL - GitHub-Aware Work Monitor (v8.18.0)
# Triages issues, PRs, and CI failures without auto-executing workflows
# ═══════════════════════════════════════════════════════════════════════════════

sentinel_tick() {
    local triage_dir="${WORKSPACE_DIR}/.octo/sentinel"
    local triage_log="$triage_dir/triage-log.md"
    mkdir -p "$triage_dir"

    if [[ "$OCTOPUS_SENTINEL_ENABLED" != "true" ]]; then
        log WARN "Sentinel is disabled. Set OCTOPUS_SENTINEL_ENABLED=true to enable."
        return 1
    fi

    if ! command -v gh &>/dev/null; then
        log ERROR "Sentinel requires GitHub CLI (gh). Install with: brew install gh"
        return 1
    fi

    echo ""
    echo -e "${CYAN}${_BOX_TOP}${NC}"
    echo -e "${CYAN}║  🔭 SENTINEL - GitHub Work Monitor                       ║${NC}"
    echo -e "${CYAN}${_BOX_BOT}${NC}"
    echo ""

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local triage_count=0

    # ── Triage Issues ──
    log INFO "Sentinel: Scanning issues..."
    local issues=""
    issues=$(gh issue list --label octopus --json number,title,labels,createdAt --limit 10 2>/dev/null) || true

    if [[ -n "$issues" && "$issues" != "[]" ]]; then
        local issue_count
        issue_count=$(echo "$issues" | jq 'length' 2>/dev/null || echo "0")
        echo -e "  ${GREEN}Issues:${NC} $issue_count tagged with 'octopus' label"

        echo "$issues" | jq -r '.[] | "\(.number)|\(.title)"' 2>/dev/null | while IFS='|' read -r num title; do
            # Dedup: skip if already triaged
            if grep -q "Issue #${num}" "$triage_log" 2>/dev/null; then
                continue
            fi

            local task_type
            task_type=$(classify_task "$title" 2>/dev/null || echo "unknown")
            local recommended=""
            case "$task_type" in
                crossfire-*) recommended="/octo:develop" ;;
                knowledge-*) recommended="/octo:research" ;;
                image-*) recommended="/octo:quick" ;;
                *) recommended="/octo:tangle" ;;
            esac

            echo "### Issue #${num}: ${title}" >> "$triage_log"
            echo "- **Triaged:** ${timestamp}" >> "$triage_log"
            echo "- **Classification:** ${task_type}" >> "$triage_log"
            echo "- **Recommended:** ${recommended}" >> "$triage_log"
            echo "---" >> "$triage_log"
            ((triage_count++)) || true

            echo -e "    #${num}: ${title:0:60} → ${YELLOW}${recommended}${NC}"
        done
    else
        echo -e "  ${DIM:-}Issues: No octopus-labeled issues found${NC}"
    fi

    # ── Triage PRs ──
    log INFO "Sentinel: Scanning pull requests..."
    local prs=""
    prs=$(gh pr list --json number,title,reviewDecision,createdAt --limit 10 2>/dev/null) || true

    if [[ -n "$prs" && "$prs" != "[]" ]]; then
        local review_needed
        review_needed=$(echo "$prs" | jq '[.[] | select(.reviewDecision == "REVIEW_REQUIRED" or .reviewDecision == "")] | length' 2>/dev/null || echo "0")
        echo -e "  ${GREEN}PRs:${NC} $review_needed needing review"

        echo "$prs" | jq -r '.[] | select(.reviewDecision == "REVIEW_REQUIRED" or .reviewDecision == "") | "\(.number)|\(.title)"' 2>/dev/null | while IFS='|' read -r num title; do
            if grep -q "PR #${num}" "$triage_log" 2>/dev/null; then
                continue
            fi

            echo "### PR #${num}: ${title}" >> "$triage_log"
            echo "- **Triaged:** ${timestamp}" >> "$triage_log"
            echo "- **Recommended:** /octo:ink (review)" >> "$triage_log"
            echo "---" >> "$triage_log"
            ((triage_count++)) || true

            echo -e "    #${num}: ${title:0:60} → ${YELLOW}/octo:ink${NC}"
        done
    else
        echo -e "  ${DIM:-}PRs: No PRs needing review${NC}"
    fi

    # ── Triage CI Failures ──
    log INFO "Sentinel: Scanning CI runs..."
    local runs=""
    runs=$(gh run list --status failure --json databaseId,displayTitle,conclusion,createdAt --limit 5 2>/dev/null) || true

    if [[ -n "$runs" && "$runs" != "[]" ]]; then
        local fail_count
        fail_count=$(echo "$runs" | jq 'length' 2>/dev/null || echo "0")
        echo -e "  ${RED}CI Failures:${NC} $fail_count recent failures"

        echo "$runs" | jq -r '.[] | "\(.databaseId)|\(.displayTitle)"' 2>/dev/null | while IFS='|' read -r id title; do
            if grep -q "CI #${id}" "$triage_log" 2>/dev/null; then
                continue
            fi

            echo "### CI #${id}: ${title}" >> "$triage_log"
            echo "- **Triaged:** ${timestamp}" >> "$triage_log"
            echo "- **Recommended:** /octo:debug" >> "$triage_log"
            echo "---" >> "$triage_log"
            ((triage_count++)) || true

            echo -e "    CI #${id}: ${title:0:60} → ${YELLOW}/octo:debug${NC}"
        done
    else
        echo -e "  ${DIM:-}CI: No recent failures${NC}"
    fi

    echo ""
    echo -e "  ${CYAN}Triage log:${NC} $triage_log"
    echo ""

    log INFO "Sentinel tick complete. New items triaged: $triage_count"
}

advise_strategy() {
    local prompt="$1"
    local task_group
    task_group=$(date +%s)

    echo ""
    echo -e "${MAGENTA}${_BOX_TOP}${NC}"
    echo -e "${MAGENTA}║  ${CYAN}📊 ADVISE${MAGENTA} - Strategic Consulting Workflow                ║${NC}"
    echo -e "${MAGENTA}║  Multi-provider strategic consulting analysis...          ║${NC}"
    echo -e "${MAGENTA}${_BOX_BOT}${NC}"
    echo ""

    log INFO "🐙 Running multi-provider strategic analysis..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would advise: $prompt"
        log INFO "[DRY-RUN] Phase 1: Market and competitive analysis"
        log INFO "[DRY-RUN] Phase 2: Strategic framework application"
        log INFO "[DRY-RUN] Phase 3: Business case and recommendations"
        log INFO "[DRY-RUN] Phase 4: Executive communication"
        return 0
    fi

    preflight_check || return 1
    mkdir -p "$RESULTS_DIR"

    echo -e "${CYAN}🦑 Phase 1/4: Analyzing market and competitive landscape...${NC}"
    local analysis
    analysis=$(run_agent_sync "agy" "You are a strategy analyst. Analyze the strategic context for: $prompt

Provide:
1. Market sizing (TAM/SAM/SOM if applicable)
2. Competitive landscape overview
3. Key industry trends and disruption factors
4. PESTLE factors affecting the decision

Be specific with data where possible, noting assumptions." "${TIMEOUT:-300}" "strategy-analyst" "advise") || {
        log WARN "Antigravity (agy) failed for market analysis, falling back to Claude"
        echo -e " ${YELLOW}⚠${NC}  Antigravity unavailable — falling back to Claude"
        analysis=$(run_agent_sync "claude-sonnet" "You are a strategy analyst. Analyze the strategic context for: $prompt. Provide: market sizing, competitive landscape, industry trends, PESTLE factors." "${TIMEOUT:-300}" "strategy-analyst" "advise") || true
    }

    echo -e "${CYAN}🦑 Phase 2/4: Applying strategic frameworks...${NC}"
    local frameworks
    frameworks=$(run_agent_sync "agy" "Based on this analysis:
$analysis

Apply relevant strategic frameworks:
1. SWOT Analysis (internal strengths/weaknesses, external opportunities/threats)
2. Porter's Five Forces (if industry analysis is relevant)
3. Strategic options matrix with trade-offs

Context: $prompt" "${TIMEOUT:-300}" "strategy-analyst" "advise") || {
        log WARN "Antigravity (agy) failed for strategic frameworks, falling back to Claude"
        echo -e " ${YELLOW}⚠${NC}  Antigravity unavailable — falling back to Claude"
        frameworks=$(run_agent_sync "claude-sonnet" "Based on this analysis: $analysis. Apply SWOT, Porter's Five Forces, and strategic options matrix. Context: $prompt" "${TIMEOUT:-300}" "strategy-analyst" "advise") || true
    }

    echo -e "${CYAN}🦑 Phase 3/4: Building business case and recommendations...${NC}"
    local recommendations
    recommendations=$(run_agent_sync "codex" "Based on this strategic analysis:

Market Analysis:
$analysis

Framework Analysis:
$frameworks

Develop:
1. 2-3 strategic options with pros/cons
2. Recommended option with clear rationale
3. Implementation considerations and risks
4. Success metrics and KPIs
5. 90-day action plan

Original question: $prompt" "${TIMEOUT:-300}" "strategy-analyst" "advise") || {
        log WARN "Codex failed for recommendations, falling back to Claude"
        echo -e " ${YELLOW}⚠${NC}  Codex unavailable — falling back to Claude"
        recommendations=$(run_agent_sync "claude-sonnet" "Based on analysis: $analysis and frameworks: $frameworks. Develop: strategic options, recommendation, risks, KPIs, 90-day plan. Question: $prompt" "${TIMEOUT:-300}" "strategy-analyst" "advise") || true
    }

    echo -e "${CYAN}🦑 Phase 4/4: Crafting executive communication...${NC}"
    local executive_summary
    executive_summary=$(run_agent_sync "agy" "Create an executive summary from this strategic analysis:

Analysis: $analysis
Frameworks: $frameworks
Recommendations: $recommendations

Format as:
1. Executive Summary (3-5 bullet points, bottom line up front)
2. Key recommendation with supporting rationale
3. Required decisions and asks
4. Timeline and next steps

Make it board-ready and actionable." 120 "exec-communicator" "advise") || {
        log WARN "Antigravity (agy) failed for executive summary, falling back to Claude"
        echo -e " ${YELLOW}⚠${NC}  Antigravity unavailable — falling back to Claude"
        executive_summary=$(run_agent_sync "claude-sonnet" "Create a board-ready executive summary from: Analysis: $analysis. Recommendations: $recommendations. Format: bullet points, key recommendation, decisions, timeline." 120 "exec-communicator" "advise") || true
    }

    local result_file="$RESULTS_DIR/advise-${task_group}.md"
    cat > "$result_file" << EOF
# Strategic Analysis: Advise Workflow
**Generated:** $(date)
**Strategic Question:** $prompt

---

## Executive Summary
$executive_summary

---

## Phase 1: Market & Competitive Analysis
$analysis

---

## Phase 2: Strategic Frameworks
$frameworks

---

## Phase 3: Recommendations & Business Case
$recommendations

---
*Generated by Claude Octopus advise workflow* 🐙
EOF

    echo ""
    octopus_complete "Advise"
    echo -e "  Result: ${CYAN}$result_file${NC}"
    echo ""

    log_agent_usage "advise" "knowledge-work" "$prompt"
}
