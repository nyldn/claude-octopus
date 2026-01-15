# Claude Octopus

<p align="center">
  <img src="https://img.shields.io/badge/Claude_Code-Plugin-blueviolet" alt="Claude Code Plugin">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
  <img src="https://img.shields.io/badge/Platform-macOS%20%7C%20Linux-blue" alt="Platform">
</p>

**Multi-agent orchestrator for Claude Code** - Coordinates [Codex CLI](https://github.com/openai/codex) and [Gemini CLI](https://github.com/google-gemini/gemini-cli) for parallel task execution with intelligent contextual routing.

```
   ___  ___ _____  ___  ____  _   _ ___
  / _ \/ __|_   _|/ _ \|  _ \| | | / __|
 | (_) |__ \ | | | (_) | |_) | |_| \__ \
  \___/|___/ |_|  \___/|____/ \___/|___/
```

## Features

- **Intelligent Auto-Routing** - Automatically selects the best agent based on task type (coding, design, research, image generation, copywriting, code review)
- **Fan-Out Pattern** - Send the same prompt to multiple agents for diverse perspectives
- **Map-Reduce Pattern** - Decompose complex tasks into parallel subtasks
- **Parallel Execution** - Run multiple agents concurrently with dependency management
- **Result Aggregation** - Combine outputs from multiple agents into unified reports

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Agent Setup & Configuration](#agent-setup--configuration)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Available Agents](#available-agents)
- [Command Reference](#command-reference)
- [Example Workflows](#example-workflows)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Prerequisites

Before installing Claude Octopus, ensure you have:

- [Claude Code](https://claude.ai/code) CLI installed
- Bash 4.0+ (macOS: `brew install bash`)
- Optional: `jq` for JSON task files (`brew install jq`)
- Optional: `coreutils` for timeout on macOS (`brew install coreutils`)

## Installation

### Automated Installation (via Claude Code)

In a Claude Code session, simply ask:

```
Install the claude-octopus plugin from https://github.com/nyldn/claude-octopus
```

Or run these commands:

```bash
# Clone to Claude plugins directory
git clone https://github.com/nyldn/claude-octopus.git ~/.claude/plugins/claude-octopus

# Make scripts executable
chmod +x ~/.claude/plugins/claude-octopus/scripts/*.sh
chmod +x ~/.claude/plugins/claude-octopus/scripts/*.py

# Initialize workspace
~/.claude/plugins/claude-octopus/scripts/orchestrate.sh init
```

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/nyldn/claude-octopus.git ~/.claude/plugins/claude-octopus
   ```

2. Make scripts executable:
   ```bash
   chmod +x ~/.claude/plugins/claude-octopus/scripts/*.sh
   chmod +x ~/.claude/plugins/claude-octopus/scripts/*.py
   ```

3. (Optional) Add to PATH for easier access:
   ```bash
   echo 'export PATH="$HOME/.claude/plugins/claude-octopus/scripts:$PATH"' >> ~/.zshrc
   source ~/.zshrc
   ```

### Clone Anywhere and Symlink

```bash
# Clone to your preferred location
git clone https://github.com/nyldn/claude-octopus.git ~/git/claude-octopus

# Create symlink in Claude plugins
ln -s ~/git/claude-octopus ~/.claude/plugins/claude-octopus

# Make scripts executable
chmod +x ~/git/claude-octopus/scripts/*.sh
chmod +x ~/git/claude-octopus/scripts/*.py
```

## Agent Setup & Configuration

Claude Octopus requires both **Codex CLI** (OpenAI) and **Gemini CLI** (Google) to be installed and configured.

### 1. Codex CLI Setup (OpenAI)

#### Install Codex CLI

```bash
# Install via npm
npm install -g @openai/codex

# Or via Homebrew
brew install openai/tap/codex
```

#### Configure OpenAI API Key

```bash
# Option 1: Environment variable (recommended)
export OPENAI_API_KEY="sk-..."
echo 'export OPENAI_API_KEY="sk-..."' >> ~/.zshrc

# Option 2: Use Codex auth command
codex auth
```

#### Verify Codex Installation

```bash
codex --version
codex exec -m gpt-5.2-codex "echo hello"
```

### 2. Gemini CLI Setup (Google)

#### Install Gemini CLI

```bash
# Install via npm
npm install -g @anthropic/gemini-cli

# Or download from releases
# https://github.com/google-gemini/gemini-cli/releases
```

#### Configure Google API Key

```bash
# Option 1: Environment variable (recommended)
export GOOGLE_API_KEY="AIza..."
echo 'export GOOGLE_API_KEY="AIza..."' >> ~/.zshrc

# Option 2: Use Gemini auth command
gemini auth login
```

#### Get a Google API Key

1. Go to [Google AI Studio](https://aistudio.google.com/apikey)
2. Click "Create API key"
3. Copy the key and save it securely
4. Set as environment variable (see above)

#### Verify Gemini Installation

```bash
gemini --version
gemini -y -m gemini-3-pro-preview "echo hello"
```

### 3. Verify Both Agents

Run this command to verify both agents are working:

```bash
~/.claude/plugins/claude-octopus/scripts/orchestrate.sh -n auto "Test prompt"
```

You should see output indicating which agent would be selected (dry-run mode).

### Environment Variables Summary

Add these to your `~/.zshrc` or `~/.bashrc`:

```bash
# OpenAI (for Codex CLI)
export OPENAI_API_KEY="sk-..."

# Google (for Gemini CLI)
export GOOGLE_API_KEY="AIza..."

# Optional: Custom workspace location
export CLAUDE_OCTOPUS_WORKSPACE="$HOME/.claude-octopus"
```

## Quick Start

```bash
# Initialize workspace
~/.claude/plugins/claude-octopus/scripts/orchestrate.sh init

# Auto-route to best agent based on task type
~/.claude/plugins/claude-octopus/scripts/orchestrate.sh auto "Generate a hero image for the landing page"
~/.claude/plugins/claude-octopus/scripts/orchestrate.sh auto "Implement user authentication with JWT"
~/.claude/plugins/claude-octopus/scripts/orchestrate.sh auto "Review the auth module for security vulnerabilities"

# Check status
~/.claude/plugins/claude-octopus/scripts/orchestrate.sh status
```

## Usage

### Auto-Route (Recommended)

Automatically selects the best agent based on your prompt:

```bash
./scripts/orchestrate.sh auto "Generate a hero image for the landing page"
# → Routes to gemini-image (Gemini 3 Pro Image Preview)

./scripts/orchestrate.sh auto "Implement user authentication"
# → Routes to codex (GPT-5.2-Codex)

./scripts/orchestrate.sh auto "Review the login module for security issues"
# → Routes to codex-review (GPT-5.2-Codex in review mode)

./scripts/orchestrate.sh auto "Analyze the codebase architecture"
# → Routes to gemini (Gemini 3 Pro Preview)
```

### Task Type Detection

| Task Type | Keywords | Agent |
|-----------|----------|-------|
| `image` | generate image, create picture, illustration, logo | `gemini-image` |
| `review` | review code, audit, security check, find bugs | `codex-review` |
| `coding` | implement, fix, refactor, debug, TypeScript | `codex` |
| `design` | UI, UX, accessibility, component, layout | `gemini` |
| `copywriting` | write copy, headline, marketing, tone | `gemini` |
| `research` | analyze, explain, documentation, best practices | `gemini` |

### Fan-Out Pattern

Send the same prompt to multiple agents simultaneously:

```bash
./scripts/orchestrate.sh fan-out "Review the authentication flow for security vulnerabilities"
```

Both Codex and Gemini will analyze the prompt, providing diverse perspectives.

### Map-Reduce Pattern

Decompose complex tasks into parallel subtasks:

```bash
./scripts/orchestrate.sh map-reduce "Refactor all API routes to use consistent error handling"
```

1. **Map Phase**: Gemini decomposes the task into independent subtasks
2. **Execute Phase**: Subtasks are distributed across agents and executed in parallel
3. **Reduce Phase**: Results are aggregated into a unified output

### Parallel Task Execution

Define tasks in JSON and execute with dependency awareness:

```json
{
  "version": "1.0",
  "project": "my-project",
  "tasks": [
    {"id": "lint", "agent": "codex", "prompt": "Run linter and fix issues"},
    {"id": "types", "agent": "codex", "prompt": "Fix TypeScript errors"},
    {"id": "review", "agent": "gemini", "prompt": "Review changes", "depends_on": ["lint", "types"]}
  ],
  "settings": {
    "max_parallel": 3,
    "timeout": 300
  }
}
```

```bash
./scripts/orchestrate.sh parallel tasks.json
```

## Available Agents

| Agent | Model | Best For |
|-------|-------|----------|
| `codex` | GPT-5.2-Codex | Complex code generation, deep refactoring |
| `codex-max` | GPT-5.1-Codex-Max | Long-running, project-scale work |
| `codex-mini` | GPT-5.1-Codex-Mini | Quick fixes, simple tasks (cost-effective) |
| `codex-general` | GPT-5.2 | Non-coding agentic tasks |
| `gemini` | Gemini 3 Pro Preview | Deep analysis, complex reasoning (1M context) |
| `gemini-fast` | Gemini 3 Flash Preview | Speed-critical tasks |
| `gemini-image` | Gemini 3 Pro Image Preview | Text-to-image generation (up to 4K) |
| `codex-review` | GPT-5.2-Codex | Specialized code review mode |

## Command Reference

| Command | Description |
|---------|-------------|
| `init` | Initialize workspace |
| `spawn <agent> <prompt>` | Spawn single agent |
| `auto <prompt>` | Auto-route to best agent |
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
| `-d, --dir` | `$PWD` | Working directory |

## Workspace Structure

```
~/.claude-octopus/
├── tasks.json      # Task definitions (editable)
├── results/        # Agent outputs (markdown files)
├── logs/           # Execution logs
└── .gitignore      # Excludes ephemeral data
```

Override with: `CLAUDE_OCTOPUS_WORKSPACE=/custom/path`

## Example Workflows

### Security Audit

```bash
./scripts/orchestrate.sh fan-out "Perform security audit focusing on: authentication, input validation, and SQL injection vulnerabilities"
```

### Large Refactoring

```bash
./scripts/orchestrate.sh map-reduce "Refactor all React class components to functional components with hooks"
```

### Multi-Model Code Review

```bash
./scripts/orchestrate.sh spawn codex-review "Review the latest commit for potential issues"
./scripts/orchestrate.sh spawn gemini "Analyze code quality and suggest improvements"
```

### Image Generation

```bash
./scripts/orchestrate.sh auto "Generate a professional hero image showing team collaboration"
```

## Troubleshooting

### Agents not responding

```bash
./scripts/orchestrate.sh kill all
./scripts/orchestrate.sh clean
```

### Timeout issues

Increase timeout for complex tasks:

```bash
./scripts/orchestrate.sh -t 600 auto "Complex task..."
```

### Missing dependencies

```bash
# Install jq for JSON task files
brew install jq

# Install coreutils for gtimeout (macOS)
brew install coreutils
```

### Codex CLI not found

```bash
# Check if installed
which codex

# If not found, install
npm install -g @openai/codex

# Verify API key is set
echo $OPENAI_API_KEY
```

### Gemini CLI not found

```bash
# Check if installed
which gemini

# If not found, install
npm install -g @anthropic/gemini-cli

# Verify API key is set
echo $GOOGLE_API_KEY
```

### API Key Issues

**OpenAI (Codex):**
```bash
# Test API key
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY"
```

**Google (Gemini):**
```bash
# Test API key
curl "https://generativelanguage.googleapis.com/v1/models?key=$GOOGLE_API_KEY"
```

### Permission Denied

```bash
# Make scripts executable
chmod +x ~/.claude/plugins/claude-octopus/scripts/*.sh
chmod +x ~/.claude/plugins/claude-octopus/scripts/*.py
```

## Python Coordinator (Advanced)

For more sophisticated task coordination with async execution:

```bash
# Initialize
python3 ./scripts/coordinator.py init

# Auto-route
python3 ./scripts/coordinator.py auto "Your prompt here"

# Fan-out
python3 ./scripts/coordinator.py fan-out "Analyze this code"

# Map-reduce
python3 ./scripts/coordinator.py map-reduce -p 4 -t 600 "Large refactoring task"

# Execute plan
python3 ./scripts/coordinator.py plan tasks.json
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Claude Code](https://claude.ai/code) - Anthropic's CLI for Claude
- [Codex CLI](https://github.com/openai/codex) - OpenAI's coding assistant
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) - Google's Gemini CLI

---

<p align="center">
  Made with care by <a href="https://github.com/nyldn">nyldn</a>
</p>
