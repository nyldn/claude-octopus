# Stub Detection Patterns

Verification patterns to ensure implementation completeness and catch placeholders.

## Purpose

Stub detection prevents incomplete implementations from passing code review by:
1. **Identifying placeholders** - TODO, FIXME, PLACEHOLDER comments
2. **Detecting empty functions** - Functions with no implementation
3. **Finding mock data** - Hardcoded test values in production code
4. **Verifying wiring** - Ensuring components are actually integrated

## Common Stub Indicators

### JavaScript/TypeScript

**Comment-based stubs:**
```bash
grep -rn "TODO\|FIXME\|PLACEHOLDER\|XXX\|HACK\|TEMP" "$file"
grep -rn "coming soon\|not implemented\|to be implemented" "$file"
```

**Empty implementations:**
```bash
# Empty function bodies
grep -E "function.*\{\s*\}" "$file"
grep -E "const.*=.*\(\).*=>.*\{\s*\}" "$file"

# Return null/undefined
grep -E "return (null|undefined);" "$file"

# Return empty objects/arrays
grep -E "return \{\};" "$file"
grep -E "return \[\];" "$file"

# Throw NotImplementedError
grep -E "throw.*NotImplemented" "$file"
```

**Console stubs:**
```bash
grep -E "console\.(log|warn|error).*stub" "$file"
grep -E "console\.(log|warn|error).*mock" "$file"
grep -E "console\.(log|warn|error).*placeholder" "$file"
```

### React/JSX Components

**Empty components:**
```bash
# Components returning null
grep -E "return null.*TODO" "$file"

# Placeholder divs
grep -E "return.*<div>.*TODO.*</div>" "$file"
grep -E "return.*<div>.*Coming soon.*</div>" "$file"

# Empty fragments
grep -E "return <></>;" "$file"
```

**Mock props:**
```bash
# Hardcoded test data
grep -E "const.*props.*=.*\{.*test.*\}" "$file"
grep -E "const.*data.*=.*\[.*mock.*\]" "$file"
```

### API Routes/Endpoints

**Empty handlers:**
```bash
# Empty response objects
grep -E "res\.json\(\{\}\)" "$file"
grep -E "res\.json\(null\)" "$file"
grep -E "return.*Response\.json\(\{\}\)" "$file"

# Status 501 Not Implemented
grep -E "status\(501\)" "$file"
```

**Placeholder responses:**
```bash
grep -E "message.*not implemented" "$file"
grep -E "message.*coming soon" "$file"
```

### Database Models/Schemas

**Undefined fields:**
```bash
# Prisma/TypeORM undefined values
grep -E "@Column.*undefined" "$file"
grep -E "type:.*undefined" "$file"

# Empty validators
grep -E "validate:.*\{\s*\}" "$file"
```

### Python

**Stub indicators:**
```bash
# Pass statements
grep -E "def.*:$" -A 1 "$file" | grep -E "^\s*pass\s*$"

# NotImplementedError
grep -E "raise NotImplementedError" "$file"

# Empty returns
grep -E "return None.*TODO" "$file"
```

### Go

**Stub indicators:**
```bash
# Empty interface implementations
grep -E "func.*\{\s*return nil\s*\}" "$file"

# panic("not implemented")
grep -E "panic\(.*not implemented" "$file"
```

## Verification Levels

Use these levels to assess implementation completeness:

### Level 1: Exists ✓
- File is present at expected path
- File is not empty (>0 bytes)
- Basic structure is in place

**Check:**
```bash
[ -f "$file" ] && [ -s "$file" ]
```

### Level 2: Substantive ✓✓
- Contains actual implementation (not just imports/types)
- No stub patterns detected
- Has meaningful content
- Minimum lines: Components (>10), Utilities (>5), Types (>3)

**Check:**
```bash
# Count non-empty, non-comment lines
lines=$(grep -vE "^\s*(//|/\*|\*|import|export|$)" "$file" | wc -l)

# Check for stub patterns
stub_count=$(grep -E "(TODO|FIXME|PLACEHOLDER)" "$file" | wc -l)

if [ "$lines" -ge 10 ] && [ "$stub_count" -eq 0 ]; then
  echo "Substantive"
fi
```

### Level 3: Wired ✓✓✓
- Imported by parent components/modules
- Called/referenced in integration points
- Exports are used (not dead code)

**Check:**
```bash
# Find imports of this module
module_name=$(basename "$file" .ts)
grep -r "import.*$module_name" . --exclude="$file"

# Find function/component usage
function_name="MyComponent"
grep -r "$function_name" . --exclude="$file"
```

### Level 4: Functional ✓✓✓✓
- Runs without errors
- Produces expected output
- Passes basic smoke tests
- Integration tests pass

**Check:**
```bash
# Run tests
npm test "$file"

# Check for runtime errors
node -c "$file"  # JavaScript syntax check
tsc --noEmit "$file"  # TypeScript type check
```

## Implementation Patterns to Flag

### 🚩 Pattern 1: Skeleton Functions

```typescript
// ❌ BAD - Empty function
export function calculateTax(amount: number): number {
  // TODO: Implement tax calculation
  return 0;
}

// ✅ GOOD - Actual implementation
export function calculateTax(amount: number): number {
  const taxRate = 0.08;
  return amount * taxRate;
}
```

### 🚩 Pattern 2: Mock Data in Production

```typescript
// ❌ BAD - Hardcoded mock data
export async function getUsers() {
  return [
    { id: 1, name: "Test User" },
    { id: 2, name: "Mock User" }
  ];
}

// ✅ GOOD - Real data fetch
export async function getUsers() {
  const response = await fetch('/api/users');
  return response.json();
}
```

