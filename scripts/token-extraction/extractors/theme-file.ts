/**
 * Theme File Extractor
 * Extracts tokens from theme.js/theme.ts files
 */

import * as fs from 'fs';
import * as path from 'path';
import { glob } from 'glob';
import {
  Token,
  TokenSource,
  ThemeConfig,
  ExtractionError,
} from '../types';
import {
  flattenObject,
  createTokenPath,
  inferTokenType,
} from '../utils';

export interface ThemeFileExtractorOptions {
  include?: string[]; // Glob patterns for theme files
  exclude?: string[]; // Patterns to exclude
}

export class ThemeFileExtractor {
  private options: ThemeFileExtractorOptions;
  private errors: ExtractionError[] = [];

  constructor(options: ThemeFileExtractorOptions = {}) {
    this.options = {
      include: [
        '**/theme.js',
        '**/theme.ts',
        '**/themes/*.js',
        '**/themes/*.ts',
        '**/config/theme.js',
        '**/config/theme.ts',
        '**/styles/theme.js',
        '**/styles/theme.ts',
      ],
      exclude: ['**/node_modules/**', '**/dist/**', '**/build/**'],
      ...options,
    };
  }

  async extract(projectRoot: string): Promise<{ tokens: Token[]; errors: ExtractionError[] }> {
    this.errors = [];
    const tokens: Token[] = [];

    try {
      const themeFiles = await this.findThemeFiles(projectRoot);

      for (const filePath of themeFiles) {
        const fileTokens = await this.extractFromFile(filePath, projectRoot);
        tokens.push(...fileTokens);
      }
    } catch (error) {
      this.errors.push({
        source: TokenSource.THEME_FILE,
        message: 'Failed to extract theme file tokens',
        error: error as Error,
      });
    }

    return { tokens, errors: this.errors };
  }

  private async findThemeFiles(projectRoot: string): Promise<string[]> {
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

  private async extractFromFile(
    filePath: string,
    projectRoot: string
  ): Promise<Token[]> {
    const tokens: Token[] = [];

    try {
      const content = fs.readFileSync(filePath, 'utf-8');
      const themeConfig = this.parseThemeFile(content, filePath);

      if (!themeConfig) {
        return tokens;
      }

      // Extract tokens from each category
      for (const [categoryKey, categoryValue] of Object.entries(themeConfig)) {
        if (typeof categoryValue !== 'object' || categoryValue === null) {
          continue;
        }

        const flattened = flattenObject(categoryValue, [categoryKey]);

        for (const { path: tokenPath, value } of flattened) {
          tokens.push({
            name: tokenPath.join('.'),
            value,
            type: inferTokenType(value, tokenPath.join('.')),
            category: categoryKey,
            source: TokenSource.THEME_FILE,
            priority: 7, // High priority for explicit theme files
            path: createTokenPath(tokenPath),
            originalKey: tokenPath.join('.'),
            metadata: {
              sourceFile: path.relative(projectRoot, filePath),
            },
          });
        }
      }
    } catch (error) {
      this.errors.push({
        source: TokenSource.THEME_FILE,
        message: `Failed to extract from file: ${filePath}`,
        error: error as Error,
        filePath,
      });
    }

    return tokens;
  }

  private parseThemeFile(content: string, filePath: string): ThemeConfig | null {
    try {
      // Remove comments
      let cleanContent = content
        .replace(/\/\*[\s\S]*?\*\//g, '')
        .replace(/\/\/.*/g, '');

      // Handle TypeScript
      if (filePath.endsWith('.ts')) {
        cleanContent = this.stripTypeScript(cleanContent);
      }

      // Try to extract theme object
      const themeObject = this.extractThemeObject(cleanContent, filePath);

      return themeObject;
    } catch (error) {
      this.errors.push({
        source: TokenSource.THEME_FILE,
        message: `Failed to parse theme file: ${filePath}`,
        error: error as Error,
        filePath,
      });
      return null;
    }
  }

  private stripTypeScript(content: string): string {
    return content
      .replace(/import\s+.*?from\s+['"].*?['"];?/g, '')
      .replace(/export\s+default\s+/, 'module.exports = ')
      .replace(/export\s+(const|let|var)\s+/g, '$1 ')
      .replace(/:\s*\w+(<[^>]+>)?(\[\])?/g, '') // Remove type annotations
      .replace(/as\s+const/g, '')
      .replace(/as\s+\w+/g, '');
  }

  private extractThemeObject(content: string, filePath: string): ThemeConfig | null {
    try {
      // Look for common export patterns
      const patterns = [
        /export\s+default\s+(\{[\s\S]*\})/,
        /module\.exports\s*=\s*(\{[\s\S]*\})/,
        /const\s+theme\s*=\s*(\{[\s\S]*\})/,
        /const\s+\w+Theme\s*=\s*(\{[\s\S]*\})/,
      ];

      for (const pattern of patterns) {
        const match = content.match(pattern);
        if (match) {
          try {
            // Use Function constructor to safely evaluate
            const themeFunc = new Function(`return ${match[1]}`);
            const theme = themeFunc();
            return theme as ThemeConfig;
          } catch (e) {
            // Try next pattern
            continue;
          }
        }
      }

      this.errors.push({
        source: TokenSource.THEME_FILE,
        message: `Could not find theme object in file: ${filePath}`,
        filePath,
      });

      return null;
    } catch (error) {
      this.errors.push({
        source: TokenSource.THEME_FILE,
        message: `Failed to extract theme object: ${filePath}`,
        error: error as Error,
        filePath,
      });
      return null;
    }
  }

  getErrors(): ExtractionError[] {
    return this.errors;
  }
}

/**
 * Convenience function to extract theme file tokens
 */
export async function extractThemeFileTokens(
  projectRoot: string,
  options?: ThemeFileExtractorOptions
): Promise<{ tokens: Token[]; errors: ExtractionError[] }> {
  const extractor = new ThemeFileExtractor(options);
  return extractor.extract(projectRoot);
}
