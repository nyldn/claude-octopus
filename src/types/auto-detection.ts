/**
 * Auto-Detection Engine Type Definitions
 *
 * Comprehensive type system for the auto-detection engine that identifies
 * frontend project characteristics through static analysis.
 */

// ============================================================================
// Core Detection Results
// ============================================================================

export interface DetectionResult {
  // Detected characteristics
  framework?: FrameworkDetection;
  styling?: StylingDetection[];
  buildTool?: BuildToolDetection;
  tokens?: TokenDetection[];
  components?: ComponentDetection[];
  routing?: RoutingDetection;
  stateManagement?: StateManagementDetection[];
  designSystem?: DesignSystemDetection;
  architecture?: ArchitectureDetection;

  // Metadata
  confidence: number;
  errors: DetectionError[];
  warnings: string[];
  partial: boolean;
  timestamp: number;
  projectPath: string;

  // Monorepo support
  monorepo?: MonorepoDetectionResult;
}

// ============================================================================
// Framework Detection
// ============================================================================

export type FrameworkType = 'react' | 'vue' | 'angular' | 'svelte' | 'vanilla';

export interface FrameworkDetection {
  framework: FrameworkType;
  version?: string;
  confidence: number;
  signals: FrameworkSignal[];
  alternatives?: AlternativeDetection[];

  // Framework-specific metadata
  metadata: {
    // React
    isNext?: boolean;
    nextVersion?: string;
    isRemix?: boolean;

    // Vue
    isNuxt?: boolean;
    nuxtVersion?: string;
    vueVersion?: 2 | 3;

    // Angular
    angularVersion?: number;
    isStandalone?: boolean;

    // Svelte
    isSvelteKit?: boolean;
  };
}

export interface FrameworkSignal {
  type: 'dependency' | 'file-pattern' | 'content' | 'config';
  source: string;
  score: number;
  framework: FrameworkType;
  details?: Record<string, any>;
}

// ============================================================================
// Styling Detection
// ============================================================================

export type StylingMethod =
  | 'tailwind'
  | 'css-modules'
  | 'styled-components'
  | 'emotion'
  | 'scss'
  | 'sass'
  | 'less'
  | 'vanilla-css'
  | 'css-in-js'
  | 'linaria'
  | 'stitches'
  | 'vanilla-extract';

export interface StylingDetection {
  method: StylingMethod;
  confidence: number;
  signals: StylingSignal[];
  configFiles?: string[];

  // Method-specific metadata
  metadata: {
    // Tailwind
    tailwindVersion?: string;
    hasCustomConfig?: boolean;
    plugins?: string[];

    // CSS Modules
    moduleCount?: number;

    // Styled Components / Emotion
    hasTheme?: boolean;

    // SCSS
    sassVersion?: string;
  };
}

export interface StylingSignal {
  type: 'dependency' | 'file-pattern' | 'usage' | 'config';
  source: string;
  score: number;
  method: StylingMethod;
}

// ============================================================================
// Build Tool Detection
// ============================================================================

export type BuildToolType =
  | 'vite'
  | 'webpack'
  | 'parcel'
  | 'esbuild'
  | 'rollup'
  | 'turbopack'
  | 'rspack'
  | 'swc';

export interface BuildToolDetection {
  tool: BuildToolType;
  version?: string;
  confidence: number;
  signals: BuildToolSignal[];
  configFile?: string;

  metadata: {
    plugins?: string[];
    entryPoint?: string;
    outputDir?: string;
  };
}

export interface BuildToolSignal {
  type: 'config' | 'dependency' | 'script' | 'output';
  source: string;
  score: number;
  tool: BuildToolType;
}

// ============================================================================
// Token Detection
// ============================================================================

export interface TokenDetection {
  file: string;
  type: 'javascript' | 'css' | 'json' | 'tailwind';
  tokens: DesignTokens;
  confidence: number;
}

export interface DesignTokens {
  colors?: Record<string, string | Record<string, string>>;
  spacing?: Record<string, string>;
  typography?: TypographyTokens;
  breakpoints?: Record<string, string>;
  shadows?: Record<string, string>;
  borderRadius?: Record<string, string>;
  zIndex?: Record<string, number>;
  transitions?: Record<string, string>;
  animations?: Record<string, string>;
}

