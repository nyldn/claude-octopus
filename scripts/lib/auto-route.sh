#!/usr/bin/env bash
# lib/auto-route.sh — Auto-routing and routing rule matching
# Extracted from orchestrate.sh

match_routing_rule() {
    local task_type="$1"
    local prompt="$2"

    local rules_json
    rules_json=$(load_routing_rules 2>/dev/null) || return 1

    if ! command -v jq &>/dev/null; then
        return 1
    fi

    local rule_count
    rule_count=$(echo "$rules_json" | jq '.rules | length' 2>/dev/null) || return 1

    local prompt_lower
    prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')

    local i=0
    while [[ $i -lt $rule_count ]]; do
        local match_type match_keywords prefer
        match_type=$(echo "$rules_json" | jq -r ".rules[$i].match.task_type // \"\"" 2>/dev/null)
        match_keywords=$(echo "$rules_json" | jq -r ".rules[$i].match.keywords // \"\"" 2>/dev/null)
        prefer=$(echo "$rules_json" | jq -r ".rules[$i].prefer // \"\"" 2>/dev/null)

        local matched=false

        # Match by task_type
        if [[ -n "$match_type" && "$task_type" == "$match_type" ]]; then
            matched=true
        fi

        # Match by keywords (any keyword match)
        if [[ -n "$match_keywords" && "$matched" == "false" ]]; then
            local keyword
            for keyword in $match_keywords; do
                if [[ " ${prompt_lower//$'\n'/ } " == *" $keyword "* ]]; then
                    matched=true
                    break
                fi
            done
        fi

        if [[ "$matched" == "true" && -n "$prefer" ]]; then
            echo "$prefer"
            return 0
        fi

        ((i++)) || true
    done

    return 1
}

_auto_route_wait_for_pids() {
    local max_wait="${1:-${TIMEOUT:-600}}"
    shift || true
    local pids=("$@")
    local wait_start=$SECONDS

    while [[ $((SECONDS - wait_start)) -lt $max_wait ]]; do
        local all_done=true
        local pid
        for pid in "${pids[@]}"; do
            [[ -z "$pid" ]] && continue
            if kill -0 "$pid" 2>/dev/null; then
                all_done=false
                break
            fi
        done
        [[ "$all_done" == "true" ]] && return 0
        sleep 1
    done

    return 1
}

