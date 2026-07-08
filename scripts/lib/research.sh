#!/usr/bin/env bash
# research.sh — Research workflow functions extracted from orchestrate.sh
# Functions: empathize_research, synthesize_research

empathize_research() {
    local prompt="$1"
    local task_group
    task_group=$(date +%s)

    echo ""
    echo -e "${MAGENTA}${_BOX_TOP}${NC}"
    echo -e "${MAGENTA}║  ${CYAN}🎯 EMPATHIZE${MAGENTA} - UX Research Synthesis Workflow            ║${NC}"
    echo -e "${MAGENTA}║  Multi-provider user research synthesis...                ║${NC}"
    echo -e "${MAGENTA}${_BOX_BOT}${NC}"
    echo ""

    log INFO "🐙 Dispatching UX research across providers..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would empathize: $prompt"
        log INFO "[DRY-RUN] Phase 1: Synthesize research data"
        log INFO "[DRY-RUN] Phase 2: Map user journeys and create personas"
        log INFO "[DRY-RUN] Phase 3: Define product requirements"
        log INFO "[DRY-RUN] Phase 4: Validate through adversarial review"
        return 0
    fi

    preflight_check || return 1
    mkdir -p "$RESULTS_DIR"

    echo -e "${CYAN}🦑 Phase 1/4: Synthesizing research data...${NC}"
    local synthesis
    synthesis=$(run_agent_sync "agy" "You are a UX researcher. Synthesize user research for: $prompt

Analyze the research context and provide:
1. Key user insights and patterns observed
2. User pain points ranked by severity
3. Unmet needs and opportunities
4. Behavioral themes across user segments

Format as a structured research synthesis." "${TIMEOUT:-300}" "ux-researcher" "empathize") || {
        log WARN "Antigravity failed for research synthesis, falling back to Claude"
        echo -e " ${YELLOW}⚠${NC}  Antigravity unavailable — falling back to Claude"
        synthesis=$(run_agent_sync "claude-sonnet" "You are a UX researcher. Synthesize user research for: $prompt. Provide: key insights, pain points, unmet needs, behavioral themes." "${TIMEOUT:-300}" "ux-researcher" "empathize") || true
    }

    echo -e "${CYAN}🦑 Phase 2/4: Creating personas and journey maps...${NC}"
    local personas
    personas=$(run_agent_sync "agy" "Based on this research synthesis:
$synthesis

Create:
1. 2-3 distinct user personas with goals, frustrations, and behaviors
2. A current-state journey map for the primary persona
3. Key moments of truth and emotional highs/lows

Use evidence-based persona development." "${TIMEOUT:-300}" "ux-researcher" "empathize") || {
        log WARN "Antigravity failed for personas, falling back to Claude"
        echo -e " ${YELLOW}⚠${NC}  Antigravity unavailable — falling back to Claude"
        personas=$(run_agent_sync "claude-sonnet" "Based on this research: $synthesis. Create 2-3 user personas and a journey map for the primary persona." "${TIMEOUT:-300}" "ux-researcher" "empathize") || true
    }

    echo -e "${CYAN}🦑 Phase 3/4: Defining product requirements...${NC}"
    local requirements
    requirements=$(run_agent_sync "codex" "Based on this UX research:

Research Synthesis:
$synthesis

Personas and Journeys:
$personas

Create product requirements:
1. User stories for addressing top 3 pain points
2. Acceptance criteria for each story
3. Success metrics tied to user outcomes
4. Prioritized backlog recommendations

Original context: $prompt" "${TIMEOUT:-300}" "product-writer" "empathize") || {
        log WARN "Codex failed for requirements, falling back to Claude"
        echo -e " ${YELLOW}⚠${NC}  Codex unavailable — falling back to Claude"
        requirements=$(run_agent_sync "claude-sonnet" "Based on research: $synthesis and personas: $personas. Create: user stories, acceptance criteria, success metrics, prioritized backlog. Context: $prompt" "${TIMEOUT:-300}" "product-writer" "empathize") || true
    }

    echo -e "${CYAN}🦑 Phase 4/4: Validating through adversarial review...${NC}"
    local validation
    validation=$(run_agent_sync "agy" "Critically review this UX research and requirements:

Research: $synthesis
Personas: $personas
Requirements: $requirements

Challenge:
1. Are the personas evidence-based or assumed?
2. Are there user segments being overlooked?
3. Do requirements actually address the pain points?
4. What biases might be present in the analysis?

Provide constructive critique and recommendations." 120 "ux-researcher" "empathize") || {
        log WARN "Antigravity failed for validation, falling back to Claude"
        echo -e " ${YELLOW}⚠${NC}  Antigravity unavailable — falling back to Claude"
        validation=$(run_agent_sync "claude-sonnet" "Critically review this UX research. Research: $synthesis. Personas: $personas. Requirements: $requirements. Challenge assumptions and identify biases." 120 "ux-researcher" "empathize") || true
    }

    local result_file="$RESULTS_DIR/empathize-${task_group}.md"
    cat > "$result_file" << EOF
# UX Research Synthesis: Empathize Workflow
**Generated:** $(date)
**Original Context:** $prompt

---

## Phase 1: Research Synthesis
$synthesis

---

## Phase 2: Personas & Journey Maps
$personas

---

## Phase 3: Product Requirements
$requirements

---

## Phase 4: Validation & Critique
$validation

---
*Generated by Claude Octopus empathize workflow* 🐙
EOF

    echo ""
    octopus_complete "Empathize"
    echo -e "  Result: ${CYAN}$result_file${NC}"
    echo ""

    log_agent_usage "empathize" "knowledge-work" "$prompt"
}

