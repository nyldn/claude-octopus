#!/usr/bin/env bash
# Claude Octopus - Multi-Agent Orchestrator
# Coordinates multiple AI agents (Codex CLI, Gemini CLI) for parallel task execution
# https://github.com/nyldn/claude-octopus

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# Workspace location - uses home directory for global installation
PROJECT_ROOT="${PWD}"
WORKSPACE_DIR="${CLAUDE_OCTOPUS_WORKSPACE:-${HOME}/.claude-octopus}"
TASKS_FILE="${WORKSPACE_DIR}/tasks.json"
RESULTS_DIR="${WORKSPACE_DIR}/results"
LOGS_DIR="${WORKSPACE_DIR}/logs"
PID_FILE="${WORKSPACE_DIR}/pids"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Agent configurations
# Models (Jan 2026) - Premium defaults for Design Thinking workflows:
# - OpenAI GPT-5.x: gpt-5.1-codex-max (premium), gpt-5.2-codex, gpt-5.1-codex-mini, gpt-5.2
# - Google Gemini 3.0: gemini-3-pro-preview, gemini-3-flash-preview, gemini-3-pro-image-preview
get_agent_command() {
    local agent_type="$1"
    case "$agent_type" in
        codex) echo "codex exec -m gpt-5.1-codex-max" ;;          # Premium default
        codex-standard) echo "codex exec -m gpt-5.2-codex" ;;     # Standard tier
        codex-max) echo "codex exec -m gpt-5.1-codex-max" ;;
        codex-mini) echo "codex exec -m gpt-5.1-codex-mini" ;;
        codex-general) echo "codex exec -m gpt-5.2" ;;
        gemini) echo "gemini -y -m gemini-3-pro-preview" ;;
        gemini-fast) echo "gemini -y -m gemini-3-flash-preview" ;;
        gemini-image) echo "gemini -y -m gemini-3-pro-image-preview" ;;
        codex-review) echo "codex exec review -m gpt-5.2-codex" ;;
        *) return 1 ;;
    esac
}

# List of available agents
AVAILABLE_AGENTS="codex codex-standard codex-max codex-mini codex-general gemini gemini-fast gemini-image codex-review"

# Task classification for contextual agent routing
# Returns: diamond-discover|diamond-develop|diamond-deliver|coding|research|design|copywriting|image|review|general
# Order matters! Double Diamond intents checked first, then specific patterns.
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
    # DOUBLE DIAMOND INTENT DETECTION
    # Routes to full workflow phases, not just single agents
    # ═══════════════════════════════════════════════════════════════════════════

    # Discover phase: research, explore, investigate
    if [[ "$prompt_lower" =~ ^(research|explore|investigate|study|discover)[[:space:]] ]] || \
       [[ "$prompt_lower" =~ (research|explore|investigate).*(option|approach|pattern|practice|alternative) ]]; then
        echo "diamond-discover"
        return
    fi

    # Develop+Deliver phase: build, develop, implement, create
    if [[ "$prompt_lower" =~ ^(develop|dev|build|implement|construct)[[:space:]] ]] || \
       [[ "$prompt_lower" =~ (build|develop|implement).*(feature|system|module|component|service) ]]; then
        echo "diamond-develop"
        return
    fi

    # Deliver phase: QA, test, review, validate
    if [[ "$prompt_lower" =~ ^(qa|test|review|validate|verify|audit|check)[[:space:]] ]] || \
       [[ "$prompt_lower" =~ (qa|test|review|validate).*(implementation|code|changes|feature) ]]; then
        echo "diamond-deliver"
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

# Get best agent for task type
get_agent_for_task() {
    local task_type="$1"
    case "$task_type" in
        image) echo "gemini-image" ;;
        review) echo "codex-review" ;;
        coding) echo "codex" ;;
        design) echo "gemini" ;;       # Gemini excels at reasoning about design
        copywriting) echo "gemini" ;;  # Gemini strong at creative writing
        research) echo "gemini" ;;     # Gemini good at analysis/synthesis
        general) echo "codex" ;;       # Default to codex for general tasks
        *) echo "codex" ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# COST-AWARE ROUTING - Complexity estimation and tiered model selection
# Prevents expensive premium models from being used on trivial tasks
# ═══════════════════════════════════════════════════════════════════════════════

# Estimate task complexity: trivial (1), standard (2), complex (3)
# Uses keyword analysis and prompt length to determine appropriate model tier
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
        1) echo "trivial (🐙 quick mode)" ;;
        2) echo "standard" ;;
        3) echo "complex (premium)" ;;
        *) echo "standard" ;;
    esac
}

# Get agent based on task type AND complexity tier
# This replaces the simple get_agent_for_task for cost-aware routing
get_tiered_agent() {
    local task_type="$1"
    local complexity="${2:-2}"  # Default: standard

    case "$task_type" in
        image)
            # Image generation always uses gemini-image
            echo "gemini-image"
            ;;
        review)
            # Reviews use standard tier (already cost-effective)
            echo "codex-review"
            ;;
        coding|general)
            # Coding tasks: tier based on complexity
            case "$complexity" in
                1) echo "codex-mini" ;;      # Trivial → mini (cheapest)
                2) echo "codex-standard" ;;  # Standard → standard tier
                3) echo "codex" ;;           # Complex → premium
            esac
            ;;
        design|copywriting|research)
            # Gemini tasks: tier based on complexity
            case "$complexity" in
                1) echo "gemini-fast" ;;     # Trivial → flash (cheaper)
                *) echo "gemini" ;;          # Standard+ → pro
            esac
            ;;
        diamond-*)
            # Double Diamond workflows always use premium
            echo "codex"
            ;;
        *)
            # Safe default: standard tier
            echo "codex-standard"
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# CONDITIONAL BRANCHING - Tentacle path selection based on task analysis
# Enables decision trees for workflow routing
# ═══════════════════════════════════════════════════════════════════════════════

# Evaluate which tentacle path to extend
# Returns: premium, standard, fast, or custom branch name
evaluate_branch_condition() {
    local task_type="$1"
    local complexity="$2"
    local custom_condition="${3:-}"

    # Check for user-specified branch override
    if [[ -n "$FORCE_BRANCH" ]]; then
        echo "$FORCE_BRANCH"
        return
    fi

    # Default branching logic based on task type + complexity
    case "$complexity" in
        3)  # Complex tasks → premium tentacle
            case "$task_type" in
                coding|review|design|diamond-*) echo "premium" ;;
                *) echo "standard" ;;
            esac
            ;;
        1)  # Trivial tasks → fast tentacle
            echo "fast"
            ;;
        *)  # Standard tasks → standard tentacle
            echo "standard"
            ;;
    esac
}

# Get display name for branch
get_branch_display() {
    local branch="$1"
    case "$branch" in
        premium) echo "premium (🐙 all tentacles engaged)" ;;
        standard) echo "standard (🐙 balanced grip)" ;;
        fast) echo "fast (🐙 quick touch)" ;;
        *) echo "$branch" ;;
    esac
}

# Evaluate next action based on quality gate outcome
# Returns: proceed, proceed_warn, retry, escalate, abort
evaluate_quality_branch() {
    local success_rate="$1"
    local retry_count="${2:-0}"
    local autonomy="${3:-$AUTONOMY_MODE}"

    # Check for explicit on-fail override
    if [[ "$ON_FAIL_ACTION" != "auto" && $success_rate -lt $QUALITY_THRESHOLD ]]; then
        case "$ON_FAIL_ACTION" in
            retry) echo "retry" ;;
            escalate) echo "escalate" ;;
            abort) echo "abort" ;;
        esac
        return
    fi

    # Auto-determine action based on success rate and settings
    if [[ $success_rate -ge 90 ]]; then
        echo "proceed"  # Quality gate passed
    elif [[ $success_rate -ge $QUALITY_THRESHOLD ]]; then
        echo "proceed_warn"  # Passed with warning
    elif [[ "$LOOP_UNTIL_APPROVED" == "true" && $retry_count -lt $MAX_QUALITY_RETRIES ]]; then
        echo "retry"  # Auto-retry enabled
    elif [[ "$autonomy" == "supervised" ]]; then
        echo "escalate"  # Human decision required
    else
        echo "abort"  # Failed, no retry
    fi
}

# Execute action based on quality gate branch decision
execute_quality_branch() {
    local branch="$1"
    local task_group="$2"
    local retry_count="${3:-0}"

    echo ""
    echo -e "${MAGENTA}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${MAGENTA}│  Quality Gate Decision: ${YELLOW}${branch}${MAGENTA}                              │${NC}"
    echo -e "${MAGENTA}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    case "$branch" in
        proceed)
            log INFO "✓ Quality gate PASSED - proceeding to delivery"
            return 0
            ;;
        proceed_warn)
            log WARN "⚠ Quality gate PASSED with warnings - proceeding cautiously"
            return 0
            ;;
        retry)
            log INFO "↻ Quality gate FAILED - retrying (attempt $((retry_count + 1))/$MAX_QUALITY_RETRIES)"
            return 2  # Signal retry
            ;;
        escalate)
            log WARN "⚡ Quality gate FAILED - escalating to human review"
            echo ""
            echo -e "${YELLOW}Manual review required. Results at: ${RESULTS_DIR}/tangle-validation-${task_group}.md${NC}"
            read -p "Continue anyway? (y/n) " -n 1 -r
            echo
            [[ $REPLY =~ ^[Yy]$ ]] && return 0 || return 1
            ;;
        abort)
            log ERROR "✗ Quality gate FAILED - aborting workflow"
            return 1
            ;;
        *)
            log ERROR "Unknown quality branch: $branch"
            return 1
            ;;
    esac
}

# Default settings
MAX_PARALLEL=3
TIMEOUT=300
VERBOSE=false
DRY_RUN=false

# v3.0 Feature: Autonomy Modes & Quality Control
# - autonomous: Full auto, proceed on failures
# - semi-autonomous: Auto with quality gates (default)
# - supervised: Human approval required after each phase
# - loop-until-approved: Retry failed tasks until quality gate passes
AUTONOMY_MODE="${CLAUDE_OCTOPUS_AUTONOMY:-semi-autonomous}"
QUALITY_THRESHOLD="${CLAUDE_OCTOPUS_QUALITY_THRESHOLD:-75}"
MAX_QUALITY_RETRIES="${CLAUDE_OCTOPUS_MAX_RETRIES:-3}"
LOOP_UNTIL_APPROVED=false
RESUME_SESSION=false

# v3.1 Feature: Cost-Aware Routing
# Complexity tiers: trivial (1), standard (2), complex/premium (3)
FORCE_TIER=""  # "", "trivial", "standard", "premium"

