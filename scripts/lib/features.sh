#!/usr/bin/env bash
# Sourced by hooks, commands and the orchestrator. Deliberately sets NO shell
# options: `set -e`/`set -o pipefail` in a sourced file leak into the caller and
# stay there after this file returns. Most callers here run probe code where a
# nonzero exit is normal.
#
# features.sh — progressive feature disclosure (manifest + user consent ledger).
#
# Problem this solves: users who installed an older version never discover
# features added later. The pre-existing mechanism was a one-line version
# advisory nobody acted on.
#
# Two pieces of state:
#
#   1. Manifest — `config/features.json`, checked into the repo. Declares each
#      disclosable feature: id, the version it landed in, the env var it sets,
#      and a named prerequisite check.
#   2. Ledger — `features_v1` in ~/.claude-octopus/state.json, per-user. Records
#      the decision the user made about each feature and at which version.
#
# The ledger key is version-namespaced (`features_v1`) from the first release
# that ships it. Once users have state.json entries in the wild, changing the
# shape needs a migration; a namespaced key makes that a read-both-write-new
# change instead of a guess about what an untagged blob meant.
#
# `model_defaults_v2: "accepted"` in state.json is the pre-existing precedent
# for a consent record (written by /octo:setup for the v9.29 routing change).
# It is deliberately left in place and NOT migrated into the ledger: it gates a
# different thing (role routing defaults, with an OCTOPUS_LEGACY_ROLES escape
# hatch) and rewriting it would invalidate consent users already gave.
#
# ── Decisions are policy choices, not on/off switches ────────────────────────
#
# Asking "enable this feature?" is the wrong question for most things worth
# asking about. The real question for Fable 5 is not whether it exists but how it
# should be used: never, for planning only, for planning and review, or strictly
# on demand. So a manifest entry declares `choices`, and the ledger stores the
# chosen value.
#
# `decision` controls whether a feature is raised at all:
#
#   required   needs a genuine policy choice; prompted once after an upgrade
#   none       ships silently with a sensible default; never prompted
#
# Most features should be `none`. A prompt is for a real fork in behaviour or
# cost, not for announcing that work happened. A release that adds ten internal
# improvements and one routing choice should ask exactly one question.
#
# A recorded choice is sticky: the feature is not raised again. Choosing the
# default value (e.g. "off") is a real decision and is recorded as such, which is
# what stops the picker from reappearing every upgrade. The single legitimate
# re-ask is a manifest `reoffer_at` version above the version at which the user
# chose, for a feature whose options have materially changed.

# Dependency note: this file deliberately does NOT source lib/providers.sh for
# its `version_compare`. providers.sh pulls in auth.sh, qwen.sh, grok.sh and
# openai-compatible.sh, which is far too much work for a SessionStart hook that
# must stay fast and silent. The local comparator below is intentionally small
# and, unlike providers.sh's, tolerates non-numeric version suffixes.

OCTOPUS_FEATURES_LEDGER_KEY="features_v1"

octo_features_state_dir() {
    printf '%s\n' "${OCTOPUS_STATE_DIR:-$HOME/.claude-octopus}"
}

octo_features_state_file() {
    printf '%s\n' "$(octo_features_state_dir)/state.json"
}

octo_features_manifest() {
    if [[ -n "${OCTOPUS_FEATURES_MANIFEST:-}" ]]; then
        printf '%s\n' "$OCTOPUS_FEATURES_MANIFEST"
        return 0
    fi
    # Search candidate roots in order and return the first that actually holds a
    # manifest. Two reasons this is a search rather than one computed path:
    #
    #   - CLAUDE_PLUGIN_ROOT routinely points at a stale cache directory for a
    #     version that is no longer installed (the "Plugin directory does not
    #     exist" hook error), so it must be probed, not trusted.
    #   - Deriving the repo root by traversing BASH_SOURCE relatively is not
    #     dependable: when this file is sourced by a relative path the traversal
    #     resolves against the caller's cwd and can land outside the repo.
    #
    # Falling through to the last candidate keeps the return value non-empty so
    # callers report a path in diagnostics rather than an empty string.
    local this_dir candidate
    this_dir="$(cd -P "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || this_dir=""
    for candidate in \
        "${CLAUDE_PLUGIN_ROOT:-}" \
        "${this_dir:+${this_dir}/../..}" \
        "$(git -C "${this_dir:-.}" rev-parse --show-toplevel 2>/dev/null)" \
        "$PWD"
    do
        [[ -n "$candidate" ]] || continue
        if [[ -f "${candidate}/config/features.json" ]]; then
            printf '%s\n' "$(cd -P "$candidate" 2>/dev/null && pwd)/config/features.json"
            return 0
        fi
    done
    printf '%s\n' "${this_dir}/../../config/features.json"
}

