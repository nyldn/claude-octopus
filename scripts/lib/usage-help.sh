#!/usr/bin/env bash
# Usage help functions extracted from orchestrate.sh
# Part of the lib/ decomposition wave
_usage_help_registry_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_usage_help_registry_dir}/provider-registry.sh" || { echo "usage-help: failed to load provider-registry.sh" >&2; return 1 2>/dev/null || exit 1; }
source "${_usage_help_registry_dir}/provider-policy.sh" || { echo "usage-help: failed to load provider-policy.sh" >&2; return 1 2>/dev/null || exit 1; }

# Override the legacy cost.sh renderer after it is sourced by orchestrate.sh.
# All interactive cost and usage reports now use one parser and pricing table.
generate_usage_report() {
    local format="${1:-table}"
    local helper="${_usage_help_registry_dir}/../helpers/usage-report.sh"
    if [[ ! -x "$helper" ]]; then
        if declare -f log >/dev/null 2>&1; then
            log ERROR "usage-report helper is unavailable: $helper"
        else
            printf '[ERROR] usage-report helper is unavailable: %s\n' "$helper" >&2
        fi
        return 1
    fi
    bash "$helper" --view costs --format "$format"
}

generate_zsh_completion() {
    cat << 'ZSH_COMPLETION'
#compdef orchestrate.sh claude-octopus
# Claude Octopus zsh completion
# Add to ~/.zshrc: eval "$(orchestrate.sh completion zsh)"

_claude_octopus() {
    local -a commands agents options

    commands=(
        'auto:Smart routing - AI chooses best approach'
        'embrace:Full 4-phase Double Diamond workflow'
        'research:Phase 1 - Parallel exploration (alias: probe)'
        'probe:Phase 1 - Parallel exploration'
        'define:Phase 2 - Consensus building (alias: grasp)'
        'grasp:Phase 2 - Consensus building'
        'develop:Phase 3 - Implementation (alias: tangle)'
        'tangle:Phase 3 - Implementation'
        'deliver:Phase 4 - Validation (alias: ink)'
        'ink:Phase 4 - Validation'
        'spawn:Run single agent directly'
        'fan-out:Same prompt to all agents'
        'map-reduce:Decompose, execute parallel, synthesize'
        'ralph:Iterate until completion'
        'iterate:Iterate until completion (alias: ralph)'
        'optimize:Auto-detect and route optimization tasks'
        'setup:Interactive configuration wizard'
        'init:Initialize workspace'
        'status:Show running agents or inspect a durable run'
        'explain:Explain a durable run without rerunning providers'
        'doctor:Run local environment and update diagnostics'
        'update-plugin:Explicitly update Octopus through the host plugin manager'
        'update-clis:Update external provider CLIs'
        'kill:Stop agents'
        'clean:Clean workspace'
        'aggregate:Combine results'
        'preflight:Validate dependencies'
        'cost:Show usage report'
        'cost-json:Export usage as JSON'
        'cost-csv:Export usage as CSV'
        'auth:Authentication management'
        'login:Login to OpenAI'
        'logout:Logout from OpenAI'
        'completion:Generate shell completion'
        'help:Show help'
    )

    agents=(
        'codex:GPT-5.6 Sol (frontier)'
        'codex-standard:GPT-5.6 Terra (balanced)'
        'codex-max:GPT-5.6 Sol (frontier)'
        'codex-mini:GPT-5.6 Luna (fast)'
        'codex-general:GPT-5.6 Terra (balanced)'
        'agy:Antigravity (Google seat)'
        'agy-research:Antigravity research mode'
        'codex-review:Code review mode'
    )

    _arguments -C \
        '-v[Verbose output]' \
        '--verbose[Verbose output]' \
        '-n[Dry run mode]' \
        '--dry-run[Dry run mode]' \
        '-Q[Use quick/cheap models]' \
        '--quick[Use quick/cheap models]' \
        '-P[Use premium models]' \
        '--premium[Use premium models]' \
        '-q[Quality threshold]:threshold:' \
        '--quality[Quality threshold]:threshold:' \
        '-p[Max parallel agents]:number:' \
        '--parallel[Max parallel agents]:number:' \
        '-t[Timeout per task]:seconds:' \
        '--timeout[Timeout per task]:seconds:' \
        '-a[Autonomy mode]:mode:(supervised semi-autonomous autonomous)' \
        '--autonomy[Autonomy mode]:mode:(supervised semi-autonomous autonomous)' \
        '--tier[Force tier]:tier:(trivial standard premium)' \
        '--no-personas[Disable agent personas]' \
        '-R[Resume session]' \
        '--resume[Resume session]' \
        '-h[Show help]' \
        '--help[Show help]' \
        '1:command:->command' \
        '*::arg:->args'

    case "$state" in
        command)
            _describe -t commands 'claude-octopus commands' commands
            ;;
        args)
            case "$words[1]" in
                spawn)
                    _describe -t agents 'agents' agents
                    ;;
                completion)
                    _values 'shell' bash zsh fish
                    ;;
                auth)
                    _values 'action' login logout status
                    ;;
                help)
                    _values 'topic' auto embrace research define develop deliver setup --full
                    ;;
            esac
            ;;
    esac
}

