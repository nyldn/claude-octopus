# Claude Octopus

<p align="center">
  <img src="https://img.shields.io/badge/Claude_Code-Plugin-blueviolet" alt="Claude Code Plugin">
  <img src="https://img.shields.io/badge/Double_Diamond-Design_Thinking-orange" alt="Double Diamond">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
  <img src="https://img.shields.io/badge/Version-1.0.0-blue" alt="Version 1.0.0">
</p>

**Multi-tentacled orchestrator for Claude Code** - using Double Diamond methodology for comprehensive problem exploration, consensus building, and validated delivery.

```
    DISCOVER          DEFINE           DEVELOP          DELIVER
      (probe)         (grasp)          (tangle)          (ink)

    \         /     \         /     \         /     \         /
     \   *   /       \   *   /       \   *   /       \   *   /
      \ * * /         \     /         \ * * /         \     /
       \   /           \   /           \   /           \   /
        \ /             \ /             \ /             \ /

   Diverge then      Converge to      Diverge with     Converge to
    converge          problem          solutions        delivery
```

> *An octopus uses its 8 arms in parallel. So does this orchestrator. Coincidence? We think not.* 🐙

<details>
<summary>🐙 Click to meet our mascot</summary>

```
                      ___
                  .-'   `'.
                 /         \
                 |         ;
                 |         |           ___.--,
        _.._     |0) ~ (0) |    _.---'`__.-( (_.
 __.--'`_.. '.__.\    '--. \_.-' ,.--'`     `""`