# Usable only when jq exists, the manifest parses, AND the ledger is either
# absent or valid JSON. Callers treat a nonzero return as "stay completely
# silent" rather than as an error to report: a broken manifest must never block a
# session or spam a hook advisory.
#
# The ledger check is what prevents the worst failure mode of this whole feature.
# A corrupt state.json makes every decision read come back empty, which looks
# identical to "never offered" — so disclosure would offer the same features
# every single session while also being unable to write the answer down. That is
# nagware with no way for the user to stop it. Refusing to run at all is the
# correct response to an unreadable ledger.
octo_features_available() {
    command -v jq >/dev/null 2>&1 || return 1
    local m f; m="$(octo_features_manifest)"
    [[ -f "$m" ]] || return 1
    jq -e '.features | type == "array"' "$m" >/dev/null 2>&1 || return 1
    f="$(octo_features_state_file)"
    if [[ -f "$f" ]]; then
        jq -e 'type == "object"' "$f" >/dev/null 2>&1 || return 1
    fi
    return 0
}

# _octo_feat_ver_gt <a> <b> — true when semver a > b. Missing components are 0.
# Non-numeric suffixes are stripped ("9.57.0-rc1" compares as 9.57.0) so a
# pre-release tag can never make an arithmetic context abort.
_octo_feat_ver_gt() {
    local a="${1:-0}" b="${2:-0}" i a_part b_part
    local -a A B
    IFS='.' read -r -a A <<< "$a"
    IFS='.' read -r -a B <<< "$b"
    for i in 0 1 2; do
        a_part="${A[$i]:-0}"; b_part="${B[$i]:-0}"
        a_part="${a_part//[^0-9]/}"; b_part="${b_part//[^0-9]/}"
        [[ -n "$a_part" ]] || a_part=0
        [[ -n "$b_part" ]] || b_part=0
        if (( a_part > b_part )); then return 0; fi
        if (( a_part < b_part )); then return 1; fi
    done
    return 1
}

# _octo_feat_field <id> <field> — one manifest field, empty if absent.
_octo_feat_field() {
    local id="$1" field="$2" m
    m="$(octo_features_manifest)"
    jq -r --arg id "$id" --arg f "$field" \
        '.features[] | select(.id == $id) | .[$f] // "" | tostring' \
        "$m" 2>/dev/null | head -1
    return 0
}

octo_features_all_ids() {
    jq -r '.features[].id' "$(octo_features_manifest)" 2>/dev/null || true
    return 0
}

octo_features_title()       { _octo_feat_field "$1" title; }
octo_features_question()    { _octo_feat_field "$1" question; }
octo_features_default()     { _octo_feat_field "$1" default; }

# Features that ship silently are never raised. This is the switch that keeps the
# session-start prompt down to the questions that genuinely need an answer.
octo_features_decision_required() {
    [[ "$(_octo_feat_field "$1" decision)" == "required" ]]
}