synthesize_research() {
    local prompt="$1"
    local task_group
    task_group=$(date +%s)

    echo ""
    echo -e "${MAGENTA}${_BOX_TOP}${NC}"
    echo -e "${MAGENTA}║  ${CYAN}📚 SYNTHESIZE${MAGENTA} - Research Synthesis Workflow              ║${NC}"
    echo -e "${MAGENTA}║  Multi-provider research literature synthesis...          ║${NC}"
    echo -e "${MAGENTA}${_BOX_BOT}${NC}"
    echo ""

    log INFO "🐙 Synthesizing research across providers..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would synthesize: $prompt"
        log INFO "[DRY-RUN] Phase 1: Gather and categorize sources"
        log INFO "[DRY-RUN] Phase 2: Thematic analysis and synthesis"
        log INFO "[DRY-RUN] Phase 3: Gap identification and future directions"
        log INFO "[DRY-RUN] Phase 4: Academic writing and formatting"
        return 0
    fi

    preflight_check || return 1
    mkdir -p "$RESULTS_DIR"

    echo -e "${CYAN}🦑 Phase 1/4: Gathering and categorizing sources...${NC}"
    local gathering
    gathering=$(run_agent_sync "agy" "You are a research synthesizer. For the topic: $prompt

Provide:
1. Key research areas and sub-topics to explore
2. Major theoretical frameworks relevant to this topic
3. Seminal works and key researchers in the field
4. Taxonomy for organizing the literature

Create a structure for systematic review." "${TIMEOUT:-300}" "research-synthesizer" "synthesize") || {
        log WARN "Antigravity failed for literature gathering, falling back to Claude"
        echo -e " ${YELLOW}⚠${NC}  Antigravity unavailable — falling back to Claude"
        gathering=$(run_agent_sync "claude-sonnet" "You are a research synthesizer. For: $prompt. Provide: key research areas, theoretical frameworks, seminal works, taxonomy for systematic review." "${TIMEOUT:-300}" "research-synthesizer" "synthesize") || true
    }

    echo -e "${CYAN}🦑 Phase 2/4: Conducting thematic analysis...${NC}"
    local themes
    themes=$(run_agent_sync "agy" "Based on this literature structure:
$gathering

Conduct thematic analysis:
1. Identify 4-6 major themes across the literature
2. Note points of consensus among researchers
3. Identify conflicting findings and their sources
4. Trace the evolution of thinking on this topic

Topic: $prompt" "${TIMEOUT:-300}" "research-synthesizer" "synthesize") || {
        log WARN "Antigravity failed for thematic analysis, falling back to Claude"
        echo -e " ${YELLOW}⚠${NC}  Antigravity unavailable — falling back to Claude"
        themes=$(run_agent_sync "claude-sonnet" "Based on: $gathering. Identify 4-6 themes, consensus points, conflicts, and evolution of thinking. Topic: $prompt" "${TIMEOUT:-300}" "research-synthesizer" "synthesize") || true
    }

    echo -e "${CYAN}🦑 Phase 3/4: Identifying gaps and future directions...${NC}"
    local gaps
    gaps=$(run_agent_sync "codex" "Based on this literature synthesis:

Structure: $gathering
Themes: $themes

Identify:
1. Research gaps - what hasn't been studied adequately?
2. Methodological limitations across studies
3. Theoretical gaps needing development
4. Practical implications needing research
5. Priority research questions for the field

Original topic: $prompt" "${TIMEOUT:-300}" "research-synthesizer" "synthesize") || {
        log WARN "Codex failed for gap identification, falling back to Claude"
        echo -e " ${YELLOW}⚠${NC}  Codex unavailable — falling back to Claude"
        gaps=$(run_agent_sync "claude-sonnet" "Based on structure: $gathering and themes: $themes. Identify: research gaps, methodological limitations, theoretical gaps, practical implications, priority questions. Topic: $prompt" "${TIMEOUT:-300}" "research-synthesizer" "synthesize") || true
    }

    echo -e "${CYAN}🦑 Phase 4/4: Drafting synthesis narrative...${NC}"
    local narrative
    narrative=$(run_agent_sync "agy" "Write a literature review synthesis for:

Topic: $prompt
Structure: $gathering
Themes: $themes
Gaps: $gaps

Create:
1. Introduction establishing importance and scope
2. Body organized by themes (not chronologically)
3. Critical synthesis connecting themes
4. Conclusion with gaps and future directions

Use academic writing conventions." "${TIMEOUT:-300}" "academic-writer" "synthesize") || {
        log WARN "Antigravity failed for synthesis narrative, falling back to Claude"
        echo -e " ${YELLOW}⚠${NC}  Antigravity unavailable — falling back to Claude"
        narrative=$(run_agent_sync "claude-sonnet" "Write a literature review for: $prompt. Structure: $gathering. Themes: $themes. Gaps: $gaps. Use academic writing conventions, organize by themes." "${TIMEOUT:-300}" "academic-writer" "synthesize") || true
    }

    local result_file="$RESULTS_DIR/synthesize-${task_group}.md"
    cat > "$result_file" << EOF
# Literature Synthesis: Research Workflow
**Generated:** $(date)
**Research Topic:** $prompt

---

## Synthesis Narrative
$narrative

---

## Appendix A: Literature Structure
$gathering

---

## Appendix B: Thematic Analysis
$themes

---

## Appendix C: Research Gaps & Future Directions
$gaps

---
*Generated by Claude Octopus synthesize workflow* 🐙
EOF

    echo ""
    octopus_complete "Synthesize"
    echo -e "  Result: ${CYAN}$result_file${NC}"
    echo ""

    log_agent_usage "synthesize" "knowledge-work" "$prompt"
}
