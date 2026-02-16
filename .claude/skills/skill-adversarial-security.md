---
name: octopus-security
description: Adversarial red team security testing with blue/red team cycle
trigger: |
  Use this skill when the user says "security audit this code", "find vulnerabilities in X",
  "red team review", "pentest this API", or "check for OWASP issues".
execution_mode: enforced
pre_execution_contract:
  - visual_indicators_displayed
validation_gates:
  - orchestrate_sh_executed
  - output_artifact_exists
---

# Adversarial Security Skill

Lightweight wrapper that triggers Claude Octopus squeeze (red team) workflow for comprehensive security testing.

## When This Skill Activates

Auto-invokes when user says:
- "security audit this code"
- "find vulnerabilities in X"
- "red team review"
- "pentest this API"
- "check for OWASP issues"

## What It Does

**Four-Phase Adversarial Testing:**

1. **Blue Team** (Defense): Codex implements secure solution
   - Reviews code for security best practices
   - Identifies attack surface
   - Proposes defenses

2. **Red Team** (Attack): Gemini finds vulnerabilities
   - Attempts to break defenses
   - Generates exploit proofs of concept
   - Documents attack vectors

3. **Remediation** (Fix): Codex fixes all found issues
   - Patches vulnerabilities
   - Implements security controls
   - Adds defensive code

4. **Validation** (Verify): Gemini re-tests
   - Confirms all vulnerabilities fixed
   - Attempts exploitation again
   - Issues security clearance or fails

## Usage

```markdown
User: "Security audit the authentication module"

Claude: *Activates octopus-security skill*
        *Runs: ${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh squeeze "Audit authentication module"*
```

## Implementation

When this skill is invoked, Claude should:

1. **Detect security intent**: User wants adversarial testing
2. **Invoke squeeze workflow**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh squeeze "[user's security request]"
   ```
3. **Present findings**: Format attack → defense → validation results

## Output Format

```markdown
## Security Audit: Authentication Module

### Phase 1: Blue Team Defense (Codex)

**Attack Surface Identified**:
- Login endpoint: POST /api/auth/login
- Password reset: POST /api/auth/reset
- Session tokens: JWT with 1hr expiry

**Proposed Defenses**:
- Rate limiting (5 attempts/min)
- Parameterized queries
- bcrypt password hashing

---

### Phase 2: Red Team Attack (Gemini)

**Vulnerabilities Found**: 3 Critical, 2 High, 1 Medium

#### 🚨 CRITICAL: SQL Injection
```python
# Exploit PoC
payload = "admin' OR '1'='1' --"
response = requests.post('/api/auth/login',
    json={'username': payload, 'password': 'any'})
# Result: Authentication bypass
```

#### 🚨 CRITICAL: Session Fixation
```python
# Exploit PoC
# Session token not rotated on login
# Attacker can set victim's session ID
```

#### 🚨 CRITICAL: Weak Password Policy
```python
# Password: "12345" accepted
# No complexity requirements
# No length requirements
```

#### ⚠️ HIGH: Missing Rate Limiting
```python
# Brute force attack successful
# 10,000 attempts/minute possible
```

#### ⚠️ HIGH: Insecure Password Reset
```python
# Reset token predictable (timestamp-based)
# Can guess other users' reset tokens
```

#### ⚙️ MEDIUM: Session Token in URL
```python
# Token leaked in server logs
# Referer header exposure risk
```

---

### Phase 3: Remediation (Codex)

**Fixes Applied**:

1. **SQL Injection** → Parameterized queries
   ```python
   cursor.execute("SELECT * FROM users WHERE username = ?", (username,))
   ```

2. **Session Fixation** → Rotate on login
   ```python
   session.regenerate_id()
   ```

3. **Weak Passwords** → Enforce policy
   ```python
   if len(password) < 12 or not re.match(r'^(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[@$!%*?&])', password):
       raise WeakPasswordError()
   ```

4. **Rate Limiting** → Redis-based throttling
   ```python
   @rate_limit(max_attempts=5, window=60)
   def login():
   ```

5. **Reset Tokens** → Cryptographically random
   ```python
   token = secrets.token_urlsafe(32)
   ```

6. **Session in URL** → Cookie with HttpOnly
   ```python
   response.set_cookie('session', token, httponly=True, secure=True)
   ```

---

### Phase 4: Validation (Gemini)