# v3.2 Feature: Conditional Branching
# Tentacle paths for workflow routing based on conditions
FORCE_BRANCH=""           # "", "premium", "standard", "fast"
ON_FAIL_ACTION="auto"     # "auto", "retry", "escalate", "abort"
CURRENT_BRANCH=""         # Tracks current branch for session recovery

# Session recovery
SESSION_FILE="${WORKSPACE_DIR}/session.json"

usage() {
    cat << EOF
${MAGENTA}
   ___  ___ _____  ___  ____  _   _ ___
  / _ \/ __|_   _|/ _ \|  _ \| | | / __|
 | (_) |__ \ | | | (_) | |_) | |_| \__ \\
  \___/|___/ |_|  \___/|____/ \___/|___/
${NC}
${CYAN}                          ___
                      .-'   \`'.
                     /         \\
                     |         ;
                     |         |           ___.--,
            _.._     |0) ~ (0) |    _.---'\`__.-( (_.
     __.--'\`_.. '.__.\    '--. \\_.-' ,.--'\`     \`""\`
    ( ,.--'\`   ',__ /./;   ;, '.__.\`    __
    _\`) )  .---.__.' / |   |\   \\__..--""  """--.,_
    \`---' .'.''-._.-.'\`_./  /\\ '.  \\ _.-~~~\`\`\`\`~~~-._\`-.__.'
         | |  .' _.-' |  |  \\  \\  '.               \`~---\`
          \\ \\/ .'     \\  \\   '. '-._)
           \\/ /        \\  \\    \`=.__\`~-.
           / /\\         \`) )    / / \`"".\\
     , _.-'.'\\ \\        / /    ( (     / /
      \`--~\`   ) )    .-'.'      '.'.  | (
             (/\`    ( (\`          ) )  '-;    Eight tentacles.
              \`      '-;         (-'         Infinite possibilities.
${NC}
${CYAN}Claude Octopus${NC} - Design Thinking Enabler for Claude Code
Multi-agent orchestration using Double Diamond methodology.

${YELLOW}Usage:${NC} $(basename "$0") [OPTIONS] COMMAND [ARGS...]

${YELLOW}Getting Started:${NC}
  setup                   ${GREEN}Interactive setup wizard${NC} (recommended for first-time users)
  preflight               Validate all dependencies are available

${YELLOW}Double Diamond Commands:${NC} (Design Thinking)
  probe <prompt>          Discover: Parallel research + synthesis
  grasp <prompt>          Define: Consensus building on approach
  tangle <prompt>         Develop: Enhanced map-reduce with validation
  ink <prompt>            Deliver: Quality gates + final output
  embrace <prompt>        Full 4-phase Double Diamond workflow

${YELLOW}Classic Commands:${NC}
  init                    Initialize workspace for parallel execution
  spawn <agent> <prompt>  Spawn a single agent with given prompt
  auto <prompt>           Smart-route (uses Double Diamond for research/build/QA)
  parallel <tasks-file>   Execute tasks from JSON file in parallel
  fan-out <prompt>        Send same prompt to all agents, collect results
  map-reduce <prompt>     Decompose task, map to agents, reduce results
  status                  Show status of running agents
  kill [agent-id|all]     Kill running agent(s)
  clean                   Clean workspace and kill all agents
  aggregate               Combine all results into single document
  help                    Show this help message

${YELLOW}Available Agents:${NC} (Premium defaults)
  codex         GPT-5.1-Codex-Max   ${GREEN}Premium default${NC} for complex coding
  codex-standard GPT-5.2-Codex      Standard coding model
  codex-max     GPT-5.1-Codex-Max   Long-running, project-scale work
  codex-mini    GPT-5.1-Codex-Mini  Quick fixes, simple tasks
  codex-general GPT-5.2             Non-coding agentic tasks
  gemini        Gemini-3-Pro        Deep analysis, complex reasoning
  gemini-fast   Gemini-3-Flash      Speed-critical tasks
  gemini-image  Gemini-3-Image      Image generation (text-to-image)
  codex-review  GPT-5.2-Codex       Specialized code review mode

${YELLOW}Options:${NC}
  -p, --parallel NUM      Max parallel agents (default: $MAX_PARALLEL)
  -t, --timeout SECS      Timeout per task in seconds (default: $TIMEOUT)
  -v, --verbose           Verbose output
  -n, --dry-run           Show what would be done without executing
  -d, --dir DIR           Working directory (default: project root)
  -a, --autonomy MODE     Autonomy mode: autonomous|semi-autonomous|supervised|loop-until-approved
  -q, --quality NUM       Quality gate threshold percentage (default: $QUALITY_THRESHOLD)
  -l, --loop              Enable loop-until-approved for quality gates
  -R, --resume            Resume last interrupted session

${YELLOW}Cost Control:${NC} (v3.1 - Smart model selection based on task complexity)
  -Q, --quick             Force trivial tier (cheapest models: codex-mini, gemini-fast)
  -P, --premium           Force premium tier (most capable: codex-max)
  --tier LEVEL            Explicit tier: trivial|standard|premium

${YELLOW}Conditional Branching:${NC} (v3.2 - Decision trees for workflow routing)
  --branch BRANCH         Force tentacle path: premium|standard|fast
  --on-fail ACTION        Quality gate failure action: auto|retry|escalate|abort

${YELLOW}Double Diamond Examples:${NC}
  # Full workflow - explore, define, develop, deliver
  $(basename "$0") embrace "Build a user authentication system"

  # Just the research phase
  $(basename "$0") probe "What are best practices for REST API design?"

  # Define the problem after research
  $(basename "$0") grasp "Implement caching layer" ./results/probe-synthesis.md

  # Smart auto-routing (detects intent)
  $(basename "$0") auto "research authentication patterns"    # → runs probe
  $(basename "$0") auto "build user auth system"              # → runs tangle → ink
  $(basename "$0") auto "review the implementation"           # → runs ink

${YELLOW}Classic Examples:${NC}
  $(basename "$0") auto "Generate a hero image for the landing page"
  $(basename "$0") spawn codex "Fix the TypeScript errors in src/components"
  $(basename "$0") fan-out "Review the authentication flow for security issues"

${YELLOW}Environment Variables:${NC}
  CLAUDE_OCTOPUS_WORKSPACE  Override workspace directory (default: ~/.claude-octopus)

${CYAN}https://github.com/nyldn/claude-octopus${NC}
EOF
    exit 0
}

log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        INFO)  echo -e "${BLUE}[$timestamp]${NC} ${GREEN}INFO${NC}: $msg" ;;
        WARN)  echo -e "${BLUE}[$timestamp]${NC} ${YELLOW}WARN${NC}: $msg" ;;
        ERROR) echo -e "${BLUE}[$timestamp]${NC} ${RED}ERROR${NC}: $msg" >&2 ;;
        DEBUG) [[ "$VERBOSE" == "true" ]] && echo -e "${BLUE}[$timestamp]${NC} ${CYAN}DEBUG${NC}: $msg" || true ;;
    esac
}

# Portable timeout function (works on macOS and Linux)
run_with_timeout() {
    local timeout_secs="$1"
    shift

    if command -v gtimeout &> /dev/null; then
        gtimeout "$timeout_secs" "$@"
    elif command -v timeout &> /dev/null; then
        timeout "$timeout_secs" "$@"
    else
        # Fallback: run command with manual timeout using background process
        "$@" &
        local cmd_pid=$!

        (
            sleep "$timeout_secs"
            if kill -0 "$cmd_pid" 2>/dev/null; then
                kill -TERM "$cmd_pid" 2>/dev/null
                sleep 2
                kill -KILL "$cmd_pid" 2>/dev/null
            fi
        ) &
        local monitor_pid=$!

        wait "$cmd_pid" 2>/dev/null
        local exit_code=$?

        kill "$monitor_pid" 2>/dev/null
        wait "$monitor_pid" 2>/dev/null

        return $exit_code
    fi
}

init_workspace() {
    log INFO "Initializing Claude Octopus workspace at $WORKSPACE_DIR"

    mkdir -p "$WORKSPACE_DIR" "$RESULTS_DIR" "$LOGS_DIR"

    if [[ ! -f "$TASKS_FILE" ]]; then
        cat > "$TASKS_FILE" << 'TASKS_JSON'
{
  "version": "1.0",
  "project": "my-project",
  "tasks": [
    {
      "id": "example-1",
      "agent": "codex",
      "prompt": "List all TypeScript files in src/",
      "priority": 1,
      "depends_on": []
    },
    {
      "id": "example-2",
      "agent": "gemini",
      "prompt": "Analyze the project structure and suggest improvements",
      "priority": 2,
      "depends_on": []
    }
  ],
  "settings": {
    "max_parallel": 3,
    "timeout": 300,
    "retry_on_failure": true
  }
}
TASKS_JSON
        log INFO "Created default tasks.json template"
    fi

    cat > "${WORKSPACE_DIR}/.gitignore" << 'GITIGNORE'
# Claude Octopus workspace - ephemeral data
*
!.gitignore
GITIGNORE

    log INFO "Workspace initialized successfully"
    echo ""
    echo -e "${GREEN}✓${NC} Workspace ready at: $WORKSPACE_DIR"
    echo -e "${GREEN}✓${NC} Edit tasks at: $TASKS_FILE"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# v3.0 FEATURE: AUTONOMY MODE HANDLER
# Controls human oversight level during workflow execution
# ═══════════════════════════════════════════════════════════════════════════════

handle_autonomy_checkpoint() {
    local phase="$1"
    local status="$2"

    case "$AUTONOMY_MODE" in
        "supervised")
            echo ""
            echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
            echo -e "${YELLOW}║  Supervised Mode - Human Approval Required                ║${NC}"
            echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
            echo -e "Phase ${CYAN}$phase${NC} completed with status: ${GREEN}$status${NC}"
            echo ""
            read -p "Continue to next phase? (y/n) " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log INFO "User chose to stop workflow after $phase phase"
                exit 0
            fi
            ;;
        "semi-autonomous")
            if [[ "$status" == "failed" || "$status" == "warning" ]]; then
                echo ""
                echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
                echo -e "${YELLOW}║  Quality Gate Issue - Review Required                     ║${NC}"
                echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
                echo -e "Phase ${CYAN}$phase${NC} has status: ${RED}$status${NC}"
                echo ""
                read -p "Continue anyway? (y/n) " -n 1 -r
                echo ""
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log ERROR "User chose to abort due to quality gate $status"
                    exit 1
                fi
            fi
            ;;
        "loop-until-approved")
            # Handled in quality gate logic - LOOP_UNTIL_APPROVED flag
            ;;
        "autonomous"|*)
            # Always continue without prompts
            log DEBUG "Autonomy mode: continuing automatically"
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# v3.0 FEATURE: SESSION RECOVERY
# Save/restore workflow state for resuming interrupted workflows
# ═══════════════════════════════════════════════════════════════════════════════

# Initialize a new session
init_session() {
    local workflow="$1"
    local prompt="$2"
    local session_id="${workflow}-$(date +%Y%m%d-%H%M%S)"

    # Ensure jq is available for JSON manipulation
    if ! command -v jq &> /dev/null; then
        log WARN "jq not available - session recovery disabled"
        return 1
    fi

    mkdir -p "$(dirname "$SESSION_FILE")"

    cat > "$SESSION_FILE" << EOF
{
  "session_id": "$session_id",
  "workflow": "$workflow",
  "status": "in_progress",
  "current_phase": null,
  "started_at": "$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)",
  "last_checkpoint": null,
  "prompt": $(printf '%s' "$prompt" | jq -Rs .),
  "phases": {}
}
EOF
    log INFO "Session initialized: $session_id"
}

# Save checkpoint after phase completion
save_session_checkpoint() {
    local phase="$1"
    local status="$2"
    local output_file="$3"

    if [[ ! -f "$SESSION_FILE" ]] || ! command -v jq &> /dev/null; then
        return 0
    fi

    local timestamp
    timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

    jq --arg phase "$phase" \
       --arg status "$status" \
       --arg output "$output_file" \
       --arg time "$timestamp" \
       '.phases[$phase] = {status: $status, output: $output, timestamp: $time} | .last_checkpoint = $time | .current_phase = $phase' \
       "$SESSION_FILE" > "${SESSION_FILE}.tmp" && mv "${SESSION_FILE}.tmp" "$SESSION_FILE"

    log DEBUG "Checkpoint saved: $phase ($status)"
}

# Check for resumable session
check_resume_session() {
    if [[ ! -f "$SESSION_FILE" ]] || ! command -v jq &> /dev/null; then
        return 1
    fi

    local status workflow phase
    status=$(jq -r '.status' "$SESSION_FILE" 2>/dev/null)

    if [[ "$status" == "in_progress" ]]; then
        workflow=$(jq -r '.workflow' "$SESSION_FILE")
        phase=$(jq -r '.current_phase // "none"' "$SESSION_FILE")

        echo ""
        echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║  Interrupted Session Found                                ║${NC}"
        echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
        echo -e "Workflow: ${CYAN}$workflow${NC}"
        echo -e "Last phase: ${CYAN}$phase${NC}"
        echo ""
        read -p "Resume from last checkpoint? (y/n) " -n 1 -r
        echo ""

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            return 0  # Resume
        fi
    fi
    return 1  # Start fresh
}

# Get the phase to resume from
get_resume_phase() {
    if [[ -f "$SESSION_FILE" ]] && command -v jq &> /dev/null; then
        jq -r '.current_phase // ""' "$SESSION_FILE"
    fi
}

# Get saved output file for a phase
get_phase_output() {
    local phase="$1"
    if [[ -f "$SESSION_FILE" ]] && command -v jq &> /dev/null; then
        jq -r ".phases.$phase.output // \"\"" "$SESSION_FILE"
    fi
}

# Mark session as complete
complete_session() {
    if [[ -f "$SESSION_FILE" ]] && command -v jq &> /dev/null; then
        jq '.status = "completed"' "$SESSION_FILE" > "${SESSION_FILE}.tmp" && \
            mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
        log INFO "Session marked complete"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# v3.0 FEATURE: SPECIALIZED AGENT ROLES
# Role-based agent selection for different phases of work
# Each "tentacle" has expertise in a specific domain
# ═══════════════════════════════════════════════════════════════════════════════

# Role-to-agent mapping (function-based for bash 3.x compatibility)
# Returns agent:model format for a given role
get_role_mapping() {
    local role="$1"
    case "$role" in
        architect)    echo "codex:gpt-5.1-codex-max" ;;      # System design, planning
        researcher)   echo "gemini:gemini-3-pro-preview" ;;   # Deep investigation
        reviewer)     echo "codex-review:gpt-5.2-codex" ;;    # Code review, validation
        implementer)  echo "codex:gpt-5.1-codex-max" ;;       # Code generation
        synthesizer)  echo "gemini:gemini-3-flash-preview" ;; # Result aggregation
        *)            echo "codex:gpt-5.1-codex-max" ;;       # Default
    esac
}

# Get agent type for a role
get_role_agent() {
    local role="$1"
    local mapping
    mapping=$(get_role_mapping "$role")
    echo "${mapping%%:*}"  # Return agent type (before colon)
}

# Get model for a role
get_role_model() {
    local role="$1"
    local mapping
    mapping=$(get_role_mapping "$role")
    echo "${mapping##*:}"  # Return model (after colon)
}

# Log role assignment for verbose mode
log_role_assignment() {
    local role="$1"
    local purpose="$2"
    local agent
    agent=$(get_role_agent "$role")
    log DEBUG "Using ${role} role (${agent}) for: ${purpose}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# v3.0 FEATURE: NANO BANANA PROMPT REFINEMENT
# Intelligent prompt enhancement for image generation tasks
# Analyzes user intent and crafts optimized prompts for visual output
# ═══════════════════════════════════════════════════════════════════════════════

# Refine image prompt using "nano banana" technique
# Takes raw user prompt and returns an enhanced prompt optimized for image generation
refine_image_prompt() {
    local raw_prompt="$1"
    local image_type="${2:-general}"

    log INFO "Applying nano banana prompt refinement for: $image_type"

    # Build refinement prompt based on image type
    local refinement_prompt=""
    case "$image_type" in
        "app-icon"|"favicon")
            refinement_prompt="Transform this into a detailed image generation prompt for an app icon/favicon:
Original request: $raw_prompt

Create a prompt that specifies:
- Simple, recognizable silhouette that works at small sizes (16x16 to 512x512)
- Bold colors with good contrast
- Minimal detail that scales well
- Professional, modern aesthetic
- Square format with optional rounded corners

Output ONLY the refined prompt, nothing else."
            ;;
        "social-media")
            refinement_prompt="Transform this into a detailed image generation prompt for social media:
Original request: $raw_prompt

Create a prompt that specifies:
- Eye-catching composition with focal point
- Appropriate aspect ratio (16:9 for banners, 1:1 for posts)
- Brand-friendly colors and style
- Space for text overlay if needed
- Professional quality suitable for marketing

Output ONLY the refined prompt, nothing else."
            ;;
        "diagram")
            refinement_prompt="Transform this into a detailed image generation prompt for a technical diagram:
Original request: $raw_prompt

Create a prompt that specifies:
- Clean, professional diagram style
- Clear visual hierarchy and flow
- Appropriate use of shapes, arrows, and connections
- Readable labels and annotations
- Light or neutral background for clarity

Output ONLY the refined prompt, nothing else."
            ;;
        *)
            refinement_prompt="Transform this into a detailed, optimized image generation prompt:
Original request: $raw_prompt

Enhance the prompt with:
- Specific visual style and composition details
- Lighting, mood, and atmosphere
- Color palette suggestions
- Technical specifications (resolution, aspect ratio if implied)
- Quality modifiers (professional, high-quality, detailed)

Output ONLY the refined prompt, nothing else."
            ;;
    esac

    # Use Gemini for intelligent prompt refinement
    local refined
    refined=$(run_agent_sync "gemini-fast" "$refinement_prompt" 60 2>/dev/null) || {
        log WARN "Prompt refinement failed, using original"
        echo "$raw_prompt"
        return
    }

    echo "$refined"
}

# Detect image type from prompt for targeted refinement
detect_image_type() {
    local prompt_lower="$1"

    if [[ "$prompt_lower" =~ (app[[:space:]]?icon|favicon|icon[[:space:]]for[[:space:]]?(an?[[:space:]])?app) ]]; then
        echo "app-icon"
    elif [[ "$prompt_lower" =~ (social[[:space:]]?media|twitter|linkedin|facebook|instagram|og[[:space:]]?image|banner|header) ]]; then
        echo "social-media"
    elif [[ "$prompt_lower" =~ (diagram|flowchart|architecture|sequence|infographic) ]]; then
        echo "diagram"
    else
        echo "general"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# v3.0 FEATURE: LOOP-UNTIL-APPROVED RETRY LOGIC
# Retry failed subtasks until quality gate passes
# ═══════════════════════════════════════════════════════════════════════════════

# Store failed tasks for retry (global array - bash 3.x compatible)
FAILED_SUBTASKS=""  # Newline-separated list for compatibility

# Retry failed subtasks
retry_failed_subtasks() {
    local task_group="$1"
    local retry_count="$2"

    if [[ -z "$FAILED_SUBTASKS" ]]; then
        log DEBUG "No failed subtasks to retry"
        return 0
    fi

    # Count tasks (newline-separated)
    local task_count
    task_count=$(echo "$FAILED_SUBTASKS" | grep -c .)
    log INFO "Retrying $task_count failed subtasks (attempt $retry_count/${MAX_QUALITY_RETRIES})..."

    local pids=""
    local subtask_num=0
    local pid_count=0

    # Process newline-separated list
    while IFS= read -r failed_task; do
        [[ -z "$failed_task" ]] && continue

        # Parse failed task info (format: agent:prompt)
        local agent="${failed_task%%:*}"
        local prompt="${failed_task#*:}"

        spawn_agent "$agent" "$prompt" "tangle-${task_group}-retry${retry_count}-${subtask_num}" &
        local pid=$!
        pids="$pids $pid"
        ((subtask_num++))
        ((pid_count++))
    done <<< "$FAILED_SUBTASKS"

    # Wait for retry tasks
    local completed=0
    while [[ $completed -lt $pid_count ]]; do
        completed=0
        for pid in $pids; do
            if ! kill -0 "$pid" 2>/dev/null; then
                ((completed++))
            fi
        done
        echo -ne "\r${YELLOW}Retry progress: $completed/${pid_count} tasks${NC}"
        sleep 2
    done
    echo ""

    # Clear failed tasks for re-evaluation
    FAILED_SUBTASKS=""
}

spawn_agent() {
    local agent_type="$1"
    local prompt="$2"
    local task_id="${3:-$(date +%s)}"

    local cmd
    if ! cmd=$(get_agent_command "$agent_type"); then
        log ERROR "Unknown agent type: $agent_type"
        log INFO "Available agents: $AVAILABLE_AGENTS"
        return 1
    fi

    local log_file="${LOGS_DIR}/${agent_type}-${task_id}.log"
    local result_file="${RESULTS_DIR}/${agent_type}-${task_id}.md"

    log INFO "Spawning $agent_type agent (task: $task_id)"
    log DEBUG "Command: $cmd \"$prompt\""

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would execute: $cmd \"$prompt\""
        return 0
    fi

    mkdir -p "$RESULTS_DIR" "$LOGS_DIR"
    touch "$PID_FILE"

    # Execute agent in background
    (
        cd "$PROJECT_ROOT" || exit 1
        set -f  # Disable glob expansion

        echo "# Agent: $agent_type" > "$result_file"
        echo "# Task ID: $task_id" >> "$result_file"
        echo "# Prompt: $prompt" >> "$result_file"
        echo "# Started: $(date)" >> "$result_file"
        echo "" >> "$result_file"
        echo "## Output" >> "$result_file"
        echo '```' >> "$result_file"

        # shellcheck disable=SC2086
        if run_with_timeout "$TIMEOUT" $cmd "$prompt" >> "$result_file" 2>> "$log_file"; then
            echo '```' >> "$result_file"
            echo "" >> "$result_file"
            echo "## Status: SUCCESS" >> "$result_file"
        else
            local exit_code=$?
            echo '```' >> "$result_file"
            echo "" >> "$result_file"
            echo "## Status: FAILED (exit code: $exit_code)" >> "$result_file"
        fi

        echo "# Completed: $(date)" >> "$result_file"
    ) &

    local pid=$!
    echo "$pid:$agent_type:$task_id" >> "$PID_FILE"

    log INFO "Agent spawned with PID: $pid"
    echo "$pid"
}

