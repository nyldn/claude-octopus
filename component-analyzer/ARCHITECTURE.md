# Component Analysis Engine - Architecture

## Overview

The Component Analysis Engine is a sophisticated TypeScript-based system that performs deep static analysis of component-based codebases. It leverages the TypeScript Compiler API and Babel to accurately extract component metadata, detect variants, track usage patterns, and generate comprehensive inventories.

## Core Design Principles

### 1. Accuracy Through Type System
- Leverages TypeScript's type checker for precise type inference
- Supports complex generic types and conditional types
- Handles union types and discriminated unions natively

### 2. Multi-Source Intelligence
- Combines information from multiple sources (TypeScript, PropTypes, JSDoc, defaults)
- Uses confidence scoring to merge conflicting information
- Validates extracted data against actual usage

### 3. Framework Agnostic
- Pluggable analyzer architecture
- Framework-specific pattern detection
- Unified metadata model across frameworks

### 4. Performance Optimized
- Incremental compilation support
- Parallel file processing
- AST caching and memoization
- Configurable limits and thresholds

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         CLI / API                            │
│                      (Entry Points)                          │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                   Analysis Engine                            │
│  • File Discovery      • Orchestration                       │
│  • Framework Detection • Result Aggregation                  │
└──────────────┬────────────────┬─────────────┬───────────────┘
               │                │             │
       ┌───────▼──────┐ ┌──────▼──────┐ ┌───▼────────┐
       │  TypeScript  │ │    Babel    │ │  Framework │
       │   Analyzer   │ │   Analyzer  │ │  Analyzers │
       └───────┬──────┘ └──────┬──────┘ └───┬────────┘
               │                │             │
               └────────┬───────┴─────────────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
   ┌────▼─────┐  ┌─────▼──────┐  ┌────▼────────┐
   │   Prop   │  │  Variant   │  │   Usage     │
   │Extractor │  │  Detector  │  │   Tracker   │
   └────┬─────┘  └─────┬──────┘  └────┬────────┘
        │              │               │
        └──────────────┼───────────────┘
                       │
              ┌────────▼────────┐
              │   Metadata      │
              │   Aggregation   │
              └────────┬────────┘
                       │
         ┌─────────────┼─────────────┐
         │             │             │
    ┌────▼────┐  ┌────▼────┐  ┌────▼────┐
    │  JSON   │  │   CSV   │  │Markdown │
    │Generator│  │Generator│  │Generator│
    └─────────┘  └─────────┘  └─────────┘
```

## Component Analysis Pipeline

### Phase 1: Discovery & Preprocessing

```typescript
async analyze(): Promise<AnalysisResult> {
  // 1. File Discovery
  const files = await this.findComponentFiles();

  // 2. Framework Detection
  files.forEach(file => {
    const framework = this.detectFramework(file);
  });

  // 3. TypeScript Program Initialization
  this.tsAnalyzer.updateProgram(files);

  // 4. Parallel Analysis
  const components = await Promise.all(
    files.map(file => this.analyzeFile(file))
  );
}
```

**Key Operations:**
- Glob pattern matching with configurable includes/excludes
- File size filtering to prevent OOM
- Framework detection via imports and file extensions
- TypeScript program creation with incremental compilation

### Phase 2: AST Traversal & Extraction

```typescript
analyzeFile(filePath: string): ComponentMetadata[] {
  const sourceFile = this.program.getSourceFile(filePath);
  const context: VisitorContext = {
    filePath,
    framework,
    components: new Map(),
    imports: this.extractImports(sourceFile),
    sourceFile
  };

  this.visitNode(sourceFile, context);
  return Array.from(context.components.values());
}
```

**AST Visitor Pattern:**

```typescript
private visitNode(node: ts.Node, context: VisitorContext): void {
  // Component Detection
  if (this.isFunctionComponent(node, context)) {
    const component = this.analyzeFunctionComponent(node, context);
    context.components.set(component.name, component);
  }

  if (this.isClassComponent(node, context)) {
    const component = this.analyzeClassComponent(node, context);
    context.components.set(component.name, component);
  }

  if (this.isHOC(node, context)) {
    const component = this.analyzeHOC(node, context);
    context.components.set(component.name, component);
  }

  // Recursive traversal
  ts.forEachChild(node, child => this.visitNode(child, context));
}
```

### Phase 3: Prop Extraction

**Multi-Source Extraction Strategy:**

```typescript
extractProps(sourceCode: string, framework: ComponentFramework): PropType[] {
  const results: PropExtractionResult[] = [];

  // Source 1: TypeScript Types (Confidence: 1.0)
  const tsResult = this.extractFromTypeScript(sourceCode);
  if (tsResult) results.push(tsResult);

  // Source 2: PropTypes (Confidence: 0.9)
  const propTypesResult = this.extractFromPropTypes(sourceCode);
  if (propTypesResult) results.push(propTypesResult);

  // Source 3: Default Props (Confidence: 0.7)
  const defaultPropsResult = this.extractFromDefaultProps(sourceCode);
  if (defaultPropsResult) results.push(defaultPropsResult);

  // Source 4: Framework-Specific (Confidence: 0.9-0.95)
  if (framework === ComponentFramework.VUE) {
    const vueResult = this.extractFromVueProps(sourceCode);
    if (vueResult) results.push(vueResult);
  }

  // Merge with confidence-based priority
  return this.mergeResults(results);
}
```

**Merge Algorithm:**

```typescript
mergeResults(results: PropExtractionResult[]): PropType[] {
  // Sort by confidence (highest first)
  results.sort((a, b) => b.confidence - a.confidence);

  const merged = new Map<string, PropType>();

  for (const result of results) {
    for (const prop of result.props) {
      if (!merged.has(prop.name)) {
        merged.set(prop.name, prop);
      } else {
        // Merge: prefer non-'any' types, existing defaults, etc.
        const existing = merged.get(prop.name)!;
        merged.set(prop.name, {
          ...existing,
          type: existing.type === 'any' ? prop.type : existing.type,
          defaultValue: existing.defaultValue || prop.defaultValue,
          description: existing.description || prop.description
        });
      }
    }
  }

  return Array.from(merged.values());
}
```

### Phase 4: Variant Detection

**Heuristic-Based Detection:**

```typescript
class VariantDetector {
  private heuristics: VariantHeuristic[] = [
    {
      name: 'discriminated-union',
      confidence: 1.0,
      detect: (props) => {
        // Detect from union types with literal values
        // Example: type: '"primary" | "secondary"'
        return variants;
      }
    },
    {
      name: 'boolean-variant',
      confidence: 0.7,
      detect: (props) => {
        // Boolean props create two variants
        return variants;
      }
    },
    // ... more heuristics
  ];