auto_route() {
    local prompt="$1"
    local prompt_lower
    prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')

    local task_type
    task_type=$(classify_task "$prompt")

    # ═══════════════════════════════════════════════════════════════════════════
    # v8.20.0: TRIVIAL TASK FAST PATH
    # ═══════════════════════════════════════════════════════════════════════════
    if [[ "${OCTOPUS_COST_TIER:-balanced}" != "premium" ]] && type detect_trivial_task &>/dev/null 2>&1; then
        local trivial_result
        trivial_result=$(detect_trivial_task "$prompt")
        if [[ "$trivial_result" == "trivial" ]]; then
            handle_trivial_task "$prompt"
            return 0
        fi
    fi

    # ═══════════════════════════════════════════════════════════════════════════
    # COST-AWARE COMPLEXITY ESTIMATION
    # ═══════════════════════════════════════════════════════════════════════════
    local complexity=2
    if [[ -n "$FORCE_TIER" ]]; then
        # User override via -Q/--quick, -P/--premium, or --tier
        case "$FORCE_TIER" in
            trivial) complexity=1 ;;
            standard) complexity=2 ;;
            premium) complexity=3 ;;
        esac
        log DEBUG "Complexity forced to $complexity via --tier flag"
    else
        # Auto-detect complexity from prompt
        complexity=$(estimate_complexity "$prompt")
    fi
    local tier_name
    tier_name=$(get_tier_name "$complexity")

    # v8.20.0: Apply cost-aware agent selection
    if type select_cost_aware_agent &>/dev/null 2>&1; then
        local cost_agent
        cost_agent=$(select_cost_aware_agent "$task_type" "$complexity")
        if [[ "$cost_agent" != "$task_type" && "$cost_agent" != "skip" ]]; then
            log "INFO" "Cost routing: complexity=$complexity, tier=${OCTOPUS_COST_TIER:-balanced}"
        fi
        # v8.20.1: Record cost tier metric
        record_task_metric "cost_tier_used" "${OCTOPUS_COST_TIER:-balanced}" 2>/dev/null || true
    fi

    # ═══════════════════════════════════════════════════════════════════════════
    # CONDITIONAL BRANCHING - Evaluate which tentacle path to extend
    # ═══════════════════════════════════════════════════════════════════════════
    local branch
    branch=$(evaluate_branch_condition "$task_type" "$complexity")
    CURRENT_BRANCH="$branch"  # Store for session recovery
    local branch_display
    branch_display=$(get_branch_display "$branch")

    local context_result
    context_result=$(detect_context "$prompt")
    local context_display
    context_display=$(get_context_display "$context_result")
    local context="${context_result%%:*}"

    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}  Claude Octopus - Smart Routing with Branching${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    # Cynefin domain classification
    local cynefin_domain
    cynefin_domain=$(classify_cynefin "$prompt" "$task_type" "$complexity")

    echo -e "${BLUE}Task Analysis:${NC}"
    echo -e "  Prompt: ${prompt:0:80}..."
    echo -e "  Detected Type: ${GREEN}$task_type${NC}"
    echo -e "  Context: ${YELLOW}$context_display${NC}"
    echo -e "  Complexity: ${CYAN}$tier_name${NC}"
    echo -e "  Domain: ${CYAN}$cynefin_domain${NC}"
    echo -e "  Branch: ${MAGENTA}$branch_display${NC}"

    # v8.18.0: Response mode auto-tuning
    local response_mode
    response_mode=$(detect_response_mode "$prompt" "$task_type")
    echo -e "  Response Mode: ${MAGENTA}${response_mode}${NC}"

    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "  $(get_context_info "$context_result")"
    fi
    echo ""

    # v8.18.0: Response mode short-circuits
    case "$response_mode" in
        direct)
            echo ""
            echo -e "${GREEN}  → Direct mode: Claude handles natively (no external providers)${NC}"
            echo ""
            # Log to provider history
            append_provider_history "claude" "auto-route" "direct mode: ${prompt:0:60}" "Handled natively without external providers" 2>/dev/null || true
            return 0
            ;;
        lightweight)
            echo ""
            echo -e "${CYAN}  → Lightweight mode: single cross-check${NC}"
            echo ""
            local fast_provider
            fast_provider=$(select_fastest_provider "codex" "gemini" 2>/dev/null || echo "codex")
            local cross_check
            cross_check=$(run_agent_sync "$fast_provider" "Quick cross-check on this task. Identify any obvious issues, missing considerations, or better approaches in 3-5 bullet points:

$prompt" 60 "code-reviewer" "auto-route" 2>/dev/null) || true
            if [[ -n "$cross_check" ]]; then
                echo -e "${CYAN}Cross-check (${fast_provider}):${NC}"
                echo "$cross_check" | head -10
                echo ""
            fi
            # Log to provider history
            append_provider_history "$fast_provider" "auto-route" "lightweight cross-check: ${prompt:0:60}" "${cross_check:0:100}" 2>/dev/null || true
            return 0
            ;;
    esac

    # ═══════════════════════════════════════════════════════════════════════════
    # DOUBLE DIAMOND WORKFLOW ROUTING
    # ═══════════════════════════════════════════════════════════════════════════
    case "$task_type" in
        diamond-discover)
            echo -e "${CYAN}${_BOX_TOP}${NC}"
            echo -e "${CYAN}║  🔍 ${context_display} DISCOVER - Parallel Research                ║${NC}"
            echo -e "${CYAN}${_BOX_BOT}${NC}"
            echo "  Routing to discover workflow for multi-perspective research."
            echo ""
            probe_discover "$prompt"
            return
            ;;
        diamond-define)
            echo -e "${CYAN}${_BOX_TOP}${NC}"
            echo -e "${CYAN}║  🤝 ${context_display} DEFINE - Consensus Building                 ║${NC}"
            echo -e "${CYAN}${_BOX_BOT}${NC}"
            echo "  Routing to define workflow for problem definition."
            echo ""
            grasp_define "$prompt"
            return
            ;;
        diamond-develop)
            echo -e "${CYAN}${_BOX_TOP}${NC}"
            echo -e "${CYAN}║  🦑 ${context_display} DEVELOP → DELIVER                           ║${NC}"
            echo -e "${CYAN}${_BOX_BOT}${NC}"
            echo "  Routing to develop then deliver workflow."
            echo ""
            tangle_develop "$prompt" && ink_deliver "$prompt"
            return
            ;;
        diamond-deliver)
            echo -e "${CYAN}${_BOX_TOP}${NC}"
            echo -e "${CYAN}║  ✅ ${context_display} DELIVER - Quality & Validation              ║${NC}"
            echo -e "${CYAN}${_BOX_BOT}${NC}"
            echo "  Routing to deliver workflow for quality gates and validation."
            echo ""
            ink_deliver "$prompt"
            return
            ;;
    esac

    # ═══════════════════════════════════════════════════════════════════════════
    # CROSSFIRE ROUTING (Adversarial Cross-Model Review)
    # Routes to grapple (debate) or squeeze (red team) workflows
    # ═══════════════════════════════════════════════════════════════════════════
    case "$task_type" in
        crossfire-grapple)
            echo -e "${RED}${_BOX_TOP}${NC}"
            echo -e "${RED}║  🤼 GRAPPLE - Adversarial Cross-Model Debate              ║${NC}"
            echo -e "${RED}${_BOX_BOT}${NC}"
            echo "  Routing to grapple workflow: Codex vs Gemini debate."
            echo ""
            grapple_debate "$prompt" "general" "${DEBATE_ROUNDS:-3}"
            return
            ;;
        crossfire-squeeze)
            echo -e "${RED}${_BOX_TOP}${NC}"
            echo -e "${RED}║  🦑 SQUEEZE - Red Team Security Review                    ║${NC}"
            echo -e "${RED}${_BOX_BOT}${NC}"
            echo "  Routing to squeeze workflow: Blue Team vs Red Team."
            echo ""
            squeeze_test "$prompt"
            return
            ;;
    esac

    # ═══════════════════════════════════════════════════════════════════════════
    # KNOWLEDGE WORKER ROUTING (v6.0)
    # Routes to empathize, advise, synthesize workflows
    # ═══════════════════════════════════════════════════════════════════════════
    case "$task_type" in
        knowledge-empathize)
            echo -e "${CYAN}${_BOX_TOP}${NC}"
            echo -e "${CYAN}║  🎯 EMPATHIZE - UX Research Synthesis                     ║${NC}"
            echo -e "${CYAN}${_BOX_BOT}${NC}"
            echo "  🐙 Dispatching UX research across providers..."
            echo ""
            empathize_research "$prompt"
            return
            ;;
        knowledge-advise)
            echo -e "${CYAN}${_BOX_TOP}${NC}"
            echo -e "${CYAN}║  📊 ADVISE - Strategic Consulting                         ║${NC}"
            echo -e "${CYAN}${_BOX_BOT}${NC}"
            echo "  🐙 Running multi-provider strategic analysis..."
            echo ""
            advise_strategy "$prompt"
            return
            ;;
        knowledge-synthesize)
            echo -e "${CYAN}${_BOX_TOP}${NC}"
            echo -e "${CYAN}║  📚 SYNTHESIZE - Research Literature Review               ║${NC}"
            echo -e "${CYAN}${_BOX_BOT}${NC}"
            echo "  🐙 Synthesizing research across providers..."
            echo ""
            synthesize_research "$prompt"
            return
            ;;
    esac

    # ═══════════════════════════════════════════════════════════════════════════
    # OPTIMIZATION ROUTING (v4.2)
    # Routes to specialized agents based on optimization domain
    # ═══════════════════════════════════════════════════════════════════════════
    case "$task_type" in
        optimize-performance)
            echo -e "${CYAN}${_BOX_TOP}${NC}"
            echo -e "${CYAN}║  ⚡ OPTIMIZE - Performance (Speed, Latency, Memory)       ║${NC}"
            echo -e "${CYAN}${_BOX_BOT}${NC}"
            echo "  Routing to performance optimization workflow."
            echo ""
            local perf_prompt="You are a performance engineer. Analyze and optimize: $prompt

