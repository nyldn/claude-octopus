#!/usr/bin/env bash
# Durable research evidence state for probe/research/embrace.
# Source-safe and Bash 3.2 compatible; no Python runtime is required.

OCTOPUS_RESEARCH_INTENSITY="${OCTOPUS_RESEARCH_INTENSITY:-standard}"
OCTOPUS_RESEARCH_EVIDENCE="${OCTOPUS_RESEARCH_EVIDENCE:-true}"
OCTOPUS_RESEARCH_RUN_ID="${OCTOPUS_RESEARCH_RUN_ID:-}"
OCTOPUS_RESEARCH_RESUME="${OCTOPUS_RESEARCH_RESUME:-false}"

research_set_intensity() {
    case "$1" in
        light) OCTOPUS_RESEARCH_INTENSITY=quick ;;
        exhaustive) OCTOPUS_RESEARCH_INTENSITY=deep ;;
        *) OCTOPUS_RESEARCH_INTENSITY="$1" ;;
    esac
}

research_parse_global_option() {
    local option="${1:-}" value="${2:-}"
    RESEARCH_OPTION_SHIFT=1
    case "$option" in
        --intensity=*) research_set_intensity "${option#*=}" ;;
        --breadth=*) research_set_intensity "${option#*=}" ;;
        --research-run=*) OCTOPUS_RESEARCH_RUN_ID="${option#*=}" ;;
        --resume-research=*)
            OCTOPUS_RESEARCH_RUN_ID="${option#*=}"
            OCTOPUS_RESEARCH_RESUME=true
            ;;
        --intensity|--breadth|--research-run|--resume-research)
            [[ -n "$value" ]] || return 2
            RESEARCH_OPTION_SHIFT=2
            case "$option" in
                --intensity|--breadth) research_set_intensity "$value" ;;
                --research-run) OCTOPUS_RESEARCH_RUN_ID="$value" ;;
                --resume-research)
                    OCTOPUS_RESEARCH_RUN_ID="$value"
                    OCTOPUS_RESEARCH_RESUME=true
                    ;;
            esac
            ;;
        *) return 1 ;;
    esac
}

research_dispatch_command() {
    local command="$1"
    shift
    case "$command" in
        research-resume)
            [[ $# -eq 1 ]] || {
                printf 'Usage: %s research-resume <run-id>\n' "$(basename "$0")" >&2
                return 2
            }
            research_resume_run "$1"
            ;;
        research-verify)
            [[ $# -eq 2 ]] || {
                printf 'Usage: %s research-verify <run-id> <synthesis-file>\n' "$(basename "$0")" >&2
                return 2
            }
            research_verify_run "$1" "$2"
            ;;
        *) return 2 ;;
    esac
}

research_sha256() {
    local file="$1"
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$file" | awk '{print $NF}'
    else
        return 1
    fi
}

research_json_string() {
    if declare -F _octo_json_string >/dev/null 2>&1; then
        _octo_json_string "$1"
        return
    fi
    local value="$1"
    case "$value" in
        *[[:cntrl:]]*) : ;;
        *)
            local fast="${value//\\/\\\\}"
            printf '"%s"\n' "${fast//\"/\\\"}"
            return 0
            ;;
    esac

    local out="" ch ord escaped i
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    for ((i = 0; i < ${#value}; i++)); do
        ch="${value:i:1}"
        case "$ch" in
            $'\b') out="${out}\\b" ;;
            $'\f') out="${out}\\f" ;;
            $'\n') out="${out}\\n" ;;
            $'\r') out="${out}\\r" ;;
            $'\t') out="${out}\\t" ;;
            *)
                LC_ALL=C printf -v ord '%d' "'$ch"
                if (( ord < 32 )); then
                    printf -v escaped '\\u%04x' "$ord"
                    out="${out}${escaped}"
                else
                    out="${out}${ch}"
                fi
                ;;
        esac
    done
    printf '"%s"\n' "$out"
}

research_safe_id() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]
}

research_manifest_value() {
    local manifest="$1" key="$2"
    [[ -r "$manifest" ]] || return 1
    sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -1
}

research_run_dir() {
    local run_id="$1"
    research_safe_id "$run_id" || return 2
    local root="${OCTOPUS_RESEARCH_ROOT:-${WORKSPACE_DIR:-${RESULTS_DIR:?}}/research-runs}"
    printf '%s/%s\n' "$root" "$run_id"
}

research_lock_acquire() {
    local lock="$1" tries=0
    local token="$$.$RANDOM.$RANDOM"
    while ! mkdir "$lock" 2>/dev/null; do
        tries=$((tries + 1))
        # A killed process can leave a mkdir lock behind. Reclaim only locks
        # that have been idle for five minutes. Rename the stale inode first:
        # deleting the live path after a check would race with a new owner.
        if [[ -d "$lock" ]] \
           && [[ -n "$(find "$lock" -prune -mmin +5 -print 2>/dev/null)" ]]; then
            local stale_lock="${lock}.stale.${token}.${tries}"
            if mv "$lock" "$stale_lock" 2>/dev/null; then
                rm -f "$stale_lock/owner" "$stale_lock/pid" 2>/dev/null || true
                rmdir "$stale_lock" 2>/dev/null || true
                continue
            fi
        fi
        [[ "$tries" -ge 100 ]] && return 1
        sleep 0.02
    done
    if ! printf '%s\n' "$token" > "$lock/owner" 2>/dev/null; then
        rmdir "$lock" 2>/dev/null || true
        return 1
    fi
    printf '%s\n' "$token"
}

