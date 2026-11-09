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
versions. It is read-only. A missing or mismatched stable root is reported for
repair; Doctor does not create or replace it.

Octopus stores this non-secret metadata in
`~/.claude-octopus/install-state.json`. SessionStart refreshes the current
host entry when the loaded root, plugin version, install scope, or profile has
changed. To refresh it manually, run:

```bash
octopus install-state record
```

`install-state record` writes metadata. It is separate from the read-only
health checks.

## Inspect provider readiness

```bash
octopus capabilities
octopus capabilities --json
```

The report uses the same static readiness contract as setup and Doctor. It
does not send prompts or make provider requests. A provider can be installed
but `degraded` when authentication is missing or cannot be confirmed safely.

## Council prerequisites

Council requires `python3` on `PATH` for atomic run-status updates and
same-key supersession. The helper uses the standard-library `fcntl` lock on
macOS and Linux; no Python packages are required. Install Python 3 before
running Council. A missing interpreter stops the run before provider dispatch
or run-directory creation and reports the prerequisite.

## Check dispatched Claude seats

Workflow preflight can run a provider smoke test. It sends a trivial prompt
through the same `claude --print` command used by Claude seats, with the selected
binary and model. This checks the subprocess login separately from the host
session. `OCTOPUS_CLAUDE_SMOKE_TIMEOUT` sets the wait, with a default of 60 seconds.
An authentication error fails preflight with login guidance. A timeout reports
degraded readiness and lets the workflow continue, including for a Claude-only
fleet. Excluding Claude with `OCTO_ALLOWED_PROVIDERS` skips its smoke check.

