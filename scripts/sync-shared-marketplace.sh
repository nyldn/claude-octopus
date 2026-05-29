#!/usr/bin/env bash
# sync-shared-marketplace.sh - Sync the octo entry into nyldn/plugins.
#
# The shared marketplace contains multiple plugins. Never copy this repo's
# whole marketplace.json over it; only replace plugins[].name == "octo".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

MARKETPLACE_REPO="${OCTOPUS_SHARED_MARKETPLACE_REPO:-https://github.com/nyldn/plugins.git}"
MARKETPLACE_BRANCH="${OCTOPUS_SHARED_MARKETPLACE_BRANCH:-main}"
WORKDIR=""
CHECK_ONLY=0
PUSH=1

usage() {
    cat <<'EOF'
Usage: scripts/sync-shared-marketplace.sh [options]

Options:
  --check           Compare only; fail if the shared octo entry is stale.
  --repo URL       Shared marketplace git remote. Defaults to nyldn/plugins.
  --branch NAME    Shared marketplace branch. Defaults to main.
  --workdir DIR    Reuse or create a checkout at DIR instead of a temp dir.
  --no-push        Commit locally but do not push.
  -h, --help       Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)
            CHECK_ONLY=1
            shift
            ;;
        --repo)
            MARKETPLACE_REPO="${2:-}"
            [[ -n "$MARKETPLACE_REPO" ]] || { echo "ERROR: --repo requires a value" >&2; exit 2; }
            shift 2
            ;;
        --branch)
            MARKETPLACE_BRANCH="${2:-}"
            [[ -n "$MARKETPLACE_BRANCH" ]] || { echo "ERROR: --branch requires a value" >&2; exit 2; }
            shift 2
            ;;
        --workdir)
            WORKDIR="${2:-}"
            [[ -n "$WORKDIR" ]] || { echo "ERROR: --workdir requires a value" >&2; exit 2; }
            shift 2
            ;;
        --no-push)
            PUSH=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

for bin in git jq; do
    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "ERROR: $bin is required" >&2
        exit 1
    fi
done

LOCAL_MARKETPLACE="$ROOT_DIR/.claude-plugin/marketplace.json"
if [[ ! -f "$LOCAL_MARKETPLACE" ]]; then
    echo "ERROR: missing local marketplace manifest: $LOCAL_MARKETPLACE" >&2
    exit 1
fi

LOCAL_ENTRY="$(mktemp "${TMPDIR:-/tmp}/octo-marketplace-entry.XXXXXX")"
cleanup_entry() {
    rm -f "$LOCAL_ENTRY"
    if [[ -n "${TEMP_WORKDIR:-}" ]]; then
        rm -rf "$TEMP_WORKDIR"
    fi
}
trap cleanup_entry EXIT

if ! jq -e '.plugins | map(select(.name == "octo")) | if length == 1 then .[0] else error("expected exactly one octo entry") end' "$LOCAL_MARKETPLACE" > "$LOCAL_ENTRY"; then
    echo "ERROR: local marketplace manifest must have exactly one octo plugin entry" >&2
    exit 1
fi

OCTO_VERSION="$(jq -r '.version' "$LOCAL_ENTRY")"
if [[ -z "$OCTO_VERSION" || "$OCTO_VERSION" == "null" ]]; then
    echo "ERROR: local octo marketplace entry has no version" >&2
    exit 1
fi

if [[ -z "$WORKDIR" ]]; then
    TEMP_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/octo-shared-marketplace.XXXXXX")"
    WORKDIR="$TEMP_WORKDIR"
fi

checkout_marketplace() {
    if [[ -d "$WORKDIR/.git" ]]; then
        git -C "$WORKDIR" fetch --quiet origin "$MARKETPLACE_BRANCH"
        git -C "$WORKDIR" checkout --quiet "$MARKETPLACE_BRANCH"
        git -C "$WORKDIR" pull --ff-only --quiet origin "$MARKETPLACE_BRANCH"
        return 0
    fi

    if [[ -e "$WORKDIR" && -n "$(find "$WORKDIR" -mindepth 1 -maxdepth 1 2>/dev/null | head -n 1)" ]]; then
        echo "ERROR: --workdir exists but is not a git checkout: $WORKDIR" >&2
        exit 1
    fi

    rm -rf "$WORKDIR"
    git clone --quiet --branch "$MARKETPLACE_BRANCH" "$MARKETPLACE_REPO" "$WORKDIR"
}

checkout_marketplace

SHARED_MARKETPLACE="$WORKDIR/.claude-plugin/marketplace.json"
if [[ ! -f "$SHARED_MARKETPLACE" ]]; then
    echo "ERROR: shared marketplace checkout is missing .claude-plugin/marketplace.json" >&2
    exit 1
fi

if ! jq -e '.plugins | map(select(.name == "octo")) | length == 1' "$SHARED_MARKETPLACE" >/dev/null; then
    echo "ERROR: shared marketplace must have exactly one octo plugin entry" >&2
    exit 1
fi

canonical_octo_entry() {
    jq -S -c '.plugins | map(select(.name == "octo")) | .[0]' "$1"
}

LOCAL_CANONICAL="$(jq -S -c '.' "$LOCAL_ENTRY")"
SHARED_CANONICAL="$(canonical_octo_entry "$SHARED_MARKETPLACE")"

if [[ "$LOCAL_CANONICAL" == "$SHARED_CANONICAL" ]]; then
    echo "OK: shared marketplace octo entry is up to date (v$OCTO_VERSION)"
    exit 0
fi

if [[ "$CHECK_ONLY" -eq 1 ]]; then
    SHARED_VERSION="$(jq -r '.plugins | map(select(.name == "octo")) | .[0].version // empty' "$SHARED_MARKETPLACE")"
    echo "ERROR: shared marketplace octo entry is stale (shared=$SHARED_VERSION, local=$OCTO_VERSION)" >&2
    exit 1
fi

TMP_MARKETPLACE="$(mktemp "${TMPDIR:-/tmp}/octo-shared-marketplace-json.XXXXXX")"
jq --slurpfile octo "$LOCAL_ENTRY" '(.plugins[] | select(.name == "octo")) = $octo[0]' \
    "$SHARED_MARKETPLACE" > "$TMP_MARKETPLACE"
mv "$TMP_MARKETPLACE" "$SHARED_MARKETPLACE"

if git -C "$WORKDIR" diff --quiet -- .claude-plugin/marketplace.json; then
    echo "OK: shared marketplace octo entry is up to date (v$OCTO_VERSION)"
    exit 0
fi

git -C "$WORKDIR" add .claude-plugin/marketplace.json
git -C "$WORKDIR" commit --quiet -m "chore: update octopus marketplace to v$OCTO_VERSION"

if [[ "$PUSH" -eq 1 ]]; then
    git -C "$WORKDIR" push --quiet origin "$MARKETPLACE_BRANCH"
    echo "OK: shared marketplace pushed: octo v$OCTO_VERSION"
else
    echo "OK: shared marketplace committed locally: octo v$OCTO_VERSION"
fi
