---
name: skill-parallel-agents
description: "Decompose large tasks across parallel agents — use for migrations, multi-file refactors, or batch work"
disable-model-invocation: true
---

> **Host: Codex CLI** — This skill was designed for Claude Code and adapted for Codex.
> Invoke installed skills by their `$skill-name`. Known Octopus commands are mapped below. A remaining `/octo:*` reference is a Claude Code command; do not execute it in Codex or invent an equivalent.
> Use the active Codex shell and subagent tools. Do not claim a provider, model, or host subagent is available until the current session exposes it.
> For host tool equivalents, see `codex-skills/blocks/codex-host-adapter.md`.


## Execution Contract (MANDATORY - CANNOT SKIP)

This generated Codex skill preserves an enforced workflow contract from the source skill.

**PROHIBITED:**
- Do not summarize, simulate, or skip the referenced workflow command when this skill requires execution.
- Do not claim provider output or validation artifacts exist without checking the actual files or command output.
- Do not continue silently when a required provider, command, or host capability is unavailable; report the unavailable dependency and use a supported fallback.


# Claude Octopus - Multi-Tentacled Orchestrator

## Scope and execution contract

Use `$skill-parallel-agents` for explicitly requested analysis, implementation or review
that needs parallel provider perspectives. Routine file operations, git commands,
code navigation and basic terminal tasks stay with the host's direct tools.
Those operations do not require provider dispatch.

For work within this skill's scope, dispatch through `orchestrate.sh` and retain
its output artifacts. Do not replace requested parallel analysis with serial
single-provider work or describe one provider's output as consensus.


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

## Resolve the loaded installation

Run this block in the same shell as each example below. Repeat it when starting
a fresh shell. If the host supplies no plugin root, set `OCTO_ROOT` to the
verified installation that loaded this skill.

```bash
OCTO_ROOT="${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${DROID_PLUGIN_ROOT:-${OCTO_ROOT:-}}}}"
: "${OCTO_ROOT:?Set the verified installation that loaded this skill}"
OCTO_ROOT="$(cd -- "$OCTO_ROOT" && pwd -P)" || exit 1
for required in scripts/orchestrate.sh scripts/helpers/workflow-result.sh scripts/lib/host-runtime.sh scripts/lib/provider-registry.sh; do
  [[ -r "$OCTO_ROOT/$required" ]] || { echo "Incomplete Octopus installation: $OCTO_ROOT/$required" >&2; exit 1; }
done
[[ -x "$OCTO_ROOT/scripts/orchestrate.sh" && -x "$OCTO_ROOT/scripts/helpers/workflow-result.sh" ]] || exit 1
export OCTO_ROOT
```

## Quick Start

Run `$skill-parallel-agents "<task>"` to request multi-provider work. The default router
stays silent for ordinary conversation; natural language alone does not activate
this skill. The following examples are for direct CLI use or automation.

```bash
# Full Double Diamond workflow (all 4 phases)
"$OCTO_ROOT/scripts/orchestrate.sh" embrace "Build a user authentication system"

# Individual phases
"$OCTO_ROOT/scripts/orchestrate.sh" probe "Research authentication best practices"
"$OCTO_ROOT/scripts/orchestrate.sh" grasp "Define auth requirements"
"$OCTO_ROOT/scripts/orchestrate.sh" tangle "Implement auth feature"
"$OCTO_ROOT/scripts/orchestrate.sh" ink "Validate and deliver auth implementation"

# Crossfire: Adversarial cross-model review
"$OCTO_ROOT/scripts/orchestrate.sh" grapple "implement password reset API"
"$OCTO_ROOT/scripts/orchestrate.sh" grapple --principles security "implement JWT auth"
"$OCTO_ROOT/scripts/orchestrate.sh" squeeze "review auth.ts for vulnerabilities"

# Smart auto-routing (detects intent automatically)
"$OCTO_ROOT/scripts/orchestrate.sh" auto "research OAuth patterns"           # -> probe
"$OCTO_ROOT/scripts/orchestrate.sh" auto "build user login"                  # -> tangle + ink
"$OCTO_ROOT/scripts/orchestrate.sh" auto "review the auth code"              # -> ink
```

## IMPORTANT: When NOT to Use This Skill

**DO NOT use this skill if the user's request involves:**

