# Migrating to Claude Octopus v10

Claude Octopus v10 makes orchestration results auditable and fail-closed. The
provider roster and existing model pins remain compatible, but scripts that
interpret Doctor status or assume every completed process contributed should
adopt the contracts below.

## Before upgrading

1. Record provider and role pins from
   `~/.claude-octopus/config/providers.json` and your `OCTOPUS_*_MODEL`
   environment variables. V10 does not overwrite them.
2. Finish or cancel active multi-provider runs. V10 can inspect older legacy
   status files, but only v10 runs have the complete seat-transition manifest.
3. Upgrade through the normal marketplace or package-manager flow; do not edit
   Claude Code or Codex cache directories directly.
4. Run `/octo:setup`, then run `octopus doctor --json` and inspect both its JSON
   body and exit status.

## Behavior changes

### Execution truth

Every provider seat now progresses through a typed lifecycle:

```text
planned -> starting -> authenticated -> running -> output_received -> validated -> contributed
```

`degraded`, `skipped`, `failed`, `timeout`, and `cancelled` are terminal states.
Only `contributed`, plus explicitly eligible degraded output, can enter
synthesis. A provider process exiting zero is no longer enough: empty,
whitespace-only, placeholder, partial timed-out, or unpersisted output is
ineligible.

Legacy `agents.jsonl` and `agents.json` files remain available as a compatibility
projection. New automation should read the v10 manifest:

```bash
octopus status --run latest --json
octopus explain --run latest
```

The durable source is `~/.claude-octopus/runs/<run-id>/run.json`.
`~/.claude-octopus/runs/latest` remains a compatibility symlink to the latest
complete run directory.

### Doctor 2.0

Doctor now has three meaningful exit classes:

| Exit | Meaning |
|---|---|
| `0` | Checks passed or produced warnings only |
| `1` | One or more checks failed; JSON output is still valid |
| `2` | Invalid option, category, or ambiguous arguments |

Do not place `doctor --json` directly behind `set -e` when you need its report:

```bash
set +e
doctor_json="$(octopus doctor --json)"
doctor_rc=$?
set -e
jq '.summary' <<<"$doctor_json"
```

Setup uses this report as its readiness source. Installation alone does not
prove authentication or that a configured model resolves.

### Provider Registry 2.0

Provider configuration files and environment variables keep their existing
shape. Maintainers adding a provider must now register matching identity and
runtime-policy rows in `scripts/lib/provider-registry.sh`; parity validation
fails closed when a field or row is missing. Provider-specific command,
credential, model, and environment adapters remain explicit.

### Cancellation and recovery

Background cancellation targets the recorded process group, waits for
descendant cleanup, and persists the cleanup result before terminalizing the
seat. Interrupted or stale `running` work can be inspected through `status` and
`explain`. Retrying a non-contributed seat creates a distinct attempt; a
contributed seat is not silently rerun.

### Routing and Fable

Eval routing is opt-in:

```bash
export OCTOPUS_ROUTING_POLICY=eval
```

It classifies work as mechanical, balanced, premium, review, or security while
retaining explicit environment and project-route precedence. Fable receives at
most one premium escalation seat per durable run and rejects prompts above
524,288 bytes before dispatch. Change that ceiling with
`OCTOPUS_FABLE5_MAX_INPUT_BYTES`. Fable and Opus are both Anthropic-family
models, so independent verification selects another vendor unless an explicit
same-family pin is honored with degraded coverage.

## Verification after upgrading

```bash
octopus doctor --json
octopus status --run latest --json
octopus explain --run latest
```

For maintainers, the release regression is hermetic and requires no credentials:

```bash
bash tests/integration/test-v10-failure-injection.sh
make ci-local
bash scripts/validate-release.sh
```

## Rollback

- Set `OCTOPUS_ROUTING_POLICY=off` to disable eval-backed defaults immediately.
- Set `OCTOPUS_FABLE5_MODE=off` to disable Fable guards and escalation.
- Continue using `octopus agent-summary` if an integration is not yet migrated
  to the v10 manifest.
- For a complete rollback, reinstall v9.66.1 through the same package manager or
  source-tag workflow used for installation. Do not repoint versioned cache
  directories or symlinks by hand.

V10 run artifacts are additive. Rolling back does not require deleting them.