Focus on:
- Identify bottlenecks (CPU, memory, I/O, network)
- Profile and measure current performance
- Recommend specific optimizations with expected impact
- Implement fixes with before/after benchmarks"
            spawn_agent "codex" "$perf_prompt"
            return
            ;;
        optimize-cost)
            echo -e "${CYAN}${_BOX_TOP}${NC}"
            echo -e "${CYAN}║  💰 OPTIMIZE - Cost (Cloud Spend, Budget, Rightsizing)    ║${NC}"
            echo -e "${CYAN}${_BOX_BOT}${NC}"
            echo "  Routing to cost optimization workflow."
            echo ""
            local cost_prompt="You are a cloud cost optimization specialist. Analyze and optimize: $prompt

Focus on:
- Identify over-provisioned resources
- Recommend rightsizing (instances, storage, databases)
- Suggest reserved instances or spot instances where applicable
- Estimate savings with specific recommendations"
            spawn_agent "gemini" "$cost_prompt"
            return
            ;;
        optimize-database)
            echo -e "${CYAN}${_BOX_TOP}${NC}"
            echo -e "${CYAN}║  🗃️  OPTIMIZE - Database (Queries, Indexes, Schema)        ║${NC}"
            echo -e "${CYAN}${_BOX_BOT}${NC}"
            echo "  Routing to database optimization workflow."
            echo ""
            local db_prompt="You are a database optimization expert. Analyze and optimize: $prompt

