# Claude Octopus Agent Catalog

> *32 specialized personas, infinite possibilities. But which one grabs YOUR problem?* 🐙

**Note on Permissions:** Current releases prompt before background provider execution so you can approve Codex or Gemini usage explicitly.

---

## TL;DR - Which Tentacle Do I Need?

| When You Want To... | Reach For This Tentacle | Why This One? |
|---------------------|-------------------------|---------------|
| Design a REST/GraphQL API | `backend-architect` | Microservices maestro |
| Find security vulnerabilities | `security-auditor` | OWASP whisperer |
| Debug failing tests | `debugger` | Stack trace detective |
| Implement with TDD | `tdd-orchestrator` | Red-green-refactor guru |
| Review code quality | `code-reviewer` | Best practices enforcer |
| Write Python code | `python-pro` | Pythonic perfection |
| Write TypeScript | `typescript-pro` | Type safety fanatic |
| Design database schema | `database-architect` | Data modeling master |
| Research AI/LLM patterns | `ai-engineer` | Prompt engineering pro |
| Optimize performance | `performance-engineer` | Latency hunter |
| Synthesize user research | `ux-researcher` | Empathy tentacle 🆕 |
| Develop business strategy | `strategy-analyst` | Framework master 🆕 |
| Write literature review | `research-synthesizer` | Knowledge weaver 🆕 |
| Draft research papers | `academic-writer` | Citation ninja 🆕 |
| Create exec summaries | `exec-communicator` | Boardroom whisperer 🆕 |
| Write PRDs/user stories | `product-writer` | Requirements master 🆕 |
| Plan marketing campaigns | `marketing-strategist` | Growth funnel guru 🆕 |
| Build financial models | `finance-analyst` | Spreadsheet surgeon 🆕 |
| Review compliance/GDPR | `legal-compliance-advisor` | Regulatory navigator 🆕 |
| Design UI/UX systems | `ui-ux-designer` | Design intelligence 🆕 |

**Still unsure?** Just describe what you need - Claude Octopus auto-routes to the right tentacle! 🦑

Knowledge-worker personas for researchers, consultants, and product managers are also included. [See Knowledge Workers Guide →](KNOWLEDGE-WORKERS.md)

---

## Table of Contents

