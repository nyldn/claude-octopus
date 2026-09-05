# Provider Wiring Map

Provider Registry 2.0 owns shared identity and runtime policy. Adding or
modifying a provider starts with two parity-enforced rows in
`scripts/lib/provider-registry.sh`; provider-specific command, model, auth, and
environment adapters remain explicit. Line numbers below are anchors, not
contracts; re-grep before editing.

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

MCP and OpenClaw load their provider environment names from
`config/provider-env-allowlist.json`. Add a provider's credential and transport
names there, then test both adapters. These host adapters pass the approved
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

codex, commandcode, claude, claude-sdk (Agent SDK seat), agy (Antigravity,
Google seat), perplexity, opencode, openrouter, orcarouter, atlascloud,
openai-compatible, openai-tools, openai-compatible-agent, cursor-agent, grok,
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