# One "value<TAB>label<TAB>description" line per choice.
octo_features_choices() {
    local id="$1"
    jq -r --arg id "$id" \
        '.features[] | select(.id == $id) | .choices // [] | .[]
         | [(.value // ""), (.label // ""), (.description // "")] | @tsv' \
        "$(octo_features_manifest)" 2>/dev/null || true
    return 0
}

octo_features_is_valid_choice() {
    local id="$1" value="$2" v
    [[ -n "$value" ]] || return 1
    while IFS=$'\t' read -r v _ _; do
        [[ "$v" == "$value" ]] && return 0
    done < <(octo_features_choices "$id")
    return 1
}
octo_features_description() { _octo_feat_field "$1" description; }
octo_features_key()         { _octo_feat_field "$1" key; }
octo_features_added_in()    { _octo_feat_field "$1" added_in; }
octo_features_prereq()      { _octo_feat_field "$1" prereq; }

# ── Ledger reads ─────────────────────────────────────────────────────────────

octo_features_decision() {
    local id="$1" f
    f="$(octo_features_state_file)"
    [[ -f "$f" ]] || return 0
    jq -r --arg k "$OCTOPUS_FEATURES_LEDGER_KEY" --arg id "$id" \
        '.[$k][$id].decision // ""' "$f" 2>/dev/null || true
    return 0
}

octo_features_decision_version() {
    local id="$1" f
    f="$(octo_features_state_file)"
    [[ -f "$f" ]] || return 0
    jq -r --arg k "$OCTOPUS_FEATURES_LEDGER_KEY" --arg id "$id" \
        '.[$k][$id].at_version // ""' "$f" 2>/dev/null || true
    return 0
}

# octo_features_choice <id> — the policy currently in force. Resolution order:
#   1. the feature's env key, when it holds a valid choice value (session override)
#   2. the recorded decision in the ledger
#   3. the manifest default
# Always echoes something, so callers can compare without a null case.
octo_features_choice() {
    local id="$1" key val recorded
    key="$(octo_features_key "$id")"
    if [[ -n "$key" ]]; then
        eval "val=\"\${${key}:-}\""
        if [[ -n "$val" ]]; then
            if octo_features_is_valid_choice "$id" "$val"; then
                printf '%s\n' "$val"; return 0
            fi
            # Boolean-shaped features (decision=none) have no choices list; pass
            # their env value through rather than silently ignoring it.
            if [[ -z "$(octo_features_choices "$id")" ]]; then
                printf '%s\n' "$val"; return 0
            fi
        fi
    fi
    recorded="$(octo_features_decision "$id")"
    if [[ -n "$recorded" ]]; then
        printf '%s\n' "$recorded"; return 0
    fi
    printf '%s\n' "$(octo_features_default "$id")"
    return 0
}

# Convenience for the boolean-shaped features: true unless the resolved choice
# reads as off. Policy features should compare octo_features_choice directly
# instead, since "which policy" is not answerable with a boolean.
octo_features_enabled() {
    case "$(octo_features_choice "$1")" in
        1|on|true|yes|enabled) return 0 ;;
        *) return 1 ;;
    esac
}

# Watermark: the version below which features are considered "already known".
# Falls back to the pre-existing last_seen_version, which version-advisory.sh
# has been tracking since v9.29.0 — that is what makes backfill bounded for
# existing users instead of offering them every feature ever shipped.
octo_features_watermark() {
    local f w
    f="$(octo_features_state_file)"
    [[ -f "$f" ]] || return 0
    w="$(jq -r '.features_watermark // ""' "$f" 2>/dev/null)" || w=""
    if [[ -z "$w" ]]; then
        w="$(jq -r '.last_seen_version // ""' "$f" 2>/dev/null)" || w=""
    fi
    printf '%s\n' "$w"
    return 0
}

# ── Prerequisite checks ──────────────────────────────────────────────────────
# Named rather than inline so the manifest stays declarative and CI can assert
# every `prereq` value resolves to a real check. Re-evaluated on every call and
# never cached, so installing a missing CLI later flips a feature to actionable
# without needing a version bump.
octo_features_prereq_ok() {
    case "${1:-none}" in
        none|"")           return 0 ;;
        codex-cli)         command -v codex >/dev/null 2>&1 ;;
        agy-cli)           command -v agy   >/dev/null 2>&1 ;;
        claude-opus-seat)  command -v claude >/dev/null 2>&1 ;;
        *)                 return 1 ;;   # unknown check: fail closed
    esac
}

# ── Offer logic ──────────────────────────────────────────────────────────────

