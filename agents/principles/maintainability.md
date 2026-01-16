---
name: maintainability-principles
domain: maintainability
description: Critique principles for maintainable, readable code
---

# Maintainability Principles

Code MUST adhere to these maintainability requirements:

## Code Structure

1. **Single Responsibility** - Functions and classes do ONE thing. Keep them focused and small.

2. **DRY (Don't Repeat Yourself)** - Extract common logic into reusable functions. Avoid copy-paste.

3. **Separation of Concerns** - Keep business logic, data access, and presentation separate.

## Naming & Readability

4. **Clear Naming** - Variables, functions, and classes describe their purpose. Avoid abbreviations.

5. **No Magic Numbers** - Constants are named and explained. Avoid hardcoded values.

6. **Consistent Style** - Follow project conventions. Use consistent formatting and patterns.

## Error Handling

7. **Explicit Error Handling** - All errors are caught and handled appropriately. No silent failures.

8. **Meaningful Error Messages** - Errors include context for debugging. Log relevant details.

9. **Graceful Degradation** - Handle edge cases. Provide fallbacks where appropriate.

## Testing & Documentation

10. **Testability** - Code is unit-testable. Dependencies are injectable. Pure functions preferred.

11. **Self-Documenting Code** - Code is readable without comments. Complex logic has explanations.

12. **API Documentation** - Public APIs have clear documentation. Include examples.

## Design

13. **Loose Coupling** - Minimize dependencies between modules. Use interfaces/abstractions.

14. **High Cohesion** - Related functionality is grouped together. Modules have clear boundaries.

15. **YAGNI** - Don't build for hypothetical future requirements. Solve current problems.

## Checklist

When reviewing code, verify:
- [ ] Functions are small and focused
- [ ] No code duplication
- [ ] Clear, descriptive naming
- [ ] No magic numbers or strings
- [ ] Consistent code style
- [ ] Proper error handling
- [ ] Code is testable
- [ ] Complex logic is documented
- [ ] Dependencies are minimized
- [ ] No over-engineering