Focus on:
- Identify slow queries using EXPLAIN ANALYZE
- Recommend missing or unused indexes
- Suggest schema optimizations
- Provide query rewrites with performance comparisons"
            spawn_agent "codex" "$db_prompt"
            return
            ;;
        optimize-bundle)
            echo -e "${CYAN}${_BOX_TOP}${NC}"
            echo -e "${CYAN}║  📦 OPTIMIZE - Bundle (Build, Webpack, Code-splitting)    ║${NC}"
            echo -e "${CYAN}${_BOX_BOT}${NC}"
            echo "  Routing to bundle optimization workflow."
            echo ""
            local bundle_prompt="You are a frontend build optimization specialist. Analyze and optimize: $prompt

Focus on:
- Analyze bundle size and composition
- Implement tree-shaking and dead code elimination
- Set up code-splitting and lazy loading
- Configure optimal minification and compression"
            spawn_agent "codex" "$bundle_prompt"
            return
            ;;
        optimize-accessibility)
            echo -e "${CYAN}${_BOX_TOP}${NC}"
            echo -e "${CYAN}║  ♿ OPTIMIZE - Accessibility (WCAG, A11y, Screen Readers) ║${NC}"
            echo -e "${CYAN}${_BOX_BOT}${NC}"
            echo "  Routing to accessibility optimization workflow."
            echo ""
            local a11y_prompt="You are an accessibility specialist. Audit and optimize: $prompt

Focus on:
- WCAG 2.1 AA compliance checklist
- Screen reader compatibility
- Keyboard navigation and focus management
- Color contrast and visual accessibility
- ARIA attributes and semantic HTML"
            spawn_agent "gemini" "$a11y_prompt"
            return
            ;;
        optimize-seo)
            echo -e "${CYAN}${_BOX_TOP}${NC}"
            echo -e "${CYAN}║  🔍 OPTIMIZE - SEO (Search Engine, Meta Tags, Schema)     ║${NC}"
            echo -e "${CYAN}${_BOX_BOT}${NC}"
            echo "  Routing to SEO optimization workflow."
            echo ""
            local seo_prompt="You are an SEO specialist. Audit and optimize: $prompt

