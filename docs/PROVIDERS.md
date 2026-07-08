# Provider Wiring Map

Adding or modifying a provider touches **seven wiring points across five files**. Both the claude-sdk seat (v9.50.0, 12 edit sites) and PR #579's atlascloud merge conflicts hit exactly these sites; this map exists so the next change is a checklist, not an archaeology dig. Line numbers are anchors, not contracts; re-grep before editing.

## The seven wiring points

| # | Concern | File | Anchor | What to add |
|---|---------|------|--------|-------------|
| 1 | Agent-type to provider mapping | `scripts/lib/dispatch.sh` | `case "$agent_type" in` near `get_agent_model` (~line 530) | `myprov*) provider="myprov" ;;` |
| 2 | Command builder | `scripts/lib/dispatch.sh` | main dispatch `case` with per-provider arms (~lines 150-300) | Arm that echoes the exec command or shim path |
| 3 | Model allowlist var | `scripts/lib/dispatch.sh` | `allowlist_var` case (~line 576) | `myprov) allowlist_var="OCTOPUS_MYPROV_ALLOWED_MODELS" ;;` |
| 4 | Hard-coded model fallback | `scripts/lib/model-resolver.sh` | Priority-7 fallback case (~line 347) | `myprov*) resolved_model="..." ;;` |
| 5 | Routing whitelists (TWO sites) | `scripts/lib/provider-routing.sh` | `set_provider_model` whitelist (~line 370 + error message ~373) AND override-clear regex (~line 480 + error message ~485) | Add provider to both lists and both error strings |
| 6 | Env isolation | `scripts/lib/provider-routing.sh` | env isolation `case` (~lines 120-180) | Arm before any glob that would shadow it; minimal `env -i` allowlist or `resolve_provider_env` |
| 7 | Detection + health | `scripts/lib/providers.sh` | detection function (~line 1160 region), health-check `case` (~line 836), `check_all_providers` loop (~line 900) | Detection block, validation arm, loop entry |

Plus, usually:
- `scripts/helpers/<provider>-exec.sh` shim (stdin prompt contract; see `grok-exec.sh` as the minimal template)
- Context budget arm in `scripts/lib/dispatch.sh` (~line 345) if the provider has a non-default window
- `config/providers/<provider>/CLAUDE.md` if unit tests expect one (agy, ollama, gemini do)
- Unit test in `tests/unit/test-<provider>-provider.sh`
- `docs/DEVELOPER.md` / README provider tables

## Traps (each has bitten a real PR)

1. **Case glob ordering.** `claude-sdk*` must precede `claude*`; `gemini-image` must precede `gemini*`. A late arm behind an earlier glob is silently unreachable; there is no error.
2. **Two whitelist sites in provider-routing.sh, not one.** PR #579 resolved the first and initially missed the second (~line 480). Grep the file for the existing provider list and count matches: expect at least 4 (two lists, two error messages).
3. **Exec bits.** New shims and any rewritten script must be `100755`. `git diff origin/main...HEAD --summary | grep "mode change"` must come back empty (see RELEASING.md step 5).
4. **Stdin contract.** spawn.sh pipes the prompt on stdin. CLIs that want argv prompts need a shim that reads stdin and re-passes it (`grok-exec.sh`, `vibe-exec.sh` pattern). Model selection reaches shims via an `env OCTOPUS_X_MODEL=... shim.sh` prefix emitted by the command builder, not via shell export.
5. **Secret-scanner quoting.** In shims, write `"SOME_API_KEY=${VAR}"` (quote the whole env argument). `SOME_API_KEY="${VAR}"` false-positives the expert-review secret scan.
6. **Nested-session markers.** Anything that execs a headless `claude` must strip `CLAUDECODE`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_CODE_CHILD_SESSION`, `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_EXECPATH`, or the child hangs believing it is nested.

## Current providers

codex, gemini (legacy, sunset), agy (Antigravity, Google seat), claude, claude-sdk (Agent SDK seat), perplexity, openrouter, atlascloud, openai-compatible-agent, ollama, copilot, qwen, cursor-agent, grok, vibe, opencode.

## Longer term

This map documents sprawl; it does not remove it. If provider additions continue at the current rate, a table-driven registry (one row per provider consumed by dispatch/routing/detection) collapses wiring points 1, 3, 5, and 7 into data. Decision tracked informally; raise before the next two provider additions.
