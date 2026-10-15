#!/usr/bin/env bash
set -euo pipefail

model="${1:-${OCTOPUS_COMMANDCODE_MODEL:-deepseek/deepseek-v4-pro}}"
permission_mode="${2:-${OCTOPUS_COMMANDCODE_PERMISSION_MODE:-plan}}"

case "$model" in
  ''|*[!A-Za-z0-9._/-]*) echo "commandcode: invalid model id" >&2; exit 1 ;;
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
prompt_file="$(mktemp "${TMPDIR:-/tmp}/octopus-commandcode-prompt.XXXXXX")" || { rm -f "$tmp"; exit 1; }
cli_pid=""
cli_pgid=""
cli_group_isolated=0
heartbeat_pid=""
kill_process_tree() {
  local parent_pid="$1"
  local child_pid
  while read -r child_pid; do
    [[ "$child_pid" =~ ^[0-9]+$ ]] || continue
    kill_process_tree "$child_pid"
  done < <(ps -A -o pid= -o ppid= 2>/dev/null | awk -v parent="$parent_pid" '$2 == parent {print $1}')
  kill -KILL "$parent_pid" 2>/dev/null || true
}
kill_cli() {
  [[ -z "$cli_pid" ]] && return 0
  if [[ "$cli_group_isolated" -eq 1 && -n "$cli_pgid" ]]; then
    if ! kill -KILL -- "-$cli_pgid" 2>/dev/null; then
      kill_process_tree "$cli_pid"
    fi
  else
    kill_process_tree "$cli_pid"
  fi
  cli_pid=""
  cli_pgid=""
}
cleanup() {
  [[ -n "$heartbeat_pid" ]] && kill "$heartbeat_pid" 2>/dev/null || true
  kill_cli
  rm -f "$tmp" "$prompt_file"
}
trap cleanup EXIT
printf '%s' "$prompt" >"$prompt_file"

args=(-p --model "$model" --output-format json --skip-onboarding --no-auto-update --trust --no-session)
case "$permission_mode" in
  yolo) args+=(--yolo) ;;
  *) args+=(--permission-mode "$permission_mode") ;;
esac

# The CLI and its children must not outlive this helper. A stall watchdog or timeout that
# kills the helper would otherwise orphan an agent that keeps editing the
# worktree next to its own retry. An isolated process group and the watcher
# cover child processes when setsid is available; otherwise the watcher stops
# descendants before their CLI parent, keeping the tree discoverable.
cli_args=("$bin" "${args[@]}")
if command -v setsid >/dev/null 2>&1; then
  cli_args=(setsid "${cli_args[@]}")
  cli_group_isolated=1
fi
if [[ "$cli_group_isolated" -eq 1 ]]; then
  "${cli_args[@]}" <"$prompt_file" >"$tmp" &
else
  "${cli_args[@]}" <"$prompt_file" >"$tmp" &
fi
cli_pid=$!
if [[ "$cli_group_isolated" -eq 1 ]]; then
  # setsid creates the child session with the CLI PID as its process-group ID.
  # Reading it through ps here races with setsid() and can capture our own
  # process group, making a later negative kill target the dispatcher too.
  cli_pgid="$cli_pid"
fi
trap 'kill_cli; exit 143' TERM
trap 'kill_cli; exit 130' INT
trap 'kill_cli; exit 129' HUP

# stdout stays empty until the final result, so a stall watchdog that only
# sees output would kill a model that is still reading and planning. The CLI
# streams NDJSON events into $tmp; report on stderr while that stream grows.
# The same loop kills the CLI if this helper disappears, and stops on its own
# once the helper is gone, so it never spins on an unreaped (zombie) CLI. The
# helper counts as gone once this loop is reparented: an unreaped helper still
# answers kill -0, and its PID can be reused. Bash 3.2 has no BASHPID, so an
# exec'd sh reports this loop's own PID.
heartbeat_secs="${OCTOPUS_COMMANDCODE_HEARTBEAT_SECS:-60}"
[[ "$heartbeat_secs" =~ ^[1-9][0-9]*$ ]] || heartbeat_secs=60
helper_pid=$$
(
  exec >/dev/null
  last_size=0
  waited=0
  watcher_pid="$(exec /bin/sh -c 'echo "$PPID"')"
  while kill -0 "$cli_pid" 2>/dev/null; do
    sleep 1
    watcher_parent="$(ps -o ppid= -p "$watcher_pid" 2>/dev/null || true)"
    watcher_parent="${watcher_parent//[[:space:]]/}"
    if [[ -n "$watcher_parent" && "$watcher_parent" != "$helper_pid" ]] ||
       ! kill -0 "$helper_pid" 2>/dev/null; then
      kill_cli
      exit 0
    fi
    waited=$((waited + 1))
    (( waited < heartbeat_secs )) && continue
    waited=0
    size="$(wc -c <"$tmp" 2>/dev/null || echo 0)"
    size="${size//[[:space:]]/}"
    if [[ "$size" =~ ^[0-9]+$ ]] && (( size > last_size )); then
      printf 'commandcode: still working (%s bytes of events)\n' "$size" >&2
      last_size="$size"
    fi
  done
  kill_cli
) &
heartbeat_pid=$!

if wait "$cli_pid"; then
  rc=0
else
  rc=$?
fi
kill_cli
kill "$heartbeat_pid" 2>/dev/null || true
wait "$heartbeat_pid" 2>/dev/null || true
heartbeat_pid=""

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
