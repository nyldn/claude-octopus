<p align="center">
  <img src="assets/social-preview.jpg" alt="Claude Octopus - Multi-tentacled orchestrator for Claude Code" width="640">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Claude_Code-Plugin-blueviolet" alt="Claude Code Plugin">
  <img src="https://img.shields.io/badge/Double_Diamond-Design_Thinking-orange" alt="Double Diamond">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
  <img src="https://img.shields.io/badge/Version-7.9.2-blue" alt="Version 7.10.0">
</p>

# Claude Octopus

**Multi-AI orchestrator for Claude Code** - coordinates Codex, Gemini, and Claude CLIs using Double Diamond methodology.

> *Why have one AI do the work when you can have eight squabble about it productively?* 🐙

## TL;DR

| What It Does | How |
|--------------|-----|
| **Parallel AI execution** | Run multiple AI models simultaneously |
| **Structured workflows** | Double Diamond: Research → Define → Develop → Deliver |
| **Quality gates** | 75% consensus threshold before delivery |
| **Smart routing** | Auto-detects intent and picks the right AI model |
| **AI Debate Hub** | Structured 3-way debates (Claude + Gemini + Codex) |
| **Adversarial review** | AI vs AI debate catches more bugs |
| **Context-aware** | Auto-detects Dev vs Knowledge context for smarter workflows 🆕 |

**How to use it:**

Use the **"octo" prefix** for reliable multi-AI workflows, or slash commands:

- 💬 `octo research OAuth authentication patterns` - Multi-AI research
- 💬 `octo build a user authentication system` - Multi-AI implementation
- 💬 `octo review this code for security` - Multi-AI validation
- 💬 `octo debate Redis vs Memcached` - Three-way AI debate

---

## Quick Start

Get started with Claude Octopus in 2 simple steps:

### Step 1: Install the Plugin

Open Claude Code and run these two commands in the chat:

```
/plugin marketplace add https://github.com/nyldn/claude-octopus
/plugin install octo@nyldn-plugins
```

The plugin is now installed and automatically enabled.

<details>
<summary>Troubleshooting Installation</summary>

**If you get "SSH authentication failed":**

Use the HTTPS URL format (already shown above). The shorthand `nyldn/claude-octopus` requires SSH keys configured with GitHub.

**If `/octo:setup` shows "Unknown skill" in Step 2:**

1. Verify the plugin is installed:
   ```
   /plugin list
   ```
   Look for `octo@nyldn-plugins` in the installed plugins list.

2. Try reinstalling:
   ```
   /plugin uninstall octo
   /plugin install octo@nyldn-plugins
   ```

3. Check for errors in debug logs (from terminal):
   ```bash
   tail -100 ~/.claude/debug/*.txt | grep -i "octo\|error"
   ```

4. Make sure you're on Claude Code v2.1.10 or later (from terminal):
   ```bash
   claude --version
   ```

</details>

### Step 2: Configure Your AI Providers

Run the setup command in Claude Code:
```
/octo:setup
```

This will:
- Auto-detect what's already installed
- Show you exactly what you need (you only need ONE provider!)
- Give you shell-specific instructions
- Verify your setup when done

**No terminal context switching needed** - Claude guides you through everything!

### Step 3: Start Using It

Use the **"octo" prefix** for reliable workflow activation:

**For research:**
> `octo research microservices patterns and compare their trade-offs`

**For development:**
> `octo build a REST API for user management with authentication`

**For code review:**
> `octo review my authentication code for security issues`

**For debates:**
> `octo debate whether we should use GraphQL or REST for our API`

**Alternative: Slash commands** (always work reliably):
```
/octo:research microservices patterns
/octo:develop REST API for user management
/octo:review authentication code
/octo:debate GraphQL vs REST
```

Claude Octopus automatically detects which providers you have and uses them intelligently.

---

## Updating the Plugin

To get the latest version of Claude Octopus:

### Option A: Via Plugin UI
1. `/plugin` to open plugin screen
2. Navigate to "Installed" tab
3. Find `octo@nyldn-plugins`
4. Click update button if available

### Option B: Reinstall Manually
```
/plugin uninstall octo
/plugin install octo@nyldn-plugins
```

### Option C: Pin to Specific Version (Claude Code 2.1.14+)
Lock to a specific git commit SHA for stability:
```
/plugin install octo@nyldn-plugins#<commit-sha>
```

Example:
```
/plugin install octo@nyldn-plugins#abc123def
```

This is useful during active development or when you need to reproduce a specific behavior.

**After updating:** Restart Claude Code to load the new version.

---

## Which Tentacle Does What?

Claude Octopus has different "tentacles" (workflows) for different tasks:

| Tentacle | When to Use | What It Does | Example |
|----------|-------------|--------------|---------|
| **🔍 Discover** (probe) | Research, explore, investigate | Multi-AI research and discovery | `octo research OAuth 2.0 patterns` |
| **🎯 Define** (grasp) | Define, clarify, scope | Requirements and problem definition | `octo define requirements for auth` |
| **🛠️ Develop** (tangle) | Build, implement, create | Multi-AI implementation approaches | `octo build user authentication` |
| **✅ Deliver** (ink) | Review, validate, audit | Quality assurance and validation | `octo review auth code for security` |
| **🐙 Debate** | Debate, discuss, deliberate | Structured 3-way AI debates | `octo debate Redis vs Memcached` |
| **🐙 Embrace** | Complete feature lifecycle | Full 4-phase Double Diamond workflow | `/octo:embrace authentication system` |