( ,.--'`   ',__ /./;   ;, '.__.'`    __
_`) )  .---.__.' / |   |\   \__..--""  """--.,_
`---' .'.''-._.-'`_./  /\ '.  \ _.-~~~````~~~-._`-.__.'
     | |  .' _.-' |  |  \  \  '.               `~---`
      \ \/ .'     \  \   '. '-._)
       \/ /        \  \    `=.__`~-.
       / /\         `) )    / / `"".`\
 , _.-'.'\ \        / /    ( (     / /
  `--~`   ) )    .-'.'      '.'.  | (
         (/`    ( (`          ) )  '-;
          `      '-;         (-'
```

*"Eight tentacles, infinite possibilities."*

</details>

## What's New in 1.0

- **Double Diamond Workflow** - Structured design thinking process
- **Octopus-Themed Commands** - `probe`, `grasp`, `tangle`, `ink`, `embrace`
- **Smart Auto-Routing** - Intent detection routes to workflows or agents
- **Premium Model Defaults** - GPT-5.1-Codex-Max for coding tasks
- **Quality Gates** - 75% success threshold in development phase

## Table of Contents

- [Quick Start](#quick-start)
- [Double Diamond Methodology](#double-diamond-methodology)
- [Smart Auto-Routing](#smart-auto-routing)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Agent Setup & Configuration](#agent-setup--configuration)
- [Available Agents](#available-agents)
- [Command Reference](#command-reference)
- [Example Workflows](#example-workflows)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Quick Start

### Install via Marketplace

```
/plugin marketplace add nyldn/claude-octopus
/plugin install claude-octopus@nyldn-plugins
```

### Use It

```bash
# Full Double Diamond workflow (all 4 phases)
./scripts/orchestrate.sh embrace "Build a user authentication system"

# Smart auto-routing (detects intent automatically)
./scripts/orchestrate.sh auto "research OAuth patterns"           # -> probe
./scripts/orchestrate.sh auto "build user login"                  # -> tangle + ink
./scripts/orchestrate.sh auto "review the auth code"              # -> ink

# Individual phases
./scripts/orchestrate.sh probe "Research authentication best practices"
./scripts/orchestrate.sh grasp "Define auth requirements"
./scripts/orchestrate.sh tangle "Implement auth feature"
./scripts/orchestrate.sh ink "Validate and deliver auth implementation"
```

## Double Diamond Methodology

Claude Octopus implements the [Double Diamond](https://www.designcouncil.org.uk/our-resources/framework-for-innovation/) design process, providing structured workflows for each phase:

### Phase 1: PROBE (Discover)
**Diverge then converge on understanding**

Parallel research from 4 perspectives:
- Problem space analysis (constraints, requirements, needs)
- Existing solutions research (what worked, what failed)
- Edge cases exploration (potential challenges)
- Technical feasibility (prerequisites, dependencies)

```bash
./scripts/orchestrate.sh probe "What are the best approaches for real-time notifications?"
```

### Phase 2: GRASP (Define)
**Build consensus on the problem**

Multi-tentacled problem definition:
- Core problem statement
- Success criteria
- Constraints and boundaries

```bash
./scripts/orchestrate.sh grasp "Define requirements for notification system"
```

### Phase 3: TANGLE (Develop)
**Diverge with multiple solutions**

Enhanced map-reduce with validation:
- Task decomposition via LLM
- Parallel execution across agents
- Quality gate (75% success threshold)

```bash
./scripts/orchestrate.sh tangle "Implement notification service"
```

### Phase 4: INK (Deliver)
**Converge to validated delivery**

Pre-delivery validation:
- Quality gate verification
- Result synthesis
- Final deliverable generation

```bash
./scripts/orchestrate.sh ink "Deliver notification system"
```

### Full Workflow: EMBRACE
Run all 4 phases sequentially with automatic context passing:

```bash
./scripts/orchestrate.sh embrace "Create a complete user dashboard feature"
```

## Smart Auto-Routing

The `auto` command detects intent keywords and routes to the appropriate workflow:

| Keywords | Routes To | Phases |
|----------|-----------|--------|
| research, explore, investigate, analyze | `probe` | Discover |
| develop, dev, build, implement, create | `tangle` + `ink` | Develop + Deliver |
| qa, test, review, validate, check | `ink` | Deliver (quality focus) |
| (other coding keywords) | `codex` agent | Single agent |
| (other design keywords) | `gemini` agent | Single agent |

**Examples:**
```bash
./scripts/orchestrate.sh auto "research best practices for caching"     # -> probe
./scripts/orchestrate.sh auto "build the caching layer"                 # -> tangle + ink
./scripts/orchestrate.sh auto "review the cache implementation"         # -> ink
./scripts/orchestrate.sh auto "fix the cache invalidation bug"          # -> codex
```

## Quality Gates

The `tangle` phase enforces quality gates:

| Score | Status | Behavior |
|-------|--------|----------|
| >= 90% | PASSED | Proceed to ink |
| 75-89% | WARNING | Proceed with caution |
| < 75% | FAILED | Ink phase flags for review |

## Prerequisites

Before installing Claude Octopus, ensure you have:

- [Claude Code](https://claude.ai/code) CLI installed
- Bash 4.0+ (macOS: `brew install bash`)
- Optional: `jq` for JSON task files (`brew install jq`)
- Optional: `coreutils` for timeout on macOS (`brew install coreutils`)

## Installation

### Via Plugin Marketplace (Recommended)

In Claude Code, run:

```
/plugin marketplace add nyldn/claude-octopus
/plugin install claude-octopus@nyldn-plugins
```

To update later:

```
/plugin marketplace update
```

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

### Keeping Up to Date

To update to the latest version:

```bash
# Navigate to plugin directory
cd ~/.claude/plugins/claude-octopus

# Pull latest changes
git pull origin main
```

Or ask Claude Code:

```
Update the claude-octopus plugin to the latest version
```

To update to a specific version:

```bash
cd ~/.claude/plugins/claude-octopus
git fetch --tags
git checkout v1.0.0  # Replace with desired version
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

### 3. Pre-flight Check

Verify all dependencies are configured:

```bash
./scripts/orchestrate.sh preflight
```

This checks for:
- Codex CLI installation
- Gemini CLI installation
- OPENAI_API_KEY environment variable
- GOOGLE_API_KEY environment variable

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

## Available Agents

| Agent | Model | Best For |
|-------|-------|----------|
| `codex` | GPT-5.1-Codex-Max | Complex code, deep refactoring (premium default) |
| `codex-standard` | GPT-5.2-Codex | Standard tier implementation |
| `codex-mini` | GPT-5.1-Codex-Mini | Quick fixes, simple tasks (cost-effective) |
| `codex-general` | GPT-5.2 | Non-coding agentic tasks |
| `gemini` | Gemini 3 Pro Preview | Deep analysis, 1M context |
| `gemini-fast` | Gemini 3 Flash Preview | Speed-critical tasks |
| `gemini-image` | Gemini 3 Pro Image Preview | Image generation (up to 4K) |
| `codex-review` | GPT-5.2-Codex | Code review mode |

## Command Reference

### Double Diamond Commands

| Command | Phase | Description |
|---------|-------|-------------|
| `probe <prompt>` | Discover | Parallel research with AI synthesis |
| `grasp <prompt>` | Define | Consensus building on problem definition |
| `tangle <prompt>` | Develop | Enhanced map-reduce with quality gates |
| `ink <prompt>` | Deliver | Validation and final delivery |
| `embrace <prompt>` | All 4 | Full Double Diamond workflow |
| `preflight` | - | Validate all dependencies |

### Classic Orchestration Commands

| Command | Description |
|---------|-------------|
| `init` | Initialize workspace |
| `spawn <agent> <prompt>` | Spawn single agent |
| `auto <prompt>` | Smart routing (Double Diamond or agent) |
| `fan-out <prompt>` | Send to multiple agents |
| `map-reduce <prompt>` | Decompose and parallelize |
| `parallel [tasks.json]` | Execute task file |
| `status` | Show running agents |
| `kill [id\|all]` | Terminate agents |
| `clean` | Reset workspace |
| `aggregate [filter]` | Combine results |

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `-p, --parallel` | 3 | Max concurrent agents |
| `-t, --timeout` | 300 | Timeout per task (seconds) |
| `-v, --verbose` | false | Verbose logging |
| `-n, --dry-run` | false | Show without executing |
| `-d, --dir` | `$PWD` | Working directory |
| `--context <file>` | - | Context from previous phase |

## Workspace Structure

```
~/.claude-octopus/
├── results/
│   ├── probe-synthesis-*.md      # Research findings
│   ├── grasp-consensus-*.md      # Problem definitions
│   ├── tangle-validation-*.md    # Quality gate reports
│   └── delivery-*.md             # Final deliverables
├── logs/                         # Execution logs
├── plans/                        # Execution plan history
└── .gitignore
```

Override with: `CLAUDE_OCTOPUS_WORKSPACE=/custom/path`

## Example Workflows

### Research-First Development

```bash
# 1. Explore the problem space
./scripts/orchestrate.sh probe "Authentication patterns for microservices"

# 2. Define the approach (with probe context)
./scripts/orchestrate.sh grasp "OAuth2 with JWT for our API" \
  --context ~/.claude-octopus/results/probe-synthesis-*.md

# 3. Implement with validation
./scripts/orchestrate.sh tangle "Implement OAuth2 authentication"

# 4. Deliver with quality checks
./scripts/orchestrate.sh ink "Finalize auth implementation"
```

### Quick Build (Auto-Routed)

```bash
# Auto-detects "build" intent -> runs tangle + ink
./scripts/orchestrate.sh auto "build a rate limiting middleware"
```

### Full Feature Development

```bash
# All 4 phases in one command
./scripts/orchestrate.sh embrace "Create a user notification system with email and push support"
```

### Security Audit (Fan-Out)

```bash
./scripts/orchestrate.sh fan-out "Perform security audit focusing on: authentication, input validation, and SQL injection vulnerabilities"
```

### Large Refactoring (Map-Reduce)

```bash
./scripts/orchestrate.sh map-reduce "Refactor all React class components to functional components with hooks"
```

## Troubleshooting

### Pre-flight check fails

```bash
./scripts/orchestrate.sh preflight
# Verify: codex CLI, gemini CLI, OPENAI_API_KEY, GOOGLE_API_KEY
```

### Quality gate failures

Tangle phase requires 75% success rate. If failing:
- Break task into smaller subtasks
- Increase timeout with `-t 600`
- Check individual agent logs in `~/.claude-octopus/logs/`

*Getting 75% of tentacles to agree is actually impressive coordination. Even real octopuses struggle with that.* 🐙

### Agents not responding

```bash
./scripts/orchestrate.sh kill all
./scripts/orchestrate.sh clean
```

*Sometimes tentacles need a rest. A clean reset untangles everything.* 🐙

### Timeout issues

Increase timeout for complex tasks:

```bash
./scripts/orchestrate.sh -t 600 auto "Complex task..."
```

*Even octopuses can't rush perfection. Give those tentacles time to work.* 🐙

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

### Reset workspace

```bash
./scripts/orchestrate.sh clean
./scripts/orchestrate.sh init
```

## Python Coordinator (Advanced)

For more sophisticated task coordination with async execution:

```bash
# Initialize
python3 ./scripts/coordinator.py init

# Double Diamond commands
python3 ./scripts/coordinator.py probe "Research prompt"
python3 ./scripts/coordinator.py grasp "Define prompt"
python3 ./scripts/coordinator.py tangle "Develop prompt"
python3 ./scripts/coordinator.py ink "Deliver prompt"
python3 ./scripts/coordinator.py embrace "Full workflow prompt"

# Pre-flight check
python3 ./scripts/coordinator.py preflight

# Classic commands
python3 ./scripts/coordinator.py auto "Your prompt here"
python3 ./scripts/coordinator.py fan-out "Analyze this code"
python3 ./scripts/coordinator.py map-reduce -p 4 -t 600 "Large refactoring task"
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

## The Octopus Philosophy

🐙 **Why an octopus?**

Real octopuses are nature's parallel processing masters:

| Octopus Trait | Claude Octopus Feature |
|---------------|----------------------|
| 8 independent arms | Multiple agents working in parallel |
| Distributed brain (neurons in each arm) | Intelligence at every endpoint |
| Ink cloud defense | Quality deliverables that make an impression |
| Master of camouflage | Adapts to any task type seamlessly |
| Opens jars, solves puzzles | Opens codebases, solves problems |
| Squeezes through tiny spaces | Fits into any workflow |

*Fun fact: Octopuses have been observed using tools, planning multi-step strategies,
and even escaping from sealed containers. Our orchestrator does the same, but digitally
(and with fewer suction cups).*

## Acknowledgments

- [Claude Code](https://claude.ai/code) - Anthropic's CLI for Claude
- [Codex CLI](https://github.com/openai/codex) - OpenAI's coding assistant
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) - Google's Gemini CLI
- [Double Diamond](https://www.designcouncil.org.uk/our-resources/framework-for-innovation/) - Design Council's framework for innovation

---

<p align="center">
  🐙 Made with eight tentacles of love 🐙<br/>
  <i>All arms working in perfect parallel harmony</i><br/>
  <a href="https://github.com/nyldn">nyldn</a>
</p>
