# Token Extraction Pipeline - Quick Start Guide

## Installation

```bash
cd /Users/chris/git/claude-octopus/plugin/scripts/token-extraction
npm install
```

## Immediate Usage

### 1. Extract Tokens (CLI)

```bash
# From any project directory
node /path/to/token-extraction/cli.ts

# Or if you're in the token-extraction directory
node cli.ts --project /path/to/your/project
```

### 2. Extract Tokens (Programmatic)

```typescript
import { runTokenExtraction } from './path/to/token-extraction';

const result = await runTokenExtraction('./my-project');
console.log(`Extracted ${result.tokens.length} tokens`);
```

## Common Use Cases

### Extract Only Tailwind Tokens

```bash
node cli.ts --include-sources tailwind.config
```

### Generate Only JSON Output

```bash
node cli.ts --formats json
```

### Custom Output Directory

```bash
node cli.ts --output ./design-tokens
```

### Handle Conflicts Manually

```bash
node cli.ts --conflict-resolution manual
```

## What Gets Extracted?

The pipeline automatically finds and extracts tokens from:

1. **Tailwind Config** (`tailwind.config.js/ts`)
   - Colors, spacing, typography, shadows, etc.
   - From `theme.extend` section

2. **CSS Variables** (`:root` in `.css` files)
   - Custom properties like `--color-primary`
   - Theme variants like `[data-theme="dark"]`

3. **Theme Files** (`theme.js/ts`)
   - JavaScript/TypeScript theme objects
   - Nested token structures

4. **Styled-Components** (theme providers)
   - Theme objects passed to ThemeProvider
   - Styled-system conventions

5. **Emotion** (theme providers)
   - Emotion theme configurations
   - Theme object patterns

## Output Files

After extraction, you'll find in `./design-tokens/`:

```
design-tokens/
├── tokens.json      # W3C Design Tokens format
├── tokens.css       # CSS custom properties
└── tokens.md        # Human-readable documentation
```

## Example Output

### tokens.json (W3C Format)
```json
{
  "$schema": "https://tr.designtokens.org/format/",
  "colors": {
    "primary": {
      "500": {
        "$type": "color",
        "$value": "#3b82f6"
      }
    }
  }
}
```

### tokens.css
```css
:root {
  --colors-primary-500: #3b82f6;
  --spacing-4: 1rem;
  --font-size-base: 1rem;
}
```

## Run Examples

```bash
# Basic usage examples
npm run example:basic

# Advanced usage examples
npm run example:advanced
```

## Check Test Fixtures

Look at example configurations:

```bash
cat test-fixtures/tailwind.config.example.js
cat test-fixtures/styles.example.css
cat test-fixtures/theme.example.ts
cat test-fixtures/styled-components.example.tsx
```

## Programmatic API

### Basic Extraction

```typescript
import { runTokenExtraction } from './token-extraction';

const result = await runTokenExtraction('/path/to/project');
```

### Advanced Configuration

```typescript
import { runTokenExtraction, TokenSource } from './token-extraction';

const result = await runTokenExtraction('/path/to/project', {
  // Only extract from specific sources
  includeSources: [
    TokenSource.TAILWIND_CONFIG,
    TokenSource.CSS_VARIABLES
  ],

  // Conflict resolution
  conflictResolution: 'priority',

  // Output options
  outputFormats: ['json', 'css', 'markdown'],
  outputDir: './tokens',

  // Validation
  validateTokens: true,
});

console.log(`Tokens: ${result.tokens.length}`);
console.log(`Conflicts: ${result.conflicts.length}`);
console.log(`Errors: ${result.errors.length}`);
```

### Individual Extractors

```typescript
import { TailwindExtractor } from './token-extraction';

const extractor = new TailwindExtractor({
  includeCore: false,
  includeExtend: true,
});

const result = await extractor.extract('./my-project');
```

## CLI Options Reference

```
-h, --help                     Show help
-v, --version                  Show version
-p, --project <path>           Project root (default: current dir)
-o, --output <path>            Output directory
-f, --formats <formats>        Output formats (json,css,markdown)
-c, --conflict-resolution      Strategy (priority|manual|merge)
--include-sources <sources>    Only extract from these sources
--exclude-sources <sources>    Skip these sources
--no-validate                  Skip validation
--preserve-keys                Keep original token keys
```

