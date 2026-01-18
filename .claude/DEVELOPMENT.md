# Claude Octopus - Plugin Development Guide

This document is for **developers working on the Claude Octopus plugin itself**. For plugin usage, see the main README.md.

## 📁 File Organization

**IMPORTANT:** Before adding files, read `.dev/FILE-ORGANIZATION.md` for the complete file placement guide.

Quick reference:
- **Commands**: `.claude/commands/` (sys-, flow-, skill- prefixes)
- **Skills**: `.claude/skills/` (registered in plugin.json)
- **Agents**: `agents/personas/`, `agents/principles/`, `agents/skills/`
- **Hooks**: `hooks/` (configured in `.claude-plugin/hooks.json`)
- **Tests**: `tests/` (smoke, unit, integration, e2e)
- **Dev files**: `.dev/` (NEVER committed - gitignored)

## 🏗️ Plugin Architecture

### Plugin Metadata
```
.claude-plugin/
├── plugin.json           # Main manifest (name, version, skills, commands)
├── marketplace.json      # Marketplace listing
└── hooks.json            # Hook configurations
```

### Core Components

#### 1. Commands (Slash Commands)
Located in `.claude/commands/`, invoked as `/namespace:command` or `/command`.

**Naming convention:**
- `sys-*.md` - System commands (setup, update)
- `flow-*.md` - Workflow commands (probe, grasp, tangle, ink)
- `skill-*.md` - Skill shortcuts

**YAML Frontmatter:**
```yaml
---
command: command-name
description: Short description for help text
category: system|workflow|skill
---
```

#### 2. Skills
Located in `.claude/skills/`, invoked by Claude or via skill shortcuts.

**Registration:** Must be listed in `.claude-plugin/plugin.json`:
```json
{
  "skills": [
    "./.claude/skills/skill-code-review.md",
    "./.claude/skills/flow-probe.md"
  ]
}
```

**YAML Frontmatter:**
```yaml
---
name: skill-name
description: Detailed skill description
use_when: When to invoke this skill
category: workflow|capability|system
---
```

#### 3. Agents (Subagents)
Located in `agents/` with subcategories:

- **Personas** (`agents/personas/`): Role-based agents
  - Example: `frontend-developer.md`, `backend-architect.md`

- **Principles** (`agents/principles/`): Critique agents
  - Example: `performance-principles.md`, `security-principles.md`

- **Skills** (`agents/skills/`): Skill-backed agents
  - Example: `octopus-code-review.md`, `octopus-architecture.md`

**YAML Frontmatter:**
```yaml
---
name: agent-name
description: Agent description
color: "#HEX"  # Display color
tools:
  - all  # or specific tool list
---
```

#### 4. Hooks
Event-driven automation configured in `.claude-plugin/hooks.json`.

**Hook Types:**
- `PreToolUse` - Before tool execution
- `PostToolUse` - After tool execution
- `SessionStart` - Session initialization
- `Stop`, `SubagentStop`, `UserPromptSubmit`, etc.

**Configuration:**
```json
{
  "PreToolUse": [
    {
      "matcher": {
        "tool": "Bash",
        "pattern": "pattern-regex"
      },
      "hooks": [
        {
          "type": "prompt",
          "prompt": "Message to Claude"
        }
      ]
    }
  ]
}
```

## 🧪 Testing

### Test Structure
```
tests/
├── smoke/          # Fast validation (< 5 seconds total)
├── unit/           # Isolated function tests
├── integration/    # Multi-component tests
├── e2e/            # Full workflow tests
├── benchmark/      # Performance benchmarks
├── helpers/        # Test utilities
└── fixtures/       # Test data
```

### Running Tests

```bash
# All tests
make test

# By category
make test-smoke       # Fast smoke tests
make test-unit        # Unit tests
make test-integration # Integration tests
make test-e2e         # End-to-end tests

# Individual test
./tests/smoke/test-syntax.sh
```

### Writing Tests

Tests should be self-contained bash scripts:

```bash
#!/bin/bash
set -euo pipefail

# Test description
echo "Test: my-feature"

# Setup
source tests/helpers/test-framework.sh

# Test logic
result=$(my_function "input")

# Assertion
assert_equals "$result" "expected" "my-feature works"

# Cleanup
cleanup

echo "✓ PASS: my-feature"
```

## 📝 Adding New Functionality

### New Command

1. Create `.claude/commands/category-name.md`:
```markdown
---
command: my-command
description: Short description
category: system
---

# Command Implementation

Command prompt and instructions...
```

2. No registration needed - auto-discovered from `.claude/commands/`

3. Test: `/namespace:my-command` or `/my-command`

### New Skill

1. Create `.claude/skills/skill-name.md`:
```markdown
---
name: skill-name
description: Detailed description of what this skill does
use_when: When Claude should invoke this skill
category: capability
---

# Skill Implementation

Skill instructions and examples...
```

