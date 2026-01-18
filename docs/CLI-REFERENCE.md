# CLI Reference - Direct orchestrate.sh Usage

This guide documents direct CLI usage of orchestrate.sh for advanced users and automation scenarios.

**Note:** For plugin users, natural language triggers (documented in [TRIGGERS.md](./TRIGGERS.md)) are the recommended way to use Claude Octopus. This CLI reference is for:
- Automation scripts
- CI/CD pipelines
- Direct command-line usage outside Claude Code
- Advanced power users

---

## Quick Reference

```bash
# Execute from repository root
./scripts/orchestrate.sh <command> [options] "<prompt>"
```

### Core Commands

| Command | What It Does |
|---------|--------------|
| `auto <prompt>` | Smart routing - picks best workflow automatically |
| `embrace <prompt>` | Full 4-phase Double Diamond workflow |
| `probe <prompt>` | Research phase - parallel exploration |
| `grasp <prompt>` | Define phase - problem clarification |
| `tangle <prompt>` | Development phase - parallel implementation |
| `ink <prompt>` | Delivery phase - validation and QA |
| `grapple <prompt>` | Adversarial debate between AI models |
| `squeeze <prompt>` | Red team security review |
| `octopus-configure` | Interactive configuration wizard |
| `preflight` | Verify all dependencies |
| `status` | Show provider status and running agents |
| `detect-providers` | Fast provider detection (< 1 second) |

---

## Installation & Setup

### Provider Installation

You need at least ONE AI provider (not both):

#### Option A: OpenAI Codex CLI (Best for code generation)
```bash
npm install -g @openai/codex
codex login  # OAuth recommended

# OR use API key
export OPENAI_API_KEY="sk-..."  # Get from https://platform.openai.com/api-keys
```

#### Option B: Google Gemini CLI (Best for analysis)
```bash
npm install -g @google/gemini-cli
gemini  # OAuth recommended

# OR use API key
export GEMINI_API_KEY="AIza..."  # Get from https://aistudio.google.com/app/apikey
```

### Making API Keys Permanent

To make API keys available in every terminal session:

```bash
# For zsh (macOS default)
echo 'export OPENAI_API_KEY="sk-..."' >> ~/.zshrc
source ~/.zshrc

# For bash (Linux default)
echo 'export OPENAI_API_KEY="sk-..."' >> ~/.bashrc
source ~/.bashrc
```

### Verify Setup

```bash
# Check provider status
./scripts/orchestrate.sh detect-providers

# Run full preflight check
./scripts/orchestrate.sh preflight

# Show current status
./scripts/orchestrate.sh status
```

---

## Double Diamond Workflows

```
     DISCOVER         DEFINE         DEVELOP          DELIVER
     (probe)          (grasp)        (tangle)          (ink)

    \         /     \         /     \         /     \         /
     \   *   /       \   *   /       \   *   /       \   *   /
      \ * * /         \     /         \ * * /         \     /
       \   /           \   /           \   /           \   /
        \ /             \ /             \ /             \ /

   Diverge then      Converge to      Diverge with     Converge to
    converge          problem          solutions        delivery
```

### Phase 1: PROBE (Discover)

Parallel research from multiple perspectives - problem space, existing solutions, edge cases, technical feasibility.

```bash
./scripts/orchestrate.sh probe "What are the best approaches for real-time notifications?"
```

**Output:**
- Research synthesis from Codex, Gemini, and Claude
- Saved to `~/.claude-octopus/results/${SESSION_ID}/probe-synthesis-*.md`

### Phase 2: GRASP (Define)

Multi-AI consensus on problem definition, success criteria, and constraints.

```bash
./scripts/orchestrate.sh grasp "Define requirements for notification system"
```

**Output:**
- Problem definition with requirements
- Saved to `~/.claude-octopus/results/${SESSION_ID}/grasp-synthesis-*.md`

### Phase 3: TANGLE (Develop)

Enhanced map-reduce with 75% quality gate threshold.