research_lock_release() {
    local lock="$1" token="$2" owner=""
    [[ -r "$lock/owner" ]] && IFS= read -r owner < "$lock/owner"
    [[ -n "$token" && "$owner" == "$token" ]] || return 0
    rm -f "$lock/owner" 2>/dev/null || true
    rmdir "$lock" 2>/dev/null || true
}

research_run_event() {
    local run_dir="$1" event="$2" detail="${3:-}"
    local events="$run_dir/events.jsonl" lock="$run_dir/.events.lock"
    mkdir -p "$run_dir" 2>/dev/null || return 1
    local lock_token
    lock_token=$(research_lock_acquire "$lock") || return 1
    local sequence timestamp record
    if [[ -f "$events" ]]; then
        sequence=$(( $(wc -l < "$events" 2>/dev/null || echo 0) + 1 ))
    else
        sequence=1
    fi
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +%s)
    printf -v record '{"sequence":%s,"timestamp":%s,"event":%s,"detail":%s}\n' \
        "$sequence" "$(research_json_string "$timestamp")" \
        "$(research_json_string "$event")" "$(research_json_string "$detail")"
    printf '%s' "$record" >> "$events"
    research_lock_release "$lock" "$lock_token"
}

research_manifest_write() {
    local run_dir="$1" run_id="$2" task_group="$3" prompt="$4"
    local intensity="$5" stage="$6" status="$7"
    local manifest="$run_dir/manifest.json" tmp="$run_dir/.manifest.$$" lock="$run_dir/.manifest.lock"
    local created_at updated_at fetch_max provider_results_dir
    provider_results_dir="${RESEARCH_PROVIDER_RESULTS_DIR:-${RESULTS_DIR:-}}"
    created_at=$(research_manifest_value "$manifest" created_at 2>/dev/null || true)
    [[ -n "$created_at" ]] || created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    updated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    case "$intensity" in
        quick) fetch_max=0 ;;
        deep) fetch_max=20 ;;
        *) fetch_max=8 ;;
    esac
    fetch_max="${OCTOPUS_RESEARCH_FETCH_MAX:-$fetch_max}"
    [[ "$fetch_max" =~ ^[0-9]+$ ]] || fetch_max=0
    local lock_token
    lock_token=$(research_lock_acquire "$lock") || return 1
    if ! (
        umask 077
        {
            printf '{\n'
            printf '  "schema_version": 1,\n'
            printf '  "run_id": %s,\n' "$(research_json_string "$run_id")"
            printf '  "task_group": %s,\n' "$(research_json_string "$task_group")"
            printf '  "prompt": %s,\n' "$(research_json_string "$prompt")"
            printf '  "intensity": %s,\n' "$(research_json_string "$intensity")"
            printf '  "stage": %s,\n' "$(research_json_string "$stage")"
            printf '  "status": %s,\n' "$(research_json_string "$status")"
            printf '  "created_at": %s,\n' "$(research_json_string "$created_at")"
            printf '  "updated_at": %s,\n' "$(research_json_string "$updated_at")"
            printf '  "provider_results_dir": %s,\n' "$(research_json_string "$provider_results_dir")"
            printf '  "limits": {"external_fetches": %s, "response_bytes": %s},\n' \
                "$fetch_max" "${OCTOPUS_RESEARCH_MAX_RESPONSE_BYTES:-2097152}"
            printf '  "artifacts": {\n'
            printf '    "prompt": "prompt.txt",\n'
            printf '    "events": "events.jsonl",\n'
            printf '    "sources": "sources.jsonl",\n'
            printf '    "claims": "claims.jsonl",\n'
            printf '    "verification": "verification.json",\n'
            printf '    "source_catalog": "source-catalog.md"\n'
            printf '  }\n'
            printf '}\n'
        } > "$tmp"
    ); then
        rm -f "$tmp"
        research_lock_release "$lock" "$lock_token"
        return 1
    fi
    mv -f "$tmp" "$manifest" || {
        rm -f "$tmp"
        research_lock_release "$lock" "$lock_token"
        return 1
    }
    research_lock_release "$lock" "$lock_token"
}

