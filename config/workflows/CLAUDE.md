# Double Diamond Workflow Methodology

This file contains workflow-specific instructions for Claude Octopus.

## What is the Double Diamond?

The Double Diamond is a design methodology with 4 phases:

```
   DISCOVER      DEFINE       DEVELOP      DELIVER

  (diverge)   (converge)   (diverge)   (converge)

    Probe       Grasp        Tangle        Ink

  Research → Requirements → Build → Validate
```

## Workflow Phases

### 1. DISCOVER (Probe) 🔍

**Purpose**: Divergent research and exploration

**Activities**:
- Multi-provider research (Codex + Gemini + Claude)
- Broad ecosystem analysis
- Technology comparison
- Best practices research
- Community insights

**Output**: Research synthesis document

**Workflow**: `probe` or `discover`

### 2. DEFINE (Grasp) 🎯

**Purpose**: Convergent consensus building

**Activities**:
- Synthesize research findings
- Build consensus on approach
- Define requirements clearly
- Identify constraints
- Establish success criteria

**Output**: Consensus document with requirements

**Workflow**: `grasp` or `define`

### 3. DEVELOP (Tangle) 🛠️

**Purpose**: Divergent implementation

**Activities**:
- Multi-provider code generation
- Implementation with quality gates
- Testing and validation
- Security review
- Performance optimization

**Output**: Implementation with validation report

**Workflow**: `tangle` or `develop`

### 4. DELIVER (Ink) ✅

**Purpose**: Convergent final validation

**Activities**:
- Quality assurance
- Final synthesis
- Documentation
- Delivery certification
- User acceptance

**Output**: Final delivery document

**Workflow**: `ink` or `deliver`

## Full Workflow

Use `embrace` to run all 4 phases automatically:

```bash
/octo:embrace "Build user authentication system"
```

## Autonomy Modes

### Supervised (Default)

- User approval required after each phase
- Maximum control and oversight
- Best for critical features

### Semi-Autonomous

- Approval only when quality gates fail
- Balanced approach
- Best for most use cases

### Autonomous

- Runs all 4 phases automatically
- No interruptions
- Best for trusted, low-risk tasks

## Quality Gates

Each phase includes quality checks:

- **Discover**: All providers responded successfully
- **Define**: Consensus achieved (75%+ agreement)
- **Develop**: Security, performance, best practices validated
- **Deliver**: Final quality certification passed

Quality gate failures trigger user review in semi-autonomous mode.

## Session Tracking

Each workflow execution:
- Has unique session ID (`${CLAUDE_SESSION_ID}`)
- Stores results in session-specific directory
- Tracks costs per provider
- Maintains audit trail

## Best Practices

1. **Use Discover for Research** - Don't skip research phase
2. **Define Before Develop** - Clear requirements prevent rework
3. **Quality Gates Matter** - Don't bypass failed checks
4. **Review Synthesis** - Read multi-provider insights carefully
5. **Session Isolation** - Keep workflows in separate sessions
