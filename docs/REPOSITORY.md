# Repository map

Start with [Contributing](CONTRIBUTING.md) for checkout and validation steps.
Use [Architecture](ARCHITECTURE.md) for execution flow and
[the script index](../scripts/README.md) to find a runtime or maintainer entry point.

## Where changes belong

| Path | Contents |
| --- | --- |
| [commands/](../commands/) | Public slash-command definitions |
| [skills/](../skills/) and [.claude/skills/](../.claude/skills/) | Skill entries and shared phase resources; source ownership is listed below |
| [scripts/](../scripts/) | CLI entry points, runtime libraries, helpers, generators and release tools |
| [hooks/](../hooks/) | Host lifecycle and safety hooks |
| [config/](../config/) | Provider, model, workflow and project templates |
| [agents/](../agents/) | Personas, review principles and generated Factory droids |
| [.claude/agents/](../.claude/agents/) | Claude native agent definitions |
| [.github/](../.github/) | CI, contributor templates and Copilot agent definitions |
| [mcp-server/](../mcp-server/) | MCP server source and its own dependency/build configuration |
| [docs/](./) | User guides, runtime contracts and contributor documentation |
| [tests/](../tests/) | Hermetic checks, fixtures and separately opt-in live tests |
| [data/evals/](../data/evals/) | Shipped evaluation scenarios |
| [evals/](../evals/) | Opt-in native Claude plugin evals; see [Claude native integrations](CLAUDE-NATIVE-INTEGRATION.md) |
| [vendors/](../vendors/), [licenses/](../licenses/) | Vendored material and third-party license files |
| [.claude-plugin/](../.claude-plugin/), [.codex-plugin/](../.codex-plugin/), [.cursor-plugin/](../.cursor-plugin/), [.factory-plugin/](../.factory-plugin/) | Host manifests and generated adapter files |

Private investigations, plans, benchmarks and task evidence belong in the
separate development workspace. Keep credentials, runtime state, installed
dependencies and temporary output untracked. The root [`.gitignore`](../.gitignore)
records the public repository's exclusions.

## Skill sources

Each skill has one authored entry. A generated copy is an adapter or mirror,
not another place to edit its contract.

| Authored source | Derived output |
| --- | --- |
| `.claude/skills/<source-dir>/SKILL.md`, except the two mirrors below | Portable `skills/<generated-name>/SKILL.md` and `skills/<generated-name>/agents/openai.yaml`, including compatibility aliases |
| `skills/flow-discover/SKILL.md` and its `references/` | `.claude/skills/flow-discover/SKILL.md` mirrors the entry; both hosts use the root resources |
| `skills/skill-refine/SKILL.md` and its `references/` | `.claude/skills/skill-refine/SKILL.md` mirrors the entry; both hosts use the root resources |
| `skills/skill-council/`, `skills/octopus-starter-pack/` | Hand-maintained root skills preserved during generation |
| `skills/blocks/` | Shared authored guidance, except generated `codex-host-adapter.md` |

For portable generation, `<generated-name>` comes from the frontmatter `name`,
sanitized and limited to 64 characters. If `name` is absent, the builder uses
the source basename. For example,
`.claude/skills/skill-architecture/SKILL.md` declares `name: octopus-architecture`
and generates `skills/octopus-architecture/`.

The builder also adds compatibility aliases through `compat_alias_for`. It maps
`skill-verification-gate` to `skill-verify`, so
`.claude/skills/skill-verification-gate/SKILL.md` generates both
`skills/skill-verification-gate/` and `skills/skill-verify/`. Edit that source
entry to update either generated copy.

`scripts/build-codex-skills.sh` owns portable skill generation and the two
Claude mirrors. `scripts/build-factory-skills.sh` calls it as part of
`make sync`. The legacy `scripts/gen-skill-docs.sh` command delegates to that
same builder; its `--dry-run` flag is a read-only check. Flow `.tmpl` files
are retired. Edit the authored entries in the table.

## Other generated files

| Authored source | Derived output | Generator |
| --- | --- | --- |
| `commands/*.md` | `.cursor-plugin/commands/*.md` | `scripts/build-factory-skills.sh` |
| `.claude/agents/*.md` | `agents/droids/*.md` | `scripts/build-factory-skills.sh` |
| Plugin metadata and runtime model/capability definitions | Mechanical release facts and counts in READMEs, catalogs and adapter manifests | `scripts/sync-readme.py` |
| `.claude-plugin/plugin.json` | The local Octopus marketplace entry | `scripts/sync-marketplace.sh` |

Run `make sync` after changing an authored source, then inspect the diff.
`make sync-check` checks the corresponding outputs without changing them.
The [release checklist](../RELEASING.md#3-regenerate-derived-artifacts-make-sync)
lists each release field and its generator. README prose outside generated
release facts remains authored documentation.

## Validation and publication

Use [the test guide](../tests/README.md) for affected, quick, full and live test
tiers. Ordinary tests use inert providers; they do not require provider logins.
Use [the assembly contract](PLUGIN-ASSEMBLY-STANDARD.md) when changing plugin
entry points or packaging, and [RELEASING.md](../RELEASING.md) for publication.

GitHub issues and PRs track public work. A local check, an approved PR, a merged
commit and a published release are separate states.
