/**
 * Styled Components / Emotion Extractor
 * Extracts tokens from styled-components and Emotion theme providers
 */

import * as fs from 'fs';
import * as path from 'path';
import { glob } from 'glob';
import {
  Token,
  TokenSource,
  StyledTheme,
  ExtractionError,
} from '../types';
import {
  flattenObject,
  createTokenPath,
  inferTokenType,
} from '../utils';

export interface StyledComponentsExtractorOptions {
  include?: string[]; // Glob patterns for theme files
  exclude?: string[]; // Patterns to exclude
  providers?: ('styled-components' | 'emotion')[]; // Which libraries to look for
}

export class StyledComponentsExtractor {
  private options: StyledComponentsExtractorOptions;
  private errors: ExtractionError[] = [];

  constructor(options: StyledComponentsExtractorOptions = {}) {
    this.options = {
      include: [
        '**/*theme*.{js,ts,jsx,tsx}',
        '**/styled-components/**/*.{js,ts,jsx,tsx}',
        '**/emotion/**/*.{js,ts,jsx,tsx}',
      ],
      exclude: ['**/node_modules/**', '**/dist/**', '**/build/**', '**/*.test.*', '**/*.spec.*'],
      providers: ['styled-components', 'emotion'],
      ...options,
    };
  }

  async extract(projectRoot: string): Promise<{ tokens: Token[]; errors: ExtractionError[] }> {
    this.errors = [];
    const tokens: Token[] = [];

    try {
      const themeFiles = await this.findThemeFiles(projectRoot);

      for (const filePath of themeFiles) {
        const provider = this.detectProvider(filePath);
        if (provider) {
          const fileTokens = await this.extractFromFile(filePath, provider, projectRoot);
          tokens.push(...fileTokens);
        }
      }
    } catch (error) {
      this.errors.push({
        source: TokenSource.STYLED_COMPONENTS,
        message: 'Failed to extract styled-components/emotion tokens',
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

  private detectProvider(filePath: string): 'styled-components' | 'emotion' | null {
    try {
      const content = fs.readFileSync(filePath, 'utf-8');

      // Check for styled-components imports
      if (
        /from\s+['"]styled-components['"]/.test(content) ||
        /import\s+\{[^}]*ThemeProvider[^}]*\}\s+from\s+['"]styled-components['"]/.test(content)
      ) {
        return 'styled-components';
      }

      // Check for Emotion imports
      if (
        /from\s+['"]@emotion\/react['"]/.test(content) ||
        /from\s+['"]@emotion\/styled['"]/.test(content) ||
        /import\s+\{[^}]*ThemeProvider[^}]*\}\s+from\s+['"]@emotion\/react['"]/.test(content)
      ) {
        return 'emotion';
      }

      return null;
    } catch (error) {
      return null;
    }
  }

  private async extractFromFile(
    filePath: string,
    provider: 'styled-components' | 'emotion',
    projectRoot: string
  ): Promise<Token[]> {
    const tokens: Token[] = [];

    try {
      const content = fs.readFileSync(filePath, 'utf-8');
      const theme = this.parseThemeProvider(content, filePath);

      if (!theme) {
        return tokens;
      }

      // Extract tokens from theme object
      for (const [categoryKey, categoryValue] of Object.entries(theme)) {
        if (typeof categoryValue !== 'object' || categoryValue === null) {
          continue;
        }

        const flattened = flattenObject(categoryValue, [categoryKey]);

        for (const { path: tokenPath, value } of flattened) {
          const source =
            provider === 'styled-components'
              ? TokenSource.STYLED_COMPONENTS
              : TokenSource.EMOTION_THEME;

          tokens.push({
            name: tokenPath.join('.'),
            value,
            type: inferTokenType(value, tokenPath.join('.')),
            category: this.mapCategoryToStandard(categoryKey),
            source,
            priority: 7, // High priority for explicit theme providers
            path: createTokenPath(tokenPath),
            originalKey: tokenPath.join('.'),
            metadata: {
              provider,
              sourceFile: path.relative(projectRoot, filePath),
            },
          });
        }
      }
    } catch (error) {
      this.errors.push({
        source: TokenSource.STYLED_COMPONENTS,
        message: `Failed to extract from file: ${filePath}`,
        error: error as Error,
        filePath,
      });
    }

    return tokens;
  }

  private parseThemeProvider(content: string, filePath: string): StyledTheme | null {
    try {
      // Remove comments
      let cleanContent = content
        .replace(/\/\*[\s\S]*?\*\//g, '')
        .replace(/\/\/.*/g, '');

      // Strip TypeScript syntax
      if (filePath.endsWith('.ts') || filePath.endsWith('.tsx')) {
        cleanContent = this.stripTypeScript(cleanContent);
      }

      // Look for theme objects
      const theme = this.extractThemeObject(cleanContent, filePath);

      return theme;
    } catch (error) {
      this.errors.push({
        source: TokenSource.STYLED_COMPONENTS,
        message: `Failed to parse theme provider: ${filePath}`,
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
      .replace(/as\s+\w+/g, '')
      .replace(/<[^>]+>/g, ''); // Remove generic types
  }

  private extractThemeObject(content: string, filePath: string): StyledTheme | null {
    try {
      // Look for common theme patterns
      const patterns = [
        // export const theme = { ... }
        /export\s+const\s+theme\s*=\s*(\{[\s\S]*?\n\})/,
        // const theme = { ... }
        /const\s+theme\s*=\s*(\{[\s\S]*?\n\})/,
        // export default { ... }
        /export\s+default\s+(\{[\s\S]*?\n\})/,
        // <ThemeProvider theme={{ ... }}>
        /<ThemeProvider\s+theme=\{\{([\s\S]*?)\}\}>/,
        // ThemeProvider theme={ ... }
        /theme=\{(\{[\s\S]*?\})\}/,
      ];

      for (const pattern of patterns) {
        const match = content.match(pattern);
        if (match) {
          try {
            const themeStr = match[1];
            // Use Function constructor to safely evaluate
            const themeFunc = new Function(`return ${themeStr}`);
            const theme = themeFunc();
            return theme as StyledTheme;
          } catch (e) {
            // Try next pattern
            continue;
          }
        }
      }

      return null;
    } catch (error) {
      this.errors.push({
        source: TokenSource.STYLED_COMPONENTS,
        message: `Failed to extract theme object: ${filePath}`,
        error: error as Error,
        filePath,
      });
      return null;
    }
  }

  private mapCategoryToStandard(category: string): string {
    const mapping: Record<string, string> = {
      colors: 'color',
      space: 'spacing',
      spacing: 'spacing',
      fonts: 'typography',
      fontSizes: 'typography',
      fontWeights: 'typography',
      lineHeights: 'typography',
      radii: 'border',
      borderRadius: 'border',
      shadows: 'shadow',
      boxShadow: 'shadow',
      zIndices: 'z-index',
      transitions: 'transition',
      breakpoints: 'breakpoint',
    };

    return mapping[category] || category;
  }

  getErrors(): ExtractionError[] {
    return this.errors;
  }
}

/**
 * Convenience function to extract styled-components/emotion tokens
 */
export async function extractStyledComponentsTokens(
  projectRoot: string,
  options?: StyledComponentsExtractorOptions
): Promise<{ tokens: Token[]; errors: ExtractionError[] }> {
  const extractor = new StyledComponentsExtractor(options);
  return extractor.extract(projectRoot);
}