## Priority System

Default priorities (higher = wins conflicts):

| Source | Priority | When to Use |
|--------|----------|-------------|
| Tailwind (extend) | 8 | Custom tokens |
| Theme Files | 7 | Explicit themes |
| Styled/Emotion | 7 | Component themes |
| CSS Variables | 6 | Runtime overrides |

## Customize Priorities

```typescript
const result = await runTokenExtraction('./project', {
  sourcePriorities: [
    { source: 'css-variables', priority: 10 },
    { source: 'tailwind.config', priority: 5 },
  ],
});
```

## Error Handling

```typescript
const result = await runTokenExtraction('./project');

if (result.errors.length > 0) {
  console.error('Extraction errors:');
  result.errors.forEach(error => {
    console.error(`[${error.source}] ${error.message}`);
  });
}

if (result.conflicts.length > 0) {
  console.warn(`${result.conflicts.length} conflicts detected`);
}
```

## Validation

Enable validation to catch issues:

```typescript
const result = await runTokenExtraction('./project', {
  validateTokens: true,
});

// Invalid tokens are excluded from output
// Check result.errors for validation failures
```

## Integration Examples

### NPM Scripts

```json
{
  "scripts": {
    "tokens:extract": "node scripts/token-extraction/cli.ts",
    "tokens:watch": "nodemon --watch src --exec npm run tokens:extract"
  }
}
```

### CI/CD (GitHub Actions)

```yaml
- name: Extract Design Tokens
  run: |
    node scripts/token-extraction/cli.ts
    git add design-tokens/
    git diff --staged --quiet || git commit -m "Update design tokens"
```

### Pre-commit Hook

```bash
#!/bin/bash
node scripts/token-extraction/cli.ts
git add design-tokens/
```

## Troubleshooting

### No tokens extracted
- Check if source files exist
- Verify file patterns match your structure
- Review error messages in output

### Unexpected conflicts
- Check source priorities
- Review token definitions
- Use `--conflict-resolution manual` for details

### Invalid output
- Enable validation: `--no-validate`
- Check source file formats
- Review error messages

## Next Steps

1. **Read Full Documentation**: Check `README.md`
2. **Explore Architecture**: See `ARCHITECTURE.md`
3. **Review Implementation**: Read `IMPLEMENTATION.md`
4. **Run Examples**: Try `examples/basic-usage.ts`
5. **Customize**: Create your own extractors/outputs

## File Locations

All files are in:
```
/Users/chris/git/claude-octopus/plugin/scripts/token-extraction/
```

## Getting Help

- Check `README.md` for detailed documentation
- Review `examples/` for code samples
- Look at `test-fixtures/` for real examples
- Read `IMPLEMENTATION.md` for technical details

## Quick Reference Card

```
┌─────────────────────────────────────────────────┐
│         TOKEN EXTRACTION QUICK REF              │
├─────────────────────────────────────────────────┤
│                                                 │
│  EXTRACT ALL                                    │
│  $ node cli.ts                                  │
│                                                 │
│  SPECIFIC SOURCES                               │
│  $ node cli.ts --include-sources tailwind.config│
│                                                 │
│  JSON ONLY                                      │
│  $ node cli.ts --formats json                   │
│                                                 │
│  CUSTOM OUTPUT                                  │
│  $ node cli.ts --output ./my-tokens             │
│                                                 │
│  PROGRAMMATIC                                   │
│  const result = await runTokenExtraction(path); │
│                                                 │
└─────────────────────────────────────────────────┘
```

## Supported Token Types

- **color**: HEX, RGB, RGBA, HSL, HSLA
- **dimension**: px, rem, em, %, vh, vw
- **fontFamily**: Font stacks (string or array)
- **fontWeight**: 100-900 or named weights
- **duration**: ms, s
- **cubicBezier**: Timing functions
- **number**: Raw numbers
- **string**: Text values
- **shadow**: Box shadows
- **gradient**: Gradients (experimental)
- **typography**: Font configs
- **border**: Border configurations
- **transition**: Transition configs

## Ready to Go!

You're all set. The pipeline is production-ready and can be used immediately on any project with supported token sources.

For detailed usage, see `README.md`.
For architecture details, see `ARCHITECTURE.md`.
For implementation details, see `IMPLEMENTATION.md`.