auto_route() {
    local prompt="$1"
    local prompt_lower
    prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')

    local task_type
    task_type=$(classify_task "$prompt")

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

    # ═══════════════════════════════════════════════════════════════════════════
    # CONDITIONAL BRANCHING - Evaluate which tentacle path to extend
    # ═══════════════════════════════════════════════════════════════════════════
    local branch
    branch=$(evaluate_branch_condition "$task_type" "$complexity")
    CURRENT_BRANCH="$branch"  # Store for session recovery
    local branch_display
    branch_display=$(get_branch_display "$branch")

    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}  Claude Octopus - Smart Routing with Branching${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BLUE}Task Analysis:${NC}"
    echo -e "  Prompt: ${prompt:0:80}..."
    echo -e "  Detected Type: ${GREEN}$task_type${NC}"
    echo -e "  Complexity: ${CYAN}$tier_name${NC}"
    echo -e "  Branch: ${MAGENTA}$branch_display${NC}"
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # DOUBLE DIAMOND WORKFLOW ROUTING
    # ═══════════════════════════════════════════════════════════════════════════
    case "$task_type" in
        diamond-discover)
            echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
            echo -e "${CYAN}║  PROBE (Discover Phase) - Parallel Research               ║${NC}"
            echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
            echo "  Routing to probe workflow for multi-perspective research."
            echo ""
            probe_discover "$prompt"
            return
            ;;
        diamond-develop)
            echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
            echo -e "${CYAN}║  TANGLE → INK (Develop + Deliver Phases)                  ║${NC}"
            echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
            echo "  Routing to tangle (develop) then ink (deliver) workflow."
            echo ""
            tangle_develop "$prompt" && ink_deliver "$prompt"
            return
            ;;
        diamond-deliver)
            echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
            echo -e "${CYAN}║  INK (Deliver Phase) - Quality & Validation               ║${NC}"
            echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
            echo "  Routing to ink workflow for quality gates and validation."
            echo ""
            ink_deliver "$prompt"
            return
            ;;
    esac

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

