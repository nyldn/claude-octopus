# Plugin Assembly Standard

This standard defines how Claude Octopus packages Claude Code skills, agents,
commands, and connector metadata. It is intentionally structural: it governs
how plugin pieces are assembled, named, validated, and wired together. It does
not prescribe the content of any one workflow.

The goal is to keep Octopus Claude-native first: use Octopus where orchestration,
multi-provider review, explicit safety gates, or connector-aware routing adds
value, and avoid duplicating native Claude Code behavior without escalation
benefit.

## Skill Assembly Contract

Skills carry reusable method, domain rules, and workflow discipline. Commands
and agents may reference skills, but should not duplicate long skill logic.

Every plugin-root skill must live at `skills/<skill-name>/SKILL.md`.
Compatibility skills may also live under `.claude/skills/*.md` until the legacy
manifest surface is retired.

Each skill must include YAML frontmatter with:

- `name`: kebab-case, stable, and aligned with the skill directory or legacy
  file name.
- `description`: a concise trigger/use statement. Prefer one direct sentence
  over a broad capability list.
- `disable-model-invocation: true`: Octopus is an explicit escalation surface;
  installed skills must not enter model context or self-activate on an ordinary
  request.

For Codex, also declare `policy.allow_implicit_invocation: false` in each
skill's `agents/openai.yaml`. Claude frontmatter does not replace this host
policy. See [plugin compatibility](PLUGIN-COMPATIBILITY.md) for validation scope.

Skill bodies should use this shape when practical:

- `When To Use`
- `When Not To Use`
- `Inputs`
- `Workflow`
- `Provider Or Data Priority`
- `Stop Or Checkpoint Rules`
- `Output Contract`
- `Verification`

Keep provider CLI syntax, helper commands, and data-source policy in reusable
blocks or runtime scripts when they are shared across skills. A skill should
describe the method and contract; it should not become the only source of truth
for fragile runtime wiring.

## Agent Assembly Contract

Agents are compact orchestration contracts. They should name the job, define the
artifact, set guardrails, and point at skills. Long encyclopedic expertise lists
belong in skills or reference docs, not agent prompts.

Preferred agent shape:

- `What You Produce`
- `Workflow`
- `Guardrails`
- `Skills Used`
- `Tool Or Provider Boundaries`
- `Output Contract`

For reusable workers, prefer a small set of role-specific agents over a broad
persona that claims every adjacent capability. When a workflow delegates to
multiple workers, make write authority explicit. A good default is read-only
research workers plus one writer or integrator.

Agent configuration must keep referenced files resolvable from the plugin root.
If `agents/config.yaml` references `file: personas/foo.md`, the validator must
be able to prove that file exists.

Claude Code has no manual-only frontmatter field for subagents: it delegates
from their descriptions. Plugin subagent descriptions must state that they are
available only after the user explicitly starts an Octopus workflow. Ordinary
requests stay on the host's native path.

## Command Assembly Contract

Commands are explicit entrypoints and must set
`disable-model-invocation: true`. They should be thin, predictable, and easy to
scan. A command can gather arguments, choose a mode, and load a skill source or
orchestration script. It should not silently fork into a separate product.

Every command markdown file in `.cursor-plugin/commands/*.md` or `commands/*.md` must
include YAML frontmatter with:

- `description`: what the command does.
- `argument-hint`: recommended for user-facing commands that accept arguments.

Legacy `commands/*.md` files should also keep their `command:` field
because the existing tests and compatibility surface rely on it.

### Manual composition contract

Because Octopus skills are model-invocation disabled, an explicit command may
compose a skill by reading its complete source from
`${HOME}/.claude-octopus/plugin/.claude/skills/<name>/SKILL.md`. The command must
then treat that body as the active instruction source in the same conversation,
follow its ordered workflow and safety checkpoints, and pass command arguments
as textual workflow input. It must not call the Skill tool recursively or treat
the markdown as a shell script.

Use `${HOME}/.claude-octopus/plugin` in model-facing command instructions. That
stable symlink is repaired at SessionStart and remains available to model tool
calls. The repair target is the plugin root loaded by the host, so direct source
loading does not introduce a second plugin trust boundary. Reserve
`CLAUDE_PLUGIN_ROOT` for hooks and runtime scripts, where Claude Code supplies
it. This distinction is intentional rather than an interchangeable path
convention.

Routers may load only literal command names from a closed allowlist. Never use
free-form prompt text as a path segment; reject path separators and traversal
tokens before joining a command name to the stable plugin root.

## Connector Assembly Contract

Connector metadata must be explicit and honest. If Octopus claims a data source
or companion integration, it must be represented by one of:

- `.mcp.json` for MCP servers.
- A documented provider in `scripts/lib/providers.sh` or a companion-specific
  script under `scripts/lib/`.
- A connector reference document that names the available tools, auth
  expectations, and fallback behavior.

Connector-aware skills should declare data-source priority. For example:

1. User-provided context.
2. Configured MCP or companion connector.
3. Provider CLI or web fallback, if allowed.
4. Explicitly mark unavailable data instead of fabricating.

Doctor checks should report connector availability when a workflow materially
depends on that connector.

## Validation Contract

The plugin assembly validator is `scripts/validate-plugin-assembly.py`.

It must run without third-party dependencies and check:

- `.claude-plugin/plugin.json` parses and has required metadata.
- Skill frontmatter exists and includes `name` and `description`.
- Command frontmatter exists and includes `description`.
- Agent frontmatter exists for plugin agent markdown files that are invocable
  roles.
- `agents/config.yaml` file references resolve.
- JSON connector and manifest files parse.

The validator should fail on structural drift and print actionable file paths.
It should not fail solely because the repository still carries legacy
compatibility surfaces, generated files, or empty optional connector manifests.

When adding a new plugin surface, add or update a unit test that proves the
validator catches the expected drift before relying on the rule.