research_run_begin() {
    local task_group="$1" prompt="$2" intensity="${3:-standard}"
    local requested_id="${OCTOPUS_RESEARCH_RUN_ID:-}"
    case "$intensity" in quick|standard|deep) ;; *) intensity=standard ;; esac
    [[ -n "$requested_id" ]] || requested_id="$task_group"
    research_safe_id "$requested_id" || {
        printf 'Invalid research run id: %s\n' "$requested_id" >&2
        return 2
    }
    local run_dir
    run_dir=$(research_run_dir "$requested_id") || return $?
    mkdir -p "$run_dir/snapshots" || return 1
    if [[ "${OCTOPUS_RESEARCH_RESUME:-false}" == "true" ]]; then
        [[ -r "$run_dir/manifest.json" ]] || {
            printf 'Research run not found: %s\n' "$requested_id" >&2
            return 1
        }
        RESEARCH_TASK_GROUP=$(research_manifest_value "$run_dir/manifest.json" task_group)
        if [[ -r "$run_dir/prompt.txt" ]]; then
            RESEARCH_PROMPT=$(<"$run_dir/prompt.txt")
        else
            RESEARCH_PROMPT=$(research_manifest_value "$run_dir/manifest.json" prompt)
        fi
        RESEARCH_INTENSITY=$(research_manifest_value "$run_dir/manifest.json" intensity)
        RESEARCH_PROVIDER_RESULTS_DIR=$(research_manifest_value "$run_dir/manifest.json" provider_results_dir)
        [[ -n "$RESEARCH_PROVIDER_RESULTS_DIR" ]] || RESEARCH_PROVIDER_RESULTS_DIR="${RESULTS_DIR:-}"
        [[ -n "$RESEARCH_TASK_GROUP" && -n "$RESEARCH_PROMPT" ]] || return 1
        export RESEARCH_PROVIDER_RESULTS_DIR
        research_run_event "$run_dir" "run.resumed" "stage=$(research_manifest_value "$run_dir/manifest.json" stage)" || true
    else
        local create_lock="$run_dir/.run-create.lock"
        local create_lock_token
        create_lock_token=$(research_lock_acquire "$create_lock") || return 1
        if [[ -e "$run_dir/manifest.json" ]]; then
            research_lock_release "$create_lock" "$create_lock_token"
            printf 'Research run already exists: %s (use --resume-research to continue it)\n' "$requested_id" >&2
            return 3
        fi
        RESEARCH_TASK_GROUP="$task_group"
        RESEARCH_PROMPT="$prompt"
        RESEARCH_INTENSITY="$intensity"
        RESEARCH_PROVIDER_RESULTS_DIR="${RESULTS_DIR:-}"
        export RESEARCH_PROVIDER_RESULTS_DIR
        if ! printf '%s' "$prompt" > "$run_dir/.prompt.$$" \
           || ! mv -f "$run_dir/.prompt.$$" "$run_dir/prompt.txt" \
           || ! research_manifest_write "$run_dir" "$requested_id" "$task_group" "$prompt" "$intensity" "initialized" "running"; then
            rm -f "$run_dir/.prompt.$$"
            research_lock_release "$create_lock" "$create_lock_token"
            return 1
        fi
        research_lock_release "$create_lock" "$create_lock_token"
        research_run_event "$run_dir" "run.started" "intensity=$intensity" || true
    fi
    RESEARCH_RUN_ID="$requested_id"
    RESEARCH_RUN_DIR="$run_dir"
    export RESEARCH_RUN_ID RESEARCH_RUN_DIR RESEARCH_TASK_GROUP RESEARCH_PROMPT RESEARCH_INTENSITY
}

research_run_update() {
    local stage="$1" status="${2:-running}" detail="${3:-}"
    [[ -n "${RESEARCH_RUN_DIR:-}" ]] || return 0
    research_manifest_write "$RESEARCH_RUN_DIR" "$RESEARCH_RUN_ID" \
        "$RESEARCH_TASK_GROUP" "$RESEARCH_PROMPT" "$RESEARCH_INTENSITY" \
        "$stage" "$status" || return 1
    research_run_event "$RESEARCH_RUN_DIR" "run.$stage" "$detail" || true
}

research_synthesis_prepare() {
    local task_group="$1" original_prompt="$2"
    [[ -z "${RESEARCH_RUN_DIR:-}" ]] || return 0

    local existing_research_dir=""
    existing_research_dir=$(research_run_dir "$task_group" 2>/dev/null || true)
    if [[ -r "$existing_research_dir/manifest.json" ]]; then
        OCTOPUS_RESEARCH_RUN_ID="$task_group" OCTOPUS_RESEARCH_RESUME=true \
            research_run_begin "$task_group" "$original_prompt" \
                "${OCTOPUS_RESEARCH_INTENSITY:-standard}" || return 1
        return 0
    fi

    # Standalone recovery also calls the synthesis function for legacy probe
    # artifacts. Do not turn that best-effort path into a new fail-closed run.
    # Live durable workflows begin their run before synthesis, and interrupted
    # durable workflows resume through the existing manifest above.
    return 0
}

research_synthesis_select_draft() {
    local synthesis_file="$1" task_group="$2"
    RESEARCH_SYNTHESIS_DRAFT_FILE="$synthesis_file"
    if [[ -n "${RESEARCH_RUN_DIR:-}" ]]; then
        RESEARCH_SYNTHESIS_DRAFT_FILE="$RESEARCH_RUN_DIR/synthesis-draft.md"
        research_run_update "drafting" "running" "task_group=$task_group" || return 1
    fi
}

research_synthesis_publish() {
    local draft_file="$1" synthesis_file="$2"
    [[ -n "${RESEARCH_RUN_DIR:-}" ]] || return 0
    if ! research_verify_synthesis "$draft_file"; then
        research_run_update "verification_failed" "blocked" \
            "report=$RESEARCH_RUN_DIR/verification.json" || true
        log ERROR "Research synthesis failed mechanical evidence verification: $RESEARCH_RUN_DIR/verification.json"
        return 1
    fi
    cp "$draft_file" "$synthesis_file" || return 1
    research_run_update "complete" "completed" "synthesis=$synthesis_file"
}