1. [By Development Phase](#by-development-phase) - Double Diamond workflow
2. [By Domain](#by-domain) - Backend, Frontend, Quality, Ops
3. [Knowledge Work](#knowledge-work) - Research, consulting, writing
4. [Top 10 Tentacles](#top-10-tentacles) - The heavy hitters
5. [Cost Tiers](#cost-tiers) - Token budget awareness
6. [Common Workflows](#common-workflows) - Multi-tentacle patterns
7. [The Principles (Don't Invoke Directly)](#the-principles-internal-use-only) - Quality checklists
8. [Decision Tree](#decision-tree) - When all else fails

---

## By Development Phase

Claude Octopus follows the **Double Diamond** methodology:

```
     DISCOVER         DEFINE         DEVELOP          DELIVER
      (probe)         (grasp)        (tangle)          (ink)

    \         /     \         /     \         /     \         /
     \  🔍  /       \  🎯  /       \  🔧  /       \  ✅  /
      \ 🦑 /         \    /         \ 🦑 /         \    /
       \  /           \  /           \  /           \  /
        \/             \/             \/             \/

   Diverge then      Converge to      Diverge with     Converge to
    converge          problem          solutions        delivery
```

### 🔍 Probe Phase: Research & Discovery

**Use when:** Starting a project, exploring options, gathering requirements

| Tentacle | Superpower | Example Prompt |
|----------|------------|----------------|
| `ai-engineer` | LLM/RAG patterns, prompt engineering | "Research OAuth 2.0 patterns for multi-tenant SaaS" |
| `business-analyst` | Requirements, metrics, stakeholder analysis | "Analyze user authentication requirements" |
| `context-manager` | Multi-agent coordination | "Coordinate research across multiple domains" |

**Pro tip:** Probe tentacles are cheap (sonnet/inherit) - fire liberally!

---

### 🎯 Grasp Phase: Architecture & Design

**Use when:** Planning architecture, defining system design, creating blueprints

| Tentacle | Superpower | Example Prompt |
|----------|------------|----------------|
| `backend-architect` ⭐ | API design, microservices, distributed systems | "Design a REST API for user authentication" |
| `frontend-developer` | React 19, Next.js 15, UI/UX patterns | "Design component architecture for dashboard" |
| `database-architect` | Schema design, migrations, normalization | "Design user and session tables" |
| `cloud-architect` | AWS/GCP/Azure, IaC, cost optimization | "Plan multi-region deployment" |
| `graphql-architect` | Federation, resolvers, schema design | "Design GraphQL schema for e-commerce" |

**Pro tip:** These tentacles are premium (opus/inherit) - they're worth it for architecture decisions.

---

### 🔧 Tangle Phase: Development & Implementation

**Use when:** Writing code, implementing features, building solutions

| Tentacle | Superpower | Example Prompt |
|----------|------------|----------------|
| `tdd-orchestrator` ⭐ | Test-driven development, red-green-refactor | "Implement user registration with TDD" |
| `debugger` ⭐ | Error analysis, stack traces, root cause | "Debug JWT validation failures" |
| `devops-troubleshooter` | K8s debugging, log analysis, infra | "Fix deployment issues in staging" |
| `python-pro` | Python 3.12+, FastAPI, async | "Implement FastAPI authentication" |
| `typescript-pro` | Advanced types, generics, strict mode | "Implement TypeScript SDK" |

**Pro tip:** Tangle has a **75% quality gate** - multiple tentacles validate before delivery.

---

### ✅ Ink Phase: Review & Delivery

**Use when:** Code review, security audit, performance optimization, shipping

| Tentacle | Superpower | Example Prompt |
|----------|------------|----------------|
| `code-reviewer` ⭐ | Best practices, architecture review | "Review authentication module" |
| `security-auditor` ⭐ | OWASP, DevSecOps, threat modeling | "Audit for SQL injection vulnerabilities" |
| `test-automator` | Unit/integration/E2E test generation | "Generate test coverage for auth" |
| `performance-engineer` | Profiling, benchmarking, Core Web Vitals | "Find N+1 query issues" |
| `deployment-engineer` | GitHub Actions, ArgoCD, GitOps | "Set up CI/CD pipeline" |

**Pro tip:** Ink tentacles work with the `squeeze` command for adversarial review!

---

## By Domain

### Backend Development 🔌

```
General Backend    → backend-architect (inherit - adapts to complexity)
Database Focus     → database-architect (opus - critical decisions)
GraphQL API        → graphql-architect (opus - schema design)
Python Backend     → python-pro (opus - advanced patterns)
Node.js Backend    → typescript-pro (opus - type safety)
```

### Frontend Development 🎨

```
React/Next.js      → frontend-developer (inherit - adapts)
TypeScript         → typescript-pro (opus - complex types)
Performance        → performance-engineer (inherit - profiling)
```

### Quality & Security 🛡️

```
Code Quality       → code-reviewer (opus - comprehensive)
Security           → security-auditor (opus - critical)
Testing            → test-automator (sonnet - generation)
Performance        → performance-engineer (inherit - profiling)
```

### Operations & Infrastructure ⚙️

```
Cloud/AWS/GCP      → cloud-architect (opus - critical decisions)
Kubernetes/Docker  → deployment-engineer (haiku - fast)
Troubleshooting    → devops-troubleshooter (sonnet - specialized)
Incidents          → incident-responder (sonnet - SRE)
```

### Documentation & Diagrams 📚

```
Technical Docs     → docs-architect (sonnet - writing)
Flowcharts         → mermaid-expert (haiku - simple)
```

---

## Knowledge Work

> *When your deliverable isn't code, but crystallized knowledge.* 🎓

Claude Octopus also includes specialized agents for researchers, consultants, designers, marketers, and product managers.

### 🎯 UX Research

```
User interviews    → ux-researcher (opus - synthesis)
Journey mapping    → ux-researcher (opus - empathy)
Pain points        → ux-researcher (opus - definition)
```

### 📊 Strategy & Consulting

```
Market analysis    → strategy-analyst (opus - frameworks)
Business cases     → strategy-analyst (opus - quantification)
Exec summaries     → exec-communicator (sonnet - clarity)
```

### 📚 Academic & Research

```
Literature review  → research-synthesizer (opus - synthesis)
Gap analysis       → research-synthesizer (opus - identification)
Academic writing   → academic-writer (sonnet - formatting)
```

### 📋 Product Management

```
PRDs & specs       → product-writer (sonnet - clarity)
User stories       → product-writer (sonnet - structure)
Acceptance criteria→ product-writer (sonnet - precision)
```

### 📣 Marketing & Growth

```
Campaign planning  → marketing-strategist (sonnet - channels)
Growth funnels     → marketing-strategist (sonnet - optimization)
SEO & content      → marketing-strategist (sonnet - strategy)
```

### 💰 Finance & Pricing

```
Financial models   → finance-analyst (sonnet - projections)
Unit economics     → finance-analyst (sonnet - metrics)
Pricing strategy   → finance-analyst (sonnet - optimization)
```

### 🎨 UI/UX Design

```
Design systems     → ui-ux-designer (sonnet - BM25 intelligence)
Color & typography → ui-ux-designer (sonnet - data-driven)
Component specs    → ui-ux-designer (sonnet - handoff)
```

### ⚖️ Legal & Compliance

```
GDPR/CCPA review   → legal-compliance-advisor (sonnet - regulations)
SOC 2 readiness    → legal-compliance-advisor (sonnet - controls)
Contract review    → legal-compliance-advisor (sonnet - risk)
```

**Deep dive:** See the full [Knowledge Workers Guide →](KNOWLEDGE-WORKERS.md)

---

## Top 10 Tentacles

The heavy hitters, based on real-world usage:

### 1. 🏗️ backend-architect
**Model:** inherit (adapts to complexity)

**Superpower:** API design, microservices architecture, distributed systems

**When to use:**
- Designing REST/GraphQL/gRPC APIs
- Architecting microservices systems
- Defining service boundaries and communication patterns
- Planning event-driven architectures

**Avoid if:**
- Simple CRUD operations (just implement directly)
- Frontend-only work (use `frontend-developer`)
- Database schema design (use `database-architect` first)

---

### 2. 🔍 code-reviewer
**Model:** opus (complex reasoning)

**Superpower:** Code quality, best practices, architecture review

**When to use:**
- PR reviews (pairs with `/octo:review` skill)
- Architecture validation
- Best practices enforcement

**Avoid if:**
- Security-focused review (use `security-auditor`)
- Performance-focused review (use `performance-engineer`)

---

### 3. 🐛 debugger
**Model:** sonnet (specialized analysis)

**Superpower:** Error analysis, stack traces, root cause identification

**When to use:**
- Failing tests or production errors
- Understanding cryptic stack traces
- Root cause analysis

**Avoid if:**
- Infrastructure issues (use `devops-troubleshooter`)

---

### 4. 🛡️ security-auditor
**Model:** opus (critical analysis)

**Superpower:** OWASP Top 10, vulnerability scanning, threat modeling

**When to use:**
- Security audits (pairs with `squeeze` command)
- Finding vulnerabilities in auth/payment code
- OWASP compliance checks

---

### 5. 🧪 tdd-orchestrator
**Model:** opus (multi-step reasoning)

**Superpower:** Test-driven development, red-green-refactor

**When to use:**
- Building new features test-first
- Comprehensive test coverage
- Refactoring with confidence

---

### 6. 🎨 frontend-developer
**Model:** inherit (adapts to complexity)

**Superpower:** React 19, Next.js 15, modern UI patterns

**When to use:**
- React component architecture
- Server Components and Client Components
- State management decisions

---

### 7. 🗃️ database-architect
**Model:** opus (critical decisions)

**Superpower:** Schema design, migrations, query optimization

**When to use:**
- New database schema design
- Migration planning
- Query performance issues

---

### 8. ⚡ performance-engineer
**Model:** inherit (adapts to profiling depth)

**Superpower:** Profiling, benchmarking, Core Web Vitals

**When to use:**
- N+1 query hunting
- API response time optimization
- Memory leak detection

---

### 9. 🐍 python-pro
**Model:** opus (advanced patterns)

**Superpower:** Python 3.12+, FastAPI, async programming

**When to use:**
- Python backend development
- FastAPI/Django/Flask services
- Async/await patterns

---

### 10. 📘 typescript-pro
**Model:** opus (complex type systems)

**Superpower:** Advanced types, generics, strict TypeScript

**When to use:**
- Advanced TypeScript type definitions
- Generic types and utility type creation
- Strict TypeScript configuration

---

## Cost Tiers

### 💎 Premium (Opus)
Most expensive, use for critical decisions.

`code-reviewer`, `tdd-orchestrator`, `database-architect`, `security-auditor`, `cloud-architect`, `python-pro`, `typescript-pro`, `graphql-architect`

### 💰 Standard (Sonnet)
Mid-range, good for focused tasks.

`debugger`, `test-automator`, `docs-architect`, `business-analyst`, `devops-troubleshooter`, `incident-responder`, `ui-ux-designer`, `marketing-strategist`, `finance-analyst`, `legal-compliance-advisor`

### 💵 Trivial (Haiku)
Cheapest, use for simple tasks.

`mermaid-expert`, `deployment-engineer`

### 🔄 Adaptive (Inherit)
Auto-selects based on task complexity.

`backend-architect`, `frontend-developer`, `ai-engineer`, `performance-engineer`, `context-manager`

---

## Common Workflows

### 🚀 New Feature Development
```
1. Research     → ai-engineer
2. Design       → backend-architect + database-architect
3. Implement    → tdd-orchestrator
4. Review       → code-reviewer + security-auditor
```

### 🔥 Production Bug Fix
```
1. Respond      → incident-responder
2. Debug        → debugger
3. Fix          → backend-architect
4. Validate     → test-automator
```

### ⚡ Performance Optimization
```
1. Profile      → performance-engineer
2. Database     → database-architect
3. Validate     → performance-engineer
```

### 🛡️ Security Audit
```
1. Scan         → security-auditor
2. Fix          → backend-architect
3. Validate     → security-auditor
```

---

## The Principles (Internal Use Only)

⚠️ **Don't invoke these directly!** They're quality checklists used BY other tentacles.

| Principle | Used By | Purpose |
|-----------|---------|---------|
| `general` | code-reviewer | Correctness, reliability |
| `security` | security-auditor | OWASP, auth patterns |
| `performance` | performance-engineer | Profiling, caching |
| `maintainability` | code-reviewer | Readability, testing |

---

## Decision Tree

See [agent-decision-tree.md](agent-decision-tree.md) for visual flowcharts.

**Quick version:**
```
What phase are you in?
├─ Research/Explore → PROBE tentacles
├─ Design/Plan     → GRASP tentacles
├─ Build/Code      → TANGLE tentacles
└─ Review/Ship     → INK tentacles
```

---

## Quick Links

- **README:** [../README.md](../README.md)
- **Decision Tree:** [agent-decision-tree.md](agent-decision-tree.md)
- **Monthly Review:** [monthly-agent-review.md](monthly-agent-review.md)
- **Personas:** [../agents/personas/](../agents/personas/)

---

<p align="center">
  🐙 <em>"39 tentacles, one purpose: your code, done right."</em> 🐙
</p>
