#!/usr/bin/env bash
set -euo pipefail

model="${1:-${OCTOPUS_COMMANDCODE_MODEL:-deepseek/deepseek-v4-pro}}"
permission_mode="${2:-${OCTOPUS_COMMANDCODE_PERMISSION_MODE:-plan}}"
max_turns="${OCTOPUS_COMMANDCODE_MAX_TURNS:-30}"

case "$model" in
  ''|*[!A-Za-z0-9._/-]*) echo "commandcode: invalid model id" >&2; exit 1 ;;
esac
case "$max_turns" in
  ''|*[!0-9]*) echo "commandcode: invalid max-turns" >&2; exit 1 ;;
esac
case "$permission_mode" in
  plan|default|dont-ask|auto-accept|yolo) ;;
  *) echo "commandcode: invalid permission mode" >&2; exit 1 ;;
esac

bin="${OCTOPUS_COMMANDCODE_BIN:-}"
if [[ -z "$bin" ]]; then
  if command -v command-code >/dev/null 2>&1; then
    bin="command-code"
  elif command -v cmd >/dev/null 2>&1; then
    bin="cmd"
  else
    echo "commandcode: CLI not found (install: npm i -g command-code@latest)" >&2
    exit 1
  fi
fi

prompt="$(cat)"
[[ -n "$prompt" ]] || { echo "commandcode: empty prompt" >&2; exit 1; }

tmp="$(mktemp "${TMPDIR:-/tmp}/octopus-commandcode.XXXXXX")" || exit 1
trap 'rm -f "$tmp"' EXIT INT TERM

args=(-p --model "$model" --output-format json --max-turns "$max_turns" --skip-onboarding --no-auto-update --trust --no-session)
case "$permission_mode" in
  yolo) args+=(--yolo) ;;
  *) args+=(--permission-mode "$permission_mode") ;;
esac

if printf '%s' "$prompt" | "$bin" "${args[@]}" >"$tmp"; then
  rc=0
else
  rc=$?
fi

result_line="$(awk 'BEGIN{line=""} /^\{/{line=$0} END{print line}' "$tmp")"
if [[ -z "$result_line" ]] || ! command -v jq >/dev/null 2>&1; then
  cat "$tmp"
  exit "$rc"
fi

subtype="$(printf '%s\n' "$result_line" | jq -r '.subtype // empty' 2>/dev/null || true)"
final_text="$(printf '%s\n' "$result_line" | jq -r '.finalText // empty' 2>/dev/null || true)"
error_text="$(printf '%s\n' "$result_line" | jq -r '.error.message // .error // empty' 2>/dev/null || true)"

[[ -n "$final_text" ]] && printf '%s\n' "$final_text"
if [[ "$subtype" == "error" ]]; then
  if [[ -n "$error_text" ]]; then
    printf 'commandcode: %s\n' "$error_text" >&2
  else
    printf 'commandcode: structured error result\n' >&2
  fi
  [[ "$rc" -ne 0 ]] || rc=1
fi
exit "$rc"
