#!/usr/bin/env bash
# Regression: concurrent run_agent_sync calls must not share capture files.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/octo-sync-parallel.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

export RESULTS_DIR="$TEST_DIR/results"
mkdir -p "$RESULTS_DIR"
RUNNER="$TEST_DIR/provider.sh"
cat > "$RUNNER" <<'RUNNER'
#!/usr/bin/env bash
read -r prompt
case "$1" in
  claude-sonnet) sleep 0.2 ;;
  claude-opus) sleep 0.8 ;;
esac
printf '%s:%s\n' "$1" "$prompt"
RUNNER
chmod +x "$RUNNER"

export RUNNER
export OCTOPUS_PERSISTENCE_AVAILABLE=true
export OCTOPUS_AGENT_MAX_OUTPUT_BYTES=262144

log() { :; }
classify_task() { echo standard; }
compute_dynamic_timeout() { echo 5; }
get_role_for_context() { echo reviewer; }
apply_persona() { printf '%s\n' "$2"; }
get_persona_override() { :; }
load_earned_skills() { :; }
build_provider_context() { :; }
enforce_context_budget() { printf '%s\n' "$1"; }
get_agent_model() { echo test-model; }
check_provider_health() { return 0; }
record_agent_call() { :; }
get_agent_command() { printf 'bash %s %s\n' "$RUNNER" "$1"; }
build_provider_env() { PROVIDER_ENV_ARRAY=(); }
run_with_timeout() { shift; "$@"; }
stop_quota_watcher() { :; }
classify_agent_output() { echo completed:ok; }
write_agent_status() { :; }
octo_estimate_tokens_for_file() { echo 1; }

source "$ROOT_DIR/scripts/lib/agent-sync.sh"

run_agent_sync claude-sonnet ALPHA 5 reviewer review > "$TEST_DIR/alpha.out" &
alpha_pid=$!
run_agent_sync claude-opus BETA 5 reviewer review > "$TEST_DIR/beta.out" &
beta_pid=$!

wait "$alpha_pid"
wait "$beta_pid"

grep -Fqx 'claude-sonnet:ALPHA' "$TEST_DIR/alpha.out" || {
  echo "FAIL: first concurrent provider lost or mixed its output" >&2
  cat "$TEST_DIR/alpha.out" >&2
  exit 1
}
grep -Fqx 'claude-opus:BETA' "$TEST_DIR/beta.out" || {
  echo "FAIL: second concurrent provider lost or mixed its output" >&2
  cat "$TEST_DIR/beta.out" >&2
  exit 1
}

if find "$RESULTS_DIR" -maxdepth 1 -name '.tmp-agent-*' -print -quit | grep -q .; then
  echo "FAIL: synchronous dispatch left capture files behind" >&2
  exit 1
fi

echo "PASS: concurrent synchronous agents use isolated capture files"
