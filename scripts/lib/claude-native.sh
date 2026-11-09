#!/usr/bin/env bash
# Claude Code launch policy. Source-safe; no provider calls or settings writes.

if ! declare -f octo_version_ok >/dev/null 2>&1; then
    source "${BASH_SOURCE[0]%/*}/provider-versions.sh" || return 1
fi

# Print validated advisor arguments for the seat; reject unsupported opt-ins.
octo_claude_advisor_fragment() {
    local seat="${1:-}" requested="${OCTOPUS_CLAUDE_ADVISOR:-}" supported=false
    # This deliberately uses a documented version floor, not --help: Claude
    # hides --advisor from help. A version gate does not prove account access.
    if [[ "${CLAUDE_CODE_VERSION:-}" =~ ^2\.[0-9]+\.[0-9]+$ ]] &&
       octo_version_ok "$CLAUDE_CODE_VERSION" 2.1.260; then
        supported=true
    fi
    # Exact-model seats and fixed judges must not acquire additional model
    # consultations through either this setting or a saved advisor default.
    if [[ "${OCTOPUS_REFINEMENT_JUDGE:-false}" == true || "$seat" == *:* ]]; then
        [[ "$supported" == false ]] || printf '%s\n' '--advisor off'
        return 0
    fi
    [[ -n "$requested" ]] || return 0
    case "$requested" in
        off|opus|sonnet|fable) ;;
        claude-*)
            [[ "$requested" =~ ^claude-[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || {
                log ERROR 'Invalid OCTOPUS_CLAUDE_ADVISOR model ID'; return 1;
            } ;;
        *) log ERROR 'OCTOPUS_CLAUDE_ADVISOR requires off, opus, sonnet, fable or a Claude model ID'; return 1 ;;
    esac
    if [[ "$supported" != true ]]; then
        log ERROR 'OCTOPUS_CLAUDE_ADVISOR requires a detected Claude Code v2.1.260+ worker'
        return 1
    fi
    if [[ "$requested" != off ]]; then
        log WARN "Claude advisor requested: ${requested}. Claude decides whether to consult it; extra usage and cost are not capped or measured by Octopus."
    fi
    printf -- '--advisor %s\n' "$requested"
}