export interface TypographyTokens {
  fontFamily?: Record<string, string | string[]>;
  fontSize?: Record<string, string | [string, { lineHeight: string }]>;
  fontWeight?: Record<string, number | string>;
  lineHeight?: Record<string, string>;
  letterSpacing?: Record<string, string>;
}

export interface CSSVariable {
  name: string;
  value: string;
  category: TokenCategory;
  file: string;
}

export type TokenCategory =
  | 'color'
  | 'spacing'
  | 'typography'
  | 'shadow'
  | 'borderRadius'
  | 'breakpoint'
  | 'animation'
  | 'other';

// ============================================================================
// Component Detection
// ============================================================================

export interface ComponentDetection {
  directories: ComponentDirectory[];
  totalComponents: number;
  patterns: ComponentPattern[];
}

export interface ComponentDirectory {
  path: string;
  type: ComponentDirectoryType;
  componentCount: number;
  confidence: number;
  subdirectories?: string[];
  hasIndex?: boolean;
}

export type ComponentDirectoryType =
  | 'shared'
  | 'layout'
  | 'page'
  | 'form'
  | 'ui'
  | 'feature'
  | 'general';

export interface ComponentPattern {
  pattern: string;
  description: string;
  examples: string[];
}

// ============================================================================
// Routing Detection
// ============================================================================

export interface RoutingDetection {
  type: 'file-based' | 'library' | 'config' | 'none';
  confidence: number;
  details: FileBasedRouting | LibraryRouting | ConfigRouting;
}

export interface FileBasedRouting {
  framework: 'next-app' | 'next-pages' | 'nuxt' | 'sveltekit' | 'remix';
  pattern: string;
  routeFiles: string[];
  dynamicRoutes?: string[];
  nestedRoutes?: string[];
}

export interface LibraryRouting {
  library: 'react-router' | 'vue-router' | 'angular-router' | 'reach-router' | 'wouter';
  version?: string;
  configFile?: string;
}

export interface ConfigRouting {
  file: string;
  routes: RouteDefinition[];
  format: 'object' | 'array' | 'function';
}

export interface RouteDefinition {
  path: string;
  type: string;
  component?: string;
  children?: RouteDefinition[];
}

// ============================================================================
// State Management Detection
// ============================================================================

export type StateManagementLibrary =
  | 'redux'
  | 'redux-toolkit'
  | 'zustand'
  | 'jotai'
  | 'recoil'
  | 'mobx'
  | 'vuex'
  | 'pinia'
  | 'xstate'
  | 'ngrx'
  | 'akita'
  | 'svelte-stores'
  | 'react-context';

export interface StateManagementDetection {
  library: StateManagementLibrary;
  type: 'global' | 'atomic' | 'state-machine' | 'builtin';
  version?: string;
  confidence: number;
  storeFiles?: string[];
  storeDirectories?: string[];
}

// ============================================================================
// Design System Detection
// ============================================================================

export interface DesignSystemDetection {
  hasDesignSystem: boolean;
  confidence: number;
  indicators: DesignSystemIndicator[];

  metadata: {
    name?: string;
    hasStorybook?: boolean;
    storybookVersion?: string;
    hasDocumentation?: boolean;
    componentCount?: number;
  };
}

export interface DesignSystemIndicator {
  type: 'package-name' | 'directory' | 'storybook' | 'documentation' | 'tokens' | 'components';
  score: number;
  details?: string;
}

// ============================================================================
// Architecture Detection
// ============================================================================

export interface ArchitectureDetection {
  patterns: ArchitecturePattern[];
  layers: ArchitectureLayer[];
  apiClients: APIClientDetection[];
  services: ServiceLayerDetection[];
  dataLayer: DataLayerDetection;
  confidence: Record<string, number>;
}

export type ArchitecturePatternType =
  | 'feature-based'
  | 'layered'
  | 'domain-driven'
  | 'clean-architecture'
  | 'hexagonal'
  | 'mvc'
  | 'mvvm';

export interface ArchitecturePattern {
  type: ArchitecturePatternType;
  confidence: number;
  details?: Record<string, any>;
}

export interface ArchitectureLayer {
  name: 'presentation' | 'application' | 'domain' | 'infrastructure' | 'data';
  directories: string[];
  confidence: number;
}

export interface APIClientDetection {
  file: string;
  library: 'axios' | 'fetch' | 'ky' | 'got' | 'superagent' | 'other';
  confidence: number;
}