Focus on:
- Meta tags (title, description, OG tags)
- Structured data (JSON-LD, Schema.org)
- Semantic HTML and heading hierarchy
- Internal linking structure
- Sitemap and robots.txt configuration
- Core Web Vitals impact"
            spawn_agent "gemini" "$seo_prompt"
            return
            ;;
        optimize-image)
            echo -e "${CYAN}${_BOX_TOP}${NC}"
            echo -e "${CYAN}║  🖼️  OPTIMIZE - Images (Compression, Format, Lazy Load)    ║${NC}"
            echo -e "${CYAN}${_BOX_BOT}${NC}"
            echo "  Routing to image optimization workflow."
            echo ""
            local img_prompt="You are an image optimization specialist. Analyze and optimize: $prompt

Focus on:
- Format recommendations (WebP, AVIF for modern browsers)
- Compression settings per image type
- Responsive images with srcset
- Lazy loading implementation
- CDN and caching strategies"
            spawn_agent "gemini" "$img_prompt"
            return
            ;;
        optimize-audit)
            echo -e "${CYAN}${_BOX_TOP}${NC}"
            echo -e "${CYAN}║  🔬 OPTIMIZE - Full Site Audit (Multi-Domain)             ║${NC}"
            echo -e "${CYAN}${_BOX_BOT}${NC}"
            echo ""
            echo -e "  ${YELLOW}Running comprehensive audit across all optimization domains...${NC}"
            echo -e "  Domains: ⚡ Performance │ ♿ Accessibility │ 🔍 SEO │ 🖼️ Images │ 📦 Bundle │ 🗃️ Database"
            echo ""

            # Define the domains to audit
            local domains=("performance" "accessibility" "seo" "images" "bundle")

            # Dry-run mode: show plan and exit
            if [[ "$DRY_RUN" == "true" ]]; then
                echo -e "  ${CYAN}[DRY-RUN] Full Site Audit Plan:${NC}"
                echo -e "    Phase 1: Parallel domain audits (${#domains[@]} agents)"
                for domain in "${domains[@]}"; do
                    echo -e "      ├─ $domain audit via gemini-fast"
                done
                echo -e "    Phase 2: Synthesize results via gemini"
                echo -e "    Phase 3: Generate unified report"
                echo ""
                echo -e "  ${YELLOW}Domains:${NC} ${domains[*]}"
                echo -e "  ${YELLOW}Output:${NC} \$WORKSPACE/results/full-audit-*.md"
                return
            fi

            # Create temp directory for audit results
            local audit_dir
            audit_dir="${WORKSPACE:-$HOME/.claude-octopus}/results/audit-$(date +%Y%m%d-%H%M%S)"
            mkdir -p "$audit_dir"
            local audit_group
            audit_group=$(date +%s)
            local pids=()
            local domain_files=()
            local agent_result_files=()

            # Phase 1: Parallel domain analysis
            echo -e "  ${CYAN}Phase 1/3: Parallel Domain Analysis${NC}"
            for domain in "${domains[@]}"; do
                local domain_prompt
                local domain_file="$audit_dir/$domain.md"
                local agent_type="gemini-fast"
                local task_id="audit-${domain}-${audit_group}"
                local agent_result_file="${RESULTS_DIR}/${agent_type}-${task_id}.md"
                domain_files+=("$domain_file")
                agent_result_files+=("$agent_result_file")

                case "$domain" in
                    performance)
                        domain_prompt="You are a performance optimization specialist. Analyze for performance issues:
$prompt

Focus on: load times, Core Web Vitals (LCP, FID, CLS), JavaScript execution, render blocking, caching.
Output a structured report with findings and recommendations." ;;
                    accessibility)
                        domain_prompt="You are an accessibility (a11y) specialist. Audit for accessibility issues:
$prompt

Focus on: WCAG 2.1 AA compliance, screen reader compatibility, keyboard navigation, color contrast, ARIA usage.
Output a structured report with findings and recommendations." ;;
                    seo)
                        domain_prompt="You are an SEO specialist. Audit for search optimization issues:
$prompt

