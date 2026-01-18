# Conflict Avoidance Strategy

## Overview

This document defines strategies to prevent natural language workflow triggers from interfering with standard claude-code basic operations.

## Core Principle

**Natural language workflows should ONLY activate for specific, non-trivial requests that clearly indicate specialized persona intent.**

Basic claude-code operations must continue to work without unexpected workflow invocations.

## Exclusion Criteria

### 1. Basic File Operations

**NEVER trigger workflows for:**

| Pattern | Reason | Examples |
|---------|--------|----------|
| `read <file>` | Basic file operation | "read the config file", "read src/app.js" |
| `write <file>` | Basic file operation | "write to output.txt", "write the results" |
| `edit <file>` | Basic file operation | "edit the README", "edit this function" |
| `create <file>` | Basic file creation | "create a new file", "create component.tsx" |
| `delete <file>` | Basic file deletion | "delete temp files", "remove old code" |

**Exclusion Rule:**
```python
def is_basic_file_op(query: str) -> bool:
    """Check if query is a basic file operation."""
    basic_ops = ['read', 'write', 'edit', 'create', 'delete', 'remove']
    file_indicators = ['file', 'folder', '.js', '.py', '.md', '/']

    query_lower = query.lower()

    for op in basic_ops:
        if query_lower.startswith(op) or f' {op} ' in query_lower:
            for indicator in file_indicators:
                if indicator in query_lower:
                    return True
    return False
```

### 2. Simple Code Tasks

**NEVER trigger workflows for:**

| Pattern | Reason | Examples |
|---------|--------|----------|
| `fix bug in <location>` | Too simple | "fix bug in login.js" |
| `add function <name>` | Straightforward task | "add function to validate email" |
| `update <component>` | Simple modification | "update the header component" |
| `change <variable>` | Basic edit | "change the API endpoint URL" |

**Distinction:** These are implementation tasks, not architectural/review requests.

**Correct Triggers:**
- ❌ "fix the authentication bug" → Regular claude-code
- ✅ "debug why authentication is failing and provide root cause analysis" → `debugger` persona
- ❌ "add a function to sort users" → Regular claude-code
- ✅ "design an API for user management with best practices" → `backend-architect` persona

### 3. Navigation and Search

**NEVER trigger workflows for:**

| Pattern | Reason | Examples |
|---------|--------|----------|
| `show me <location>` | Basic navigation | "show me the routes", "show the config" |
| `find <pattern>` | Basic search | "find all TODO comments", "find uses of API" |
| `search for <term>` | Basic search | "search for 'authenticate'" |
| `list <items>` | Basic listing | "list all components", "list dependencies" |
| `where is <item>` | Basic location | "where is the database config" |

**Exclusion Rule:**
```python
def is_navigation_query(query: str) -> bool:
    """Check if query is basic navigation/search."""
    nav_verbs = ['show', 'find', 'search', 'list', 'where', 'locate', 'display']
    query_lower = query.lower()

    return any(query_lower.startswith(verb) or f' {verb} ' in query_lower
               for verb in nav_verbs)
```

### 4. Version Control Operations

**NEVER trigger workflows for:**

| Pattern | Reason | Examples |
|---------|--------|----------|
| `commit <message>` | Basic git operation | "commit the changes" |
| `push <branch>` | Basic git operation | "push to origin main" |
| `pull <branch>` | Basic git operation | "pull latest from main" |
| `checkout <branch>` | Basic git operation | "checkout develop branch" |

**Exception:** CI/CD setup requests → `deployment-engineer`
- ✅ "set up automated deployment pipeline"
- ✅ "configure GitHub Actions for testing"

### 5. General Questions

**NEVER trigger workflows for:**

| Pattern | Reason | Examples |
|---------|--------|----------|
| `how do I <task>` | Learning question | "how do I install pytest" |
| `what is <concept>` | Informational query | "what is GraphQL" |
| `why <phenomenon>` | Explanation request | "why is this slow" |
| `explain <topic>` | Educational request | "explain async/await" |

**Exception:** Context matters
- ❌ "explain how authentication works" → Informational
- ✅ "explain the architecture of our authentication system" → Could be `docs-architect`
- ❌ "what is a microservice" → Informational
- ✅ "design a microservices architecture for our platform" → `backend-architect`

## Specificity Requirements

### Minimum Phrase Length

**Rule:** Triggers must be 2+ words AND contain specific intent signals.

```python
def meets_specificity_threshold(query: str) -> bool:
    """Check if query meets minimum specificity."""
    words = query.split()

    # Must be at least 2 words
    if len(words) < 2:
        return False

    # Must contain specific action + domain term
    specific_actions = [
        'design', 'architect', 'review', 'audit', 'optimize',
        'generate', 'document', 'analyze', 'synthesize'
    ]

    domain_terms = [
        'api', 'architecture', 'security', 'performance', 'database',
        'infrastructure', 'testing', 'deployment', 'documentation'
    ]

    has_action = any(action in query.lower() for action in specific_actions)
    has_domain = any(term in query.lower() for domain in domain_terms)

    return has_action and has_domain
```

### Context Enrichment

Some phrases require additional context:

