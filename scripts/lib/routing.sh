#!/usr/bin/env bash
# Claude Octopus - Task Routing Library (v8.21.0)
# Provides: task classification, complexity estimation, persona recommendation, role mapping
#
# Sourced by orchestrate.sh. Extracted from orchestrate.sh to reduce monolith size.

# Source guard — prevent double-loading
[[ -n "${_ROUTING_LOADED:-}" ]] && return 0
_ROUTING_LOADED=1

# ═══════════════════════════════════════════════════════════════════════════════
# TASK CLASSIFICATION
# ═══════════════════════════════════════════════════════════════════════════════

# Classify task intent from prompt text
# Returns one of: image, crossfire-squeeze, crossfire-grapple, knowledge-empathize,
#   knowledge-advise, knowledge-synthesize, diamond-discover, diamond-define,
#   diamond-develop, diamond-deliver, optimize-*, review, copywriting, design,
#   research, coding, general
# Usage: classify_task <prompt>
classify_task() {
    local prompt="$1"
    local prompt_lower
    prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')

    # ═══════════════════════════════════════════════════════════════════════════
    # IMAGE GENERATION (highest priority - checked before Double Diamond)
    # v3.0: Enhanced to detect app icons, favicons, diagrams, social media banners
    # ═══════════════════════════════════════════════════════════════════════════
    if [[ "$prompt_lower" =~ (generate|create|make|draw|render).*(image|picture|photo|illustration|graphic|icon|logo|banner|visual|artwork|favicon|avatar) ]] || \
       [[ "$prompt_lower" =~ (image|picture|photo|illustration|graphic|icon|logo|banner|favicon|avatar).*generat ]] || \
       [[ "$prompt_lower" =~ (visualize|depict|illustrate|sketch) ]] || \
       [[ "$prompt_lower" =~ (dall-?e|midjourney|stable.?diffusion|imagen|text.?to.?image) ]] || \
       [[ "$prompt_lower" =~ (app.?icon|favicon|og.?image|social.?media.?(banner|image|graphic)) ]] || \
       [[ "$prompt_lower" =~ (hero.?image|header.?image|cover.?image|thumbnail) ]] || \
       [[ "$prompt_lower" =~ (diagram|flowchart|architecture.?diagram|sequence.?diagram|infographic) ]] || \
       [[ "$prompt_lower" =~ (twitter|linkedin|facebook|instagram).*(image|graphic|banner|post) ]] || \
       [[ "$prompt_lower" =~ (marketing|promotional).*(image|graphic|visual) ]]; then
        echo "image"
        return
    fi

    # ═══════════════════════════════════════════════════════════════════════════
    # CROSSFIRE INTENT DETECTION (Adversarial Cross-Model Review)
    # Routes to grapple (debate) or squeeze (red team) workflows
    # ═══════════════════════════════════════════════════════════════════════════

    # Squeeze (Red Team): security audit, penetration test, vulnerability review
    if [[ "$prompt_lower" =~ (security|penetration|pen).*(audit|test|review) ]] || \
       [[ "$prompt_lower" =~ red.?team ]] || \
       [[ "$prompt_lower" =~ (pentest|vulnerability|vuln).*(review|test|audit|assess) ]] || \
       [[ "$prompt_lower" =~ (find|check|scan).*(vulnerabilities|security.?issues|exploits) ]] || \
       [[ "$prompt_lower" =~ squeeze ]] || \
       [[ "$prompt_lower" =~ (attack|exploit|hack).*(surface|vector|test) ]]; then
        echo "crossfire-squeeze"
        return
    fi

    # Grapple (Debate): adversarial review, cross-model debate, both models
    if [[ "$prompt_lower" =~ (adversarial|cross.?model).*(review|debate|critique) ]] || \
       [[ "$prompt_lower" =~ debate.*(architecture|design|implementation|approach|solution) ]] || \
       [[ "$prompt_lower" =~ (debate|grapple|wrestle|compare).*(models?|approaches?|solutions?) ]] || \
       [[ "$prompt_lower" =~ (both|multiple).*(models?|ai|llm).*(review|compare|debate) ]] || \
       [[ "$prompt_lower" =~ (codex|gemini).*(vs|versus|debate|compare) ]] || \
       [[ "$prompt_lower" =~ grapple ]]; then
        echo "crossfire-grapple"
        return
    fi

    # ═══════════════════════════════════════════════════════════════════════════
    # KNOWLEDGE WORKER INTENT DETECTION (v6.0)
    # Routes to empathize, advise, synthesize workflows
    # ═══════════════════════════════════════════════════════════════════════════

    # Empathize: UX research, user research, journey mapping, personas
    if [[ "$prompt_lower" =~ (user|ux).*(research|interview|synthesis|finding) ]] || \
       [[ "$prompt_lower" =~ (journey|experience).*(map|mapping) ]] || \
       [[ "$prompt_lower" =~ (persona|user.?profile|archetype) ]] || \
       [[ "$prompt_lower" =~ (usability|heuristic).*(evaluation|audit|review|test|analysis|result) ]] || \
       [[ "$prompt_lower" =~ (analyze|analyse).*(usability|ux).*(test|result) ]] || \
       [[ "$prompt_lower" =~ (pain.?point|user.?need|empathize|empathy) ]] || \
       [[ "$prompt_lower" =~ affinity.?(map|diagram|cluster) ]]; then
        echo "knowledge-empathize"
        return
    fi

    # Advise: strategy, consulting, business case, market analysis
    if [[ "$prompt_lower" =~ (market|competitive).*(analysis|intelligence|landscape) ]] || \
       [[ "$prompt_lower" =~ (business|investment).*(case|proposal|rationale) ]] || \
       [[ "$prompt_lower" =~ (strategic|strategy).*(recommendation|option|analysis) ]] || \
       [[ "$prompt_lower" =~ (swot|porter|pestle|bcg|ansoff) ]] || \
       [[ "$prompt_lower" =~ (go.?to.?market|gtm|market.?entry) ]] || \
       [[ "$prompt_lower" =~ (stakeholder|executive).*(analysis|presentation|summary) ]] || \
       [[ "$prompt_lower" =~ advise ]]; then
        echo "knowledge-advise"
        return
    fi

    # Synthesize: literature review, research synthesis, academic
    if [[ "$prompt_lower" =~ (literature|lit).*(review|synthesis|survey) ]] || \
       [[ "$prompt_lower" =~ (research|academic).*(synthesis|summary|review) ]] || \
       [[ "$prompt_lower" =~ (systematic|scoping|narrative).*(review) ]] || \
       [[ "$prompt_lower" =~ (annotated.?bibliography|citation.?analysis) ]] || \
       [[ "$prompt_lower" =~ (research.?gap|knowledge.?gap|state.?of.?the.?art) ]] || \
       [[ "$prompt_lower" =~ (thematic|meta).*(analysis|synthesis) ]] || \
       [[ "$prompt_lower" =~ synthesize ]]; then
        echo "knowledge-synthesize"
        return
    fi

    # ═══════════════════════════════════════════════════════════════════════════
    # DOUBLE DIAMOND INTENT DETECTION
    # Routes to full workflow phases, not just single agents
    # ═══════════════════════════════════════════════════════════════════════════

    # Discover phase: research, explore, investigate
    if [[ "$prompt_lower" =~ ^(research|explore|investigate|study|discover)[[:space:]] ]] || \
       [[ "$prompt_lower" =~ (research|explore|investigate).*(option|approach|pattern|practice|alternative) ]]; then
        echo "diamond-discover"
        return
    fi

    # Define phase: define, clarify, scope, requirements
    if [[ "$prompt_lower" =~ ^(define|clarify|scope|specify)[[:space:]] ]] || \
       [[ "$prompt_lower" =~ (define|clarify).*(requirements|scope|problem|approach|boundaries) ]] || \
       [[ "$prompt_lower" =~ (what|which).*(requirements|approach|constraints) ]]; then
        echo "diamond-define"
        return
    fi

    # Develop+Deliver phase: build, develop, implement, create
    if [[ "$prompt_lower" =~ ^(develop|dev|build|implement|construct)[[:space:]] ]] || \
       [[ "$prompt_lower" =~ (build|develop|implement).*(feature|system|module|component|service) ]]; then
        echo "diamond-develop"
        return
    fi

    # Deliver phase: QA, test, review, validate
    # NOTE: Exclude "audit" when followed by site/website/app to allow optimize-audit routing
    if [[ "$prompt_lower" =~ ^(qa|test|review|validate|verify|check)[[:space:]] ]] || \
       [[ "$prompt_lower" =~ ^audit[[:space:]] && ! "$prompt_lower" =~ audit.*(site|website|app|application) ]] || \
       [[ "$prompt_lower" =~ (qa|test|review|validate).*(implementation|code|changes|feature) ]]; then
        echo "diamond-deliver"
        return
    fi

    # ═══════════════════════════════════════════════════════════════════════════
    # OPTIMIZATION INTENT DETECTION (v4.2)
    # Routes to specialized optimization workflows based on domain
    # NOTE: Order matters! More specific patterns (database, bundle) come before
    #       generic patterns (performance) to ensure correct routing.
    # ═══════════════════════════════════════════════════════════════════════════

    # Multi-domain / Full site audit: comprehensive optimization across all domains
    # CHECK FIRST - before individual domain patterns
    if [[ "$prompt_lower" =~ (full|complete|comprehensive|entire|whole).*(audit|optimization|optimize|review) ]] || \
       [[ "$prompt_lower" =~ (site|website|app|application).*(audit|optimization) ]] || \
       [[ "$prompt_lower" =~ (audit|optimize|optimise).*(site|website|app|application|everything) ]] || \
       [[ "$prompt_lower" =~ audit.*(my|the|this).*(site|website|app|application) ]] || \
       [[ "$prompt_lower" =~ (optimize|optimise).*(everything|all|across.?the.?board) ]] || \
       [[ "$prompt_lower" =~ (lighthouse|pagespeed|web.?vitals).*(full|complete|audit) ]] || \
       [[ "$prompt_lower" =~ multi.?(domain|area|aspect).*(optimization|audit) ]]; then
        echo "optimize-audit"
        return
    fi

    # Database optimization: query, index, SQL, slow queries (CHECK BEFORE PERFORMANCE)
    if [[ "$prompt_lower" =~ (optimize|optimise).*(database|query|sql|index|postgres|mysql) ]] || \
       [[ "$prompt_lower" =~ (database|query|sql).*(optimize|slow|improve|tune) ]] || \
       [[ "$prompt_lower" =~ (slow.?quer|explain.?analyze|index.?scan|full.?scan) ]] || \
       [[ "$prompt_lower" =~ slow.*(database|query|sql) ]]; then
        echo "optimize-database"
        return
    fi

    # Cost optimization: budget, savings, cloud spend, reduce cost
    if [[ "$prompt_lower" =~ (optimize|optimise|reduce).*(cost|budget|spend|bill|price) ]] || \
       [[ "$prompt_lower" =~ (cost|budget|spending).*(optimize|reduce|cut|lower) ]] || \
       [[ "$prompt_lower" =~ (save.?money|cheaper|rightsiz|reserved|spot.?instance) ]]; then
        echo "optimize-cost"
        return
    fi

    # Performance optimization: speed, latency, throughput, memory
    # Note: Generic "slow" patterns moved here after database to avoid false matches
    if [[ "$prompt_lower" =~ (optimize|optimise).*(performance|speed|latency|throughput|p99|cpu|memory) ]] || \
       [[ "$prompt_lower" =~ (performance|speed|latency).*(optimize|improve|fix|slow) ]] || \
       [[ "$prompt_lower" =~ (slow|sluggish|takes.?too.?long|bottleneck) ]]; then
        echo "optimize-performance"
        return
    fi

    # Bundle/build optimization: webpack, tree-shake, code-split
    if [[ "$prompt_lower" =~ (optimize|optimise).*(bundle|build|webpack|vite|rollup) ]] || \
       [[ "$prompt_lower" =~ (bundle|build).*(optimize|size|slow|faster) ]] || \
       [[ "$prompt_lower" =~ (tree.?shak|code.?split|chunk|minif) ]]; then
        echo "optimize-bundle"
        return
    fi

    # Accessibility optimization: a11y, WCAG, screen reader
    if [[ "$prompt_lower" =~ (optimize|optimise|improve).*(accessibility|a11y|wcag) ]] || \
       [[ "$prompt_lower" =~ (accessibility|a11y).*(optimize|improve|fix|audit) ]] || \
       [[ "$prompt_lower" =~ (screen.?reader|aria|contrast|keyboard.?nav) ]]; then
        echo "optimize-accessibility"
        return
    fi

    # SEO optimization: search engine, meta tags, structured data
    if [[ "$prompt_lower" =~ (optimize|optimise|improve).*(seo|search.?engine|ranking) ]] || \
       [[ "$prompt_lower" =~ (seo|search.?engine).*(optimize|improve|fix|audit) ]] || \
       [[ "$prompt_lower" =~ (meta.?tag|structured.?data|schema.?org|sitemap|robots\.txt) ]]; then
        echo "optimize-seo"
        return
    fi

    # Image optimization: compress, format, lazy load, WebP
    if [[ "$prompt_lower" =~ (optimize|optimise|compress).*(image|photo|graphic|png|jpg|jpeg) ]] || \
       [[ "$prompt_lower" =~ (image|photo).*(optimize|compress|reduce|smaller) ]] || \
       [[ "$prompt_lower" =~ (webp|avif|lazy.?load|srcset|responsive.?image) ]]; then
        echo "optimize-image"
        return
    fi

    # Generic optimize (fallback)
    if [[ "$prompt_lower" =~ ^(optimize|optimise)[[:space:]] ]]; then
        echo "optimize-general"
        return
    fi

    # ═══════════════════════════════════════════════════════════════════════════
    # STANDARD TASK CLASSIFICATION (for single-agent routing)
    # ═══════════════════════════════════════════════════════════════════════════

    # Code review keywords (check before coding - more specific)
    if [[ "$prompt_lower" =~ (review|audit).*(code|commit|pr|pull.?request|module|component|implementation|function|authentication) ]] || \
       [[ "$prompt_lower" =~ (code|security|performance).*(review|audit) ]] || \
       [[ "$prompt_lower" =~ review.*(for|the).*(security|vulnerability|issue|bug|problem) ]] || \
       [[ "$prompt_lower" =~ (find|spot|identify|check).*(bug|issue|problem|vulnerability|vulnerabilities) ]]; then
        echo "review"
        return
    fi

    # Copywriting/content keywords (check before coding - "write" overlap)
    if [[ "$prompt_lower" =~ (write|draft|compose|edit).*(copy|content|text|message|email|blog|article|marketing) ]] || \
       [[ "$prompt_lower" =~ (marketing|advertising|promotional).*(copy|content|text) ]] || \
       [[ "$prompt_lower" =~ (headline|tagline|slogan|cta|call.?to.?action) ]] || \
       [[ "$prompt_lower" =~ (tone|voice|brand.?messaging|marketing.?copy) ]] || \
       [[ "$prompt_lower" =~ (rewrite|rephrase|improve.?the.?wording) ]]; then
        echo "copywriting"
        return
    fi

    # Design/UI/UX keywords (check before coding - accessibility is design)
    if [[ "$prompt_lower" =~ (accessibility|a11y|wcag|contrast|color.?scheme) ]] || \
       [[ "$prompt_lower" =~ (ui|ux|interface|layout|wireframe|prototype|mockup) ]] || \
       [[ "$prompt_lower" =~ (design.?system|component.?library|style.?guide|theme) ]] || \
       [[ "$prompt_lower" =~ (responsive|mobile|tablet|breakpoint) ]] || \
       [[ "$prompt_lower" =~ (tailwind|shadcn|radix|styled) ]]; then
        echo "design"
        return
    fi

    # Research/analysis keywords (check before coding - "analyze" overlap)
    if [[ "$prompt_lower" =~ (research|investigate|explore|study|compare) ]] || \
       [[ "$prompt_lower" =~ (what|why|how|explain|understand|summarize|overview) ]] || \
       [[ "$prompt_lower" =~ (documentation|docs|readme|architecture|structure) ]] || \
       [[ "$prompt_lower" =~ analyze.*(codebase|architecture|project|structure|pattern) ]] || \
       [[ "$prompt_lower" =~ (best.?practice|pattern|approach|strategy|recommendation) ]]; then
        echo "research"
        return
    fi

    # Coding/implementation keywords
    if [[ "$prompt_lower" =~ (implement|develop|program|build|fix|debug|refactor) ]] || \
       [[ "$prompt_lower" =~ (create|write|add).*(function|class|component|module|api|endpoint|hook) ]] || \
       [[ "$prompt_lower" =~ (function|class|module|api|endpoint|route|service) ]] || \
       [[ "$prompt_lower" =~ (typescript|javascript|python|react|next\.?js|node|sql|html|css) ]] || \
       [[ "$prompt_lower" =~ (error|bug|test|compile|lint|type.?check) ]] || \
       [[ "$prompt_lower" =~ (add|remove|update|delete|modify).*(feature|method|handler) ]]; then
        echo "coding"
        return
    fi

    # Default to general
    echo "general"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PERSONA AGENT RECOMMENDATION (v5.0)
# Suggests specialized persona agents based on prompt keyword analysis
# Returns: agent name or empty string if no strong match
# ═══════════════════════════════════════════════════════════════════════════════

recommend_persona_agent() {
    local prompt="$1"
    local prompt_lower
    prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')
    local recommendations=""
    local confidence=0

    # Backend/API patterns -> backend-architect
    if [[ "$prompt_lower" =~ (api|endpoint|microservice|rest|graphql|grpc|event.?driven|kafka|rabbitmq) ]]; then
        recommendations="${recommendations}backend-architect "
        ((confidence += 30))
    fi

    # Security patterns -> security-auditor
    if [[ "$prompt_lower" =~ (security|vulnerability|owasp|auth|authentication|injection|xss|csrf|pentest) ]]; then
        recommendations="${recommendations}security-auditor "
        ((confidence += 25))
    fi

    # Test/TDD patterns -> tdd-orchestrator
    if [[ "$prompt_lower" =~ (test|tdd|coverage|red.?green|unit.?test|integration.?test) ]]; then
        recommendations="${recommendations}tdd-orchestrator "
        ((confidence += 25))
    fi

    # Debug/error patterns -> debugger
    if [[ "$prompt_lower" =~ (debug|error|stack.?trace|troubleshoot|failing|broken|exception) ]]; then
        recommendations="${recommendations}debugger "
        ((confidence += 20))
    fi

    # Frontend/React patterns -> frontend-developer
    if [[ "$prompt_lower" =~ (react|frontend|ui|component|next\.?js|tailwind|css|responsive) ]]; then
        recommendations="${recommendations}frontend-developer "
        ((confidence += 25))
    fi

    # Database patterns -> database-architect
    if [[ "$prompt_lower" =~ (database|schema|migration|sql|nosql|postgres|mysql|mongodb|redis) ]]; then
        recommendations="${recommendations}database-architect "
        ((confidence += 25))
    fi

    # Cloud/Infrastructure patterns -> cloud-architect
    if [[ "$prompt_lower" =~ (cloud|aws|gcp|azure|infrastructure|terraform|kubernetes|k8s|docker) ]]; then
        recommendations="${recommendations}cloud-architect "
        ((confidence += 25))
    fi

    # Performance patterns -> performance-engineer
    if [[ "$prompt_lower" =~ (performance|optimize|slow|profile|benchmark|latency|n\+1|cache) ]]; then
        recommendations="${recommendations}performance-engineer "
        ((confidence += 25))
    fi

    # Code review patterns -> code-reviewer
    if [[ "$prompt_lower" =~ (review|code.?quality|best.?practice|refactor|clean.?code|solid) ]]; then
        recommendations="${recommendations}code-reviewer "
        ((confidence += 20))
    fi

    # Python patterns -> python-pro
    if [[ "$prompt_lower" =~ (python|fastapi|django|flask|pydantic|asyncio|pip|uv) ]]; then
        recommendations="${recommendations}python-pro "
        ((confidence += 25))
    fi

    # TypeScript patterns -> typescript-pro
    if [[ "$prompt_lower" =~ (typescript|generics|type.?safe|strict|tsconfig|discriminated) ]]; then
        recommendations="${recommendations}typescript-pro "
        ((confidence += 25))
    fi

    # GraphQL patterns -> graphql-architect
    if [[ "$prompt_lower" =~ (graphql|resolver|mutation|subscription|federation|apollo) ]]; then
        recommendations="${recommendations}graphql-architect "
        ((confidence += 25))
    fi

    # UX Research patterns -> ux-researcher (v6.0)
    if [[ "$prompt_lower" =~ (user.?research|ux.?research|user.?interview|usability|journey.?map|persona) ]]; then
        recommendations="${recommendations}ux-researcher "
        ((confidence += 25))
    fi

    # Strategy/Consulting patterns -> strategy-analyst (v6.0)
    if [[ "$prompt_lower" =~ (market.?analysis|competitive|business.?case|strategic|swot|gtm|go.?to.?market) ]]; then
        recommendations="${recommendations}strategy-analyst "
        ((confidence += 25))
    fi

    # Research Synthesis patterns -> research-synthesizer (v6.0)
    if [[ "$prompt_lower" =~ (literature.?review|research.?synthesis|systematic.?review|annotated.?bibliography) ]]; then
        recommendations="${recommendations}research-synthesizer "
        ((confidence += 25))
    fi

    # Product Writing patterns -> product-writer (v6.0)
    if [[ "$prompt_lower" =~ (prd|product.?requirement|user.?story|acceptance.?criteria|feature.?spec) ]]; then
        recommendations="${recommendations}product-writer "
        ((confidence += 25))
    fi

    # Executive Communication patterns -> exec-communicator (v6.0)
    if [[ "$prompt_lower" =~ (executive.?summary|board.?presentation|stakeholder.?report|workshop.?synthesis) ]]; then
        recommendations="${recommendations}exec-communicator "
        ((confidence += 25))
    fi

    # Academic Writing patterns -> academic-writer (v6.0)
    if [[ "$prompt_lower" =~ (research.?paper|grant.?proposal|abstract|peer.?review|thesis|dissertation) ]]; then
        recommendations="${recommendations}academic-writer "
        ((confidence += 25))
    fi

    # Return first recommendation if confidence is high enough
    local primary
    primary=$(echo "$recommendations" | awk '{print $1}')

    # Only recommend if we have a match
    if [[ -n "$primary" ]]; then
        echo "$primary"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# COMPLEXITY ESTIMATION
# ═══════════════════════════════════════════════════════════════════════════════

# Estimate task complexity from prompt (1=trivial, 2=standard, 3=complex)
# Usage: estimate_complexity <prompt>
estimate_complexity() {
    local prompt="$1"
    local prompt_lower
    prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')  # Bash 3.2 compatible
    local word_count=$(echo "$prompt" | wc -w | tr -d ' ')
    local score=2  # Default: standard

    # TRIVIAL indicators (reduce score)
    # Short, simple operations that don't need premium models
    local trivial_patterns="typo|rename|update.?version|bump.?version|change.*to|fix.?typo|formatting|indent|whitespace|simple|quick|small"
    local single_file_patterns="in readme|in package|in changelog|in config|\.json|\.md|\.txt|\.yml|\.yaml"

    # Check for trivial indicators
    if [[ $word_count -lt 12 ]]; then
        ((score--))
    fi

    if [[ "$prompt_lower" =~ ($trivial_patterns) ]]; then
        ((score--))
    fi

    if [[ "$prompt_lower" =~ ($single_file_patterns) ]]; then
        ((score--))
    fi

    # COMPLEX indicators (increase score)
    # Multi-step, architectural, or comprehensive tasks need premium models
    local complex_patterns="implement|design|architect|build.*feature|create.*system|from.?scratch|comprehensive|full.?system|entire|integrate|authentication|api|database"
    local multi_component="and.*and|multiple|across|throughout|all.?files|refactor.*entire|complete"

    # Check for complex indicators
    if [[ $word_count -gt 40 ]]; then
        ((score++))
    fi

    if [[ "$prompt_lower" =~ ($complex_patterns) ]]; then
        ((score++))
    fi

    if [[ "$prompt_lower" =~ ($multi_component) ]]; then
        ((score++))
    fi

    # Clamp to 1-3 range
    [[ $score -lt 1 ]] && score=1
    [[ $score -gt 3 ]] && score=3

    echo "$score"
}

# Get complexity tier name for display
get_tier_name() {
    local complexity="$1"
    case "$complexity" in
        1) echo "trivial (quick mode)" ;;
        2) echo "standard" ;;
        3) echo "complex (premium)" ;;
        *) echo "standard" ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# ROLE MAPPING