2. Register in `.claude-plugin/plugin.json`:
```json
{
  "skills": [
    "./.claude/skills/skill-name.md"
  ]
}
```

3. Create shortcut command in `.claude/commands/skill-name.md`:
```markdown
---
command: name
description: Quick access to skill
---

Use the Skill tool with skill="namespace:skill-name"
```

### New Agent

1. Choose category:
   - Persona: `agents/personas/role-name.md`
   - Principle: `agents/principles/principle-name.md`
   - Skill: `agents/skills/namespace-skill-name.md`

2. Create agent file:
```markdown
---
name: agent-name
description: Agent description (visible in Task tool)
color: "#4A90E2"
tools:
  - all  # or specific tools
---

# System Prompt

Agent's system instructions...
```

3. If skill-backed, create corresponding skill and register it

4. Configure routing in `agents/config.yaml` if needed

### New Hook

1. Create hook script in `hooks/`:
```bash
#!/bin/bash
# Hook implementation
echo "Hook executed"
```

2. Configure in `.claude-plugin/hooks.json`:
```json
{
  "PreToolUse": [
    {
      "matcher": {
        "tool": "Bash",
        "pattern": "my-pattern"
      },
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/hooks/my-hook.sh"
        }
      ]
    }
  ]
}
```

3. Make executable: `chmod +x hooks/my-hook.sh`

## 🔍 Debugging

### Common Issues

**Command not found:**
- Check file exists in `.claude/commands/`
- Verify YAML frontmatter has `command:` field
- Try `/namespace:command` instead of `/command`

**Skill not invoked:**
- Verify skill is registered in `plugin.json`
- Check `use_when` description is clear
- Try invoking manually with Skill tool

**Agent not available:**
- Check YAML frontmatter format
- Verify `description` field (shown in Task tool)
- Check file is in correct `agents/` subdirectory

**Hook not triggering:**
- Verify pattern matches the command
- Check hook script is executable
- Review `hooks.json` syntax

### Debug Mode

```bash
# Verbose Claude Code output
claude --verbose

# Check plugin loading
claude --list-plugins

# Test hook patterns
grep -r "pattern-text" .claude-plugin/hooks.json
```

## 📦 Version Management

### Version Bump Checklist

1. Update version in:
   - `.claude-plugin/plugin.json`
   - `.claude-plugin/marketplace.json`
   - `README.md`

2. Update `CHANGELOG.md`:
```markdown
## [7.x.x] - 2026-MM-DD

### Added
- New feature description

### Changed
- Modified behavior description

### Fixed
- Bug fix description
```

3. Create git tag:
```bash
git tag -a v7.x.x -m "Version 7.x.x: Description"
git push origin v7.x.x
```

## 🚀 Release Process

1. **Pre-release checks:**
```bash
make test              # All tests pass
make lint              # No syntax errors
git status             # Working tree clean
```

2. **Update documentation:**
   - README.md usage examples
   - CHANGELOG.md version entry
   - Command/skill documentation

3. **Version bump:** (see above)

4. **Commit and tag:**
```bash
git add .
git commit -m "chore: Version 7.x.x"
git tag -a v7.x.x -m "Release 7.x.x"
git push origin main --tags
```

5. **GitHub Release:**
   - Draft release notes from CHANGELOG.md
   - Attach any assets if needed
   - Publish release

## 🛠️ Development Tools

### Makefile Targets

```bash
make help              # Show all targets
make test              # Run all tests
make test-smoke        # Smoke tests only
make lint              # Syntax checks
make clean             # Clean artifacts
```

### Helper Scripts

```bash
scripts/install-hooks.sh    # Install git hooks
tests/helpers/test-framework.sh  # Test utilities
```

## 📚 Best Practices

### Commands
- Use imperative mood: "Setup", not "Sets up"
- Keep descriptions under 80 characters
- Use categories consistently (system, workflow, skill)

### Skills
- Clear `use_when` triggers
- Detailed instructions in content
- Examples for complex skills

### Agents
- Focused, single-purpose descriptions
- Specific tool requirements
- Color codes for visual organization

### Hooks
- Minimal performance impact
- Fail gracefully (exit 0 on errors)
- Use `${CLAUDE_PLUGIN_ROOT}` for paths

### Tests
- Fast smoke tests (< 1 second each)
- Isolated unit tests (no external dependencies)
- Realistic integration tests
- Comprehensive e2e tests (main workflows)

## 🔗 Resources

- **File Organization**: `.dev/FILE-ORGANIZATION.md` (complete guide)
- **Main README**: `README.md` (user documentation)
- **Changelog**: `CHANGELOG.md` (version history)
- **License**: `LICENSE` (MIT)

## 🤝 Contributing

1. Read `.dev/FILE-ORGANIZATION.md` first
2. Create feature branch: `git checkout -b feature/name`
3. Add tests for new functionality
4. Update documentation
5. Submit pull request with clear description

---

**Last Updated:** v7.5.2 (2026-01-18)