**Re-testing Results**:

✅ SQL Injection: FIXED (parameterized queries working)
✅ Session Fixation: FIXED (ID rotates on login)
✅ Weak Passwords: FIXED (12+ chars, complexity enforced)
✅ Rate Limiting: FIXED (5 attempts/min enforced)
✅ Reset Tokens: FIXED (cryptographically secure)
✅ Session in URL: FIXED (HttpOnly cookie)

**Final Verdict**: ✅ SECURITY CLEARANCE GRANTED

All vulnerabilities remediated. No new issues found in re-testing.

**Remaining Recommendations**:
- Add MFA for admin accounts
- Implement account lockout after 5 failed attempts
- Add login notification emails
- Consider passwordless authentication
```

## Why Use This?

| Aspect | Adversarial Testing | Manual Testing |
|--------|---------------------|----------------|
| Coverage | Blue + Red team | Single perspective |
| Exploitation | Real PoC exploits | Theoretical issues |
| Validation | Automated re-test | Manual verification |
| Bias | Adversarial reduces blind spots | Defender bias |

## Configuration

Respects all octopus configuration:
- `--principles security`: Apply OWASP Top 10 focus
- `--autonomy`: Control remediation approval
- `--quality`: Set vulnerability threshold
- `--loop`: Retry until all issues fixed

## Example Scenarios

### Scenario 1: API Security Audit
```
User: "Red team review the payment API"
→ Blue Team: Identify payment flow attack surface
→ Red Team: Attempt payment bypass, data theft
→ Remediation: Fix all vulnerabilities
→ Validation: Confirm secure payment processing
```

### Scenario 2: Authentication Review
```
User: "Find vulnerabilities in our login system"
→ Blue Team: Document auth mechanisms
→ Red Team: Test for auth bypass, session attacks
→ Remediation: Implement security controls
→ Validation: Re-test all attack vectors
```

### Scenario 3: Data Privacy Check
```
User: "Check for data leakage in user profiles"
→ Blue Team: Map data flow and access controls
→ Red Team: Attempt unauthorized data access
→ Remediation: Fix privacy violations
→ Validation: Confirm data isolation
```

## Attack Patterns Available

The squeeze workflow includes these attack categories:

### OWASP Top 10 (2025)
- Broken Access Control
- Cryptographic Failures
- Injection
- Insecure Design
- Security Misconfiguration
- Vulnerable Components
- Authentication Failures
- Software Integrity Failures
- Logging & Monitoring Failures
- Server-Side Request Forgery

### Additional Patterns
- Race conditions
- Business logic flaws
- Denial of service
- Information disclosure
- Client-side attacks (XSS, CSRF)

## Advanced Features

### Custom Attack Principles

Guide red team focus:
```bash
# Focus on specific vulnerabilities
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh squeeze \
    --principles security \
    "Audit for authentication bypass only"
```

### Loop Until Secure

```bash
# Keep testing until all vulnerabilities fixed
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh squeeze \
    --loop \
    --quality 100 \
    "Security audit with zero tolerance"
```

### Session Recovery

```bash
# Resume interrupted security audit
${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh squeeze --resume
```

## Related Skills

- **octopus-quick-review** (grasp + tangle) - For code quality review
- **octopus-research** (probe) - For security pattern research
- **grapple** - For adversarial architecture debate

## When NOT to Use This

❌ **Don't use for**:
- Production systems (use real pentest tools)
- Compliance audits (use certified auditors)
- Legal verification (consult security lawyers)

✅ **Do use for**:
- Pre-commit security checks
- Development-phase testing
- Learning secure coding
- Architecture security review
- CI/CD security gates

## Comparison: squeeze vs grapple

| Feature | squeeze (Security) | grapple (Debate) |
|---------|-------------------|------------------|
| Focus | Security vulnerabilities | Design decisions |
| Approach | Attack → Defend | Propose → Critique |
| Output | Exploit PoCs | Consensus solution |
| Phases | 4 (BTRV) | 3 (PCS) |
| Best For | Code security | Architecture |

## Technical Notes

- Uses existing squeeze command from orchestrate.sh
- Requires both Codex and Gemini for adversarial testing
- Blue team (Codex) focuses on defense
- Red team (Gemini) focuses on attack
- Remediation ensures all issues fixed
- Validation confirms security clearance
