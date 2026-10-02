#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"

log() { :; }

export OCTOPUS_CONFIG_DIR="$TEST_TMP_DIR/probe-web-research-allowlist-root"
unset CLAUDE_CODE_SESSION_ID OCTO_ALLOWED_PROVIDERS PERPLEXITY_API_KEY

# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/provider-allowlist.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/workflows.sh"

test_suite "Probe web research seat honors the provider allowlist"

test_case "deep probe with a Perplexity key and no allowlist seats web research"
if PERPLEXITY_API_KEY="fixture-key" probe_web_research_seat_enabled deep; then
    test_pass
else
    test_fail "web research seat should be enabled when no allowlist is set"
fi

test_case "deep probe skips web research when the allowlist excludes perplexity"
if ! OCTO_ALLOWED_PROVIDERS="codex claude" PERPLEXITY_API_KEY="fixture-key" probe_web_research_seat_enabled deep; then
    test_pass
else
    test_fail "allowlist 'codex claude' must keep the perplexity seat out of probe"
fi

test_case "deep probe seats web research when the allowlist includes perplexity"
if OCTO_ALLOWED_PROVIDERS="codex perplexity" PERPLEXITY_API_KEY="fixture-key" probe_web_research_seat_enabled deep; then
    test_pass
else
    test_fail "allowlist naming perplexity should keep the web research seat"
fi

test_case "standard probe never seats web research"
if ! PERPLEXITY_API_KEY="fixture-key" probe_web_research_seat_enabled standard; then
    test_pass
else
    test_fail "web research seat is deep-only"
fi

test_case "deep probe without a Perplexity key never seats web research"
if ! probe_web_research_seat_enabled deep; then
    test_pass
else
    test_fail "web research seat requires PERPLEXITY_API_KEY"
fi

test_case "probe_discover gates the perplexity seat through the allowlist-aware helper"
if grep -B4 'probe_agents+=("perplexity")' "$PROJECT_ROOT/scripts/lib/workflows.sh" \
    | grep -q 'probe_web_research_seat_enabled "\$research_intensity"'; then
    test_pass
else
    test_fail "probe_discover must add the perplexity seat only via probe_web_research_seat_enabled"
fi

test_summary
