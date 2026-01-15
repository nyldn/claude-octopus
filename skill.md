---
name: claude-octopus
description: |
  Multi-agent orchestrator for Claude Code that coordinates Codex CLI and Gemini CLI
  for parallel task execution. Use when you need to:
  - Execute multiple independent tasks simultaneously
  - Fan-out a single prompt to multiple AI agents for diverse perspectives
  - Decompose complex tasks into subtasks and execute in parallel (map-reduce)
  - Auto-route tasks to the best agent based on task type (coding, design, research, image generation)
  - Review code from multiple angles using different AI models

  NOT for: Simple sequential tasks, tasks requiring human interaction, debugging sessions
---

# Claude Octopus

Multi-agent orchestrator for Claude Code - coordinates Codex CLI and Gemini CLI for parallel task execution with intelligent contextual routing.

## Quick Start

```bash
# Initialize workspace
./scripts/orchestrate.sh init

# Auto-route: Intelligently routes to best agent based on task type
./scripts/orchestrate.sh auto "Generate a hero image for the landing page"
./scripts/orchestrate.sh auto "Implement user authentication with JWT"
./scripts/orchestrate.sh auto "Review the auth module for security vulnerabilities"

# Fan-out: Same prompt to multiple agents
./scripts/orchestrate.sh fan-out "Review authentication security"

# Map-reduce: Decompose and parallelize complex task
./scripts/orchestrate.sh map-reduce "Refactor all API error handling"

# Check status
./scripts/orchestrate.sh status
```

## When to Use

### Contextual Auto-Routing (Recommended)
Let the orchestrator automatically select the best agent based on your task type:

**Task Types Detected:**
| Type | Keywords | Agent Used |
|------|----------|------------|
| `image` | generate image, create picture, illustration, logo | `gemini-image` |
| `review` | review code, audit, security check, find bugs | `codex-review` |
| `coding` | implement, fix, refactor, debug, TypeScript | `codex` |
| `design` | UI, UX, accessibility, component, layout | `gemini` |
| `copywriting` | write copy, headline, marketing, tone | `gemini` |
| `research` | analyze, explain, documentation, best practices | `gemini` |

**Example:**
```bash
# Image generation → gemini-image (gemini-3-pro-image-preview)
./scripts/orchestrate.sh auto "Generate a patriotic hero banner image"

# Code implementation → codex (gpt-5.2-codex)
./scripts/orchestrate.sh auto "Implement user authentication with JWT"

# Code review → codex-review (gpt-5.2-codex in review mode)
./scripts/orchestrate.sh auto "Review the login component for security issues"

# Design analysis → gemini (gemini-3-pro-preview)
./scripts/orchestrate.sh auto "Analyze the accessibility of the form components"
```

### Fan-Out Pattern
Send the same prompt to Codex and Gemini simultaneously to get diverse perspectives:

**Good for:**
- Code reviews (different models catch different issues)
- Architecture analysis
- Security audits
- Documentation generation

**Example:**
```bash
./scripts/orchestrate.sh fan-out "Analyze the authentication flow for potential security vulnerabilities"
```

### Map-Reduce Pattern
Automatically decompose complex tasks into subtasks, execute in parallel, and synthesize results:

**Good for:**
- Large refactoring tasks
- Codebase-wide changes
- Multi-file analysis
- Complex feature implementation

**Example:**
```bash
./scripts/orchestrate.sh map-reduce "Update all API routes to use consistent error handling with proper logging"
```

### Parallel Task Execution
Define explicit tasks in JSON and execute with dependency awareness:

**Good for:**
- CI/CD-style workflows
- Multi-step builds with dependencies
- Orchestrated testing

**Example tasks.json:**
```json
{
  "tasks": [
    {"id": "lint", "agent": "codex", "prompt": "Run linter and fix issues"},
    {"id": "types", "agent": "codex", "prompt": "Fix TypeScript errors"},
    {"id": "review", "agent": "gemini", "prompt": "Review changes", "depends_on": ["lint", "types"]}
  ]
}
```

