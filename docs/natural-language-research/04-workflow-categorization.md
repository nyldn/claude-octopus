# Workflow Categorization

## Overview

This document maps natural language keyword patterns to specific `@claude-octopus` personas, enabling automatic workflow detection from user queries.

## Persona Mapping Framework

### Strategy Analyst

**Persona ID:** `claude-octopus:personas:strategy-analyst`

**Primary Keywords (High Confidence):**
- "market analysis"
- "competitive intelligence"
- "business case"
- "strategic planning"
- "market sizing"
- "competitive landscape"
- "SWOT analysis"
- "business strategy"
- "market research"
- "strategic recommendations"

**Secondary Contextual Signals:**
- Mentions of competitors, market segments, or industry trends
- Financial projections or revenue models
- Business model discussions
- Porter's Five Forces, TAM/SAM/SOM analysis

**Anti-patterns (DO NOT Match):**
- Generic "analyze" without business context
- Technical performance analysis
- Code or system analysis

**Example Queries:**
```
✅ "analyze the competitive landscape for our product"
✅ "create a business case for the new feature"
✅ "research market size for SaaS tools"
✅ "perform SWOT analysis of our go-to-market strategy"
❌ "analyze this database query" (performance, not strategy)
❌ "analyze code structure" (code review, not business)
```

**Confidence Scoring:**
- High (>0.8): Explicit mention of business/market/competitive + analysis
- Medium (0.5-0.8): Business context + strategic verbs
- Low (<0.5): Generic strategic terms without clear business focus

---

### Backend Architect

**Persona ID:** `claude-octopus:personas:backend-architect`

**Primary Keywords:**
- "API design"
- "microservices architecture"
- "REST API"
- "GraphQL schema"
- "service architecture"
- "distributed systems"
- "backend architecture"
- "event-driven architecture"
- "service mesh"
- "API gateway"

**Secondary Contextual Signals:**
- Mentions of HTTP methods, endpoints, routes
- Database + API integration discussions
- Service boundaries and communication patterns
- Authentication/authorization in API context

**Anti-patterns:**
- Frontend API consumption
- Simple CRUD operations without architecture discussion
- Database-only design (use database-architect)

**Example Queries:**
```
✅ "design a REST API for user management"
✅ "architect a microservices system for e-commerce"
✅ "create GraphQL schema for the data model"
✅ "design event-driven architecture for order processing"
❌ "fetch data from the API" (implementation, not architecture)
❌ "design the database schema" (database-architect)
```

**Confidence Scoring:**
- High (>0.8): Explicit API/service architecture + design/architect verb
- Medium (0.5-0.8): Backend + design/structure context
- Low (<0.5): Generic API mentions without architectural scope

---

### Code Reviewer

**Persona ID:** `claude-octopus:personas:code-reviewer`

**Primary Keywords:**
- "review code"
- "code review"
- "audit code"
- "check code quality"
- "review pull request"
- "review PR"
- "analyze code"
- "inspect implementation"
- "code quality check"
- "review changes"

**Secondary Contextual Signals:**
- References to files, functions, or specific code
- Quality concerns (readability, maintainability)
- Best practices, patterns, anti-patterns
- Pull request context

**Anti-patterns:**
- "Review requirements" or "review documentation"
- Performance profiling (use performance-engineer)
- Security-specific audits (use security-auditor)

**Example Queries:**
```
✅ "review this code for quality issues"
✅ "audit the implementation of user authentication"
✅ "check this pull request for best practices"
✅ "review the code changes in src/api/"
❌ "review the deployment logs" (operations, not code review)
❌ "review for security vulnerabilities" (security-auditor)
```

**Confidence Scoring:**
- High (>0.8): "review" + "code"/"PR"/"implementation"
- Medium (0.5-0.8): Quality/audit verbs + code context
- Low (<0.5): Generic review without code specificity

---

### Research Synthesizer

**Persona ID:** `claude-octopus:personas:research-synthesizer`