```bash
./scripts/orchestrate.sh tangle "Implement notification service"
```

**Output:**
- Implementation approaches from multiple providers
- Quality gate evaluation
- Saved to `~/.claude-octopus/results/${SESSION_ID}/tangle-synthesis-*.md`

### Phase 4: INK (Deliver)

Validation and final deliverable generation.

```bash
./scripts/orchestrate.sh ink "Deliver notification system"
```

**Output:**
- Validation report with quality scores
- Go/no-go recommendation
- Saved to `~/.claude-octopus/results/${SESSION_ID}/ink-validation-*.md`

### Full Workflow: EMBRACE

Run all four phases in sequence:

```bash
./scripts/orchestrate.sh embrace "Create a complete user dashboard feature"
```

**Executes:**
1. Probe - Research dashboard patterns
2. Grasp - Define dashboard requirements
3. Tangle - Implement dashboard
4. Ink - Validate dashboard implementation

---

## Smart Auto-Routing

The `auto` command detects intent and routes to the appropriate workflow:

| Intent Keywords | Routes To | Example |
|----------------|-----------|---------|
| research, explore, investigate | `probe` | "research caching best practices" |
| define, clarify, scope | `grasp` | "define caching requirements" |
| develop, build, implement | `tangle` → `ink` | "build the caching layer" |
| qa, test, validate, review | `ink` | "review the caching implementation" |
| adversarial, debate | `grapple` | "adversarial review of cache design" |
| security audit, red team | `squeeze` | "security audit the auth module" |

**Usage:**
```bash
./scripts/orchestrate.sh auto "research OAuth patterns"           # -> probe
./scripts/orchestrate.sh auto "build user login"                  # -> tangle + ink
./scripts/orchestrate.sh auto "security audit auth.ts"            # -> squeeze
```

---

## Adversarial Review (Crossfire)

Different AI models have different blind spots. Crossfire forces models to critique each other.

### Grapple - Adversarial Debate

```bash
./scripts/orchestrate.sh grapple "implement password reset API"
./scripts/orchestrate.sh grapple --principles security "implement JWT auth"
```

**How it works:**
```
Round 1: Codex proposes → Gemini proposes (parallel)
Round 2: Gemini critiques Codex → Codex critiques Gemini
Round 3: Synthesis determines winner + final implementation
```

**Constitutional Principles:**

| Principle | Focus |
|-----------|-------|
| `general` | Overall quality (default) |
| `security` | OWASP Top 10, secure coding |
| `performance` | N+1 queries, caching, async |
| `maintainability` | Clean code, testability |

**Examples:**
```bash
# General quality review
./scripts/orchestrate.sh grapple "implement user registration"

# Security-focused review
./scripts/orchestrate.sh grapple --principles security "implement JWT auth"

# Performance-focused review
./scripts/orchestrate.sh grapple --principles performance "implement API caching"
```

### Squeeze - Red Team Security Review

```bash
./scripts/orchestrate.sh squeeze "implement user login form"
```

**How it works:**

| Phase | Team | Action |
|-------|------|--------|
| 1 | Blue Team (Codex) | Implements secure solution |
| 2 | Red Team (Gemini) | Finds vulnerabilities |
| 3 | Remediation | Fixes all issues |
| 4 | Validation | Verifies all fixed |

**Example:**
```bash
./scripts/orchestrate.sh squeeze "review auth.ts for vulnerabilities"
```

---

## Provider-Aware Routing

Claude Octopus intelligently routes tasks based on your subscription tiers and costs.

### CLI Flags

```bash
--provider <name>     # Force provider: codex, gemini, claude, openrouter
--cost-first          # Prefer cheapest capable provider
--quality-first       # Prefer highest-tier provider
--openrouter-nitro    # Use fastest OpenRouter routing
--openrouter-floor    # Use cheapest OpenRouter routing
```

### Cost Optimization Strategies

