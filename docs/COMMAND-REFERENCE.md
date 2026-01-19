# Command Reference

Complete reference for all Claude Octopus commands.

---

## Quick Reference

All commands use the `/octo:` namespace.

### System Commands

| Command | Description |
|---------|-------------|
| `/octo:setup` | Check setup status and configure providers |
| `/octo:update` | Check for plugin updates |
| `/octo:dev` | Switch to Dev Work mode |
| `/octo:km` | Toggle Knowledge Work mode |
| `/octo:sys-setup` | Full name for setup |
| `/octo:sys-update` | Full name for update |
| `/octo:check-update` | Alias for sys-update |

### Workflow Commands

| Command | Phase | Description |
|---------|-------|-------------|
| `/octo:discover` | Discover | Multi-AI research and exploration |
| `/octo:define` | Define | Requirements clarification and scope |
| `/octo:develop` | Develop | Multi-AI implementation |
| `/octo:deliver` | Deliver | Validation and quality assurance |
| `/octo:embrace` | All | Full 4-phase Double Diamond workflow |

### Skill Commands

| Command | Description |
|---------|-------------|
| `/octo:debate` | AI Debate Hub - 3-way debates (Claude + Gemini + Codex) |
| `/octo:review` | Expert code review with quality assessment |
| `/octo:research` | Deep research with multi-source synthesis |
| `/octo:security` | Security audit with OWASP compliance |
| `/octo:debug` | Systematic debugging with investigation |
| `/octo:tdd` | Test-driven development workflows |
| `/octo:docs` | Document delivery (PPTX/DOCX/PDF export) |

---

## System Commands

### `/octo:setup`

Check setup status and configure AI providers.

**Usage:**
```
/octo:setup
```

**What it does:**
- Auto-detects installed providers (Codex CLI, Gemini CLI)
- Shows which providers are available
- Provides installation instructions for missing providers
- Verifies API keys and authentication

**Example output:**
```
Claude Octopus Setup Status

Providers:
  Codex CLI: ready
  Gemini CLI: ready

You're all set! Try: octo research OAuth patterns
```

### `/octo:update`

Check for plugin updates and install if available.

**Usage:**
```
/octo:update           # Check only
/octo:update --update  # Check and auto-install
```

**What it does:**
- Compares installed version with latest release
- Shows changelog for new versions
- Optionally auto-installs updates

### `/octo:km`

Toggle between Dev Work mode and Knowledge Work mode.

**Usage:**
```
/octo:km          # Show current status
/octo:km on       # Enable Knowledge Work mode
/octo:km off      # Disable (return to Dev Work mode)
```

**Modes:**
| Mode | Focus | Best For |
|------|-------|----------|
| Dev Work (default) | Code, tests, debugging | Software development |
| Knowledge Work | Research, strategy, UX | Consulting, research, product work |

### `/octo:dev`

Shortcut to switch to Dev Work mode.

**Usage:**
```
/octo:dev
```

Equivalent to `/octo:km off`.

---

## Workflow Commands

### `/octo:discover`

Discovery phase - Multi-AI research and exploration.

**Usage:**
```
/octo:discover OAuth authentication patterns
```

**What it does:**
- Launches parallel research using Codex CLI + Gemini CLI
- Synthesizes findings from multiple AI perspectives
- Shows visual indicator: 🐙 🔍

**Natural language triggers:**
- `octo research X`
- `octo explore Y`
- `octo investigate Z`

### `/octo:define`

Definition phase - Clarify requirements and scope.

**Usage:**
```
/octo:define requirements for user authentication
```

**What it does:**
- Multi-AI consensus on problem definition
- Identifies success criteria and constraints
- Shows visual indicator: 🐙 🎯

**Natural language triggers:**
- `octo define requirements for X`
- `octo clarify scope of Y`
- `octo scope out Z feature`

### `/octo:develop`

Development phase - Multi-AI implementation.

**Usage:**
```
/octo:develop user authentication system
```

**What it does:**
- Generates implementation approaches from multiple AIs
- Applies 75% quality gate threshold
- Shows visual indicator: 🐙 🛠️

**Natural language triggers:**
- `octo build X`
- `octo implement Y`
- `octo create Z`

### `/octo:deliver`

Delivery phase - Validation and quality assurance.

**Usage:**
```
/octo:deliver authentication implementation
```

**What it does:**
- Multi-AI validation and review
- Quality scores and go/no-go recommendation
- Shows visual indicator: 🐙 ✅

**Natural language triggers:**
- `octo review X`
- `octo validate Y`
- `octo audit Z`

