# Script index

The [repository map](../docs/REPOSITORY.md) records source ownership and generated
outputs. This index groups the existing script paths by their role.

## Runtime entry points

| Entry | Purpose |
| --- | --- |
| [`../bin/octopus`](../bin/octopus), [`orchestrate.sh`](orchestrate.sh) | CLI and workflow dispatch |
| [`doctor.sh`](doctor.sh), [`repair.sh`](repair.sh) | Installation and environment diagnosis or repair |
| [`provider-router.sh`](provider-router.sh) | Provider routing interface |
| [`octo-state.sh`](octo-state.sh), [`state-manager.sh`](state-manager.sh) | Project and workflow state interfaces |
| [`refinement-run.py`](refinement-run.py), [`refinement-judge.sh`](refinement-judge.sh), [`refinement-pair.py`](refinement-pair.py), [`refinement-score.py`](refinement-score.py) | Persisted refinement control, paired judging and scoring |
| [`scheduler/`](scheduler/) | Scheduled workflow runner |

## Runtime implementation

| Directory | Purpose |
| --- | --- |
| [`lib/`](lib/) | Sourced Bash modules for dispatch, providers, workflows, safety and accounting |
| [`helpers/`](helpers/) | Standalone helpers called by those modules or skill contracts |
| [`extract/`](extract/) | Content extraction orchestration |
| [`token-extraction/`](token-extraction/) | Provider-specific usage parsing and its fixtures; see its [README](token-extraction/README.md) |

Follow the caller's path when changing a helper. Public commands and skills may
invoke it directly, so a file move needs a reference audit and the relevant
behavior checks.

## Generators

`make sync` runs the maintained generation pipeline. `make sync-check` verifies it.

| Script | Responsibility |
| --- | --- |
| [`sync-readme.py`](sync-readme.py) | Mechanical release facts, counts and manifest fields |
| [`sync-marketplace.sh`](sync-marketplace.sh) | Local marketplace entry from plugin metadata |
| [`build-factory-skills.sh`](build-factory-skills.sh) | Calls the portable skill builder; generates Cursor commands and Factory droids |
| [`build-codex-skills.sh`](build-codex-skills.sh) | Portable skills, interface metadata and canonical-entry mirrors |
| [`gen-skill-docs.sh`](gen-skill-docs.sh) | Compatibility entry point for the same skill builder; accepts `--dry-run` |

## Contributor and release tools

| Script | Responsibility |
| --- | --- |
| [`ci-changed.sh`](ci-changed.sh) | Selects affected suites through [`tests/changed-scope.tsv`](../tests/changed-scope.tsv) |
| [`validate-plugin-assembly.py`](validate-plugin-assembly.py) | Checks registered plugin components and host metadata |
| [`validate-release.sh`](validate-release.sh) | Checks release consistency and publication state without publishing |
| [`release.sh`](release.sh) | Gated version, PR, merge, tag and release process |
| [`sync-shared-marketplace.sh`](sync-shared-marketplace.sh) | Updates only the Octopus entry in the shared marketplace |
| [`safe-gh-comment.sh`](safe-gh-comment.sh) | Validates generated GitHub text before writing it |

See [Contributing](../docs/CONTRIBUTING.md), [the test guide](../tests/README.md)
and [the release checklist](../RELEASING.md) for required checks and authorization.