fan_out() {
    local prompt="$1"
    local agents=("codex" "gemini")
    local pids=()
    local task_group
    task_group=$(date +%s)

    log INFO "Fan-out: Sending prompt to ${#agents[@]} agents"
    echo ""

    for agent in "${agents[@]}"; do
        local pid
        pid=$(spawn_agent "$agent" "$prompt" "${task_group}-${agent}")
        pids+=("$pid")
        sleep 0.5
    done

    log INFO "All agents spawned. PIDs: ${pids[*]}"
    echo ""
    echo -e "${CYAN}Monitor progress:${NC}"
    echo "  $(basename "$0") status"
    echo ""
    echo -e "${CYAN}View results:${NC}"
    echo "  ls -la $RESULTS_DIR/"
    echo ""
}

parallel_execute() {
    local tasks_file="${1:-$TASKS_FILE}"

    if [[ ! -f "$tasks_file" ]]; then
        log ERROR "Tasks file not found: $tasks_file"
        log INFO "Run '$(basename "$0") init' to create a template"
        return 1
    fi

    log INFO "Loading tasks from: $tasks_file"

    if ! command -v jq &> /dev/null; then
        log ERROR "jq is required for parallel execution. Install with: brew install jq"
        return 1
    fi

    local task_count
    task_count=$(jq '.tasks | length' "$tasks_file")
    log INFO "Found $task_count tasks"

    local running=0
    local completed=0
    local pids=()

    while IFS= read -r task; do
        local task_id agent prompt
        task_id=$(echo "$task" | jq -r '.id')
        agent=$(echo "$task" | jq -r '.agent')
        prompt=$(echo "$task" | jq -r '.prompt')

        while [[ $running -ge $MAX_PARALLEL ]]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                    unset 'pids[i]'
                    ((running--))
                    ((completed++))
                fi
            done
            sleep 1
        done

        local pid
        pid=$(spawn_agent "$agent" "$prompt" "$task_id")
        pids+=("$pid")
        ((running++))

        log INFO "Progress: $completed/$task_count completed, $running running"
    done < <(jq -c '.tasks[]' "$tasks_file")

    log INFO "Waiting for remaining $running tasks to complete..."
    wait

    log INFO "All $task_count tasks completed"
    aggregate_results
}

map_reduce() {
    local main_prompt="$1"
    local task_group
    task_group=$(date +%s)

    log INFO "Map-Reduce: Decomposing task and distributing to agents"

    log INFO "Phase 1: Task decomposition with Gemini"
    local decompose_prompt="Analyze this task and break it into 3-5 independent subtasks that can be executed in parallel. Output as a simple numbered list. Task: $main_prompt"

    local decompose_result="${RESULTS_DIR}/decompose-${task_group}.txt"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would decompose: $main_prompt"
        return 0
    fi

    gemini "$decompose_prompt" > "$decompose_result" 2>&1 || {
        log WARN "Decomposition failed, falling back to fan-out"
        fan_out "$main_prompt"
        return
    }

    log INFO "Decomposition complete. Subtasks:"
    cat "$decompose_result"
    echo ""

    log INFO "Phase 2: Mapping subtasks to agents"
    local subtask_num=0
    local agents=("codex" "gemini")

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[0-9]+[\.\)] ]] || continue

        local subtask
        subtask=$(echo "$line" | sed 's/^[0-9]*[\.\)]\s*//')
        local agent="${agents[$((subtask_num % ${#agents[@]}))]}"

        spawn_agent "$agent" "$subtask" "${task_group}-subtask-${subtask_num}"
        ((subtask_num++))
    done < "$decompose_result"

    log INFO "Spawned $subtask_num subtask agents"

    log INFO "Phase 3: Waiting for subtasks to complete..."
    wait

    aggregate_results "$task_group"
}

