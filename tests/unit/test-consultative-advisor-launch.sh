#!/usr/bin/env bash
# Brainstorm Team mode and /octo:debate collect each advisor's answer through
# octo_launch_advisors. `orchestrate.sh spawn` is asynchronous for every
# provider except agy: it prints status lines and the worker PID, then returns
# while the worker is still running, and the answer lands later in the worker's
# result file. The launcher used to save spawn's own stdout as the answer and
# count a seat as successful whenever spawn exited 0, so a debate was scored on
# log lines and PIDs. The brainstorm Team precheck also looked for
# `spawn <agent>` in the no-argument quick-start text, which never lists it, so
# Team mode stopped before dispatching anything (#1118).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../helpers/test-framework.sh"
test_suite "consultative advisor launch"

unset OCTO_ALLOWED_PROVIDERS OCTOPUS_AGENT_LIFECYCLE_HOOK OCTOPUS_ADVISOR_WAIT_SECONDS
# shellcheck source=/dev/null
source "$PROJECT_ROOT/scripts/lib/consultative-advisors.sh"

ORCH="$PROJECT_ROOT/scripts/orchestrate.sh"
BRAINSTORM_FILES=(
    "$PROJECT_ROOT/commands/brainstorm.md"
    "$PROJECT_ROOT/.cursor-plugin/commands/octo-brainstorm.md"
)
DEBATE_FILES=(
    "$PROJECT_ROOT/.claude/skills/skill-debate/SKILL.md"
    "$PROJECT_ROOT/skills/skill-debate/SKILL.md"
)
STUB_ANSWER="$(printf '%s\n' \
    'STUB CODEX ANSWER 4242' \
    '## Output' \
    '```text' \
    'an answer may quote a fenced block of its own' \
    '```' \
    'final answer line')"

# The real orchestrator runs against a stub codex. As in the other real-spawn
# suites, the stub directories come first on PATH and the caller's PATH follows,
# so `#!/usr/bin/env bash` finds the same bash as the caller (Homebrew bash on
# macOS, not /bin/bash 3.2). Every other provider CLI is shadowed by a tripwire
# that fails; any call but a `--version` probe is recorded, so the last case
# can show that no real provider was reached. Every piece of Octopus state
# stays inside the test directory.
E2E="$TEST_TMP_DIR/e2e"
TRIPWIRE_CLIS=(claude grok gemini agy qwen copilot kimi ollama opencode agent
    cursor-agent vibe droid command-code perplexity)
mkdir -p "$E2E/answer-bin" "$E2E/fail-bin" "$E2E/tripwire-bin" \
    "$E2E/home/.claude-octopus" "$E2E/data" "$E2E/project" "$E2E/tmp"
for cli in "${TRIPWIRE_CLIS[@]}"; do
    cat > "$E2E/tripwire-bin/$cli" <<SH
#!/usr/bin/env bash
[[ "\$*" == --version ]] ||
    printf '%s %s\n' "\${0##*/}" "\$*" >> "$E2E/tripwire.log"
exit 1
SH
    chmod +x "$E2E/tripwire-bin/$cli"
done
ln -s "$PROJECT_ROOT" "$E2E/home/.claude-octopus/plugin"
printf '%s\n' "$STUB_ANSWER" > "$E2E/answer.txt"
cat > "$E2E/answer-bin/codex" <<SH
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then
    printf '%s\n' 'codex-cli 0.155.1'
    exit 0
fi
cat >/dev/null
# Answer only after spawn has printed its worker PID and returned.
sleep 3
printf '%s\n' 'stub codex progress note on stderr' >&2
cat "$E2E/answer.txt"
SH
cat > "$E2E/fail-bin/codex" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
    printf '%s\n' 'codex-cli 0.155.1'
    exit 0
fi
cat >/dev/null
printf '%s\n' 'stub codex: simulated provider failure' >&2
exit 1
SH
chmod +x "$E2E/answer-bin/codex" "$E2E/fail-bin/codex"
cat > "$E2E/fleet-builder.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'codex|Problem Analysis|fixture'
SH
chmod +x "$E2E/fleet-builder.sh"

