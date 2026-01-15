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

- Bash 4.0+ (`bash --version`)
- Python 3.8+
- jq (for JSON processing)
- Codex CLI and Gemini CLI (for full testing)

### Validate Your Changes

```bash
# Check shell script syntax
bash -n scripts/orchestrate.sh

# Check Python syntax
python3 -m py_compile scripts/coordinator.py

# Dry-run test
./scripts/orchestrate.sh -n auto "test prompt"
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

**Python:**
- Follow PEP 8
- Use type hints
- Document functions with docstrings

## Pull Request Process

1. **Create a feature branch** from `main`
2. **Make your changes** with clear commits
3. **Test thoroughly** with dry-run mode
4. **Update documentation** if needed
5. **Submit a PR** with a clear description

### PR Checklist

- [ ] Code passes syntax validation
- [ ] Dry-run tests pass
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
