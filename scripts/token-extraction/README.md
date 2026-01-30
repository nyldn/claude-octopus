# Token Extraction Pipeline

A comprehensive TypeScript pipeline for extracting design tokens from multiple sources and converting them to the W3C Design Tokens format.

## Features

- **Multiple Source Support**: Extract tokens from:
  - Tailwind CSS configuration files (`tailwind.config.js/ts`)
  - CSS custom properties (`:root` declarations)
  - Theme configuration files (`theme.js/ts`)
  - Styled-components theme providers
  - Emotion theme providers

- **W3C Compliance**: Outputs tokens in the standard W3C Design Tokens format
- **Conflict Resolution**: Intelligent priority-based merging with conflict detection
- **Multiple Output Formats**: Generate JSON, CSS, and Markdown documentation
- **Type Safety**: Full TypeScript support with comprehensive type definitions
- **Validation**: Built-in token validation for format compliance
- **Error Handling**: Robust error handling for malformed configs

## Installation

```bash
# Install dependencies
npm install glob
npm install --save-dev @types/node

# Make CLI executable
chmod +x scripts/token-extraction/cli.ts
```

## Quick Start

### CLI Usage

```bash
# Extract all tokens from current project
node scripts/token-extraction/cli.ts

# Extract only Tailwind and CSS variables
node scripts/token-extraction/cli.ts --include-sources tailwind.config,css-variables

# Generate only JSON output
node scripts/token-extraction/cli.ts --formats json

# Custom output directory
node scripts/token-extraction/cli.ts --output ./tokens
```

### Programmatic Usage

```typescript
import { runTokenExtraction } from './scripts/token-extraction';

// Basic extraction
const result = await runTokenExtraction('/path/to/project');

console.log(`Extracted ${result.tokens.length} tokens`);
console.log(`Conflicts: ${result.conflicts.length}`);

// Advanced options
const result = await runTokenExtraction('/path/to/project', {
  conflictResolution: 'priority',
  outputFormats: ['json', 'css', 'markdown'],
  outputDir: './design-tokens',
  includeSources: ['tailwind.config', 'css-variables'],
  validateTokens: true,
});
```

## Architecture

### Pipeline Flow

```
1. Source Discovery
   ├─ Find Tailwind config
   ├─ Scan CSS files for variables
   ├─ Locate theme files
   └─ Detect styled-components/emotion

2. Token Extraction
   ├─ Parse configuration files
   ├─ Extract token definitions
   ├─ Normalize token names
   └─ Infer token types

3. Token Merging
   ├─ Group by path
   ├─ Detect conflicts
   ├─ Apply priority rules
   └─ Resolve conflicts

4. Validation
   ├─ Validate token types
   ├─ Check value formats
   └─ Report errors

5. Output Generation
   ├─ Convert to W3C format
   ├─ Generate JSON
   ├─ Generate CSS variables
   └─ Generate Markdown docs
```

### Priority System

Tokens from different sources are merged based on priority:

| Source | Priority | Rationale |
|--------|----------|-----------|
| Tailwind Config (extend) | 8 | Explicit customization |
| Theme Files | 7 | Direct theme definition |
| Styled-components/Emotion | 7 | Component library themes |
| CSS Variables | 6 | Runtime customization |

Higher priority sources override lower priority ones during conflicts.

## Configuration

### Extraction Options

```typescript
interface ExtractionOptions {
  // Source filtering
  includeSources?: TokenSource[];
  excludeSources?: TokenSource[];

  // Priority configuration
  sourcePriorities?: SourcePriority[];

  // Conflict resolution
  conflictResolution?: 'priority' | 'manual' | 'merge';

  // Output options
  outputFormats?: ('json' | 'css' | 'markdown')[];
  outputDir?: string;

  // Processing options
  preserveOriginalKeys?: boolean;
  validateTokens?: boolean;
}
```

### Custom Priorities

```typescript
import { runTokenExtraction, TokenSource } from './scripts/token-extraction';

const result = await runTokenExtraction('/path/to/project', {
  sourcePriorities: [
    { source: TokenSource.CSS_VARIABLES, priority: 10 }, // Highest
    { source: TokenSource.TAILWIND_CONFIG, priority: 5 },
    { source: TokenSource.THEME_FILE, priority: 3 },
  ],
});
```

