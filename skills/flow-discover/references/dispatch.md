### STEP 4: Launch Parallel Agent Subagents (MANDATORY - Use Agent Tool)

Restore the literal `OCTO_ROOT`, `RUN_ID`, `RUN_TIMESTAMP` and `RUN_NONCE` printed
by the bootstrap. Set `OCTO_RESEARCH_ROOT` to that same root. Carry these values
through every separate shell and child prompt, including after compaction. Do
not generate or look up a newer run ID to replace this invocation's identity.


**Launch each perspective as a background Agent subagent.** Each agent calls `orchestrate.sh probe-single` which handles persona application, credential isolation, result file writing, and durable evidence-run recording. Pass the nonce-bearing `$RUN_ID` to every child and include `$RUN_NONCE` in every task ID so parallel runs cannot share result filenames.

Use the host's supported background-delegation interface for each perspective.
On Claude Code, use `Agent` with `run_in_background: true`. On Codex or another
host, use the exposed equivalent and follow that host's tool rules. Do not invent
an `Agent` tool or unsupported arguments. Launch providers strictly in the runtime
`FLEET_OUTPUT` sequence.

For each perspective in the fleet, the Claude Code call is:

```
Agent(
  run_in_background: true,
  description: "<label> (<agent_type>)",
  prompt: "Run this command and return its COMPLETE stdout output, including the result file path on the last line:

"$OCTO_RESEARCH_ROOT/scripts/orchestrate.sh" probe-single <agent_type> '<perspective_prompt>' <task_id> '<original_prompt>' --research-run '<run_id>'

After the command completes, read the result file path that was printed and return the full file contents."
)
```

Replace `<run_id>` with the current nonce-bearing `$RUN_ID` value when creating each Agent prompt. Substitute the resolved `$OCTO_RESEARCH_ROOT` as a literal quoted path in each child command. Reuse that installation for evidence verification; do not resolve a different root midway through the run.

**Launch order:** Iterate the parsed `FLEET_OUTPUT` order from `build-fleet.sh`. Launch all entries from that runtime fleet in parallel when possible; do not reorder by hardcoded provider names.

**CRITICAL: You are PROHIBITED from:**
- ❌ Researching directly without calling orchestrate.sh probe-single — single-model research misses perspectives that Codex (implementation depth) and Antigravity (ecosystem breadth) bring
- ❌ Using a single `Bash(orchestrate.sh probe)` call — this causes the 120s Bash timeout that this refactor fixes
- ❌ Using web search instead of orchestrate.sh
- ❌ Claiming you're "simulating" the workflow


### STEP 5: Collect Results (MANDATORY - Wait for Background Agents)

**Wait for all background agents to complete.** You will be automatically notified as each finishes.

**Minimum 2 results required** (same threshold as synthesize_probe_results()). Graceful degradation rules:
- 0 results -> Report error, show logs, DO NOT proceed
- 1 result -> Warn user, proceed with reduced synthesis quality
- 2+ results -> Proceed normally
- If some agents fail/timeout, proceed with successful results

**For each completed agent, collect its output** (the result file contents returned by the agent).

Run the status table before synthesis:

```bash
"${OCTO_ROOT:?}/scripts/orchestrate.sh" agent-summary
```

Only cite providers with usable output (`ok`, `degraded`, or timeout with partial content). Failed provider output, context-limit errors, and empty outputs are evidence of coverage gaps only.
