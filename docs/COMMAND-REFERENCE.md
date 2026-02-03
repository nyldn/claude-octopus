# Command Reference

Complete reference for all Claude Octopus commands.

---

## Quick Reference

All commands use the `/co:` namespace.

### System Commands

| Command | Description |
|---------|-------------|
| `/co:setup` | Check setup status and configure providers |
| `/co:update` | Check for plugin updates |
| `/co:dev` | Switch to Dev Work mode |
| `/co:km` | Toggle Knowledge Work mode |
| `/co:sys-setup` | Full name for setup |
| `/co:sys-update` | Full name for update |
| `/co:check-update` | Alias for sys-update |

### Workflow Commands

| Command | Phase | Description |
|---------|-------|-------------|
| `/co:discover` | Discover | Multi-AI research and exploration |
| `/co:define` | Define | Requirements clarification and scope |
| `/co:develop` | Develop | Multi-AI implementation |
| `/co:deliver` | Deliver | Validation and quality assurance |
| `/co:embrace` | All | Full 4-phase Double Diamond workflow |

### Skill Commands

| Command | Description |
|---------|-------------|
| `/co:debate` | AI Debate Hub - 3-way debates (Claude + Gemini + Codex) |
| `/co:review` | Expert code review with quality assessment |
| `/co:research` | Deep research with multi-source synthesis |
| `/co:security` | Security audit with OWASP compliance |
| `/co:debug` | Systematic debugging with investigation |
| `/co:tdd` | Test-driven development workflows |
| `/co:docs` | Document delivery (PPTX/DOCX/PDF export) |

### Project Lifecycle Commands

| Command | Description |
|---------|-------------|
| `/octo:status` | Show project progress dashboard |
| `/octo:resume` | Restore context from previous session |
| `/octo:ship` | Finalize project with Multi-AI validation |
| `/octo:issues` | Track issues across sessions |
| `/octo:rollback` | Restore from checkpoint |

---

## Project Lifecycle Commands

Commands for managing project state across sessions.

### `/octo:status`

Show project progress dashboard.

**Usage:** `/octo:status`

**Output:**
- Current phase and position
- Roadmap progress with checkmarks
- Active blockers
- Suggested next action

---

### `/octo:resume`

Restore context from previous session.

**Usage:** `/octo:resume`

**Behavior:**
1. Reads `.octo/STATE.md` for current position
2. Loads context using adaptive tier
3. Shows restoration summary
4. Suggests next action

---

### `/octo:ship`

Finalize project with Multi-AI validation.

**Usage:** `/octo:ship`

**Behavior:**
1. Verifies project ready (all phases complete)
2. Runs Multi-AI security audit (Codex + Gemini + Claude)
3. Captures lessons learned
4. Archives project state
5. Creates shipped checkpoint

---

### `/octo:issues`

Track issues across sessions.

**Usage:** `/octo:issues [list|add|resolve|show] [args]`

**Subcommands:**
- `list` - Show all open issues (default)
- `add <description>` - Add new issue
- `resolve <id>` - Mark issue resolved
- `show <id>` - Show issue details

**Issue ID Format:** `ISS-YYYYMMDD-NNN`

**Severity Levels:** critical, high, medium, low

---

### `/octo:rollback`

Restore from checkpoint.

**Usage:** `/octo:rollback [list|<tag>]`

**Subcommands:**
- `list` - Show available checkpoints (default)
- `<tag>` - Rollback to specific checkpoint

**Safety:**
- Creates pre-rollback checkpoint automatically
- Preserves LESSONS.md (never rolled back)
- Requires explicit "ROLLBACK" confirmation

---

## System Commands

### `/co:setup`

Check setup status and configure AI providers.