1. **Built-in Claude Code commands** - Commands starting with `/` that are part of Claude Code itself:
   - `/plugin` - Plugin management (add, remove, update, list)
   - `/init` - Project initialization
   - `/help` - Help documentation
   - `/clear` - Clear conversation
   - `/commit` - Git commit operations
   - `/remember` - Memory management
   - Any other `/` command that isn't `/parallel-agents` or `/octo:*`

2. **Direct tool usage** - Simple file operations, git commands, or terminal tasks
   - Reading/writing files
   - Running git commands
   - Basic bash operations
   - These should use built-in tools directly

3. **Claude Code configuration** - Managing Claude Code itself
   - Changing settings
   - Managing plugins
   - Updating Claude Code

**If the user's request matches any of the above, DO NOT activate this skill. Handle the request using standard Claude Code tools and capabilities instead.**

## Visual Indicators - Know What's Running

Claude Octopus uses **visual indicators** so you always know which AI is responding:

| Indicator | Meaning | Uses |
|-----------|---------|------|
| 🐙 | **Parallel Mode** | Multiple CLIs orchestrated via orchestrate.sh |
| 🔴 | **Codex CLI** | OpenAI Codex (your OPENAI_API_KEY) |
| 🧭 | **Antigravity CLI** | Google Antigravity (your authenticated seat) |
| 🔵 | **Host tools** | Local file, git and shell operations |

### External provider work and local tools

**External CLIs execute when:**
- Using `/parallel-agents` command explicitly
- Using `$skill-debate` command (AI Debate Hub)
- Running orchestrate.sh workflows (probe, grasp, tangle, ink, embrace, grapple, squeeze)
- Knowledge mode deliberation (when Knowledge Mode is ON)
- Explicit invocation of this skill for research, implementation or review

**Use the host's direct tools for:**
- Simple file operations (read, write, edit)
- Git commands and bash operations
- Code reading and navigation
- Tasks that don't need multiple perspectives
- Built-in Claude Code capabilities are sufficient

External provider calls can use provider quotas or incur charges. Local file and git operations use the host's direct tools.

When you see 🐙 **CLAUDE OCTOPUS ACTIVATED**, external CLI providers such as Codex, Antigravity, and others will be invoked for multi-perspective analysis.


## Force Multi-Provider Mode

Sometimes you want multi-provider analysis even for simple tasks that wouldn't normally trigger workflows. This is useful when you need comprehensive perspectives on decisions, want to compare how different models think, or when automatic routing underestimates task complexity.

### Explicit Command

Force multi-provider execution using the `$skill-parallel-agents` command:

```
$skill-parallel-agents "Explain how Redis works"
$skill-parallel-agents "What is OAuth?"
$skill-parallel-agents "Review this simple function"
$skill-parallel-agents "Should we use TypeScript?"
```

### Explicit task requests

Put a request for multiple providers inside `$skill-parallel-agents`, for example:

```
$skill-parallel-agents "What is JWT?"
$skill-parallel-agents "Review our architecture from multiple perspectives"
$skill-parallel-agents "Compare perspectives on this design decision"
$skill-parallel-agents "Explain caching strategies"
$skill-parallel-agents "Analyze our API design"
```

### When to Force Parallel Mode

**Use forced parallel mode when:**
- **High-stakes decisions** require comprehensive analysis from multiple models
- **Comparing perspectives** - you want to see how different models approach the same problem
- **Simple questions with depth** - seemingly simple questions that deserve thorough multi-model analysis
- **Learning different approaches** - exploring how each model thinks about a topic
- **Automatic routing underestimates complexity** - task appears simple but has nuance

**Don't force parallel mode when:**
- A specific Octopus command already selects the workflow you need
- Simple factual questions Claude can answer reliably
- Cost efficiency is important (see cost awareness below)
- File operations or code navigation (use built-in tools)

### Cost Awareness

Forcing parallel mode uses external CLIs for every task, which incurs API costs:

| Provider | Cost per Query | What It Uses |
|----------|----------------|--------------|
| 🔴 Codex CLI | ~0.01-0.05 USD | Your OPENAI_API_KEY |
| 🧭 Antigravity CLI | Included with access/subscription | Antigravity CLI auth |
| 🔵 Claude | Included | Claude Code subscription |

**Total cost per forced query: ~0.02-0.08 USD**

Use parallel mode for tasks that benefit from multiple perspectives. Handle routine file and terminal work with direct tools; invoke Octopus explicitly when its workflows are needed.

### Visual Indicator

When you force parallel mode, you'll see this banner:

```
🐙 **CLAUDE OCTOPUS ACTIVATED** - Multi-provider mode
Force parallel execution

Providers:
🔴 Codex CLI - [Role in this task]
🧭 Antigravity CLI - [Role in this task]
🔵 Claude - [Role in this task]
```

Followed by results from each provider marked with their indicators (for example 🔴 🟡 🧭 🔵).


## Prerequisites check

Once this skill activates, run the local provider check:

```bash
source "$OCTO_ROOT/scripts/lib/host-runtime.sh" || exit 1
source "$OCTO_ROOT/scripts/lib/provider-registry.sh" || exit 1
HOST_RUNTIME="$(octo_detect_host_runtime "$OCTO_ROOT")" || exit 1
case "$HOST_RUNTIME" in
  claude|codex) HOST_PROVIDER="$HOST_RUNTIME" ;;
  *) HOST_PROVIDER="$(octo_provider_canonical "${OCTOPUS_HOST:-}")" || {
       echo "Set OCTOPUS_HOST to this host's configured provider before counting additional providers." >&2
       exit 1
     } ;;
esac
PROVIDER_REPORT="$("$OCTO_ROOT/scripts/orchestrate.sh" detect-providers)" || exit 1
printf '%s\n' "$PROVIDER_REPORT"
if [[ "$HOST_RUNTIME" == claude ]] && grep -qx 'CLAUDE_CODE_STATUS=outdated' <<< "$PROVIDER_REPORT"; then
  echo "Update the active Claude Code host before continuing." >&2
  exit 1
fi
ADDITIONAL_PROVIDER=""
while IFS='=' read -r name status; do
  [[ "$status" == ok && "$name" == *_STATUS && "$name" != CLAUDE_CODE_STATUS ]] || continue
  provider="$(printf '%s' "${name%_STATUS}" | tr '[:upper:]_' '[:lower:]-')"
  provider="$(octo_provider_canonical "$provider")" || continue
  [[ "$provider" == "$HOST_PROVIDER" ]] && continue
  ADDITIONAL_PROVIDER="$provider"
  break
done <<< "$PROVIDER_REPORT"
[[ -n "$ADDITIONAL_PROVIDER" ]] || {
  echo "No additional provider is ready. Run /octo:setup before parallel work." >&2
  exit 1
}
```

This check reads local commands, credentials, and the one-hour cache. It does not call provider APIs. Current output includes the Claude Code version contract and one status per provider:

```text
Detecting Claude Code version...

CLAUDE_CODE_VERSION=2.1.219
CLAUDE_CODE_STATUS=ok
CLAUDE_CODE_MINIMUM=2.1.14

CODEX_STATUS=ok
AGY_STATUS=unauthenticated
```

Provider values are `ok`, `unauthenticated`, `quota`, `not-installed`, or a specific reason such as `model-invalid`.

### Route based on the result

When Claude Code is the active host, an outdated version stops the workflow. On Codex, that version is diagnostic and does not block ready providers:

```text
CLAUDE_CODE_VERSION=2.1.13
CLAUDE_CODE_STATUS=outdated
CLAUDE_CODE_MINIMUM=2.1.14
```

Count ready provider identities other than the active host. The host cannot satisfy the requirement for an additional perspective; version metadata is not a provider. If none is ready, stop this parallel workflow and direct the user to `$sys-configure`. Ordinary Claude-only commands remain available. An additional provider supplies another perspective, not proof of consensus.

The command writes `~/.claude-octopus/.provider-cache`. Reuse it for up to one hour; after that, run detection again.

## Double Diamond Workflow

### Phase 1: PROBE (Discover)
**Diverge then converge on understanding**

Parallel research from 4 perspectives:
- Problem space analysis (constraints, requirements, needs)
- Existing solutions research (what worked, what failed)
- Edge cases exploration (potential challenges)
- Technical feasibility (prerequisites, dependencies)

```bash
"$OCTO_ROOT/scripts/orchestrate.sh" probe "What are the best approaches for real-time notifications?"
```

### Phase 2: GRASP (Define)
**Build consensus on the problem**

Multi-tentacled problem definition:
- Core problem statement
- Success criteria
- Constraints and boundaries

```bash
# Optional second argument: no phase sets this variable; copy the path the probe
# phase printed after "Probe synthesis saved to:"
PROBE_SYNTHESIS="<printed probe-synthesis-*.md path>"
"$OCTO_ROOT/scripts/orchestrate.sh" grasp "Define requirements for notification system" "$PROBE_SYNTHESIS"
```