research_url_parts() {
    local url="$1"
    local re='^https://([^/?#]+)(/[^?#]*)?(\?[^#]*)?([#].*)?$'
    [[ "$url" =~ $re ]] || return 1
    local authority="${BASH_REMATCH[1]}"
    local raw_path="${BASH_REMATCH[2]:-/}${BASH_REMATCH[3]}"
    [[ "$authority" != *"@"* && "$authority" != *"["* && "$authority" != *"]"* ]] || return 1
    case "$authority" in
        *:*) [[ "$authority" == *:443 ]] || return 1; authority="${authority%:443}" ;;
    esac
    authority=$(printf '%s' "$authority" | tr '[:upper:]' '[:lower:]')
    [[ "$authority" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || return 1
    [[ "$authority" != *..* && "$authority" != .* && "$authority" != *. ]] || return 1
    case "$authority" in
        localhost|localhost.*|*.localhost|*.local|*.internal|*.home|*.lan) return 1 ;;
    esac
    RESEARCH_URL_HOST="$authority"
    RESEARCH_URL_PATH="$raw_path"
    export RESEARCH_URL_HOST RESEARCH_URL_PATH
}

research_ipv4_is_public() {
    local ip="$1"
    awk -F. '
        NF != 4 { exit 1 }
        { for (i=1; i<=4; i++) if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255) exit 1 }
        $1 == 0 || $1 == 10 || $1 == 127 { exit 1 }
        $1 == 100 && $2 >= 64 && $2 <= 127 { exit 1 }
        $1 == 169 && $2 == 254 { exit 1 }
        $1 == 172 && $2 >= 16 && $2 <= 31 { exit 1 }
        $1 == 192 && ($2 == 0 || $2 == 168) { exit 1 }
        $1 == 192 && $2 == 0 && $3 == 2 { exit 1 }
        $1 == 198 && ($2 == 18 || $2 == 19 || ($2 == 51 && $3 == 100)) { exit 1 }
        $1 == 203 && $2 == 0 && $3 == 113 { exit 1 }
        $1 >= 224 { exit 1 }
        { exit 0 }
    ' <<< "$ip"
}

