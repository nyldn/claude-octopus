/**
 * CSS Variables Extractor
 * Extracts CSS custom properties from :root and other selectors
 */

import * as fs from 'fs';
import * as path from 'path';
import { glob } from 'glob';
import {
  Token,
  TokenSource,
  CSSVariable,
  ExtractionError,
} from '../types';
import {
  parseCSSVariableName,
  inferTokenType,
  createTokenPath,
} from '../utils';

export interface CSSVariablesExtractorOptions {
  include?: string[]; // Glob patterns to include
  exclude?: string[]; // Glob patterns to exclude
  selectors?: string[]; // CSS selectors to extract from (default: [':root'])
}

export class CSSVariablesExtractor {
  private options: CSSVariablesExtractorOptions;
  private errors: ExtractionError[] = [];

  constructor(options: CSSVariablesExtractorOptions = {}) {
    this.options = {
      include: ['**/*.css', '**/*.scss', '**/*.sass', '**/*.less'],
      exclude: ['**/node_modules/**', '**/dist/**', '**/build/**'],
      selectors: [':root', '[data-theme="light"]', '[data-theme="dark"]'],
      ...options,
    };
  }

  async extract(projectRoot: string): Promise<{ tokens: Token[]; errors: ExtractionError[] }> {
    this.errors = [];
    const tokens: Token[] = [];

    try {
      const cssFiles = await this.findCSSFiles(projectRoot);

      for (const filePath of cssFiles) {
        const fileTokens = await this.extractFromFile(filePath);
        tokens.push(...fileTokens);
      }
    } catch (error) {
      this.errors.push({
        source: TokenSource.CSS_VARIABLES,
        message: 'Failed to extract CSS variables',
        error: error as Error,
      });
    }

    return { tokens, errors: this.errors };
  }

  private async findCSSFiles(projectRoot: string): Promise<string[]> {
    const files: string[] = [];

    for (const pattern of this.options.include!) {
      const matches = await glob(pattern, {
        cwd: projectRoot,
        absolute: true,
        ignore: this.options.exclude,
      });
      files.push(...matches);
    }

    return files;
  }

  private async extractFromFile(filePath: string): Promise<Token[]> {
    const tokens: Token[] = [];

    try {
      const content = fs.readFileSync(filePath, 'utf-8');
      const variables = this.parseCSSVariables(content);

      for (const variable of variables) {
        const path = parseCSSVariableName(variable.name);

        tokens.push({
          name: variable.name,
          value: variable.value.trim(),
          type: inferTokenType(variable.value.trim(), variable.name),
          category: this.categorizeVariable(variable.name),
          source: TokenSource.CSS_VARIABLES,
          priority: 6, // Medium priority
          path: createTokenPath(path),
          originalKey: variable.name,
          metadata: {
            selector: variable.selector,
            sourceFile: path.relative(process.cwd(), filePath),
          },
        });
      }
    } catch (error) {
      this.errors.push({
        source: TokenSource.CSS_VARIABLES,
        message: `Failed to extract from file: ${filePath}`,
        error: error as Error,
        filePath,
      });
    }

    return tokens;
  }

  private parseCSSVariables(content: string): CSSVariable[] {
    const variables: CSSVariable[] = [];

    // Remove comments
    const cleanContent = content
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/\/\/.*/g, '');

    // Match CSS rules with selectors
    const ruleRegex = /([^{}]+)\{([^}]+)\}/g;
    let match;

    while ((match = ruleRegex.exec(cleanContent)) !== null) {
      const selector = match[1].trim();
      const declarations = match[2];

      // Check if selector matches our target selectors
      const isTargetSelector = this.options.selectors!.some(
        target => selector.includes(target)
      );

      if (!isTargetSelector) {
        continue;
      }

      // Extract CSS custom properties
      const propRegex = /(--[\w-]+)\s*:\s*([^;]+);/g;
      let propMatch;

      while ((propMatch = propRegex.exec(declarations)) !== null) {
        const name = propMatch[1].trim();
        const value = propMatch[2].trim();

        variables.push({
          name,
          value,
          source: selector === ':root' ? 'root' : 'custom-selector',
          selector,
        });
      }
    }

    return variables;
  }

  private categorizeVariable(name: string): string {
    const nameLower = name.toLowerCase();

    if (nameLower.includes('color') || nameLower.includes('bg')) {
      return 'color';
    }
    if (
      nameLower.includes('space') ||
      nameLower.includes('gap') ||
      nameLower.includes('margin') ||
      nameLower.includes('padding')
    ) {
      return 'spacing';
    }
    if (nameLower.includes('font')) {
      return 'typography';
    }
    if (nameLower.includes('shadow')) {
      return 'shadow';
    }
    if (nameLower.includes('radius') || nameLower.includes('border')) {
      return 'border';
    }
    if (nameLower.includes('z-index') || nameLower.includes('zindex')) {
      return 'z-index';
    }
    if (nameLower.includes('duration') || nameLower.includes('transition')) {
      return 'transition';
    }

    return 'other';
  }

  getErrors(): ExtractionError[] {
    return this.errors;
  }
}

/**
 * Convenience function to extract CSS variables
 */
export async function extractCSSVariables(
  projectRoot: string,
  options?: CSSVariablesExtractorOptions
): Promise<{ tokens: Token[]; errors: ExtractionError[] }> {
  const extractor = new CSSVariablesExtractor(options);
  return extractor.extract(projectRoot);
}