Focus on: meta tags, structured data (JSON-LD), heading hierarchy, URL structure, mobile-friendliness, Core Web Vitals.
Output a structured report with findings and recommendations." ;;
                    images)
                        domain_prompt="You are an image optimization specialist. Audit for image optimization issues:
$prompt

Focus on: format usage (WebP/AVIF), compression, responsive images (srcset), lazy loading, alt text.
Output a structured report with findings and recommendations." ;;
                    bundle)
                        domain_prompt="You are a frontend build specialist. Audit for bundle optimization issues:
$prompt

Focus on: bundle size, code splitting, tree shaking, unused dependencies, compression (gzip/brotli).
Output a structured report with findings and recommendations." ;;
                esac

                echo -e "    ├─ Starting ${domain} audit..."
                local pid=""
                if pid=$(spawn_agent_capture_pid "$agent_type" "$domain_prompt" "$task_id" "auditor" "optimize-audit"); then
                    pids+=("$pid")
                else
                    pids+=("")
                    echo -e "      ${RED}✗${NC} ${domain} audit failed to spawn"
                fi
            done

            # Wait for all audits to complete
            echo -e "    └─ Waiting for ${#pids[@]} audits to complete..."
            local failed=0
            if ! _auto_route_wait_for_pids "${TIMEOUT:-600}" "${pids[@]}"; then
                echo -e "      ${YELLOW}!${NC} One or more domain audits reached the timeout; collecting available results"
            fi
            for i in "${!pids[@]}"; do
                local domain="${domains[$i]}"
                local domain_file="${domain_files[$i]}"
                local agent_result_file="${agent_result_files[$i]}"
                local pid="${pids[$i]:-}"
                if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                    ((failed++)) || true
                    echo -e "      ${RED}✗${NC} ${domain} audit timed out"
                elif [[ -f "$agent_result_file" ]]; then
                    cp "$agent_result_file" "$domain_file"
                    if grep -q '^## Status: FAILED' "$agent_result_file" 2>/dev/null; then
                        ((failed++)) || true
                        echo -e "      ${RED}✗${NC} ${domain} audit failed"
                    else
                        echo -e "      ${GREEN}✓${NC} ${domain} audit complete"
                    fi
                else
                    ((failed++)) || true
                    echo -e "      ${RED}✗${NC} ${domain} audit produced no result"
                fi
            done
            echo ""

            # Phase 2: Synthesize results
            echo -e "  ${CYAN}Phase 2/3: Synthesizing Results${NC}"
            local synthesis_input=""
            for i in "${!domains[@]}"; do
                local domain="${domains[$i]}"
                local domain_file="${domain_files[$i]}"
                if [[ -f "$domain_file" ]]; then
                    synthesis_input+="
## $(echo "$domain" | tr '[:lower:]' '[:upper:]') AUDIT RESULTS
$(<"$domain_file")

---
"
                fi
            done

            local synthesis_prompt="You are a senior web optimization consultant. Synthesize these multi-domain audit results into a comprehensive report:

$synthesis_input

Create a unified report with:
1. **Executive Summary** - Top 5 most impactful issues across all domains
2. **Priority Matrix** - Issues ranked by impact (High/Medium/Low) and effort
3. **Domain Summaries** - Key findings per domain (2-3 bullets each)
4. **Action Plan** - Recommended order of fixes with rationale
5. **Quick Wins** - Issues that can be fixed immediately with high ROI