### Phase 3: TANGLE (Develop)
**Diverge with multiple solutions**

Enhanced map-reduce with validation:
- Task decomposition via LLM
- Parallel execution across agents
- Quality gate (75% success threshold)

```bash
# Optional second argument: no phase sets this variable; copy the path the grasp
# phase printed after "Problem definition saved to:"
GRASP_CONSENSUS="<printed grasp-consensus-*.md path>"
"$OCTO_ROOT/scripts/orchestrate.sh" tangle "Implement notification service" "$GRASP_CONSENSUS"
```

### Phase 4: INK (Deliver)
**Converge to validated delivery**

Pre-delivery validation:
- Quality gate verification
- Result synthesis
- Final deliverable generation

```bash
# Optional second argument: no phase sets this variable; copy the path the tangle
# phase printed after "Validation complete:"
TANGLE_VALIDATION="<printed tangle-validation-*.md path>"
"$OCTO_ROOT/scripts/orchestrate.sh" ink "Deliver notification system" "$TANGLE_VALIDATION"
```

### Full Workflow: EMBRACE
Run all 4 phases sequentially with automatic context passing:

```bash
"$OCTO_ROOT/scripts/orchestrate.sh" embrace "Create a complete user dashboard feature"
```

## Crossfire: Adversarial Cross-Model Review

Different models have different blind spots. Crossfire commands force models to critique each other's work, catching more issues than single-model review.

### GRAPPLE - Adversarial Debate

*Two tentacles wrestling until consensus*

Available providers each propose solutions, then critique each other's work. A synthesis determines the winner.

```
┌─────────────┐     ┌─────────────┐
│   Codex     │     │ Antigravity │
│ (Proposer)  │     │ (Proposer)  │
└──────┬──────┘     └──────┬──────┘
       │                   │
       ▼                   ▼
┌─────────────┐     ┌─────────────┐
│ PROPOSAL A  │ ←─→ │ PROPOSAL B  │
└──────┬──────┘     └──────┬──────┘
       │                   │
       ▼                   ▼
┌─────────────┐     ┌─────────────┐
│ Antigravity │     │   Codex     │
│ (Critic)    │     │  (Critic)   │
└──────┬──────┘     └──────┬──────┘
       │                   │
       └─────────┬─────────┘
                 ▼
       ┌─────────────────┐
       │   SYNTHESIS     │
       │ (Winner + Fix)  │
       └─────────────────┘
```

```bash
# Basic grapple
"$OCTO_ROOT/scripts/orchestrate.sh" grapple "implement password reset API"

# Grapple with security principles
"$OCTO_ROOT/scripts/orchestrate.sh" grapple --principles security "implement JWT authentication"

# Grapple with performance principles
"$OCTO_ROOT/scripts/orchestrate.sh" grapple --principles performance "optimize database queries"
```

### SQUEEZE - Red Team Security Review

*Octopus squeezes prey to test for weaknesses*

Blue Team (Codex) implements secure code. Red Team (Antigravity) attacks to find vulnerabilities. Then remediation and validation.

```
Phase 1: Blue Team implements secure solution
Phase 2: Red Team finds vulnerabilities
Phase 3: Remediation fixes all issues
Phase 4: Validation verifies all fixed
```

```bash
"$OCTO_ROOT/scripts/orchestrate.sh" squeeze "implement user login form"
"$OCTO_ROOT/scripts/orchestrate.sh" squeeze "review auth.ts for vulnerabilities"
```

### Constitutional Principles

Grapple supports domain-specific critique principles:

| Principle | Focus | Use Case |
|-----------|-------|----------|
| `general` | Overall quality | Default for most reviews |
| `security` | OWASP Top 10, secure coding | Auth, payments, user data |
| `performance` | N+1 queries, caching, async | Database, API optimization |
| `maintainability` | Clean code, testability | Refactoring, code reviews |

```bash
"$OCTO_ROOT/scripts/orchestrate.sh" grapple --principles security "implement password reset"
"$OCTO_ROOT/scripts/orchestrate.sh" grapple --principles performance "optimize search API"
"$OCTO_ROOT/scripts/orchestrate.sh" grapple --principles maintainability "refactor user service"
```

## Smart Auto-Routing

The `auto` command detects intent keywords and routes to the appropriate workflow:

| Keywords | Routes To | Phases |
|----------|-----------|--------|
| research, explore, investigate, analyze | `probe` | Discover |
| develop, dev, build, implement, create | `tangle` + `ink` | Develop + Deliver |
| qa, test, review, validate, check | `ink` | Deliver (quality focus) |
| security audit, red team, pentest | `squeeze` | Red Team |
| adversarial, cross-model, debate | `grapple` | Debate |
| (other coding keywords) | `codex` agent | Single agent |
| (other design keywords) | `agy` agent | Single agent |

**Examples:**
```bash
"$OCTO_ROOT/scripts/orchestrate.sh" auto "research best practices for caching"     # -> probe
"$OCTO_ROOT/scripts/orchestrate.sh" auto "build the caching layer"                 # -> tangle + ink
"$OCTO_ROOT/scripts/orchestrate.sh" auto "review the cache implementation"         # -> ink
"$OCTO_ROOT/scripts/orchestrate.sh" auto "security audit the auth module"          # -> squeeze
"$OCTO_ROOT/scripts/orchestrate.sh" auto "have both models debate the API design"  # -> grapple
"$OCTO_ROOT/scripts/orchestrate.sh" auto "fix the cache invalidation bug"          # -> codex
```

## Quality Gates

The `tangle` phase enforces quality gates:

| Score | Status | Behavior |
|-------|--------|----------|
| >= 90% | PASSED | Proceed to ink |
| 75-89% | WARNING | Proceed with caution |
| < 75% | FAILED | Ink phase flags for review |

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

### Crossfire Commands (Adversarial Review)

| Command | Description |
|---------|-------------|
| `grapple <prompt>` | Codex vs Antigravity debate until consensus |
| `grapple --principles TYPE <prompt>` | Debate with domain principles (security, performance, maintainability) |
| `squeeze <prompt>` | Red Team security review (Blue Team vs Red Team) |

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
| `-t, --timeout` | 600 | Timeout per task (seconds); also replaces fixed per-call budgets such as grasp's 300s. `OCTOPUS_AGENT_TIMEOUT` overrides it |
| `-v, --verbose` | false | Verbose logging |
| `-n, --dry-run` | false | Show without executing |

## Agent Selection (Premium Defaults)

| Agent | Model | Best For |
|-------|-------|----------|
| `codex` | gpt-5.6-sol | Frontier implementation and independent review |
| `codex-standard` | gpt-5.6-terra | Balanced implementation and review |
| `codex-mini` | gpt-5.6-luna | Quick fixes, simple tasks |
| `agy` | service-selected default | Deep analysis and external review |
| `agy-research` | service-selected default | Research-focused Antigravity seat |
| `codex-review` | gpt-5.6-sol | Code review mode |
| `openrouter` | Various | Universal fallback (400+ models) |
| `orcarouter` | Various | Universal fallback via OrcaRouter gateway |

## Provider-Aware Routing (v4.8)

Claude Octopus now intelligently routes tasks based on your subscription tiers and costs.

### Provider Subscription Tiers

| Provider | Tiers | Monthly Cost | Capabilities |
|----------|-------|--------------|--------------|
| **Codex/OpenAI** | Free, Plus, Pro, API | 0-200 USD | code, chat, review |
| **Antigravity** | Google access/subscription | Included with access | code, analysis, external review |
| **Claude** | Pro, Max 5x, Max 20x, API | 20-200 USD | code, chat, analysis, long-context |
| **OpenRouter** | Pay-per-use | Variable | 400+ models, routing variants |
| **OrcaRouter** | Pay-per-use | Variable | Single gateway, namespaced model IDs |

### Cost Optimization Strategies

| Strategy | Description |
|----------|-------------|
| `balanced` (default) | Smart mix of cost and quality |
| `cost-first` | Prefer cheapest capable provider |
| `quality-first` | Prefer highest-tier provider |

**Example:** If your Google seat includes Antigravity access, the system can prefer AGY for analysis without invoking the retired Gemini CLI.

### Routing CLI Flags

```bash
# Force a specific provider
"$OCTO_ROOT/scripts/orchestrate.sh" --provider agy auto "analyze code structure"

# Prefer cheapest option
"$OCTO_ROOT/scripts/orchestrate.sh" --cost-first auto "research best practices"

# Prefer highest quality
"$OCTO_ROOT/scripts/orchestrate.sh" --quality-first auto "complex refactoring task"

# OpenRouter routing variants
"$OCTO_ROOT/scripts/orchestrate.sh" --openrouter-nitro auto "quick task"  # Fastest
"$OCTO_ROOT/scripts/orchestrate.sh" --openrouter-floor auto "bulk task"   # Cheapest
```

