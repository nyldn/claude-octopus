# Contributing to Claude Octopus

Thanks for your interest in contributing to Claude Octopus! This document provides guidelines for contributing.

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/claude-octopus.git
   cd claude-octopus
   ```
3. **Make scripts executable**:
   ```bash
   chmod +x scripts/*.sh scripts/*.py
   ```

## Development Setup

### Prerequisites

- Bash 3.2+ (bash 3.x compatible — no associative arrays)
- jq (for JSON processing)
- Codex CLI, Antigravity CLI (`agy`), Copilot CLI, Ollama (all optional — for multi-provider testing)

### Validate Your Changes

```bash
# Regenerate shipped plugin artifacts
bash scripts/build-factory-skills.sh

# Validate plugin against the local Claude CLI
claude plugin validate .claude-plugin/plugin.json

# Check shell script syntax
bash -n scripts/orchestrate.sh
bash -n scripts/lib/*.sh

# Run test suite
bash tests/unit/test-openclaw-compat.sh
bash tests/unit/test-adapter-flags.sh

# Verify OpenClaw registry in sync
scripts/build-openclaw.sh --check

# Run full pre-push suite
bash tests/run-pre-push.sh
```

## Making Changes

### Branch Naming

- `feature/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation updates
- `refactor/` - Code refactoring

Example: `feature/add-new-agent-type`

### Commit Messages

Follow conventional commits:

```
type: short description

Longer description if needed.
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`

### Code Style

**Bash:**
- Use `[[ ]]` for conditionals
- Quote variables: `"$var"`
- Use functions for reusable logic
- Add comments for complex sections

## Pull Request Process

1. **Create a feature branch** from `main`
2. **Make your changes** with clear commits
3. **Test thoroughly** with dry-run mode
4. **Update documentation** if needed
5. **Submit a PR** with a clear description

### PR Checklist

- [ ] Shell scripts pass `bash -n` check
- [ ] Tests pass: `bash tests/run-pre-push.sh`
- [ ] Generated plugin-root skills/commands refreshed and `claude plugin validate .claude-plugin/plugin.json` passes
- [ ] Documentation updated (if applicable)
- [ ] CHANGELOG.md updated (for features/fixes)
- [ ] Commit messages follow conventions

## Reporting Issues

When reporting issues, please include:

1. **Description** - What happened?
2. **Expected behavior** - What should happen?
3. **Steps to reproduce** - How can we recreate it?
4. **Environment** - OS, Bash version, etc.
5. **Logs** - Run with `-v` for verbose output

## Feature Requests

For feature requests:

1. **Check existing issues** first
2. **Describe the use case** - Why is this needed?
3. **Propose a solution** - How might it work?

## Code of Conduct

Be respectful and constructive. We're all here to build something useful together.

## Questions?

Open an issue with the `question` label or reach out to the maintainers.

---

*"Eight tentacles working together build better software."* 🐙
