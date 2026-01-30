/**
 * Component Analysis Engine - Type Definitions
 * Comprehensive type system for component analysis
 */

/**
 * Supported component frameworks
 */
export enum ComponentFramework {
  REACT = 'react',
  VUE = 'vue',
  SVELTE = 'svelte',
  UNKNOWN = 'unknown'
}

/**
 * Component pattern types
 */
export enum ComponentPattern {
  FUNCTION = 'function',
  CLASS = 'class',
  HOC = 'hoc',
  RENDER_PROP = 'render-prop',
  COMPOUND = 'compound',
  FORWARD_REF = 'forward-ref',
  MEMO = 'memo',
  LAZY = 'lazy',
  VUE_OPTIONS = 'vue-options',
  VUE_COMPOSITION = 'vue-composition',
  SVELTE_COMPONENT = 'svelte-component'
}

/**
 * Prop type information
 */
export interface PropType {
  name: string;
  type: string;
  required: boolean;
  defaultValue?: string;
  description?: string;
  deprecated?: boolean;
  deprecationMessage?: string;
}

/**
 * Component variant information
 */
export interface ComponentVariant {
  name: string;
  discriminator: string;
  discriminatorValue: string | number | boolean;
  additionalProps: PropType[];
  description?: string;
}

/**
 * Component usage information
 */
export interface ComponentUsage {
  filePath: string;
  line: number;
  column: number;
  propsUsed: string[];
  importSource: string;
  isDefaultImport: boolean;
}

/**
 * Component metadata
 */
export interface ComponentMetadata {
  name: string;
  filePath: string;
  framework: ComponentFramework;
  pattern: ComponentPattern;
  props: PropType[];
  variants: ComponentVariant[];
  usages: ComponentUsage[];
  exports: {
    isDefault: boolean;
    isNamed: boolean;
    aliases: string[];
  };
  dependencies: string[];
  complexity: {
    cyclomaticComplexity: number;
    cognitiveComplexity: number;
    linesOfCode: number;
  };
  sourceLocation: {
    start: { line: number; column: number };
    end: { line: number; column: number };
  };
  documentation?: {
    summary?: string;
    examples?: string[];
    tags?: Record<string, string>;
  };
}

/**
 * Analysis configuration
 */
export interface AnalysisConfig {
  rootDir: string;
  include: string[];
  exclude: string[];
  frameworks: ComponentFramework[];
  detectVariants: boolean;
  trackUsages: boolean;
  extractDocs: boolean;
  maxFileSize: number;
  parallelism: number;
  tsConfigPath?: string;
}

/**
 * Analysis result
 */
export interface AnalysisResult {
  components: ComponentMetadata[];
  summary: {
    totalComponents: number;
    byFramework: Record<ComponentFramework, number>;
    byPattern: Record<ComponentPattern, number>;
    totalProps: number;
    totalVariants: number;
    totalUsages: number;
    analysisTimeMs: number;
  };
  errors: AnalysisError[];
  warnings: AnalysisWarning[];
}

/**
 * Analysis error
 */
export interface AnalysisError {
  filePath: string;
  message: string;
  line?: number;
  column?: number;
  stack?: string;
}

/**
 * Analysis warning
 */
export interface AnalysisWarning {
  filePath: string;
  message: string;
  severity: 'low' | 'medium' | 'high';
  line?: number;
  column?: number;
}

/**
 * Export format options
 */
export interface ExportOptions {
  format: 'json' | 'csv' | 'markdown';
  outputPath: string;
  includeUsages: boolean;
  includeVariants: boolean;
  prettify: boolean;
}

/**
 * CSV row format for component inventory
 */
export interface ComponentInventoryRow {
  name: string;
  framework: string;
  pattern: string;
  filePath: string;
  propsCount: number;
  variantsCount: number;
  usagesCount: number;
  complexity: number;
  isExported: boolean;
  hasDocumentation: boolean;
}

/**
 * Prop extraction source types
 */
export enum PropSource {
  TYPESCRIPT_INTERFACE = 'typescript-interface',
  TYPESCRIPT_TYPE = 'typescript-type',
  PROPTYPES = 'proptypes',
  JSDOC = 'jsdoc',
  VUE_PROPS = 'vue-props',
  SVELTE_EXPORT = 'svelte-export',
  DEFAULT_PROPS = 'default-props',
  FUNCTION_PARAMS = 'function-params'
}

/**
 * Internal prop extraction result
 */
export interface PropExtractionResult {
  props: PropType[];
  source: PropSource;
  confidence: number;
}

/**
 * AST visitor context
 */
export interface VisitorContext {
  filePath: string;
  framework: ComponentFramework;
  components: Map<string, ComponentMetadata>;
  imports: Map<string, ImportInfo>;
  sourceFile: any; // TypeScript SourceFile or Babel AST
}

/**
 * Import information
 */
export interface ImportInfo {
  source: string;
  importName: string;
  localName: string;
  isDefault: boolean;
  isNamespace: boolean;
}

/**
 * Variant detection heuristics
 */
export interface VariantHeuristic {
  name: string;
  detect: (props: PropType[]) => ComponentVariant[];
  confidence: number;
}
