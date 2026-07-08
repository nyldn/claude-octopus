#!/usr/bin/env bash
# completions.sh — Shell completion generation for Claude Octopus
#
# Functions: generate_shell_completion, generate_bash_completion, generate_fish_completion
#
# Extracted from orchestrate.sh (optimization sweep)
# Source-safe: no main execution block.

# ═══════════════════════════════════════════════════════════════════════════════
# v4.2 FEATURE: SHELL COMPLETION
# Generate bash/zsh completion scripts for Claude Octopus
# ═══════════════════════════════════════════════════════════════════════════════

generate_shell_completion() {
    local shell_type="${1:-bash}"

    case "$shell_type" in
        bash)
            generate_bash_completion
            ;;
        zsh)
            generate_zsh_completion
            ;;
        fish)
            generate_fish_completion
            ;;
        *)
            echo "Unsupported shell: $shell_type"
            echo "Supported: bash, zsh, fish"
            exit 1
            ;;
    esac
}

generate_bash_completion() {
    cat << 'BASH_COMPLETION'
# Claude Octopus bash completion
# Add to ~/.bashrc: eval "$(orchestrate.sh completion bash)"

_claude_octopus_completions() {
    local cur prev commands agents options
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Main commands
    commands="auto embrace research probe define grasp develop tangle deliver ink spawn fan-out map-reduce ralph iterate optimize setup init status kill clean aggregate preflight cost cost-json cost-csv cost-clear auth login logout completion help"

    # Agents for spawn command
    agents="codex codex-standard codex-max codex-mini codex-general codex-review"

    # Options
    options="-v --verbose -n --dry-run -Q --quick -P --premium -q --quality -p --parallel -t --timeout -a --autonomy -R --resume --no-personas --tier --branch --on-fail -h --help"

    case "$prev" in
        spawn)
            COMPREPLY=( $(compgen -W "$agents" -- "$cur") )
            return 0
            ;;
        --autonomy|-a)
            COMPREPLY=( $(compgen -W "supervised semi-autonomous autonomous" -- "$cur") )
            return 0
            ;;
        --tier)
            COMPREPLY=( $(compgen -W "trivial standard premium" -- "$cur") )
            return 0
            ;;
        --on-fail)
            COMPREPLY=( $(compgen -W "auto retry escalate abort" -- "$cur") )
            return 0
            ;;
        completion)
            COMPREPLY=( $(compgen -W "bash zsh fish" -- "$cur") )
            return 0
            ;;
        auth)
            COMPREPLY=( $(compgen -W "login logout status" -- "$cur") )
            return 0
            ;;
        help)
            COMPREPLY=( $(compgen -W "auto embrace research define develop deliver setup --full" -- "$cur") )
            return 0
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$options" -- "$cur") )
    else
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
    fi
}

complete -F _claude_octopus_completions orchestrate.sh
complete -F _claude_octopus_completions claude-octopus
BASH_COMPLETION
}

# [EXTRACTED to lib/usage-help.sh]

generate_fish_completion() {
    cat << 'FISH_COMPLETION'
# Claude Octopus fish completion
# Save to ~/.config/fish/completions/orchestrate.sh.fish

# Disable file completion by default
complete -c orchestrate.sh -f

# Main commands
complete -c orchestrate.sh -n "__fish_use_subcommand" -a "auto" -d "Smart routing - AI chooses best approach"
complete -c orchestrate.sh -n "__fish_use_subcommand" -a "embrace" -d "Full 4-phase Double Diamond workflow"
complete -c orchestrate.sh -n "__fish_use_subcommand" -a "research" -d "Phase 1 - Parallel exploration"
complete -c orchestrate.sh -n "__fish_use_subcommand" -a "probe" -d "Phase 1 - Parallel exploration"
complete -c orchestrate.sh -n "__fish_use_subcommand" -a "define" -d "Phase 2 - Consensus building"
complete -c orchestrate.sh -n "__fish_use_subcommand" -a "grasp" -d "Phase 2 - Consensus building"
complete -c orchestrate.sh -n "__fish_use_subcommand" -a "develop" -d "Phase 3 - Implementation"
complete -c orchestrate.sh -n "__fish_use_subcommand" -a "tangle" -d "Phase 3 - Implementation"
complete -c orchestrate.sh -n "__fish_use_subcommand" -a "deliver" -d "Phase 4 - Validation"
complete -c orchestrate.sh -n "__fish_use_subcommand" -a "ink" -d "Phase 4 - Validation"
complete -c orchestrate.sh -n "__fish_use_subcommand" -a "spawn" -d "Run single agent directly"
complete -c orchestrate.sh -n "__fish_use_subcommand" -a "fan-out" -d "Same prompt to all agents"
complete -c orchestrate.sh -n "__fish_use_subcommand" -a "map-reduce" -d "Decompose, execute, synthesize"
complete -c orchestrate.sh -n "__fish_use_subcommand" -a "ralph" -d "Iterate until completion"
complete -c orchestrate.sh -n "__fish_use_subcommand" -a "optimize" -d "Auto-detect optimization tasks"
complete -c orchestrate.sh -n "__fish_use_subcommand" -a "setup" -d "Interactive configuration"
complete -c orchestrate.sh -n "__fish_use_subcommand" -a "init" -d "Initialize workspace"
complete -c orchestrate.sh -n "__fish_use_subcommand" -a "status" -d "Show running agents"
complete -c orchestrate.sh -n "__fish_use_subcommand" -a "cost" -d "Show usage report"
complete -c orchestrate.sh -n "__fish_use_subcommand" -a "auth" -d "Authentication management"
complete -c orchestrate.sh -n "__fish_use_subcommand" -a "completion" -d "Generate shell completion"
complete -c orchestrate.sh -n "__fish_use_subcommand" -a "help" -d "Show help"

# Spawn agents
complete -c orchestrate.sh -n "__fish_seen_subcommand_from spawn" -a "codex codex-standard codex-max codex-mini codex-review"

# Completion shells
complete -c orchestrate.sh -n "__fish_seen_subcommand_from completion" -a "bash zsh fish"

# Auth actions
complete -c orchestrate.sh -n "__fish_seen_subcommand_from auth" -a "login logout status"

# Options
complete -c orchestrate.sh -s v -l verbose -d "Verbose output"
complete -c orchestrate.sh -s n -l dry-run -d "Dry run mode"
complete -c orchestrate.sh -s Q -l quick -d "Use quick/cheap models"
complete -c orchestrate.sh -s P -l premium -d "Use premium models"
complete -c orchestrate.sh -s q -l quality -d "Quality threshold" -r
complete -c orchestrate.sh -s p -l parallel -d "Max parallel agents" -r
complete -c orchestrate.sh -s t -l timeout -d "Timeout per task" -r
complete -c orchestrate.sh -s a -l autonomy -d "Autonomy mode" -ra "supervised semi-autonomous autonomous"
complete -c orchestrate.sh -l tier -d "Force tier" -ra "trivial standard premium"
complete -c orchestrate.sh -l no-personas -d "Disable agent personas"
complete -c orchestrate.sh -s R -l resume -d "Resume session"
complete -c orchestrate.sh -s h -l help -d "Show help"
FISH_COMPLETION
}