| Strategy | Description |
|----------|-------------|
| `balanced` (default) | Smart mix of cost and quality |
| `cost-first` | Prefer cheapest capable provider |
| `quality-first` | Prefer highest-tier provider |

### Provider Tiers

The configuration wizard sets your subscription tier for each provider:

| Provider | Tiers | Cost Behavior |
|----------|-------|---------------|
| Codex/OpenAI | free, plus, pro, api-only | Routes based on tier |
| Gemini | free, google-one, workspace, api-only | Workspace = bundled (free) |
| Claude | pro, max-5x, max-20x, api-only | Conserves Opus for complex tasks |
| OpenRouter | pay-per-use | 400+ models as fallback |

**Example:** If you have Google Workspace (bundled Gemini), the system prefers Gemini for heavy analysis since it's "free" with your work account.

**Usage:**
```bash
# Check current provider status
./scripts/orchestrate.sh status

# Force cost-first routing
./scripts/orchestrate.sh --cost-first auto "research best practices"

# Force specific provider
./scripts/orchestrate.sh --provider gemini probe "research OAuth patterns"

# Quality-first for critical tasks
./scripts/orchestrate.sh --quality-first tangle "implement authentication"
```

---

## Common Options

| Option | Description | Example |
|--------|-------------|---------|
| `-n`, `--dry-run` | Show what would execute without running | `--dry-run probe "test"` |
| `-v`, `--verbose` | Enable verbose logging | `-v tangle "build feature"` |
| `-t <seconds>`, `--timeout <seconds>` | Set timeout in seconds | `-t 600 probe "research"` |
| `--cost-first` | Prefer cheapest provider | `--cost-first auto "task"` |
| `--quality-first` | Prefer highest-tier provider | `--quality-first tangle "critical"` |
| `--provider <name>` | Force specific provider | `--provider gemini probe "research"` |

**Examples:**
```bash
# Dry run to preview execution
./scripts/orchestrate.sh -n probe "research caching"

# Verbose mode for debugging
./scripts/orchestrate.sh -v tangle "implement auth"

# Extended timeout for complex tasks
./scripts/orchestrate.sh -t 1200 embrace "build complete dashboard"

# Cost-optimized research
./scripts/orchestrate.sh --cost-first probe "research microservices"
```

---

## Quality Gates

Quality gates ensure minimum standards before delivery:

| Score | Status | Behavior |
|-------|--------|----------|
| >= 90% | PASSED | Proceed to ink |
| 75-89% | WARNING | Proceed with caution |
| < 75% | FAILED | Flags for review |

**Quality Dimensions:**
- **Code Quality** (25%): Complexity, maintainability, documentation
- **Security** (35%): OWASP compliance, auth, input validation
- **Best Practices** (20%): Error handling, logging, testing
- **Completeness** (20%): Feature completeness, edge cases

**Example:**
```bash
# Tangle phase includes automatic quality gates
./scripts/orchestrate.sh tangle "implement user authentication"

# Output includes quality score:
# Quality Score: 82/100 (WARNING - below 90%)
# - Code Quality: 85/100
# - Security: 78/100 ⚠️
# - Best Practices: 80/100
# - Completeness: 85/100
```

---

## Configuration

### Interactive Configuration Wizard

```bash
./scripts/orchestrate.sh octopus-configure
```

**Configures:**
- Provider detection and setup
- Subscription tier for each provider
- Cost optimization strategy
- Quality thresholds
- Session storage locations

### Preflight Checks

```bash
./scripts/orchestrate.sh preflight
```

**Verifies:**
- ✅ All required dependencies installed
- ✅ Providers configured correctly
- ✅ API keys valid
- ✅ File permissions correct
- ✅ Session directories writable

### Status

```bash
./scripts/orchestrate.sh status
```

**Shows:**
- Provider availability
- Current configuration
- Running agents
- Recent activity
- Cost tracking (if enabled)

---

## Output and Results

### Result Storage

