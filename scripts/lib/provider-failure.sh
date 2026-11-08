#!/usr/bin/env bash
# Retry only diagnostics that explicitly describe recoverable provider failures.
octopus_provider_failure_classify() {
    local provider="$1" diagnostic="$2" login_pattern
    case "$provider" in
        codex*) login_pattern='not logged in|please (run )?codex login' ;;
        claude*) login_pattern='not logged in|please (run )?.*login|run /login' ;;
        agy*|gemini*|antigravity*) login_pattern='not logged in|login required|please authenticate' ;;
        *) login_pattern='not logged in|login required' ;;
    esac
    # Sandbox denials are execution failures, not recoverable login failures.
    if printf '%s\n' "$diagnostic" | grep -Eic '^[[:space:]]*(error: )?.*(sandbox.*(denied|not permitted)|operation not permitted|permission denied)' >/dev/null; then
        printf '%s\n' other
        return 0
    fi
    # Honor the watcher's terminal policy without triggering any watcher or login.
    if [[ -n "${OCTOPUS_QUOTA_PATTERN:-}" ]] &&
       printf '%s\n' "$diagnostic" | grep -E "$OCTOPUS_QUOTA_PATTERN" | grep -cv 'Retrying after' >/dev/null; then
        printf '%s\n' terminal
        return 0
    fi
    # Terminal and quota diagnostics win over a later transport/refresh line.
    if printf '%s\n' "$diagnostic" | grep -Eic "^[[:space:]]*((error|fatal|authentication error|auth error)(:|\\[)[[:space:]]*)?(incorrect api key|invalid authentication credentials|(you are )?not logged in|invalid[ _-]*(api[ _-]*)?key|api[ _-]*key (is )?(invalid|revoked)|revoked (api )?key|invalid credentials|credentials (denied|revoked)|authentication failed|login required|missing (login|credentials)|access denied|unauthorized|api[ _-]*key.*revoked|credentials? (are |were )?(invalid|denied|revoked)|$login_pattern)|invalid_api_key|QUOTA_EXHAUSTED|TerminalQuotaError|insufficient_quota|IneligibleTierError" >/dev/null; then
        printf '%s\n' terminal
        return 0
    fi
    if printf '%s\n' "$diagnostic" | grep -Eic '^[[:space:]]*((error|fatal|warning|warn)(:|\[)[[:space:]]*)?((oauth |access )?token expired.*(refreshing|refresh succeeded|retry)|token refresh (succeeded|temporarily unavailable|failed.*(timeout|temporar|connection))|((request|network|transport) (error: )?)?(ECONNRESET|ETIMEDOUT|EAI_AGAIN|connection reset by peer|temporary failure in name resolution)|HTTP (502|503|504)( |:|$))' >/dev/null; then
        printf '%s\n' retryable
    else
        printf '%s\n' other
    fi
}

# Succeed only for a recoverable classification; terminal auth and quota errors fail.
octopus_provider_failure_retryable() {
    [[ "$(octopus_provider_failure_classify "$@")" == retryable ]]
}