Format as markdown. Be specific and actionable."

            local synthesis_file="$audit_dir/synthesis.md"
            local synthesis_task_id="audit-synthesis-${audit_group}"
            local synthesis_result_file="${RESULTS_DIR}/gemini-${synthesis_task_id}.md"
            local synthesis_pid=""
            if synthesis_pid=$(spawn_agent_capture_pid "gemini" "$synthesis_prompt" "$synthesis_task_id" "synthesizer" "optimize-audit"); then
                if ! _auto_route_wait_for_pids "${TIMEOUT:-600}" "$synthesis_pid"; then
                    echo "Synthesis timed out; detailed domain reports are still included below." > "$synthesis_file"
                elif [[ -f "$synthesis_result_file" ]]; then
                    cp "$synthesis_result_file" "$synthesis_file"
                else
                    echo "Synthesis produced no result; detailed domain reports are still included below." > "$synthesis_file"
                fi
            else
                echo "Synthesis failed to spawn; detailed domain reports are still included below." > "$synthesis_file"
            fi
            echo ""

            # Phase 3: Generate final report
            echo -e "  ${CYAN}Phase 3/3: Generating Final Report${NC}"
            local final_report="${WORKSPACE:-$HOME/.claude-octopus}/results/full-audit-$(date +%Y%m%d-%H%M%S).md"
            {
                echo "# Full Site Optimization Audit"
                echo ""
                echo "_Generated: $(date)_"
                echo "_Domains Audited: ${domains[*]}_"
                echo ""
                echo "---"
                echo ""
                if [[ -f "$synthesis_file" ]]; then
                    cat "$synthesis_file"
                fi
                echo ""
                echo "---"
                echo ""
                echo "# Detailed Domain Reports"
                echo ""
                for i in "${!domains[@]}"; do
                    local domain="${domains[$i]}"
                    local domain_file="${domain_files[$i]}"
                    echo "## $(_ucfirst "$domain") Audit"
                    echo ""
                    if [[ -f "$domain_file" ]]; then
                        cat "$domain_file"
                    else
                        echo "_No results available_"
                    fi
                    echo ""
                    echo "---"
                    echo ""
                done
            } > "$final_report"

            octopus_complete "Full audit"
            echo -e "  ${CYAN}Report:${NC} $final_report"
            echo ""

            # Display synthesis if available
            if [[ -f "$synthesis_file" ]]; then
                echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
                echo -e "${CYAN}                    AUDIT SYNTHESIS                        ${NC}"
                echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
                cat "$synthesis_file"
            fi
            return
            ;;
        optimize-general)
            echo -e "${CYAN}${_BOX_TOP}${NC}"
            echo -e "${CYAN}║  🔧 OPTIMIZE - General Analysis                           ║${NC}"
            echo -e "${CYAN}${_BOX_BOT}${NC}"
            echo "  Auto-detecting optimization domain..."
            echo ""
            # Run analysis to determine best optimization approach
            local analysis_prompt="Analyze this optimization request and identify the specific domain(s):

$prompt