# octo_features_is_offerable <id> — should the user be told about this feature?
# Independent of whether they *can* enable it (see prereq_ok); a feature whose
# prerequisite is missing is still listed, with the reason, because hiding it
# means the user never learns the prerequisite exists.
octo_features_is_offerable() {
    local id="$1" decision reoffer decided_at added_in watermark

    # Silent features are never raised, however new they are.
    octo_features_decision_required "$id" || return 1

    decision="$(octo_features_decision "$id")"
    case "$decision" in
        "")
            ;;
        *)
            # A recorded choice is sticky. The one legitimate re-ask is a
            # manifest reoffer_at above the version at which the user chose,
            # for a feature whose options have materially changed.
            reoffer="$(_octo_feat_field "$id" reoffer_at)"
            [[ -n "$reoffer" ]] || return 1
            decided_at="$(octo_features_decision_version "$id")"
            _octo_feat_ver_gt "$reoffer" "$decided_at"
            return $?
            ;;
    esac

    # No decision recorded. Backfill entries are offered once regardless of the
    # watermark; without them the framework would ship with an empty catalog on
    # the very release that introduces it.
    [[ "$(_octo_feat_field "$id" backfill)" == "true" ]] && return 0

    added_in="$(octo_features_added_in "$id")"
    watermark="$(octo_features_watermark)"
    # No watermark yet (genuinely fresh install): setup owns the conversation,
    # so nothing is "new" and nothing is offered.
    [[ -n "$watermark" ]] || return 1
    _octo_feat_ver_gt "$added_in" "$watermark"
}

# Returns 0 whenever it ran, regardless of how many ids it emitted. An empty
# offer list is the normal steady state, not a failure, and without the explicit
# return the status of the last loop iteration leaks out — so a caller running
# under `set -e` would abort simply because the final manifest entry happened to
# be already-decided.
octo_features_offerable_ids() {
    octo_features_available || return 0
    local id
    while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        if octo_features_is_offerable "$id"; then
            printf '%s\n' "$id"
        fi
    done < <(octo_features_all_ids)
    return 0
}

# Count only features the user could actually act on. The advisory uses this,
# not the raw offerable count: nagging about a feature whose CLI is not
# installed teaches the user to ignore the advisory.
octo_features_actionable_count() {
    octo_features_available || { printf '0\n'; return 0; }
    local id n=0
    while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        if octo_features_prereq_ok "$(octo_features_prereq "$id")"; then
            n=$((n + 1))
        fi
    done < <(octo_features_offerable_ids)
    printf '%s\n' "$n"
}

# ── Ledger writes ────────────────────────────────────────────────────────────

# octo_features_record <id> <decision> <version>
# Atomic tmp+mv, matching version-advisory.sh. Re-reads the file inside the same
# call so an interleaved write from the hook is merged rather than clobbered.
octo_features_record() {
    local id="$1" decision="$2" version="${3:-}"
    [[ -n "$id" && -n "$decision" ]] || return 1
    # Validate against the feature's own choices so a typo cannot record a
    # policy nothing reads. Features without a choices list (decision=none)
    # accept any non-empty value.
    if [[ -n "$(octo_features_choices "$id")" ]] \
       && ! octo_features_is_valid_choice "$id" "$decision"; then
        return 1
    fi
    command -v jq >/dev/null 2>&1 || return 1

    local dir f tmp
    dir="$(octo_features_state_dir)"; f="$dir/state.json"
    mkdir -p "$dir" 2>/dev/null || return 1
    [[ -f "$f" ]] || echo '{}' > "$f"

    tmp="$(mktemp "${f}.XXXXXX")" || return 1
    if jq --arg k "$OCTOPUS_FEATURES_LEDGER_KEY" \
          --arg id "$id" --arg d "$decision" --arg v "$version" \
          '.[$k] = ((.[$k] // {}) + {($id): {decision: $d, at_version: $v}})' \
          "$f" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$f"
        return 0
    fi
    rm -f "$tmp" 2>/dev/null
    return 1
}

# Seed the watermark from last_seen_version on first use, so existing users are
# offered only what landed after they last ran, plus backfill entries.
octo_features_seed_watermark() {
    command -v jq >/dev/null 2>&1 || return 1
    local dir f tmp seed
    dir="$(octo_features_state_dir)"; f="$dir/state.json"
    mkdir -p "$dir" 2>/dev/null || return 1
    [[ -f "$f" ]] || echo '{}' > "$f"

    if [[ -n "$(jq -r '.features_watermark // ""' "$f" 2>/dev/null)" ]]; then
        return 0
    fi
    seed="${1:-$(jq -r '.last_seen_version // ""' "$f" 2>/dev/null)}"
    [[ -n "$seed" ]] || return 0

    tmp="$(mktemp "${f}.XXXXXX")" || return 1
    if jq --arg v "$seed" '.features_watermark = $v' "$f" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$f"
        return 0
    fi
    rm -f "$tmp" 2>/dev/null
    return 1
}

