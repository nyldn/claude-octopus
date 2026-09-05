# Upgrading to v11

## MCP and OpenClaw callers

Supply `project_root` on every workflow call, and on MCP `octopus_status`:

```json
{
  "prompt": "Review the current changes",
  "project_root": "/absolute/path/to/your/project"
}
```

Use the target project directory, not the plugin installation. The path must
exist, be a directory, and not be the filesystem root. Each call resolves its
own root, so concurrent calls can safely target different projects. Refresh
your client's tool schemas after updating. `octopus_set_editor_context` is
advisory and cannot substitute for `project_root`.

## Model selection

GPT-6 Astra remains explicit-only. A stored allowlist or fallback chain is not
authorization to upgrade an ordinary model selection to Astra. Select it for
the invocation and satisfy the documented provider/version restrictions.
See [model routing](MODEL-ROUTING-STRATEGY.md) for precedence and escalation.

Unknown model IDs are rejected from automatic routing unless the provider
declares support for custom automatic models. Exact model-qualified seats fail
if their model is blocked; they are not silently replaced by another model.

## Council responses and evidence

Custom reviewers must end their response with exactly one standalone line:

```text
VERDICT: APPROVE
```

The other accepted values are `REVISE` and `BLOCK`. Do not put the actual vote
inside a code fence, indented code, quote, or conditional sentence. Text after the verdict
makes it incomplete for voting and timeout salvage.

Artifact fingerprints include tracked and non-ignored working-tree file bytes,
including uncommitted changes. Outside Git, common runtime and dependency
directories are omitted. Symlinks are recorded as links rather than followed.
Each contribution combines that workspace fingerprint with the full-file hashes
of its validated citations, including cited ignored files and nested repositories.
The fingerprint identifies the captured inputs; it is not an immutable workspace
snapshot or proof that a model read or understood those inputs. Avoid changing
reviewed files during a council run.

## Installation and cache updates

Keep using the installed marketplace selector. Update through the host's plugin
manager, then restart it; do not edit its versioned cache. Skills remain
explicitly invoked in both Claude Code and Codex. See
[plugin compatibility](PLUGIN-COMPATIBILITY.md) for host-specific behavior.