_claude_octopus "$@"
ZSH_COMPLETION
}

usage_command() {
    local cmd="$1"
    case "$cmd" in
        auto)
            cat << EOF
${YELLOW}auto${NC} - Smart routing (recommended for most tasks)

${YELLOW}Usage:${NC} $(basename "$0") auto <prompt>

Analyzes your prompt and automatically selects the best workflow:
  • Research tasks    → runs 'research' phase (parallel exploration)
  • Build tasks       → runs 'develop' + 'deliver' phases
  • Review tasks      → runs 'deliver' phase (validation)
  • Simple tasks      → single agent execution

${YELLOW}Examples:${NC}
  $(basename "$0") auto "research authentication patterns"
  $(basename "$0") auto "build a REST API for user management"
  $(basename "$0") auto "review this code for security issues"
  $(basename "$0") auto "fix the TypeScript errors"

${YELLOW}Options:${NC}
  -Q, --quick       Use faster/cheaper models
  -P, --premium     Use most capable models
  -v, --verbose     Show detailed progress
EOF
            ;;
        update-plugin)
            cat << EOF
${YELLOW}update-plugin${NC} - Explicitly update Claude Octopus through the active host

${YELLOW}Usage:${NC} $(basename "$0") update-plugin

Refreshes nyldn-plugins and Octopus through the supported Claude Code or Codex
plugin manager. This command performs network and package-manager work, so it
only runs when explicitly requested; SessionStart hooks and doctor diagnostics
never invoke it.

After Claude Code updates, run /reload-plugins or restart. For Codex, exit the
active session first, run this command from a separate terminal, and then start
Codex again. The updater refuses to replace files used by its own Codex session.
EOF
            ;;
        embrace)
            cat << EOF
${YELLOW}embrace${NC} - Full Double Diamond workflow

${YELLOW}Usage:${NC} $(basename "$0") embrace <prompt>

Runs all 4 phases of the Double Diamond methodology:
  1. ${CYAN}Research${NC}  - Parallel exploration from multiple perspectives
  2. ${CYAN}Define${NC}    - Build consensus on the problem/approach
  3. ${CYAN}Develop${NC}   - Implementation with quality validation
  4. ${CYAN}Deliver${NC}   - Final quality gates and output

Best for complex features that need thorough exploration.

${YELLOW}Examples:${NC}
  $(basename "$0") embrace "implement user authentication with OAuth"
  $(basename "$0") embrace "design and build a caching layer"
  $(basename "$0") embrace "create a payment processing system"

${YELLOW}Options:${NC}
  -q, --quality NUM    Quality threshold percentage (default: 75)
  --autonomy MODE      supervised|semi-autonomous|autonomous
  -v, --verbose        Show detailed progress
EOF
            ;;
        discover|research|probe)
            cat << EOF
${YELLOW}discover${NC} (aliases: research, probe) - Parallel exploration phase

${YELLOW}Usage:${NC} $(basename "$0") discover <prompt>

Sends your prompt to multiple AI agents in parallel, each exploring
from a different perspective. Results are synthesized into a
comprehensive research summary.

${YELLOW}Perspectives used:${NC}
  • Technical feasibility
  • Best practices & patterns
  • Potential challenges
  • Implementation approaches

${YELLOW}Examples:${NC}
  $(basename "$0") discover "What are the best caching strategies for APIs?"
  $(basename "$0") discover "How should we handle user authentication?"

