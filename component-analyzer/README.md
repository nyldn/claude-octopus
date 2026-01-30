# Component Analysis Engine

Advanced TypeScript-based component analysis engine for React, Vue, and Svelte applications. Performs deep AST traversal, prop extraction, variant detection, usage tracking, and generates comprehensive component inventories.

## Features

### 🔍 **Multi-Framework Support**
- **React**: Function components, class components, HOCs, render props, hooks
- **Vue**: Options API and Composition API components
- **Svelte**: Component scripts with exported props

### 🎯 **Advanced Prop Extraction**
- TypeScript interfaces and type aliases
- PropTypes definitions
- JSDoc annotations
- Vue props configuration
- Svelte export statements
- Default props and values
- Multi-source merging with confidence scoring

### 🎨 **Variant Detection**
- Discriminated unions
- Union types with literal values
- Boolean variants
- Size/color/theme variants
- Polymorphic component patterns (as/component props)
- Enum-based variants
- Custom heuristics

### 📊 **Usage Tracking**
- Cross-file component usage analysis
- JSX element detection
- Import source tracking
- Props usage at call sites
- Dependency graphs

### 📈 **Complexity Metrics**
- Cyclomatic complexity
- Cognitive complexity
- Lines of code
- Nesting depth

### 📦 **Export Formats**
- JSON (detailed)
- CSV (tabular)
- Markdown (documentation)
- Custom statistics reports

## Installation

```bash
npm install @claude-octopus/component-analyzer
# or
yarn add @claude-octopus/component-analyzer
```

## Quick Start

### CLI Usage

```bash
# Basic analysis
npx component-analyzer

# Analyze specific directory
npx component-analyzer --root src/components

# Generate CSV inventory
npx component-analyzer --format csv --output components.csv

# React-only analysis with custom patterns
npx component-analyzer --frameworks react --include "src/**/*.tsx"

# Full analysis with statistics
npx component-analyzer --verbose --output inventory.json
```

### Programmatic Usage

```typescript
import { ComponentAnalysisEngine, InventoryGenerator } from '@claude-octopus/component-analyzer';

// Configure analysis
const config = {
  rootDir: './src',
  include: ['**/*.tsx', '**/*.ts'],
  exclude: ['**/*.test.*', '**/node_modules/**'],
  frameworks: ['react'],
  detectVariants: true,
  trackUsages: true,
  extractDocs: true,
  maxFileSize: 1024 * 1024,
  parallelism: 4
};

// Run analysis
const engine = new ComponentAnalysisEngine(config);
const result = await engine.analyze();

console.log(`Found ${result.summary.totalComponents} components`);
console.log(`Total props: ${result.summary.totalProps}`);
console.log(`Total variants: ${result.summary.totalVariants}`);

// Generate inventory
const generator = new InventoryGenerator();
generator.generateInventory(result, {
  format: 'json',
  outputPath: './component-inventory.json',
  includeUsages: true,
  includeVariants: true,
  prettify: true
});
```

## Architecture

### Core Components

```
component-analyzer/
├── src/
│   ├── analyzers/
│   │   ├── typescript-analyzer.ts    # TS Compiler API integration
│   │   ├── prop-extractor.ts         # Multi-source prop extraction
│   │   ├── variant-detector.ts       # Variant detection heuristics
│   │   └── usage-tracker.ts          # Cross-file usage tracking
│   ├── generators/
│   │   └── inventory-generator.ts    # Export format generators
│   ├── engine.ts                     # Main orchestration
│   ├── types.ts                      # Type definitions
│   ├── index.ts                      # Public API
│   └── cli.ts                        # CLI interface
```

### TypeScript Compiler API Integration

The engine uses the TypeScript Compiler API for accurate AST traversal:

```typescript
import * as ts from 'typescript';

class TypeScriptAnalyzer {
  private program: ts.Program;
  private checker: ts.TypeChecker;

  analyzeFile(filePath: string): ComponentMetadata[] {
    const sourceFile = this.program.getSourceFile(filePath);
    // AST traversal with type checking
  }
}
```

### Prop Extraction Pipeline

```typescript
class PropExtractor {
  extractProps(sourceCode: string, framework: ComponentFramework): PropType[] {
    // 1. TypeScript interfaces/types (confidence: 1.0)
    // 2. PropTypes (confidence: 0.9)
    // 3. Vue props (confidence: 0.95)
    // 4. Svelte exports (confidence: 0.95)
    // 5. Default props (confidence: 0.7)

    // Merge with confidence-based priority
    return this.mergeResults(results);
  }
}
```

### Variant Detection Heuristics

```typescript
class VariantDetector {
  private heuristics = [
    discriminatedUnionHeuristic,   // confidence: 1.0
    enumVariantHeuristic,          // confidence: 0.9
    booleanVariantHeuristic,       // confidence: 0.7
    asPropsHeuristic,              // confidence: 0.95
    sizeVariantHeuristic,          // confidence: 0.8
    colorVariantHeuristic,         // confidence: 0.8
    variantPropHeuristic           // confidence: 0.85
  ];
}
```

## Component Patterns

### React Components

#### Function Component
```typescript
interface ButtonProps {
  variant: 'primary' | 'secondary';
  size?: 'small' | 'medium' | 'large';
  disabled?: boolean;
}

export function Button({ variant, size = 'medium', disabled }: ButtonProps) {
  return <button className={`btn-${variant} btn-${size}`} disabled={disabled} />;
}
```

**Detected:**
- Pattern: `function`
- Props: 3 (variant, size, disabled)
- Variants: 6 (2 variant × 3 size)