All workflow results are saved to:
```
~/.claude-octopus/results/${SESSION_ID}/
├── probe-synthesis-20260118-143022.md
├── grasp-synthesis-20260118-144530.md
├── tangle-synthesis-20260118-145800.md
└── ink-validation-20260118-150200.md
```

### Debate Storage

Debates are stored in session-aware folders:
```
~/.claude-octopus/debates/${SESSION_ID}/
└── 042-redis-vs-memcached/
    ├── context.md
    ├── state.json
    ├── synthesis.md
    └── rounds/
        ├── r001_gemini.md
        ├── r001_codex.md
        └── r001_claude.md
```

---

## Examples

### Research and Implement a Feature

```bash
# Phase 1: Research authentication patterns
./scripts/orchestrate.sh probe "authentication best practices for React apps"

# Phase 2: Define requirements
./scripts/orchestrate.sh grasp "define requirements for JWT authentication"

# Phase 3: Implement
./scripts/orchestrate.sh tangle "implement JWT authentication system"

# Phase 4: Validate
./scripts/orchestrate.sh ink "validate authentication implementation"
```

### Or use embrace for all phases:
```bash
./scripts/orchestrate.sh embrace "build complete JWT authentication system"
```

### Security Audit

```bash
# Red team security review
./scripts/orchestrate.sh squeeze "audit auth.ts for security vulnerabilities"

# Adversarial security-focused debate
./scripts/orchestrate.sh grapple --principles security "review login implementation"
```

### Cost-Optimized Research

```bash
# Use cheapest provider for research
./scripts/orchestrate.sh --cost-first probe "research React state management"

# Use quality-first for critical implementation
./scripts/orchestrate.sh --quality-first tangle "implement payment processing"
```

---

## Troubleshooting

### Provider Not Found

```bash
# Check provider status
./scripts/orchestrate.sh detect-providers

# Expected output:
# CODEX_STATUS=ready
# GEMINI_STATUS=ready
```

**If missing:**
```bash
# Install provider
npm install -g @openai/codex
codex login

# Or set API key
export OPENAI_API_KEY="sk-..."
```

### Permission Denied

```bash
# Make orchestrate.sh executable
chmod +x ./scripts/orchestrate.sh

# Check file permissions
ls -la ./scripts/orchestrate.sh
```

### Session Directory Not Found

```bash
# Verify session directory exists
ls -la ~/.claude-octopus/

# Create if missing
mkdir -p ~/.claude-octopus/results
mkdir -p ~/.claude-octopus/debates
```

### Timeout Errors

```bash
# Increase timeout for complex tasks
./scripts/orchestrate.sh -t 1200 embrace "complex feature"

# Default timeout is 120 seconds (2 minutes)
# Maximum timeout is 1800 seconds (30 minutes)
```

---

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Code Review with Claude Octopus

on: [pull_request]

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Install providers
        run: |
          npm install -g @openai/codex
          echo "OPENAI_API_KEY=${{ secrets.OPENAI_API_KEY }}" >> $GITHUB_ENV

      - name: Run code review
        run: |
          ./scripts/orchestrate.sh ink "review changes in this PR"

      - name: Post results
        uses: actions/github-script@v6
        with:
          script: |
            const fs = require('fs');
            const results = fs.readFileSync('~/.claude-octopus/results/latest/ink-validation.md', 'utf8');
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.name,
              body: results
            });
```

---

## See Also

- **[Visual Indicators Guide](./VISUAL-INDICATORS.md)** - Understanding what's running in plugin mode
- **[Triggers Guide](./TRIGGERS.md)** - Natural language triggers for plugin users
- **[Plugin Architecture](./PLUGIN-ARCHITECTURE.md)** - How the plugin works internally
- **[README](../README.md)** - Main documentation

---

**For plugin users:** The natural language interface (documented in [TRIGGERS.md](./TRIGGERS.md)) is the recommended way to use Claude Octopus. Use this CLI reference for automation, CI/CD, or advanced power-user scenarios.