**Use "octo" prefix or `/octo:` commands for reliable activation!**

---

## ✨ What's New

### v7.9.2 - Plugin Rename
- **Plugin renamed**: `claude-octopus` → `octo`
- **Commands now work as documented**: `/octo:research`, `/octo:debate`, etc.
- **Migration**: Uninstall old plugin, install new: `/plugin install octo@nyldn-plugins`

### v7.9.x
- Single-provider mode (only need Codex OR Gemini)
- Fixed path resolution in skill files
- Optimized skill descriptions for Claude Code discovery

### Context-Aware Detection (v7.8.0)

Claude Octopus **auto-detects** Dev vs Knowledge context:

| Aspect | Dev Context 🔧 | Knowledge Context 🎓 |
|--------|---------------|---------------------|
| **Research Focus** | Libraries, patterns, implementation | Market, competitive, strategic |
| **Build Output** | Code, tests, APIs | PRDs, presentations, reports |
| **Review Focus** | Security, performance, quality | Clarity, evidence, completeness |

Override with: `/octo:km on` (Knowledge) | `/octo:km off` (Dev) | `/octo:km auto`

📖 **[Full Changelog →](CHANGELOG.md)** - See all version history

---

## Companion Skills

Claude Octopus includes 20+ battle-tested skills organized by category:

### Code Quality
| Skill | Command | Description |
|-------|---------|-------------|
| **Code Review** | `/octo:review` | Comprehensive code quality analysis |
| **Quick Review** | - | Fast pre-commit checks |
| **Security Audit** | `/octo:security` | OWASP compliance and vulnerability detection |
| **Adversarial Security** | - | Red team security testing |

### Development Discipline
| Skill | Command | Description |
|-------|---------|-------------|
| **TDD** | `/octo:tdd` | Test-driven development (red-green-refactor) |
| **Debugging** | `/octo:debug` | Systematic 4-phase bug investigation |
| **Verification** | - | Pre-completion validation ("Iron Law") |
| **Iterative Loop** | - | Loop until exit criteria pass |

### Planning & Architecture
| Skill | Command | Description |
|-------|---------|-------------|
| **Architecture** | - | System design and technical decisions |
| **PRD Writing** | `/octo:prd` | AI-optimized PRD with 100-point scoring |
| **Writing Plans** | - | Zero-context implementation plans |
| **Decision Support** | - | Present options with trade-offs |

### Research & Knowledge
| Skill | Command | Description |
|-------|---------|-------------|
| **Deep Research** | `/octo:research` | Multi-source research synthesis |
| **AI Debate** | `/octo:debate` | Structured 3-way AI debates |
| **Knowledge Work** | `/octo:km` | Toggle Dev/Knowledge context |

### Workflow & Delivery
| Skill | Command | Description |
|-------|---------|-------------|
| **Task Management** | - | Todo orchestration and resumption |
| **Finish Branch** | - | Post-implementation: verify → merge/PR |
| **Doc Delivery** | `/octo:docs` | Export to DOCX, PPTX, PDF |
| **Visual Feedback** | - | Process UI/UX screenshot feedback |
| **Audit** | - | Systematic codebase checking |

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
- 🔴 Codex CLI: OpenAI API costs (GPT-5.x based)
- 🟡 Gemini CLI: Google AI costs (Gemini 3.0)
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


## Claude Code 2.1.14+ Features

Claude Octopus leverages the latest Claude Code capabilities:

### Bash History Autocomplete
Type `!` followed by a partial command and press Tab to complete from your bash history:
```bash
!octo<Tab>  # Completes to previous orchestrate.sh commands
```

### Wildcard Bash Permissions
Pre-approve commands with wildcard patterns in your settings:
```json
{
  "permissions": {
    "allow": [
      "Bash(./scripts/orchestrate.sh *)",
      "Bash(npm *)",
      "Bash(git * main)"
    ]
  }
}
```

### Session-Aware Workflows
All Claude Octopus workflows now display the session ID in visual banners for better debugging and cross-session correlation:
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 [Dev] Discover Phase: Technical research on caching patterns
📋 Session: ses_abc123xyz
```

### Memory-Optimized Skills
Heavy skills (PRD, debates, code review) now run in forked contexts to prevent conversation bloat.

---

## Documentation

### User Guides
- **[Visual Indicators Guide](docs/VISUAL-INDICATORS.md)** - Understanding what's running
- **[Triggers Guide](docs/TRIGGERS.md)** - What activates each workflow
- **[Command Reference](docs/COMMAND-REFERENCE.md)** - All available commands
- **[CLI Reference](docs/CLI-REFERENCE.md)** - Direct CLI usage (advanced)

### Developer Guides
- **[Architecture Guide](docs/ARCHITECTURE.md)** - Models, providers, and execution flow
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
/octo:km on
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
