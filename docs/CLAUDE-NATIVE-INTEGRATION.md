# Claude Code integrations

Octopus uses native Claude features where they help the current task. Cross-provider
review, fixed judging budgets and provider restrictions still apply.

## Advisor for Claude workers

Use an advisor when a Claude worker has a long implementation or debugging task
with a few difficult decisions. For short tasks, the extra consultation usually
adds little. In your current Claude session, use `/advisor opus`, or configure
`"advisorModel": "opus"` in user or project settings. Claude chooses when to
consult it. A skill can recommend a consultation but cannot guarantee a call.

For Octopus CLI workers, explicitly set `OCTOPUS_CLAUDE_ADVISOR=opus`. Supported
values are `off`, `opus`, `sonnet`, `fable`, and full `claude-*` model IDs. This
adds the documented `--advisor` launch argument to Claude Code seats only. It
requires a detected Claude Code worker v2.1.260 or later. Octopus checks the
selected worker's `--version` with a five-second timeout, independently of the
outer host. This also works when Octopus runs under Codex. A custom
`OCTOPUS_CLAUDE_BIN` must implement that CLI contract. Octopus rejects malformed
values and unsupported or unknown versions rather than silently dropping the
request. Unset the variable to preserve the worker's existing configuration.

The host validates model pairings, account access and model allowlists. Proxies
and gateways can reject the server tool; Claude can retry without it. An enabled
advisor, or a successful worker, does not prove an advisor consultation happened.
Octopus logs the requested advisor in the launch command, but does not currently
collect advisor-call receipts or separate advisor usage. Cost stays unknown.
Claude Code has no hard advisor-call cap, so this option is unsuitable for a
workflow that requires a fixed number of model calls. Existing worker deadlines
still apply.

Fixed refinement judges disable the advisor, including a saved advisor default.
Exact-model CLI seats also launch with `--advisor off` on supported workers. This
keeps additional consultations out of the declared judging panel. Octopus's
consultative multi-provider advisors are separate workers and use their existing
contracts. The `claude-agent` SDK and `anthropic-api` adapters do not acquire the
new CLI option.

When worker version detection fails, exact-model seats omit the version-specific
flag. Saved-advisor behavior in that case remains unverified. Fixed refinement
judges also set `CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1` independently of the flag.

Plugins cannot enable this by putting `advisorModel` in their manifest's settings.
Only the documented plugin settings keys take effect. Octopus never writes the
user's advisor settings or accepts model billing consent for them.

A future direct Messages API implementation must account for
`usage.iterations` entries of type `advisor_message`, preserve complete encrypted
result blocks across turns, and handle `pause_turn`. Top-level executor token
totals do not include advisor usage. Per-turn `max_uses` and advisor `max_tokens`
do not provide a conversation-wide budget without client accounting.

## Refining an existing artifact

Use `/octo:refine` after drafting a plan, specification, document or deck when
you want independent scoring and bounded revisions. `/octo:auto refine this
plan` and explicit requests to improve an artifact against a rubric or score
target hand off to the same installed command, including conversational requests
such as "Can you refine this plan against a rubric?" Generic "improve this plan"
requests stay ordinary editing. Multi-provider, security and parallel intents
retain their routing priority.

Explicit refinement of a flowchart or diagram also uses this workflow. Requests
such as "improve this plan without using a rubric" stay outside refinement.
For ordinary improvement requests, Lighthouse and PageSpeed score targets retain
task routing, such as performance optimization. A request to use a rubric still
selects refinement.
Direct provider spawns retain the underlying coding or design role and task-type
rules. Their rules can also match `native-refine`, in configured first-match order.

Refinement freezes its rubric, uses real independent Claude and Codex judges,
and validates the accepted candidate. Its normal limits remain 95/100, five
improvement rounds, 30 minutes and 14 external calls. A request to improve a
plan authorizes editing that artifact. Executing the plan needs its own scope.
Missing evidence or providers produces a blocker, never an invented score.

## Hook failures

On Claude Code v2.1.295 or later, critical synchronous PreToolUse hooks set
`onFailure: "block"`. This covers provider routing, Codex execution checks,
scheduler policy, careful mode and frozen edit boundaries. The host blocks the
tool if the hook cannot start, crashes, times out or emits invalid JSON.

This is additional protection for the hook's failure path. It does not detect
policy bugs that return a successful allow decision. Older hosts keep the
existing hook behavior and do not provide this failure guarantee. Codex and
other hosts need their own hook compatibility checks. Stop, SubagentStop,
TaskCompleted, TeammateIdle and async hooks do not gain this protection.

## Subagent context and effort

