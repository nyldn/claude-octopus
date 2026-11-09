# Contributing to Claude Octopus

Use the [repository map](REPOSITORY.md) to locate authored sources and generated
files. The [script index](../scripts/README.md) groups runtime and maintainer
entry points. Read [AGENTS.md](../AGENTS.md) and [CLAUDE.md](../CLAUDE.md) before
editing; detailed workflow contracts are in [DEVELOPER.md](DEVELOPER.md).

## Set up a checkout

Fork the repository, clone your fork, and create a branch from current `main`.
For example:

```bash
git clone https://github.com/YOUR_USERNAME/claude-octopus.git
cd claude-octopus
git switch -c fix/short-description
```

This contributor workflow requires Git, Make, Bash 3.2 or newer, Python 3.9 or
newer, `jq`, Node.js 18 or newer, and npm. See
[plugin compatibility](PLUGIN-COMPATIBILITY.md) for host requirements. Install
the test dependencies once per clean checkout:

```bash
make test-deps
```

This setup uses npm registry access. Ordinary smoke, unit and integration tests
then use local fixtures and inert providers. They do not require provider logins
or live model calls. Preserve the executable modes stored by Git; do not apply
blanket `chmod` commands to the checkout.

## Edit the source

- Add or change slash commands in `commands/`.
- Follow the [skill source table](REPOSITORY.md#skill-sources) before editing a
  skill. Flow `.tmpl` files are retired. Most Claude entries are authored under
  `.claude/skills/`; phase-loaded discovery and refinement are authored under
  root `skills/`.
- Follow [the provider wiring checklist](PROVIDERS.md) for provider changes.
- Keep generated adapters, catalogs and release facts in sync through their
  generators. Do not patch generated output to hide a source mismatch.
- Keep Bash compatible with 3.2, quote variable expansions and use `[[ ]]` for
  conditionals. Add behavioral regressions for changed runtime contracts.

## Validate the change

Run affected suites while editing. After changing source files or plugin
metadata, regenerate and inspect the outputs:

```bash
make sync
make ci-quick
scripts/ci-changed.sh --list
```

When the selector reports focused coverage, run `make ci-changed`. For a shared
or unmapped change, use affected regressions and the required hosted matrix;
`make ci-local` remains the complete offline fallback. Do not repeat a completed
hosted matrix locally. The [test guide](../tests/README.md) owns the test tiers,
fixture rules and live-test boundary.

Inspect `git diff --check` and `git diff --summary`. Shell scripts and Python
helpers must retain their executable bits. Local tests can alter fixture modes,
so review mode changes after running them. Packaging or installation changes
also require the native/artifact checks in [RELEASING.md](../RELEASING.md).

## Submit a PR

Use a focused branch and a conventional commit, such as `fix: preserve review
paths` or `docs: explain setup recovery`. Describe the problem, resulting behavior
and relevant validation. Update public documentation and the changelog when the
change affects their contracts.

Before merge, the exact PR commit must have successful `Smoke Tests`, `Unit
Tests` and `Integration Tests`, an independent approved review, zero unresolved
review threads and an up-to-date base. A changed commit needs fresh evidence.
Publication has the additional gates in [RELEASING.md](../RELEASING.md).

## Report a problem or propose a feature

Open a GitHub issue with the observed behavior, expected result, reproduction
steps, relevant environment details and bounded logs. Check existing issues
before proposing a feature, then explain the use case and expected benefit.
Keep credentials and private project content out of public reports.

Follow the [code of conduct](CODE_OF_CONDUCT.md) in issues and reviews.
