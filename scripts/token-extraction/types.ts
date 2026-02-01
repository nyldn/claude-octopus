/**
 * W3C Design Tokens Format Specification
 * @see https://design-tokens.github.io/community-group/format/
 */

export type TokenType =
  | 'color'
  | 'dimension'
  | 'fontFamily'
  | 'fontWeight'
  | 'duration'
  | 'cubicBezier'
  | 'number'
  | 'string'
  | 'shadow'
  | 'gradient'
  | 'typography'
  | 'border'
  | 'transition';

export interface W3CDesignToken {
  $type?: TokenType;
  $value: any;
  $description?: string;
  $extensions?: Record<string, any>;
}

export interface W3CTokenGroup {
  [key: string]: W3CDesignToken | W3CTokenGroup;
}

export interface W3CTokensFile {
  $schema?: string;
  $description?: string;
  [key: string]: any;
}

/**
 * Internal token representation before conversion to W3C format
 */
export interface Token {
  name: string;
  value: string | number | object;
  type?: TokenType;
  category?: string;
  source: TokenSource;
  priority: number;
  description?: string;
  path: string[]; // Hierarchical path (e.g., ['colors', 'primary', '500'])
  originalKey?: string; // Original key before normalization
  metadata?: Record<string, any>;
}

export enum TokenSource {
  TAILWIND_CONFIG = 'tailwind.config',
  CSS_VARIABLES = 'css-variables',
  THEME_FILE = 'theme-file',
  STYLED_COMPONENTS = 'styled-components',
  EMOTION_THEME = 'emotion-theme',
}

export interface SourcePriority {
  source: TokenSource;
  priority: number;
}

export interface TokenConflict {
  path: string[];
  tokens: Token[];
  resolution: 'auto' | 'manual';
  resolvedToken?: Token;
  reason?: string;
}

export interface ExtractionResult {
  tokens: Token[];
  conflicts: TokenConflict[];
  errors: ExtractionError[];
  sources: {
    [key in TokenSource]?: {
      found: boolean;
      path?: string;
      tokensExtracted: number;
    };
  };
}

export interface ExtractionError {
  source: TokenSource | string;
  message: string;
  error?: Error;
  filePath?: string;
  line?: number;
  column?: number;
}

export interface ExtractionOptions {
  sourcePriorities?: SourcePriority[];
  conflictResolution?: 'priority' | 'manual' | 'merge';
  includeSources?: TokenSource[];
  excludeSources?: TokenSource[];
  outputFormats?: (
    | 'json'
    | 'css'
    | 'markdown'
    | 'typescript'
    | 'tailwind'
    | 'styled-components'
    | 'style-dictionary'
    | 'schema'
  )[];
  outputDir?: string;
  preserveOriginalKeys?: boolean;
  validateTokens?: boolean;
  accessibility?: {
    enabled?: boolean;
    targetLevel?: 'AA' | 'AAA';
    generateFocusStates?: boolean;
    generateTouchTargets?: boolean;
    generateHighContrastAlternatives?: boolean;
  };
  browserExtraction?: {
    enabled?: boolean;
    url?: string;
    includeInteractionStates?: boolean;
    selectors?: string[];
  };
  debate?: {
    enabled?: boolean;
    rounds?: number;
    consensusThreshold?: number;
  };
  validation?: {
    enabled?: boolean;
    generateCertificate?: boolean;
  };
}

/**
 * Tailwind Config Types
 */
export interface TailwindConfig {
  theme?: {
    extend?: Record<string, any>;
    [key: string]: any;
  };
  [key: string]: any;
}

/**
 * CSS Root Variables
 */
export interface CSSVariable {
  name: string;
  value: string;
  source: 'root' | 'custom-selector';
  selector?: string;
}

/**
 * Theme File Types
 */
export interface ThemeConfig {
  colors?: Record<string, any>;
  spacing?: Record<string, any>;
  typography?: Record<string, any>;
  breakpoints?: Record<string, any>;
  shadows?: Record<string, any>;
  [key: string]: any;
}

/**
 * Styled Components / Emotion Theme
 */
export interface StyledTheme {
  colors?: Record<string, any>;
  space?: Record<string, any>;
  fonts?: Record<string, any>;
  fontSizes?: Record<string, any>;
  fontWeights?: Record<string, any>;
  lineHeights?: Record<string, any>;
  radii?: Record<string, any>;
  shadows?: Record<string, any>;
  [key: string]: any;
}

/**
 * Output Formats
 */
export interface OutputFiles {
  json?: string; // Path to tokens.json
  css?: string; // Path to tokens.css
  markdown?: string; // Path to tokens.md
  typescript?: string; // Path to tokens.d.ts
  tailwind?: string; // Path to tailwind.tokens.js
  styledComponents?: string; // Path to tokens.styled.ts
  styleDictionary?: string; // Path to style-dictionary.config.js
  schema?: string; // Path to tokens.schema.json
}

export interface MergeStrategy {
  onConflict: (existing: Token, incoming: Token) => Token;
  shouldMerge: (existing: Token, incoming: Token) => boolean;
}

/**
 * Debate Integration Types
 */
export interface DebateResult {
  rounds: number;
  consensus: DebateConsensus[];
  improvements: TokenChange[];
  auditTrail: string;
  timestamp: string;
}

export interface DebateConsensus {
  topic: string;
  agreement: number; // 0-1
  recommendation: string;
  providers: string[];
}

export interface TokenChange {
  tokenName: string;
  path: string[];
  oldValue: any;
  newValue: any;
  reason: string;
  confidence: number;
  approvedBy: string[];
}

/**
 * Validation Types
 */
export interface ValidationCertificate {
  timestamp: string;
  projectName: string;
  gates: ValidationGate[];
  overallStatus: 'passed' | 'failed' | 'warning';
  recommendations: string[];
  signature: string;
}

export interface ValidationGate {
  name: string;
  description: string;
  status: 'passed' | 'failed' | 'warning';
  details: string;
  required: boolean;
}
