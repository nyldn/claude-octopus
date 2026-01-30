# Token Extraction Pipeline - Implementation Guide

## Overview

This document provides a comprehensive overview of the token extraction pipeline implementation, including architecture decisions, file structure, and usage patterns.

## Project Structure

```
token-extraction/
├── types.ts                    # Core TypeScript type definitions
├── utils.ts                    # Utility functions for token processing
├── pipeline.ts                 # Main orchestration pipeline
├── merger.ts                   # Token merging and conflict resolution
├── index.ts                    # Public API exports
├── cli.ts                      # Command-line interface
├── package.json                # Package configuration
├── README.md                   # User documentation
├── IMPLEMENTATION.md           # This file
├── extractors/
│   ├── tailwind.ts            # Tailwind config extractor
│   ├── css-variables.ts       # CSS custom properties extractor
│   ├── theme-file.ts          # Theme file extractor
│   └── styled-components.ts   # Styled-components/Emotion extractor
├── outputs/
│   ├── json.ts                # W3C JSON format generator
│   ├── css.ts                 # CSS custom properties generator
│   └── markdown.ts            # Markdown documentation generator
├── examples/
│   ├── basic-usage.ts         # Basic usage examples
│   └── advanced-usage.ts      # Advanced usage examples
└── test-fixtures/
    ├── tailwind.config.example.js
    ├── styles.example.css
    ├── theme.example.ts
    └── styled-components.example.tsx
```

## Core Components

### 1. Type System (types.ts)

The type system provides full TypeScript support with comprehensive type definitions for:

- **W3C Design Tokens Format**: Full compliance with the W3C specification
- **Internal Token Representation**: Rich token objects with metadata
- **Source Types**: Enumeration of all supported token sources
- **Configuration Options**: Type-safe configuration for all pipeline operations
- **Error Handling**: Structured error types for robust error reporting

Key types:
- `Token`: Internal token representation with source tracking
- `W3CDesignToken`: W3C format token structure
- `ExtractionResult`: Pipeline execution results
- `TokenConflict`: Conflict detection and resolution data

### 2. Utility Functions (utils.ts)

Provides essential token processing utilities:

- **Type Inference**: Automatic token type detection from values and keys
- **Name Normalization**: Converts various naming conventions to kebab-case
- **Token Validation**: Format validation for different token types
- **Path Management**: Hierarchical token path creation and manipulation
- **W3C Conversion**: Transform internal tokens to W3C format
- **Object Flattening**: Convert nested objects to flat token lists

### 3. Extractors

#### Tailwind Extractor (extractors/tailwind.ts)

Parses Tailwind configuration files and extracts design tokens.

**Features**:
- Supports `.js`, `.ts`, `.cjs`, `.mjs` config files
- Extracts from `theme.extend` (custom tokens)
- Optional extraction from core theme (overrides)
- Handles both JavaScript and TypeScript syntax
- Preserves Tailwind semantic categories

**Token Mapping**:
- `colors` → color tokens
- `spacing` → dimension tokens
- `fontSize`, `fontFamily`, `fontWeight` → typography tokens
- `borderRadius`, `borderWidth` → border tokens
- `boxShadow` → shadow tokens
- `screens` → breakpoint tokens
- And more...

**Error Handling**:
- Detects missing config files
- Handles malformed JavaScript/TypeScript
- Reports parsing errors with line numbers

#### CSS Variables Extractor (extractors/css-variables.ts)

Extracts CSS custom properties from stylesheets.

**Features**:
- Scans `.css`, `.scss`, `.sass`, `.less` files
- Configurable selectors (`:root`, data attributes, etc.)
- Automatic categorization based on variable names
- Glob pattern support for file discovery
- Comments and preprocessing syntax handling

**Selector Support**:
- `:root` (global variables)
- `[data-theme="..."]` (theme variants)
- Custom selectors (component-scoped variables)

**Categorization**:
- Detects colors, spacing, typography, shadows, etc.
- Based on variable name patterns
- Extensible categorization logic

#### Theme File Extractor (extractors/theme-file.ts)

Extracts tokens from JavaScript/TypeScript theme configuration files.

**Features**:
- Finds theme files using glob patterns
- Supports various export patterns (default, named, const)
- Handles TypeScript type annotations
- Extracts nested theme structures
- Preserves category organization

**Supported Patterns**:
```typescript
// Default export
export default { colors: {...} };

// Named export
export const theme = { colors: {...} };

// CommonJS
module.exports = { colors: {...} };
```

#### Styled-Components/Emotion Extractor (extractors/styled-components.ts)