### Custom Merge Strategy

```typescript
import { TokenMerger, MergeStrategy } from './scripts/token-extraction';

const customStrategy: MergeStrategy = {
  shouldMerge: (existing, incoming) => {
    // Only merge if types match
    return existing.type === incoming.type;
  },
  onConflict: (existing, incoming) => {
    // Use incoming value but preserve existing metadata
    return {
      ...incoming,
      metadata: {
        ...existing.metadata,
        ...incoming.metadata,
      },
    };
  },
};

const merger = new TokenMerger();
const tokens = merger.applyCustomStrategy(allTokens, customStrategy);
```

## Output Formats

### JSON (W3C Design Tokens)

```json
{
  "$schema": "https://tr.designtokens.org/format/",
  "$description": "Design tokens extracted from project sources",
  "colors": {
    "primary": {
      "500": {
        "$type": "color",
        "$value": "#3b82f6",
        "$description": "Primary brand color",
        "$extensions": {
          "com.claude-octopus": {
            "source": "tailwind.config",
            "originalKey": "colors.primary.500"
          }
        }
      }
    }
  }
}
```

### CSS Custom Properties

```css
/**
 * Design Tokens - CSS Custom Properties
 * Generated from project design token sources
 */

/* Colors */
:root {
  --colors-primary-500: #3b82f6;
  --colors-gray-100: #f3f4f6;
  --colors-gray-900: #111827;
}

/* Spacing */
:root {
  --spacing-1: 0.25rem;
  --spacing-2: 0.5rem;
  --spacing-4: 1rem;
}
```

### Markdown Documentation

```markdown
# Design Tokens

## Statistics

- **Total Tokens**: 147
- **Tokens by Source**:
  - tailwind.config: 89
  - css-variables: 34
  - theme-file: 24
- **Conflicts**: 5

## Tokens

### Colors

| Name | Value | Type | CSS Variable | Source |
|------|-------|------|--------------|--------|
| colors.primary.500 | `#3b82f6` | color | `--colors-primary-500` | tailwind.config |
```

## API Reference

### Main Pipeline

```typescript
class TokenExtractionPipeline {
  constructor(projectRoot: string, options?: ExtractionOptions);
  async execute(): Promise<ExtractionResult>;
}
```

### Extractors

```typescript
// Tailwind
class TailwindExtractor {
  async extract(projectRoot: string): Promise<{
    tokens: Token[];
    errors: ExtractionError[];
  }>;
}

// CSS Variables
class CSSVariablesExtractor {
  async extract(projectRoot: string): Promise<{
    tokens: Token[];
    errors: ExtractionError[];
  }>;
}

// Theme Files
class ThemeFileExtractor {
  async extract(projectRoot: string): Promise<{
    tokens: Token[];
    errors: ExtractionError[];
  }>;
}

// Styled-components/Emotion
class StyledComponentsExtractor {
  async extract(projectRoot: string): Promise<{
    tokens: Token[];
    errors: ExtractionError[];
  }>;
}
```

### Token Merger

```typescript
class TokenMerger {
  constructor(options?: ExtractionOptions);

  merge(tokenLists: Token[][]): {
    tokens: Token[];
    conflicts: TokenConflict[];
  };

  applyCustomStrategy(tokens: Token[], strategy: MergeStrategy): Token[];
  validateTokens(tokens: Token[]): { valid: Token[]; invalid: Token[] };
  getConflicts(): TokenConflict[];
  getManualConflicts(): TokenConflict[];
  getConflictStats(): ConflictStats;
}
```

### Output Generators

```typescript
// JSON
async function generateJSONOutput(
  tokens: Token[],
  options: JSONOutputOptions
): Promise<void>;

// CSS
async function generateCSSOutput(
  tokens: Token[],
  options: CSSOutputOptions
): Promise<void>;