# Run a command with the stub codex (answer-bin, or fail-bin when
# STUB_CODEX_BIN says so) and the test's isolated Octopus state.
in_stub_env() {
    (
        export "HOME=$E2E/home" "CLAUDE_PLUGIN_DATA=$E2E/data" \
            "CLAUDE_PLUGIN_ROOT=$PROJECT_ROOT" "OCTOPUS_PROJECT_DIR=$E2E/project" \
            "TMPDIR=$E2E/tmp" "OCTOPUS_SKIP_PROVIDER_PROBES=true" "OPENAI_API_KEY=test-only" \
            "PATH=$E2E/${STUB_CODEX_BIN:-answer-bin}:$E2E/tripwire-bin:$PATH" \
            "OCTO_ALLOWED_PROVIDERS=${STUB_ALLOWED_PROVIDERS:-codex}" \
            "OCTOPUS_FLEET_BUILDER=$E2E/fleet-builder.sh" \
            "OCTOPUS_ADVISOR_WAIT_SECONDS=180"
        cd "$E2E/project"
        "$@"
    )
}

# Print the Step 2c dispatch block of a brainstorm command file.
team_block() {
    awk '/^#### Step 2c/ { step = 1 }
         step && /^```bash$/ { on = 1; next }
         on && /^```$/ { exit }
         on' "$1"
}

test_case "an asynchronous spawn's answer comes from its result file, not spawn's stdout"
out="$TEST_TMP_DIR/answer"
mkdir -p "$out"
rc=0
count="$(in_stub_env octo_launch_advisors "$ORCH" codex "$out" octopus-brainstorm- \
    'Say hello, {{advisor}}' 1 2>"$TEST_TMP_DIR/answer.err")" || rc=$?
response="$out/octopus-brainstorm-codex.md"
if [[ "$rc" -eq 0 && "$count" == 1 && -f "$response" &&
      "$(< "$response")" == "$STUB_ANSWER" ]]; then
    test_pass
else
    test_fail "rc=$rc count='$count' response: $(head -c 600 "$response" 2>/dev/null | tr '\n' '|')"
fi

test_case "the collected answer holds no worker PID, spawn status line or stderr transcript"
if [[ -f "$response" ]] &&
   ! grep -Eq '^[0-9]+$' "$response" &&
   ! grep -Eq 'Agent spawned|Spawning codex|^(INFO|SUCCESS|WARN|ERROR):' "$response" &&
   ! grep -Fq 'stub codex progress note on stderr' "$response" &&
   ! grep -Eq 'UNTRUSTED|^## (Status|Warnings/Errors|Runtime Identity)' "$response"; then
    test_pass
else
    test_fail "response carries spawn or result-file metadata: $(head -c 600 "$response" 2>/dev/null | tr '\n' '|')"
fi

test_case "a provider that fails is not counted and leaves no response, even a stale one"
out="$TEST_TMP_DIR/failed"
mkdir -p "$out"
response="$out/octopus-brainstorm-codex.md"
printf '%s\n' 'stale answer from an earlier attempt' > "$response"
rc=0
count="$(STUB_CODEX_BIN=fail-bin in_stub_env octo_launch_advisors "$ORCH" codex "$out" \
    octopus-brainstorm- 'Say hello, {{advisor}}' 1 2>"$TEST_TMP_DIR/failed.err")" || rc=$?
if [[ "$rc" -ne 0 && -z "$count" && ! -e "$response" ]]; then
    test_pass
else
    test_fail "rc=$rc count='$count' response left: $(head -c 300 "$response" 2>/dev/null | tr '\n' '|')"
fi

# A spawn that prints a worker PID but whose lifecycle events were never
# recorded cannot be read back; its stdout must not stand in for the answer.
fake_orch="$TEST_TMP_DIR/orch-unrecorded"
cat > "$fake_orch" <<'SH'
#!/usr/bin/env bash
[[ "${1:-}" == spawn ]] || exit 64
printf '%s\n' 'SUCCESS: stub status line' 424242
SH
chmod +x "$fake_orch"
test_case "a worker PID with no recorded lifecycle events is not counted"
out="$TEST_TMP_DIR/unrecorded"
mkdir -p "$out"
rc=0
count="$(octo_launch_advisors "$fake_orch" codex "$out" t- 'x' 1 2>"$TEST_TMP_DIR/unrecorded.err")" || rc=$?
if [[ "$rc" -ne 0 && -z "$count" && ! -e "$out/t-codex.md" ]] &&
   grep -q 'lifecycle events were not recorded' "$TEST_TMP_DIR/unrecorded.err"; then
    test_pass
