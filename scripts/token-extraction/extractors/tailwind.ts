/**
 * Tailwind Config Extractor
 * Parses tailwind.config.js/ts files and extracts design tokens
 */

import * as fs from 'fs';
import * as path from 'path';
import {
  Token,
  TokenSource,
  TailwindConfig,
  ExtractionError,
} from '../types';
import {
  flattenObject,
  createTokenPath,
  inferTokenType,
  normalizeTokenName,
} from '../utils';

export interface TailwindExtractorOptions {
  configPath?: string;
  includeCore?: boolean; // Include Tailwind's default theme
  includeExtend?: boolean; // Include theme.extend values
}

export class TailwindExtractor {
  private options: TailwindExtractorOptions;
  private errors: ExtractionError[] = [];

  constructor(options: TailwindExtractorOptions = {}) {
    this.options = {
      includeCore: false, // Only extract custom values by default
      includeExtend: true,
      ...options,
    };
  }

  async extract(projectRoot: string): Promise<{ tokens: Token[]; errors: ExtractionError[] }> {
    this.errors = [];
    const tokens: Token[] = [];

    try {
      const configPath = await this.findTailwindConfig(projectRoot);
      if (!configPath) {
        this.errors.push({
          source: TokenSource.TAILWIND_CONFIG,
          message: 'No Tailwind config file found',
        });
        return { tokens, errors: this.errors };
      }

      const config = await this.loadConfig(configPath);
      if (!config) {
        return { tokens, errors: this.errors };
      }

      // Extract from theme.extend (custom tokens)
      if (this.options.includeExtend && config.theme?.extend) {
        tokens.push(...this.extractFromTheme(config.theme.extend, 'extend'));
      }

      // Extract from theme (core overrides)
      if (this.options.includeCore && config.theme) {
        const coreTheme = { ...config.theme };
        delete coreTheme.extend;
        tokens.push(...this.extractFromTheme(coreTheme, 'core'));
      }
    } catch (error) {
      this.errors.push({
        source: TokenSource.TAILWIND_CONFIG,
        message: 'Failed to extract Tailwind tokens',
        error: error as Error,
      });
    }

    return { tokens, errors: this.errors };
  }

  private async findTailwindConfig(projectRoot: string): Promise<string | null> {
    const possiblePaths = [
      'tailwind.config.js',
      'tailwind.config.ts',
      'tailwind.config.cjs',
      'tailwind.config.mjs',
    ];

    for (const configFile of possiblePaths) {
      const fullPath = path.join(projectRoot, configFile);
      if (fs.existsSync(fullPath)) {
        return fullPath;
      }
    }

    return null;
  }

  private async loadConfig(configPath: string): Promise<TailwindConfig | null> {
    try {
      const ext = path.extname(configPath);
      const content = fs.readFileSync(configPath, 'utf-8');

      // Handle TypeScript config
      if (ext === '.ts') {
        return this.parseTSConfig(content, configPath);
      }

      // Handle JavaScript config
      return this.parseJSConfig(content, configPath);
    } catch (error) {
      this.errors.push({
        source: TokenSource.TAILWIND_CONFIG,
        message: `Failed to load config: ${configPath}`,
        error: error as Error,
        filePath: configPath,
      });
      return null;
    }
  }

  private parseJSConfig(content: string, filePath: string): TailwindConfig | null {
    try {
      // Remove comments
      const cleanContent = content
        .replace(/\/\*[\s\S]*?\*\//g, '')
        .replace(/\/\/.*/g, '');

      // Extract the config object
      const configMatch = cleanContent.match(/module\.exports\s*=\s*(\{[\s\S]*\})/);
      if (!configMatch) {
        this.errors.push({
          source: TokenSource.TAILWIND_CONFIG,
          message: 'Could not find module.exports in config',
          filePath,
        });
        return null;
      }

      // Use Function constructor to safely evaluate the config
      // This is safer than eval but still requires trusted input
      const configStr = configMatch[1];
      const configFunc = new Function(`return ${configStr}`);
      const config = configFunc();

      return config as TailwindConfig;
    } catch (error) {
      this.errors.push({
        source: TokenSource.TAILWIND_CONFIG,
        message: 'Failed to parse JavaScript config',
        error: error as Error,
        filePath,
      });
      return null;
    }
  }

  private parseTSConfig(content: string, filePath: string): TailwindConfig | null {
    try {
      // Remove TypeScript syntax and comments
      const cleanContent = content
        .replace(/\/\*[\s\S]*?\*\//g, '')
        .replace(/\/\/.*/g, '')
        .replace(/import\s+.*?from\s+['"].*?['"];?/g, '')
        .replace(/export\s+default\s+/, 'module.exports = ')
        .replace(/:\s*Config/g, '');

      return this.parseJSConfig(cleanContent, filePath);
    } catch (error) {
      this.errors.push({
        source: TokenSource.TAILWIND_CONFIG,
        message: 'Failed to parse TypeScript config',
        error: error as Error,
        filePath,
      });
      return null;
    }
  }

  private extractFromTheme(
    theme: Record<string, any>,
    category: 'core' | 'extend'
  ): Token[] {
    const tokens: Token[] = [];
    const priority = category === 'extend' ? 8 : 7; // Custom tokens get higher priority

    // Known Tailwind theme keys and their categories
    const themeCategories: Record<string, string> = {
      colors: 'color',
      spacing: 'spacing',
      fontSize: 'typography',
      fontFamily: 'typography',
      fontWeight: 'typography',
      lineHeight: 'typography',
      letterSpacing: 'typography',
      borderRadius: 'border',
      borderWidth: 'border',
      boxShadow: 'shadow',
      screens: 'breakpoint',
      zIndex: 'z-index',
      opacity: 'opacity',
      transitionDuration: 'transition',
      transitionTimingFunction: 'transition',
      animation: 'animation',
      keyframes: 'animation',
    };

    for (const [themeKey, themeValue] of Object.entries(theme)) {
      if (typeof themeValue !== 'object' || themeValue === null) {
        continue;
      }

      const category = themeCategories[themeKey] || themeKey;
      const flattened = flattenObject(themeValue, [themeKey]);

      for (const { path: tokenPath, value } of flattened) {
        // Skip DEFAULT keys that are just aliases
        if (tokenPath[tokenPath.length - 1] === 'DEFAULT') {
          continue;
        }

        tokens.push({
          name: tokenPath.join('.'),
          value,
          type: inferTokenType(value, tokenPath.join('.')),
          category,
          source: TokenSource.TAILWIND_CONFIG,
          priority,
          path: createTokenPath(tokenPath),
          originalKey: tokenPath.join('.'),
          metadata: {
            tailwindCategory: themeKey,
            isExtend: category === 'extend',
          },
        });
      }
    }

    return tokens;
  }

  getErrors(): ExtractionError[] {
    return this.errors;
  }
}

/**
 * Convenience function to extract Tailwind tokens
 */
export async function extractTailwindTokens(
  projectRoot: string,
  options?: TailwindExtractorOptions
): Promise<{ tokens: Token[]; errors: ExtractionError[] }> {
  const extractor = new TailwindExtractor(options);
  return extractor.extract(projectRoot);
}
