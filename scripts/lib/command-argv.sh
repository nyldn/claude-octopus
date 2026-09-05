#!/usr/bin/env bash
# Safe argv serialization for the restricted commands emitted by dispatch.sh.

[[ -n "${_OCTOPUS_COMMAND_ARGV_LOADED:-}" ]] && return 0
_OCTOPUS_COMMAND_ARGV_LOADED=true

# Parse quoting and escaped whitespace without eval, expansion, or operator
# interpretation. The result is returned in OCTO_COMMAND_ARGV.
octo_dispatch_command_to_argv() {
    local command="${1-}" state=unquoted token="" char="" have_token=false
    local i=0 length=${#command}
    OCTO_COMMAND_ARGV=()

    [[ "$command" != *$'\n'* && "$command" != *$'\r'* ]] || return 2
    while [[ $i -lt $length ]]; do
        char="${command:$i:1}"
        case "$state" in
            unquoted)
                case "$char" in
                    [[:space:]])
                        if [[ "$have_token" == true ]]; then
                            OCTO_COMMAND_ARGV+=("$token")
                            token=""
                            have_token=false
                        fi
                        ;;
                    "'") state=single; have_token=true ;;
                    '"') state=double; have_token=true ;;
                    \\)
                        i=$((i + 1))
                        [[ $i -lt $length ]] || return 2
                        token="${token}${command:$i:1}"
                        have_token=true
                        ;;
                    *) token="${token}${char}"; have_token=true ;;
                esac
                ;;
            single)
                if [[ "$char" == "'" ]]; then
                    state=unquoted
                else
                    token="${token}${char}"
                fi
                ;;
            double)
                case "$char" in
                    '"') state=unquoted ;;
                    \\)
                        i=$((i + 1))
                        [[ $i -lt $length ]] || return 2
                        token="${token}${command:$i:1}"
                        ;;
                    *) token="${token}${char}" ;;
                esac
                ;;
        esac
        i=$((i + 1))
    done

    [[ "$state" == unquoted ]] || return 2
    if [[ "$have_token" == true ]]; then
        OCTO_COMMAND_ARGV+=("$token")
    fi
    [[ ${#OCTO_COMMAND_ARGV[@]} -gt 0 ]]
}

octo_dispatch_command_argv_json() {
    octo_dispatch_command_to_argv "${1-}" || return 2
    jq -cn --args '$ARGS.positional' -- "${OCTO_COMMAND_ARGV[@]}"
}