else
    test_fail "rc=$rc count='$count' stderr: $(tr '\n' '|' < "$TEST_TMP_DIR/unrecorded.err")"
fi

# Timeout fixtures own their late processes and remove retained work files only
# after stopping those processes. Production leaves late jobs running.
cleanup_retained_advisor_files() {
    local error_file="$1" retained
    retained="$(sed -n 's/^WARNING: advisor work files retained for late jobs: //p' "$error_file")"
    [[ -z "$retained" ]] || rm -rf "$retained"
}

# agy runs synchronously inside spawn and prints the answer itself.
fake_orch="$TEST_TMP_DIR/orch-sync"
cat > "$fake_orch" <<'SH'
#!/usr/bin/env bash
[[ "${1:-}" == spawn ]] || exit 64
printf 'synchronous answer from %s\n' "$2"
SH
chmod +x "$fake_orch"
test_case "a synchronous spawn's stdout is still the answer"
out="$TEST_TMP_DIR/sync"
mkdir -p "$out"
rc=0
count="$(octo_launch_advisors "$fake_orch" agy "$out" t- 'x' 1 2>/dev/null)" || rc=$?
if [[ "$rc" -eq 0 && "$count" == 1 && "$(< "$out/t-agy.md")" == 'synchronous answer from agy' ]]; then
    test_pass
else
    test_fail "rc=$rc count='$count'"
fi

# The deadline also bounds a synchronous spawn (agy), which runs the whole
# provider call inside spawn itself.
fake_orch="$TEST_TMP_DIR/orch-sync-stuck"
sync_stuck_pid_file="$TEST_TMP_DIR/sync-stuck.pid"
cat > "$fake_orch" <<SH
#!/usr/bin/env bash
[[ "\${1:-}" == spawn ]] || exit 64
printf '%s\n' "\$\$" > "$sync_stuck_pid_file"
exec sleep 30
SH
chmod +x "$fake_orch"
test_case "a synchronous spawn still running at the wait deadline is not counted"
out="$TEST_TMP_DIR/sync-stuck"
mkdir -p "$out"
rc=0
started="$(date +%s)"
count="$(OCTOPUS_ADVISOR_WAIT_SECONDS=2 octo_launch_advisors "$fake_orch" agy "$out" t- 'x' 1 \
    2>"$TEST_TMP_DIR/sync-stuck.err")" || rc=$?
elapsed=$(( $(date +%s) - started ))
kill "$(cat "$sync_stuck_pid_file" 2>/dev/null)" 2>/dev/null || true
# The stub outlives the 2 s wait by 28 s, so a launcher that ignores the deadline fails the bound.
if [[ "$rc" -ne 0 && -z "$count" && ! -e "$out/t-agy.md" && "$elapsed" -le 4 ]] &&
   grep -q 'did not finish before the wait deadline' "$TEST_TMP_DIR/sync-stuck.err"; then
    test_pass
else
    test_fail "rc=$rc count='$count' elapsed=${elapsed}s stderr: $(tr '\n' '|' < "$TEST_TMP_DIR/sync-stuck.err")"
fi

cleanup_retained_advisor_files "$TEST_TMP_DIR/sync-stuck.err"

