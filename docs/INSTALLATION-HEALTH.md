# Installation health

Claude Octopus can inspect its installation without contacting a model
provider or changing a host-managed plugin cache.

## Start with Doctor

```bash
octopus doctor installation
```

This checks the plugin root loaded by the current host, the stable Octopus
root, the saved install metadata, and the active context profile. Claude Code
and Codex have separate saved entries because they can load different plugin
versions.

Octopus stores this non-secret metadata in
`~/.claude-octopus/install-state.json`. SessionStart refreshes the current
host entry when the loaded root, plugin version, install scope, or profile has
changed. To refresh it manually, run:

```bash
octopus install-state record
```

## Inspect provider readiness

```bash
octopus capabilities
octopus capabilities --json
```

The report uses the same static readiness contract as setup and Doctor. It
does not send prompts or make provider requests. A provider can be installed
but `degraded` when authentication is missing or cannot be confirmed safely.

## Check cached installations

```bash
octopus cache-check
octopus cache-check --json
```

The cache check validates each Claude Code and Codex cache version it finds,
including the active and newest entries. Invalid stale versions are warnings;
an invalid active or newest version is a failure. The command never removes a
cache directory.

## Repair the stable root

Use a dry run first:

```bash
octopus repair --dry-run
octopus repair --apply
```

Repair can create or replace the Octopus-owned stable link at
`~/.claude-octopus/plugin` and refresh the current host's install metadata. It
refuses to replace an unowned regular file or directory. It does not alter the
Claude Code or Codex cache.

## Choose a context profile

```bash
octopus profile                 # show the current profile
octopus profile core
octopus profile orchestration
octopus profile full
```

`core` keeps optional context hooks off. `orchestration` enables context
reinforcement and post-tool coordination during active Octopus workflows.
`full` allows every profile-managed context hook defined by the installed
release. Profiles never disable safety or lifecycle hooks.

## Export a portable checkpoint

```bash
octopus handoff export
octopus handoff export --json
octopus handoff show --json
```

The export contains a small allowlisted workflow summary and strips common
credential patterns. It omits the local project path and writes with mode
`0600` under `~/.claude-octopus/handoffs/` by default. Review any checkpoint
before sharing it.

## Run the local plugin audit

```bash
octopus security-audit
octopus security-audit --json
```

This offline check validates shell syntax and plugin manifests, then reports
high-risk shell patterns for review. It audits the installed Octopus files,
not the user's project. Use `/octo:security` for a project security review.

## Exit codes

The diagnostic commands use these exit codes:

| Code | Meaning |
|---:|---|
| `0` | Checks passed, with informational results or warnings allowed where documented |
| `1` | A required check failed, a repair was blocked, or state could not be written |
| `2` | Invalid command or arguments |

JSON output remains valid when a check exits with code `1`, so automation can
read the evidence before deciding what to do.