aggregate_results() {
    local filter="${1:-}"
    local aggregate_file="${RESULTS_DIR}/aggregate-$(date +%s).md"

    log INFO "Aggregating results..."

    echo "# Claude Octopus - Aggregated Results" > "$aggregate_file"
    echo "" >> "$aggregate_file"
    echo "Generated: $(date)" >> "$aggregate_file"
    echo "" >> "$aggregate_file"

    local result_count=0
    for result in "$RESULTS_DIR"/*.md; do
        [[ -f "$result" ]] || continue
        [[ "$result" == *aggregate* ]] && continue
        [[ -n "$filter" && "$result" != *"$filter"* ]] && continue

        echo "---" >> "$aggregate_file"
        echo "" >> "$aggregate_file"
        cat "$result" >> "$aggregate_file"
        echo "" >> "$aggregate_file"
        ((result_count++))
    done

    echo "---" >> "$aggregate_file"
    echo "**Total Results: $result_count**" >> "$aggregate_file"

    log INFO "Aggregated $result_count results to: $aggregate_file"
    echo ""
    echo -e "${GREEN}✓${NC} Results aggregated to: $aggregate_file"
}

# ═══════════════════════════════════════════════════════════════════════════════
# SETUP WIZARD - Interactive first-time setup
# Guides users through CLI installation and API key configuration
# ═══════════════════════════════════════════════════════════════════════════════

# Config file for storing setup state
SETUP_CONFIG_FILE="$WORKSPACE_DIR/.setup-complete"

# Open URL in default browser (cross-platform)
open_browser() {
    local url="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        open "$url"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        xdg-open "$url" 2>/dev/null || sensible-browser "$url" 2>/dev/null || echo "Please open: $url"
    elif [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "cygwin"* ]]; then
        start "$url"
    else
        echo "Please open: $url"
    fi
}

# Interactive setup wizard
setup_wizard() {
    echo ""
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}        🐙 Claude Octopus Setup Wizard 🐙${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Welcome! Let's get all 8 tentacles connected and ready to work."
    echo -e "  This wizard will help you install dependencies and configure API keys."
    echo ""

    local total_steps=4
    local current_step=0
    local shell_profile=""
    local keys_to_add=""

    # Detect shell profile
    if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == *"zsh"* ]]; then
        shell_profile="$HOME/.zshrc"
    elif [[ -n "${BASH_VERSION:-}" ]] || [[ "$SHELL" == *"bash"* ]]; then
        shell_profile="$HOME/.bashrc"
    else
        shell_profile="$HOME/.profile"
    fi

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 1: Check/Install Codex CLI
    # ═══════════════════════════════════════════════════════════════════════════
    ((current_step++))
    echo -e "${CYAN}Step $current_step/$total_steps: Codex CLI (Tentacles 1-4)${NC}"
    echo -e "  OpenAI's Codex CLI powers our coding tentacles."
    echo ""

    if command -v codex &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Codex CLI already installed: $(command -v codex)"
    else
        echo -e "  ${YELLOW}✗${NC} Codex CLI not found"
        echo ""
        read -p "  Install Codex CLI now? (requires npm) [Y/n] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo -e "  ${CYAN}→${NC} Installing Codex CLI..."
            if npm install -g @openai/codex 2>&1 | sed 's/^/    /'; then
                echo -e "  ${GREEN}✓${NC} Codex CLI installed successfully"
            else
                echo -e "  ${RED}✗${NC} Installation failed. Try manually: npm install -g @openai/codex"
            fi
        else
            echo -e "  ${YELLOW}⚠${NC} Skipped. Install later: npm install -g @openai/codex"
        fi
    fi
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 2: Check/Install Gemini CLI
    # ═══════════════════════════════════════════════════════════════════════════
    ((current_step++))
    echo -e "${CYAN}Step $current_step/$total_steps: Gemini CLI (Tentacles 5-8)${NC}"
    echo -e "  Google's Gemini CLI powers our reasoning and image tentacles."
    echo ""

    if command -v gemini &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Gemini CLI already installed: $(command -v gemini)"
    else
        echo -e "  ${YELLOW}✗${NC} Gemini CLI not found"
        echo ""
        read -p "  Install Gemini CLI now? (requires npm) [Y/n] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo -e "  ${CYAN}→${NC} Installing Gemini CLI..."
            if npm install -g @anthropic/gemini-cli 2>&1 | sed 's/^/    /'; then
                echo -e "  ${GREEN}✓${NC} Gemini CLI installed successfully"
            else
                echo -e "  ${RED}✗${NC} Installation failed. Try manually: npm install -g @anthropic/gemini-cli"
            fi
        else
            echo -e "  ${YELLOW}⚠${NC} Skipped. Install later: npm install -g @anthropic/gemini-cli"
        fi
    fi
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 3: OpenAI API Key
    # ═══════════════════════════════════════════════════════════════════════════
    ((current_step++))
    echo -e "${CYAN}Step $current_step/$total_steps: OpenAI API Key${NC}"
    echo -e "  Required for Codex CLI (GPT models for coding tasks)."
    echo ""

    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        echo -e "  ${GREEN}✓${NC} OPENAI_API_KEY already set (${#OPENAI_API_KEY} chars)"
    else
        echo -e "  ${YELLOW}✗${NC} OPENAI_API_KEY not set"
        echo ""
        read -p "  Open OpenAI platform to get an API key? [Y/n] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo -e "  ${CYAN}→${NC} Opening https://platform.openai.com/api-keys ..."
            open_browser "https://platform.openai.com/api-keys"
            sleep 1
        fi
        echo ""
        echo -e "  Paste your OpenAI API key (starts with 'sk-'):"
        read -p "  → " openai_key
        if [[ -n "$openai_key" ]]; then
            export OPENAI_API_KEY="$openai_key"
            keys_to_add="${keys_to_add}export OPENAI_API_KEY=\"$openai_key\"\n"
            echo -e "  ${GREEN}✓${NC} OPENAI_API_KEY set for this session"
        else
            echo -e "  ${YELLOW}⚠${NC} Skipped. Set later: export OPENAI_API_KEY=\"your-key\""
        fi
    fi
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # STEP 4: Gemini API Key
    # ═══════════════════════════════════════════════════════════════════════════
    ((current_step++))
    echo -e "${CYAN}Step $current_step/$total_steps: Gemini API Key${NC}"
    echo -e "  Required for Gemini CLI (reasoning and image generation)."
    echo ""

    # Check for legacy GOOGLE_API_KEY
    if [[ -z "${GEMINI_API_KEY:-}" && -n "${GOOGLE_API_KEY:-}" ]]; then
        export GEMINI_API_KEY="$GOOGLE_API_KEY"
    fi

    if [[ -n "${GEMINI_API_KEY:-}" ]]; then
        echo -e "  ${GREEN}✓${NC} GEMINI_API_KEY already set (${#GEMINI_API_KEY} chars)"
    else
        echo -e "  ${YELLOW}✗${NC} GEMINI_API_KEY not set"
        echo ""
        read -p "  Open Google AI Studio to get an API key? [Y/n] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo -e "  ${CYAN}→${NC} Opening https://aistudio.google.com/apikey ..."
            open_browser "https://aistudio.google.com/apikey"
            sleep 1
        fi
        echo ""
        echo -e "  Paste your Gemini API key (starts with 'AIza'):"
        read -p "  → " gemini_key
        if [[ -n "$gemini_key" ]]; then
            export GEMINI_API_KEY="$gemini_key"
            keys_to_add="${keys_to_add}export GEMINI_API_KEY=\"$gemini_key\"\n"
            echo -e "  ${GREEN}✓${NC} GEMINI_API_KEY set for this session"
        else
            echo -e "  ${YELLOW}⚠${NC} Skipped. Set later: export GEMINI_API_KEY=\"your-key\""
        fi
    fi
    echo ""

    # ═══════════════════════════════════════════════════════════════════════════
    # SUMMARY & PERSISTENCE
    # ═══════════════════════════════════════════════════════════════════════════
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}                    Setup Summary${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Show status
    local all_good=true
    echo -e "  ${CYAN}Dependencies:${NC}"
    if command -v codex &>/dev/null; then
        echo -e "    ${GREEN}✓${NC} Codex CLI"
    else
        echo -e "    ${RED}✗${NC} Codex CLI"
        all_good=false
    fi
    if command -v gemini &>/dev/null; then
        echo -e "    ${GREEN}✓${NC} Gemini CLI"
    else
        echo -e "    ${RED}✗${NC} Gemini CLI"
        all_good=false
    fi
    echo ""
    echo -e "  ${CYAN}API Keys:${NC}"
    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        echo -e "    ${GREEN}✓${NC} OPENAI_API_KEY"
    else
        echo -e "    ${RED}✗${NC} OPENAI_API_KEY"
        all_good=false
    fi
    if [[ -n "${GEMINI_API_KEY:-}" ]]; then
        echo -e "    ${GREEN}✓${NC} GEMINI_API_KEY"
    else
        echo -e "    ${RED}✗${NC} GEMINI_API_KEY"
        all_good=false
    fi
    echo ""

    # Offer to persist keys
    if [[ -n "$keys_to_add" ]]; then
        echo -e "  ${YELLOW}To persist API keys across sessions, add to $shell_profile:${NC}"
        echo ""
        echo -e "$keys_to_add" | sed 's/^/    /'
        echo ""
        read -p "  Add these to $shell_profile automatically? [Y/n] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo "" >> "$shell_profile"
            echo "# Claude Octopus API Keys (added by setup wizard)" >> "$shell_profile"
            echo -e "$keys_to_add" >> "$shell_profile"
            echo -e "  ${GREEN}✓${NC} Added to $shell_profile"
            echo -e "  ${CYAN}→${NC} Run 'source $shell_profile' or restart your terminal"
        fi
        echo ""
    fi

    # Initialize workspace
    if [[ ! -d "$WORKSPACE_DIR" ]]; then
        init_workspace
    fi

    # Mark setup as complete
    mkdir -p "$WORKSPACE_DIR"
    date '+%Y-%m-%d %H:%M:%S' > "$SETUP_CONFIG_FILE"

    # Final message
    if $all_good; then
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  🐙 All 8 tentacles are connected and ready to work! 🐙${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "  Try these commands:"
        echo -e "    ${CYAN}orchestrate.sh preflight${NC}     - Verify everything works"
        echo -e "    ${CYAN}orchestrate.sh embrace${NC}       - Run full Double Diamond workflow"
        echo -e "    ${CYAN}orchestrate.sh auto <prompt>${NC} - Smart task routing"
        echo ""
    else
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}  🐙 Some tentacles need attention! Run setup again when ready.${NC}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
        echo ""
        return 1
    fi

    return 0
}

# Check if first run (setup not completed)
check_first_run() {
    if [[ ! -f "$SETUP_CONFIG_FILE" ]]; then
        # Check if any required component is missing
        if ! command -v codex &>/dev/null || \
           ! command -v gemini &>/dev/null || \
           [[ -z "${OPENAI_API_KEY:-}" ]] || \
           [[ -z "${GEMINI_API_KEY:-}" ]]; then
            echo ""
            echo -e "${YELLOW}🐙 First time? Run the setup wizard to get started:${NC}"
            echo -e "   ${CYAN}./scripts/orchestrate.sh setup${NC}"
            echo ""
            return 1
        fi
    fi
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# DOUBLE DIAMOND METHODOLOGY - Design Thinking Commands
# Octopus-themed commands for the four phases of Double Diamond
# ═══════════════════════════════════════════════════════════════════════════════

# Pre-flight dependency validation
preflight_check() {
    # 🐙 Checking if all 8 tentacles are properly attached...
    log INFO "Running pre-flight checks... 🐙"
    log INFO "Checking if all tentacles are attached..."
    local errors=0

    # Check Codex CLI (Tentacle #1-4: OpenAI arms)
    if ! command -v codex &>/dev/null; then
        log ERROR "Codex CLI not found. Install: npm install -g @openai/codex"
        log ERROR "  (That's tentacles 1-4 missing! We need those!)"
        ((errors++))
    else
        log DEBUG "Codex CLI: $(command -v codex)"
    fi

    # Check Gemini CLI (Tentacle #5-8: Google arms)
    if ! command -v gemini &>/dev/null; then
        log ERROR "Gemini CLI not found. Install: npm install -g @google/gemini-cli"
        log ERROR "  (That's tentacles 5-8 missing! Only half an octopus!)"
        ((errors++))
    else
        log DEBUG "Gemini CLI: $(command -v gemini)"
    fi

    # Check API keys
    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        log ERROR "OPENAI_API_KEY not set"
        ((errors++))
    else
        log DEBUG "OPENAI_API_KEY: set (${#OPENAI_API_KEY} chars)"
    fi

    # Support both GEMINI_API_KEY and GOOGLE_API_KEY (legacy) for Gemini CLI
    if [[ -z "${GEMINI_API_KEY:-}" && -n "${GOOGLE_API_KEY:-}" ]]; then
        export GEMINI_API_KEY="$GOOGLE_API_KEY"
        log DEBUG "Using GOOGLE_API_KEY as GEMINI_API_KEY (legacy fallback)"
    fi

    if [[ -z "${GEMINI_API_KEY:-}" ]]; then
        log WARN "GEMINI_API_KEY not set"
        log INFO "  (Tentacles 5-8 need authentication to grip!)"
        echo ""
        echo -e "${YELLOW}🐙 Gemini API key required for full functionality.${NC}"
        echo ""

        # Offer to open browser
        read -p "Open Google AI Studio to get an API key? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            local url="https://aistudio.google.com/apikey"
            log INFO "Opening $url in your browser..."
            if [[ "$OSTYPE" == "darwin"* ]]; then
                open "$url"
            elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
                xdg-open "$url" 2>/dev/null || sensible-browser "$url" 2>/dev/null
            fi
            echo ""
        fi

        # Prompt for key
        read -p "Enter your GEMINI_API_KEY (or press Enter to skip): " api_key
        if [[ -n "$api_key" ]]; then
            export GEMINI_API_KEY="$api_key"
            log INFO "GEMINI_API_KEY set for this session"
            echo ""
            echo -e "${GREEN}Tip:${NC} Add this to your shell profile for persistence:"
            echo "  export GEMINI_API_KEY=\"$api_key\""
            echo ""
        else
            log ERROR "GEMINI_API_KEY not provided - Gemini features will fail"
            ((errors++))
        fi
    else
        log DEBUG "GEMINI_API_KEY: set (${#GEMINI_API_KEY} chars)"
    fi

    # Check workspace
    if [[ ! -d "$WORKSPACE_DIR" ]]; then
        log WARN "Workspace not initialized. Running init..."
        init_workspace
    fi

    # Check for potentially conflicting plugins (informational only)
    local conflicts=0
    local claude_plugins_dir="$HOME/.claude/plugins"

    if [[ -d "$claude_plugins_dir/oh-my-claude-code" ]]; then
        log WARN "Detected: oh-my-claude-code (has own cost-aware routing)"
        ((conflicts++))
    fi

    if [[ -d "$claude_plugins_dir/claude-flow" ]]; then
        log WARN "Detected: claude-flow (may spawn competing subagents)"
        ((conflicts++))
    fi

    if [[ -d "$claude_plugins_dir/agents" ]] || [[ -d "$claude_plugins_dir/wshobson-agents" ]]; then
        log WARN "Detected: wshobson/agents (large context consumption)"
        ((conflicts++))
    fi

    if [[ $conflicts -gt 0 ]]; then
        log INFO "Found $conflicts potentially overlapping orchestrator(s)"
        log INFO "  Claude Octopus uses external CLIs, so conflicts are unlikely"
    fi

    if [[ $errors -gt 0 ]]; then
        log ERROR "$errors pre-flight check(s) failed"
        return 1
    fi

    log INFO "Pre-flight checks passed 🐙"
    echo -e "${GREEN}✓${NC} All 8 tentacles accounted for and ready to work!"
    return 0
}

# Synchronous agent execution (for sequential steps within phases)
run_agent_sync() {
    local agent_type="$1"
    local prompt="$2"
    local timeout_secs="${3:-120}"

    local cmd
    cmd=$(get_agent_command "$agent_type") || return 1

    # shellcheck disable=SC2086
    run_with_timeout "$timeout_secs" $cmd "$prompt" 2>/dev/null
}

# Phase 1: PROBE (Discover) - Parallel research with synthesis
# Like an octopus probing with multiple tentacles simultaneously
probe_discover() {
    local prompt="$1"
    local task_group
    task_group=$(date +%s)

    echo ""
    echo -e "${MAGENTA}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║  PROBE (Discover Phase) - Parallel Research               ║${NC}"
    echo -e "${MAGENTA}║  Extending all tentacles into the unknown...              ║${NC}"
    echo -e "${MAGENTA}║  Who knows what we'll find? 🐙                            ║${NC}"
    echo -e "${MAGENTA}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    log INFO "Phase 1: Parallel exploration with multiple perspectives"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would probe: $prompt"
        log INFO "[DRY-RUN] Would spawn 4 parallel research agents"
        return 0
    fi

    # Pre-flight validation
    preflight_check || return 1

    mkdir -p "$RESULTS_DIR" "$LOGS_DIR"

    # Research prompts from different angles
    local perspectives=(
        "Analyze the problem space: $prompt. Focus on understanding constraints, requirements, and user needs."
        "Research existing solutions and patterns for: $prompt. What has been done before? What worked, what failed?"
        "Explore edge cases and potential challenges for: $prompt. What could go wrong? What's often overlooked?"
        "Investigate technical feasibility and dependencies for: $prompt. What are the prerequisites?"
    )

    local pids=()
    for i in "${!perspectives[@]}"; do
        local perspective="${perspectives[$i]}"
        local agent="gemini"
        [[ $((i % 2)) -eq 0 ]] && agent="codex"

        spawn_agent "$agent" "$perspective" "probe-${task_group}-${i}" &
        pids+=($!)
        sleep 0.3
    done

    log INFO "Spawned ${#pids[@]} parallel research threads"

    # Wait for all to complete with progress
    local completed=0
    while [[ $completed -lt ${#pids[@]} ]]; do
        completed=0
        for pid in "${pids[@]}"; do
            if ! kill -0 "$pid" 2>/dev/null; then
                ((completed++))
            fi
        done
        echo -ne "\r${CYAN}Progress: $completed/${#pids[@]} research threads complete${NC}"
        sleep 2
    done
    echo ""

    # Intelligent synthesis
    synthesize_probe_results "$task_group" "$prompt"
}

# Synthesize probe results into insights
synthesize_probe_results() {
    local task_group="$1"
    local original_prompt="$2"
    local synthesis_file="${RESULTS_DIR}/probe-synthesis-${task_group}.md"

    log INFO "Synthesizing research findings..."

    # Gather all probe results
    local results=""
    local result_count=0
    for result in "$RESULTS_DIR"/probe-${task_group}-*.md; do
        [[ -f "$result" ]] || continue
        results+="$(cat "$result")\n\n---\n\n"
        ((result_count++))
    done

    if [[ $result_count -eq 0 ]]; then
        log WARN "No probe results found to synthesize"
        return 1
    fi

    # Use Gemini for intelligent synthesis
    local synthesis_prompt="Synthesize these research findings into a coherent discovery summary.

Original Question: $original_prompt

Identify:
1. Key insights and patterns across all perspectives
2. Conflicting perspectives that need resolution
3. Gaps in understanding that need more research
4. Recommended approach based on findings

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
    echo ""
    echo -e "${GREEN}✓${NC} Probe synthesis saved to: $synthesis_file"
    echo ""
}

# Phase 2: GRASP (Define) - Consensus building on approach
# The octopus grasps the core problem with coordinated tentacles
grasp_define() {
    local prompt="$1"
    local probe_results="${2:-}"
    local task_group
    task_group=$(date +%s)

    echo ""
    echo -e "${MAGENTA}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║  GRASP (Define Phase) - Consensus Building                ║${NC}"
    echo -e "${MAGENTA}║  Eight arms, one decision. Let's reach consensus. 🐙      ║${NC}"
    echo -e "${MAGENTA}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    log INFO "Phase 2: Building consensus on problem definition"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would grasp: $prompt"
        log INFO "[DRY-RUN] Would gather 3 perspectives and build consensus"
        return 0
    fi

    mkdir -p "$RESULTS_DIR"

    # Include probe context if available
    local context=""
    if [[ -n "$probe_results" && -f "$probe_results" ]]; then
        context="Previous research findings:\n$(cat "$probe_results")\n\n"
        log INFO "Using probe context from: $probe_results"
    fi

    # Multiple agents define the problem from their perspective
    log INFO "Gathering problem definitions from multiple perspectives..."

    local def1 def2 def3
    def1=$(run_agent_sync "codex" "Based on: $prompt\n${context}Define the core problem statement in 2-3 sentences. What is the essential challenge?" 120)
    def2=$(run_agent_sync "gemini" "Based on: $prompt\n${context}Define success criteria. How will we know when this is solved correctly? List 3-5 measurable criteria." 120)
    def3=$(run_agent_sync "gemini" "Based on: $prompt\n${context}Define constraints and boundaries. What are we NOT solving? What are hard limits?" 120)

    # Build consensus
    local consensus_file="${RESULTS_DIR}/grasp-consensus-${task_group}.md"

    log INFO "Building consensus from perspectives..."

    local consensus_prompt="Review these different problem definitions and create a unified problem statement.
Resolve any conflicts and synthesize the best elements from each.

Problem Statement Perspective:
$def1

Success Criteria Perspective:
$def2

Constraints Perspective:
$def3

Output a single, clear problem definition document with:
1. Problem Statement (2-3 sentences)
2. Success Criteria (bullet points)
3. Constraints & Boundaries
4. Recommended Approach"

    local consensus
    consensus=$(run_agent_sync "gemini" "$consensus_prompt" 180) || {
        consensus="[Auto-consensus failed - manual review required]\n\nProblem: $def1\n\nSuccess Criteria: $def2\n\nConstraints: $def3"
    }

    cat > "$consensus_file" << EOF
# GRASP Phase - Problem Definition Consensus
## Task: $prompt
## Generated: $(date)

$consensus

---
*Consensus built from multiple agent perspectives (task group: $task_group)*
EOF

    log INFO "Consensus document: $consensus_file"
    echo ""
    echo -e "${GREEN}✓${NC} Problem definition saved to: $consensus_file"
    echo ""
}

# Phase 3: TANGLE (Develop) - Enhanced map-reduce with validation
# Tentacles work together in a coordinated tangle of activity
tangle_develop() {
    local prompt="$1"
    local grasp_file="${2:-}"
    local task_group
    task_group=$(date +%s)

    echo ""
    echo -e "${MAGENTA}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║  TANGLE (Develop Phase) - Parallel Development            ║${NC}"
    echo -e "${MAGENTA}║  It looks messy, but trust us - there's method in the     ║${NC}"
    echo -e "${MAGENTA}║  tentacles. 🐙                                            ║${NC}"
    echo -e "${MAGENTA}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    log INFO "Phase 3: Parallel development with validation gates"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would tangle: $prompt"
        log INFO "[DRY-RUN] Would decompose into subtasks and execute in parallel"
        return 0
    fi

    mkdir -p "$RESULTS_DIR"

    # Load problem definition if available
    local context=""
    if [[ -n "$grasp_file" && -f "$grasp_file" ]]; then
        context="Problem Definition:\n$(cat "$grasp_file")\n\n"
        log INFO "Using grasp context from: $grasp_file"
    fi

    # Step 1: Decompose into validated subtasks
    log INFO "Step 1: Task decomposition..."
    local decompose_prompt="Decompose this task into 4-6 independent subtasks that can be executed in parallel.
Each subtask should be:
- Self-contained and independently verifiable
- Clear about inputs and expected outputs
- Assignable to either a coding agent [CODING] or reasoning agent [REASONING]

${context}Task: $prompt

Output as numbered list with [CODING] or [REASONING] prefix for each subtask."

    local subtasks
    subtasks=$(run_agent_sync "gemini" "$decompose_prompt" 120) || {
        log WARN "Decomposition failed, falling back to direct execution"
        spawn_agent "codex" "$prompt" "tangle-${task_group}-direct"
        wait
        return
    }

    echo -e "${CYAN}Decomposed into subtasks:${NC}"
    echo "$subtasks"
    echo ""

    # Step 2: Parallel execution with progress tracking
    log INFO "Step 2: Parallel execution..."
    local subtask_num=0
    local pids=()

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ ! "$line" =~ ^[0-9]+[\.\)] ]] && continue

        local subtask
        subtask=$(echo "$line" | sed 's/^[0-9]*[\.\)]\s*//')
        local agent="codex"
        [[ "$subtask" =~ \[REASONING\] ]] && agent="gemini"
        subtask=$(echo "$subtask" | sed 's/\[CODING\]\s*//; s/\[REASONING\]\s*//')

        spawn_agent "$agent" "$subtask" "tangle-${task_group}-${subtask_num}" &
        pids+=($!)
        ((subtask_num++))
    done <<< "$subtasks"

    log INFO "Spawned $subtask_num development threads"

    # Wait with progress monitoring
    local completed=0
    while [[ $completed -lt ${#pids[@]} ]]; do
        completed=0
        for pid in "${pids[@]}"; do
            if ! kill -0 "$pid" 2>/dev/null; then
                ((completed++))
            fi
        done
        echo -ne "\r${CYAN}Progress: $completed/${#pids[@]} subtasks complete${NC}"
        sleep 2
    done
    echo ""

    # Step 3: Validation gate
    log INFO "Step 3: Validation gate..."
    validate_tangle_results "$task_group" "$prompt"
}

# Validate tangle results with quality gate
# v3.0: Supports configurable threshold and loop-until-approved retry logic
validate_tangle_results() {
    local task_group="$1"
    local original_prompt="$2"
    local validation_file="${RESULTS_DIR}/tangle-validation-${task_group}.md"
    local quality_retry_count=0

    while true; do
        # Collect all results
        local results=""
        local success_count=0
        local fail_count=0
        FAILED_SUBTASKS=""  # Reset for this validation pass (string-based)

        for result in "$RESULTS_DIR"/tangle-${task_group}*.md; do
            [[ -f "$result" ]] || continue
            [[ "$result" == *validation* ]] && continue

            if grep -q "Status: SUCCESS" "$result" 2>/dev/null; then
                ((success_count++))
            else
                ((fail_count++))
                # Extract agent and prompt for retry (if loop-until-approved enabled)
                if [[ "$LOOP_UNTIL_APPROVED" == "true" ]]; then
                    local agent prompt_line
                    agent=$(grep "^# Agent:" "$result" 2>/dev/null | sed 's/# Agent: //')
                    prompt_line=$(grep "^# Prompt:" "$result" 2>/dev/null | sed 's/# Prompt: //')
                    if [[ -n "$agent" && -n "$prompt_line" ]]; then
                        FAILED_SUBTASKS="${FAILED_SUBTASKS}${agent}:${prompt_line}"$'\n'
                    fi
                fi
            fi
            results+="$(cat "$result")\n\n---\n\n"
        done

        # Quality gate check (using configurable threshold)
        local total=$((success_count + fail_count))
        local success_rate=0
        [[ $total -gt 0 ]] && success_rate=$((success_count * 100 / total))

        local gate_status="PASSED"
        local gate_color="${GREEN}"
        if [[ $success_rate -lt $QUALITY_THRESHOLD ]]; then
            gate_status="FAILED"
            gate_color="${RED}"
        elif [[ $success_rate -lt 90 ]]; then
            gate_status="WARNING"
            gate_color="${YELLOW}"
        fi

        # ═══════════════════════════════════════════════════════════════════════
        # CONDITIONAL BRANCHING - Quality gate decision tree
        # ═══════════════════════════════════════════════════════════════════════
        local quality_branch
        quality_branch=$(evaluate_quality_branch "$success_rate" "$quality_retry_count")

        case "$quality_branch" in
            proceed|proceed_warn)
                # Quality gate passed - continue to delivery
                ;;
            retry)
                # Retry failed tasks
                if [[ $quality_retry_count -lt $MAX_QUALITY_RETRIES ]]; then
                    ((quality_retry_count++))
                    echo ""
                    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
                    echo -e "${YELLOW}║  🐙 Branching: Retry Path (attempt $quality_retry_count/$MAX_QUALITY_RETRIES)                    ║${NC}"
                    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
                    log WARN "Quality gate at ${success_rate}%, below ${QUALITY_THRESHOLD}%. Retrying..."
                    retry_failed_subtasks "$task_group" "$quality_retry_count"
                    sleep 3
                    continue  # Re-validate
                else
                    log ERROR "Max retries ($MAX_QUALITY_RETRIES) exceeded. Proceeding with ${success_rate}%"
                fi
                ;;
            escalate)
                # Human decision required
                echo ""
                echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
                echo -e "${YELLOW}║  🐙 Branching: Escalate Path (human review)               ║${NC}"
                echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
                echo -e "${YELLOW}Quality gate FAILED. Manual review required.${NC}"
                echo -e "${YELLOW}Results at: ${RESULTS_DIR}/tangle-validation-${task_group}.md${NC}"
                read -p "Continue anyway? (y/n) " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log ERROR "User declined to continue after quality gate failure"
                    return 1
                fi
                ;;
            abort)
                # Abort workflow
                echo ""
                echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
                echo -e "${RED}║  🐙 Branching: Abort Path (quality gate failed)           ║${NC}"
                echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
                log ERROR "Quality gate FAILED with ${success_rate}%. Aborting workflow."
                return 1
                ;;
        esac

        # Write validation report
        cat > "$validation_file" << EOF
