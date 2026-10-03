# Provider Wiring Map

Provider Registry 2.0 owns shared identity and runtime policy. Adding or
modifying a provider starts with two parity-enforced rows in
`scripts/lib/provider-registry.sh`; provider-specific command, model, auth, and
environment adapters remain explicit. Line numbers below are anchors, not
contracts; re-grep before editing.

## Terms used in routing and review

| Term | Meaning |
|---|---|
| provider | Executable or API transport; it does not prove model family |
| model | Requested or resolved model identity, with its source stated |
| installed | A binary was found; login and access remain unproven |
| authenticated | Credential or session evidence; model entitlement remains separate |
| entitlement | Account access to a service or model, when established |
| readiness | Timestamped local check with reason and remediation |
| billing mode | `subscription`, `api`, `local`, `mixed`, or `unknown`; installation does not establish it |
| quota | Remaining allowance from an authoritative source |
| seat | Requested reviewer job, not a completed contribution |
| contribution | Received artifact with provenance and grounding status |
| vote | Admissible judgment after contribution validation |

Registry `cost_class=bundled` is routing metadata, not proof of the user's account
billing. Two provider transports can expose the same model family, so transport
count is not independence evidence. Keep an unknown model family unknown.

The original five-column row is a public compatibility contract:

```text
id|aliases|command|organization|capabilities
```

The keyed runtime row must use the same canonical ID and supplies auth mode,
health and detection handlers, model environment, default resolver, safe
context budget, cost class, sandbox class, and independence organization. The
registry governance test fails when the two inventories differ or a required
field is invalid.

After resolution, synchronous and background runners consume the same immutable
dispatch plan. The plan records canonical provider and model identity, selection
source, canonical project and plugin roots, argv, credential names, tool policy,
input and reserve budgets, deadline, and billing mode. It never records
credential values. Add provider-specific command and authentication logic before
the plan boundary instead of rebuilding policy in a runner.

Context admission uses the smallest configured, catalogued-model, and effective
transport limit, then deducts output and system/tool reserves. A broad provider
limit must not raise a smaller exact-model limit.

MCP loads provider environment names from `config/provider-env-allowlist.json`.
Add a provider's credential and transport names there, then test the adapter.
The host adapter passes the approved
names to the orchestrator; the dispatch plan still narrows each provider child
to the credential selected for that seat. A custom OpenAI-compatible key named
by `OPENAI_COMPAT_API_KEY_ENV` is forwarded automatically. Other custom
provider keys require a comma-separated `OCTOPUS_CREDENTIAL_ENV_NAMES` list;
names must end in `API_KEY`, `TOKEN`, `CREDENTIAL`, or `CREDENTIALS`.

## The seven wiring points

| # | Concern | File | Anchor | What to add |
|---|---------|------|--------|-------------|
| 1 | Canonical identity and capabilities | `scripts/lib/provider-registry.sh` | `octo_provider_registry_rows` | Five-column row; use explicit `*` only for intended prefix aliases |
| 2 | Runtime policy | `scripts/lib/provider-registry.sh` | `octo_provider_runtime_rows` | Matching row with all Provider Registry 2.0 fields |
| 3 | Command builder | `scripts/lib/dispatch.sh` | main dispatch `case` | Arm that emits the exec command or shim path |
| 4 | Model fallback and restrictions | `scripts/lib/model-resolver.sh`, `scripts/lib/dispatch.sh` | Priority-7 fallback and allowlist selection | Safe provider default or explicit fail-closed requirement; allowlist env when supported |
| 5 | Environment isolation | `scripts/lib/provider-routing.sh` | `_octo_build_provider_env_impl` | Minimal `env -i` allowlist or explicit inherited-environment policy |
| 6 | Detection and health implementations | `scripts/lib/providers.sh` | `detect_providers`, `check_provider_health` | Provider-specific implementation matching the registry handlers and capabilities |
| 7 | Dispatch and parity tests | `tests/unit/` | provider, registry, availability, health, and round-trip suites | Auth failure, valid dispatch, unsafe input, no-config model, and registry parity oracles |

Plus, usually:
- `scripts/helpers/<provider>-exec.sh` shim (stdin prompt contract; see `grok-exec.sh` as the minimal template)
- Context budget arm in `scripts/lib/dispatch.sh` (~line 345) if the provider has a non-default window
- `config/providers/<provider>/CLAUDE.md` if unit tests expect one (agy and ollama do)
- Unit test in `tests/unit/test-<provider>-provider.sh`
- `docs/DEVELOPER.md` / README provider tables

## Cheaper Inference setup