${YELLOW}Output:${NC}
  Results saved to: ~/.claude-octopus/results/discover-synthesis-*.md
EOF
            ;;
        define|grasp)
            cat << EOF
${YELLOW}define${NC} (alias: grasp) - Consensus building phase

${YELLOW}Usage:${NC} $(basename "$0") define <prompt> [research-file]

Builds consensus on the problem definition and approach.
Optionally uses output from a previous 'research' phase.

${YELLOW}Examples:${NC}
  $(basename "$0") define "implement caching layer"
  $(basename "$0") define "implement caching" ./results/discover-synthesis-123.md

${YELLOW}Output:${NC}
  Results saved to: ~/.claude-octopus/results/define-consensus-*.md
EOF
            ;;
        develop|tangle)
            cat << EOF
${YELLOW}develop${NC} (alias: tangle) - Implementation phase

${YELLOW}Usage:${NC} $(basename "$0") develop <prompt> [define-file]

Implements the solution with built-in quality validation.
Uses a map-reduce pattern: decompose → parallel implement → validate → contextual code review.

${YELLOW}Quality Gates:${NC}
  • Tangle validation report checks subtask status and worktree evidence
  • Contextual code review compares the diff against the task contract/decomposition
  • severity=normal findings trigger a progress-supervised correction loop before delivery

${YELLOW}Environment:${NC}
  OCTOPUS_TANGLE_CODE_REVIEW=false              Skip contextual code review
  OCTOPUS_TANGLE_REVIEW_CORRECTION_MODE=unbounded Progress-supervised loop (default)
  OCTOPUS_TANGLE_TIMEOUT=1200                    Minimum positive implementer budget; TIMEOUT=0 stays unlimited
  OCTOPUS_TANGLE_REVIEW_CORRECTION_MODE=bounded   Opt into explicit round cap
  OCTOPUS_TANGLE_REVIEW_CORRECTION_ROUNDS=3       Bound count when mode=bounded
  OCTOPUS_TANGLE_CORRECTION_STALL_WINDOW=1800     Stop only after silence/no progress
  OCTOPUS_TANGLE_CORRECTION_HARD_CAP=10           Absolute round ceiling, both modes (0 disables)
  OCTOPUS_TANGLE_CORRECTION_POLL_SECS=30          Progress check cadence
  OCTOPUS_TANGLE_REVIEW_TARGET=working-tree     Review target passed to code-review
  OCTOPUS_TANGLE_INK=true                       Run optional ink/deliver after review passes

${YELLOW}Examples:${NC}
  $(basename "$0") develop "build the user authentication API"
  $(basename "$0") develop "implement caching" ./results/define-consensus-123.md

${YELLOW}Output:${NC}
  Results saved to: ~/.claude-octopus/results/develop-validation-*.md
EOF
            ;;
        deliver|ink)
            cat << EOF
${YELLOW}deliver${NC} (alias: ink) - Final validation and delivery phase

${YELLOW}Usage:${NC} $(basename "$0") deliver <prompt> [develop-file]

Final quality gates and output generation.
Reviews implementation, runs validation, produces deliverable.

${YELLOW}Examples:${NC}
  $(basename "$0") deliver "finalize the authentication system"
  $(basename "$0") deliver "ship it" ./results/develop-validation-123.md

${YELLOW}Output:${NC}
  Results saved to: ~/.claude-octopus/results/deliver-result-*.md
EOF
            ;;
        octopus-configure)
            cat << EOF
${YELLOW}octopus-configure${NC} - Interactive configuration wizard

${YELLOW}Usage:${NC} $(basename "$0") octopus-configure

Guides you through:
  1. Checking/installing dependencies (Codex CLI and supported tools)
  2. Configuring provider authentication, including Antigravity when available
  3. Setting up workspace
  4. Running a test command

Run this first if you're new to Claude Octopus!

${YELLOW}Alias:${NC} setup (deprecated, use octopus-configure)
EOF
            ;;
        setup)
            cat << EOF
${YELLOW}setup${NC} - ${RED}[DEPRECATED]${NC} Use 'octopus-configure' instead

${YELLOW}Usage:${NC} $(basename "$0") octopus-configure
EOF
            ;;
        optimize|optimise)
            cat << EOF
${YELLOW}optimize${NC} - Auto-detect and route optimization tasks

${YELLOW}Usage:${NC} $(basename "$0") optimize <prompt>

