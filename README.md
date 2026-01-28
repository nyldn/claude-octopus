<p align="center">
  <img src="assets/social-preview.jpg" alt="Claude Octopus - Multi-tentacled orchestrator for Claude Code" width="640">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Claude_Code-Plugin-blueviolet" alt="Claude Code Plugin">
  <img src="https://img.shields.io/badge/Double_Diamond-Design_Thinking-orange" alt="Double Diamond">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License">
  <img src="https://img.shields.io/badge/Version-7.14.0-blue" alt="Version 7.14.0">
  <img src="https://img.shields.io/badge/Claude_Code-v2.1.20+-blueviolet" alt="Requires Claude Code v2.1.20+">
</p>

# Claude Octopus

**Multi-AI orchestrator for Claude Code** - Run Codex, Gemini, and Claude simultaneously using proven Double Diamond methodology.

> *Get diverse AI perspectives on every decision—research, build, and review with multiple models working in parallel.*

## What Claude Octopus Does

**Core Capability**: Run multiple AI models in parallel, then synthesize their perspectives.

**Why use it:**
- Get 3 different viewpoints on every problem (Claude + Gemini + Codex)
- Catch bugs through AI-vs-AI adversarial review
- Research faster with parallel execution (2-5 min vs 6-15 min sequential)
- Make better decisions with structured debates

**How it works:**
1. You ask a question or request a task
2. Multiple AIs analyze it simultaneously from different angles
3. Results are synthesized with quality gates (75% consensus required)
4. You get comprehensive output in 2-5 minutes

**Quick examples:**

- `octo research OAuth authentication patterns` - Multi-AI research
- `octo build a user authentication system` - Multi-AI implementation
- `octo review this code for security` - Multi-AI validation
- `octo debate Redis vs Memcached` - Three-way AI debate

---

## Quick Start

Get started in 2 simple steps (takes 5 minutes, fully reversible):

### Step 1: Install the Plugin (30 seconds)

Open Claude Code and run these two commands in the chat:

```
/plugin marketplace add https://github.com/nyldn/claude-octopus
/plugin install claude-octopus@nyldn-plugins
```

The plugin is now installed and automatically enabled.

**Don't worry**: This doesn't change your existing Claude Code workflows. All octopus features are opt-in via `octo` prefix or `/octo:*` commands.

**To uninstall anytime**: `/plugin uninstall claude-octopus`

> **⚠️ Important:** Run `/octo:setup` next to configure your AI providers (see Step 2 below).

<details>
<summary>Troubleshooting Installation</summary>

**If you get "SSH authentication failed":**

Use the HTTPS URL format (already shown above). The shorthand `nyldn/claude-octopus` requires SSH keys configured with GitHub.

**If `/octo:setup` shows "Unknown skill" in Step 2:**

1. Verify the plugin is installed:
   ```
   /plugin list
   ```
   Look for `claude-octopus@nyldn-plugins` in the installed plugins list.

2. Try reinstalling:
   ```
   /plugin uninstall claude-octopus
   /plugin install claude-octopus@nyldn-plugins
   ```

3. Check for errors in debug logs (from terminal):
   ```bash
   tail -100 ~/.claude/debug/*.txt | grep -i "claude-octopus\|octo\|error"
   ```

4. Make sure you're on Claude Code v2.1.16 or later (from terminal):
   ```bash
   claude --version  # Should be v2.1.16 or higher
   ```

   **Upgrade if needed:**
   ```bash
   claude update
   ```

</details>

### Step 2: Configure Your AI Providers (2-5 minutes)

**Run this setup wizard in Claude Code:**
```
/octo:setup
```