`cheaperinference-agent` uses the OpenAI-compatible tool-loop helper at
`https://api.cheaperinference.com/v1`. Set `CHEAPER_INFERENCE_API_KEY` and
choose a model supported by that gateway. No model is selected by default.

Model selection uses `CHEAPER_INFERENCE_MODEL`, then
`OCTOPUS_CHEAPERINFERENCE_MODEL`, then `OPENAI_COMPAT_MODEL`, then the string
`providers.cheaperinference.default` in
`~/.claude-octopus/config/providers.json`. `OCTOPUS_PROVIDERS_CONFIG` can select
another file. Native model resolution, dispatch, health, detection and
readiness use the same selection. Qualified seats use their exact model pin
without requiring another default. Invalid pins and allowlist fallbacks fail
closed.
Use `CHEAPER_INFERENCE_ALLOWED_MODELS` to restrict dispatch models.

Read-only roles disable local tools. The child receives only its selected
credential and the shared helper's approved runtime settings. This provider
is excluded from Council. Local readiness does not prove model entitlement,
tool support, quota or billed cost. See the [gateway API documentation](https://api.cheaperinference.com/docs)
for its current model capabilities.

## API Route setup

`api-route-agent` uses the same OpenAI-compatible tool-loop helper at
`https://global.api-route.com/v1`. Get a key from
[API Route](https://www.api-route.com), set `API_ROUTE_API_KEY`, and choose a
model available to your account (for example `deepseek-v4.1-flash`). No model
is selected automatically.

Model selection uses `API_ROUTE_MODEL`, then `OCTOPUS_API_ROUTE_MODEL`, then
`OPENAI_COMPAT_MODEL`, then the string `providers["api-route"].default` in
`~/.claude-octopus/config/providers.json`. `OCTOPUS_PROVIDERS_CONFIG` can select
another file. Detection, health, readiness and dispatch share this resolution.
An exact seat such as `api-route-agent:deepseek-v4.1-flash` uses its model pin
without requiring a default. `API_ROUTE_ALLOWED_MODELS` restricts dispatch
models; missing models, unsafe pins and invalid fallbacks fail closed.

Read-only roles disable local tools. The isolated child receives only
`API_ROUTE_API_KEY` and the helper's approved runtime settings. This provider
is excluded from Council, and gateway identity does not establish independent
model-family diversity. Local readiness does not prove entitlement, quota,
tool support or billed cost.

## Perplexity Agent API

Perplexity requests use `POST /v1/agent`. Legacy Sonar model names map to
Perplexity's recommended presets; explicit `provider/model` names enable the
`web_search` tool. Bare `fast`, `low`, `medium`, `high`, and `xhigh` values
select a preset and inherit its tools. Selecting `xhigh` enables Perplexity's
remote code sandbox, web search, and finance search. Preset tools merge with
request tools, so an empty `tools` array does not disable them. See
[Perplexity's preset configuration](https://docs.perplexity.ai/docs/agent-api/presets).

## Grok headless tool approval

The Grok stdin shim uses `--always-approve --sandbox read-only` by default.
Advisory seats receive only `read_file`, `grep`, and `list_dir` through `--tools`,
plus a deny rule for MCP tools and disabled subagents. They can inspect source
without granting shell or file mutation authority. The CLI must advertise these
controls in `--help`; missing controls reject the call before prompt execution.
`OCTOPUS_GROK_APPROVE=0` omits the approval and sandbox flags and retains the
tool ceiling.
`OCTOPUS_GROK_SANDBOX` overrides the profile: `off`, `workspace`, `read-only`, or
`strict`. Invalid values produce one stderr warning and use the call's default.
The shim's standalone default is `read-only`.

Dispatch defaults to `workspace` only for write-capable implementation roles in
`tangle`/`develop` when `OCTOPUS_CODEX_SANDBOX` permits writes. Codex's default
is `workspace-write`; `danger-full-access` also maps to Grok `workspace`, while
Codex `read-only` keeps Grok read-only. Review, consult, council, and unknown
contexts default to `read-only`, including consultative calls that grant Codex
`danger-full-access` inside a disposable workspace. Explicit Grok overrides
take precedence for the sandbox profile. They cannot raise an advisory role's
tool ceiling. Only eligible implementation calls receive full tools, and an
explicit Grok `read-only` override narrows those calls too. Approval, sandbox,
and tool policy travel with `OCTOPUS_GROK_MODEL` in the shim's env prefix so they
survive provider environment isolation. Standalone calls default to the same
read-tool ceiling. A trusted operator can request full tools for standalone
implementation with `OCTOPUS_GROK_TOOL_POLICY=full`; dispatch derives that value
from the role and phase and overrides inherited values.

Grok's [sandbox guide](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/18-sandbox.md)
permits temporary-directory writes under `read-only`. Its child-network block
is Linux-only. The tool ceiling avoids relying on that profile for advisory
write protection. Grok's [CLI reference](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-shell/README.md#tool-filtering-tools--disallowed-tools)
documents the read-tool allowlist. These flags are present in locally checked
Grok 1.0.3 help; no provider call is needed for that compatibility check.

Prompts above 100000 bytes use a private temporary file, preserving the stdin
bytes. `OCTOPUS_GROK_ARGV_MAX` can lower the inline threshold; `0` forces file
transport. Invalid values and values above 100000 retain the safe ceiling.
File transport cancellation sends TERM to the direct child, waits up to two
seconds, then escalates to KILL and reaps it before removing the prompt. It
does not claim ownership of unregistered descendants.

## Kimi Code integration

Kimi Code exercises all seven wiring points: `kimi` identity/runtime rows in
`provider-registry.sh`; the `kimi` command arm and `kimi-exec.sh` stdin shim;
model alias resolution through `OCTOPUS_KIMI_MODEL`; an isolated environment
that preserves `KIMI_CODE_HOME` and the documented `KIMI_MODEL_*` override
family; config-aware detection and health checks; and
real sync/background dispatch regressions. Its readiness contract uses the
explicit `OCTOPUS_KIMI_MODEL` alias when set, or `default_model` from
`$KIMI_CODE_HOME/config.toml` (default `~/.kimi-code/config.toml`) otherwise.
The selected name must resolve to a complete model alias in Kimi's model table.
It resolves that model's provider in Kimi's order: the model's `provider_id`,
the model's `provider`, then top-level `default_provider`. Models without a
provider can instead define a flat `base_url` and `protocol`. Model-level
`api_key` or OAuth takes precedence over provider-level `api_key`,
provider-local `env` credentials, or OAuth. A complete `KIMI_MODEL_NAME` plus
`KIMI_MODEL_API_KEY` override is also accepted. Bare `KIMI_API_KEY` in the
parent shell is not Kimi Code authentication.

Current Kimi Code print mode is non-interactive and auto-approves tool calls;
the CLI does not expose a tool permission allowlist. Octopus therefore admits
Kimi only for write-capable implementation roles and rejects it for research,
review, and other read-only roles. Use a provider with an enforceable sandbox
for those seats. Direct `kimi_execute` calls use the same environment allowlist
as normal dispatch unless `OCTOPUS_ALLOW_FULL_KIMI_ENV=true` is explicitly set.
The integration uses the current `-p` non-interactive contract; update Kimi
Code if that option is unavailable.

Readiness validates the complete TOML document with Kimi Code's own runtime and
built-in `doctor` command, then uses `provider list --json` for provider and
model records. Because that JSON omits top-level defaults, the bundled helper
reads only `default_model` and `default_provider` from the already validated
document. This works with both the native executable and the Node launcher
without requiring a separate Python installation. If validation cannot run,
the provider fails closed and asks the user to reinstall or update Kimi Code.
Legacy keyring-only OAuth is not reported as ready; run `kimi` with the same
`KIMI_CODE_HOME` and enter `/login` again.

Kimi Code 0.40.1 documents Vertex ADC, but its shipped default headless runtime
rejects an ADC-only provider before dispatch. Octopus therefore fails that
configuration closed and does not forward `GOOGLE_APPLICATION_CREDENTIALS`.
Use `VERTEXAI_API_KEY` or `GOOGLE_API_KEY` inside the selected provider's
`env` table until the Kimi runtime contract supports ADC consistently.

## Traps (each has bitten a real PR)

1. **Case glob ordering.** More-specific aliases must precede broader globs (for example, `claude-sdk*` before `claude*`). A late arm behind an earlier glob is silently unreachable; there is no error.
2. **Registry parity is mandatory.** A provider in only the identity table or
   only the runtime table fails `octo_provider_validate_contracts`. Do not add a
   fallback case to make an incomplete registration appear valid.
3. **Exec bits.** New shims and any rewritten script must be `100755`. `git diff origin/main...HEAD --summary | grep "mode change"` must come back empty (see RELEASING.md step 5).
4. **Stdin contract.** spawn.sh pipes the prompt on stdin. CLIs that want argv prompts need a shim that reads stdin and re-passes it (`grok-exec.sh`, `vibe-exec.sh` pattern). Model selection reaches shims via an `env OCTOPUS_X_MODEL=... shim.sh` prefix emitted by the command builder, not via shell export.
5. **Secret-scanner quoting.** In shims, write `"SOME_API_KEY=${VAR}"` (quote the whole env argument). `SOME_API_KEY="${VAR}"` false-positives the expert-review secret scan.
6. **Nested-session markers.** Anything that execs a headless `claude` must strip `CLAUDECODE`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_CODE_CHILD_SESSION`, `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_EXECPATH`, or the child hangs believing it is nested.

## Current providers

codex, commandcode, claude, claude-sdk (Agent SDK seat), anthropic-api (text-only Messages seat), agy (Antigravity,
Google seat), perplexity, opencode, openrouter, orcarouter, atlascloud,
cheaperinference, openai-compatible, openai-tools, openai-compatible-agent, cursor-agent, grok,
qwen, ollama, copilot, vibe, and kimi.

`cursor-agent` is the Cursor CLI (`agent` binary, `cursor` alias). Its auth
probe lives in `scripts/lib/cursor-agent.sh` (`cursor_agent_is_available`):
`CURSOR_API_KEY`, else an `authInfo` block in `~/.cursor/cli-config.json`
(cheap but not always present), else a bounded (`OCTOPUS_CURSOR_AGENT_STATUS_TIMEOUT`, 15s) `agent status
--format json` probe whose yes/no verdict is cached per process and on disk.
The cache path resolves to `OCTOPUS_CURSOR_AGENT_AUTH_CACHE_FILE` when set,
otherwise `${XDG_CACHE_HOME:-$HOME/.cache}/claude-octopus/cursor-agent-auth-verdict`
(TTL 600s; never in the workspace, symlinks refused, atomic replace). Do not re-implement that check in
consumers. Dispatch is read-only by default
(`--mode ask`; `--mode plan` for planner roles; `--force` only for implementer
roles or `OCTOPUS_CURSOR_AGENT_MODE=agent`).

Retired `gemini` and `gemini-*` IDs are accepted only as compatibility aliases and canonicalize to `agy`. They are not executable providers, are never probed, and are not written to new configuration.

## Remaining adapter work

Registry 2.0 removes shared provider identity, model-environment, context,
cost, health-selection, and independence lists from consumers. Command syntax,
credential validation, model fallbacks, and environment isolation stay explicit
because their provider contracts differ and deserve direct tests. The dispatch
plan is the handoff between those adapters and the common execution lifecycle.

## Anthropic Messages text seat

`anthropic-api` sends one request with no tools using Python's standard library.
Only an explicit `ANTHROPIC_API_KEY` enters its isolated child environment.
`config/provider-env-allowlist.json` already includes that key for MCP. The
adapter ignores CLI authentication, `CLAUDE_SDK_API_KEY`, OAuth tokens,
`ANTHROPIC_BASE_URL`, and shell credential files. Its endpoint is fixed to the
Anthropic Messages API, redirects are blocked, and errors report status codes
without response bodies or credential values.

Select `anthropic-api` explicitly for `planner`, `strategist`, `architect`,
`researcher`, `synthesizer`, `reviewer`, `code-reviewer`, or `security-reviewer`.
Supply all evidence in the prompt. Local readiness checks prove only Python
and key presence; they do not verify authentication or model entitlement.
The provider does not enter automatic defaults or council selection. To route
only synthesis through it, run `/octo:model-config route-role synthesizer
anthropic-api`. Set `ANTHROPIC_API_KEY` in the caller environment before use.

Its default model is `claude-sonnet-5-5` with high effort. API `auto` thinking
selects `between_tools` at low, medium, or high effort, and adaptive thinking
at xhigh or max. `claude-opus-5-5` uses adaptive thinking. Explicit model and
effort pins reach the request unchanged. Unsupported models and incompatible
thinking modes fail before transport. Set `OCTOPUS_ANTHROPIC_API_TIMEOUT` to
change the 120-second request timeout, up to 600 seconds, and
`OCTOPUS_ANTHROPIC_API_MAX_TOKENS` to change the 8,192-token output allowance,
up to the model's 128,000-token limit. Context admission reserves that output
allowance. Set `OCTOPUS_ANTHROPIC_API_CONTEXT_BUDGET` to raise the conservative
12,000-token default budget, up to the native 1M context limit. A larger output
allowance can require a larger configured context budget.

See the [thinking migration](MODEL-ROUTING-STRATEGY.md#sonnet-55-api-thinking-2026-10-01)
for the current CLI and Agent SDK limitation and the API compatibility rules.