**Primary Keywords:**
- "literature review"
- "research synthesis"
- "synthesize research"
- "research gaps"
- "thematic analysis"
- "multi-source synthesis"
- "academic research"
- "research summary"
- "scholarly analysis"
- "research findings"

**Secondary Contextual Signals:**
- Multiple sources, papers, or articles mentioned
- Academic or scholarly context
- Citation or reference discussions
- Knowledge synthesis across domains

**Anti-patterns:**
- Business/market research (use strategy-analyst)
- Simple web searches or information gathering
- Technical documentation research

**Example Queries:**
```
✅ "synthesize research from multiple academic papers on ML"
✅ "perform literature review on neural architecture search"
✅ "identify research gaps in federated learning"
✅ "analyze themes across 10 research papers"
❌ "research how to implement OAuth" (technical research, not synthesis)
❌ "research competitor products" (strategy-analyst)
```

**Confidence Scoring:**
- High (>0.8): "literature review" or "research synthesis" explicit
- Medium (0.5-0.8): Academic/scholarly + synthesis/analysis context
- Low (<0.5): Generic "research" without synthesis component

---

### Test Automator

**Persona ID:** `claude-octopus:personas:test-automator`

**Primary Keywords:**
- "automate testing"
- "test automation"
- "write tests"
- "generate tests"
- "unit tests"
- "integration tests"
- "test coverage"
- "test suite"
- "automated testing"
- "testing framework"

**Secondary Contextual Signals:**
- Testing frameworks (Jest, Pytest, JUnit)
- CI/CD testing context
- Coverage percentages or metrics
- Test types (unit, integration, e2e)

**Anti-patterns:**
- Manual testing instructions
- User acceptance testing without automation
- Simple "test this" without automation context

**Example Queries:**
```
✅ "write unit tests for the authentication module"
✅ "automate integration testing for the API"
✅ "generate test suite with 80% coverage"
✅ "set up automated testing with Pytest"
❌ "test if the login works" (manual testing)
❌ "create test user accounts" (data setup, not test automation)
```

**Confidence Scoring:**
- High (>0.8): "automate" + "test" or explicit test generation
- Medium (0.5-0.8): Test framework + automation context
- Low (<0.5): Generic "test" without automation signals

---

### Docs Architect

**Persona ID:** `claude-octopus:personas:docs-architect`

**Primary Keywords:**
- "generate documentation"
- "create documentation"
- "document architecture"
- "technical documentation"
- "API documentation"
- "architecture guide"
- "system documentation"
- "document codebase"
- "write technical docs"
- "documentation from code"

**Secondary Contextual Signals:**
- References to README, docs folders
- API reference, architecture diagrams
- Technical manual, handbook context
- From-scratch or comprehensive documentation

**Anti-patterns:**
- Code comments only
- Simple README updates
- User-facing docs (unless technical depth)

**Example Queries:**
```
✅ "generate comprehensive API documentation from codebase"
✅ "create architecture guide for the system"
✅ "document the microservices architecture"
✅ "write technical documentation for the platform"
❌ "add a comment to this function" (simple comment, not docs)
❌ "update the README with install instructions" (too simple)
```

**Confidence Scoring:**
- High (>0.8): "generate"/"create" + "documentation" + technical scope
- Medium (0.5-0.8): Documentation + architecture/system context
- Low (<0.5): Simple doc updates without comprehensive scope

---

### Performance Engineer

**Persona ID:** `claude-octopus:personas:performance-engineer`

**Primary Keywords:**
- "optimize performance"
- "performance optimization"
- "improve performance"
- "reduce latency"
- "speed up"
- "performance tuning"
- "profile performance"
- "benchmark"
- "performance bottleneck"
- "scalability optimization"

**Secondary Contextual Signals:**
- Mentions of metrics (latency, throughput, response time)
- Performance tools (profilers, monitoring)
- Caching, indexing, query optimization
- Load testing, stress testing

**Anti-patterns:**
- User experience improvements without performance metrics
- Code quality improvements
- Generic "make it better"

