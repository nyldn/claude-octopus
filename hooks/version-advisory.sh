#!/usr/bin/env bash
# Claude Octopus — SessionStart Version Advisory (v9.29.0+)
#
# When the plugin version jumps between sessions, emit a ONE-LINE advisory
# so existing users find out about behavioral changes (e.g. role routing,
# default model shifts) without having to manually run /octo:setup.
#
# This hook:
#   1. Reads the current plugin version from .claude-plugin/plugin.json
#   2. Compares it to the `last_seen_version` stored in ~/.claude-octopus/state.json
#   3. If different (and not first-run), emits a one-line advisory referencing
#      the CHANGELOG entry for the target version
#   4. Updates `last_seen_version` in state.json
#   5. Stays silent on no-change or first-run (session-start-memory.sh handles first-run)
#
# Hook event: SessionStart (runs after session-start-memory.sh first-run gate)
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail
# EXIT trap — emits diagnostic stderr ONLY when the hook exits non-zero, so
# the Claude Code harness error "No stderr output" can never recur. EXIT (not
# ERR) avoids over-firing on intermediate `grep -o`/`cmd | ...` inside $() that
# the hook's logic already handles. See issue #313.
_octo_hook_exit() { local c=$?; if [[ $c -ne 0 ]]; then echo "[hook:$(basename "$0")] exit $c" >&2 2>/dev/null || true; fi; return 0; }
trap _octo_hook_exit EXIT


STATE_DIR="${OCTOPUS_STATE_DIR:-${HOME}/.claude-octopus}"
STATE_FILE="${STATE_DIR}/state.json"
SETUP_MARKER="${STATE_DIR}/.setup-complete"
PLUGIN_MANIFEST="${CLAUDE_PLUGIN_ROOT:-}/.claude-plugin/plugin.json"

# Progressive feature disclosure (scripts/lib/features.sh). Sourced defensively:
# this hook must never block or noisily fail a session, so a missing library just
# means the advisory keeps its pre-existing one-line form.
_HOOK_DIR="$(cd -P "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || _HOOK_DIR=""
for _feat_lib in \
    "${CLAUDE_PLUGIN_ROOT:-}/scripts/lib/features.sh" \
    "${_HOOK_DIR}/../scripts/lib/features.sh"
do
    if [[ -n "$_feat_lib" && -f "$_feat_lib" ]]; then
        # shellcheck source=../scripts/lib/features.sh
        source "$_feat_lib" 2>/dev/null || true
        break
    fi
done

