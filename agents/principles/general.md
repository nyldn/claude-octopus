---
name: general-principles
domain: general
description: General code quality critique principles
---

# General Quality Principles

Code MUST adhere to these quality requirements:

## Correctness

1. **Functional Correctness** - Code does what it's supposed to do. All requirements are met.

2. **Edge Case Handling** - Boundary conditions are handled. Empty inputs, nulls, and limits work.

3. **Error Handling** - Errors are caught and handled gracefully. No unhandled exceptions.

## Reliability

4. **No Race Conditions** - Concurrent access is properly synchronized.

5. **Resource Management** - Resources are acquired late, released early. No leaks.

6. **Idempotency** - Operations that should be idempotent are implemented correctly.

## Code Quality

7. **Readability** - Code is clear and understandable. Intent is obvious.

8. **Simplicity** - Solutions are as simple as possible, but no simpler.

9. **Consistency** - Code follows established patterns and conventions.

## Best Practices

10. **Type Safety** - Use types effectively. Avoid any/unknown where possible.

11. **Validation** - Input is validated at boundaries. Output is sanitized.

12. **Logging** - Important events are logged. Errors include context.

## Architecture

13. **Modularity** - Code is organized into logical modules. Clear boundaries.

14. **Dependencies** - External dependencies are justified and minimal.

15. **Configuration** - Environment-specific values are configurable.

## Checklist

When reviewing code, verify:
- [ ] Code is functionally correct
- [ ] Edge cases are handled
- [ ] Errors are handled appropriately
- [ ] No obvious bugs or issues
- [ ] Code is readable and maintainable
- [ ] Follows project conventions
- [ ] No unnecessary complexity
- [ ] Proper use of types
- [ ] Input validation in place
- [ ] Appropriate logging