#### Class Component
```typescript
interface ListProps<T> {
  items: T[];
  renderItem: (item: T) => React.ReactNode;
}

export class List<T> extends React.Component<ListProps<T>> {
  render() {
    return <ul>{this.props.items.map(this.props.renderItem)}</ul>;
  }
}
```

**Detected:**
- Pattern: `class`
- Props: 2 (items, renderItem)
- Generic parameters: tracked

#### Higher-Order Component
```typescript
export function withLoading<P>(Component: React.ComponentType<P>) {
  return ({ isLoading, ...props }: P & { isLoading: boolean }) => {
    return isLoading ? <Loading /> : <Component {...props} />;
  };
}
```

**Detected:**
- Pattern: `hoc`
- Wrapper component analysis

#### Discriminated Union
```typescript
type IconButtonProps =
  | { variant: 'icon'; icon: React.ReactNode; label: string }
  | { variant: 'text'; children: React.ReactNode };

export function IconButton(props: IconButtonProps) {
  if (props.variant === 'icon') {
    return <button aria-label={props.label}>{props.icon}</button>;
  }
  return <button>{props.children}</button>;
}
```

**Detected:**
- Variants: 2 (icon, text)
- Discriminator: `variant`
- Additional props per variant

### Vue Components

```vue
<script>
export default {
  props: {
    title: {
      type: String,
      required: true
    },
    variant: {
      type: String,
      default: 'primary',
      validator: (value) => ['primary', 'secondary'].includes(value)
    }
  }
}
</script>
```

**Detected:**
- Pattern: `vue-options`
- Props: 2 with types and defaults

### Svelte Components

```svelte
<script lang="ts">
  export let title: string;
  export let variant: 'primary' | 'secondary' = 'primary';
  export let disabled: boolean = false;
</script>
```

**Detected:**
- Pattern: `svelte-component`
- Props: 3 with TypeScript types

## Output Formats

### JSON
```json
{
  "summary": {
    "totalComponents": 15,
    "totalProps": 47,
    "totalVariants": 23,
    "totalUsages": 142,
    "analysisTimeMs": 1234
  },
  "components": [
    {
      "name": "Button",
      "framework": "react",
      "pattern": "function",
      "props": [
        {
          "name": "variant",
          "type": "\"primary\" | \"secondary\"",
          "required": true
        }
      ],
      "variants": [
        {
          "name": "variant_primary",
          "discriminator": "variant",
          "discriminatorValue": "primary"
        }
      ],
      "usages": [
        {
          "filePath": "src/App.tsx",
          "line": 42,
          "propsUsed": ["variant", "onClick"]
        }
      ]
    }
  ]
}
```

### CSV
```csv
Name,Framework,Pattern,File Path,Props Count,Variants Count,Usages Count,Complexity
Button,react,function,src/components/Button.tsx,3,6,24,2
Card,react,function,src/components/Card.tsx,4,2,18,1
```

### Markdown
```markdown
# Component Inventory

## Summary
- Total Components: 15
- Total Props: 47
- Total Variants: 23

### react

#### Button

- **Pattern**: function
- **File**: `src/components/Button.tsx`
- **Props**: 3

| Name | Type | Required | Default |
|------|------|----------|---------|
| variant | `"primary" \| "secondary"` | Yes | - |
| size | `"small" \| "medium" \| "large"` | No | "medium" |
```

## CLI Options

```
Usage: component-analyzer [options]

Options:
  -r, --root <dir>         Root directory (default: current)
  -i, --include <patterns> Include patterns (comma-separated)
  -e, --exclude <patterns> Exclude patterns (comma-separated)
  -f, --frameworks <list>  Frameworks: react,vue,svelte
  -o, --output <file>      Output file path
  --format <type>          Format: json, csv, markdown
  --no-usages              Disable usage tracking
  --no-variants            Disable variant detection
  --tsconfig <path>        Path to tsconfig.json
  -v, --verbose            Verbose output
  -h, --help               Show help
```

## Performance

### Optimization Strategies

1. **Incremental Compilation**: Reuses TypeScript program for faster re-analysis
2. **File Size Limits**: Configurable max file size (default: 1MB)
3. **Parallel Processing**: Configurable parallelism (default: 4)
4. **Caching**: In-memory AST caching

### Benchmarks

| Project Size | Components | Analysis Time |
|--------------|------------|---------------|
| Small (< 50) | 45 | ~2s |
| Medium (< 200) | 187 | ~8s |
| Large (< 500) | 456 | ~25s |
| Enterprise (1000+) | 1200 | ~60s |

## Advanced Usage

### Custom Variant Detection

```typescript
import { VariantDetector } from '@claude-octopus/component-analyzer';

const detector = new VariantDetector();

// Add custom heuristic
detector.addHeuristic({
  name: 'custom-status',
  confidence: 0.9,
  detect: (props) => {
    const statusProp = props.find(p => p.name === 'status');
    if (!statusProp) return [];

    return ['active', 'pending', 'completed'].map(status => ({
      name: `status_${status}`,
      discriminator: 'status',
      discriminatorValue: status,
      additionalProps: []
    }));
  }
});
```

### Filtering and Querying

```typescript
const result = await engine.analyze();

// Get most used components
const mostUsed = engine.getMostUsed(result.components, 10);

// Get most complex components
const mostComplex = engine.getMostComplex(result.components, 10);

// Filter by framework
const reactComponents = engine.filterByFramework(result.components, 'react');

// Filter by pattern
const hocs = engine.filterByPattern(result.components, 'hoc');
```

## Contributing

Contributions welcome! Areas for improvement:

- Additional framework support (Angular, Solid.js)
- Enhanced variant detection heuristics
- Performance optimizations
- Better error recovery
- More export formats

## License

MIT

## Credits

Built with:
- TypeScript Compiler API
- Babel Parser
- json2csv
- glob