**Ambiguous:** "review this"
- With context: Current file is security-critical code → Consider `security-auditor`
- With context: Current file is documentation → Regular review
- **Default:** Regular claude-code review (don't assume specialized workflow)

**Ambiguous:** "optimize this"
- With context: User mentions "slow queries" → `performance-engineer`
- With context: User mentions "reduce bundle size" → `performance-engineer`
- Without context: Could be code quality → Regular claude-code

## False Positive Risk Assessment

### Testing Framework

Test potential triggers against known false positive scenarios:

```python
FALSE_POSITIVE_TEST_CASES = [
    # Should NOT trigger workflows
    ("read the API documentation", None),
    ("find all security issues", None),  # Too vague without file context
    ("show me the test files", None),
    ("commit and push changes", None),
    ("how do I write a test", None),
    ("fix the bug in auth", None),
    ("add error handling", None),

    # SHOULD trigger workflows
    ("review the code for security vulnerabilities", "security-auditor"),
    ("design a REST API for user management", "backend-architect"),
    ("generate comprehensive system documentation", "docs-architect"),
    ("optimize database query performance", "performance-engineer"),
    ("automate the testing with pytest", "test-automator")
]

def test_false_positives():
    """Validate that triggers don't match basic operations."""
    for query, expected_persona in FALSE_POSITIVE_TEST_CASES:
        result = categorize_query(query)
        if expected_persona is None:
            assert len(result) == 0, f"False positive: {query}"
        else:
            assert result[0][0] == expected_persona, f"Wrong match: {query}"
```

## Conflict Detection Methodology

### 1. Pattern Overlap Analysis

Identify overlapping terms between basic operations and workflow triggers:

| Term | Basic Operation | Workflow Trigger |
|------|----------------|------------------|
| "review" | "review file content" | "review code for quality" |
| "check" | "check if file exists" | "check for vulnerabilities" |
| "analyze" | "analyze git log" | "analyze system architecture" |
| "test" | "test if feature works" | "automate testing framework" |
| "document" | "document this function" | "generate technical documentation" |

**Resolution Strategy:**
- Require specific qualifiers for workflow triggers
- Use length and complexity heuristics
- Default to basic operation on ambiguity

### 2. Whitelisting vs Blacklisting

**Approach:** Hybrid model

**Whitelist (Explicit Triggers):**
- Specific phrase combinations guaranteed to activate workflows
- High confidence, low false positive risk
- Examples: "security audit", "architecture design", "performance optimization"

**Blacklist (Explicit Exclusions):**
- Patterns that must NEVER activate workflows
- Protect basic claude-code operations
- Examples: Single-word commands, basic file ops, simple navigation

```python
# Whitelist: High-confidence triggers
WHITELIST_TRIGGERS = {
    'security-auditor': [
        'security audit',
        'vulnerability assessment',
        'penetration test',
        'OWASP check'
    ],
    'backend-architect': [
        'API design',
        'microservices architecture',
        'design REST API',
        'architect backend system'
    ],
    # ... more personas
}

# Blacklist: Never trigger workflows
BLACKLIST_PATTERNS = [
    r'^(read|write|edit|create|delete)\s',  # File operations
    r'^(show|find|search|list|where)\s',    # Navigation
    r'^(commit|push|pull|checkout)\s',      # Version control
    r'^(how|what|why|when|explain)\s',      # Questions
    r'^\w+$'  # Single words
]
```

### 3. User Override Mechanism

Allow users to:
1. **Explicitly invoke:** "@code-reviewer review this" (always triggers)
2. **Explicitly suppress:** "just show me the file" (never triggers)
3. **Confirm ambiguous:** Prompt user when confidence is medium (0.5-0.7)

## Confidence Threshold Tuning

### Three-tier System

```python
class ConfidenceLevel:
    HIGH = 0.8      # Auto-trigger workflow
    MEDIUM = 0.5    # Prompt user for confirmation
    LOW = 0.3       # Don't trigger, use regular claude-code

def should_trigger_workflow(query: str) -> Tuple[bool, Optional[str]]:
    """
    Determine if a workflow should be triggered.

    Returns:
        (should_trigger, persona_id or None)
    """
    # Check blacklist first
    if matches_blacklist(query):
        return (False, None)

    # Check whitelist for high-confidence matches
    persona = check_whitelist(query)
    if persona:
        return (True, persona)

    # Analyze with ML/heuristics
    matches = categorize_query(query)

    if not matches:
        return (False, None)

    persona_id, confidence = matches[0]

    if confidence >= ConfidenceLevel.HIGH:
        return (True, persona_id)
    elif confidence >= ConfidenceLevel.MEDIUM:
        # TODO: Implement user confirmation prompt
        return (False, None)  # Default to safe side
    else:
        return (False, None)
```

## Testing and Validation

### Comprehensive Test Suite

```python
def test_conflict_avoidance():
    """Test all conflict scenarios."""

    # Test basic operations don't trigger
    assert not should_trigger("read src/app.js")[0]
    assert not should_trigger("write to output.txt")[0]
    assert not should_trigger("find all TODOs")[0]
    assert not should_trigger("commit changes")[0]

    # Test ambiguous queries default to safe
    assert not should_trigger("review this")[0]
    assert not should_trigger("check it")[0]
    assert not should_trigger("analyze")[0]

    # Test specific triggers work
    assert should_trigger("security audit of API")[0]
    assert should_trigger("design microservices architecture")[0]
    assert should_trigger("optimize query performance")[0]

    # Test edge cases
    assert not should_trigger("design a logo")[0]  # Not code architecture
    assert should_trigger("design API architecture")[0]
```

---

**Next Steps:** Proceed to `06-implementation-guide.md` for step-by-step execution instructions.