# A worker that never completes is abandoned at OCTOPUS_ADVISOR_WAIT_SECONDS.
fake_orch="$TEST_TMP_DIR/orch-stuck"
stuck_pid_file="$TEST_TMP_DIR/stuck.pid"
cat > "$fake_orch" <<SH
#!/usr/bin/env bash
[[ "\${1:-}" == spawn ]] || exit 64
sleep 300 </dev/null >/dev/null 2>&1 &
worker=\$!
printf '%s\n' "\$worker" > "$stuck_pid_file"
[[ -z "\${OCTOPUS_AGENT_LIFECYCLE_HOOK:-}" ]] ||
    OCTOPUS_AGENT_PID="\$worker" OCTOPUS_AGENT_STATUS=running \
        OCTOPUS_AGENT_RESULT_FILE="$TEST_TMP_DIR/stuck-result.md" \
        "\$OCTOPUS_AGENT_LIFECYCLE_HOOK" spawned
printf '%s\n' 'INFO: Agent spawned' "\$worker"
SH
chmod +x "$fake_orch"
test_case "a worker still running at the wait deadline is not counted"
out="$TEST_TMP_DIR/stuck"
mkdir -p "$out"
rc=0
started="$(date +%s)"
count="$(OCTOPUS_ADVISOR_WAIT_SECONDS=2 octo_launch_advisors "$fake_orch" codex "$out" t- 'x' 1 \
    2>"$TEST_TMP_DIR/stuck.err")" || rc=$?
elapsed=$(( $(date +%s) - started ))
kill "$(cat "$stuck_pid_file" 2>/dev/null)" 2>/dev/null || true
if [[ "$rc" -ne 0 && -z "$count" && ! -e "$out/t-codex.md" && "$elapsed" -le 4 ]] &&
   grep -q 'did not finish before the wait deadline' "$TEST_TMP_DIR/stuck.err"; then
    test_pass
else
    test_fail "rc=$rc count='$count' elapsed=${elapsed}s stderr: $(tr '\n' '|' < "$TEST_TMP_DIR/stuck.err")"
fi

cleanup_retained_advisor_files "$TEST_TMP_DIR/stuck.err"

# A leading zero must not make the wait invalid octal (08, 09), zero, or the
# 3600 s default: "08" is eight seconds.
test_case "OCTOPUS_ADVISOR_WAIT_SECONDS=08 is read as eight seconds"
out="$TEST_TMP_DIR/stuck-08"
mkdir -p "$out"
rm -f "$stuck_pid_file"
rc=0
started="$(date +%s)"
count="$(OCTOPUS_ADVISOR_WAIT_SECONDS=08 octo_launch_advisors "$fake_orch" codex "$out" t- 'x' 1 \
    2>"$TEST_TMP_DIR/stuck-08.err")" || rc=$?
elapsed=$(( $(date +%s) - started ))
kill "$(cat "$stuck_pid_file" 2>/dev/null)" 2>/dev/null || true
if [[ "$rc" -ne 0 && -z "$count" && ! -e "$out/t-codex.md" && "$elapsed" -ge 8 && "$elapsed" -le 10 ]] &&
   grep -q 'did not finish before the wait deadline' "$TEST_TMP_DIR/stuck-08.err"; then
    test_pass
else
    test_fail "rc=$rc count='$count' elapsed=${elapsed}s stderr: $(tr '\n' '|' < "$TEST_TMP_DIR/stuck-08.err")"
fi

cleanup_retained_advisor_files "$TEST_TMP_DIR/stuck-08.err"

# Completed jobs remain waitable even when the shared deadline has passed.
test_case "a spawn completed at the deadline retains its success or failure status"
( exit 0 ) &
finished_pid=$!
( exit 7 ) &
failed_pid=$!
sleep 1
rc=0
_octo_advisor_wait_spawn "$finished_pid" "$(( $(date +%s) - 1 ))" || rc=$?
failed_rc=0
_octo_advisor_wait_spawn "$failed_pid" "$(( $(date +%s) - 1 ))" || failed_rc=$?
if [[ "$rc" -eq 0 && "$failed_rc" -eq 7 ]]; then
    test_pass
else
    test_fail "completed rc=$rc failed rc=$failed_rc"
fi

fake_orch="$TEST_TMP_DIR/orch-sync-failed"
cat > "$fake_orch" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'answer printed before provider failure'
exit 7
SH
chmod +x "$fake_orch"
test_case "a failed synchronous spawn is not counted despite printable stdout"
out="$TEST_TMP_DIR/sync-failed"
mkdir -p "$out"
rc=0
count="$(octo_launch_advisors "$fake_orch" agy "$out" t- x 1 2>"$out/error")" || rc=$?
if [[ "$rc" -ne 0 && -z "$count" && ! -e "$out/t-agy.md" ]]; then
    test_pass
