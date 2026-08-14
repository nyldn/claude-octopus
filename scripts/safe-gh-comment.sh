#!/usr/bin/env bash
# Post GitHub text only after snapshotting and validating the outbound body.

set -euo pipefail

readonly EX_USAGE=64
readonly EX_DATAERR=65
readonly EX_NOINPUT=66
readonly EX_UNAVAILABLE=69
readonly EX_SOFTWARE=70
readonly MAX_BODY_BYTES=65536

usage() {
    cat >&2 <<'USAGE'
Usage:
  safe-gh-comment.sh --repo OWNER/REPO pr-comment PR BODY_SOURCE
  safe-gh-comment.sh --repo OWNER/REPO pr-review PR BODY_SOURCE
  safe-gh-comment.sh --repo OWNER/REPO pr-create TITLE HEAD BODY_SOURCE
  safe-gh-comment.sh --repo OWNER/REPO issue-comment ISSUE BODY_SOURCE
  safe-gh-comment.sh --repo OWNER/REPO issue-create TITLE BODY_SOURCE
  safe-gh-comment.sh --repo OWNER/REPO review-reply PR COMMENT_ID BODY_SOURCE
  safe-gh-comment.sh --repo OWNER/REPO review-line PR COMMIT PATH LINE BODY_SOURCE

BODY_SOURCE is a readable file or - to snapshot standard input.
USAGE
    exit "$EX_USAGE"
}

fail_input() {
    printf 'ERROR: outbound GitHub body file is unavailable or invalid\n' >&2
    exit "$EX_NOINPUT"
}

block_body() {
    printf 'ERROR: outbound GitHub text blocked by the credential-safety gate\n' >&2
    exit "$EX_DATAERR"
}

body_matches() {
    local pattern="$1"
    local body_file="$2"
    local grep_rc=0

    if LC_ALL=C grep -Eic -- "$pattern" "$body_file" >/dev/null; then
        return 0
    else
        grep_rc=$?
    fi
    [[ "$grep_rc" -eq 1 ]] && return 1
    printf 'ERROR: outbound GitHub credential scan failed closed\n' >&2
    exit "$EX_SOFTWARE"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'ERROR: required command is unavailable: %s\n' "$1" >&2
        exit "$EX_UNAVAILABLE"
    }
}

valid_positive_integer() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