The smoke cache includes whether Claude is checked, its binary, and its model.
Changing any of these requires a new check. Static Doctor and capability reports
remain local-only; they do not run this prompt.

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
```

Repair can create or replace the Octopus-owned stable link at
`~/.claude-octopus/plugin` and refresh the current host's install metadata. It
refuses to replace an unowned regular file or directory. It does not alter the
Claude Code or Codex cache. Treat `--apply` as a write: review the dry-run
output and authorize the exact repair first. Then, and only then, run:

```bash
octopus repair --apply
```

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
release. `OCTOPUS_CONTEXT_PROFILE` selects this setting and
`OCTOPUS_HOOK_PROFILE` can override the optional hook profile. These settings
never disable safety or lifecycle hooks. `OCTO_PROFILE` is the separate legacy
workflow-intensity setting, not a context-hook switch.

## Export a portable checkpoint

```bash
octopus handoff export
octopus handoff export --json
octopus handoff show --json
```

The export contains a small allowlisted workflow summary and redacts common
credential patterns. It omits the local project path and writes with mode
`0600` under `~/.claude-octopus/handoffs/` by default. Redaction is pattern-based,
not a guarantee that every secret is removed. An arbitrary input or output
failure can also prevent the command from producing valid JSON. Review any
checkpoint before sharing it.

The file is a summary for inspection or manual transfer, not imported runtime
state. `/octo:resume` resumes local state; it does not import this JSON.

## Run the local plugin audit

```bash
octopus security-audit
octopus security-audit --json
```

This offline check validates shell syntax and plugin manifests, then reports
high-risk shell patterns for review. It audits the installed Octopus files,
not the user's project. Use `/octo:security` for a project security review.

## Setup behavior

`/octo:setup` runs the installation Doctor category and cache check as a safe,
read-only health pass when setup is used for troubleshooting and again during
completion verification. It reports the evidence without applying repairs,
cleaning caches, logging in, or contacting a provider service. If the report
calls for a change, review `octopus repair --dry-run` and authorize
`octopus repair --apply` separately.

## Exit codes

The diagnostic commands use these exit codes:

| Code | Meaning |
|---:|---|
| `0` | Checks passed, with informational results or warnings allowed where documented |
| `1` | A required check failed, a repair was blocked, or state could not be written |
| `2` | Invalid command or arguments |

JSON output remains valid when a check exits with code `1`, so automation can
read the evidence before deciding what to do.

## Windows host acceptance

Octopus workflows run on Linux and macOS. Windows users can run the Claude Code
CLI inside WSL, with a separate Linux plugin installation, or use Claude Code
Desktop over SSH to a Linux or macOS host. The desktop app's built-in WSL sessions
[do not load plugins](https://code.claude.com/docs/en/desktop-wsl).

On native Git Bash, MSYS2, and Cygwin, every registered Claude Code hook exits
before reading input or writing state. The SessionStart root helper creates no
stable-root copy. Codex uses the existing native Windows no-op hook commands.
Run `bash tests/unit/test-native-windows-hook-inert.sh` and
`bash tests/unit/test-windows-doctor-compat.sh` to check simulated Windows hosts,
WSL identification, and the documented entry points. Actual Windows desktop
installation requires a Windows host; simulation does not establish host discovery.

## Portable feature workflow

`/octo:spec` creates `specs/NNN-slug/` with `spec.md`, `research.md`,
`plan.md`, `tasks.md`, `decisions.md` and `feature.json`. The manifest keeps
relative artifact paths, provider attribution, task identities and open user
decisions. Existing Spec Kit directories are reused. Raw transcripts and policy
snapshots stay in runtime state.

`OCTOPUS_FEATURE` selects a feature directory or spec filename. With multiple
features, select one before planning, development or resume. An explicit spec
filename is honored. `OCTOPUS_FEATURE_LAYOUT=legacy` keeps new specs at the
repository root; the default `auto` retains existing root specs and uses feature
directories for new ones. Both layouts remain supported through the next minor
release. Non-Git or unwritable repositories receive a warning and use the legacy
path when it is writable.

Policy discovery checks `.specify/memory/constitution.md`, then the path in
`OCTOPUS_PROJECT_POLICY`, then `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md` and
`.github/CONTRIBUTING.md`. The first readable, bounded source wins. Missing
policy warns and proceeds. Octopus does not create a constitution. A verified
conflict must quote the policy and the proposed action against their current
source digests before implementation is blocked.

Skipped user questions remain in the spec. The host asks at most three in a
batch before the next affected phase. Task-specific decisions defer affected
tasks while independent tasks may proceed. Models cannot resolve user decisions
by supplying their own answers.

`/octo:resume specs/NNN-slug` reads repository artifacts on a fresh clone.
Historical completion is evidence to check, not execution permission. Completed
coding scopes must match the current committed files and pass fresh repository
verification before they unlock dependent tasks. Unverified work remains pending.

The delivery checks for these paths exercise first and repeated activation,
legacy and Spec Kit compatibility, concurrent allocation, secret withholding,
policy conflicts, skipped questions, stable task identities, both dispatchers,
fresh-home resume and the packaged command/skill references. They use disposable
repositories and inert providers. They do not install into an active host cache.

Run the focused acceptance checks with:

```bash
bash tests/unit/test-feature-delivery.sh
bash tests/unit/test-feature-workflow.sh
bash tests/unit/test-feature-tasks.sh
bash tests/unit/test-feature-analysis-runtime.sh
make sync-check
make validate-plugin-assembly
```

Run `make ci-changed` before pushing and `make ci-local` before merging.
The hosted branch checks must pass against the PR's current commit.

## Recover a discovery handoff

Define stops before provider dispatch if discovery is incomplete or its saved
research is missing, changed or unsafe to read. Restore the original artifact to keep using that research.
To proceed without it, explicitly discard the handoff binding and retry
`/octo:define`. Standalone Define requests use the same recovery.

Use the absolute installed plugin root for `OCTO_ROOT`, then run:

```bash
WORKFLOW_STATE_FILE=$("${OCTO_ROOT:?Set OCTO_ROOT to the installed plugin root}/scripts/state-manager.sh" handoff_path)
python3 "$OCTO_ROOT/scripts/helpers/discovery-handoff.py" discard "$WORKFLOW_STATE_FILE"
```

Discarding clears only the current project's handoff record. It preserves
research files, project documents, decisions and provider settings. A new
discovery also invalidates the prior binding. Completed research becomes
available to Define only after presentation and requested persistence succeed.

Discovery completion holds the current-run lock while saving an opted-in
project summary and completion status. It records rollback data before those
writes. If publication fails or the process stops, the next handoff operation
restores the previous summary and incomplete state before proceeding. A
superseded run cannot change the current project's completion files.

The discovery handoff uses the physical project path as its identity, so adding
or changing a Git remote does not hide completed research. Existing records
are adopted in place through a stable index. Their locks and recovery journals
stay in their original location. The general workflow state remains separate.