# TANGLE Phase Validation Report
## Task: $original_prompt
## Generated: $(date)

### Quality Gate: ${gate_status}
- Success Rate: ${success_rate}% (threshold: ${QUALITY_THRESHOLD}%)
- Successful: ${success_count}/${total} tentacles
- Failed: ${fail_count}/${total} tentacles
- Retry Attempts: ${quality_retry_count}/${MAX_QUALITY_RETRIES}

### Subtask Results
$results
EOF

        echo ""
        echo -e "${gate_color}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${gate_color}║  Quality Gate: ${gate_status} (${success_rate}% of tentacles succeeded)${NC}"
        echo -e "${gate_color}╚═══════════════════════════════════════════════════════════╝${NC}"

        if [[ "$gate_status" == "FAILED" ]]; then
            log WARN "Quality gate failed. Review failures before proceeding to delivery."
            echo -e "${RED}Review results at: $validation_file${NC}"
        fi

        log INFO "Validation complete: $validation_file"
        echo ""

        # Exit loop - validation complete
        break
    done

    # Return non-zero if gate failed (but don't exit)
    [[ "$gate_status" != "FAILED" ]]
}

# Phase 4: INK (Deliver) - Quality gates + final output
# The octopus inks the final solution with precision
ink_deliver() {
    local prompt="$1"
    local tangle_results="${2:-}"
    local task_group
    task_group=$(date +%s)

    echo ""
    echo -e "${MAGENTA}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║  INK (Deliver Phase) - Final Output                       ║${NC}"
    echo -e "${MAGENTA}║  Time to release the cloud of excellence! 🐙              ║${NC}"
    echo -e "${MAGENTA}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    log INFO "Phase 4: Finalizing delivery with quality checks"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would ink: $prompt"
        log INFO "[DRY-RUN] Would synthesize and deliver final output"
        return 0
    fi

    mkdir -p "$RESULTS_DIR"

    # Step 1: Pre-delivery quality checks
    log INFO "Step 1: Running quality checks..."

    local checks_passed=true

    # Check 1: Results exist
    if [[ -z "$(ls -A "$RESULTS_DIR"/*.md 2>/dev/null)" ]]; then
        log ERROR "No results found. Cannot deliver."
        return 1
    fi

    # Check 2: No critical failures from tangle phase
    if [[ -n "$tangle_results" && -f "$tangle_results" ]]; then
        if grep -q "Quality Gate: FAILED" "$tangle_results" 2>/dev/null; then
            log WARN "Development phase has failed quality gate. Proceeding with caution."
            checks_passed=false
        fi
    fi

    # Step 2: Synthesize final output
    log INFO "Step 2: Synthesizing final deliverable..."

    local all_results=""
    local result_count=0
    for result in "$RESULTS_DIR"/*.md; do
        [[ -f "$result" ]] || continue
        [[ "$result" == *aggregate* || "$result" == *delivery* ]] && continue
        all_results+="$(cat "$result")\n\n"
        ((result_count++))
        [[ $result_count -ge 10 ]] && break  # Limit context size
    done

    local synthesis_prompt="Create a polished final deliverable from these development results.

Structure the output as:
1. Executive Summary (2-3 sentences)
2. Key Deliverables (what was produced)
3. Implementation Details (technical specifics)
4. Next Steps / Recommendations
5. Known Limitations

Original task: $prompt

Results to synthesize:
$all_results"

    local delivery
    delivery=$(run_agent_sync "gemini" "$synthesis_prompt" 180) || {
        delivery="[Synthesis failed - raw results attached]\n\n$all_results"
    }

    # Step 3: Generate final document
    local delivery_file="${RESULTS_DIR}/delivery-${task_group}.md"

    cat > "$delivery_file" << EOF
# DELIVERY DOCUMENT
## Task: $prompt
## Generated: $(date)
## Status: $([[ "$checks_passed" == "true" ]] && echo "COMPLETE" || echo "PARTIAL - Review Required")

---

$delivery

---

## Quality Certification
- Pre-delivery checks: $([[ "$checks_passed" == "true" ]] && echo "PASSED" || echo "NEEDS REVIEW")
- Results synthesized: $result_count files
- Generated by: Claude Octopus Double Diamond
- Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

    log INFO "Delivery document: $delivery_file"
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Delivery complete!                                       ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo -e "Final document: ${CYAN}$delivery_file${NC}"
    echo ""
}

# EMBRACE - Full 4-phase Double Diamond workflow
# The octopus embraces the entire problem with all tentacles
# v3.0: Supports session recovery, autonomy checkpoints
embrace_full_workflow() {
    local prompt="$1"
    local task_group
    task_group=$(date +%s)
    local resume_from=""

    echo ""
    echo -e "${MAGENTA}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║  EMBRACE - Full Double Diamond Workflow                   ║${NC}"
    echo -e "${MAGENTA}║  Full octopus hug incoming! All 8 arms engaged. 🐙        ║${NC}"
    echo -e "${MAGENTA}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    log INFO "Starting complete Double Diamond workflow"
    log INFO "Task: $prompt"
    log INFO "Autonomy mode: $AUTONOMY_MODE"
    [[ "$LOOP_UNTIL_APPROVED" == "true" ]] && log INFO "Loop-until-approved: enabled"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would embrace: $prompt"
        log INFO "[DRY-RUN] Would run all 4 phases: probe → grasp → tangle → ink"
        return 0
    fi

    # Session recovery check
    if [[ "$RESUME_SESSION" == "true" ]] && check_resume_session; then
        resume_from=$(get_resume_phase)
        log INFO "Resuming from phase: $resume_from"
    else
        init_session "embrace" "$prompt"
    fi

    # Pre-flight validation
    if ! preflight_check; then
        log ERROR "Pre-flight check failed. Aborting workflow."
        return 1
    fi

    local workflow_dir="${RESULTS_DIR}/embrace-${task_group}"
    mkdir -p "$workflow_dir"

    # Track timing
    local start_time=$SECONDS
    local probe_synthesis grasp_consensus tangle_validation

    # Phase 1: PROBE (Discover)
    if [[ -z "$resume_from" || "$resume_from" == "null" ]]; then
        echo ""
        echo -e "${CYAN}[1/4] Starting PROBE phase (Discover)...${NC}"
        echo ""
        probe_discover "$prompt"
        probe_synthesis=$(ls -t "$RESULTS_DIR"/probe-synthesis-*.md 2>/dev/null | head -1)
        save_session_checkpoint "probe" "completed" "$probe_synthesis"
        handle_autonomy_checkpoint "probe" "completed"
        sleep 1
    else
        probe_synthesis=$(get_phase_output "probe")
        [[ -z "$probe_synthesis" ]] && probe_synthesis=$(ls -t "$RESULTS_DIR"/probe-synthesis-*.md 2>/dev/null | head -1)
        log INFO "Skipping probe phase (resuming)"
    fi

    # Phase 2: GRASP (Define)
    if [[ -z "$resume_from" || "$resume_from" == "null" || "$resume_from" == "probe" ]]; then
        echo ""
        echo -e "${CYAN}[2/4] Starting GRASP phase (Define)...${NC}"
        echo ""
        grasp_define "$prompt" "$probe_synthesis"
        grasp_consensus=$(ls -t "$RESULTS_DIR"/grasp-consensus-*.md 2>/dev/null | head -1)
        save_session_checkpoint "grasp" "completed" "$grasp_consensus"
        handle_autonomy_checkpoint "grasp" "completed"
        sleep 1
    else
        grasp_consensus=$(get_phase_output "grasp")
        [[ -z "$grasp_consensus" ]] && grasp_consensus=$(ls -t "$RESULTS_DIR"/grasp-consensus-*.md 2>/dev/null | head -1)
        log INFO "Skipping grasp phase (resuming)"
    fi

    # Phase 3: TANGLE (Develop)
    if [[ -z "$resume_from" || "$resume_from" == "null" || "$resume_from" == "probe" || "$resume_from" == "grasp" ]]; then
        echo ""
        echo -e "${CYAN}[3/4] Starting TANGLE phase (Develop)...${NC}"
        echo ""
        tangle_develop "$prompt" "$grasp_consensus"
        tangle_validation=$(ls -t "$RESULTS_DIR"/tangle-validation-*.md 2>/dev/null | head -1)

        # Check quality gate status for autonomy
        local tangle_status="completed"
        if grep -q "Quality Gate: FAILED" "$tangle_validation" 2>/dev/null; then
            tangle_status="warning"
        fi
        save_session_checkpoint "tangle" "$tangle_status" "$tangle_validation"
        handle_autonomy_checkpoint "tangle" "$tangle_status"
        sleep 1
    else
        tangle_validation=$(get_phase_output "tangle")
        [[ -z "$tangle_validation" ]] && tangle_validation=$(ls -t "$RESULTS_DIR"/tangle-validation-*.md 2>/dev/null | head -1)
        log INFO "Skipping tangle phase (resuming)"
    fi

    # Phase 4: INK (Deliver)
    echo ""
    echo -e "${CYAN}[4/4] Starting INK phase (Deliver)...${NC}"
    echo ""
    ink_deliver "$prompt" "$tangle_validation"
    save_session_checkpoint "ink" "completed" "$(ls -t "$RESULTS_DIR"/delivery-*.md 2>/dev/null | head -1)"

    # Mark session complete
    complete_session

    # Summary
    local duration=$((SECONDS - start_time))

    echo ""
    echo -e "${MAGENTA}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║  EMBRACE workflow complete!                               ║${NC}"
    echo -e "${MAGENTA}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Duration: ${duration}s"
    echo -e "Autonomy: ${AUTONOMY_MODE}"
    echo -e "Results: ${RESULTS_DIR}/"
    echo ""
    echo -e "${CYAN}Phase outputs:${NC}"
    [[ -n "$probe_synthesis" ]] && echo -e "  Probe:  $probe_synthesis"
    [[ -n "$grasp_consensus" ]] && echo -e "  Grasp:  $grasp_consensus"
    [[ -n "$tangle_validation" ]] && echo -e "  Tangle: $tangle_validation"
    echo -e "  Ink:    $(ls -t "$RESULTS_DIR"/delivery-*.md 2>/dev/null | head -1)"
    echo ""
}

show_status() {
    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}  Claude Octopus Status${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    if [[ ! -f "$PID_FILE" ]]; then
        echo -e "${YELLOW}No agents tracked. Workspace may need initialization.${NC}"
        echo "Run: $(basename "$0") init"
        return
    fi

    local running=0
    local total=0

    echo -e "${BLUE}Active Agents:${NC}"
    while IFS=: read -r pid agent task_id; do
        ((total++))
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "  ${GREEN}●${NC} PID $pid - $agent ($task_id) - RUNNING"
            ((running++))
        else
            echo -e "  ${RED}○${NC} PID $pid - $agent ($task_id) - COMPLETED"
        fi
    done < "$PID_FILE"

    echo ""
    echo -e "${BLUE}Summary:${NC} $running running / $total total"
    echo ""

    if [[ -d "$RESULTS_DIR" ]]; then
        local result_count
        result_count=$(find "$RESULTS_DIR" -name "*.md" -type f | wc -l | tr -d ' ')
        echo -e "${BLUE}Results:${NC} $result_count files in $RESULTS_DIR"
    fi

    echo ""
}

kill_agents() {
    local target="${1:-}"

    if [[ ! -f "$PID_FILE" ]]; then
        log WARN "No PID file found"
        return
    fi

    if [[ "$target" == "all" || -z "$target" ]]; then
        log INFO "Killing all tracked agents..."
        while IFS=: read -r pid agent task_id; do
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null && log INFO "Killed $agent ($pid)"
            fi
        done < "$PID_FILE"
        > "$PID_FILE"
    else
        log INFO "Killing agent: $target"
        while IFS=: read -r pid agent task_id; do
            if [[ "$pid" == "$target" || "$task_id" == "$target" ]]; then
                kill "$pid" 2>/dev/null && log INFO "Killed $agent ($pid)"
            fi
        done < "$PID_FILE"
    fi
}

clean_workspace() {
    log WARN "Cleaning workspace and killing all agents..."

    kill_agents "all"

    if [[ -d "$WORKSPACE_DIR" ]]; then
        rm -rf "${WORKSPACE_DIR:?}/results" "${WORKSPACE_DIR:?}/logs" "$PID_FILE"
        mkdir -p "$RESULTS_DIR" "$LOGS_DIR"
        log INFO "Workspace cleaned"
    fi
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--parallel) MAX_PARALLEL="$2"; shift 2 ;;
        -t|--timeout) TIMEOUT="$2"; shift 2 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -n|--dry-run) DRY_RUN=true; shift ;;
        -d|--dir) PROJECT_ROOT="$2"; shift 2 ;;
        -a|--autonomy) AUTONOMY_MODE="$2"; shift 2 ;;
        -q|--quality) QUALITY_THRESHOLD="$2"; shift 2 ;;
        -l|--loop) LOOP_UNTIL_APPROVED=true; shift ;;
        -R|--resume) RESUME_SESSION=true; shift ;;
        -Q|--quick) FORCE_TIER="trivial"; shift ;;
        -P|--premium) FORCE_TIER="premium"; shift ;;
        --tier) FORCE_TIER="$2"; shift 2 ;;
        --branch) FORCE_BRANCH="$2"; shift 2 ;;
        --on-fail) ON_FAIL_ACTION="$2"; shift 2 ;;
        -h|--help|help) usage ;;
        *) break ;;
    esac
done

# Handle autonomy mode aliases
if [[ "$AUTONOMY_MODE" == "loop-until-approved" ]]; then
    LOOP_UNTIL_APPROVED=true
fi

# Main command dispatch
COMMAND="${1:-help}"
shift || true

# Check for first-run on commands that need setup (skip for help/setup/preflight)
if [[ "$COMMAND" != "help" && "$COMMAND" != "setup" && "$COMMAND" != "preflight" && "$COMMAND" != "-h" && "$COMMAND" != "--help" ]]; then
    check_first_run || true  # Show hint but don't block
fi

case "$COMMAND" in
    # ═══════════════════════════════════════════════════════════════════════════
    # DOUBLE DIAMOND COMMANDS
    # ═══════════════════════════════════════════════════════════════════════════
    probe)
        [[ $# -lt 1 ]] && { log ERROR "Usage: probe <prompt>"; exit 1; }
        probe_discover "$*"
        ;;
    grasp)
        [[ $# -lt 1 ]] && { log ERROR "Usage: grasp <prompt> [probe-results-file]"; exit 1; }
        grasp_define "$1" "${2:-}"
        ;;
    tangle)
        [[ $# -lt 1 ]] && { log ERROR "Usage: tangle <prompt> [grasp-consensus-file]"; exit 1; }
        tangle_develop "$1" "${2:-}"
        ;;
    ink)
        [[ $# -lt 1 ]] && { log ERROR "Usage: ink <prompt> [tangle-validation-file]"; exit 1; }
        ink_deliver "$1" "${2:-}"
        ;;
    embrace)
        [[ $# -lt 1 ]] && { log ERROR "Usage: embrace <prompt>"; exit 1; }
        embrace_full_workflow "$*"
        ;;
    preflight)
        preflight_check
        ;;
    setup)
        setup_wizard
        ;;
    # ═══════════════════════════════════════════════════════════════════════════
    # CLASSIC COMMANDS
    # ═══════════════════════════════════════════════════════════════════════════
    init)
        init_workspace
        ;;
    spawn)
        [[ $# -lt 2 ]] && { log ERROR "Usage: spawn <agent> <prompt>"; exit 1; }
        spawn_agent "$1" "$2"
        ;;
    auto)
        [[ $# -lt 1 ]] && { log ERROR "Usage: auto <prompt>"; exit 1; }
        auto_route "$*"
        ;;
    parallel)
        parallel_execute "${1:-}"
        ;;
    fan-out|fanout)
        [[ $# -lt 1 ]] && { log ERROR "Usage: fan-out <prompt>"; exit 1; }
        fan_out "$*"
        ;;
    map-reduce|mapreduce)
        [[ $# -lt 1 ]] && { log ERROR "Usage: map-reduce <prompt>"; exit 1; }
        map_reduce "$*"
        ;;
    status)
        show_status
        ;;
    kill)
        kill_agents "${1:-all}"
        ;;
    clean)
        clean_workspace
        ;;
    aggregate)
        aggregate_results "${1:-}"
        ;;
    *)
        log ERROR "Unknown command: $COMMAND"
        echo ""
        usage
        ;;
esac
