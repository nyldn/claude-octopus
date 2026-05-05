#!/usr/bin/env bash
# Durable proof packet helpers.
#
# Proof packets are local-only run artifacts. They make escalated Octopus
# workflows auditable without turning the plugin into a full project manager.

octo_proof_enabled() {
    case "${OCTOPUS_PROOF_PACKET:-1}" in
        0|false|FALSE|off|OFF|no|NO) return 1 ;;
    esac
    command -v jq >/dev/null 2>&1
}

octo_proof_sanitize_id() {
    local raw="${1:-}"
    local sanitized
    sanitized=$(printf '%s' "$raw" \
        | tr '[:upper:]' '[:lower:]' \
        | tr -cs 'a-z0-9._-' '-' \
        | sed 's/^-//; s/-$//; s/--*/-/g')
    if [[ -z "$sanitized" ]]; then
        sanitized="run-$(date -u +%Y%m%dT%H%M%SZ)-$$"
    fi
    printf '%s\n' "$sanitized"
}

_octo_proof_now() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

_octo_proof_json_object() {
    local json="${1:-}"
    [[ -z "$json" ]] && json="{}"
    jq -c -n --arg value "$json" 'try ($value | fromjson) catch $value'
}

octo_proof_init() {
    local workflow="${1:-workflow}"
    local goal="${2:-}"
    local profile_json="${3:-}"
    [[ -z "$profile_json" ]] && profile_json="{}"

    octo_proof_enabled || return 1

    local run_id root run_dir started_at profile_value
    run_id=$(octo_proof_sanitize_id "${OCTOPUS_PROOF_RUN_ID:-${CLAUDE_CODE_SESSION:-${workflow}-$(date -u +%Y%m%dT%H%M%SZ)-$$}}")
    root="${OCTOPUS_PROOF_ROOT:-${HOME}/.claude-octopus/runs}"
    run_dir="${root}/${run_id}"
    started_at=$(_octo_proof_now)
    profile_value=$(_octo_proof_json_object "$profile_json")

    mkdir -p "$run_dir/artifacts"
    : > "$run_dir/proof.jsonl"

    jq -n \
        --arg workflow "$workflow" \
        --arg goal "$goal" \
        --arg run_id "$run_id" \
        --arg run_dir "$run_dir" \
        --arg started_at "$started_at" \
        --argjson profile "$profile_value" \
        '{
          schema: 1,
          run_id: $run_id,
          workflow: $workflow,
          goal: $goal,
          status: "running",
          started_at: $started_at,
          finished_at: null,
          run_dir: $run_dir,
          profile: $profile
        }' > "$run_dir/state.json"

    octo_proof_event "$run_dir" "started" "$(jq -n \
        --arg workflow "$workflow" \
        --arg goal "$goal" \
        --argjson profile "$profile_value" \
        '{workflow:$workflow, goal:$goal, profile:$profile}')"

    printf '%s\n' "$run_dir"
}

octo_proof_event() {
    local run_dir="$1"
    local type="$2"
    local data_json="${3:-}"
    [[ -z "$data_json" ]] && data_json="{}"

    [[ -n "$run_dir" && -d "$run_dir" ]] || return 0
    octo_proof_enabled || return 0

    local at
    at=$(_octo_proof_now)
    jq -c -n \
        --arg at "$at" \
        --arg type "$type" \
        --arg data "$data_json" \
        '{at:$at, type:$type, data:(try ($data | fromjson) catch $data)}' >> "$run_dir/proof.jsonl"
}

octo_proof_artifact() {
    local run_dir="$1"
    local kind="$2"
    local path="$3"
    local note="${4:-}"
    local exists="false"
    [[ -e "$path" ]] && exists="true"

    octo_proof_event "$run_dir" "artifact" "$(jq -n \
        --arg kind "$kind" \
        --arg path "$path" \
        --arg note "$note" \
        --argjson exists "$exists" \
        '{kind:$kind, path:$path, note:$note, exists:$exists}')"
}

octo_proof_command() {
    local run_dir="$1"
    local command_text="$2"
    local exit_code="${3:-0}"
    local output_ref="${4:-}"

    octo_proof_event "$run_dir" "command" "$(jq -n \
        --arg command "$command_text" \
        --arg output_ref "$output_ref" \
        --arg exit_code "$exit_code" \
        '{command:$command, exit_code:($exit_code|tonumber? // $exit_code), output_ref:$output_ref}')"
}