  detectVariants(props: PropType[]): ComponentVariant[] {
    const allVariants = this.heuristics.flatMap(h => h.detect(props));
    return this.deduplicateVariants(allVariants);
  }
}
```

**TypeScript AST-Based Detection:**

```typescript
detectVariantsFromSource(sourceCode: string, propsTypeName: string) {
  const sourceFile = ts.createSourceFile(...);

  const visit = (node: ts.Node) => {
    if (ts.isTypeAliasDeclaration(node)) {
      if (ts.isUnionTypeNode(node.type)) {
        // Find discriminator property
        const discriminator = this.findDiscriminator(node.type);

        // Extract variants
        node.type.types.forEach(typeNode => {
          const variant = this.extractVariant(typeNode, discriminator);
          variants.push(variant);
        });
      }
    }
  };
}
```

### Phase 5: Usage Tracking

**Cross-File Analysis:**

```typescript
trackUsages(componentName: string, files: string[]): ComponentUsage[] {
  const usages: ComponentUsage[] = [];

  for (const file of files) {
    // 1. Extract imports
    const imports = this.extractImports(file);

    // 2. Find local names importing this component
    const localNames = this.findLocalNames(imports, componentName);

    // 3. Find JSX usages
    const fileUsages = this.findJSXUsages(file, localNames);

    usages.push(...fileUsages);
  }

  return usages;
}
```

**Import Matching:**

```typescript
matchesComponent(importInfo: ImportInfo, componentName: string): boolean {
  // Check import name
  if (importInfo.importName !== componentName) return false;

  // Check source path
  const normalizedSource = this.normalizePath(importInfo.source);
  const normalizedTarget = this.normalizePath(componentFilePath);

  return normalizedSource === normalizedTarget ||
         normalizedTarget.includes(normalizedSource);
}
```

### Phase 6: Complexity Calculation

**Metrics:**

```typescript
calculateComplexity(node: ts.Node) {
  let cyclomaticComplexity = 1;
  let cognitiveComplexity = 0;
  let nestingLevel = 0;

  const visit = (n: ts.Node, nesting: number) => {
    // Cyclomatic: decision points
    if (isDecisionPoint(n)) {
      cyclomaticComplexity++;
    }

    // Cognitive: decision points + nesting
    if (isDecisionPoint(n)) {
      cognitiveComplexity += (1 + nesting);
      visit(n, nesting + 1);
    }
  };

  return { cyclomaticComplexity, cognitiveComplexity, linesOfCode };
}
```

### Phase 7: Result Aggregation

```typescript
generateSummary(components: ComponentMetadata[]): Summary {
  return {
    totalComponents: components.length,
    byFramework: this.countByFramework(components),
    byPattern: this.countByPattern(components),
    totalProps: components.reduce((sum, c) => sum + c.props.length, 0),
    totalVariants: components.reduce((sum, c) => sum + c.variants.length, 0),
    totalUsages: components.reduce((sum, c) => sum + c.usages.length, 0),
    analysisTimeMs
  };
}
```

## Data Structures

### ComponentMetadata

```typescript
interface ComponentMetadata {
  // Identity
  name: string;
  filePath: string;