For a custom log-analysis or debugger agent, `autoCompactWindow: 200000` lets
long investigations compact earlier on Claude Code v2.1.296 or later. This is
an opt-in agent setting, not an Octopus-wide default. Verify that the installed
agent definition is the one the host actually loads before relying on it. Before
compaction, retain the reproducer, current hypothesis, failed approaches,
changed files and verification results in task-owned evidence. An explicit
`CLAUDE_CODE_AUTO_COMPACT_WINDOW` takes precedence when the host accepts it.

For custom workers on v2.1.271 or later, `omitClaudeMd: true` fits only a
self-contained brief that includes the applicable repository instructions,
scope and acceptance checks. Octopus keeps instruction inheritance by default.
Managed policy still applies; nested instructions may load during file access.
Omitting initial instructions is not a security boundary.

On v2.1.292 or later, the native Agent tool can receive a per-invocation
`effort`. Use lower effort for bounded extraction or formatting, and the
configured reasoning level for design, implementation and judging. Preserve
explicit user effort choices. Do not pass Agent fields to shell workers or to
hosts whose tool schema does not expose them. Older hosts use their existing
agent configuration.

## Native plugin evals

`evals/` contains real host cases for missing-input refinement and unrelated
requests. Deterministic shell tests separately cover routing and command
validation. These small cases measure preconditions and accidental activation;
they do not establish judge quality or successful multi-provider execution.

On Claude Code v2.1.269 or later, run `make test-native-evals` from a source
checkout for one bounded pass. From an extracted package, run this equivalent
command in the plugin directory:

```bash
claude plugin eval . --runs 1 --ablation none --model opus --concurrency 1 \
  --max-cost-usd 3 --no-publish --trust-plugin
```

Each case uses at most six turns and 90 seconds. The command limits the
list-price estimate to $3 and runs one case at a time, with local reports and
no shell, write, network or live MCP grants. The estimate is checked between
runs, so an in-flight run can exceed it. Reports contain prompts and model
outputs and are ignored by Git.

For a release-quality comparison, run the default three repetitions and a
no-plugin baseline, with an explicit model and budget:

```bash
claude plugin eval . --runs 3 --ablation with-without --model opus \
  --concurrency 1 --max-cost-usd 10 --no-publish --trust-plugin
```

These calls use the account's real model access. Do not add them to every
contributor's CI without provisioning that access. A server-side feature flag
or authentication error is an unrun model evaluation, not a passing test.

## Dynamic workflow handoff

For a large Claude-only migration, prefer the host's native dynamic workflow
when available, starting at v2.1.154. Give it the allowed paths, source revision,
task decomposition, budget and acceptance commands. Request changed-file and
verification evidence on return. Do not run a native workflow and an Octopus
worker against the same paths concurrently. Return to Octopus for explicit
cross-provider validation or disagreement, using the completed artifact as the
handoff. A refinement or plan-only request never starts a migration.

## Features held for a separate implementation

Claude Mods, introduced in v2.1.287, could display worker progress and receipts.
A useful first experiment would observe existing lifecycle events without
dispatching workers or changing policy. `turn.step` result `serverToolUses`
exposes advisor calls on v2.1.290 or later. Advisor calls never emit `tool.call`
or `tool.check` hooks. `$.model.complete` and `$.model.fork` are independent
model operations, not advisor calls. Octopus ships no mod runtime until that
experiment establishes value over the current status and result files.

MCP tasks require a server that implements durable task creation, polling,
cancellation, expiry and reconnect behavior. Current Octopus MCP tools retain
their synchronous contract. The documented host floor is v2.1.304, with broader
terminal support in v2.1.319. Account feature flags still matter. One-shot
`claude -p` does not receive task completions, so changing only the transport
declaration would lose results. A later task implementation needs lifecycle and
compatibility tests before replacing that contract.

## References

- [Advisor](https://code.claude.com/docs/en/advisor)
- [Advisor API](https://platform.claude.com/docs/en/agents-and-tools/tool-use/advisor-tool)
- [Plugin settings](https://code.claude.com/docs/en/plugins/manifest-reference#settings)
- [Hook failure handling](https://code.claude.com/docs/en/hooks#block-the-action-when-a-hook-fails)
- [Subagents](https://code.claude.com/docs/en/sub-agents)
- [Plugin evals](https://code.claude.com/docs/en/plugin-evals)
- [Dynamic workflows](https://code.claude.com/docs/en/workflows)
- [Mods](https://code.claude.com/docs/en/plugins/mods/overview)
- [MCP tasks](https://code.claude.com/docs/en/mcp#mcp-tasks-that-run-on-the-server)