export interface ServiceLayerDetection {
  directory?: string;
  pattern?: 'centralized' | 'scattered';
  files?: string[];
  fileCount: number;
  confidence: number;
}

export interface DataLayerDetection {
  hasLayer: boolean;
  patterns: DataLayerPattern[];
}

export interface DataLayerPattern {
  type: 'repository' | 'models' | 'orm' | 'query-builder';
  name?: string;
  directory?: string;
  directories?: string[];
  confidence: number;
}

// ============================================================================
// Monorepo Support
// ============================================================================

export interface MonorepoDetectionResult {
  isMonorepo: boolean;
  tool?: 'lerna' | 'nx' | 'turborepo' | 'pnpm' | 'yarn' | 'npm';
  root?: string;
  workspaces?: WorkspaceDetection[];
  commonPatterns?: CommonPattern[];
}

export interface WorkspaceDetection {
  workspace: WorkspaceInfo;
  detection: DetectionResult;
}

export interface WorkspaceInfo {
  path: string;
  name: string;
  type: 'app' | 'package' | 'shared' | 'tool';
}

export interface CommonPattern {
  pattern: string;
  workspaces: string[];
  frequency: number;
}

// ============================================================================
// Alternative Detections
// ============================================================================

export interface AlternativeDetection {
  name: string;
  confidence: number;
  reason?: string;
}

// ============================================================================
// Detection Signals
// ============================================================================

export type SignalType =
  | 'packageJson'
  | 'configFile'
  | 'filePattern'
  | 'contentAnalysis'
  | 'naming'
  | 'directory';

export interface Signal {
  type: SignalType;
  source: string;
  score: number;
  weight: number;
  details?: Record<string, any>;
}

// ============================================================================
// Error Handling
// ============================================================================

export class DetectionError extends Error {
  constructor(
    message: string,
    public code: DetectionErrorCode,
    public recoverable: boolean = true,
    public context?: Record<string, any>
  ) {
    super(message);
    this.name = 'DetectionError';
  }
}

export type DetectionErrorCode =
  | 'FILE_NOT_FOUND'
  | 'PARSE_ERROR'
  | 'INVALID_CONFIG'
  | 'PERMISSION_DENIED'
  | 'TIMEOUT'
  | 'CORRUPTED_FILE'
  | 'CIRCULAR_REFERENCE'
  | 'UNKNOWN_ERROR';

// ============================================================================
// Configuration
// ============================================================================

export interface DetectionOptions {
  // Performance
  maxFileSize?: number;
  maxSampleFiles?: number;
  cacheEnabled?: boolean;
  cacheTTL?: number;
  timeout?: number;

  // Behavior
  confidenceThresholds?: ConfidenceThresholds;
  includeAlternatives?: boolean;
  deepAnalysis?: boolean;
  parallelDetection?: boolean;

  // Filtering
  excludePatterns?: string[];
  includePatterns?: string[];
  ignoreNodeModules?: boolean;

  // Monorepo
  detectWorkspaces?: boolean;
  workspaceFilter?: (workspace: WorkspaceInfo) => boolean;
  maxWorkspaces?: number;

  // Debugging
  verbose?: boolean;
  logLevel?: 'error' | 'warn' | 'info' | 'debug';
}

export interface ConfidenceThresholds {
  framework: number;
  buildTool: number;
  styling: number;
  routing: number;
  stateManagement: number;
  tokens: number;
  components: number;
  architecture: number;
  designSystem: number;
}

export const DEFAULT_CONFIDENCE_THRESHOLDS: ConfidenceThresholds = {
  framework: 0.7,
  buildTool: 0.6,
  styling: 0.5,
  routing: 0.6,
  stateManagement: 0.6,
  tokens: 0.5,
  components: 0.4,
  architecture: 0.5,
  designSystem: 0.5,
};

// ============================================================================
// File Patterns
// ============================================================================

export interface FilePatterns {
  framework: Record<FrameworkType, string[]>;
  styling: Record<StylingMethod, string[]>;
  buildTool: Record<BuildToolType, string[]>;
  tokens: string[];
  components: string[];
}