### Configuration

Provider tiers are configured during `setup` or via the providers config file:

```bash
# Run setup wizard (includes provider tier steps)
"$OCTO_ROOT/scripts/orchestrate.sh" setup

# View current provider status
"$OCTO_ROOT/scripts/orchestrate.sh" status
```

Configuration file: `~/.claude-octopus/.providers-config`

```yaml
version: "2.0"
providers:
  codex:
    installed: true
    auth_method: "oauth"
    subscription_tier: "plus"    # free|plus|pro|api-only
    cost_tier: "low"             # free|low|medium|high|bundled|pay-per-use

  agy:
    installed: true
    auth_method: "oauth"
    subscription_tier: "google"     # service-managed Google access
    cost_tier: "bundled"

  openrouter:
    enabled: false
    routing_preference: "default"   # default|nitro|floor

  orcarouter:
    enabled: false

cost_optimization:
  strategy: "balanced"  # cost-first|quality-first|balanced
```

### OpenRouter Fallback

OpenRouter provides 400+ models as a universal fallback when direct external CLIs are unavailable:

```bash
# Set up OpenRouter API key
export OPENROUTER_API_KEY="sk-or-..."

# Re-run setup to configure
"$OCTO_ROOT/scripts/orchestrate.sh" setup
```

### OrcaRouter Fallback

OrcaRouter provides a single gateway to many models as a universal fallback when direct external CLIs are unavailable:

```bash
# Set up OrcaRouter API key
export ORCAROUTER_API_KEY="sk-orca-..."

# Re-run setup to configure
"$OCTO_ROOT/scripts/orchestrate.sh" setup
```

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

## Example Workflows

### Research-First Development
```bash
# 1. Explore the problem space
"$OCTO_ROOT/scripts/orchestrate.sh" probe "Authentication patterns for microservices"

# 2. Define the approach (with the path step 1 printed after "Probe synthesis saved to:")
PROBE_SYNTHESIS="<printed probe-synthesis-*.md path>"
"$OCTO_ROOT/scripts/orchestrate.sh" grasp "OAuth2 with JWT for our API" \
  "$PROBE_SYNTHESIS"

# 3. Implement and validate the report from this invocation.
RUN_MARKER=$(mktemp) || exit 1
TANGLE_STATUS=0
OCTOPUS_WORKFLOW_INVOCATION_ID="${RUN_MARKER##*/}" "$OCTO_ROOT/scripts/orchestrate.sh" tangle "Implement OAuth2 authentication" || TANGLE_STATUS=$?
REPORT_STATUS=0
TANGLE_VALIDATION=$("$OCTO_ROOT/scripts/helpers/workflow-result.sh" develop "$RUN_MARKER" "$TANGLE_STATUS") || REPORT_STATUS=$?
rm -f "$RUN_MARKER"
[[ "$REPORT_STATUS" == 0 ]] || exit "$REPORT_STATUS"

# 4. Deliver with that validation report as context.
"$OCTO_ROOT/scripts/orchestrate.sh" ink "Finalize auth implementation" "$TANGLE_VALIDATION" || exit 1
```

### Quick Build (Auto-Routed)
```bash
# Auto-detects "build" intent -> runs tangle + ink
"$OCTO_ROOT/scripts/orchestrate.sh" auto "build a rate limiting middleware"
```

### Full Feature Development
```bash
# All 4 phases in one command
"$OCTO_ROOT/scripts/orchestrate.sh" embrace "Create a user notification system with email and push support"
```

## Best Practices

1. **Start with `embrace`** for new features requiring exploration
2. **Use `probe` alone** when researching before committing to an approach
3. **Use `auto`** for smart routing based on your intent
4. **Chain phases** by passing the previous phase's result file as the second argument for incremental workflows
5. **Run `preflight`** before long workflows to verify dependencies
6. **Review quality gates** in tangle output before proceeding to ink

## Troubleshooting

### Pre-flight check fails
```bash
"$OCTO_ROOT/scripts/orchestrate.sh" preflight
# Verify: codex CLI, agy CLI, and task-relevant provider credentials
```

### Quality gate failures
Tangle phase requires 75% success rate. If failing:
- Break task into smaller subtasks
- Increase the 600-second default with `-t 900`
- Check individual agent logs in `~/.claude-octopus/logs/`

### Reset workspace
```bash
"$OCTO_ROOT/scripts/orchestrate.sh" clean
"$OCTO_ROOT/scripts/orchestrate.sh" init
```
