<p align="center">
  <img src="assets/social-preview.jpg" alt="Claude Octopus - Multi-tentacled orchestrator for Claude Code" width="640">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Claude_Code-Plugin-blueviolet" alt="Claude Code Plugin">
  <img src="https://img.shields.io/badge/Double_Diamond-Design_Thinking-orange" alt="Double Diamond">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
  <img src="https://img.shields.io/badge/Version-7.6.3-blue" alt="Version 7.6.3">
</p>

# Claude Octopus

**Multi-AI orchestrator for Claude Code** - coordinates Codex, Gemini, and Claude CLIs using Double Diamond methodology.

> *Why have one AI do the work when you can have eight squabble about it productively?* 🐙

## TL;DR

| What It Does | How |
|--------------|-----|
| **Visual feedback** | Know when external CLIs run (🐙 🔴 🟡) vs built-in (🔵) 🆕 |
| **Natural language workflows** | "research X" → discover, "build X" → develop, "review X" → deliver 🆕 |
| **Parallel AI execution** | Run multiple AI models simultaneously |
| **Structured workflows** | Double Diamond: Research → Define → Develop → Deliver |
| **Quality gates** | 75% consensus threshold before delivery |
| **Smart routing** | Auto-detects intent and picks the right AI model |
| **AI Debate Hub** | Structured 3-way debates (Claude + Gemini + Codex) |
| **Adversarial review** | AI vs AI debate catches more bugs |
| **Two work modes** | Dev mode (code) or Knowledge mode (research/UX/strategy) |

**How to use it:**

Just talk to Claude naturally! Claude Octopus automatically activates when you need multi-AI collaboration:

- 💬 "Research OAuth authentication patterns and summarize the best approaches"
- 💬 "Build a user authentication system"
- 💬 "Review this code for security vulnerabilities"
- 💬 "Run a debate about whether we should use Redis or Memcached"

Claude coordinates multiple AI models behind the scenes to give you comprehensive, validated results.

---

## Quick Start

Get started with Claude Octopus in 2 simple steps:

### Step 1: Install the Plugin

Open Claude Code and run these two commands in the chat:

```
/plugin marketplace add nyldn/claude-octopus
/plugin install claude-octopus@nyldn-plugins
```

The plugin is now installed and automatically enabled.

<details>
<summary>Troubleshooting Installation</summary>

**If `/co:setup` shows "Unknown skill" in Step 2:**

1. Verify the plugin is installed:
   ```
   /plugin list
   ```
   Look for `claude-octopus@nyldn-plugins` in the installed plugins list.

2. Try reinstalling:
   ```
   /plugin uninstall claude-octopus
   /plugin marketplace update nyldn-plugins
   /plugin install claude-octopus@nyldn-plugins
   ```

3. Check for errors in debug logs (from terminal):
   ```bash
   tail -100 ~/.claude/debug/*.txt | grep -i "claude-octopus\|error"
   ```

4. Make sure you're on Claude Code v2.1.10 or later (from terminal):
   ```bash
   claude --version
   ```

</details>

### Step 2: Configure Your AI Providers

Run the setup command in Claude Code:
```
/co:setup
```

This will:
- Auto-detect what's already installed
- Show you exactly what you need (you only need ONE provider!)
- Give you shell-specific instructions
- Verify your setup when done

**No terminal context switching needed** - Claude guides you through everything!

### Step 3: Start Using It

Just talk to Claude naturally! Claude Octopus automatically activates when you need multi-AI collaboration:

**For research:**
> "Research microservices patterns and compare their trade-offs"

**For development:**
> "Build a REST API for user management with authentication"

**For code review:**
> "Review my authentication code for security issues"

**For debates:**
> "Run a debate about whether we should use GraphQL or REST for our API"

Claude Octopus automatically detects which providers you have and uses them intelligently.

---

## Updating the Plugin

To get the latest version of Claude Octopus:

### Option A: Auto-Update (Easiest) 🆕
```
/co:update --update
```
This will automatically check for updates and install the latest version if available.

### Option B: Via Plugin UI
1. `/plugin` to open plugin screen
2. Navigate to "Installed" tab
3. Find `claude-octopus@nyldn-plugins`
4. Click update button if available

### Option C: Reinstall Manually
```
/plugin uninstall claude-octopus
/plugin marketplace update nyldn-plugins
/plugin install claude-octopus@nyldn-plugins
```

**After updating:** Restart Claude Code to load the new version.

---

## 🆕 What's New in v7.6 - Shorter Commands & Skill Discovery

**60% shorter commands!** v7.6 changes the namespace from `/claude-octopus:` to `/co:` and adds 11 new skill commands.

### All Available Commands (18 total)

All commands use the `/co:` namespace and appear in autocomplete:

**System Commands** (7):
| Command | Description |
|---------|-------------|
| `/co:setup` | Check setup status (shortcut for sys-setup) |
| `/co:update` | Check for updates (shortcut for sys-update) |
| `/co:dev` | Switch to Dev Work mode |
| `/co:km` | Toggle between Dev Work and Knowledge Work modes |
| `/co:sys-setup` | Full name: Check Claude Octopus setup |
| `/co:sys-update` | Full name: Check for plugin updates |
| `/co:check-update` | Alias for sys-update |

**Skill Commands** (12) - 🆕 New in v7.7:
| Command | Description |
|---------|-------------|
| `/co:debate` | AI Debate Hub - Structured three-way debates |
| `/co:review` | Expert code review with quality assessment |
| `/co:research` | Deep research with multi-source synthesis |
| `/co:security` | Security audit with OWASP compliance |
| `/co:debug` | Systematic debugging with investigation |
| `/co:tdd` | Test-driven development workflows |
| `/co:docs` | Document delivery (PPTX/DOCX/PDF export) |
| `/co:embrace` | Full Double Diamond workflow (all 4 phases) |
| `/co:discover` | Discovery phase (🔍 probe) |
| `/co:define` | Definition phase (🎯 grasp) |
| `/co:develop` | Development phase (🛠️ tangle) |
| `/co:deliver` | Delivery phase (✅ ink) |

### Major Changes in v7.6

- ✅ **Shorter namespace**: `/co:` instead of `/claude-octopus:` (60% shorter!)
- ✅ **Skills as commands**: All major skills now accessible via autocomplete
- ✅ **Better discoverability**: Type `/co:` and see everything
- ✅ **Natural language still works**: Commands are shortcuts, triggers remain active

### Quick Examples

```bash
/co:setup              # Check your configuration
/co:debate             # Start a multi-AI debate
/co:review             # Code review a file/module
/co:research           # Deep research on a topic
/co:security           # Security audit
/co:embrace            # Full 4-phase workflow
/co:discover           # Discovery phase research
```

📖 **[Migration Guide →](docs/MIGRATION-v7.5.md)**
📖 **[Command Reference →](docs/COMMAND-REFERENCE.md)**

---

## What's New in v7.4 - Visual Feedback & Natural Language Workflows

**Now you always know what's running!** v7.4 adds visual indicators and natural language workflow triggers.

### Visual Indicators

See exactly which AI is responding:

| Indicator | Meaning | Provider | Cost |
|-----------|---------|----------|------|
| 🐙 | **Parallel Mode** | Multiple CLIs orchestrated | Uses external APIs |
| 🔴 | **Codex CLI** | OpenAI Codex | Your OPENAI_API_KEY |
| 🟡 | **Gemini CLI** | Google Gemini | Your GEMINI_API_KEY |
| 🔵 | **Claude Subagent** | Claude Code Task tool | Included with Claude Code |

**Example:**
```
User: Research authentication best practices

Claude:
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 Discover Phase: Researching authentication patterns

Providers:
🔴 Codex CLI - Technical implementation analysis
🟡 Gemini CLI - Ecosystem and community research
🔵 Claude - Strategic synthesis

[Multi-provider research results...]
```