# Silent exit on missing prereqs — never block session start
[[ ! -f "$PLUGIN_MANIFEST" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# First-run is handled by session-start-memory.sh — don't double-prompt
[[ ! -f "$SETUP_MARKER" ]] && exit 0

CURRENT_VERSION=$(jq -r '.version // "unknown"' "$PLUGIN_MANIFEST" 2>/dev/null || echo "unknown")
[[ "$CURRENT_VERSION" == "unknown" || -z "$CURRENT_VERSION" ]] && exit 0

# Read (or seed) last_seen_version
mkdir -p "$STATE_DIR"
if [[ ! -f "$STATE_FILE" ]]; then
    echo '{}' > "$STATE_FILE"
fi

LAST_SEEN=$(jq -r '.last_seen_version // empty' "$STATE_FILE" 2>/dev/null)

# Already up to date — stay quiet
if [[ "$LAST_SEEN" == "$CURRENT_VERSION" ]]; then
    exit 0
fi

# First time we're recording a version (not a real upgrade) — seed silently
if [[ -z "$LAST_SEEN" ]]; then
    TMP=$(mktemp "${STATE_FILE}.XXXXXX")
    jq --arg v "$CURRENT_VERSION" '. + {last_seen_version: $v}' "$STATE_FILE" > "$TMP" \
        && mv "$TMP" "$STATE_FILE"
    exit 0
fi

# Seed the disclosure watermark from the version the user is coming FROM, not the
# one they are moving to. Seeding from CURRENT_VERSION would place every feature
# shipped in this release below the watermark, so nothing would ever be offered.
FEATURE_LINE=""
if declare -f octo_features_seed_watermark >/dev/null 2>&1; then
    export OCTOPUS_STATE_DIR="$STATE_DIR"
    octo_features_seed_watermark "$LAST_SEEN" 2>/dev/null || true
    _actionable="$(octo_features_actionable_count 2>/dev/null || echo 0)"
    if [[ "$_actionable" =~ ^[0-9]+$ ]] && (( _actionable > 0 )); then
        _noun="features are"; [[ "$_actionable" == "1" ]] && _noun="feature is"
        _plural="s"; [[ "$_actionable" == "1" ]] && _plural=""

        # Pointing at a command is the weak form of this: users do not run
        # commands they have to remember, and they do not hand-edit env vars
        # either. A SessionStart hook cannot raise a picker itself, but the
        # context it injects is acted on by the assistant — the same mechanism
        # auto-router-inject.sh uses to trigger a Skill. So ask the assistant to
        # raise the picker on the first turn.
        #
        # Gated on three things, because an unwanted prompt is worse than a
        # missed one:
        #   - an interactive session (a cron/headless/remote run has nobody to
        #     answer, and prompting there burns or stalls the turn);
        #   - a remaining prompt budget for this version (an unanswered prompt
        #     leaves everything undecided, which would otherwise re-ask forever);
        #   - the assistant actually honouring the directive, which is advisory.
        # When any of those fails, the plain pointer below is still emitted, so
        # discoverability degrades rather than disappears.
        if declare -f octo_features_session_interactive >/dev/null 2>&1 \
           && octo_features_session_interactive \
           && octo_features_prompt_allowed "$CURRENT_VERSION"; then
            _offers="$(octo_features_prompt_manifest 2>/dev/null || true)"
            if [[ -n "$_offers" ]]; then
                octo_features_record_prompt_attempt "$CURRENT_VERSION" 2>/dev/null || true
                FEATURE_LINE="
<OCTOPUS-NEW-FEATURES>
This upgrade added ${_actionable} setting${_plural} the user has not chosen yet.
Each one is a real policy question, not an announcement.

Before doing anything else this session, call AskUserQuestion ONCE with one
question per feature below. Use each feature's own question text and its own
choices verbatim; do not invent options, and do not collapse them into a yes/no.
Keep each choice description's cost note, because that is what the choice turns
on.

The lines below are tab-separated:
  Q<TAB>id<TAB>question
  C<TAB>id<TAB>value<TAB>label<TAB>description

${_offers}

Record every answer, including any that picks the default:
  source \"\${CLAUDE_PLUGIN_ROOT:-.}/scripts/lib/features.sh\"
  octo_features_record <id> <chosen value> ${CURRENT_VERSION}

Recording is what stops the question being asked again, so record all of them.
Tell the user /octo:whats-new can change any of it later. Apply nothing they did
not pick. If their first message is urgent, answer it first and ask right after.
</OCTOPUS-NEW-FEATURES>"
            fi
        fi

        # Fallback pointer, also used when the picker is suppressed or spent.
        if [[ -z "$FEATURE_LINE" ]]; then
            FEATURE_LINE="
   ${_actionable} new ${_noun} available to enable: /octo:whats-new"
        fi
    fi
fi

# Version changed — advisory. Keep it to one or two lines, non-blocking. Emit a
# valid SessionStart hook-output object (bare text fails v2.1.178 validation); jq
# JSON-escapes the multi-line message.
jq -cn --arg ctx "🐙 Claude Octopus updated: ${LAST_SEEN} → ${CURRENT_VERSION}
   Review changes: /octo:setup (or see CHANGELOG for role routing / default model shifts).
   Opt out of new routing: export OCTOPUS_LEGACY_ROLES=1${FEATURE_LINE}" \
    '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'

# Persist new version so we don't advise again next session
TMP=$(mktemp "${STATE_FILE}.XXXXXX")
jq --arg v "$CURRENT_VERSION" '.last_seen_version = $v' "$STATE_FILE" > "$TMP" \
    && mv "$TMP" "$STATE_FILE"

exit 0