Automatically detects the type of optimization needed and routes to
the appropriate specialist agent.

${YELLOW}Supported Domains:${NC}
  • ${CYAN}Performance${NC}  - Speed, latency, throughput, memory
  • ${CYAN}Cost${NC}         - Cloud spend, budget, rightsizing
  • ${CYAN}Database${NC}     - Queries, indexes, slow queries
  • ${CYAN}Bundle${NC}       - Webpack, tree-shaking, code-splitting
  • ${CYAN}Accessibility${NC} - WCAG, screen readers, a11y
  • ${CYAN}SEO${NC}          - Meta tags, structured data, rankings
  • ${CYAN}Images${NC}       - Compression, formats, lazy loading

${YELLOW}Examples:${NC}
  $(basename "$0") optimize "My app is slow on mobile"
  $(basename "$0") optimize "Reduce our AWS bill"
  $(basename "$0") optimize "Fix slow database queries"
  $(basename "$0") optimize "Make the site accessible"
  $(basename "$0") optimize "Improve search rankings"

${YELLOW}Options:${NC}
  -v, --verbose     Show detailed progress
  -n, --dry-run     Preview without executing
EOF
            ;;
        auth)
            cat << EOF
${YELLOW}auth${NC} - Manage OpenAI authentication

${YELLOW}Usage:${NC} $(basename "$0") auth [login|logout|status]

${YELLOW}Commands:${NC}
  login     Authenticate with OpenAI via browser OAuth
  logout    Clear stored OAuth tokens
  status    Show current authentication status

${YELLOW}Examples:${NC}
  $(basename "$0") auth status     Check authentication
  $(basename "$0") login           Login to OpenAI
  $(basename "$0") logout          Logout from OpenAI

${YELLOW}Notes:${NC}
  • OAuth login requires the Codex CLI (npm install -g @openai/codex)
  • Alternative: Set OPENAI_API_KEY environment variable
EOF
            ;;
        completion)
            cat << EOF
${YELLOW}completion${NC} - Generate shell completion scripts

${YELLOW}Usage:${NC} $(basename "$0") completion [bash|zsh|fish]

${YELLOW}Installation:${NC}
  ${CYAN}Bash:${NC}   eval "\$($(basename "$0") completion bash)"
          Add to ~/.bashrc for persistence

  ${CYAN}Zsh:${NC}    eval "\$($(basename "$0") completion zsh)"
          Add to ~/.zshrc for persistence

  ${CYAN}Fish:${NC}   $(basename "$0") completion fish > ~/.config/fish/completions/orchestrate.sh.fish

${YELLOW}Features:${NC}
  • Tab completion for all commands
  • Agent name completion for spawn
  • Option completion with descriptions
  • Context-aware suggestions
EOF
            ;;
        init)
            cat << EOF
${YELLOW}init${NC} - Initialize Claude Octopus workspace

${YELLOW}Usage:${NC} $(basename "$0") init [--interactive|-i]

Sets up the workspace directory structure for results, logs, and configuration.

${YELLOW}Options:${NC}
  --interactive, -i    Run interactive setup wizard (recommended for first-time setup)

${YELLOW}Interactive Wizard Features:${NC}
  • Step-by-step API key configuration with validation
  • CLI tools verification (Codex, Antigravity)
  • Workspace location customization
  • Shell completion installation
  • Issue detection with fix instructions

${YELLOW}Examples:${NC}
  $(basename "$0") init                     # Quick init (creates directories only)
  $(basename "$0") init --interactive       # Full guided setup wizard
  $(basename "$0") init -i                  # Same as --interactive

${YELLOW}Created Structure:${NC}
  ~/.claude-octopus/
  ├── results/    # Output from workflows
  ├── logs/       # Execution logs
  └── tasks.json  # Example task file
EOF
            ;;
        config|configure|preferences)
            cat << EOF
${YELLOW}config${NC} - Update user preferences (v4.5)

${YELLOW}Usage:${NC} $(basename "$0") config

Re-run the preference wizard to update your settings without
going through the full setup process.

${YELLOW}What you can configure:${NC}
  • Primary use case (backend, frontend, UX, etc.)
  • Resource tier (Pro, Max 5x, Max 20x, API-only)
  • Model routing preferences

${YELLOW}These settings affect:${NC}
  • Default agent personas for your work type
  • Model selection (conservative vs. full power)
  • Cost optimization strategies