// Markdown
async function generateMarkdownOutput(
  tokens: Token[],
  options: MarkdownOutputOptions,
  conflicts?: TokenConflict[]
): Promise<void>;
```

## Error Handling

The pipeline handles various error scenarios:

### Malformed Configs

```typescript
// Invalid JavaScript syntax in config
{
  source: 'tailwind.config',
  message: 'Failed to parse JavaScript config',
  error: SyntaxError,
  filePath: '/path/to/tailwind.config.js',
}
```

### Missing Files

```typescript
// Config file not found
{
  source: 'tailwind.config',
  message: 'No Tailwind config file found',
}
```

### Invalid Token Values

```typescript
// Token fails validation
{
  source: 'css-variables',
  message: 'Invalid token: colors.primary - Invalid color format',
}
```

### Handling Errors

```typescript
const result = await runTokenExtraction('/path/to/project');

if (result.errors.length > 0) {
  console.error('Extraction errors:');
  for (const error of result.errors) {
    console.error(`[${error.source}] ${error.message}`);
  }
}
```

## Advanced Usage

### Extract Only Specific Tokens

```typescript
import { TailwindExtractor } from './scripts/token-extraction';

const extractor = new TailwindExtractor({
  includeCore: false,      // Skip Tailwind defaults
  includeExtend: true,     // Only custom tokens
});

const result = await extractor.extract('/path/to/project');
```

### Custom CSS Variable Selectors

```typescript
import { CSSVariablesExtractor } from './scripts/token-extraction';

const extractor = new CSSVariablesExtractor({
  selectors: [
    ':root',
    '[data-theme="light"]',
    '[data-theme="dark"]',
    '.custom-theme',
  ],
});

const result = await extractor.extract('/path/to/project');
```

### Theme Variants

```typescript
import { generateCSSOutput } from './scripts/token-extraction';

const generator = new CSSOutputGenerator({
  outputPath: './tokens.css',
  mediaQueries: {
    dark: '@media (prefers-color-scheme: dark)',
    mobile: '@media (max-width: 768px)',
  },
});

await generator.generate(tokens);
```

### Programmatic Conflict Resolution

```typescript
const result = await runTokenExtraction('/path/to/project', {
  conflictResolution: 'manual',
});

// Review manual conflicts
for (const conflict of result.conflicts) {
  console.log(`Conflict at: ${conflict.path.join('.')}`);
  console.log('Options:');

  for (const token of conflict.tokens) {
    console.log(`  [${token.source}] ${token.value} (priority: ${token.priority})`);
  }

  // Implement custom resolution logic
}
```

## Testing

### Example Test Cases

```typescript
import { runTokenExtraction } from './scripts/token-extraction';

describe('Token Extraction Pipeline', () => {
  it('should extract Tailwind tokens', async () => {
    const result = await runTokenExtraction('./test-fixtures/tailwind-project');
    expect(result.tokens.length).toBeGreaterThan(0);
    expect(result.errors.length).toBe(0);
  });

  it('should handle conflicts correctly', async () => {
    const result = await runTokenExtraction('./test-fixtures/conflict-project');
    expect(result.conflicts.length).toBeGreaterThan(0);
    expect(result.tokens.length).toBeGreaterThan(0);
  });

  it('should validate token formats', async () => {
    const result = await runTokenExtraction('./test-fixtures/invalid-project', {
      validateTokens: true,
    });
    expect(result.errors.some(e => e.message.includes('Invalid'))).toBe(true);
  });
});
```

## Troubleshooting

### No tokens extracted

- Verify source files exist in the project
- Check file patterns match your project structure
- Review error messages for parsing issues

### Unexpected conflicts

- Review conflict resolution strategy
- Adjust source priorities
- Check for duplicate token definitions

### Invalid output

- Enable token validation
- Review error messages
- Verify source file formats

## Contributing

Contributions welcome! Areas for improvement:

- Support for additional token sources
- Enhanced type inference
- More output formats (Figma, iOS, Android)
- Improved conflict resolution strategies

## License

MIT License - See LICENSE file for details

## Resources

- [W3C Design Tokens Specification](https://design-tokens.github.io/community-group/format/)
- [Tailwind CSS Documentation](https://tailwindcss.com/docs/configuration)
- [CSS Custom Properties](https://developer.mozilla.org/en-US/docs/Web/CSS/--*)
- [Styled Components Theming](https://styled-components.com/docs/advanced#theming)
- [Emotion Theming](https://emotion.sh/docs/theming)
