/**
 * Token Extraction Pipeline
 * Main entry point and public API
 */

// Core pipeline
export { TokenExtractionPipeline, runTokenExtraction } from './pipeline';

// Extractors
export { TailwindExtractor, extractTailwindTokens } from './extractors/tailwind';
export { CSSVariablesExtractor, extractCSSVariables } from './extractors/css-variables';
export { ThemeFileExtractor, extractThemeFileTokens } from './extractors/theme-file';
export {
  StyledComponentsExtractor,
  extractStyledComponentsTokens,
} from './extractors/styled-components';

// Merger
export { TokenMerger, applyPriorities, DEFAULT_SOURCE_PRIORITIES } from './merger';

// Output generators
export { JSONOutputGenerator, generateJSONOutput } from './outputs/json';
export { CSSOutputGenerator, generateCSSOutput } from './outputs/css';
export { MarkdownOutputGenerator, generateMarkdownOutput } from './outputs/markdown';

// Utilities
export * from './utils';

// Types
export * from './types';

// CLI
export * from './cli';