${YELLOW}Config file:${NC}
  ~/.claude-octopus/.user-config

${YELLOW}Examples:${NC}
  $(basename "$0") config              # Update preferences
  $(basename "$0") init --interactive  # Full setup (includes config)
EOF
            ;;
        review)
            cat << EOF
${YELLOW}review${NC} - Human-in-the-loop review queue (v4.4)

${YELLOW}Usage:${NC} $(basename "$0") review [subcommand] [args]

Manage pending reviews for quality-gated workflows. Items that fail
quality gates or need human approval are queued for review.

${YELLOW}Subcommands:${NC}
  list              List all pending reviews (default)
  approve <id>      Approve a review and log decision
  reject <id>       Reject with optional reason
  show <id>         View the output file for a review

${YELLOW}Examples:${NC}
  $(basename "$0") review                           # List pending reviews
  $(basename "$0") review approve review-1234567890 # Approve
  $(basename "$0") review reject review-1234567890 "Needs security fixes"
  $(basename "$0") review show review-1234567890    # View output

${YELLOW}Notes:${NC}
  • All decisions are logged to the audit trail
  • Use 'audit' command to view decision history
  • Reviews are stored in ~/.claude-octopus/review-queue.json
EOF
            ;;
        audit)
            cat << EOF
${YELLOW}audit${NC} - View audit trail of decisions (v4.4)

${YELLOW}Usage:${NC} $(basename "$0") audit [count] [filter]

Shows a log of all review decisions, approvals, rejections, and
workflow status changes. Essential for compliance and debugging.

${YELLOW}Arguments:${NC}
  count      Number of recent entries to show (default: 20)
  filter     Optional grep pattern to filter entries

${YELLOW}Examples:${NC}
  $(basename "$0") audit                  # Show last 20 entries
  $(basename "$0") audit 50               # Show last 50 entries
  $(basename "$0") audit 100 rejected     # Last 100, only rejections
  $(basename "$0") audit 20 probe         # Last 20, only probe phase

${YELLOW}Entry Format:${NC}
  Each entry shows: timestamp | action | phase | decision | reviewer

${YELLOW}Notes:${NC}
  • Audit log stored at ~/.claude-octopus/audit.log
  • Entries are JSON (one per line) for easy parsing
  • Integrates with CI/CD for compliance tracking
EOF
            ;;
        grapple)
            cat << EOF
${YELLOW}grapple${NC} - Adversarial debate between Codex and Antigravity

${YELLOW}Usage:${NC} $(basename "$0") grapple [--principles TYPE] <prompt>

Multi-round debate where Codex proposes, Antigravity critiques, and they
iterate until reaching consensus. Uses critique principles to guide
the review (security, performance, maintainability, etc.).

${YELLOW}Principles:${NC}
  general          General code quality critique (default)
  security         Security-focused review (vulnerabilities, attack vectors)
  performance      Performance optimization focus (speed, memory, efficiency)
  maintainability  Maintainability focus (readability, patterns, documentation)

${YELLOW}Examples:${NC}
  $(basename "$0") grapple "implement password reset"
  $(basename "$0") grapple --principles security "implement auth.ts"
  $(basename "$0") grapple --principles performance "optimize database queries"

${YELLOW}Workflow:${NC}
  Round 1: Codex proposes solution
  Round 2: Antigravity critiques with principles
  Round 3: Codex refines based on critique
  Synthesis: Both agents converge on final solution

${YELLOW}Output:${NC}
  Results saved to: ~/.claude-octopus/results/grapple-*.md
EOF
            ;;
        council)
            cat << EOF
${YELLOW}council${NC} - Multi-LLM council advice and gated implementation

${YELLOW}Usage:${NC} $(basename "$0") council [OPTIONS] <task>

${YELLOW}Options:${NC}
  --goal advice|decision|plan|implement|review
  --domain auto|architecture|product|security|business|research|docs
  --style balanced|adversarial|implementation|executive|red-team
  --depth quick|standard|deep
  --members auto|3|5|7
  --persona <name>[,<name>]
  --implement never|after-approval|plan-only
  --worktree auto|on|off
  --benchmark auto|on|off
  --providers auto|$(octo_council_default_providers)
  --max-cost <usd>
  --dry-run
  --json
  --output-dir <path>
