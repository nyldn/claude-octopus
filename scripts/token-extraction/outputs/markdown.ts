/**
 * Markdown Output Generator
 * Generates human-readable documentation for design tokens
 */

import * as fs from 'fs';
import * as path from 'path';
import { Token, TokenConflict } from '../types';
import { toCSSVariableName } from '../utils';
import { AccessibilityReport } from '../accessibility/types';

export interface MarkdownOutputOptions {
  outputPath: string;
  includeConflicts?: boolean;
  includeMetadata?: boolean;
  groupByCategory?: boolean;
  includeStats?: boolean;
  accessibilityReport?: AccessibilityReport;
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

    if (this.options.accessibilityReport) {
      lines.push('- [Accessibility Audit](#accessibility-audit)');
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

    // Add accessibility section
    if (this.options.accessibilityReport) {
      lines.push('## Accessibility Audit');
      lines.push('');
      lines.push(...this.generateAccessibilityMarkdown(this.options.accessibilityReport));
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

  /**
   * Generate accessibility audit markdown
   */
  private generateAccessibilityMarkdown(report: AccessibilityReport): string[] {
    const lines: string[] = [];

    lines.push(`**Audit Timestamp**: ${new Date(report.timestamp).toLocaleString()}`);
    lines.push('');

    // Summary
    lines.push('### Summary');
    lines.push('');
    lines.push(`- **Total Color Pairs Tested**: ${report.totalColorPairs}`);
    lines.push(`- **WCAG AA Compliant**: ${report.summary.passAA} (${report.summary.percentCompliant.toFixed(1)}%)`);
    lines.push(`- **WCAG AAA Compliant**: ${report.summary.passAAA}`);
    lines.push(`- **Violations**: ${report.summary.fail}`);
    lines.push('');

    // Generated tokens
    if (report.generatedTokens.focusStates > 0 || report.generatedTokens.touchTargets > 0) {
      lines.push('### Generated Accessibility Tokens');
      lines.push('');
      if (report.generatedTokens.focusStates > 0) {
        lines.push(`- **Focus States**: ${report.generatedTokens.focusStates} tokens`);
      }
      if (report.generatedTokens.touchTargets > 0) {
        lines.push(`- **Touch Targets**: ${report.generatedTokens.touchTargets} tokens`);
      }
      if (report.generatedTokens.highContrastAlternatives > 0) {
        lines.push(`- **High Contrast Alternatives**: ${report.generatedTokens.highContrastAlternatives} tokens`);
      }
      lines.push('');
    }

    // Violations
    if (report.violations.length > 0) {
      lines.push('### Contrast Violations');
      lines.push('');

      const criticalViolations = report.violations.filter(v => v.severity === 'critical');
      const warningViolations = report.violations.filter(v => v.severity === 'warning');

      if (criticalViolations.length > 0) {
        lines.push(`#### Critical (${criticalViolations.length})`);
        lines.push('');
        lines.push('| Foreground | Background | Ratio | WCAG Level | Recommendation |');
        lines.push('|------------|------------|-------|------------|----------------|');

        for (const violation of criticalViolations.slice(0, 10)) {
          const fg = violation.affectedTokens.foreground || violation.foreground;
          const bg = violation.affectedTokens.background || violation.background;
          const ratio = `${violation.ratio.toFixed(2)}:1`;
          const level = violation.wcagLevel;
          const rec = violation.recommendation || 'Adjust colors';

          lines.push(`| ${fg} | ${bg} | ${ratio} | ${level} | ${rec} |`);
        }

        if (criticalViolations.length > 10) {
          lines.push(`| ... | ... | ... | ... | *${criticalViolations.length - 10} more* |`);
        }

        lines.push('');
      }

      if (warningViolations.length > 0) {
        lines.push(`#### Warnings (${warningViolations.length})`);
        lines.push('');
        lines.push('| Foreground | Background | Ratio | WCAG Level |');
        lines.push('|------------|------------|-------|------------|');

        for (const violation of warningViolations.slice(0, 5)) {
          const fg = violation.affectedTokens.foreground || violation.foreground;
          const bg = violation.affectedTokens.background || violation.background;
          const ratio = `${violation.ratio.toFixed(2)}:1`;
          const level = violation.wcagLevel;

          lines.push(`| ${fg} | ${bg} | ${ratio} | ${level} |`);
        }

        if (warningViolations.length > 5) {
          lines.push(`| ... | ... | ... | *${warningViolations.length - 5} more* |`);
        }

        lines.push('');
      }
    }

    // Warnings
    if (report.warnings.length > 0) {
      lines.push('### Warnings');
      lines.push('');
      for (const warning of report.warnings) {
        lines.push(`- ⚠️  ${warning}`);
      }
      lines.push('');
    }

    // Recommendations
    if (report.recommendations.length > 0) {
      lines.push('### Recommendations');
      lines.push('');
      for (const recommendation of report.recommendations) {
        lines.push(`- ${recommendation}`);
      }
      lines.push('');
    }

    return lines;
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
