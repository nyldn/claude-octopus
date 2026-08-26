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
qwen, ollama, copilot, and vibe.

Retired `gemini` and `gemini-*` IDs are accepted only as compatibility aliases and canonicalize to `agy`. They are not executable providers, are never probed, and are not written to new configuration.

## Remaining adapter work

Registry 2.0 removes shared provider identity, model-environment, context,
cost, health-selection, and independence lists from consumers. Command syntax,
credential validation, model fallbacks, and environment isolation stay explicit
because their provider contracts differ and deserve direct tests.
