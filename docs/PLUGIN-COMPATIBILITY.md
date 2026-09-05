# Plugin compatibility

Octopus supports local Claude Code and Codex plugin installations. It is not a
hosted ChatGPT plugin: provider execution requires local CLIs and a filesystem.

## Claude Code

`.claude-plugin/plugin.json` retains the `octo` namespace and its explicit
command/skill paths. Root `hooks/hooks.json` is discovered by the host. Skills
use `disable-model-invocation: true` to keep provider workflows explicitly
invoked. Native plugin and marketplace validation passes; Claude's warning
that root `CLAUDE.md` is not loaded as plugin context is expected. Runtime
instructions belong in skills and hooks, not that maintainer file.

## Codex

`.codex-plugin/plugin.json` retains `claude-octopus`, points to `./skills/`, and
uses relative icon paths. Codex discovers `hooks/hooks.json` without a redundant
manifest field. Its runtime supplies `CLAUDE_PLUGIN_ROOT` for compatibility.
Users must review and trust hook definitions; installation alone does not
activate them. See [OpenAI's package contract](https://developers.openai.com/plugins/build/plugins)
and [hook runtime](https://learn.chatgpt.com/docs/hooks).

Careful mode asks for confirmation in Claude Code. In Codex it denies the
matched command with an explanation, because Codex does not support the hook
`ask` decision. Freeze mode checks all Add/Update/Delete/Move paths in Codex
`apply_patch` calls. Both guards parse JSON structurally and need Python 3;
when active, they fail closed if the helper or input cannot be validated.
These are opt-in guardrails, not a sandbox for arbitrary shell commands.

Every skill also declares `policy.allow_implicit_invocation: false` in
`agents/openai.yaml`. This is Codex's documented invocation control, distinct
from Claude's frontmatter. Explicit skill mentions still work. See
[OpenAI's skill metadata](https://learn.chatgpt.com/docs/build-skills).

Verified with Codex CLI 0.153.2: installation from an isolated local marketplace
and native `skills/list` discovery, without a model request. The runtime loaded
62 packaged skills and 20 converted command entries without skill-load errors.
This checks installation and discovery, not a live multi-provider workflow.

The bundled OpenAI plugin-creator ingestion validator rejects the shared
Claude frontmatter's explicit-invocation flag and the nested starter/block
layout. That validator targets public-directory ingestion; a successful Codex
runtime installation does not imply eligibility for OpenAI's universal public
directory. Do not remove invocation safeguards merely to satisfy that separate
submission contract. A hosted distribution would need its own package and
execution architecture; see [OpenAI's Claude plugin migration guide](https://developers.openai.com/plugins/guides/submit-claude-plugin).

## MCP and other editors

The root `.mcp.json` is intentionally empty: MCP is opt-in. Configure the server
using [IDE integration](IDE-INTEGRATION.md) and supply per-call `project_root`
as described in [the v11 migration guide](MIGRATING-V11.md). Do not advertise
unconfigured servers or translate Claude's camel-case MCP configuration into a
Codex bundled-server manifest without checking Codex's schema.