Domains to consider: performance, cost, database, bundle/build, accessibility, SEO, images.
Then provide specific optimization recommendations."
            spawn_agent "gemini" "$analysis_prompt"
            return
            ;;
    esac

    # ═══════════════════════════════════════════════════════════════════════════
    # KNOWLEDGE WORK MODE - Suggest knowledge workflows for ambiguous tasks
    # When enabled, offers knowledge workflow options for research-like tasks
    # ═══════════════════════════════════════════════════════════════════════════
    load_user_config 2>/dev/null || true
    if [[ "$KNOWLEDGE_WORK_MODE" == "true" && "$task_type" =~ ^(research|general|coding)$ ]]; then
        echo -e "${MAGENTA}${_BOX_TOP}${NC}"
        echo -e "${MAGENTA}║  🐙 Knowledge Work Mode Active                            ║${NC}"
        echo -e "${MAGENTA}${_BOX_BOT}${NC}"
        echo ""
        echo -e "  Your task could benefit from a knowledge workflow:"
        echo ""
        echo -e "    ${GREEN}[E]${NC} empathize  - UX research synthesis (personas, journey maps)"
        echo -e "    ${GREEN}[A]${NC} advise     - Strategic consulting (market analysis, frameworks)"
        echo -e "    ${GREEN}[S]${NC} synthesize - Literature review (research synthesis, gaps)"
        echo -e "    ${GREEN}[D]${NC} default    - Continue with standard routing"
        echo ""
        
        if [[ -t 0 && -z "$CI" ]]; then
            read -p "  Choose workflow [E/A/S/D]: " -n 1 -r kw_choice
            echo ""
            case "$kw_choice" in
                [Ee])
                    echo -e "  ${GREEN}✓${NC} Routing to empathize workflow..."
                    empathize_research "$prompt"
                    return
                    ;;
                [Aa])
                    echo -e "  ${GREEN}✓${NC} Routing to advise workflow..."
                    advise_strategy "$prompt"
                    return
                    ;;
                [Ss])
                    echo -e "  ${GREEN}✓${NC} Routing to synthesize workflow..."
                    synthesize_research "$prompt"
                    return
                    ;;
                *)
                    echo -e "  ${CYAN}→${NC} Continuing with standard routing..."
                    echo ""
                    ;;
            esac
        fi
    fi

    # ═══════════════════════════════════════════════════════════════════════════
    # STANDARD SINGLE-AGENT ROUTING (with cost-aware tier selection)
    # Branch override: premium=3, standard=2, fast=1
    # ═══════════════════════════════════════════════════════════════════════════
    local agent_complexity="$complexity"
    if [[ -n "$FORCE_BRANCH" ]]; then
        case "$FORCE_BRANCH" in
            premium) agent_complexity=3 ;;
            standard) agent_complexity=2 ;;
            fast) agent_complexity=1 ;;
        esac
    fi
    local agent
    agent=$(get_tiered_agent "$task_type" "$agent_complexity")
    local model_name
    model_name=$(get_agent_command "$agent" | awk '{print $NF}')
    echo -e "  Selected Agent: ${GREEN}$agent${NC} → ${CYAN}$model_name${NC}"
    echo ""

    case "$task_type" in
        image)
            echo -e "${YELLOW}Image Generation Task${NC}"
            echo "  Using gemini-3-pro-image-preview for text-to-image generation."
            echo "  Supports: text-to-image, image editing, multi-turn editing"
            echo "  Output: Up to 4K resolution images"
            echo ""

            # v3.0: Nano banana prompt refinement for better image results
            local image_type
            image_type=$(detect_image_type "$prompt_lower")
            echo -e "${CYAN}Detected image type: $image_type${NC}"
            echo -e "${CYAN}Applying nano banana prompt refinement...${NC}"
            echo ""

            local refined_prompt
            refined_prompt=$(refine_image_prompt "$prompt" "$image_type")

            echo -e "${GREEN}Refined prompt:${NC}"
            echo "  ${refined_prompt:0:200}..."
            echo ""

            log INFO "Routing refined prompt to $agent agent"
            spawn_agent "$agent" "$refined_prompt"
            return
            ;;
        review)
            echo -e "${YELLOW}Code Review Task${NC}"
            echo "  Using $model_name for thorough code analysis."
            echo "  Focus: Security, performance, best practices, bugs"
            ;;
        coding)
            echo -e "${YELLOW}Coding/Implementation Task${NC}"
            case "$complexity" in
                1) echo "  Using $model_name (mini) for quick fixes and simple tasks." ;;
                2) echo "  Using $model_name (standard) for general coding tasks." ;;
                3) echo "  Using $model_name (premium) for complex code generation." ;;
            esac
            ;;
        design)
            echo -e "${YELLOW}Design/UI/UX Task${NC}"
            echo "  Using $model_name for design reasoning and analysis."
            echo "  Strong at: Component patterns, accessibility, design systems"
            ;;
        copywriting)
            echo -e "${YELLOW}Copywriting Task${NC}"
            echo "  Using $model_name for creative content generation."
            echo "  Strong at: Marketing copy, tone adaptation, messaging"
            ;;
        research)
            echo -e "${YELLOW}Research/Analysis Task${NC}"
            echo "  Using $model_name for deep analysis and synthesis."
            ;;
        *)
            echo -e "${YELLOW}General Task${NC}"
            case "$complexity" in
                1) echo "  Using $model_name (mini) - detected as simple task." ;;
                2) echo "  Using $model_name (standard) for general tasks." ;;
                3) echo "  Using $model_name (premium) - detected as complex task." ;;
            esac
            ;;
    esac
    echo ""

    log INFO "Routing to $agent agent (task: $task_type, tier: $tier_name)"

    spawn_agent "$agent" "$prompt"
}