## Agent Selection Guide

| Agent | Model | Best For | Characteristics |
|-------|-------|----------|-----------------|
| `codex` | gpt-5.2-codex | Complex code generation, deep refactoring | State-of-the-art on SWE-Bench Pro |
| `codex-max` | gpt-5.1-codex-max | Long-running, project-scale work | Token-efficient, native compaction |
| `codex-mini` | gpt-5.1-codex-mini | Quick fixes, simple tasks | 4x more cost-effective |
| `codex-general` | gpt-5.2 | Non-coding agentic tasks | General reasoning |
| `gemini` | gemini-3-pro-preview | Deep analysis, complex reasoning | 1M context, 76.2% SWE-bench |
| `gemini-fast` | gemini-3-flash-preview | Speed-critical tasks | Fast iteration, high-frequency |
| `gemini-image` | gemini-3-pro-image-preview | Image generation | Text-to-image, editing, up to 4K |
| `codex-review` | gpt-5.2-codex | Code review | Specialized review mode |

## Workspace Structure

After initialization:
```
~/.claude-octopus/
├── tasks.json      # Task definitions (editable)
├── results/        # Agent outputs (markdown files)
├── logs/           # Execution logs
└── .gitignore      # Excludes ephemeral data
```

## Command Reference

### orchestrate.sh

| Command | Description |
|---------|-------------|
| `init` | Initialize workspace |
| `spawn <agent> <prompt>` | Spawn single agent |
| `auto <prompt>` | Auto-route to best agent based on task type |
| `fan-out <prompt>` | Send to all agents |
| `map-reduce <prompt>` | Decompose and execute |
| `parallel [tasks.json]` | Execute task file |
| `status` | Show running agents |
| `kill [id\|all]` | Terminate agents |
| `clean` | Reset workspace |
| `aggregate` | Combine results |

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `-p, --parallel` | 3 | Max concurrent agents |
| `-t, --timeout` | 300 | Timeout per task (seconds) |
| `-v, --verbose` | false | Verbose logging |
| `-n, --dry-run` | false | Show without executing |

## Example Workflows

### Auto-Routed Image Generation
```bash
./scripts/orchestrate.sh auto "Generate a patriotic hero image with American flag"
./scripts/orchestrate.sh auto "Create an illustration of a family enjoying benefits"
```

### Auto-Routed Code Tasks
```bash
# Routes to codex for implementation
./scripts/orchestrate.sh auto "Implement a React hook for form validation"

# Routes to codex-review for review
./scripts/orchestrate.sh auto "Review the authentication module for security vulnerabilities"

# Routes to gemini for research/analysis
./scripts/orchestrate.sh auto "Analyze the codebase architecture and suggest improvements"
```

### Security Audit
```bash
./scripts/orchestrate.sh fan-out "Perform security audit focusing on: authentication, input validation, and SQL injection vulnerabilities"
```

### Codebase Refactoring
```bash
./scripts/orchestrate.sh map-reduce "Refactor all React class components to functional components with hooks"
```

### Multi-Model Code Review
```bash
./scripts/orchestrate.sh spawn codex-review "Review the latest commit for potential issues"
./scripts/orchestrate.sh spawn gemini "Analyze code quality and suggest improvements"
```

## Best Practices

1. **Start with auto** for intelligent routing based on task type
2. **Use fan-out** for exploratory tasks needing multiple perspectives
3. **Use map-reduce** for complex, decomposable tasks
4. **Define dependencies** when task order matters
5. **Set appropriate timeouts** for long-running tasks
6. **Review aggregated results** before applying changes
7. **Use verbose mode** when debugging agent issues

## Troubleshooting

### Agents not responding
```bash
./scripts/orchestrate.sh kill all
./scripts/orchestrate.sh clean
```

### Timeout issues
Increase timeout: `-t 600` for complex tasks

### Missing jq
```bash
brew install jq  # Required for JSON task files
```
