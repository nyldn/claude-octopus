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
# Models (Jan 2026):
# - OpenAI GPT-5.x: gpt-5.2-codex, gpt-5.1-codex-max, gpt-5.1-codex-mini, gpt-5.2
# - Google Gemini 3.0: gemini-3-pro-preview, gemini-3-flash-preview, gemini-3-pro-image-preview
get_agent_command() {
    local agent_type="$1"
    case "$agent_type" in
        codex) echo "codex exec -m gpt-5.2-codex" ;;
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
AVAILABLE_AGENTS="codex codex-max codex-mini codex-general gemini gemini-fast gemini-image codex-review"

# Task classification for contextual agent routing
# Returns: coding|research|design|copywriting|image|review|general
# Order matters! More specific patterns checked first.
classify_task() {
    local prompt="$1"
    local prompt_lower
    prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')

    # Image generation keywords (highest priority - very specific)
    if [[ "$prompt_lower" =~ (generate|create|make|draw|render).*(image|picture|photo|illustration|graphic|icon|logo|banner|visual|artwork) ]] || \
       [[ "$prompt_lower" =~ (image|picture|photo|illustration|graphic|icon|logo|banner).*generat ]] || \
       [[ "$prompt_lower" =~ (visualize|depict|illustrate|sketch) ]] || \
       [[ "$prompt_lower" =~ (dall-?e|midjourney|stable.?diffusion|imagen|text.?to.?image) ]]; then
        echo "image"
        return
    fi

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

# Default settings
MAX_PARALLEL=3
TIMEOUT=300
VERBOSE=false
DRY_RUN=false

usage() {
    cat << EOF
${MAGENTA}
   ___  ___ _____  ___  ____  _   _ ___
  / _ \/ __|_   _|/ _ \|  _ \| | | / __|
 | (_) |__ \ | | | (_) | |_) | |_| \__ \\
  \___/|___/ |_|  \___/|____/ \___/|___/
${NC}
${CYAN}Claude Octopus${NC} - Multi-Agent Orchestrator for Claude Code
Coordinates Codex CLI and Gemini CLI for parallel task execution.

${YELLOW}Usage:${NC} $(basename "$0") [OPTIONS] COMMAND [ARGS...]

${YELLOW}Commands:${NC}
  init                    Initialize workspace for parallel execution
  spawn <agent> <prompt>  Spawn a single agent with given prompt
  auto <prompt>           Auto-route prompt to best agent based on task type
  parallel <tasks-file>   Execute tasks from JSON file in parallel
  fan-out <prompt>        Send same prompt to all agents, collect results
  map-reduce <prompt>     Decompose task, map to agents, reduce results
  status                  Show status of running agents
  kill [agent-id|all]     Kill running agent(s)
  clean                   Clean workspace and kill all agents
  help                    Show this help message

${YELLOW}Available Agents:${NC}
  codex         GPT-5.2-Codex       Complex code generation, refactoring
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

${YELLOW}Examples:${NC}
  # Auto-route to best agent
  $(basename "$0") auto "Generate a hero image for the landing page"
  $(basename "$0") auto "Implement user authentication"
  $(basename "$0") auto "Review the auth module for security issues"

  # Spawn specific agent
  $(basename "$0") spawn codex "Fix the TypeScript errors in src/components"

  # Fan-out to multiple agents
  $(basename "$0") fan-out "Review the authentication flow for security issues"

  # Map-reduce complex task
  $(basename "$0") map-reduce "Refactor all API routes to use consistent error handling"

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

    local task_type
    task_type=$(classify_task "$prompt")

    local agent
    agent=$(get_agent_for_task "$task_type")

    echo ""
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}  Claude Octopus - Contextual Agent Routing${NC}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BLUE}Task Analysis:${NC}"
    echo -e "  Prompt: ${prompt:0:80}..."
    echo -e "  Detected Type: ${GREEN}$task_type${NC}"
    echo -e "  Selected Agent: ${GREEN}$agent${NC}"
    echo ""

    case "$task_type" in
        image)
            echo -e "${YELLOW}Image Generation Task${NC}"
            echo "  Using gemini-3-pro-image-preview for text-to-image generation."
            echo "  Supports: text-to-image, image editing, multi-turn editing"
            echo "  Output: Up to 4K resolution images"
            ;;
        review)
            echo -e "${YELLOW}Code Review Task${NC}"
            echo "  Using gpt-5.2-codex in review mode for thorough code analysis."
            echo "  Focus: Security, performance, best practices, bugs"
            ;;
        coding)
            echo -e "${YELLOW}Coding/Implementation Task${NC}"
            echo "  Using gpt-5.2-codex for complex code generation and refactoring."
            echo "  State-of-the-art on SWE-Bench Pro benchmarks"
            ;;
        design)
            echo -e "${YELLOW}Design/UI/UX Task${NC}"
            echo "  Using gemini-3-pro-preview for design reasoning and analysis."
            echo "  Strong at: Component patterns, accessibility, design systems"
            ;;
        copywriting)
            echo -e "${YELLOW}Copywriting Task${NC}"
            echo "  Using gemini-3-pro-preview for creative content generation."
            echo "  Strong at: Marketing copy, tone adaptation, messaging"
            ;;
        research)
            echo -e "${YELLOW}Research/Analysis Task${NC}"
            echo "  Using gemini-3-pro-preview for deep analysis and synthesis."
            echo "  1M token context window for comprehensive analysis"
            ;;
        *)
            echo -e "${YELLOW}General Task${NC}"
            echo "  Using codex as default for general-purpose tasks."
            ;;
    esac
    echo ""

    log INFO "Routing to $agent agent (task type: $task_type)"

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
        -h|--help|help) usage ;;
        *) break ;;
    esac
done

# Main command dispatch
COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
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