research_resolve_ipv4() {
    local host="$1"
    if [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf '%s\n' "$host"
    elif command -v getent >/dev/null 2>&1; then
        getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u
    elif command -v dig >/dev/null 2>&1; then
        dig +short A "$host" 2>/dev/null | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/'
    elif command -v dscacheutil >/dev/null 2>&1; then
        dscacheutil -q host -a name "$host" 2>/dev/null | sed -n 's/^ip_address: //p' | awk '/^[0-9]+\./'
    else
        return 1
    fi
}

research_validate_fetch_target() {
    local url="$1"
    research_url_parts "$url" || return 1
    local addresses ip found=false
    addresses=$(research_resolve_ipv4 "$RESEARCH_URL_HOST") || return 1
    while IFS= read -r ip; do
        [[ -n "$ip" ]] || continue
        found=true
        research_ipv4_is_public "$ip" || return 1
    done <<< "$addresses"
    [[ "$found" == "true" ]] || return 1
    RESEARCH_URL_IP=$(printf '%s\n' "$addresses" | head -1)
    export RESEARCH_URL_IP
}

research_resolve_redirect() {
    local base="$1" location="$2"
    location=${location//$'\r'/}
    case "$location" in
        https://*) printf '%s\n' "${location%%#*}" ;;
        //*) printf 'https:%s\n' "${location%%#*}" ;;
        /*)
            research_url_parts "$base" || return 1
            printf 'https://%s%s\n' "$RESEARCH_URL_HOST" "${location%%#*}"
            ;;
        *)
            research_url_parts "$base" || return 1
            local base_path="${RESEARCH_URL_PATH%%\?*}"
            local directory="${base_path%/*}"
            printf 'https://%s%s/%s\n' "$RESEARCH_URL_HOST" "$directory" "${location%%#*}"
            ;;
    esac
}

research_fetch_url() {
    local url="$1" output="$2"
    local max_bytes="${3:-${OCTOPUS_RESEARCH_MAX_RESPONSE_BYTES:-2097152}}"
    local max_redirects="${OCTOPUS_RESEARCH_MAX_REDIRECTS:-5}"
    [[ "$max_bytes" =~ ^[1-9][0-9]*$ && "$max_redirects" =~ ^[0-9]+$ ]] || return 2
    command -v curl >/dev/null 2>&1 || return 127
    local current="$url" hop=0 tmp_body="${output}.tmp.$$" tmp_headers="${output}.headers.$$"
    rm -f "$tmp_body" "$tmp_headers"
    while :; do
        research_validate_fetch_target "$current" || { rm -f "$tmp_body" "$tmp_headers"; return 3; }
        local code curl_status=0
        local prior_errexit=false
        case "$-" in *e*) prior_errexit=true; set +e ;; esac
        # -q prevents a user's curlrc from injecting headers, proxies, or
        # other request behavior into this bounded evidence fetch.
        curl -q --silent --show-error --request GET \
            --output - --dump-header "$tmp_headers" \
            --proto '=https' --proto-redir '=https' \
            --max-redirs 0 --connect-timeout 10 --max-time 30 \
            --max-filesize "$max_bytes" --noproxy '*' \
            --resolve "${RESEARCH_URL_HOST}:443:${RESEARCH_URL_IP}" \
            "$current" | head -c "$((max_bytes + 1))" > "$tmp_body"
        local pipeline_curl_status="${PIPESTATUS[0]}" pipeline_head_status="${PIPESTATUS[1]}"
        curl_status="$pipeline_curl_status"
        local head_status="$pipeline_head_status"
        [[ "$prior_errexit" == "true" ]] && set -e
        [[ "$head_status" -eq 0 ]] || { rm -f "$tmp_body" "$tmp_headers"; return 1; }
        code=$(awk '/^HTTP\/[0-9.]+[[:space:]]+[0-9]+/ { value=$2 } END { print value }' "$tmp_headers" 2>/dev/null)
        [[ "$code" =~ ^[0-9]{3}$ ]] || { rm -f "$tmp_body" "$tmp_headers"; return 22; }
        case "$code" in
            2??)
                local size
                size=$(wc -c < "$tmp_body" 2>/dev/null || echo 0)
                [[ "$size" =~ ^[0-9]+$ && "$size" -le "$max_bytes" ]] \
                    || { rm -f "$tmp_body" "$tmp_headers"; return 63; }
                [[ "$curl_status" -eq 0 ]] || { rm -f "$tmp_body" "$tmp_headers"; return "$curl_status"; }
                mv -f "$tmp_body" "$output"
                rm -f "$tmp_headers"
                RESEARCH_FETCH_FINAL_URL="$current"
                export RESEARCH_FETCH_FINAL_URL
                return 0
                ;;
            301|302|303|307|308)
                [[ "$hop" -lt "$max_redirects" ]] || { rm -f "$tmp_body" "$tmp_headers"; return 47; }
                local location
                location=$(sed -n 's/^[Ll]ocation:[[:space:]]*//p' "$tmp_headers" | tail -1 | tr -d '\r')
                [[ -n "$location" ]] || { rm -f "$tmp_body" "$tmp_headers"; return 47; }
                current=$(research_resolve_redirect "$current" "$location") || { rm -f "$tmp_body" "$tmp_headers"; return 3; }
                hop=$((hop + 1))
                rm -f "$tmp_body" "$tmp_headers"
                ;;
            *) rm -f "$tmp_body" "$tmp_headers"; return 22 ;;
        esac
    done
}

research_canonical_url() {
    local url="$1"
    url="${url%%#*}"
    while :; do
        case "$url" in
            *\)|*\"|*\.|*\,|*\;|*:) url="${url%?}" ;;
            *) break ;;
        esac
    done
    printf '%s\n' "$url"
}

research_source_field() {
    local sources="$1" source_id="$2" field="$3"
    if command -v jq >/dev/null 2>&1; then
        jq -r --arg id "$source_id" --arg field "$field" \
            'select(.source_id == $id) | .[$field] // ""' "$sources" 2>/dev/null | head -1
    else
        sed -n '/"source_id":"'"$source_id"'"/s/.*"'"$field"'":"\([^"]*\)".*/\1/p' "$sources" | head -1
    fi
}

research_extract_numbers() {
    local line="$1"
    # Do not mistake ordered-list markers ("1." / "2)") for factual values.
    line=$(printf '%s\n' "$line" | sed -E 's/^[[:space:]]*([-*+][[:space:]]*)?[0-9]+[.)][[:space:]]*//')
    printf '%s\n' "$line" | grep -Eo '[0-9]+([.,][0-9]+)*%?' | sort -u || true
}

research_number_in_snapshot() {
    local number="$1" snapshot="$2" escaped
    escaped=$(printf '%s' "$number" | sed 's/[.[\*^$\\]/\\&/g')
    if [[ "$number" == *% ]]; then
        grep -Ei -c "(^|[^0-9])${escaped}([^0-9]|$)" "$snapshot" >/dev/null
    else
        grep -Ei -c "(^|[^0-9])${escaped}([^0-9%]|$)" "$snapshot" >/dev/null
    fi
}

