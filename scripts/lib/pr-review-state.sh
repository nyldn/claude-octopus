#!/usr/bin/env bash
# Round-aware PR review state helpers.
#
# State is intentionally local-only. It lets repeated /octo:review runs on the
# same PR compare current findings with the previous run without changing the
# public finding contract emitted by review.sh.

pr_review_state_enabled() {
    case "${OCTOPUS_PR_HISTORY:-1}" in
        0|false|FALSE|off|OFF|no|NO) return 1 ;;
    esac
    command -v jq >/dev/null 2>&1
}

pr_review_state_path() {
    local host="$1"
    local repo="$2"
    local pr_number="$3"
    printf '%s/.claude-octopus/pr-state/%s/%s/%s.json\n' "$HOME" "$host" "$repo" "$pr_number"
}

pr_review_state_validate() {
    local state_file="$1"
    [[ -f "$state_file" ]] || return 1
    jq -e '.schema == 1 and (.rounds | type == "array") and (.pr | type == "object")' "$state_file" >/dev/null 2>&1
}

pr_review_state_next_round() {
    local state_file="$1"
    if ! pr_review_state_validate "$state_file"; then
        echo "1"
        return 0
    fi
    jq -r '([.rounds[].n] | max // 0) + 1' "$state_file" 2>/dev/null || echo "1"
}

pr_review_state_previous_round() {
    local state_file="$1"
    pr_review_state_validate "$state_file" || return 1
    jq -c '.rounds[-1] // empty' "$state_file"
}

pr_review_state_append_round() {
    local state_file="$1"
    local host="$2"
    local repo="$3"
    local pr_number="$4"
    local head_sha="$5"
    local providers_json="$6"
    local findings_json="$7"
    local classification_json="$8"

    mkdir -p "$(dirname "$state_file")"

    local base_json
    if pr_review_state_validate "$state_file"; then
        base_json=$(cat "$state_file")
    else
        base_json=$(jq -n \
            --arg host "$host" \
            --arg repo "$repo" \
            --arg pr "$pr_number" \
            '{schema:1, pr:{host:$host, repo:$repo, number:($pr|tonumber? // $pr)}, rounds:[]}')
    fi

    local round_n
    round_n=$(printf '%s' "$base_json" | jq -r '([.rounds[].n] | max // 0) + 1')

    local written_at
    written_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local tmp_file
    tmp_file=$(mktemp "${TMPDIR:-/tmp}/octopus-pr-state.XXXXXX")
    printf '%s' "$base_json" | jq \
        --arg host "$host" \
        --arg repo "$repo" \
        --arg pr "$pr_number" \
        --argjson n "$round_n" \
        --arg at "$written_at" \
        --arg head "$head_sha" \
        --argjson providers "$providers_json" \
        --argjson findings "$findings_json" \
        --argjson classification "$classification_json" \
        '.schema = 1
         | .pr = {host:$host, repo:$repo, number:($pr|tonumber? // $pr)}
         | .rounds += [{
             n:$n,
             at:$at,
             head_sha:$head,
             providers:$providers,
             classification:$classification,
             findings:$findings
           }]' > "$tmp_file"
    mv "$tmp_file" "$state_file"
}

_pr_review_state_finding_key_filter() {
    cat <<'JQ'
def key: [(.file // ""), ((.line // 0)|tostring), (.title // "")] | join("\u001f");
JQ
}

pr_review_state_classify_findings() {
    local previous_json="${1:-[]}"
    local current_json="${2:-[]}"

    jq -n \
        --argjson previous "$previous_json" \
        --argjson current "$current_json" \
        "$(_pr_review_state_finding_key_filter)
         ($previous | map(. + {_key:key})) as \$prev
         | ($current | map(. + {_key:key})) as \$curr
         | {
             addressed: ([\$prev[] | select((.status // \"open\") != \"addressed\") | select(. as \$p | [\$curr[] | select(._key == \$p._key)] | length == 0)] | length),
             persistent: ([\$curr[] | select(. as \$c | [\$prev[] | select(._key == \$c._key and ((.status // \"open\") != \"addressed\"))] | length > 0)] | length),
             new: ([\$curr[] | select(. as \$c | [\$prev[] | select(._key == \$c._key)] | length == 0)] | length),
             regressed: ([\$curr[] | select(. as \$c | [\$prev[] | select(._key == \$c._key and ((.status // \"open\") == \"addressed\"))] | length > 0)] | length)
           }"
}

pr_review_state_diff_since() {
    local previous_sha="$1"
    local current_sha="${2:-HEAD}"

    git cat-file -e "${previous_sha}^{commit}" 2>/dev/null || return 1
    git cat-file -e "${current_sha}^{commit}" 2>/dev/null || return 1
    git diff "${previous_sha}..${current_sha}"
}

pr_review_state_context_for_prompt() {
    local state_file="$1"
    local since_diff="${2:-}"
    local max_chars="${3:-12000}"

    pr_review_state_validate "$state_file" || return 0

    local previous_round previous_findings classification
    previous_round=$(pr_review_state_previous_round "$state_file") || return 0
    previous_findings=$(printf '%s' "$previous_round" | jq -c '.findings // []')
    classification=$(printf '%s' "$previous_round" | jq -c '.classification // {}')

    local context
    context="Prior round-aware review context:
Previous round: $(printf '%s' "$previous_round" | jq -r '.n')
Previous head SHA: $(printf '%s' "$previous_round" | jq -r '.head_sha // "unknown"')
Previous classification: ${classification}
Previous findings JSON: ${previous_findings}"

    if [[ -n "$since_diff" ]]; then
        context="${context}

Diff since previous review round:
\`\`\`
${since_diff}
\`\`\`"
    fi

    printf '%s' "$context" | cut -c "1-${max_chars}"
}

pr_review_state_render_timeline() {
    local state_file="$1"
    local current_sha="${2:-HEAD}"
    local classification_override="${3:-}"
    local round_override="${4:-}"

    pr_review_state_validate "$state_file" || return 0

    local previous_round
    previous_round=$(pr_review_state_previous_round "$state_file") || return 0

    local next_round addressed persistent new regressed previous_head
    next_round="${round_override:-$(pr_review_state_next_round "$state_file")}"
    previous_head=$(printf '%s' "$previous_round" | jq -r '.head_sha // "unknown"')
    if [[ -n "$classification_override" ]]; then
        addressed=$(printf '%s' "$classification_override" | jq -r '.addressed // 0')
        persistent=$(printf '%s' "$classification_override" | jq -r '.persistent // 0')
        new=$(printf '%s' "$classification_override" | jq -r '.new // 0')
        regressed=$(printf '%s' "$classification_override" | jq -r '.regressed // 0')
    else
        addressed=$(printf '%s' "$previous_round" | jq -r '.classification.addressed // 0')
        persistent=$(printf '%s' "$previous_round" | jq -r '.classification.persistent // 0')
        new=$(printf '%s' "$previous_round" | jq -r '.classification.new // 0')
        regressed=$(printf '%s' "$previous_round" | jq -r '.classification.regressed // 0')
    fi

    cat <<EOF
Round-aware review timeline
Round ${next_round}: ${current_sha}
Previous round head: ${previous_head}
Addressed: ${addressed}
Persistent: ${persistent}
New: ${new}
Regressed: ${regressed}
EOF
}