else
    test_fail "rc=$rc count='$count'"
fi

fake_orch="$TEST_TMP_DIR/orch-multiple-stuck"
cat > "$fake_orch" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$\$" >> "$TEST_TMP_DIR/multiple.pids"
exec sleep 30
SH
chmod +x "$fake_orch"
test_case "multiple synchronous seats share one deadline and leave no answers"
out="$TEST_TMP_DIR/multiple"
mkdir -p "$out"
rc=0
started="$(date +%s)"
count="$(OCTOPUS_ADVISOR_WAIT_SECONDS=2 octo_launch_advisors "$fake_orch" agy,codex "$out" t- x 2 \
    2>"$out/error")" || rc=$?
elapsed=$(( $(date +%s) - started ))
late_count=0
while read -r fixture_pid; do
    kill -0 "$fixture_pid" 2>/dev/null && late_count=$((late_count + 1))
    kill "$fixture_pid" 2>/dev/null || true
done < "$TEST_TMP_DIR/multiple.pids"
if [[ "$rc" -ne 0 && -z "$count" && "$elapsed" -le 4 && "$late_count" -eq 2 &&
      ! -e "$out/t-agy.md" && ! -e "$out/t-codex.md" ]]; then
    test_pass
else
    test_fail "rc=$rc count='$count' elapsed=${elapsed}s late=$late_count"
fi
cleanup_retained_advisor_files "$out/error"

fake_orch="$TEST_TMP_DIR/orch-finished-seat"
cat > "$fake_orch" <<SH
#!/usr/bin/env bash
if [[ "\$2" == agy ]]; then
    printf '%s\n' "\$\$" > "$TEST_TMP_DIR/finished-seat.pid"
    exec sleep 30
fi
result="$TEST_TMP_DIR/finished-seat-result.md"
printf '%s\n' '# Started: now' '## Output' '\`\`\`' 'finished answer' '\`\`\`' '## Status: SUCCESS' > "\$result"
OCTOPUS_AGENT_PID="\$\$" OCTOPUS_AGENT_STATUS=running OCTOPUS_AGENT_RESULT_FILE="\$result" \
    "\$OCTOPUS_AGENT_LIFECYCLE_HOOK" spawned
OCTOPUS_AGENT_PID="\$\$" OCTOPUS_AGENT_STATUS=completed OCTOPUS_AGENT_RESULT_FILE="\$result" \
    "\$OCTOPUS_AGENT_LIFECYCLE_HOOK" completed
printf '%s\n' "\$\$"
SH
chmod +x "$fake_orch"
test_case "a finished asynchronous seat counts after an earlier seat consumes the deadline"
out="$TEST_TMP_DIR/finished-seat"
mkdir -p "$out"
rc=0
count="$(OCTOPUS_ADVISOR_WAIT_SECONDS=2 octo_launch_advisors "$fake_orch" agy,codex "$out" t- x 1 \
    2>"$out/error")" || rc=$?
kill "$(cat "$TEST_TMP_DIR/finished-seat.pid")" 2>/dev/null || true
if [[ "$rc" -eq 0 && "$count" == 1 && ! -e "$out/t-agy.md" &&
      "$(cat "$out/t-codex.md" 2>/dev/null)" == 'finished answer' ]]; then
    test_pass
else
    test_fail "rc=$rc count='$count'"
fi
cleanup_retained_advisor_files "$out/error"