Extracts theme tokens from styled-components and Emotion theme providers.

**Features**:
- Auto-detects styled-components vs Emotion
- Finds theme objects in ThemeProvider usage
- Maps styled-system conventions to standard categories
- Handles TypeScript generic types
- Supports various theme patterns

**Category Mapping**:
- `colors` → color
- `space`, `spacing` → spacing
- `fonts`, `fontSizes`, `fontWeights` → typography
- `radii` → border
- `shadows` → shadow
- `zIndices` → z-index

### 4. Token Merger (merger.ts)

Handles merging tokens from multiple sources with intelligent conflict resolution.

**Features**:
- Priority-based merging
- Automatic conflict detection
- Multiple resolution strategies
- Custom merge strategies
- Conflict reporting and statistics

**Resolution Strategies**:
1. **Priority**: Use token from highest priority source
2. **Manual**: Flag conflicts for manual resolution
3. **Merge**: Attempt to merge compatible values

**Priority System**:
- Default priorities favor explicit customization
- Customizable per-project needs
- Metadata preservation during merge

### 5. Output Generators

#### JSON Output (outputs/json.ts)

Generates W3C Design Tokens JSON format.

**Features**:
- Full W3C compliance
- Schema reference inclusion
- Pretty printing support
- Nested token structure
- Metadata extensions

**Output Format**:
```json
{
  "$schema": "https://tr.designtokens.org/format/",
  "colors": {
    "primary": {
      "$type": "color",
      "$value": "#3b82f6",
      "$extensions": {
        "com.claude-octopus": {
          "source": "tailwind.config"
        }
      }
    }
  }
}
```

#### CSS Output (outputs/css.ts)

Generates CSS custom properties file.

**Features**:
- Generates CSS variables from tokens
- Configurable selectors
- Category grouping with comments
- Media query support for theme variants
- Human-readable formatting

**Output Format**:
```css
/* Colors */
:root {
  --colors-primary: #3b82f6;
  --colors-secondary: #8b5cf6;
}

/* Spacing */
:root {
  --spacing-1: 0.25rem;
  --spacing-2: 0.5rem;
}
```

#### Markdown Output (outputs/markdown.ts)

Generates human-readable token documentation.

**Features**:
- Comprehensive token tables
- Conflict reporting
- Statistics and summaries
- Category organization
- CSS variable references

**Sections**:
- Statistics (token counts, sources, conflicts)
- Table of contents
- Token tables by category
- Conflict details with resolution info

### 6. Main Pipeline (pipeline.ts)

Orchestrates the entire extraction process.

**Execution Flow**:
1. **Discovery**: Find all token sources in project
2. **Extraction**: Extract tokens from each source
3. **Priority Application**: Apply configured priorities
4. **Merging**: Merge tokens and detect conflicts
5. **Validation**: Validate token formats and values
6. **Output Generation**: Generate all output formats
7. **Reporting**: Print summary and statistics

**Features**:
- Source filtering (include/exclude)
- Progress logging
- Error aggregation
- Comprehensive summary reporting
- Configurable output formats

### 7. CLI (cli.ts)

Command-line interface for the pipeline.

**Features**:
- Argument parsing
- Help and version commands
- Multiple output format selection
- Source filtering
- Conflict resolution strategy selection

**Usage**:
```bash
token-extraction --project ./my-app --formats json,css
token-extraction --include-sources tailwind.config,css-variables
token-extraction --output ./design-tokens
```

## Implementation Details

### Token Type Inference

The pipeline automatically infers token types using multiple heuristics:

1. **Value Pattern Matching**: Regex patterns for colors, dimensions, etc.
2. **Key Name Analysis**: Token names like `color`, `spacing`, `font`
3. **Context Awareness**: Parent category provides hints
4. **Fallback Handling**: Defaults to appropriate primitive types

### Name Normalization

Token names are normalized for consistency:

- **camelCase** → kebab-case
- **PascalCase** → kebab-case
- **snake_case** → kebab-case
- **Spaces** → hyphens
- **Trim** leading/trailing hyphens

### Conflict Detection

Conflicts are detected when:

1. Multiple tokens have identical paths
2. Tokens come from different sources
3. Values differ between sources

**Resolution Process**:
1. Group tokens by path
2. Sort by priority
3. Apply resolution strategy
4. Track conflict metadata

### Error Handling

Comprehensive error handling at multiple levels:

1. **Source Level**: File not found, parse errors
2. **Token Level**: Invalid values, type mismatches
3. **Pipeline Level**: Extraction failures, I/O errors

