/**
 * Component Analysis Engine - Main Export
 */

export { ComponentAnalysisEngine } from './engine';
export { TypeScriptAnalyzer } from './analyzers/typescript-analyzer';
export { PropExtractor } from './analyzers/prop-extractor';
export { VariantDetector } from './analyzers/variant-detector';
export { UsageTracker } from './analyzers/usage-tracker';
export { InventoryGenerator } from './generators/inventory-generator';

export * from './types';

// Default configuration
export const DEFAULT_CONFIG = {
  rootDir: process.cwd(),
  include: [
    '**/*.tsx',
    '**/*.ts',
    '**/*.jsx',
    '**/*.js',
    '**/*.vue',
    '**/*.svelte'
  ],
  exclude: [
    '**/node_modules/**',
    '**/dist/**',
    '**/build/**',
    '**/*.test.*',
    '**/*.spec.*',
    '**/__tests__/**'
  ],
  frameworks: [
    'react',
    'vue',
    'svelte'
  ] as any[],
  detectVariants: true,
  trackUsages: true,
  extractDocs: true,
  maxFileSize: 1024 * 1024, // 1MB
  parallelism: 4
};