# The watchdog makes this test bounded even if wait regresses on stopped jobs.
fake_orch="$TEST_TMP_DIR/orch-stopped"
cat > "$fake_orch" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$\$" > "$TEST_TMP_DIR/stopped.pid"
kill -STOP "\$\$"
printf '%s\n' 'resumed answer'
SH
chmod +x "$fake_orch"
test_case "a stopped synchronous spawn cannot bypass the shared deadline"
out="$TEST_TMP_DIR/stopped"
mkdir -p "$out"
(
    sleep 6
    fixture_pid="$(cat "$TEST_TMP_DIR/stopped.pid" 2>/dev/null)"
    [[ -z "$fixture_pid" ]] || {
        kill -TERM "$fixture_pid" 2>/dev/null || true
        kill -CONT "$fixture_pid" 2>/dev/null || true
    }
) </dev/null >/dev/null 2>&1 &
watchdog=$!
rc=0
started="$(date +%s)"
count="$(OCTOPUS_ADVISOR_WAIT_SECONDS=2 octo_launch_advisors "$fake_orch" agy "$out" t- x 1 \
    2>"$out/error")" || rc=$?
elapsed=$(( $(date +%s) - started ))
fixture_pid="$(cat "$TEST_TMP_DIR/stopped.pid")"
kill -TERM "$fixture_pid" 2>/dev/null || true
kill -CONT "$fixture_pid" 2>/dev/null || true
kill "$watchdog" 2>/dev/null || true
wait "$watchdog" 2>/dev/null || true
if [[ "$rc" -ne 0 && -z "$count" && "$elapsed" -le 4 && ! -e "$out/t-agy.md" ]] &&
   grep -q 'did not finish before the wait deadline' "$out/error"; then
    test_pass
else
    test_fail "rc=$rc count='$count' elapsed=${elapsed}s"
fi
cleanup_retained_advisor_files "$out/error"

# Late synchronous and asynchronous jobs must still be able to execute the
# chained lifecycle hook after the launcher has returned at its deadline.
fake_orch="$TEST_TMP_DIR/orch-late-hook"
cat > "$fake_orch" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$OCTOPUS_AGENT_LIFECYCLE_HOOK" > "$TEST_TMP_DIR/late-hook-\$2.path"
finish() {
    sleep 3
    OCTOPUS_AGENT_PID="\$\$" OCTOPUS_AGENT_STATUS=completed \
        "\$OCTOPUS_AGENT_LIFECYCLE_HOOK" completed "\$2"
}
if [[ "\$2" == agy ]]; then
    finish "\$@"
else
    finish "\$@" </dev/null >/dev/null 2>&1 &
    worker=\$!
    OCTOPUS_AGENT_PID="\$worker" OCTOPUS_AGENT_STATUS=running \
        "\$OCTOPUS_AGENT_LIFECYCLE_HOOK" spawned "\$2"
    printf '%s\n' "\$worker"
fi
SH
prev_hook="$TEST_TMP_DIR/previous-hook"
cat > "$prev_hook" <<SH
#!/usr/bin/env bash
[[ "\$1" != completed ]] || printf '%s\n' "\$2" >> "$TEST_TMP_DIR/late-completed"
SH
chmod +x "$fake_orch" "$prev_hook"
test_case "late spawns and workers retain their lifecycle hooks after timeout"
out="$TEST_TMP_DIR/late-hooks"
mkdir -p "$out"
rc=0
OCTOPUS_AGENT_LIFECYCLE_HOOK="$prev_hook" OCTOPUS_ADVISOR_WAIT_SECONDS=1 \
    octo_launch_advisors "$fake_orch" agy,codex "$out" t- x 2 >"$out/count" 2>"$out/error" || rc=$?
retained_hook="$(cat "$TEST_TMP_DIR/late-hook-agy.path")"
hook_was_retained=false
[[ ! -x "$retained_hook" ]] || hook_was_retained=true
sleep 4
if [[ "$rc" -ne 0 && ! -s "$out/count" && "$hook_was_retained" == true &&
      ! -e "$out/t-agy.md" && ! -e "$out/t-codex.md" ]] &&
   grep -qx agy "$TEST_TMP_DIR/late-completed" && grep -qx codex "$TEST_TMP_DIR/late-completed"; then
    test_pass
else
    test_fail "rc=$rc retained=$hook_was_retained completed=$(cat "$TEST_TMP_DIR/late-completed" 2>/dev/null)"
fi
cleanup_retained_advisor_files "$out/error"