EOF
            ;;
        squeeze|red-team)
            cat << EOF
${YELLOW}squeeze${NC} (alias: red-team) - Security testing workflow

${YELLOW}Usage:${NC} $(basename "$0") squeeze <prompt>

Four-phase security review where Blue Team implements, Red Team attacks,
Blue Team remediates, and validation confirms fixes.

${YELLOW}Phases:${NC}
  1. Blue Team   - Initial implementation/code review
  2. Red Team    - Attack simulation, vulnerability discovery
  3. Remediation - Blue Team fixes identified issues
  4. Validation  - Confirm vulnerabilities are resolved

${YELLOW}Examples:${NC}
  $(basename "$0") squeeze "review auth.ts for vulnerabilities"
  $(basename "$0") squeeze "security audit of payment processing"
  $(basename "$0") red-team "test API for SQL injection"

${YELLOW}Use Cases:${NC}
  • Security code reviews
  • Penetration testing simulations
  • Vulnerability discovery
  • Compliance validation

${YELLOW}Output:${NC}
  Results saved to: ~/.claude-octopus/results/squeeze-*.md
EOF
            ;;
        *)
            echo "Unknown command: $cmd"
            echo "Run '$(basename "$0") help --full' for all commands."
            exit 1
            ;;
    esac
    exit 0
}

