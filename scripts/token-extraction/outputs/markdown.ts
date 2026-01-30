/**
 * Markdown Output Generator
 * Generates human-readable documentation for design tokens
 */

import * as fs from 'fs';
import * as path from 'path';
import { Token, TokenConflict } from '../types';
import { toCSSVariableName } from '../utils';

export interface MarkdownOutputOptions {
  outputPath: string;
  includeConflicts?: boolean;
  includeMetadata?: boolean;
  groupByCategory?: boolean;
  includeStats?: boolean;
}

export class MarkdownOutputGenerator {
  private options: MarkdownOutputOptions;

  constructor(options: MarkdownOutputOptions) {
    this.options = {
      includeConflicts: true,
      includeMetadata: true,
      groupByCategory: true,
      includeStats: true,
      ...options,
    };
  }

  /**
   * Generate Markdown output
   */
  async generate(
    tokens: Token[],
    conflicts?: TokenConflict[]
  ): Promise<void> {
    const markdown = this.toMarkdown(tokens, conflicts);

    // Ensure output directory exists
    const outputDir = path.dirname(this.options.outputPath);
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }

    // Write to file
    fs.writeFileSync(this.options.outputPath, markdown, 'utf-8');
  }

  /**
   * Convert tokens to Markdown
   */
  private toMarkdown(tokens: Token[], conflicts?: TokenConflict[]): string {
    const lines: string[] = [];

    // Add header
    lines.push('# Design Tokens');
    lines.push('');
    lines.push('Design tokens extracted from project sources and converted to W3C Design Tokens format.');
    lines.push('');

    // Add statistics
    if (this.options.includeStats) {
      lines.push(...this.generateStats(tokens, conflicts));
      lines.push('');
    }

    // Add table of contents
    lines.push('## Table of Contents');
    lines.push('');
    lines.push('- [Tokens](#tokens)');

    if (this.options.groupByCategory) {
      const categories = this.getCategories(tokens);
      for (const category of categories) {
        const anchor = this.createAnchor(category);
        lines.push(`  - [${this.formatCategoryName(category)}](#${anchor})`);
      }
    }

    if (this.options.includeConflicts && conflicts && conflicts.length > 0) {
      lines.push('- [Conflicts](#conflicts)');
    }

    lines.push('');

    // Add tokens section
    lines.push('## Tokens');
    lines.push('');

    if (this.options.groupByCategory) {
      const grouped = this.groupByCategory(tokens);

      for (const [category, categoryTokens] of Object.entries(grouped)) {
        lines.push(...this.generateCategoryMarkdown(category, categoryTokens));
        lines.push('');
      }
    } else {
      lines.push(...this.generateTokenTable(tokens));
    }

    // Add conflicts section
    if (this.options.includeConflicts && conflicts && conflicts.length > 0) {
      lines.push('## Conflicts');
      lines.push('');
      lines.push(...this.generateConflictsMarkdown(conflicts));
    }

    return lines.join('\n');
  }

  /**
   * Generate statistics section
   */
  private generateStats(tokens: Token[], conflicts?: TokenConflict[]): string[] {
    const lines: string[] = [];

    lines.push('## Statistics');
    lines.push('');

    // Token count
    lines.push(`- **Total Tokens**: ${tokens.length}`);

    // Tokens by source
    const bySource = this.groupBySource(tokens);
    lines.push('- **Tokens by Source**:');
    for (const [source, count] of Object.entries(bySource)) {
      lines.push(`  - ${source}: ${count}`);
    }

    // Tokens by type
    const byType = this.groupByType(tokens);
    lines.push('- **Tokens by Type**:');
    for (const [type, count] of Object.entries(byType)) {
      lines.push(`  - ${type || 'untyped'}: ${count}`);
    }

    // Conflicts
    if (conflicts && conflicts.length > 0) {
      lines.push(`- **Conflicts**: ${conflicts.length}`);
      const autoResolved = conflicts.filter(c => c.resolution === 'auto').length;
      const manualResolved = conflicts.filter(c => c.resolution === 'manual').length;
      lines.push(`  - Auto-resolved: ${autoResolved}`);
      lines.push(`  - Manual resolution needed: ${manualResolved}`);
    }

    return lines;
  }

  /**
   * Generate category markdown
   */
  private generateCategoryMarkdown(category: string, tokens: Token[]): string[] {
    const lines: string[] = [];

    // Add category header
    const formattedCategory = this.formatCategoryName(category);
    lines.push(`### ${formattedCategory}`);
    lines.push('');

    // Add token table
    lines.push(...this.generateTokenTable(tokens));

    return lines;
  }

  /**
   * Generate token table
   */
  private generateTokenTable(tokens: Token[]): string[] {
    const lines: string[] = [];

    // Table header
    lines.push('| Name | Value | Type | CSS Variable | Source |');
    lines.push('|------|-------|------|--------------|--------|');

    // Sort tokens by path
    const sortedTokens = [...tokens].sort((a, b) =>
      a.path.join('.').localeCompare(b.path.join('.'))
    );

    // Table rows
    for (const token of sortedTokens) {
      const name = token.path.join('.');
      const value = this.formatValue(token.value);
      const type = token.type || '-';
      const cssVar = `\`${toCSSVariableName(token.path)}\``;
      const source = token.source;

      lines.push(`| ${name} | ${value} | ${type} | ${cssVar} | ${source} |`);

      // Add description row if metadata is enabled
      if (this.options.includeMetadata && token.description) {
        lines.push(`| | *${token.description}* | | | |`);
      }
    }

    return lines;
  }

  /**
   * Generate conflicts markdown
   */
  private generateConflictsMarkdown(conflicts: TokenConflict[]): string[] {
    const lines: string[] = [];

    lines.push('The following conflicts were detected during token extraction:');
    lines.push('');

    for (let i = 0; i < conflicts.length; i++) {
      const conflict = conflicts[i];
      const path = conflict.path.join('.');

      lines.push(`### ${i + 1}. \`${path}\``);
      lines.push('');

      if (conflict.reason) {
        lines.push(`**Resolution**: ${conflict.reason}`);
        lines.push('');
      }

      lines.push('**Conflicting values**:');
      lines.push('');

      for (const token of conflict.tokens) {
        const value = this.formatValue(token.value);
        lines.push(`- **${token.source}** (priority ${token.priority}): ${value}`);
      }

      if (conflict.resolvedToken) {
        lines.push('');
        const resolvedValue = this.formatValue(conflict.resolvedToken.value);
        lines.push(`**Resolved to**: ${resolvedValue} (from ${conflict.resolvedToken.source})`);
      }

      lines.push('');
    }

    return lines;
  }

  /**
   * Format value for display
   */
  private formatValue(value: any): string {
    if (typeof value === 'string') {
      // Escape special characters
      const escaped = value.replace(/\|/g, '\\|');

      // Show color preview for hex colors
      if (/^#[0-9a-f]{3,8}$/i.test(value)) {
        return `\`${escaped}\` <span style="background:${value};display:inline-block;width:1em;height:1em;border:1px solid #ccc;vertical-align:middle;"></span>`;
      }

      return `\`${escaped}\``;
    }

    if (typeof value === 'number') {
      return `\`${value}\``;
    }

    if (Array.isArray(value)) {
      return `\`[${value.join(', ')}]\``;
    }

    if (typeof value === 'object') {
      return `\`${JSON.stringify(value)}\``;
    }

    return `\`${String(value)}\``;
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
   * Get all categories
   */
  private getCategories(tokens: Token[]): string[] {
    const categories = new Set<string>();

    for (const token of tokens) {
      categories.add(token.category || 'other');
    }

    return Array.from(categories).sort();
  }

  /**
   * Group tokens by source
   */
  private groupBySource(tokens: Token[]): Record<string, number> {
    const grouped: Record<string, number> = {};

    for (const token of tokens) {
      const source = token.source;
      grouped[source] = (grouped[source] || 0) + 1;
    }

    return grouped;
  }

  /**
   * Group tokens by type
   */
  private groupByType(tokens: Token[]): Record<string, number> {
    const grouped: Record<string, number> = {};

    for (const token of tokens) {
      const type = token.type || 'untyped';
      grouped[type] = (grouped[type] || 0) + 1;
    }

    return grouped;
  }

  /**
   * Format category name
   */
  private formatCategoryName(category: string): string {
    return category
      .split('-')
      .map(word => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ');
  }

  /**
   * Create anchor from category name
   */
  private createAnchor(category: string): string {
    return category.toLowerCase().replace(/\s+/g, '-');
  }
}

/**
 * Convenience function to generate Markdown output
 */
export async function generateMarkdownOutput(
  tokens: Token[],
  options: MarkdownOutputOptions,
  conflicts?: TokenConflict[]
): Promise<void> {
  const generator = new MarkdownOutputGenerator(options);
  await generator.generate(tokens, conflicts);
}