for file in "${BRAINSTORM_FILES[@]}"; do
    rel="${file#"$PROJECT_ROOT"/}"
    test_case "$rel: the Team precheck finds spawn in the orchestrator's real help"
    precheck="$(team_block "$file" | awk '/^ORCH_HELP=/ { on = 1 } on { print } on && /does not expose spawn/ { exit }')"
    rc=0
    precheck_out="$(in_stub_env env "ORCH=$ORCH" bash -c "$precheck" 2>&1)" || rc=$?
    # The same lines must still reject an orchestrator that does not offer spawn.
    no_spawn_rc=0
    env "ORCH=/bin/true" bash -c "$precheck" >/dev/null 2>&1 || no_spawn_rc=$?
    if [[ -n "$precheck" && "$rc" -eq 0 && "$no_spawn_rc" -ne 0 ]]; then
        test_pass
    else
        test_fail "precheck rc=$rc (no-spawn rc=$no_spawn_rc): $(printf '%s' "$precheck_out" | tail -3 | tr '\n' '|')"
    fi
done

test_case "commands/brainstorm.md: the Team block prints every collected answer before it exits"
rc=0
block_out="$(STUB_ALLOWED_PROVIDERS='codex claude' in_stub_env \
    bash -c "$(team_block "$PROJECT_ROOT/commands/brainstorm.md")" 2>"$TEST_TMP_DIR/team.err")" || rc=$?
if [[ "$rc" -eq 0 ]] &&
   grep -qx 'SUCCESSFUL_EXTERNAL_ADVISORS=1' <<< "$block_out" &&
   grep -Fqx 'STUB CODEX ANSWER 4242' <<< "$block_out" &&
   grep -Fqx 'final answer line' <<< "$block_out"; then
    test_pass
else
    test_fail "rc=$rc stdout: $(printf '%s' "$block_out" | tail -5 | tr '\n' '|') stderr: $(tail -3 "$TEST_TMP_DIR/team.err" | tr '\n' '|')"
fi

# The generated Codex copy of a skill names the host's background option
# differently, so only the word "background", the foreground timeout and the
# launcher's own wait limit are required.
has_wait_guidance() {
    grep -q 'background' <<< "$1" && grep -q '600000 ms timeout' <<< "$1" &&
        grep -q 'OCTOPUS_ADVISOR_WAIT_SECONDS' <<< "$1"
}
test_case "brainstorm Team and debate Step 5 say the launch waits for every advisor"
missing=""
for file in "${BRAINSTORM_FILES[@]}"; do
    section="$(awk '/^#### Step 2c/ { on = 1 } /^\*\*Claude Agent\*\*/ { on = 0 } on' "$file")"
    has_wait_guidance "$section" || missing+="${file#"$PROJECT_ROOT"/} "
done
for file in "${DEBATE_FILES[@]}"; do
    section="$(awk '/^### Step 5/ { on = 1 } /^#### 5\.2/ { on = 0 } on' "$file")"
    has_wait_guidance "$section" || missing+="${file#"$PROJECT_ROOT"/} "
done
if [[ -z "$missing" ]]; then
    test_pass
else
    test_fail "no background/timeout guidance in: $missing"
fi

# Runs last, so the tripwire log covers every stub-environment run above.
test_case "the stub environment resolves every provider CLI to a stub and reached no real one"
wrong=""
for bin in answer-bin fail-bin; do
    resolved="$(STUB_CODEX_BIN="$bin" in_stub_env command -v codex || true)"
    [[ "$resolved" == "$E2E/$bin/codex" ]] || wrong+="codex=$resolved "
done
for cli in "${TRIPWIRE_CLIS[@]}"; do
    resolved="$(in_stub_env command -v "$cli" || true)"
    [[ "$resolved" == "$E2E/tripwire-bin/$cli" ]] || wrong+="$cli=$resolved "
done
if [[ -z "$wrong" && ! -s "$E2E/tripwire.log" ]]; then
    test_pass
else
    test_fail "resolved outside the stubs: ${wrong:-none}; tripwire calls: $(tr '\n' '|' < "$E2E/tripwire.log" 2>/dev/null)"
fi

test_summary
