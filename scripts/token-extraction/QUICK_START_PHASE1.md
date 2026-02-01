# Quick Start: Phase 1 Features

## 🚀 Using the New Features

### 1. Run Accessibility Audit

```bash
cd plugin/scripts/token-extraction

# Extract with accessibility audit
npm run extract -- \
  --project ./your-app \
  --formats json,css,markdown \
  --accessibility-enabled \
  --accessibility-target AAA

# Check the markdown output for accessibility report
cat design-tokens/tokens.md
```

### 2. Generate All Output Formats

```bash
npm run extract -- \
  --project ./your-app \
  --formats typescript,tailwind,styled-components,style-dictionary,schema
```

**Output files generated**:
- `tokens.ts` + `tokens.d.ts` - TypeScript
- `tailwind.tokens.js` - Tailwind config
- `tokens.styled.ts` - Styled Components
- `style-dictionary.config.js` + `tokens-source.json` - Style Dictionary
- `tokens.schema.json` - JSON Schema

### 3. Run Tests

```bash
# Run all tests
npm test

# Run in watch mode
npm run test:watch

# View in UI
npm run test:ui

# Generate coverage report
npm run test:coverage
```

### 4. Use in Your Code

```typescript
import { runTokenExtraction } from '@claude-octopus/token-extraction';

const result = await runTokenExtraction('./my-app', {
  // Enable accessibility audit
  accessibility: {
    enabled: true,
    targetLevel: 'AA',  // or 'AAA'
    generateFocusStates: true,
    generateTouchTargets: true,
    generateHighContrastAlternatives: false,
  },

  // Choose output formats
  outputFormats: [
    'json',
    'css',
    'markdown',
    'typescript',
    'tailwind',
    'styled-components',
    'style-dictionary',
    'schema',
  ],

  outputDir: './design-tokens',
});

// Access the accessibility report
if (result.accessibilityReport) {
  console.log(`WCAG AA: ${result.accessibilityReport.summary.passAA} passes`);
  console.log(`Violations: ${result.accessibilityReport.violations.length}`);
}
```

## 📋 CLI Flags (New in Phase 1)

```bash
--accessibility-enabled          # Enable accessibility audit
--accessibility-target AA|AAA    # Target WCAG level (default: AA)
--accessibility-focus-states     # Generate focus state tokens
--accessibility-touch-targets    # Generate touch target tokens
```

## 🎨 Example Output

### Accessibility Report (in tokens.md)

```markdown
## Accessibility Audit

**Audit Timestamp**: 2026-02-01T12:00:00Z

### Summary
- **Total Color Pairs Tested**: 42
- **WCAG AA Compliant**: 38 (90.5%)
- **WCAG AAA Compliant**: 22
- **Violations**: 4

### Generated Accessibility Tokens
- **Focus States**: 6 tokens
- **Touch Targets**: 6 tokens

### Contrast Violations

#### Critical (2)
| Foreground | Background | Ratio | WCAG Level | Recommendation |
|------------|------------|-------|------------|----------------|
| text-muted | bg-light | 2.3:1 | Fail | Significantly adjust colors |
```

### TypeScript Output

```typescript
// tokens.d.ts
export interface DesignTokens {
  colors: {
    primary: { 500: string };
    text: { primary: string; secondary: string };
  };
  spacing: {
    xs: string;
    sm: string;
    md: string;
  };
}

// tokens.ts
export const tokens = {
  colors: {
    primary: { 500: '#3b82f6' },
    text: { primary: '#000000', secondary: '#666666' }
  },
  spacing: { xs: '0.5rem', sm: '1rem', md: '1.5rem' }
} as const;

export type Tokens = typeof tokens;
```

### Tailwind Config

```javascript
// tailwind.tokens.js
module.exports = {
  theme: {
    extend: {
      colors: {
        primary: { 500: '#3b82f6' },
      },
      spacing: {
        xs: '0.5rem',
        sm: '1rem',
      }
    }
  }
};
```

## 🔍 Verify Installation

```bash
# 1. Check dependencies installed
npm list tinycolor2 vitest

# 2. Run test suite
npm test

# 3. Try basic extraction
npm run extract -- --project ./test-fixtures

# 4. Check output files
ls design-tokens/
```

## 📚 Documentation

- Full implementation details: `PHASE1_COMPLETE.md`
- Overall status: `IMPLEMENTATION_STATUS.md`
- Architecture: `ARCHITECTURE.md`
- Original README: `README.md`

## 🐛 Troubleshooting

### Tests failing?
```bash
# Clear node_modules and reinstall
rm -rf node_modules package-lock.json
npm install

# Run tests
npm test
```

### Missing dependencies?
```bash
npm install tinycolor2 @types/tinycolor2 vitest @vitest/ui
```

### Output not generating?
```bash
# Check format spelling
npm run extract -- --formats json,css,typescript  # comma-separated, no spaces
```

## ✅ What's Working

- ✅ WCAG 2.1 contrast calculations (tested against W3C spec)
- ✅ Accessibility audits with violations reporting
- ✅ Auto-generated focus states (2px outline, WCAG compliant)
- ✅ Touch target tokens (44px minimum)
- ✅ TypeScript output (types + constants)
- ✅ Tailwind config generation
- ✅ Styled Components theme
- ✅ Style Dictionary multi-platform
- ✅ JSON Schema validation
- ✅ 41 tests passing

## ⏸️ Not Yet Implemented (Phase 2 & 3)

- Browser extraction via MCP
- Interaction state capture (:hover, :focus, :active)
- Multi-AI debate integration
- Validation workflow
- Validation certificates

---

**Phase 1 Status**: ✅ COMPLETE AND READY TO USE