**Why this matters:** External CLIs cost money (your API quotas). Visual indicators help you understand costs.

📖 **[Complete Visual Indicators Guide →](docs/VISUAL-INDICATORS.md)**

### Natural Language Workflow Triggers

No more CLI commands! Just talk naturally:

| You Say | What Triggers | Indicator |
|---------|---------------|-----------|
| "research X" | Discover workflow | 🐙 🔍 |
| "define requirements for X" | Define workflow | 🐙 🎯 |
| "build X" | Develop workflow | 🐙 🛠️ |
| "review X" | Deliver workflow | 🐙 ✅ |
| "read file.ts" | Claude Read tool (no external CLIs) | (none) |

**Before v7.7:**
```bash
# Had to use CLI commands
./scripts/orchestrate.sh discover "research OAuth patterns"
./scripts/orchestrate.sh develop "implement auth system"
```

**v7.7+:**
```
# Just talk naturally
"Research OAuth authentication patterns"
"Build a user authentication system"
```

📖 **[Complete Triggers Guide →](docs/TRIGGERS.md)**

### What Else Changed

- ✅ Debate skill accessible via natural language ("run a debate about X")
- ✅ Hook-based visual indicators (PreToolUse hooks)
- ✅ Four workflow skills (discover, define, develop, deliver) with natural language triggers
- ✅ Enhanced parallel-agents.md with visual indicators section
- ✅ Comprehensive documentation (VISUAL-INDICATORS.md, TRIGGERS.md)

---

## ✨ What's New in v7.6 - Two-Mode System

**Choose your work mode!** Claude Octopus now has two equal modes optimized for different tasks. Both use the same AI providers (Codex + Gemini) but with different personas.

### Quick Toggle
Switch modes instantly in Claude Code:
```
/co:dev        # Switch to Dev Work mode (default)
/co:km on      # Switch to Knowledge Work mode
/co:km         # Check current status
```

### Natural Language
Or just tell me:
- "Switch to dev mode"
- "Switch to knowledge mode"
- "What mode am I in?"

I'll detect and switch automatically! ✨

### What Changes
| Aspect | Dev Mode 🔧 | Knowledge Mode 🎓 |
|--------|------------|-------------------|
| **Default Tasks** | Code, test, debug | Research, strategy, UX |
| **Debate Style** | Technical (code-focused) | Strategic (business-focused) |
| **Document Export** | Code docs, API specs | Reports, presentations, proposals |
| **Quality Gates** | Security, performance | Insight depth, evidence quality |

---

## Which Tentacle Does What?

Claude Octopus has different "tentacles" (workflows) for different tasks:

| Tentacle | When to Use | What It Does | Example |
|----------|-------------|--------------|---------|
| **🔍 Discover** (probe) | Research, explore, investigate | Multi-AI research and discovery | "Research OAuth 2.0 patterns" |
| **🎯 Define** (grasp) | Define, clarify, scope | Requirements and problem definition | "Define requirements for auth system" |
| **🛠️ Develop** (tangle) | Build, implement, create | Multi-AI implementation approaches | "Build user authentication" |
| **✅ Deliver** (ink) | Review, validate, audit | Quality assurance and validation | "Review auth code for security" |
| **🐙 Debate** | Debate, discuss, deliberate | Structured 3-way AI debates | "Run a debate about Redis vs Memcached" |
| **🐙 Embrace** | Complete feature lifecycle | Full 4-phase Double Diamond workflow | "Build a complete authentication system" |

**Natural language automatically activates the right tentacle!**

---

## Companion Skills

Claude Octopus includes battle-tested skills for code quality:

- **🏗️ Architecture** - System design and technical decisions
- **🔍 Code Review** - Comprehensive code quality analysis
- **🔒 Security Audit** - OWASP compliance and vulnerability detection
- **⚡ Quick Review** - Fast pre-commit checks
- **🔬 Deep Research** - Multi-source research synthesis
- **🛡️ Adversarial Security** - Red team security testing
- **🎯 Systematic Debugging** - Methodical bug investigation
- **✅ TDD** - Test-driven development workflows
- **🎯 Verification** - Pre-completion validation checklist

---

## Workflow Skills (Updated in v7.7)

Natural language workflow wrappers for the Double Diamond methodology:

- **discover-workflow.md** (probe) - "research X" → Multi-AI research
- **define-workflow.md** (grasp) - "define requirements for X" → Problem definition
- **develop-workflow.md** (tangle) - "build X" → Implementation with quality gates
- **deliver-workflow.md** (ink) - "review X" → Validation and quality assurance
- **embrace** - "build complete X" → Full 4-phase workflow

These make orchestrate.sh workflows accessible through natural conversation!

---

## Understanding Costs

**External CLIs use your API quotas:**
- 🔴 Codex CLI: OpenAI API costs (GPT-4 based)
- 🟡 Gemini CLI: Google AI costs (Gemini Pro)
- Typical costs: $0.01-0.10 per query

**Claude subagents are included:**
- 🔵 Claude Code Task tool: No additional cost
- Included with your Claude Code subscription

**When to use external CLIs (🐙):**
- Need multiple perspectives on a problem
- Research requires broad coverage
- Complex implementation needs different approaches
- Security review benefits from adversarial analysis
- High-stakes decisions

**When to use Claude only (no indicator):**
- Simple file operations
- Single perspective adequate
- Quick edits or fixes
- Cost efficiency important
- Straightforward tasks

📖 **[Visual Indicators Guide](docs/VISUAL-INDICATORS.md)** - Complete cost breakdown

---

## Why Claude Octopus?

| What Others Do | What We Do |
|----------------|------------|
| Single-agent execution | 8 agents working simultaneously |
| Hope for the best | Quality gates with 75% consensus |
| One model, one price | Cost-aware routing to cheaper models |
| Ad-hoc workflows | Double Diamond methodology baked in |
| Single perspective | Adversarial AI-vs-AI review |
| Guess what's running | Visual indicators (🐙 🔴 🟡 🔵) |
| CLI commands only | Natural language triggers workflows |

---

## Documentation

### User Guides
- **[Visual Indicators Guide](docs/VISUAL-INDICATORS.md)** - Understanding what's running
- **[Triggers Guide](docs/TRIGGERS.md)** - What activates each workflow
- **[CLI Reference](docs/CLI-REFERENCE.md)** - Direct CLI usage (advanced)

### Developer Guides
- **[Plugin Architecture](docs/PLUGIN-ARCHITECTURE.md)** - How it all works
- **[Contributing Guidelines](CONTRIBUTING.md)** - How to contribute

---

## 🙏 Attribution & Open Source Collaboration

### AI Debate Hub Integration

> **Built on the shoulders of giants** 🤝