**Usage:**
```
/co:setup
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

### `/co:update`

Check for plugin updates and install if available.

**Usage:**
```
/co:update           # Check only
/co:update --update  # Check and auto-install
```

**What it does:**
- Compares installed version with latest release
- Shows changelog for new versions
- Optionally auto-installs updates

### `/co:km`

Toggle between Dev Work mode and Knowledge Work mode.

**Usage:**
```
/co:km          # Show current status
/co:km on       # Enable Knowledge Work mode
/co:km off      # Disable (return to Dev Work mode)
```

**Modes:**
| Mode | Focus | Best For |
|------|-------|----------|
| Dev Work (default) | Code, tests, debugging | Software development |
| Knowledge Work | Research, strategy, UX | Consulting, research, product work |

### `/co:dev`

Shortcut to switch to Dev Work mode.

**Usage:**
```
/co:dev
```

Equivalent to `/co:km off`.

---

## Workflow Commands

### `/co:discover`

Discovery phase - Multi-AI research and exploration.

**Usage:**
```
/co:discover OAuth authentication patterns
```

**What it does:**
- Launches parallel research using Codex CLI + Gemini CLI
- Synthesizes findings from multiple AI perspectives
- Shows visual indicator: 🐙 🔍

**Natural language triggers:**
- `octo research X`
- `octo explore Y`
- `octo investigate Z`

### `/co:define`

Definition phase - Clarify requirements and scope.

**Usage:**
```
/co:define requirements for user authentication
```

**What it does:**
- Multi-AI consensus on problem definition
- Identifies success criteria and constraints
- Shows visual indicator: 🐙 🎯

**Natural language triggers:**
- `octo define requirements for X`
- `octo clarify scope of Y`
- `octo scope out Z feature`

### `/co:develop`

Development phase - Multi-AI implementation.

**Usage:**
```
/co:develop user authentication system
```

**What it does:**
- Generates implementation approaches from multiple AIs
- Applies 75% quality gate threshold
- Shows visual indicator: 🐙 🛠️

**Natural language triggers:**
- `octo build X`
- `octo implement Y`
- `octo create Z`

### `/co:deliver`

Delivery phase - Validation and quality assurance.

**Usage:**
```
/co:deliver authentication implementation
```

**What it does:**
- Multi-AI validation and review
- Quality scores and go/no-go recommendation
- Shows visual indicator: 🐙 ✅

**Natural language triggers:**
- `octo review X`
- `octo validate Y`
- `octo audit Z`

### `/co:embrace`

Full Double Diamond workflow - all 4 phases.

**Usage:**
```
/co:embrace complete authentication system
```

**What it does:**
1. **Discover**: Research patterns and approaches
2. **Define**: Clarify requirements
3. **Develop**: Implement with quality gates
4. **Deliver**: Validate and finalize

Shows visual indicator: 🐙 (all phases)

---

## Skill Commands

### `/co:debate`

AI Debate Hub - Structured 3-way debates.

**Usage:**
```
/co:debate Redis vs Memcached for caching
/co:debate -r 3 Should we use GraphQL or REST
/co:debate -d adversarial Review auth.ts security
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

### `/co:review`

Expert code review with quality assessment.

**Usage:**
```
/co:review auth.ts
/co:review src/components/
```

**What it does:**
- Comprehensive code quality analysis
- Security vulnerability detection
- Architecture review
- Best practices enforcement

### `/co:research`

Deep research with multi-source synthesis.

**Usage:**
```
/co:research microservices patterns
```

**What it does:**
- Multi-source research using AI providers
- Documentation lookup via librarian
- Synthesizes findings into actionable insights

### `/co:security`

Security audit with OWASP compliance.

**Usage:**
```
/co:security auth.ts
/co:security src/api/
```

**What it does:**
- OWASP Top 10 vulnerability scanning
- Authentication and authorization review
- Input validation checks
- Red team analysis (adversarial testing)

### `/co:debug`

Systematic debugging with investigation.

**Usage:**
```
/co:debug failing test in auth.spec.ts
```

**What it does:**
1. Investigate: Gather evidence
2. Analyze: Root cause identification
3. Hypothesize: Form theories
4. Implement: Fix with verification

### `/co:tdd`

Test-driven development workflows.

**Usage:**
```
/co:tdd implement user registration
```

**What it does:**
- Red: Write failing test first
- Green: Minimal code to pass
- Refactor: Improve while keeping tests green

### `/co:docs`

Document delivery with export options.

**Usage:**
```
/co:docs create API documentation
/co:docs export report.md to PPTX
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
| `octo research OAuth patterns` | `/co:discover OAuth patterns` |
| `octo build user auth` | `/co:develop user auth` |
| `octo review my code` | `/co:deliver my code` |
| `octo debate X vs Y` | `/co:debate X vs Y` |

**Why "octo"?** Common words like "research" may conflict with Claude's base behaviors. The "octo" prefix ensures reliable activation.

📖 See [Triggers Guide](./TRIGGERS.md) for the complete list.

---

## See Also

- **[Visual Indicators Guide](./VISUAL-INDICATORS.md)** - Understanding what's running
- **[Triggers Guide](./TRIGGERS.md)** - What activates each workflow
- **[CLI Reference](./CLI-REFERENCE.md)** - Direct CLI usage (advanced)
- **[README](../README.md)** - Main documentation