valid_pr_head() {
    local value="$1"
    local owner=""
    local branch="$value"

    [[ -n "$value" && ${#value} -le 256 && "$value" != *$'\n'* ]] || return 1
    if [[ "$value" == *:* ]]; then
        [[ "$value" != *:*:* ]] || return 1
        owner="${value%%:*}"
        branch="${value#*:}"
        [[ "$owner" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || return 1
    fi

    git check-ref-format --branch "$branch" >/dev/null 2>&1
}

validate_body() {
    local body_file="$1"
    local body_bytes disallowed_control_count env_line_count

    body_bytes=$(wc -c < "$body_file" | tr -d '[:space:]')
    [[ "$body_bytes" =~ ^[0-9]+$ ]] || fail_input
    [[ "$body_bytes" -gt 0 && "$body_bytes" -le "$MAX_BODY_BYTES" ]] || fail_input

    iconv -f UTF-8 -t UTF-8 "$body_file" >/dev/null 2>&1 || block_body
    disallowed_control_count=$(LC_ALL=C \
        tr -d '\011\012\015\040-\176\200-\377' < "$body_file" | \
        wc -c | tr -d '[:space:]')
    [[ "$disallowed_control_count" == "0" ]] || block_body

    # Recognizable provider and platform credential formats. Never print the
    # matching line: validation output must not become a second disclosure.
    if body_matches \
        '(pplx-|sk-(ant-|proj-)?|sk_live_|rk_live_|gh[pousr]_|github_pat_|glpat-|xox[baprs]-|hf_|AIza)[A-Za-z0-9._-]{16,}|(AKIA|ASIA)[0-9A-Z]{16}' \
        "$body_file"; then
        block_body
    fi

    if body_matches \
        "-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----|Authorization[\"']?[[:space:]]*:[[:space:]]*[\"']?(Bearer|Basic)[[:space:]]+[A-Za-z0-9._~+/-]+|[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]@/:]*:[^[:space:]@/]+@|eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}" \
        "$body_file"; then
        block_body
    fi

    # Reject values assigned to sensitive environment names anywhere in
    # generated text while permitting explicit redaction and variable-reference
    # placeholders.
    local sensitive_scan_rc=0
    LC_ALL=C awk '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        function strip_wrapping(value, edge) {
            while (value != "") {
                edge = substr(value, 1, 1)
                if (index("*`_", edge) == 0) break
                value = substr(value, 2)
            }
            while (value != "") {
                edge = substr(value, length(value), 1)
                if (index("*`_.,;:.)]}", edge) == 0) break
                value = substr(value, 1, length(value) - 1)
            }
            return value
        }
        function is_placeholder(value, lower, upper, expression_upper) {
            value = trim(value)
            expression_upper = toupper(value)
            if (expression_upper ~ /^\$\{\{[[:space:]]*(SECRETS|VARS|ENV)\.[A-Z][A-Z0-9_]*[[:space:]]*\}\}$/) {
                return 1
            }
            value = strip_wrapping(value)
            lower = tolower(value)
            upper = toupper(value)
            return (upper ~ /^\$\{?[A-Z][A-Z0-9_]*\}?$/ ||
                lower == "redacted" || lower == "<redacted>" ||
                lower == "***" || lower == "example")
        }
        function value_is_safe(text, allow_empty, quote, end, value, rest) {
            text = trim(text)
            if (text == "") {
                return allow_empty
            }
            if (is_placeholder(text)) {
                return 1
            }
            quote = substr(text, 1, 1)
            if (quote == "\"" || quote == "\047") {
                text = substr(text, 2)
                end = index(text, quote)
                if (end == 0) {
                    return 0
                }
                value = substr(text, 1, end - 1)
                rest = trim(substr(text, end + 1))
                if (rest != "" && index(",;.)]}#", substr(rest, 1, 1)) == 0) {
                    return 0
                }
            } else {
                value = text
                sub(/[[:space:],;#].*$/, "", value)
            }
            value = strip_wrapping(value)
            if (value == "") {
                return allow_empty
            }
            return is_placeholder(value)
        }
        BEGIN {
            snake_name = "([A-Z][A-Z0-9_]*_)?(API_KEY|ACCESS_KEY_ID|ACCESS_KEY|PRIVATE_KEY|SECRET_KEY|KEY|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|CREDENTIALS|DATABASE_URL|DATABASE_DSN|CONNECTION_STRING|AUTHORIZATION)"
            compact_name = "(APIKEY|ACCESSKEYID|ACCESSKEY|PRIVATEKEY|SECRETKEY|SECRETKEYBASE|CLIENTSECRET|ACCESSTOKEN|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|CREDENTIALS|DATABASEURL|DATABASEDSN|CONNECTIONSTRING|AUTHORIZATION)"
            prefixed_compact_name = "[A-Z][A-Z0-9]*(APIKEY|ACCESSKEYID|ACCESSKEY|PRIVATEKEY|SECRETKEY|SECRETKEYBASE|CLIENTSECRET|PASSWORD|PASSWD)"
            name = "(" snake_name "|SECRET_KEY_BASE|" compact_name "|" prefixed_compact_name ")"
            quote = "(\"|\047)?"
            assignment = "(^|[^A-Z0-9_])" quote name quote "[[:space:]]*=[[:space:]]*"
            structured = "(^|\\{[[:space:]]*|\\[[[:space:]]*)" quote name quote "[[:space:]]*:[[:space:]]*"
        }
        {
            remaining = $0
            normalized = toupper(remaining)
            while (match(normalized, assignment)) {
                remaining = substr(remaining, RSTART + RLENGTH)
                normalized = toupper(remaining)
                if (substr(remaining, 1, 1) != "=" &&
                        !value_is_safe(remaining, 1)) {
                    found = 1
                }
            }

            segment_count = split($0, segments, ",")
            for (segment_index = 1; segment_index <= segment_count; segment_index++) {
                segment = trim(segments[segment_index])
                while (segment ~ /^([+>*-]|[0-9]+\.)[[:space:]]+/) {
                    sub(/^([+>*-]|[0-9]+\.)[[:space:]]+/, "", segment)
                }
                while (segment != "" && index("{[", substr(segment, 1, 1)) > 0) {
                    segment = trim(substr(segment, 2))
                }
                structured_remaining = segment
                normalized_segment = toupper(structured_remaining)
                while (match(normalized_segment, structured)) {
                    structured_remaining = substr(structured_remaining, RSTART + RLENGTH)
                    normalized_segment = toupper(structured_remaining)
                    structured_value = structured_remaining
                    if (!value_is_safe(structured_value, 0)) {
                        found = 1
                    }
                }
            }
        }
        END { exit(found ? 0 : 1) }
    ' "$body_file" || sensitive_scan_rc=$?
    case "$sensitive_scan_rc" in
        0) block_body ;;
        1) ;;
        *)
            printf 'ERROR: outbound GitHub sensitive-assignment scan failed closed\n' >&2
            exit "$EX_SOFTWARE"
            ;;
    esac

    # A cluster of shell-style assignments is an environment dump even when a
    # provider-specific detector does not recognize any individual value.
    if ! env_line_count=$(LC_ALL=C awk '
        {
            if (toupper($0) ~ /(^|[^A-Z0-9_])[A-Z_][A-Z0-9_]*=/) {
                count++
            }
        }
        END { print count + 0 }
    ' "$body_file"); then
        printf 'ERROR: outbound GitHub environment scan failed closed\n' >&2
        exit "$EX_SOFTWARE"
    fi
    [[ "$env_line_count" -lt 5 ]] || block_body
}

[[ $# -ge 5 && "$1" == "--repo" ]] || usage
repo="$2"
operation="$3"
shift 3

[[ "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || usage

case "$operation" in
    pr-comment|pr-review|issue-comment)
        [[ $# -eq 2 ]] || usage
        target_number="$1"
        body_source="$2"
        valid_positive_integer "$target_number" || usage
        ;;
    pr-create)
        [[ $# -eq 3 ]] || usage
        create_title="$1"
        create_head="$2"
        body_source="$3"
        [[ -n "$create_title" && ${#create_title} -le 256 && "$create_title" != *$'\n'* ]] || usage
        valid_pr_head "$create_head" || usage
        ;;
    issue-create)
        [[ $# -eq 2 ]] || usage
        create_title="$1"
        body_source="$2"
        [[ -n "$create_title" && ${#create_title} -le 256 && "$create_title" != *$'\n'* ]] || usage
        ;;
    review-reply)
        [[ $# -eq 3 ]] || usage
        target_number="$1"
        comment_id="$2"
        body_source="$3"
        valid_positive_integer "$target_number" || usage
        valid_positive_integer "$comment_id" || usage
        ;;
    review-line)
        [[ $# -eq 5 ]] || usage
        target_number="$1"
        commit_id="$2"
        review_path="$3"
        review_line="$4"
        body_source="$5"
        valid_positive_integer "$target_number" || usage
        [[ "$commit_id" =~ ^[0-9a-fA-F]{7,64}$ ]] || usage
        [[ -n "$review_path" && "$review_path" != /* && "$review_path" != *$'\n'* ]] || usage
        [[ "$review_path" != ".." && "$review_path" != ../* && \
            "$review_path" != */../* && "$review_path" != */.. ]] || usage
        valid_positive_integer "$review_line" || usage
        ;;
    *)
        usage
        ;;
esac

if [[ "$body_source" != "-" ]]; then
    [[ -f "$body_source" && -r "$body_source" ]] || fail_input
fi

for dependency in gh git grep awk wc tr iconv mktemp cat head sleep; do
    require_command "$dependency"
done
case "$operation" in
    review-reply|review-line) require_command jq ;;
esac

snapshot_dir=$(mktemp -d "${TMPDIR:-/tmp}/octopus-safe-gh.XXXXXX") || exit "$EX_SOFTWARE"
child_pid=""
terminate_child() {
    local signal_name="$1"
    local exit_status="$2"
    local attempts=0
    if [[ -n "$child_pid" ]] && kill -0 "$child_pid" 2>/dev/null; then
        kill -"$signal_name" "$child_pid" 2>/dev/null || true
        while kill -0 "$child_pid" 2>/dev/null && [[ "$attempts" -lt 10 ]]; do
            sleep 0.02
            attempts=$((attempts + 1))
        done
        if kill -0 "$child_pid" 2>/dev/null; then
            kill -KILL "$child_pid" 2>/dev/null || true
        fi
        wait "$child_pid" 2>/dev/null || true
    fi
    child_pid=""
    exit "$exit_status"
}
run_command() {
    local command_status=0
    "$@" &
    child_pid=$!
    wait "$child_pid" || command_status=$?
    child_pid=""
    return "$command_status"
}
trap 'rm -rf "$snapshot_dir"' EXIT
trap 'terminate_child INT 130' INT
trap 'terminate_child TERM 143' TERM
snapshot_file="$snapshot_dir/body.md"
if [[ "$body_source" == "-" ]]; then
    head -c "$((MAX_BODY_BYTES + 1))" > "$snapshot_file" || fail_input
else
    head -c "$((MAX_BODY_BYTES + 1))" < "$body_source" > "$snapshot_file" || fail_input
fi
chmod 600 "$snapshot_file"

validate_body "$snapshot_file"

case "$operation" in
    pr-create|issue-create)
        title_file="$snapshot_dir/title.txt"
        printf '%s\n' "$create_title" > "$title_file"
        chmod 600 "$title_file"
        validate_body "$title_file"
        ;;
esac

post_output=""
case "$operation" in
    pr-comment)
        run_command gh pr comment "$target_number" --repo "$repo" \
            --body-file "$snapshot_file" >/dev/null
        ;;
    pr-review)
        run_command gh pr review "$target_number" --repo "$repo" --comment \
            --body-file "$snapshot_file" >/dev/null
        ;;
    pr-create)
        output_file="$snapshot_dir/post-output.txt"
        run_command gh pr create --repo "$repo" --head "$create_head" \
            --title "$create_title" --body-file "$snapshot_file" > "$output_file"
        post_output=$(<"$output_file")
        ;;
    issue-comment)
        run_command gh issue comment "$target_number" --repo "$repo" \
            --body-file "$snapshot_file" >/dev/null
        ;;
    issue-create)
        output_file="$snapshot_dir/post-output.txt"
        run_command gh issue create --repo "$repo" --title "$create_title" \
            --body-file "$snapshot_file" > "$output_file"
        post_output=$(<"$output_file")
        ;;
    review-reply)
        request_file="$snapshot_dir/request.json"
        jq -n --rawfile body "$snapshot_file" '{body: $body}' > "$request_file"
        run_command gh api --silent --method POST \
            "repos/${repo}/pulls/${target_number}/comments/${comment_id}/replies" \
            --input "$request_file"
        ;;
    review-line)
        request_file="$snapshot_dir/request.json"
        jq -n --rawfile body "$snapshot_file" \
            --arg commit_id "$commit_id" \
            --arg path "$review_path" \
            --argjson line "$review_line" \
            '{body: $body, commit_id: $commit_id, path: $path, line: $line, side: "RIGHT"}' \
            > "$request_file"
        run_command gh api --silent --method POST \
            "repos/${repo}/pulls/${target_number}/comments" \
            --input "$request_file"
        ;;
esac

case "$operation" in
    pr-create|issue-create) printf '%s\n' "$post_output" ;;
    *) printf 'Posted GitHub %s through the credential-safety gate.\n' "$operation" ;;
esac