octo_proof_claim() {
    local run_dir="$1"
    local claim="$2"
    local claim_status="${3:-unverified}"
    local evidence="${4:-}"

    octo_proof_event "$run_dir" "claim" "$(jq -n \
        --arg claim "$claim" \
        --arg status "$claim_status" \
        --arg evidence "$evidence" \
        '{claim:$claim, status:$status, evidence:$evidence}')"
}

octo_proof_capture_provider_status() {
    local run_dir="$1"
    local status_file="$2"

    [[ -n "$run_dir" && -d "$run_dir" && -f "$status_file" ]] || return 0
    octo_proof_enabled || return 0

    while IFS='|' read -r provider provider_status detail; do
        [[ -z "${provider:-}" ]] && continue
        detail="${detail:-}"
        octo_proof_event "$run_dir" "provider_status" "$(jq -n \
            --arg provider "$provider" \
            --arg status "$provider_status" \
            --arg detail "$detail" \
            '{provider:$provider, status:$status, detail:$detail}')"

        case "$provider_status" in
            fallback|auth-failed)
                local replacement=""
                if [[ "$detail" == *"->"* ]]; then
                    replacement="${detail##*->}"
                    replacement="${replacement#"${replacement%%[![:space:]]*}"}"
                fi
                octo_proof_event "$run_dir" "provider_substitution" "$(jq -n \
                    --arg provider "$provider" \
                    --arg status "$provider_status" \
                    --arg detail "$detail" \
                    --arg replacement "$replacement" \
                    '{provider:$provider, status:$status, detail:$detail, replacement:$replacement}')"
                ;;
        esac
    done < "$status_file"
}

octo_proof_finalize() {
    local run_dir="$1"
    local verdict="${2:-unknown}"
    local summary="${3:-}"

    [[ -n "$run_dir" && -d "$run_dir" ]] || return 0
    octo_proof_enabled || return 0

    local finished_at state_file tmp_file
    finished_at=$(_octo_proof_now)
    state_file="$run_dir/state.json"
    tmp_file=$(mktemp "${TMPDIR:-/tmp}/octopus-proof-state.XXXXXX")

    if [[ -f "$state_file" ]]; then
        jq \
            --arg status "$verdict" \
            --arg summary "$summary" \
            --arg finished_at "$finished_at" \
            '.status = $status | .summary = $summary | .finished_at = $finished_at' \
            "$state_file" > "$tmp_file"
        mv "$tmp_file" "$state_file"
    else
        rm -f "$tmp_file"
    fi

    octo_proof_event "$run_dir" "finalized" "$(jq -n \
        --arg verdict "$verdict" \
        --arg summary "$summary" \
        '{verdict:$verdict, summary:$summary}')"

    {
        echo "# Octopus Proof Packet"
        echo ""
        jq -r '"Workflow: " + (.workflow // "unknown")' "$state_file" 2>/dev/null || echo "Workflow: unknown"
        echo "Verdict: $verdict"
        jq -r '"Run ID: " + (.run_id // "unknown")' "$state_file" 2>/dev/null || true
        jq -r '"Started: " + (.started_at // "unknown")' "$state_file" 2>/dev/null || true
        echo "Finished: $finished_at"
        jq -r '"Goal: " + (.goal // "")' "$state_file" 2>/dev/null || true
        echo ""
        echo "Summary: $summary"
        echo ""
        echo "## Artifacts"
        jq -r '
          select(.type == "artifact")
          | "- " + (.data.kind // "artifact") + ": " + (.data.path // "") +
            (if (.data.note // "") != "" then " (" + .data.note + ")" else "" end)
        ' "$run_dir/proof.jsonl" 2>/dev/null || true
        echo ""
        echo "## Provider Substitutions"
        jq -r '
          select(.type == "provider_substitution")
          | "- " + (.data.provider // "provider") + ": " + (.data.status // "unknown") +
            (if (.data.detail // "") != "" then " - " + .data.detail else "" end)
        ' "$run_dir/proof.jsonl" 2>/dev/null || true
        echo ""
        echo "Raw events: $run_dir/proof.jsonl"
    } > "$run_dir/summary.md"
}
