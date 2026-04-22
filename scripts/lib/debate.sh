#!/usr/bin/env bash
# lib/debate.sh — Adversarial cross-model debate (extracted from orchestrate.sh)
# Provides: grapple_debate

# ═══════════════════════════════════════════════════════════════════════════
# CROSSFIRE - Adversarial Cross-Model Review
# Two tentacles wrestling—adversarial debate until consensus 🤼
# ═══════════════════════════════════════════════════════════════════════════

grapple_debate() {
    local prompt="$1"
    local principles="${2:-general}"
    local rounds="${3:-3}"  # v7.13.2: Configurable rounds (default 3)
    local debate_mode="${4:-cross-critique}"  # v8.31.0: cross-critique (ACH) or blinded (independent)
    local task_group
    task_group=$(date +%s)

    # Validate rounds (3-7 allowed)
    if [[ $rounds -lt 3 ]]; then
        log WARN "Minimum 3 rounds required, using 3"
        rounds=3
    elif [[ $rounds -gt 7 ]]; then
        log WARN "Maximum 7 rounds allowed, using 7"
        rounds=7
    fi

    # v8.31.0: Blinded mode skips rebuttals (nothing to rebut against)
    if [[ "$debate_mode" == "blinded" && $rounds -gt 3 ]]; then
        log WARN "Blinded mode uses 3 rounds (no rebuttals). Ignoring -r $rounds"
        rounds=3
    fi

    echo ""
    echo -e "${RED}${_BOX_TOP}${NC}"
    echo -e "${RED}║  🤼 GRAPPLE - Adversarial Cross-Model Review              ║${NC}"
    echo -e "${RED}║  Codex vs Gemini vs Sonnet 4.6 debate (${rounds} rounds)  ║${NC}"
    if [[ "$debate_mode" == "blinded" ]]; then
    echo -e "${RED}║  Mode: Blinded (independent evaluation, no anchoring)     ║${NC}"
    fi
    echo -e "${RED}${_BOX_BOT}${NC}"
    echo ""

    log INFO "Starting adversarial cross-model debate ($rounds rounds, mode: $debate_mode)"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would grapple on: $prompt"
        log INFO "[DRY-RUN] Principles: $principles"
        log INFO "[DRY-RUN] Round 1: Generate competing proposals (Codex + Gemini + Sonnet 4.6)"
        log INFO "[DRY-RUN] Round 2: Cross-critique (each critiques the other two)"
        log INFO "[DRY-RUN] Round 3: Synthesis and winner determination"
        return 0
    fi

    # Pre-flight validation
    preflight_check || return 1

    mkdir -p "$RESULTS_DIR" "$LOGS_DIR"

    # Load principles if available
    local principle_text=""
    local principle_file="$PLUGIN_DIR/agents/principles/${principles}.md"
    if [[ -f "$principle_file" ]]; then
        # Extract content after frontmatter
        principle_text=$(awk '/^---$/{if(++c==2)p=1;next}p' "$principle_file")
        log INFO "Loaded principles: $principles"
    else
        log DEBUG "No principles file found for: $principles"
    fi

    # ═══════════════════════════════════════════════════════════════════════
    # Round 1: Parallel proposals
    # ═══════════════════════════════════════════════════════════════════════
    echo ""
    echo -e "${CYAN}[Round 1/3] Generating competing proposals...${NC}"
    echo ""

    # Constraint to prevent agentic file exploration
    local no_explore_constraint="IMPORTANT: Do NOT read, explore, or modify any files. Do NOT run any shell commands. Just output your response as TEXT directly. This is a debate exercise, not a coding session."

    # v8.31.0: Debate integrity rules — always-on quality constraints
    local debate_integrity_rules="
DEBATE INTEGRITY RULES (MANDATORY — follow these in every response):
- ANTI-CONTRARIAN: Do NOT disagree just to create conflict. If an approach is genuinely sound, acknowledge it with specific technical evidence.
- ANTI-RUBBER-STAMP: Do NOT agree just to be agreeable. If you see a real flaw, name it concretely even if the overall approach is good.
- EVIDENCE-BASED: Every claim (positive or negative) MUST cite a specific technical reason, not vague sentiment like 'feels cleaner' or 'seems better'.
- PROPORTIONAL: A minor style issue is NOT a critical flaw. A fundamental architecture mistake is NOT a 'minor concern'. Calibrate severity honestly."

    local codex_proposal gemini_proposal sonnet_proposal
    codex_proposal=$(run_agent_sync "codex" "
$no_explore_constraint

You are formulating a HYPOTHESIS. Propose your best approach to this task:
$prompt

${principle_text:+Adhere to these principles:
$principle_text}

Structure your response:
1. HYPOTHESIS: Your proposed approach and why it should work
2. KEY ASSUMPTIONS: List 3-5 assumptions your approach depends on
3. FALSIFICATION CRITERIA: What evidence would DISPROVE this approach?
4. IMPLEMENTATION: Your concrete implementation

$debate_integrity_rules
Be thorough and practical." 120 "implementer" "grapple")

    if [[ $? -ne 0 || -z "$codex_proposal" ]]; then
        echo ""
        echo -e "${RED}❌ Codex proposal generation failed${NC}"
        echo -e "   Check logs: ${LOGS_DIR}/"
        log ERROR "Grapple debate failed: Codex proposal empty or error"
        return 1
    fi

    gemini_proposal=$(run_agent_sync "gemini" "
$no_explore_constraint

You are formulating a HYPOTHESIS. Propose your best approach to this task:
$prompt

${principle_text:+Adhere to these principles:
$principle_text}

Structure your response:
1. HYPOTHESIS: Your proposed approach and why it should work
2. KEY ASSUMPTIONS: List 3-5 assumptions your approach depends on
3. FALSIFICATION CRITERIA: What evidence would DISPROVE this approach?
4. IMPLEMENTATION: Your concrete implementation

$debate_integrity_rules
Be thorough and practical." 120 "researcher" "grapple")

    if [[ $? -ne 0 || -z "$gemini_proposal" ]]; then
        echo ""
        echo -e "${RED}❌ Gemini proposal generation failed${NC}"
        echo -e "   Check logs: ${LOGS_DIR}/"
        log ERROR "Grapple debate failed: Gemini proposal empty or error"
        return 1
    fi

    sonnet_proposal=$(run_agent_sync "claude-sonnet" "
$no_explore_constraint

You are formulating a HYPOTHESIS. Propose your best approach to this task:
$prompt

${principle_text:+Adhere to these principles:
$principle_text}

Structure your response:
1. HYPOTHESIS: Your proposed approach and why it should work
2. KEY ASSUMPTIONS: List 3-5 assumptions your approach depends on
3. FALSIFICATION CRITERIA: What evidence would DISPROVE this approach?
4. IMPLEMENTATION: Your concrete implementation

$debate_integrity_rules
Be thorough and practical." 120 "researcher" "grapple")

    if [[ $? -ne 0 || -z "$sonnet_proposal" ]]; then
        echo ""
        echo -e "${RED}❌ Sonnet proposal generation failed${NC}"
        echo -e "   Check logs: ${LOGS_DIR}/"
        log ERROR "Grapple debate failed: Sonnet proposal empty or error"
        return 1
    fi

    # ═══════════════════════════════════════════════════════════════════════
    # Round 2: Critique — mode-aware (v8.31.0)
    # cross-critique: ACH falsification — models see each other's proposals
    # blinded: Independent evaluation — models evaluate against criteria only
    # ═══════════════════════════════════════════════════════════════════════
    echo ""
    if [[ "$debate_mode" == "blinded" ]]; then
        echo -e "${CYAN}[Round 2/3] Independent evaluation (blinded — no cross-contamination)...${NC}"
    else
        echo -e "${CYAN}[Round 2/3] Cross-model critique (ACH falsification)...${NC}"
    fi
    echo ""

    local codex_critique gemini_critique sonnet_critique

    if [[ "$debate_mode" == "blinded" ]]; then
        # ── BLINDED MODE: Each model evaluates independently against criteria ──
        # No model sees another's proposals — prevents anchoring bias

        codex_critique=$(run_agent_sync "codex-review" "
$no_explore_constraint

You are an INDEPENDENT EVALUATOR. You have NOT seen any other model's proposals.
Evaluate this task and identify potential risks, failure modes, and overlooked concerns:

TASK:
$prompt

${principle_text:+Evaluate against these principles:
$principle_text}

Provide your INDEPENDENT assessment:
- TOP 3 RISKS: What could go wrong with common approaches to this task?
- OVERLOOKED CONCERNS: What do teams typically miss when solving this?
- CRITICAL ASSUMPTIONS: What assumptions would need to be true for any solution to work?
- EVALUATION CRITERIA: How should solutions be judged? Rate each criterion by importance (1-10).
$debate_integrity_rules" 90 "code-reviewer" "grapple")

        if [[ $? -ne 0 || -z "$codex_critique" ]]; then
            echo -e "${RED}❌ Codex evaluation failed${NC}"
            log ERROR "Grapple debate failed: Codex blinded evaluation empty or error"
            return 1
        fi

        gemini_critique=$(run_agent_sync "gemini" "
$no_explore_constraint

You are an INDEPENDENT EVALUATOR. You have NOT seen any other model's proposals.
Evaluate this task and identify potential risks, failure modes, and overlooked concerns:

TASK:
$prompt

${principle_text:+Evaluate against these principles:
$principle_text}

Provide your INDEPENDENT assessment:
- TOP 3 RISKS: What could go wrong with common approaches to this task?
- OVERLOOKED CONCERNS: What do teams typically miss when solving this?
- CRITICAL ASSUMPTIONS: What assumptions would need to be true for any solution to work?
- EVALUATION CRITERIA: How should solutions be judged? Rate each criterion by importance (1-10).
$debate_integrity_rules" 90 "security-auditor" "grapple")

        if [[ $? -ne 0 || -z "$gemini_critique" ]]; then
            echo -e "${RED}❌ Gemini evaluation failed${NC}"
            log ERROR "Grapple debate failed: Gemini blinded evaluation empty or error"
            return 1
        fi

        sonnet_critique=$(run_agent_sync "claude-sonnet" "
$no_explore_constraint

You are an INDEPENDENT EVALUATOR. You have NOT seen any other model's proposals.
Evaluate this task and identify potential risks, failure modes, and overlooked concerns:

TASK:
$prompt

${principle_text:+Evaluate against these principles:
$principle_text}

Provide your INDEPENDENT assessment:
- TOP 3 RISKS: What could go wrong with common approaches to this task?
- OVERLOOKED CONCERNS: What do teams typically miss when solving this?
- CRITICAL ASSUMPTIONS: What assumptions would need to be true for any solution to work?
- EVALUATION CRITERIA: How should solutions be judged? Rate each criterion by importance (1-10).
$debate_integrity_rules" 90 "code-reviewer" "grapple")

        if [[ $? -ne 0 || -z "$sonnet_critique" ]]; then
            echo -e "${RED}❌ Sonnet evaluation failed${NC}"
            log ERROR "Grapple debate failed: Sonnet blinded evaluation empty or error"
            return 1
        fi

    else
        # ── CROSS-CRITIQUE MODE (default): ACH falsification ──

        # Codex falsifies Gemini + Sonnet hypotheses
        codex_critique=$(run_agent_sync "codex-review" "
$no_explore_constraint

You are a FALSIFIER using Analysis of Competing Hypotheses (ACH). Your job is to DISPROVE these proposals by testing their stated assumptions.

HYPOTHESIS 1 (from Gemini):
$gemini_proposal

HYPOTHESIS 2 (from Sonnet 4.6):
$sonnet_proposal

For each hypothesis, attempt to falsify it:
- ASSUMPTION TESTED: [which stated assumption you're challenging]
- FALSIFYING EVIDENCE: [concrete evidence or scenario that disproves it]
- SEVERITY: [Critical/High/Medium — would this break the approach?]
- UNFALSIFIED: [which assumptions survived your analysis]

${principle_text:+Evaluate against these principles:
$principle_text}

Focus on falsification, not preference. An approach with unfalsified assumptions is stronger than one that 'feels better'.
$debate_integrity_rules" 90 "code-reviewer" "grapple")

        if [[ $? -ne 0 || -z "$codex_critique" ]]; then
            echo -e "${RED}❌ Codex critique generation failed${NC}"
            log ERROR "Grapple debate failed: Codex critique empty or error"
            return 1
        fi

        # Gemini falsifies Codex + Sonnet hypotheses
        gemini_critique=$(run_agent_sync "gemini" "
$no_explore_constraint

You are a FALSIFIER using Analysis of Competing Hypotheses (ACH). Your job is to DISPROVE these proposals by testing their stated assumptions.

HYPOTHESIS 1 (from Codex):
$codex_proposal

HYPOTHESIS 2 (from Sonnet 4.6):
$sonnet_proposal

For each hypothesis, attempt to falsify it:
- ASSUMPTION TESTED: [which stated assumption you're challenging]
- FALSIFYING EVIDENCE: [concrete evidence or scenario that disproves it]
- SEVERITY: [Critical/High/Medium — would this break the approach?]
- UNFALSIFIED: [which assumptions survived your analysis]

${principle_text:+Evaluate against these principles:
$principle_text}

Focus on falsification, not preference. An approach with unfalsified assumptions is stronger than one that 'feels better'.
$debate_integrity_rules" 90 "security-auditor" "grapple")

        if [[ $? -ne 0 || -z "$gemini_critique" ]]; then
            echo -e "${RED}❌ Gemini critique generation failed${NC}"
            log ERROR "Grapple debate failed: Gemini critique empty or error"
            return 1
        fi

        # Sonnet falsifies Codex + Gemini hypotheses
        sonnet_critique=$(run_agent_sync "claude-sonnet" "
$no_explore_constraint

You are a FALSIFIER using Analysis of Competing Hypotheses (ACH). Your job is to DISPROVE these proposals by testing their stated assumptions.

HYPOTHESIS 1 (from Codex):
$codex_proposal

HYPOTHESIS 2 (from Gemini):
$gemini_proposal

For each hypothesis, attempt to falsify it:
- ASSUMPTION TESTED: [which stated assumption you're challenging]
- FALSIFYING EVIDENCE: [concrete evidence or scenario that disproves it]
- SEVERITY: [Critical/High/Medium — would this break the approach?]
- UNFALSIFIED: [which assumptions survived your analysis]

${principle_text:+Evaluate against these principles:
$principle_text}

$debate_integrity_rules" 90 "code-reviewer" "grapple")

        if [[ $? -ne 0 || -z "$sonnet_critique" ]]; then
            echo -e "${RED}❌ Sonnet critique generation failed${NC}"
            log ERROR "Grapple debate failed: Sonnet critique empty or error"
            return 1
        fi
    fi

    # ═══════════════════════════════════════════════════════════════════════
    # Rounds 3 to N-1: Rebuttals (v7.13.2)
    # ═══════════════════════════════════════════════════════════════════════
    if [[ $rounds -gt 3 ]]; then
        for ((i=3; i<rounds; i++)); do
            echo ""
            echo -e "${CYAN}[Round $i/$rounds] Rebuttal and refinement...${NC}"
            echo ""

            # Codex defends and refines
            local codex_rebuttal
            codex_rebuttal=$(run_agent_sync "codex" "
$no_explore_constraint

You are DEFENDING your implementation against critiques from Gemini and Sonnet.

YOUR ORIGINAL PROPOSAL:
$codex_proposal

CRITIQUE FROM GEMINI:
$gemini_critique

CRITIQUE FROM SONNET:
$sonnet_critique

Respond to both critiques by:
1. Acknowledging valid points and proposing improvements
2. Defending against unfair or incorrect criticism with evidence
3. Refining your approach based on valid feedback

$debate_integrity_rules
Be specific, technical, and constructive. Focus on improving the solution." 120 "implementer" "grapple")

            if [[ $? -ne 0 || -z "$codex_rebuttal" ]]; then
                echo ""
                echo -e "${RED}❌ Codex rebuttal generation failed${NC}"
                echo -e "   Check logs: ${LOGS_DIR}/"
                log ERROR "Grapple debate failed: Codex rebuttal empty or error (round $i)"
                return 1
            fi

            # Gemini defends and refines
            local gemini_rebuttal
            gemini_rebuttal=$(run_agent_sync "gemini" "
$no_explore_constraint

You are DEFENDING your implementation against critiques from Codex and Sonnet.

YOUR ORIGINAL PROPOSAL:
$gemini_proposal

CRITIQUE FROM CODEX:
$codex_critique

CRITIQUE FROM SONNET:
$sonnet_critique

Respond to both critiques by:
1. Acknowledging valid points and proposing improvements
2. Defending against unfair or incorrect criticism with evidence
3. Refining your approach based on valid feedback

$debate_integrity_rules
Be specific, technical, and constructive. Focus on improving the solution." 120 "researcher" "grapple")

            if [[ $? -ne 0 || -z "$gemini_rebuttal" ]]; then
                echo ""
                echo -e "${RED}❌ Gemini rebuttal generation failed${NC}"
                echo -e "   Check logs: ${LOGS_DIR}/"
                log ERROR "Grapple debate failed: Gemini rebuttal empty or error (round $i)"
                return 1
            fi

            # Sonnet defends and refines
            local sonnet_rebuttal
            sonnet_rebuttal=$(run_agent_sync "claude-sonnet" "
$no_explore_constraint

You are DEFENDING your implementation against critiques from Codex and Gemini.

YOUR ORIGINAL PROPOSAL:
$sonnet_proposal

CRITIQUE FROM CODEX:
$codex_critique

CRITIQUE FROM GEMINI:
$gemini_critique

Respond to both critiques by:
1. Acknowledging valid points and proposing improvements
2. Defending against unfair or incorrect criticism with evidence
3. Refining your approach based on valid feedback

$debate_integrity_rules
Be specific, technical, and constructive. Focus on improving the solution." 120 "researcher" "grapple")

            if [[ $? -ne 0 || -z "$sonnet_rebuttal" ]]; then
                echo ""
                echo -e "${RED}❌ Sonnet rebuttal generation failed${NC}"
                echo -e "   Check logs: ${LOGS_DIR}/"
                log ERROR "Grapple debate failed: Sonnet rebuttal empty or error (round $i)"
                return 1
            fi

            # Append rebuttals to proposals
            codex_proposal="${codex_proposal}

### Rebuttal (Round $i)
${codex_rebuttal}"

            gemini_proposal="${gemini_proposal}

### Rebuttal (Round $i)
${gemini_rebuttal}"

            sonnet_proposal="${sonnet_proposal}

### Rebuttal (Round $i)
${sonnet_rebuttal}"
        done
    fi

    # v8.20.0: Quorum consensus mode — check for 2/3 agreement before synthesis
    local synthesis=""
    if [[ "${OCTOPUS_CONSENSUS:-moderator}" == "quorum" ]]; then
        echo ""
        echo -e "${CYAN}[Quorum Mode] Checking for 2/3 agreement...${NC}"
        local quorum_result
        quorum_result=$(apply_consensus "quorum" "$codex_proposal" "$gemini_proposal" "$sonnet_proposal" "$prompt")
        if [[ -n "$quorum_result" && "$quorum_result" != "MODERATOR_MODE" ]]; then
            synthesis="## Quorum Result (2/3 Agreement)

$quorum_result"
            echo -e "${GREEN}  ✓ Quorum reached — using majority position${NC}"
        else
            echo -e "${YELLOW}  No quorum — falling back to moderator synthesis${NC}"
        fi
    fi

    # ═══════════════════════════════════════════════════════════════════════
    # Final Round: Synthesis (Moderator Mode)
    # ═══════════════════════════════════════════════════════════════════════
    if [[ -z "$synthesis" ]]; then
    echo ""
    echo -e "${CYAN}[Round $rounds/$rounds] Final synthesis...${NC}"
    echo ""

    # v8.31.0: Mode-aware synthesis prompt
    local synthesis_prompt=""
    if [[ "$debate_mode" == "blinded" ]]; then
        synthesis_prompt="$no_explore_constraint

You are the JUDGE synthesizing a $rounds-round BLINDED debate between three AI models.
Each model proposed independently (Round 1) and evaluated independently (Round 2) — no model saw another's work. This prevents anchoring bias but means models may have identified different concerns.

CODEX PROPOSAL:
$codex_proposal

GEMINI PROPOSAL:
$gemini_proposal

SONNET 4.6 PROPOSAL:
$sonnet_proposal

CODEX'S INDEPENDENT EVALUATION:
$codex_critique

GEMINI'S INDEPENDENT EVALUATION:
$gemini_critique

SONNET'S INDEPENDENT EVALUATION:
$sonnet_critique

$debate_integrity_rules

WARNING: Do NOT default to 'all approaches have merit' or 'a hybrid of all three'.
If one approach is clearly superior, say so. If all are flawed, say THAT.
Where models CONVERGE independently, that signal is especially strong (no anchoring).
Where models DIVERGE, that signals genuine uncertainty — surface it honestly.

TASK: Synthesize the independent perspectives. Provide:

## Convergence Analysis
[Where did models independently agree? These are high-confidence findings.]

## Divergence Analysis
[Where did models disagree? What does each model see that others miss?]

## Most Robust Approach
[Which proposal best survives the independent evaluations?]

## Final Recommended Implementation
[The strongest solution, informed by all three independent perspectives]

## Remaining Unknowns
[Concerns raised by only one model — risks to monitor]

## Next Steps
1. [Concrete action item]
2. [Concrete action item]
3. [Concrete action item]

Be specific and actionable. Format as markdown."
    else
        synthesis_prompt="$no_explore_constraint

You are the JUDGE evaluating a $rounds-round ACH (Analysis of Competing Hypotheses) debate between three AI models. Your role is to determine which hypotheses SURVIVED falsification, not which 'feels best'.

CODEX HYPOTHESIS:
$codex_proposal

GEMINI HYPOTHESIS:
$gemini_proposal

SONNET 4.6 HYPOTHESIS:
$sonnet_proposal

CODEX'S FALSIFICATION ATTEMPTS (against Gemini + Sonnet):
$codex_critique

GEMINI'S FALSIFICATION ATTEMPTS (against Codex + Sonnet):
$gemini_critique

SONNET'S FALSIFICATION ATTEMPTS (against Codex + Gemini):
$sonnet_critique

$debate_integrity_rules

WARNING: Do NOT default to 'all approaches have merit' or 'a hybrid of all three'.
If one approach is clearly superior, say so. If all are flawed, say THAT.
Convergent agreement between models may indicate shared blind spots, not correctness.

TASK: Evaluate based on falsification survival. Provide:

## Falsification Results
[For each hypothesis: which assumptions were falsified vs survived. Rate robustness.]

## Most Robust Approach
[Which hypothesis has the most unfalsified assumptions — codex, gemini, sonnet, or hybrid]

## Falsified Elements to Avoid
[Concrete things that were disproven — do NOT include these in the final approach]

## Final Recommended Implementation
[The most robust solution, built from unfalsified elements across all three hypotheses]

## Remaining Unknowns
[Assumptions that were neither proven nor disproven — risks to monitor]

## Next Steps
1. [Concrete action item]
2. [Concrete action item]
3. [Concrete action item]

Be specific and actionable. Format as markdown."
    fi

    synthesis=$(run_agent_sync "claude" "$synthesis_prompt" 150 "synthesizer" "grapple")

    if [[ $? -ne 0 || -z "$synthesis" ]]; then
        echo ""
        echo -e "${RED}❌ Synthesis generation failed${NC}"
        echo -e "   Check logs: ${LOGS_DIR}/"
        log ERROR "Grapple debate failed: Synthesis empty or error"
        return 1
    fi
    fi  # end of: if [[ -z "$synthesis" ]] (quorum may have set it already)

    # ═══════════════════════════════════════════════════════════════════════
    # Save results
    # ═══════════════════════════════════════════════════════════════════════
    local result_file="$RESULTS_DIR/grapple-${task_group}.md"
    cat > "$result_file" << EOF
# Crossfire Review: $prompt

**Generated:** $(date)
**Rounds:** $rounds
**Mode:** $debate_mode
**Principles:** $principles
**Participants:** Codex, Gemini, Sonnet 4.6

---

## Round 1: Proposals

### Codex Proposal
$codex_proposal

### Gemini Proposal
$gemini_proposal

### Sonnet 4.6 Proposal
$sonnet_proposal

---

## Round 2: $(if [[ "$debate_mode" == "blinded" ]]; then echo "Independent Evaluations (Blinded)"; else echo "Cross-Critique"; fi)

### Codex's $(if [[ "$debate_mode" == "blinded" ]]; then echo "Evaluation"; else echo "Critique (of Gemini + Sonnet)"; fi)
$codex_critique

### Gemini's $(if [[ "$debate_mode" == "blinded" ]]; then echo "Evaluation"; else echo "Critique (of Codex + Sonnet)"; fi)
$gemini_critique

### Sonnet's $(if [[ "$debate_mode" == "blinded" ]]; then echo "Evaluation"; else echo "Critique (of Codex + Gemini)"; fi)
$sonnet_critique

---

## Round $rounds: Final Synthesis & Winner
$synthesis
EOF

    # ═══════════════════════════════════════════════════════════════════════
    # Conclusion Ceremony (v7.13.2 - Issue #10)
    # ═══════════════════════════════════════════════════════════════════════
    echo ""
    octopus_complete "Debate"
    echo ""
    echo -e "  ${GREEN}✓${NC} $rounds rounds completed"
    echo -e "  ${GREEN}✓${NC} All three perspectives analyzed"
    echo -e "  ${GREEN}✓${NC} Final synthesis generated"
    echo ""
    echo -e "${CYAN}📊 Debate Summary:${NC}"
    echo -e "  Topic: ${prompt:0:70}..."
    echo -e "  Participants: ${RED}Codex${NC} vs ${YELLOW}Gemini${NC} vs ${BLUE}Sonnet 4.6${NC}"
    echo -e "  Principles: $principles"
    echo ""
    echo -e "${YELLOW}💡 Next Steps:${NC}"
    echo "  1. Review the synthesis above for the recommended approach"
    echo "  2. Check the complete debate transcript: $result_file"
    echo "  3. Implement the winning solution or hybrid approach"
    echo ""
    echo -e "${CYAN}📁 Results:${NC}"
    echo -e "  Full debate: ${CYAN}$result_file${NC}"
    if [[ -n "${CLAUDE_CODE_SESSION:-}" ]]; then
        echo -e "  Session: ${DIM}$CLAUDE_CODE_SESSION${NC}"
    fi
    echo ""

    # v8.18.0: Record debate synthesis decision
    write_structured_decision \
        "debate-synthesis" \
        "grapple_debate" \
        "Debate concluded on: ${prompt:0:80}" \
        "" \
        "high" \
        "3-way debate (Codex vs Gemini vs Sonnet) with $rounds rounds" \
        "" 2>/dev/null || true

    # v8.18.0: Earn skill from debate synthesis
    earn_skill \
        "debate-${prompt:0:30}" \
        "grapple_debate" \
        "Multi-perspective analysis pattern for: ${prompt:0:60}" \
        "When evaluating trade-offs or comparing approaches" \
        "${synthesis:0:100}" 2>/dev/null || true

    # Record usage
    record_agent_call "grapple" "multi-model" "$prompt" "grapple" "debate" "0"
}