research_collect_sources() {
    local task_group="$1" run_dir="${RESEARCH_RUN_DIR:?}"
    local sources="$run_dir/sources.jsonl" tmp="$run_dir/.sources.$$"
    local catalog="$run_dir/source-catalog.md" seen="$run_dir/.source-urls.$$"
    : > "$tmp"; : > "$seen"
    local fetch_max
    case "${RESEARCH_INTENSITY:-standard}" in quick) fetch_max=0 ;; deep) fetch_max=20 ;; *) fetch_max=8 ;; esac
    fetch_max="${OCTOPUS_RESEARCH_FETCH_MAX:-$fetch_max}"
    [[ "$fetch_max" =~ ^[0-9]+$ ]] || fetch_max=0
    [[ "${OCTOPUS_RESEARCH_FETCH:-true}" == "true" ]] || fetch_max=0
    local index=0 fetched=0 result url canonical host source_id status reason snapshot sha independence
    local provider_results_dir="${RESEARCH_PROVIDER_RESULTS_DIR:-$RESULTS_DIR}"
    for result in "$provider_results_dir"/*-probe-${task_group}-*.md; do
        [[ -f "$result" ]] || continue
        probe_result_file_is_usable "$result" || continue
        while IFS= read -r url; do
            canonical=$(research_canonical_url "$url")
            [[ -n "$canonical" ]] || continue
            grep -Fxc -- "$canonical" "$seen" >/dev/null 2>&1 && continue
            printf '%s\n' "$canonical" >> "$seen"
            index=$((index + 1)); printf -v source_id 'S%03d' "$index"
            status="not_fetched"; reason="budget"; sha=""; independence=""
            if research_url_parts "$canonical"; then
                host="$RESEARCH_URL_HOST"
                independence="host:$host"
                snapshot="$run_dir/snapshots/${source_id}.body"
                if [[ "$fetched" -lt "$fetch_max" ]]; then
                    if research_fetch_url "$canonical" "$snapshot"; then
                        fetched=$((fetched + 1)); status="fetched"; reason=""
                        sha=$(research_sha256 "$snapshot" 2>/dev/null || true)
                        [[ -n "$sha" ]] && independence="content:$sha"
                        canonical="${RESEARCH_FETCH_FINAL_URL:-$canonical}"
                    else
                        status="fetch_failed"; reason="blocked_or_unavailable"
                    fi
                fi
            else
                host=""; status="rejected"; reason="unsafe_url"; independence="rejected:$source_id"
            fi
            printf '{"source_id":%s,"url":%s,"canonical_url":%s,"publisher":%s,"provider_artifact":%s,"retrieved_at":%s,"fetch_status":%s,"reason":%s,"content_sha256":%s,"independence_key":%s}\n' \
                "$(research_json_string "$source_id")" "$(research_json_string "$url")" \
                "$(research_json_string "$canonical")" "$(research_json_string "$host")" \
                "$(research_json_string "$(basename "$result")")" \
                "$(research_json_string "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")" \
                "$(research_json_string "$status")" "$(research_json_string "$reason")" \
                "$(research_json_string "$sha")" "$(research_json_string "$independence")" >> "$tmp"
        done < <(grep -Eo "https://[^][()<>{}\"'[:space:]]+" "$result" 2>/dev/null || true)
    done
    mv -f "$tmp" "$sources"; rm -f "$seen"
    {
        echo "# Research Source Catalog"
        echo
        if [[ "$index" -eq 0 ]]; then
            echo "No external source URLs were found. Treat provider conclusions as analysis, not independent evidence."
        else
            local sid surl spub sind sstatus
            while IFS= read -r sid; do
                surl=$(research_source_field "$sources" "$sid" canonical_url)
                spub=$(research_source_field "$sources" "$sid" publisher)
                sind=$(research_source_field "$sources" "$sid" independence_key)
                sstatus=$(research_source_field "$sources" "$sid" fetch_status)
                printf -- '- [source:%s] %s (publisher: %s; independence: %s; snapshot: %s)\n' \
                    "$sid" "$surl" "${spub:-unknown}" "$sind" "$sstatus"
            done < <(sed -n 's/.*"source_id":"\([^"]*\)".*/\1/p' "$sources")
        fi
    } > "$catalog"
    research_run_update "evidence_ready" "running" "sources=$index fetched=$fetched"
}

research_source_catalog() {
    [[ -r "${RESEARCH_RUN_DIR:-}/source-catalog.md" ]] && cat "$RESEARCH_RUN_DIR/source-catalog.md"
}

research_normalize_snapshot() {
    sed 's/<[^>]*>/ /g; s/&quot;/"/g; s/&#39;/'"'"'/g; s/&nbsp;/ /g; s/&amp;/\&/g' "$1" 2>/dev/null \
        | tr '\n\r\t' '   ' | sed 's/[[:space:]][[:space:]]*/ /g'
}