  // Classification
  framework: ComponentFramework;
  pattern: ComponentPattern;

  // Props & Variants
  props: PropType[];
  variants: ComponentVariant[];

  // Usage & Dependencies
  usages: ComponentUsage[];
  dependencies: string[];

  // Exports
  exports: {
    isDefault: boolean;
    isNamed: boolean;
    aliases: string[];
  };

  // Metrics
  complexity: ComplexityMetrics;
  sourceLocation: SourceLocation;

  // Documentation
  documentation?: Documentation;
}
```

### PropType

```typescript
interface PropType {
  name: string;
  type: string;              // TypeScript type string
  required: boolean;
  defaultValue?: string;
  description?: string;
  deprecated?: boolean;
  deprecationMessage?: string;
}
```

### ComponentVariant

```typescript
interface ComponentVariant {
  name: string;                    // Variant identifier
  discriminator: string;           // Prop that discriminates
  discriminatorValue: any;         // Value for this variant
  additionalProps: PropType[];     // Props unique to variant
  description?: string;
}
```

## Performance Optimization

### Incremental Compilation

```typescript
class TypeScriptAnalyzer {
  private program: ts.Program;

  updateProgram(files: string[]): void {
    // Reuse previous program for incremental compilation
    this.program = ts.createProgram(
      files,
      config,
      undefined,
      this.program  // Previous program
    );
  }
}
```

### Parallel Processing

```typescript
async analyzeFiles(files: string[]): Promise<ComponentMetadata[]> {
  const chunks = this.chunkArray(files, this.config.parallelism);

  const results = await Promise.all(
    chunks.map(chunk =>
      Promise.all(chunk.map(file => this.analyzeFile(file)))
    )
  );

  return results.flat(2);
}
```

### Caching Strategy

```typescript
class AnalysisCache {
  private astCache = new Map<string, ts.SourceFile>();
  private propsCache = new Map<string, PropType[]>();

  getCachedAST(filePath: string, mtime: number): ts.SourceFile | null {
    const cached = this.astCache.get(filePath);
    if (cached && cached.mtime === mtime) {
      return cached.ast;
    }
    return null;
  }
}
```

## Error Handling

### Graceful Degradation

```typescript
try {
  const components = this.analyzeFile(filePath);
  return components;
} catch (error) {
  errors.push({
    filePath,
    message: error.message,
    stack: error.stack
  });
  return []; // Continue with other files
}
```

### Validation

```typescript
validateComponent(component: ComponentMetadata): AnalysisWarning[] {
  const warnings: AnalysisWarning[] = [];

  if (component.props.length > 20) {
    warnings.push({
      filePath: component.filePath,
      message: `Component has ${component.props.length} props (consider splitting)`,
      severity: 'medium'
    });
  }

  if (component.complexity.cyclomaticComplexity > 10) {
    warnings.push({
      filePath: component.filePath,
      message: 'High cyclomatic complexity',
      severity: 'high'
    });
  }

  return warnings;
}
```

## Extension Points

### Custom Heuristics

```typescript
detector.addHeuristic({
  name: 'custom-pattern',
  confidence: 0.85,
  detect: (props: PropType[]): ComponentVariant[] => {
    // Custom variant detection logic
    return variants;
  }
});
```

### Custom Analyzers

```typescript
class CustomFrameworkAnalyzer implements FrameworkAnalyzer {
  analyze(filePath: string): ComponentMetadata[] {
    // Custom analysis logic
  }
}

engine.registerAnalyzer('custom-framework', new CustomFrameworkAnalyzer());
```

## Testing Strategy

### Unit Tests
- Individual analyzers (TypeScript, Babel, Prop Extractor)
- Variant detection heuristics
- Usage tracking algorithms
- Complexity calculations

### Integration Tests
- End-to-end analysis pipelines
- Multi-file component analysis
- Cross-framework scenarios

### Snapshot Tests
- Output format validation
- Regression detection

## Future Enhancements

1. **Real-time Analysis**: Watch mode with incremental updates
2. **Dependency Graphs**: Visual component relationships
3. **Migration Tools**: Automated refactoring suggestions
4. **Plugin System**: Custom analyzers and exporters
5. **AI-Powered Insights**: ML-based component recommendations
6. **Performance Profiling**: Runtime usage analysis integration

## Conclusion

The Component Analysis Engine provides a robust, accurate, and performant solution for understanding component-based codebases. Its architecture prioritizes accuracy through the TypeScript type system while maintaining flexibility for multiple frameworks and extensibility for custom analysis needs.