**Example Queries:**
```
✅ "optimize database query performance"
✅ "reduce API response latency"
✅ "profile and improve application performance"
✅ "benchmark different caching strategies"
❌ "improve the user interface" (UX, not performance)
❌ "make the code cleaner" (quality, not performance)
```

**Confidence Scoring:**
- High (>0.8): Performance-specific verb + metrics/context
- Medium (0.5-0.8): Optimization + performance indicators
- Low (<0.5): Generic "improve" without performance context

---

### Debugger

**Persona ID:** `claude-octopus:personas:debugger`

**Primary Keywords:**
- "debug error"
- "fix bug"
- "investigate error"
- "troubleshoot issue"
- "diagnose problem"
- "debug failure"
- "trace error"
- "root cause analysis"
- "why is failing"
- "error investigation"

**Secondary Contextual Signals:**
- Error messages or stack traces
- "not working", "failing", "broken"
- Logs, exceptions, crashes
- Test failures

**Anti-patterns:**
- Feature requests disguised as bugs
- Known issues requiring implementation
- Optimization (not bugs)

**Example Queries:**
```
✅ "debug why the authentication is failing"
✅ "investigate the 500 error in production"
✅ "troubleshoot the test failures"
✅ "find root cause of the memory leak"
❌ "add error handling" (feature, not debugging)
❌ "optimize slow query" (performance, not debugging)
```

**Confidence Scoring:**
- High (>0.8): Debug/troubleshoot + specific error/failure
- Medium (0.5-0.8): Investigation + problem context
- Low (<0.5): Generic "fix" without clear bug context

---

### Security Auditor

**Persona ID:** `claude-octopus:personas:security-auditor`

**Primary Keywords:**
- "security audit"
- "security scan"
- "vulnerability assessment"
- "check vulnerabilities"
- "security review"
- "penetration test"
- "security analysis"
- "threat modeling"
- "security compliance"
- "OWASP check"

**Secondary Contextual Signals:**
- Authentication/authorization security
- Injection attacks (SQL, XSS, etc.)
- Security frameworks (OWASP, NIST)
- Compliance standards (GDPR, HIPAA, SOC2)

**Anti-patterns:**
- Generic code review
- Access control implementation (without security focus)
- Performance of security features

**Example Queries:**
```
✅ "audit the API for security vulnerabilities"
✅ "check for SQL injection vulnerabilities"
✅ "perform security review of authentication"
✅ "scan codebase for OWASP top 10 issues"
❌ "review the auth code" (code-reviewer unless security specified)
❌ "implement OAuth" (implementation, not audit)
```

**Confidence Scoring:**
- High (>0.8): "security" + audit/scan/vulnerability
- Medium (0.5-0.8): Security context + review/check
- Low (<0.5): Generic security mentions without audit intent

---

### Cloud Architect

**Persona ID:** `claude-octopus:personas:cloud-architect`

**Primary Keywords:**
- "cloud architecture"
- "AWS infrastructure"
- "cloud design"
- "infrastructure as code"
- "Terraform"
- "CloudFormation"
- "Kubernetes architecture"
- "cloud migration"
- "multi-cloud"
- "serverless architecture"

**Secondary Contextual Signals:**
- Cloud providers (AWS, Azure, GCP)
- Infrastructure tools (Terraform, Pulumi, CDK)
- Container orchestration
- Cloud-native patterns

**Anti-patterns:**
- Simple cloud deployments without architecture
- Cloud service usage questions
- DevOps without infrastructure design

**Example Queries:**
```
✅ "design AWS infrastructure for microservices"
✅ "architect a multi-cloud deployment strategy"
✅ "create Terraform modules for cloud resources"
✅ "design serverless architecture on AWS Lambda"
❌ "deploy to AWS" (deployment, not architecture)
❌ "how do I use S3?" (usage question, not architecture)
```

**Confidence Scoring:**
- High (>0.8): Cloud + architecture/design + infrastructure
- Medium (0.5-0.8): Cloud platform + design/structure context
- Low (<0.5): Generic cloud mentions without architecture scope

---

### Database Architect

**Persona ID:** `claude-octopus:personas:database-architect`