usage_full() {
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

${GREEN}═══════════════════════════════════════════════════════════════════════════${NC}
${GREEN}ESSENTIALS (start here)${NC}
${GREEN}═══════════════════════════════════════════════════════════════════════════${NC}
  ${GREEN}auto${NC} <prompt>           Smart routing - AI chooses best approach
  ${GREEN}embrace${NC} <prompt>        Full 4-phase Double Diamond workflow
  ${GREEN}octopus-configure${NC}       Interactive configuration wizard

${YELLOW}═══════════════════════════════════════════════════════════════════════════${NC}
${YELLOW}DOUBLE DIAMOND PHASES${NC} (can be run individually)
${YELLOW}═══════════════════════════════════════════════════════════════════════════${NC}
  research <prompt>       Phase 1: Parallel exploration (alias: probe)
  define <prompt>         Phase 2: Consensus building (alias: grasp)
  develop <prompt>        Phase 3: Implementation + validation (alias: tangle)
  deliver <prompt>        Phase 4: Final quality gates (alias: ink)
  synthesize-probe [id]  Synthesize probe results (timeout recovery)

${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}
${CYAN}ADVANCED ORCHESTRATION${NC}
${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}
  spawn <agent> <prompt>  Run single agent directly
  fan-out <prompt>        Same prompt to all agents, collect results
  map-reduce <prompt>     Decompose → parallel execute → synthesize
  ralph <prompt>          Iterate until completion (ralph-wiggum pattern)
  parallel <tasks.json>   Execute task file in parallel

${GREEN}═══════════════════════════════════════════════════════════════════════════${NC}
${GREEN}OPTIMIZATION${NC} (v4.2) - Auto-detect and route optimization tasks
${GREEN}═══════════════════════════════════════════════════════════════════════════${NC}
  optimize <prompt>       Smart optimization routing (performance, cost, a11y, SEO...)

${MAGENTA}═══════════════════════════════════════════════════════════════════════════${NC}
${MAGENTA}KNOWLEDGE WORK${NC} (v6.0) - Research, consulting, and writing workflows
${MAGENTA}═══════════════════════════════════════════════════════════════════════════${NC}
  empathize <prompt>      UX research synthesis (personas, journey maps, pain points)
  advise <prompt>         Strategic consulting (market analysis, frameworks, business case)
  synthesize <prompt>     Literature review (research synthesis, gap analysis)
  knowledge-toggle        Toggle Knowledge Work Mode on/off

${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}
${BLUE}AUTHENTICATION${NC} (v4.2)
${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}
  auth [action]           Manage OpenAI authentication (login, logout, status)
  login                   Login to OpenAI via OAuth
  logout                  Logout from OpenAI

${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}
${CYAN}SHELL COMPLETION${NC} (v4.2)
${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}
  completion [shell]      Generate shell completion (bash, zsh, fish)

${MAGENTA}═══════════════════════════════════════════════════════════════════════════${NC}
${MAGENTA}WORKSPACE MANAGEMENT${NC}
${MAGENTA}═══════════════════════════════════════════════════════════════════════════${NC}
  init                    Initialize workspace
  init --interactive      Full guided setup (7 steps)
  config                  Update preferences (v4.5)
  status                  Show running agents
  status --run ID --json  Read a durable v10 run manifest
  explain --run ID        Explain terminal seat decisions offline
  agent-summary           Show current run provider status table
  kill [id|all]           Stop agents
  clean                   Clean workspace
  aggregate               Combine all results
  preflight               Validate dependencies
  doctor [updates]        Run local diagnostics (use 'doctor updates' for plugin freshness)
  update-plugin           Explicitly update Octopus through the active host

${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}
${BLUE}COST & USAGE REPORTING${NC} (v4.1)
${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}
  cost                    Show usage report (tokens, costs, by model/agent/phase)
  cost-json               Export usage as JSON
  cost-csv                Export usage as CSV
  cost-clear              Clear current session usage

${RED}═══════════════════════════════════════════════════════════════════════════${NC}
${RED}REVIEW & AUDIT${NC} (v4.4 - Human-in-the-loop)
${RED}═══════════════════════════════════════════════════════════════════════════${NC}
  review                  List pending reviews
  review approve <id>     Approve a pending review
  review reject <id>      Reject with reason
  review show <id>        View review output
  audit [count] [filter]  View audit trail (decisions log)

${YELLOW}Available Agents:${NC}
  codex           GPT-5.6 Sol          ${GREEN}Premium${NC} (frontier coding)
  codex-standard  GPT-5.6 Terra        Standard tier
  codex-mini      GPT-5.6 Luna         Quick/cheap tasks
  agy             Antigravity         Google research and design seat
  agy-research    Antigravity         Research-focused routing

${YELLOW}Common Options:${NC}
  -v, --verbose           Detailed output
  --debug                 Enable debug logging (very verbose)
  -n, --dry-run           Preview without executing
  -Q, --quick             Use cheaper/faster models
  -P, --premium           Use most capable models
  -q, --quality NUM       Quality threshold (default: $QUALITY_THRESHOLD)
  --autonomy MODE         supervised | semi-autonomous | autonomous

${YELLOW}Advanced Options:${NC}
  -p, --parallel NUM      Max parallel agents (default: $MAX_PARALLEL)
  -t, --timeout SECS      Timeout per task (default: $TIMEOUT)
  --tier LEVEL            Force tier: trivial|standard|premium
  --on-fail ACTION        auto|retry|escalate|abort
  --no-personas           Disable agent personas
  --skip-smoke-test       Skip provider smoke test (not recommended)
  -R, --resume            Resume interrupted session
  --ci                    CI/CD mode (non-interactive, JSON output)

${YELLOW}Visualization & Async:${NC}
  --async                 Enable async task management (better progress tracking)
  --tmux                  Enable tmux visualization (live agent output in panes)
  --no-async              Disable async mode
  --no-tmux               Disable tmux mode

${YELLOW}Examples:${NC}
  $(basename "$0") auto "build a login form"
  $(basename "$0") embrace "implement OAuth authentication"
  $(basename "$0") research "caching strategies for high-traffic APIs"
  $(basename "$0") develop "user management API" -P --autonomy supervised

${YELLOW}Environment:${NC}
  CLAUDE_OCTOPUS_WORKSPACE  Override workspace (default: ~/.claude-octopus)
  OCTOPUS_WORKFLOW_STATE_DIR Override project workflow state location (default: workspace/projects/<project-id>)
  OCTOPUS_PROJECT_PERSISTENCE Set true to opt into project-local .octo/ lifecycle files
  OPENAI_API_KEY            Codex CLI (or 'codex login' OAuth)
  COMMAND_CODE_API_KEY       Command Code CLI (or authenticated CLI session)
  AGY_AUTH_TOKEN            Antigravity CLI auth token (optional; launch plain 'agy' for browser sign-in)
  PERPLEXITY_API_KEY        Perplexity Sonar web search
  OPENROUTER_API_KEY        OpenRouter models
  QWEN_API_KEY              Qwen CLI (Coding-Plan: OPENAI_API_KEY + OPENAI_BASE_URL also works;
                            free OAuth tier was discontinued 2026-04-15)

${CYAN}https://github.com/nyldn/claude-octopus${NC}
EOF
    exit 0
}