research_verify_synthesis() {
    local draft="$1" run_dir="${RESEARCH_RUN_DIR:?}"
    local sources="$run_dir/sources.jsonl" claims="$run_dir/claims.jsonl"
    local report="$run_dir/verification.json" findings="$run_dir/.verification-findings.$$"
    : > "$claims"; : > "$findings"
    local claim_count=0 failures=0 warnings=0 line_no=0 line plain_line ids id invalid groups group unique_groups
    local in_fence=false
    local snapshot normalized number quote numbers quotes score source_json groups_json
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_no=$((line_no + 1))
        if [[ "$line" == '```'* ]]; then
            if [[ "$in_fence" == "true" ]]; then
                in_fence=false
            else
                in_fence=true
            fi
            continue
        fi
        [[ "$in_fence" == "true" ]] && continue
        [[ -n "${line//[[:space:]]/}" ]] || continue
        [[ "$line" == \#* || "$line" == '---'* ]] && continue
        ids=$(printf '%s\n' "$line" | grep -Eo '\[source:S[0-9]{3}\]' | sed 's/\[source:\(.*\)\]/\1/' | sort -u || true)
        plain_line=$(printf '%s\n' "$line" | sed 's/\[source:S[0-9][0-9][0-9]\]//g')
        numbers=$(research_extract_numbers "$plain_line")
        quotes=$(printf '%s\n' "$plain_line" | awk '{ s=$0; while (match(s, /"[^"][^"][^"][^"]+"/)) { print substr(s,RSTART+1,RLENGTH-2); s=substr(s,RSTART+RLENGTH) } }')
        if [[ -z "$ids" && ( -n "$numbers" || -n "$quotes" ) \
              && "$line" != *"[inference]"* && "$line" != *"[opinion"* ]]; then
            failures=$((failures + 1))
            printf 'missing_citation|%s|%s\n' "$line_no" "$line" >> "$findings"
            continue
        fi
        [[ -n "$ids" ]] || continue
        claim_count=$((claim_count + 1)); invalid=false; groups=""; source_json=""; groups_json=""
        while IFS= read -r id; do
            [[ -n "$id" ]] || continue
            if ! grep -c '"source_id":"'"$id"'"' "$sources" >/dev/null 2>&1; then
                invalid=true
                printf 'unknown_source|%s|%s\n' "$line_no" "$id" >> "$findings"
                continue
            fi
            group=$(research_source_field "$sources" "$id" independence_key)
            groups="${groups}${group}"$'\n'
            source_json="${source_json}${source_json:+,}\"${id}\""
        done <<< "$ids"
        unique_groups=$(printf '%s' "$groups" | sed '/^$/d' | sort -u | wc -l | tr -d ' ')
        groups_json=$(printf '%s' "$groups" | sed '/^$/d' | sort -u | awk 'BEGIN{s=""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); s=s (s?",":"") "\"" $0 "\""} END{print s}')
        local cited_count
        cited_count=$(printf '%s\n' "$ids" | sed '/^$/d' | wc -l | tr -d ' ')
        score=$(awk -v u="${unique_groups:-0}" -v c="${cited_count:-1}" 'BEGIN { if (c < 1) c=1; printf "%.3f", u/c }')
        if [[ "$line" =~ [Cc]onsensus|[Ss]ources[[:space:]]+agree|[Mm]ultiple[[:space:]]+(independent[[:space:]]+)?sources|[Cc]orroborat ]] \
           && [[ "${unique_groups:-0}" -lt 2 ]]; then
            failures=$((failures + 1))
            printf 'false_consensus|%s|independent_groups=%s\n' "$line_no" "${unique_groups:-0}" >> "$findings"
        fi
        if [[ "$invalid" == "false" && ( -n "$numbers" || -n "$quotes" ) ]]; then
            while IFS= read -r number; do
                [[ -n "$number" ]] || continue
                local checked=false matched=false
                while IFS= read -r id; do
                    snapshot="$run_dir/snapshots/${id}.body"; [[ -r "$snapshot" ]] || continue
                    checked=true; research_number_in_snapshot "$number" "$snapshot" 2>/dev/null && matched=true
                done <<< "$ids"
                if [[ "$checked" == "true" && "$matched" != "true" ]]; then
                    failures=$((failures + 1)); printf 'number_mismatch|%s|%s\n' "$line_no" "$number" >> "$findings"
                elif [[ "$checked" != "true" ]]; then
                    warnings=$((warnings + 1)); printf 'number_unverified|%s|%s\n' "$line_no" "$number" >> "$findings"
                fi
            done <<< "$numbers"
            while IFS= read -r quote; do
                [[ -n "$quote" ]] || continue
                local checked=false matched=false
                while IFS= read -r id; do
                    snapshot="$run_dir/snapshots/${id}.body"; [[ -r "$snapshot" ]] || continue
                    checked=true
                    normalized="$run_dir/.normalized-${id}.$$"
                    research_normalize_snapshot "$snapshot" > "$normalized"
                    grep -Fic -- "$quote" "$normalized" >/dev/null 2>&1 && matched=true
                    rm -f "$normalized"
                done <<< "$ids"
                if [[ "$checked" == "true" && "$matched" != "true" ]]; then
                    failures=$((failures + 1)); printf 'quote_mismatch|%s|%s\n' "$line_no" "$quote" >> "$findings"
                elif [[ "$checked" != "true" ]]; then
                    warnings=$((warnings + 1)); printf 'quote_unverified|%s|%s\n' "$line_no" "$quote" >> "$findings"
                fi
            done <<< "$quotes"
        fi
        printf '{"claim_id":"C%03d","line":%s,"text":%s,"source_ids":[%s],"independence_groups":[%s],"independence_score":%s}\n' \
            "$claim_count" "$line_no" "$(research_json_string "$line")" \
            "$source_json" "$groups_json" "$score" >> "$claims"
    done < "$draft"
    local verification_status="passed"
    [[ "$failures" -gt 0 ]] && verification_status="failed"
    {
        printf '{\n'
        printf '  "status": %s,\n' "$(research_json_string "$verification_status")"
        printf '  "claims_checked": %s,\n' "$claim_count"
        printf '  "failures": %s,\n' "$failures"
        printf '  "warnings": %s,\n' "$warnings"
        printf '  "checks": [\n'
        local sep="" kind fline detail
        while IFS='|' read -r kind fline detail; do
            [[ -n "$kind" ]] || continue
            printf '%s    {"kind":%s,"line":%s,"detail":%s}' "$sep" \
                "$(research_json_string "$kind")" "${fline:-0}" "$(research_json_string "$detail")"
            sep=$',\n'
        done < "$findings"
        [[ -n "$sep" ]] && printf '\n'
        printf '  ]\n}\n'
    } > "$report"
    rm -f "$findings"
    research_run_event "$run_dir" "verification.completed" "status=$verification_status failures=$failures warnings=$warnings" || true
    [[ "$failures" -eq 0 ]]
}

research_resume_run() {
    local run_id="$1"
    OCTOPUS_RESEARCH_RUN_ID="$run_id" OCTOPUS_RESEARCH_RESUME=true \
        research_run_begin "$run_id" "" "standard" || return $?
    local final="$RESULTS_DIR/probe-synthesis-${RESEARCH_RUN_ID}.md"
    local draft="$RESEARCH_RUN_DIR/synthesis-draft.md"
    if [[ -r "$draft" ]]; then
        if research_verify_synthesis "$draft"; then
            cp "$draft" "$final"
            research_run_update "complete" "completed" "synthesis=$final"
            printf '%s\n' "$final"
            return 0
        fi
        research_run_update "verification_failed" "blocked" "report=$RESEARCH_RUN_DIR/verification.json"
        return 1
    fi
    research_collect_sources "$RESEARCH_TASK_GROUP" || return 1
    synthesize_probe_results "$RESEARCH_TASK_GROUP" "$RESEARCH_PROMPT" "0"
}

research_probe_single_begin() {
    local task_id="$1" prompt="$2"
    local evidence="${OCTOPUS_RESEARCH_EVIDENCE-true}"
    local intensity="${OCTOPUS_RESEARCH_INTENSITY-standard}"
    local configured_run_id="${OCTOPUS_RESEARCH_RUN_ID-}"
    [[ "$evidence" == "true" ]] || return 0
    [[ "$task_id" =~ ^probe-[0-9]+(-[0-9a-f]+)?-[0-9]+$ ]] || return 0
    local task_group
    task_group="${task_id#probe-}"
    task_group="${task_group%-*}"
    local run_id="$configured_run_id"
    [[ -n "$run_id" ]] || run_id="flow-$task_group"
    local run_dir
    run_dir=$(research_run_dir "$run_id") || return 1
    local begin_rc=0
    if [[ -r "$run_dir/manifest.json" ]]; then
        OCTOPUS_RESEARCH_RUN_ID="$run_id" OCTOPUS_RESEARCH_RESUME=true \
            research_run_begin "$task_group" "$prompt" "$intensity" || return $?
    else
        # Several probe children can reach this point together. The first
        # child owns run creation; later children must resume the run it just
        # created rather than treating the expected race as a hard failure.
        OCTOPUS_RESEARCH_RUN_ID="$run_id" OCTOPUS_RESEARCH_RESUME=false \
            research_run_begin "$task_group" "$prompt" "$intensity" || begin_rc=$?
        if [[ "$begin_rc" -eq 3 && -r "$run_dir/manifest.json" ]]; then
            OCTOPUS_RESEARCH_RUN_ID="$run_id" OCTOPUS_RESEARCH_RESUME=true \
                research_run_begin "$task_group" "$prompt" "$intensity" || return $?
        elif [[ "$begin_rc" -ne 0 ]]; then
            return "$begin_rc"
        fi
    fi
    research_run_event "$RESEARCH_RUN_DIR" "provider.started" "task_id=$task_id" || true
}

research_probe_single_record() {
    local task_id="$1" agent_type="$2" status="$3"
    [[ -n "$status" ]] || status="completed"
    [[ -n "${RESEARCH_RUN_DIR:-}" ]] || return 0
    research_run_event "$RESEARCH_RUN_DIR" "provider.completed" \
        "task_id=$task_id provider=$agent_type status=$status" || true
}

research_verify_run() {
    local run_id="$1" draft="$2"
    [[ -r "$draft" ]] || { printf 'Synthesis draft is not readable: %s\n' "$draft" >&2; return 2; }
    OCTOPUS_RESEARCH_RUN_ID="$run_id" OCTOPUS_RESEARCH_RESUME=true \
        research_run_begin "$run_id" "" "standard" || return $?
    research_collect_sources "$RESEARCH_TASK_GROUP" || return 1
    cp "$draft" "$RESEARCH_RUN_DIR/synthesis-draft.md" || return 1
    if research_verify_synthesis "$RESEARCH_RUN_DIR/synthesis-draft.md"; then
        local final="$RESULTS_DIR/probe-synthesis-$RESEARCH_RUN_ID.md"
        cp "$RESEARCH_RUN_DIR/synthesis-draft.md" "$final" || return 1
        research_run_update "complete" "completed" "synthesis=$final"
        printf '%s\n' "$final"
        return 0
    fi
    research_run_update "verification_failed" "blocked" "report=$RESEARCH_RUN_DIR/verification.json" || true
    return 1
}