**Primary Keywords:**
- "database design"
- "schema design"
- "data model"
- "database architecture"
- "database schema"
- "data modeling"
- "normalize schema"
- "database structure"
- "ERD design"
- "database selection"

**Secondary Contextual Signals:**
- Database technologies (PostgreSQL, MongoDB, etc.)
- Normalization, indexing strategies
- Data relationships, foreign keys
- SQL vs NoSQL selection

**Anti-patterns:**
- Query optimization (use performance-engineer)
- Database administration tasks
- Simple CRUD operations

**Example Queries:**
```
✅ "design database schema for e-commerce platform"
✅ "create data model for user management"
✅ "design normalized database structure"
✅ "choose between SQL and NoSQL for use case"
❌ "optimize this query" (performance-engineer)
❌ "backup the database" (admin task)
```

**Confidence Scoring:**
- High (>0.8): Database + design/schema/model/architecture
- Medium (0.5-0.8): Data + structure/design context
- Low (<0.5): Generic database mentions without design scope

---

### Deployment Engineer

**Persona ID:** `claude-octopus:personas:deployment-engineer`

**Primary Keywords:**
- "CI/CD pipeline"
- "deployment automation"
- "GitHub Actions"
- "deployment pipeline"
- "continuous deployment"
- "GitOps"
- "release automation"
- "deployment workflow"
- "ArgoCD"
- "deployment strategy"

**Secondary Contextual Signals:**
- CI/CD tools (GitHub Actions, GitLab CI, Jenkins)
- GitOps tools (ArgoCD, Flux)
- Deployment strategies (blue-green, canary)
- Container registries, artifact management

**Anti-patterns:**
- Manual deployment instructions
- Simple "deploy" commands without automation
- Infrastructure provisioning (use cloud-architect)

**Example Queries:**
```
✅ "set up CI/CD pipeline with GitHub Actions"
✅ "automate deployment with ArgoCD"
✅ "create deployment workflow for microservices"
✅ "implement blue-green deployment strategy"
❌ "deploy the app to production" (manual deploy)
❌ "provision AWS infrastructure" (cloud-architect)
```

**Confidence Scoring:**
- High (>0.8): CI/CD + pipeline/automation
- Medium (0.5-0.8): Deployment + automation context
- Low (<0.5): Generic deploy without automation signals

---

## Categorization Algorithm

### Multi-label Classification

Many queries may match multiple personas. Use confidence scoring to rank:

```python
def categorize_query(query: str, threshold: float = 0.5) -> List[Tuple[str, float]]:
    """
    Categorize a user query into persona(s).

    Returns list of (persona_id, confidence_score) tuples.
    """
    matches = []

    for persona_id, persona_config in PERSONAS.items():
        score = calculate_persona_match(query, persona_config)
        if score >= threshold:
            matches.append((persona_id, score))

    # Sort by confidence descending
    return sorted(matches, key=lambda x: x[1], reverse=True)
```

### Example Multi-label Cases

**Query:** "review API security vulnerabilities"
- `security-auditor` (0.9) - Primary match
- `code-reviewer` (0.6) - Secondary match
- **Action:** Invoke `security-auditor` (highest confidence)

**Query:** "design and document microservices architecture"
- `backend-architect` (0.85) - Design focus
- `docs-architect` (0.75) - Documentation focus
- **Action:** Could invoke both, or prioritize `backend-architect`

---

## Implementation Reference

```python
PERSONA_TRIGGERS = {
    'claude-octopus:personas:strategy-analyst': {
        'high_confidence': [
            'market analysis', 'competitive intelligence', 'business case',
            'strategic planning', 'market sizing', 'SWOT analysis'
        ],
        'medium_confidence': [
            'business strategy', 'competitive landscape', 'market research'
        ],
        'context_signals': ['competitor', 'market', 'revenue', 'business model'],
        'anti_patterns': ['technical analysis', 'code analysis']
    },
    # ... (continue for all personas)
}
```

---

**Next Steps:** Proceed to `05-conflict-avoidance-strategy.md` to ensure these triggers don't interfere with standard claude-code operations.