# ═══════════════════════════════════════════════════════════════════════════════

# Get the appropriate role for an agent based on context
# Usage: get_role_for_context <agent_type> <task_type> [phase]
get_role_for_context() {
    local agent_type="$1"
    local task_type="$2"
    local phase="${3:-}"

    # Phase-specific role mapping (highest priority)
    case "$phase" in
        probe)
            echo "researcher"
            return
            ;;
        grasp)
            if [[ "${SUPPORTS_AGENT_TYPE_ROUTING:-false}" == "true" ]]; then
                echo "strategist"
            else
                echo "synthesizer"
            fi
            return
            ;;
        ink)
            if [[ "${SUPPORTS_AGENT_TYPE_ROUTING:-false}" == "true" ]]; then
                echo "strategist"
            else
                echo "synthesizer"
            fi
            return
            ;;
    esac

    # Task-type based role mapping
    case "$task_type" in
        review|diamond-deliver)
            echo "reviewer"
            ;;
        coding|diamond-develop)
            # Refine based on agent type
            if [[ "$agent_type" == "gemini" || "$agent_type" == "gemini-fast" ]]; then
                echo "researcher"
            else
                echo "implementer"
            fi
            ;;
        design)
            echo "frontend-architect"
            ;;
        research|diamond-discover)
            echo "researcher"
            ;;
        *)
            # Agent-type fallback
            case "$agent_type" in
                codex|codex-max|codex-standard)
                    echo "implementer"
                    ;;
                codex-review)
                    echo "reviewer"
                    ;;
                gemini|gemini-fast)
                    echo "researcher"
                    ;;
                *)
                    echo ""  # No persona
                    ;;
            esac
            ;;
    esac
}