# ── Interactive prompt budget ────────────────────────────────────────────────
# The SessionStart advisory can ask Claude to raise an interactive picker rather
# than printing a pointer to a command the user will never type. That is only
# safe with a hard cap.
#
# An unanswered prompt leaves every feature undecided, which is indistinguishable
# from "never offered", so the next session would ask again — forever, for a user
# who simply does not want to answer. The cap converts that into: ask a couple of
# times, then fall back permanently to the one-line advisory for this version.
#
# Attempts are scoped to a plugin version, so a later upgrade shipping genuinely
# new features gets a fresh budget instead of inheriting an exhausted one.
OCTOPUS_FEATURES_PROMPT_MAX=${OCTOPUS_FEATURES_PROMPT_MAX:-2}

octo_features_prompt_attempts() {
    local version="${1:-}" f recorded_version count
    f="$(octo_features_state_file)"
    [[ -f "$f" ]] || { printf '0\n'; return 0; }
    recorded_version="$(jq -r '.features_prompt_version // ""' "$f" 2>/dev/null)" || recorded_version=""
    # A different version means the budget resets.
    if [[ -n "$version" && "$recorded_version" != "$version" ]]; then
        printf '0\n'; return 0
    fi
    count="$(jq -r '.features_prompt_attempts // 0' "$f" 2>/dev/null)" || count=0
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    printf '%s\n' "$count"
    return 0
}

# True while the interactive picker is still within budget for this version.
octo_features_prompt_allowed() {
    local version="${1:-}" attempts
    [[ "$OCTOPUS_FEATURES_PROMPT_MAX" =~ ^[0-9]+$ ]] || return 1
    (( OCTOPUS_FEATURES_PROMPT_MAX > 0 )) || return 1
    attempts="$(octo_features_prompt_attempts "$version")"
    (( attempts < OCTOPUS_FEATURES_PROMPT_MAX ))
}

octo_features_record_prompt_attempt() {
    local version="${1:-}" f dir tmp attempts
    command -v jq >/dev/null 2>&1 || return 1
    dir="$(octo_features_state_dir)"; f="$dir/state.json"
    mkdir -p "$dir" 2>/dev/null || return 1
    [[ -f "$f" ]] || echo '{}' > "$f"
    attempts="$(octo_features_prompt_attempts "$version")"
    tmp="$(mktemp "${f}.XXXXXX")" || return 1
    if jq --arg v "$version" --argjson n "$(( attempts + 1 ))" \
          '.features_prompt_version = $v | .features_prompt_attempts = $n' \
          "$f" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$f"
        return 0
    fi
    rm -f "$tmp" 2>/dev/null
    return 1
}

# A session with no human cannot answer a picker. Prompting there burns a turn in
# a cron/headless run, or worse, stalls it. Detection mirrors the REMOTE_SESSION
# guard in hooks/session-start-memory.sh and adds the usual CI signals.
octo_features_session_interactive() {
    [[ "${CLAUDE_CODE_REMOTE:-}" == "true" ]] && return 1
    [[ "${CLAUDE_CODE_WEB:-}" == "true" ]] && return 1
    [[ "${OCTOPUS_REMOTE_SESSION:-false}" == "true" ]] && return 1
    [[ "${OCTOPUS_AUTONOMY:-}" == "autonomous" ]] && return 1
    [[ -n "${CI:-}" ]] && return 1
    [[ -n "${OCTOPUS_NON_INTERACTIVE:-}" ]] && return 1
    return 0
}

# Machine-readable question set for the SessionStart directive. One block per
# feature that needs a decision:
#
#   Q<TAB>id<TAB>question
#   C<TAB>id<TAB>value<TAB>label<TAB>description      (one per choice)
#
# Emitting the choices rather than just the feature name is what lets the picker
# ask "how should this be used" instead of "enable this?".
octo_features_prompt_manifest() {
    octo_features_available || return 0
    local id line value label desc
    while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        octo_features_prereq_ok "$(octo_features_prereq "$id")" || continue
        printf 'Q\t%s\t%s\n' "$id" "$(octo_features_question "$id")"
        while IFS=$'\t' read -r value label desc; do
            [[ -n "$value" ]] || continue
            printf 'C\t%s\t%s\t%s\t%s\n' "$id" "$value" "$label" "$desc"
        done < <(octo_features_choices "$id")
    done < <(octo_features_offerable_ids)
    return 0
}