### `/octo:embrace`

Full Double Diamond workflow - all 4 phases.

**Usage:**
```
/octo:embrace complete authentication system
```

**What it does:**
1. **Discover**: Research patterns and approaches
2. **Define**: Clarify requirements
3. **Develop**: Implement with quality gates
4. **Deliver**: Validate and finalize

Shows visual indicator: 🐙 (all phases)

---

## Skill Commands

### `/octo:debate`

AI Debate Hub - Structured 3-way debates.

**Usage:**
```
/octo:debate Redis vs Memcached for caching
/octo:debate -r 3 Should we use GraphQL or REST
/octo:debate -d adversarial Review auth.ts security
```

**Options:**
| Flag | Description |
|------|-------------|
| `-r N`, `--rounds N` | Number of debate rounds (default: 2) |
| `-d STYLE`, `--debate-style STYLE` | quick, thorough, adversarial, collaborative |

**What it does:**
- Claude, Gemini CLI, and Codex CLI debate the topic
- Claude participates as both debater and moderator
- Produces synthesis with recommendations

**Natural language triggers:**
- `octo debate X vs Y`
- `run a debate about Z`
- `I want gemini and codex to review X`

### `/octo:review`

Expert code review with quality assessment.

**Usage:**
```
/octo:review auth.ts
/octo:review src/components/
```

**What it does:**
- Comprehensive code quality analysis
- Security vulnerability detection
- Architecture review
- Best practices enforcement

### `/octo:research`

Deep research with multi-source synthesis.

**Usage:**
```
/octo:research microservices patterns
```

**What it does:**
- Multi-source research using AI providers
- Documentation lookup via librarian
- Synthesizes findings into actionable insights

### `/octo:security`

Security audit with OWASP compliance.

**Usage:**
```
/octo:security auth.ts
/octo:security src/api/
```

**What it does:**
- OWASP Top 10 vulnerability scanning
- Authentication and authorization review
- Input validation checks
- Red team analysis (adversarial testing)

### `/octo:debug`

Systematic debugging with investigation.

**Usage:**
```
/octo:debug failing test in auth.spec.ts
```

**What it does:**
1. Investigate: Gather evidence
2. Analyze: Root cause identification
3. Hypothesize: Form theories
4. Implement: Fix with verification

### `/octo:tdd`

Test-driven development workflows.

**Usage:**
```
/octo:tdd implement user registration
```

**What it does:**
- Red: Write failing test first
- Green: Minimal code to pass
- Refactor: Improve while keeping tests green

### `/octo:docs`

Document delivery with export options.

**Usage:**
```
/octo:docs create API documentation
/octo:docs export report.md to PPTX
```

**Supported formats:**
- DOCX (Word)
- PPTX (PowerPoint)
- PDF

---

## Visual Indicators

When Claude Octopus activates external CLIs, you'll see visual indicators:

| Indicator | Meaning | Provider |
|-----------|---------|----------|
| 🐙 | Multi-AI mode active | Multiple providers |
| 🔴 | Codex CLI executing | OpenAI (your OPENAI_API_KEY) |
| 🟡 | Gemini CLI executing | Google (your GEMINI_API_KEY) |
| 🔵 | Claude subagent | Included with Claude Code |

**Example:**
```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider research mode
🔍 Discover Phase: Researching authentication patterns

Providers:
🔴 Codex CLI - Technical implementation analysis
🟡 Gemini CLI - Ecosystem and community research
🔵 Claude - Strategic synthesis
```

📖 See [Visual Indicators Guide](./VISUAL-INDICATORS.md) for details.

---

## Natural Language Triggers

Instead of slash commands, you can use natural language with the "octo" prefix:

| You Say | Equivalent Command |
|---------|--------------------|
| `octo research OAuth patterns` | `/octo:discover OAuth patterns` |
| `octo build user auth` | `/octo:develop user auth` |
| `octo review my code` | `/octo:deliver my code` |
| `octo debate X vs Y` | `/octo:debate X vs Y` |

**Why "octo"?** Common words like "research" may conflict with Claude's base behaviors. The "octo" prefix ensures reliable activation.

📖 See [Triggers Guide](./TRIGGERS.md) for the complete list.

---

## See Also

- **[Visual Indicators Guide](./VISUAL-INDICATORS.md)** - Understanding what's running
- **[Triggers Guide](./TRIGGERS.md)** - What activates each workflow
- **[CLI Reference](./CLI-REFERENCE.md)** - Direct CLI usage (advanced)
- **[README](../README.md)** - Main documentation