Errors include:
- Source identifier
- Error message
- File path (if applicable)
- Line/column numbers (when available)

### Performance Considerations

- **Glob Caching**: File discovery uses efficient glob patterns
- **Lazy Evaluation**: Extractors run only for included sources
- **Streaming**: Large files processed incrementally
- **Parallel Processing**: Independent extractions can run concurrently

## Configuration Best Practices

### Source Priority Strategy

**Recommended priorities**:
```typescript
[
  { source: 'tailwind.config', priority: 8 },  // Explicit config
  { source: 'theme-file', priority: 7 },       // Theme definition
  { source: 'styled-components', priority: 7 }, // Component themes
  { source: 'css-variables', priority: 6 },     // Runtime overrides
]
```

### Conflict Resolution Strategy

**Priority**: Use for most projects (automatic, based on priorities)
**Manual**: Use for critical tokens requiring review
**Merge**: Use when values should be combined (experimental)

### Output Formats

**JSON**: For tool integration, design systems, documentation
**CSS**: For runtime usage in stylesheets
**Markdown**: For team documentation and reference

### Validation

Enable validation (`validateTokens: true`) to catch:
- Invalid color formats
- Malformed dimensions
- Incorrect font weights
- Type mismatches

## Extension Points

### Custom Extractors

Create custom extractors by implementing the extractor interface:

```typescript
class CustomExtractor {
  async extract(projectRoot: string): Promise<{
    tokens: Token[];
    errors: ExtractionError[];
  }> {
    // Implementation
  }
}
```

### Custom Merge Strategies

Define custom merge logic:

```typescript
const customStrategy: MergeStrategy = {
  shouldMerge: (existing, incoming) => {
    // Custom merge decision
  },
  onConflict: (existing, incoming) => {
    // Custom conflict resolution
  },
};
```

### Custom Output Formats

Add new output generators:

```typescript
class CustomOutputGenerator {
  async generate(tokens: Token[]): Promise<void> {
    // Custom output generation
  }
}
```

## Testing Strategy

### Unit Tests

Test individual components:
- Type inference accuracy
- Name normalization
- Token validation
- Conflict detection

### Integration Tests

Test complete extraction flows:
- Extract from test fixtures
- Verify token counts and types
- Check conflict detection
- Validate output files

### Test Fixtures

Included test fixtures demonstrate:
- Valid Tailwind configs
- CSS variable patterns
- Theme file structures
- Styled-components usage

## Deployment

### As CLI Tool

```bash
npm install -g @claude-octopus/token-extraction
token-extraction --project ./my-app
```

### As Library

```typescript
import { runTokenExtraction } from '@claude-octopus/token-extraction';

const result = await runTokenExtraction('./my-app', {
  outputFormats: ['json', 'css'],
});
```

### In CI/CD

```yaml
- name: Extract Design Tokens
  run: |
    npx token-extraction
    git add design-tokens/
    git commit -m "Update design tokens"
```

## Future Enhancements

Potential areas for expansion:

1. **Additional Sources**:
   - Figma API integration
   - Sketch plugin
   - Adobe XD extraction
   - Design system packages

2. **Output Formats**:
   - iOS (Swift/UIKit)
   - Android (XML resources)
   - React Native
   - Flutter (Dart)
   - SASS variables
   - LESS variables

3. **Advanced Features**:
   - Token aliasing and references
   - Computed tokens
   - Semantic token layers
   - Design token transformations
   - Version control integration
   - Diff tracking

4. **Tooling**:
   - VS Code extension
   - Web UI for conflict resolution
   - Integration with design tools
   - Real-time sync

5. **Validation**:
   - Accessibility compliance checks
   - Naming convention enforcement
   - Token usage analysis
   - Breaking change detection

## Troubleshooting

### Common Issues

**No tokens extracted**:
- Verify source files exist
- Check file patterns match your structure
- Review error messages

**Unexpected conflicts**:
- Review source priorities
- Check for duplicate definitions
- Adjust conflict resolution strategy

**Invalid output**:
- Enable validation
- Check token value formats
- Review type inference

**Performance issues**:
- Limit glob patterns
- Exclude unnecessary directories
- Use specific source inclusion

## Contributing

See main README for contribution guidelines.

Areas particularly welcome for contributions:
- Additional source extractors
- New output formats
- Improved type inference
- Enhanced documentation
- Bug fixes and optimizations

## License

MIT License - See LICENSE file for details.

## Support

For issues, questions, or contributions:
- GitHub Issues: https://github.com/nyldn/claude-octopus/issues
- Documentation: See README.md
- Examples: See examples/ directory