### 🚩 Pattern 3: Placeholder UI

```tsx
// ❌ BAD - Placeholder component
export function UserProfile({ userId }: Props) {
  return <div>User profile coming soon</div>;
}

// ✅ GOOD - Real implementation
export function UserProfile({ userId }: Props) {
  const user = useUser(userId);
  return (
    <div>
      <h1>{user.name}</h1>
      <p>{user.email}</p>
    </div>
  );
}
```

### 🚩 Pattern 4: Commented-Out Logic

```typescript
// ❌ BAD - Critical logic commented out
export function processPayment(amount: number) {
  // const result = await stripe.charges.create({...});
  // return result;
  return { success: true }; // FIXME: Add real Stripe integration
}

// ✅ GOOD - Actual implementation
export async function processPayment(amount: number) {
  const result = await stripe.charges.create({
    amount,
    currency: 'usd'
  });
  return result;
}
```

## Automated Detection Script

```bash
#!/usr/bin/env bash
# detect-stubs.sh - Comprehensive stub detection

check_file_stubs() {
    local file="$1"
    local issues=0

    echo "Checking: $file"

    # Check 1: Comment-based stubs
    stub_comments=$(grep -n -E "(TODO|FIXME|PLACEHOLDER|XXX|HACK)" "$file" | wc -l)
    if [ "$stub_comments" -gt 0 ]; then
        echo "  ⚠️  Found $stub_comments stub comments"
        grep -n -E "(TODO|FIXME|PLACEHOLDER)" "$file" | head -3
        issues=$((issues + 1))
    fi

    # Check 2: Empty functions
    empty_funcs=$(grep -E "function.*\{\s*\}|=>.*\{\s*\}" "$file" | wc -l)
    if [ "$empty_funcs" -gt 0 ]; then
        echo "  ❌ Found $empty_funcs empty functions"
        issues=$((issues + 1))
    fi

    # Check 3: Return null/undefined
    null_returns=$(grep -E "return (null|undefined);" "$file" | wc -l)
    if [ "$null_returns" -gt 0 ]; then
        echo "  ⚠️  Found $null_returns null/undefined returns"
        issues=$((issues + 1))
    fi

    # Check 4: Minimum substantive content
    substantive_lines=$(grep -vE "^\s*(//|/\*|\*|import|export|$)" "$file" | wc -l)
    if [ "$substantive_lines" -lt 5 ]; then
        echo "  ⚠️  Only $substantive_lines substantive lines (expected >5)"
        issues=$((issues + 1))
    fi

    # Check 5: Console log stubs
    console_stubs=$(grep -E "console\.(log|warn).*stub|mock|test" "$file" | wc -l)
    if [ "$console_stubs" -gt 0 ]; then
        echo "  ⚠️  Found $console_stubs console stub references"
        issues=$((issues + 1))
    fi

    if [ "$issues" -eq 0 ]; then
        echo "  ✅ No stubs detected"
    fi

    return "$issues"
}

# Usage
for file in "$@"; do
    check_file_stubs "$file"
done
```

## Integration with Code Review

When reviewing pull requests, run stub detection on changed files:

```bash
# Get changed files
changed_files=$(git diff --name-only HEAD~1..HEAD)

# Filter for source files
source_files=$(echo "$changed_files" | grep -E "\.(ts|tsx|js|jsx|py|go)$")

# Check each file
total_issues=0
for file in $source_files; do
    check_file_stubs "$file"
    total_issues=$((total_issues + $?))
done

# Report
if [ "$total_issues" -eq 0 ]; then
    echo "✅ All files substantive - no stubs detected"
else
    echo "⚠️  Found stubs in $total_issues files"
    echo "Review required before merge"
fi
```

## Severity Levels

| Pattern | Severity | Action |
|---------|----------|--------|
| TODO/FIXME comments | ⚠️ Warning | Note in review, non-blocking |
| Empty functions | ❌ Error | Block merge until implemented |
| Return null/undefined | ⚠️ Warning | Verify intentional |
| Mock/test data | ❌ Error | Block merge, use real data |
| <5 substantive lines | ⚠️ Warning | Check if component is too simple |
| console.log stubs | ⚠️ Warning | Remove before production |
| Not imported anywhere | ❌ Error | Dead code or missing integration |

## Best Practices

### ✅ DO:
- Run stub detection on all changed files before review
- Flag empty functions as blocking issues
- Verify minimum substantive content
- Check that new components are imported/used
- Allow TODO comments for follow-up work (non-blocking)

### ❌ DON'T:
- Auto-merge PRs with empty functions
- Ignore stub patterns in "small" PRs
- Skip verification for "quick fixes"
- Allow mock data in production code
- Merge dead code (not imported anywhere)

## Example Review Checklist

```markdown
## Implementation Completeness

- [ ] No empty function bodies
- [ ] No return null/undefined without justification
- [ ] No mock/test data in production code
- [ ] All components imported and used
- [ ] Minimum substantive content (>10 lines for components)
- [ ] TODO comments documented with follow-up tickets
- [ ] Console logs removed or converted to proper logging
- [ ] No commented-out critical logic
```

## Conclusion

Stub detection ensures that code reviews catch incomplete implementations before they reach production. By systematically checking for common stub patterns, we maintain code quality and prevent technical debt accumulation.

Use the detection script as part of CI/CD pipelines or pre-commit hooks to catch stubs early in the development process.