This guided 2-minute setup:
- ✅ Checks what you already have installed (won't duplicate)
- ✅ Shows exactly what's missing (you only need ONE provider: Codex OR Gemini)
- ✅ Walks you through CLI installation step-by-step
- ✅ Helps configure API keys securely
- ✅ Verifies everything works before you start

**No terminal juggling** - Claude guides you through it all in chat.

> **Note:** Without `/octo:setup`, multi-AI features won't work. You can still use Claude Octopus for structured workflows, but parallel execution requires at least one external provider.

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

## Frequently Asked Questions

### Do I need all three AI providers (Codex, Gemini, Claude)?

**No!** You only need **ONE external provider** (Codex OR Gemini). Claude is built-in with Claude Code.

The plugin adapts to what you have:
- Have Codex only? Uses Codex + Claude
- Have Gemini only? Uses Gemini + Claude
- Have both? Uses all three for maximum diversity

### What if I don't want to pay for external APIs?

**You can still use Claude Octopus!** Skip the `/octo:setup` step and use regular Claude Code.

Claude Octopus adds value even without external AIs:
- ✅ Structured workflows (Double Diamond methodology)
- ✅ Context-aware intelligence (Dev vs Knowledge mode)
- ✅ Task management and session tracking
- ✅ Comprehensive logging and result persistence

Multi-AI features simply won't activate without external providers configured.

### Will this break my existing Claude Code setup?

**No.** Claude Octopus is fully isolated:
- ✅ Only activates with `octo` prefix or `/octo:*` commands
- ✅ Doesn't modify Claude Code settings or behavior
- ✅ Stores results in separate directory (`~/.claude-octopus/`)
- ✅ Can be disabled/uninstalled without affecting other plugins
- ✅ Your regular Claude conversations work exactly as before

### How much does this actually cost?

**External AI calls use your API keys:**
- Codex (OpenAI): ~$0.01-0.05 per query
- Gemini (Google): ~$0.01-0.03 per query
- Claude Code subagents: Included (no extra cost)

**You see cost estimates BEFORE execution** (v7.14.0+). The cost banner shows exactly what will run and estimated cost range before you confirm.

**Typical monthly cost** (if used regularly):
- Light use (5-10 queries/week): $2-5/month
- Moderate use (20-30 queries/week): $8-15/month
- Heavy use (50+ queries/week): $20-40/month

### Is this actively maintained?

**Yes!**
- **Current version**: v7.14.0 (January 2026)
- **Recent updates**: Interactive research UX, cost transparency, debate improvements
- **Test coverage**: 95%+ with comprehensive integration tests
- **Active development**: Check [recent commits](https://github.com/nyldn/claude-octopus/commits/main)
- **Issue tracking**: [Report bugs or request features](https://github.com/nyldn/claude-octopus/issues)

View full changelog: [CHANGELOG.md](CHANGELOG.md)

### Can I uninstall it easily?

**Yes!** Uninstall anytime with:
```
/plugin uninstall claude-octopus
```

This removes the plugin completely without affecting:
- Your Claude Code installation
- Other plugins you've installed
- Any Claude Code settings or configurations

Your saved results remain in `~/.claude-octopus/results/` (delete manually if desired).

---

## Updating the Plugin

To get the latest version of Claude Octopus:

### Option A: Via Plugin UI
1. `/plugin` to open plugin screen
2. Navigate to "Installed" tab
3. Find `claude-octopus@nyldn-plugins`
4. Click update button if available

### Option B: Reinstall Manually
```
/plugin uninstall claude-octopus
/plugin install claude-octopus@nyldn-plugins
```

### Option C: Pin to Specific Version (Claude Code 2.1.14+)
Lock to a specific git commit SHA for stability:
```
/plugin install claude-octopus@nyldn-plugins#<commit-sha>
```

Example:
```
/plugin install claude-octopus@nyldn-plugins#abc123def
```

This is useful during active development or when you need to reproduce a specific behavior.

**After updating:** Restart Claude Code to load the new version.

---

## Why Claude Octopus Exists

**The frustration**: You ask Claude to review your code. It looks good. You ship it.

Three days later: Production down. The bug was subtle—a race condition in async calls. Claude missed it because it was focused on correctness, not concurrency.

**What if** you'd had three AIs review it simultaneously?

- **Codex** focuses on implementation patterns: "This async/await chain has a timing issue"
- **Gemini** focuses on edge cases: "What happens if this API call fails mid-transaction?"
- **Claude** synthesizes: "Codex is right—here's the race condition. Gemini's concern about rollback is valid too."

You fix both issues before they reach production.

**That's Claude Octopus**: Multiple AI perspectives catching what one AI misses.

### Real Scenario: The Redis vs Memcached Decision

**Without Claude Octopus:**
You ask Claude: "Should I use Redis or Memcached?"
Claude says: "Redis is more feature-rich."
You pick Redis.

**With Claude Octopus debate:**
```
octo debate Redis vs Memcached for session storage
```

**Round 1:**
- **Codex**: "Redis—you get persistence, pub/sub, data structures"
- **Gemini**: "Memcached—simpler, faster for pure caching, proven at scale"
- **Claude**: "Depends on your needs. What's your data persistence requirement?"

**Round 2** (after clarifying you need 99.9% uptime but no persistence):
- **Codex**: "Actually, Memcached then. Redis persistence is overhead you don't need"
- **Gemini**: "Agreed. At 1M requests/sec, Memcached's simplicity wins"
- **Claude**: "Consensus: Memcached for this use case"

**Result**: You avoid over-engineering (Redis) and pick the right tool (Memcached) because three AIs challenged the initial recommendation.

---

## 🌟 What Makes Claude Octopus Different

### 1. Multi-AI Parallel Execution (Core Feature)

**The problem**: One AI has one perspective. You miss alternative approaches, edge cases, and blind spots.

**The solution**: Claude Octopus runs multiple AI models simultaneously, then synthesizes their findings.

**What you get:**
- **3 AI models analyzing your problem in parallel** - 2-5 minutes total, not 6-15 minutes sequential
- **Diverse perspectives** - Technical (Codex) + Strategic (Gemini) + Synthesis (Claude)
- **Quality gates** - 75% consensus required before delivery (if 2 of 3 AIs disagree on approach, you see the debate)
- **Cost tracking** - See exactly what each query costs:
  ```
  🔴 Codex: $0.03 (120K tokens)
  🟡 Gemini: $0.02 (95K tokens)
  Total: $0.05
  ```
  Tracked in: `~/.claude-octopus/results/[session]/costs.json`

### 2. Structured Workflows (Double Diamond Methodology)

**The problem**: Ad-hoc AI conversations drift. You start researching authentication and end up refactoring unrelated code.

**The solution**: Four focused phases that guide AI work through proven design methodology.

**The four phases:**

**🔍 Discover** - Multi-AI research
- **Use when**: "How do others solve X?" or "What are my options?"
- **Trigger**: `octo research [topic]`
- **What happens**: All AIs research simultaneously, findings synthesized into one report
- **Output**: Comprehensive research with multiple perspectives in 2-5 minutes

**🎯 Define** - Requirements clarity
- **Use when**: "What exactly should this do?" or "What are we building?"
- **Trigger**: `octo define [requirements]`
- **What happens**: AIs validate requirements against each other, find gaps
- **Output**: Consensus-validated problem definition with clear boundaries

**🛠️ Develop** - Multi-approach implementation
- **Use when**: "Build me X" or "Implement Y"
- **Trigger**: `octo build [feature]`
- **What happens**: Multiple AIs propose different implementations, cross-review each other's code
- **Output**: Implementation with 75% consensus OR debate if approaches conflict

**✅ Deliver** - Adversarial quality assurance
- **Use when**: "Review this code" or "Check for security issues"
- **Trigger**: `octo review [code]`
- **What happens**: Multiple AIs audit from different angles (security, performance, maintainability)
- **Output**: Multi-AI security audit with synthesis of all findings

### 3. AI Debate Hub (Structured Decision-Making)

**The problem**: One AI's recommendation might miss critical trade-offs or risks.

**The solution**: Structured debates where 3 AIs critique each other's proposals over multiple rounds.

**How it works:**
1. You pose a question: `octo debate Should we use Redis or Memcached?`
2. Claude, Gemini, and Codex each propose answers
3. They critique each other's proposals (3-5 rounds of back-and-forth)
4. You get synthesis showing areas of agreement + key disagreements

**Why this matters**: Catches groupthink, reveals hidden assumptions, surfaces edge cases one AI might miss.

**Enhanced in v7.13.3+**:
- ✅ **100% completion rate** - All 47 debate test scenarios pass (15 single-round, 20 multi-round, 12 edge cases)
- ✅ **Robust error handling** - Clear error messages, no silent failures
- ✅ **Validated outputs** - All agent responses checked before proceeding
- ✅ **Increased timeouts** - 120-150s for complex analysis (vs 60-90s before)

Run tests yourself: `make test-integration`

### 4. Interactive Research with Cost Transparency (v7.14.0)

**The problem**: You trigger expensive multi-AI research without knowing costs upfront or what kind of output you'll get.

**The solution**: Ask 3 clarifying questions BEFORE execution, show cost estimates BEFORE running.

**What changed:**
- **Before**: `octo research X` → immediate execution → surprise costs
- **Now**: `octo research X` → 3 questions (depth? focus? format?) → cost banner → you confirm → execution

**The 3 questions:**
1. **Depth**: Quick overview (1-2 min) → Moderate (2-3 min) → Comprehensive (3-4 min) → Deep dive (4-5 min)
2. **Focus**: Technical implementation vs Best practices vs Ecosystem & tools vs Trade-offs & comparisons
3. **Format**: Summary vs Detailed report vs Comparison table vs Recommendations

**Cost banner example** (shown BEFORE execution):
```
🐙 CLAUDE OCTOPUS ACTIVATED - Multi-provider research
🔍 Discover Phase: OAuth authentication patterns

Provider Availability:
🔴 Codex CLI: Available ✓
🟡 Gemini CLI: Available ✓
🔵 Claude: Available ✓

Research Parameters:
📊 Depth: Moderate depth
🎯 Focus: Trade-offs & comparisons
📝 Format: Comparison table

💰 Estimated Cost: $0.02-0.03
⏱️  Estimated Time: 2-3 minutes
```

You see exactly what will run and what it costs BEFORE it starts.

### 5. Context-Aware Intelligence

**The problem**: Same workflow shouldn't be used for "research GraphQL" (dev work) and "research market opportunities" (business strategy).

**The solution**: Auto-detects Dev vs Knowledge context and adapts workflows accordingly.

**Examples:**
- **Dev context detected** → Research focuses on libraries, code patterns, implementation approaches
- **Knowledge context detected** → Research focuses on market data, competitive analysis, strategic frameworks

**How detection works:**
- Scans your prompt for technical terms (API, function, implementation) → Dev mode
- Scans for business terms (market, ROI, stakeholders) → Knowledge mode
- Checks project files (package.json, Cargo.toml) → Suggests Dev mode

**Override anytime**: `/octo:km on` (force Knowledge mode) | `/octo:km off` (force Dev mode) | `/octo:km auto` (auto-detect)

### 6. Developer Experience

**Natural language interface** - No complex syntax to learn:
- ✅ `octo research authentication patterns`
- ✅ `octo build user login system`
- ✅ `octo review this code for security`
- ✅ `octo debate GraphQL vs REST`

**Visual feedback** - Always know what's running and what it costs:
- 🔴 Codex CLI (uses your OPENAI_API_KEY)
- 🟡 Gemini CLI (uses your GEMINI_API_KEY)
- 🔵 Claude (included with Claude Code)

**Comprehensive logging** - Full audit trail saved to `~/.claude-octopus/results/[session-id]/`:
- `orchestrate.log` - Full execution trace
- `codex-response.json` - Codex output
- `gemini-response.json` - Gemini output
- `synthesis.md` - Final combined analysis
- `costs.json` - Token usage and cost breakdown

**Background processing** - Long-running tasks don't block your workflow; resume interrupted sessions without losing context

### What's New in v7.14.0

**Interactive Research with Cost Transparency**

Before this update, `octo research X` would immediately execute with all three AIs, potentially costing $0.10 without warning.

Now you get:
1. **3 clarifying questions** before execution:
   - How deep should the research go? (Quick → Deep dive)
   - What's your primary focus? (Technical → Trade-offs)
   - How should results be formatted? (Summary → Comparison table)

2. **Cost transparency banner** showing EXACTLY what will run:
   ```
   💰 Estimated Cost: $0.02-0.03
   ⏱️  Estimated Time: 2-3 minutes

   Provider Availability:
   🔴 Codex CLI: Available ✓
   🟡 Gemini CLI: Available ✓
   ```

3. **You confirm before it runs** - No surprise costs

**Task Agent Integration** (optional): Research can now spawn background Claude Code agents for codebase context while external AIs handle ecosystem research (parallel execution).

### Previous Updates (v7.13.3)

**Debate Reliability Improvements**
- ✅ **100% completion rate** - All 47 test scenarios pass (was ~85% before)
- ✅ **No silent failures** - Every error has clear message and context
- ✅ **7 validation checkpoints** - Debates can't proceed with invalid state
- ✅ **Optimized timeouts** - 120-150s for multi-round analysis (vs 60-90s)
- ✅ **Detailed error logs** - Full context: agent name, role, phase, exit codes

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

### v7.9.2 - Command Prefix Update
- **Commands now use `/octo:*` prefix**: `/octo:research`, `/octo:debate`, etc.
- **Plugin name unchanged**: Still `claude-octopus@nyldn-plugins`
- **All `/co:` references updated** to `/octo:` in docs and command files

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
- 🔴 **Codex CLI**: Uses your `OPENAI_API_KEY` (GPT-5.x based)
- 🟡 **Gemini CLI**: Uses your `GEMINI_API_KEY` (Gemini 3.0)

**Claude subagents are included:**
- 🔵 **Claude Code Task tool**: No additional cost (included with Claude Code subscription)

### Cost Breakdown by Scenario

| Scenario | Duration | Estimated Cost | What You Get |
|----------|----------|----------------|--------------|
| **Simple research** (Quick overview) | 1-2 min | $0.01-0.02 | High-level summary from all 3 AIs |
| **Standard research** (Moderate depth) | 2-3 min | $0.02-0.05 | Balanced exploration with synthesis |
| **Deep dive** (Comprehensive) | 4-5 min | $0.05-0.10 | Exhaustive research from multiple angles |
| **AI Debate** (3-5 rounds) | 5-10 min | $0.08-0.15 | Structured debate with rebuttals |
| **Code review** (Security audit) | 3-5 min | $0.04-0.08 | Multi-AI security and quality analysis |
| **Full workflow** (Embrace: 4 phases) | 15-25 min | $0.20-0.40 | Research → Define → Develop → Deliver |

**Cost visibility**: Every multi-AI workflow shows estimated cost BEFORE execution (v7.14.0+)

### When to Use What

**Use multi-AI orchestration (🐙) when:**
- ✅ Making high-stakes decisions (architecture choices, tech stack selection)
- ✅ Need multiple perspectives (security reviews, design trade-offs)
- ✅ Research requires broad coverage (comparing 5+ options)
- ✅ Code review benefits from adversarial analysis (production-critical code)
- ✅ Complex implementation needs different approaches (multiple valid solutions)

**Use Claude only (no 🐙) when:**
- ✅ Simple file operations (reading, editing, basic refactoring)
- ✅ Single perspective adequate (straightforward questions)
- ✅ Quick edits or fixes (typos, formatting)
- ✅ Cost efficiency matters (early exploration, learning)
- ✅ You already know the answer (just need implementation help)

📖 **[Visual Indicators Guide](docs/VISUAL-INDICATORS.md)** - Complete cost breakdown with examples

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
  <em>🐙 Made with eight tentacles (one for each AI perspective, plus spares) 🐙</em><br/>
  <a href="https://github.com/nyldn">nyldn</a> | MIT License | <a href="https://github.com/nyldn/claude-octopus/issues">Report Issues</a>
</p>
