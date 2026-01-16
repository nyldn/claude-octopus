---
name: security-principles
domain: security
description: Critique principles for secure code development
---

# Security Principles

Code MUST adhere to these security requirements:

## Input & Output

1. **No SQL Injection** - All database queries MUST be parameterized. Never concatenate user input into SQL strings.

2. **No XSS (Cross-Site Scripting)** - All output MUST be properly escaped/encoded for the context (HTML, JavaScript, URL, CSS).

3. **No Command Injection** - Never pass user input directly to shell commands. Use safe APIs or strict validation.

## Authentication & Authorization

4. **No CSRF** - State-changing requests MUST require valid CSRF tokens.

5. **Secure Authentication** - Use strong password hashing (bcrypt/argon2), implement rate limiting, support MFA.

6. **Least Privilege** - Grant minimal permissions required. Never run as root/admin unless necessary.

## Data Protection

7. **Secure Defaults** - Fail closed, not open. Default to denying access.

8. **Sensitive Data Handling** - Never log passwords, tokens, or PII. Use encryption at rest and in transit.

9. **Secure Session Management** - Use secure, httpOnly cookies. Regenerate session IDs on privilege changes.

## Defense in Depth

10. **Input Validation** - Validate ALL user input server-side. Client-side validation is for UX only.

11. **Error Handling** - Never expose stack traces or internal details to users.

12. **Dependency Security** - Audit dependencies for known vulnerabilities. Keep packages updated.

## Checklist

When reviewing code, verify:
- [ ] No hardcoded secrets or credentials
- [ ] All inputs validated and sanitized
- [ ] All outputs properly encoded
- [ ] Authentication properly implemented
- [ ] Authorization checks on all protected resources
- [ ] Secure communication (HTTPS, TLS)
- [ ] Proper error handling without info leakage
- [ ] Logging without sensitive data exposure
