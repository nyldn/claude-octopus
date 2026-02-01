/**
 * CSS Output Generator
 * Generates CSS custom properties file
 */

import * as fs from 'fs';
import * as path from 'path';
import { Token } from '../types';
import { toCSSVariableName, formatCSSValue } from '../utils';

export interface CSSOutputOptions {
  outputPath: string;
  selector?: string; // CSS selector (default: ':root')
  includeComments?: boolean;
  groupByCategory?: boolean;
  mediaQueries?: Record<string, string>; // e.g., { 'dark': '@media (prefers-color-scheme: dark)' }
}

export class CSSOutputGenerator {
  private options: CSSOutputOptions;

  constructor(options: CSSOutputOptions) {
    this.options = {
      selector: ':root',
      includeComments: true,
      groupByCategory: true,
      ...options,
    };
  }

  /**
   * Generate CSS output
   */
  async generate(tokens: Token[]): Promise<void> {
    const css = this.toCSS(tokens);

    // Ensure output directory exists
    const outputDir = path.dirname(this.options.outputPath);
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }

    // Write to file
    fs.writeFileSync(this.options.outputPath, css, 'utf-8');
  }

  /**
   * Convert tokens to CSS
   */
  private toCSS(tokens: Token[]): string {
    const lines: string[] = [];

    // Add file header
    lines.push('/**');
    lines.push(' * Design Tokens - CSS Custom Properties');
    lines.push(' * Generated from project design token sources');
    lines.push(' * @see https://developer.mozilla.org/en-US/docs/Web/CSS/--*');
    lines.push(' */');
    lines.push('');

    if (this.options.groupByCategory) {
      const grouped = this.groupByCategory(tokens);

      for (const [category, categoryTokens] of Object.entries(grouped)) {
        lines.push(...this.generateCategoryCSS(category, categoryTokens));
        lines.push('');
      }
    } else {
      lines.push(...this.generateCategoryCSS('all', tokens));
    }

    return lines.join('\n');
  }

  /**
   * Group tokens by category
   */
  private groupByCategory(tokens: Token[]): Record<string, Token[]> {
    const grouped: Record<string, Token[]> = {};

    for (const token of tokens) {
      const category = token.category || 'other';

      if (!grouped[category]) {
        grouped[category] = [];
      }

      grouped[category].push(token);
    }

    // Sort categories alphabetically
    const sorted: Record<string, Token[]> = {};
    const sortedKeys = Object.keys(grouped).sort();

    for (const key of sortedKeys) {
      sorted[key] = grouped[key];
    }

    return sorted;
  }

  /**
   * Generate CSS for a category
   */
  private generateCategoryCSS(category: string, tokens: Token[]): string[] {
    const lines: string[] = [];

    // Add category comment
    if (this.options.includeComments && category !== 'all') {
      lines.push(`/* ${this.formatCategoryName(category)} */`);
    }

    // Start selector block
    lines.push(`${this.options.selector} {`);

    // Sort tokens by path for better readability
    const sortedTokens = [...tokens].sort((a, b) =>
      a.path.join('.').localeCompare(b.path.join('.'))
    );

    for (const token of sortedTokens) {
      const varName = toCSSVariableName(token.path);
      const value = formatCSSValue(token.value);

      // Add token comment
      if (this.options.includeComments && token.description) {
        lines.push(`  /* ${token.description} */`);
      }

      // Add token declaration
      lines.push(`  ${varName}: ${value};`);
    }

    lines.push('}');

    return lines;
  }

  /**
   * Format category name for comments
   */
  private formatCategoryName(category: string): string {
    return category
      .split('-')
      .map(word => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ');
  }

  /**
   * Generate CSS with media queries for theme variants
   */
  generateWithMediaQueries(tokens: Token[], themeVariants: Record<string, Token[]>): string {
    const lines: string[] = [];

    // Add file header
    lines.push('/**');
    lines.push(' * Design Tokens - CSS Custom Properties');
    lines.push(' * Includes theme variants with media queries');
    lines.push(' */');
    lines.push('');

    // Generate default theme
    lines.push(this.toCSS(tokens));
    lines.push('');

    // Generate theme variants
    if (this.options.mediaQueries) {
      for (const [variantName, mediaQuery] of Object.entries(this.options.mediaQueries)) {
        const variantTokens = themeVariants[variantName];

        if (!variantTokens || variantTokens.length === 0) {
          continue;
        }

        lines.push(`/* ${this.formatCategoryName(variantName)} Theme */`);
        lines.push(mediaQuery + ' {');
        lines.push(this.toCSS(variantTokens).replace(/^/gm, '  ')); // Indent
        lines.push('}');
        lines.push('');
      }
    }

    return lines.join('\n');
  }
}

/**
 * Convenience function to generate CSS output
 */
export async function generateCSSOutput(
  tokens: Token[],
  options: CSSOutputOptions
): Promise<void> {
  const generator = new CSSOutputGenerator(options);
  await generator.generate(tokens);
}
