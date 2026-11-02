# Codex Host Adapter

Claude Octopus skills are authored from the Claude Code source surface and then adapted for Codex.

When a generated skill references a host tool, use the active Codex equivalent:

| Skill wording | Codex equivalent |
| --- | --- |
| native shell command tool | use the available Codex shell execution tool |
| host subagent tool | use `spawn_agent`, `wait_agent`, and `close_agent` only when those tools are available and the user has authorized delegation |
| task plan tool | use Codex task planning/status tools when present |
| `/octo:*` command examples | use the installed skill name or run `scripts/orchestrate.sh` directly |

Provider and model availability must be checked at runtime. If `OCTO_ALLOWED_PROVIDERS` is set, treat providers outside that list as unavailable even when installed. If a skill names a provider that is missing or disallowed in the current Codex session, mark it unavailable and continue only with available providers.