Claude-octopus integrates **[AI Debate Hub](https://github.com/wolverin0/claude-skills)** by **[wolverin0](https://github.com/wolverin0)** with deep gratitude and proper attribution:

- **Original Repository**: https://github.com/wolverin0/claude-skills
- **Author**: wolverin0
- **License**: MIT
- **Integration Type**: Git submodule (read-only reference)
- **Version**: v4.7

**What it does**: Enables structured three-way debates where Claude, Gemini CLI, and Codex CLI analyze problems from multiple perspectives. Claude actively participates as both a debater and moderator.

**Claude-octopus enhancements**:
- ✅ Session-aware storage (integrates with Claude Code sessions)
- ✅ Quality gates for debate responses (75% threshold)
- ✅ Cost tracking and analytics
- ✅ Document export to PPTX/DOCX/PDF (via document-delivery skill)
- ✅ Knowledge mode deliberation workflow

**Usage**:

Just use natural language to trigger debates:

```bash
# Basic debate
"Run a debate about whether we should use Redis or in-memory cache"

# Thorough analysis
"I want Gemini and Codex to review our API architecture with thorough analysis"

# Adversarial security review
"Run a debate about security vulnerabilities in auth.ts with adversarial analysis"

# Knowledge mode deliberation
/co:km on
"Debate whether we should enter the European market"
```

**Initialize submodule** (if not auto-initialized):
```bash
git submodule update --init --recursive
```

**Update to latest** from wolverin0:
```bash
git submodule update --remote .dependencies/claude-skills
```

**Contributing**: Generic improvements to the debate functionality should be contributed to [wolverin0/claude-skills](https://github.com/wolverin0/claude-skills) via pull requests. Claude-octopus-specific integrations remain in this repository.

---

## Acknowledgments

Claude Octopus stands on the shoulders of giants:

- **[wolverin0/claude-skills](https://github.com/wolverin0/claude-skills)** by **wolverin0** - AI Debate Hub enables structured three-way debates between Claude, Gemini CLI, and Codex CLI. Integrated as a git submodule with claude-octopus enhancements (quality gates, cost tracking, document export). wolverin0's innovative "Claude as participant" design pattern is brilliant—Claude doesn't just orchestrate, it actively debates. This integration demonstrates proper open-source collaboration: clear attribution, hybrid approach (original + enhancement layer), and a path to contribute improvements back upstream. MIT License.

- **[obra/superpowers](https://github.com/obra/superpowers)** by **Jesse Vincent** - Several discipline skills (TDD, systematic debugging, verification, planning, branch finishing) were inspired by the excellent patterns in this Claude Code skills library. The "Iron Law" enforcement approach and anti-rationalization techniques are particularly valuable. MIT License.

- **Double Diamond** methodology by the [UK Design Council](https://www.designcouncil.org.uk/our-resources/the-double-diamond/) - The Discover/Define/Develop/Deliver workflow structure (with playful aliases probe/grasp/tangle/ink) provides a proven framework for divergent and convergent thinking in design and development.

---

## Contributing

We believe in giving back to the open source community. Here's how you can contribute:

### To Claude-Octopus

1. **Report Issues**: Found a bug? [Open an issue](https://github.com/nyldn/claude-octopus/issues)
2. **Suggest Features**: Have an idea? We'd love to hear it!
3. **Submit PRs**: Improvements welcome—please follow the existing code style
4. **Share Knowledge**: Write about your experience using claude-octopus

### To Upstream Dependencies

When improving claude-octopus, consider whether enhancements benefit the broader community:

**AI Debate Hub (wolverin0/claude-skills)**
- Generic improvements to debate functionality → Submit to [wolverin0/claude-skills](https://github.com/wolverin0/claude-skills)
- Claude-octopus-specific integrations → Keep in this repo
- Examples: Atomic state writes, retry logic, error messages

**Superpowers (obra/superpowers)**
- Improvements to discipline skills → Submit to [obra/superpowers](https://github.com/obra/superpowers)
- Claude-octopus-specific workflows → Keep in this repo

### Contribution Principles

✅ **Do**:
- Maintain clear attribution
- Test thoroughly (95%+ coverage standard)
- Follow existing patterns
- Document your changes
- Consider backward compatibility

❌ **Don't**:
- Break existing workflows
- Remove attribution
- Skip tests
- Introduce unnecessary complexity

### Development Setup

```bash
# Clone with submodules
git clone --recursive https://github.com/nyldn/claude-octopus.git
cd claude-octopus

# Or initialize submodules after cloning
git submodule update --init --recursive

# Run tests
make test

# Run specific test suite
make test-unit
make test-integration
make test-e2e
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

---

## License

MIT License - see [LICENSE](LICENSE)

<p align="center">
  🐙 Made with eight tentacles of love 🐙<br/>
  <a href="https://github.com/nyldn">nyldn</a>
</p>