export const FRAMEWORK_PATTERNS: Record<FrameworkType, string[]> = {
  react: [
    '**/package.json',
    '**/*.jsx',
    '**/*.tsx',
    '**/next.config.{js,mjs,ts}',
    '**/remix.config.js',
  ],
  vue: [
    '**/package.json',
    '**/*.vue',
    '**/nuxt.config.{js,ts}',
    '**/vue.config.js',
  ],
  angular: [
    '**/package.json',
    '**/angular.json',
    '**/*.component.ts',
    '**/*.module.ts',
  ],
  svelte: [
    '**/package.json',
    '**/*.svelte',
    '**/svelte.config.js',
  ],
  vanilla: [
    '**/package.json',
    '**/index.html',
    '**/*.{js,ts}',
  ],
};

export const STYLING_PATTERNS: Record<StylingMethod, string[]> = {
  tailwind: [
    '**/tailwind.config.{js,ts,cjs}',
    '**/postcss.config.js',
  ],
  'css-modules': [
    '**/*.module.{css,scss,sass}',
  ],
  'styled-components': [
    '**/package.json',
  ],
  emotion: [
    '**/package.json',
  ],
  scss: [
    '**/*.scss',
  ],
  sass: [
    '**/*.sass',
  ],
  less: [
    '**/*.less',
  ],
  'vanilla-css': [
    '**/*.css',
  ],
  'css-in-js': [],
  linaria: [
    '**/package.json',
  ],
  stitches: [
    '**/package.json',
  ],
  'vanilla-extract': [
    '**/*.css.ts',
  ],
};

export const BUILD_TOOL_PATTERNS: Record<BuildToolType, string[]> = {
  vite: [
    '**/vite.config.{js,ts,mjs}',
  ],
  webpack: [
    '**/webpack.config.{js,ts}',
    '**/webpack.*.js',
  ],
  parcel: [
    '**/.parcelrc',
  ],
  esbuild: [
    '**/esbuild.config.{js,mjs}',
  ],
  rollup: [
    '**/rollup.config.{js,ts,mjs}',
  ],
  turbopack: [
    '**/turbo.json',
  ],
  rspack: [
    '**/rspack.config.{js,ts}',
  ],
  swc: [
    '**/.swcrc',
  ],
};

export const TOKEN_FILE_PATTERNS = [
  '**/theme.{ts,js}',
  '**/tokens.{ts,js}',
  '**/design-tokens.{ts,js,json}',
  '**/tailwind.config.{js,ts}',
  '**/:root.css',
  '**/variables.css',
  '**/theme.css',
];

export const COMPONENT_DIR_PATTERNS = [
  '**/components',
  '**/component',
  '**/ui',
  '**/elements',
  '**/widgets',
  '**/shared',
  '**/common',
];

// ============================================================================
// Cache
// ============================================================================

export interface CacheEntry<T> {
  data: T;
  timestamp: number;
  hits: number;
}

export interface DetectionCache {
  get<T>(key: string): T | undefined;
  set<T>(key: string, value: T, ttl?: number): void;
  invalidate(key: string): void;
  clear(): void;
  size(): number;
}

// ============================================================================
// Engine Interface
// ============================================================================

export interface IAutoDetectionEngine {
  /**
   * Run full detection on a project
   */
  detect(projectPath: string, options?: DetectionOptions): Promise<DetectionResult>;

  /**
   * Run incremental detection (faster, uses cache)
   */
  detectIncremental(
    projectPath: string,
    changedFiles?: string[],
    options?: DetectionOptions
  ): Promise<DetectionResult>;

  /**
   * Detect specific aspects
   */
  detectFramework(projectPath: string): Promise<FrameworkDetection | undefined>;
  detectStyling(projectPath: string): Promise<StylingDetection[]>;
  detectBuildTool(projectPath: string): Promise<BuildToolDetection | undefined>;
  detectTokens(projectPath: string): Promise<TokenDetection[]>;
  detectComponents(projectPath: string, framework?: FrameworkType): Promise<ComponentDetection | undefined>;
  detectRouting(projectPath: string, framework?: FrameworkType): Promise<RoutingDetection | undefined>;
  detectStateManagement(projectPath: string, framework?: FrameworkType): Promise<StateManagementDetection[]>;
  detectArchitecture(projectPath: string): Promise<ArchitectureDetection | undefined>;
  detectDesignSystem(projectPath: string): Promise<DesignSystemDetection | undefined>;

  /**
   * Cache management
   */
  clearCache(): void;
  getCacheStats(): { size: number; hits: number; misses: number };

  /**
   * Configuration
   */
  configure(options: DetectionOptions): void;
  getConfiguration(): DetectionOptions;
}
