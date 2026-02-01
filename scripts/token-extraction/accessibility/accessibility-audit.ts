/**
 * Accessibility Auditor
 * Main module for running accessibility audits on design tokens
 */

import { Token, TokenType } from '../types';
import {
  AccessibilityReport,
  AccessibilityAuditOptions,
  DEFAULT_ACCESSIBILITY_OPTIONS,
  ColorPair,
  ContrastViolation,
  FocusStateConfig,
  TouchTargetConfig,
} from './types';
import {
  calculateContrastRatio,
  getWCAGLevel,
  checkWCAGCompliance,
  adjustColorForContrast,
} from './wcag-contrast';

export class AccessibilityAuditor {
  private options: Required<AccessibilityAuditOptions>;

  constructor(options: AccessibilityAuditOptions = {}) {
    this.options = {
      ...DEFAULT_ACCESSIBILITY_OPTIONS,
      ...options,
    };
  }

  /**
   * Run full accessibility audit on tokens
   */
  public auditTokens(tokens: Token[]): AccessibilityReport {
    const timestamp = new Date().toISOString();
    const colorPairs = this.generateColorPairs(tokens);
    const violations: ContrastViolation[] = [];
    const warnings: string[] = [];

    let passAA = 0;
    let passAAA = 0;
    let fail = 0;

    // Check each color pair for contrast violations
    for (const pair of colorPairs) {
      const ratio = calculateContrastRatio(pair.foreground, pair.background);
      const wcagLevel = getWCAGLevel(ratio);
      const passes = checkWCAGCompliance(ratio);

      if (passes.AA_normal) {
        passAA++;
      }

      if (passes.AAA_normal) {
        passAAA++;
      }

      if (!passes.AA_normal) {
        fail++;

        const severity = ratio < 3.0 ? 'critical' : 'warning';
        const violation: ContrastViolation = {
          ratio,
          wcagLevel,
          passes,
          foreground: pair.foreground,
          background: pair.background,
          severity,
          message: `Contrast ratio ${ratio.toFixed(2)}:1 fails WCAG ${this.options.targetLevel} (requires ${this.options.minContrastNormal}:1 for normal text)`,
          recommendation: this.getRecommendation(pair, ratio),
          affectedTokens: {
            foreground: pair.foregroundToken,
            background: pair.backgroundToken,
          },
        };

        violations.push(violation);
      }
    }

    // Generate additional tokens if enabled
    const generatedTokens = {
      focusStates: 0,
      touchTargets: 0,
      highContrastAlternatives: 0,
    };

    if (this.options.generateFocusStates) {
      generatedTokens.focusStates = this.generateFocusStates(tokens).length;
    }

    if (this.options.generateTouchTargets) {
      generatedTokens.touchTargets = this.generateTouchTargets().length;
    }

    if (this.options.generateHighContrastAlternatives) {
      generatedTokens.highContrastAlternatives = this.generateHighContrastAlternatives(
        tokens,
        violations
      ).length;
    }

    // Add warnings for common issues
    if (violations.length > colorPairs.length * 0.5) {
      warnings.push(
        'Over 50% of color pairs fail WCAG standards. Consider reviewing your color palette.'
      );
    }

    const totalChecks = colorPairs.length;
    const percentCompliant = totalChecks > 0 ? (passAA / totalChecks) * 100 : 0;

    return {
      timestamp,
      totalColorPairs: colorPairs.length,
      violations,
      warnings,
      generatedTokens,
      summary: {
        passAA,
        passAAA,
        fail,
        percentCompliant,
      },
      recommendations: this.generateRecommendations(violations, warnings),
    };
  }

  /**
   * Generate all possible foreground/background color pairs from tokens
   */
  public generateColorPairs(tokens: Token[]): ColorPair[] {
    const colorTokens = tokens.filter(t => t.type === 'color' && typeof t.value === 'string');

    // Identify likely backgrounds and foregrounds
    const backgrounds = colorTokens.filter(t =>
      this.isLikelyBackground(t.name, t.path)
    );

    const foregrounds = colorTokens.filter(t =>
      this.isLikelyForeground(t.name, t.path)
    );

    const pairs: ColorPair[] = [];

    // Generate pairs based on naming conventions
    for (const fg of foregrounds) {
      for (const bg of backgrounds) {
        pairs.push({
          foreground: fg.value as string,
          background: bg.value as string,
          foregroundToken: fg.name,
          backgroundToken: bg.name,
          context: `${fg.name}-on-${bg.name}`,
        });
      }
    }

    // If no clear foreground/background split, test all combinations
    if (pairs.length === 0 && colorTokens.length > 0) {
      for (let i = 0; i < colorTokens.length; i++) {
        for (let j = i + 1; j < colorTokens.length; j++) {
          pairs.push({
            foreground: colorTokens[i].value as string,
            background: colorTokens[j].value as string,
            foregroundToken: colorTokens[i].name,
            backgroundToken: colorTokens[j].name,
          });
        }
      }
    }

    return pairs;
  }

  /**
   * Generate focus state tokens
   */
  public generateFocusStates(tokens: Token[]): Token[] {
    const focusTokens: Token[] = [];
    const colorTokens = tokens.filter(t => t.type === 'color');

    // Standard focus state configs
    const focusConfigs: FocusStateConfig[] = [
      {
        baseColor: '#0066CC',
        colorToken: 'focus-primary',
        outlineWidth: '2px',
        outlineOffset: '2px',
        outlineStyle: 'solid',
      },
      {
        baseColor: '#005299',
        colorToken: 'focus-primary-dark',
        outlineWidth: '2px',
        outlineOffset: '2px',
        outlineStyle: 'solid',
      },
    ];

    // Find primary color if available
    const primaryColor = colorTokens.find(t =>
      t.name.toLowerCase().includes('primary') && !t.name.includes('background')
    );

    if (primaryColor) {
      focusConfigs[0].baseColor = primaryColor.value as string;
    }

    // Generate focus state tokens
    for (const config of focusConfigs) {
      focusTokens.push({
        name: `focus-outline-color-${config.colorToken}`,
        value: config.baseColor,
        type: 'color',
        category: 'accessibility',
        source: 'accessibility-audit' as any,
        priority: 100,
        path: ['accessibility', 'focus', config.colorToken || 'default'],
        description: 'Accessible focus outline color (WCAG compliant)',
        metadata: {
          generatedBy: 'accessibility-audit',
          wcagCompliant: true,
        },
      });

      focusTokens.push({
        name: `focus-outline-width`,
        value: config.outlineWidth,
        type: 'dimension',
        category: 'accessibility',
        source: 'accessibility-audit' as any,
        priority: 100,
        path: ['accessibility', 'focus', 'outline-width'],
        description: 'Focus outline width (minimum 2px for visibility)',
      });

      focusTokens.push({
        name: `focus-outline-offset`,
        value: config.outlineOffset,
        type: 'dimension',
        category: 'accessibility',
        source: 'accessibility-audit' as any,
        priority: 100,
        path: ['accessibility', 'focus', 'outline-offset'],
        description: 'Focus outline offset (visual separation)',
      });
    }

    return focusTokens;
  }

  /**
   * Generate touch target tokens
   */
  public generateTouchTargets(): Token[] {
    const touchTargets: Token[] = [];

    const configs: TouchTargetConfig[] = [
      {
        name: 'touch-target-minimum',
        minWidth: '44px',
        minHeight: '44px',
        padding: '12px',
      },
      {
        name: 'touch-target-comfortable',
        minWidth: '48px',
        minHeight: '48px',
        padding: '16px',
      },
    ];

    for (const config of configs) {
      touchTargets.push({
        name: `${config.name}-width`,
        value: config.minWidth,
        type: 'dimension',
        category: 'accessibility',
        source: 'accessibility-audit' as any,
        priority: 100,
        path: ['accessibility', 'touch-target', config.name, 'width'],
        description: 'Minimum touch target width (WCAG 2.5.5)',
      });

      touchTargets.push({
        name: `${config.name}-height`,
        value: config.minHeight,
        type: 'dimension',
        category: 'accessibility',
        source: 'accessibility-audit' as any,
        priority: 100,
        path: ['accessibility', 'touch-target', config.name, 'height'],
        description: 'Minimum touch target height (WCAG 2.5.5)',
      });

      touchTargets.push({
        name: `${config.name}-padding`,
        value: config.padding,
        type: 'dimension',
        category: 'accessibility',
        source: 'accessibility-audit' as any,
        priority: 100,
        path: ['accessibility', 'touch-target', config.name, 'padding'],
        description: 'Touch target padding for comfortable interaction',
      });
    }

    return touchTargets;
  }

  /**
   * Generate high-contrast color alternatives
   */
  private generateHighContrastAlternatives(
    tokens: Token[],
    violations: ContrastViolation[]
  ): Token[] {
    const alternatives: Token[] = [];

    for (const violation of violations) {
      if (!violation.affectedTokens.foreground || !violation.affectedTokens.background) {
        continue;
      }

      const targetRatio = this.options.targetLevel === 'AAA' ? 7.0 : 4.5;
      const adjustedColor = adjustColorForContrast(
        violation.foreground,
        violation.background,
        targetRatio
      );

      alternatives.push({
        name: `${violation.affectedTokens.foreground}-high-contrast`,
        value: adjustedColor,
        type: 'color',
        category: 'accessibility',
        source: 'accessibility-audit' as any,
        priority: 100,
        path: ['accessibility', 'high-contrast', violation.affectedTokens.foreground],
        description: `High-contrast alternative to ${violation.affectedTokens.foreground} (${targetRatio}:1 on ${violation.affectedTokens.background})`,
        metadata: {
          originalColor: violation.foreground,
          contrastRatio: calculateContrastRatio(adjustedColor, violation.background),
          wcagLevel: this.options.targetLevel,
        },
      });
    }

    return alternatives;
  }

  /**
   * Check if token is likely a background color
   */
  private isLikelyBackground(name: string, path: string[]): boolean {
    const lower = name.toLowerCase();
    const pathStr = path.join('.').toLowerCase();

    return (
      lower.includes('background') ||
      lower.includes('bg') ||
      lower.includes('surface') ||
      pathStr.includes('background') ||
      pathStr.includes('bg') ||
      pathStr.includes('surface')
    );
  }

  /**
   * Check if token is likely a foreground color
   */
  private isLikelyForeground(name: string, path: string[]): boolean {
    const lower = name.toLowerCase();
    const pathStr = path.join('.').toLowerCase();

    return (
      lower.includes('text') ||
      lower.includes('foreground') ||
      lower.includes('fg') ||
      lower.includes('color') ||
      pathStr.includes('text') ||
      pathStr.includes('foreground')
    );
  }

  /**
   * Get recommendation for improving contrast
   */
  private getRecommendation(pair: ColorPair, currentRatio: number): string {
    const targetRatio = this.options.minContrastNormal;
    const deficit = targetRatio - currentRatio;

    if (deficit > 2) {
      return `Consider significantly adjusting ${pair.foregroundToken} or ${pair.backgroundToken}. Current ratio is ${currentRatio.toFixed(2)}:1, need ${targetRatio}:1 minimum.`;
    } else {
      return `Slightly adjust ${pair.foregroundToken} lightness to meet ${targetRatio}:1 requirement.`;
    }
  }

  /**
   * Generate overall recommendations
   */
  private generateRecommendations(
    violations: ContrastViolation[],
    warnings: string[]
  ): string[] {
    const recommendations: string[] = [];

    if (violations.length === 0) {
      recommendations.push('All color pairs meet WCAG ' + this.options.targetLevel + ' standards!');
    } else {
      recommendations.push(
        `Fix ${violations.length} contrast violation(s) to meet WCAG ${this.options.targetLevel} standards.`
      );

      const criticalCount = violations.filter(v => v.severity === 'critical').length;
      if (criticalCount > 0) {
        recommendations.push(
          `${criticalCount} critical violation(s) with contrast ratio below 3:1 - these should be addressed immediately.`
        );
      }
    }

    if (this.options.generateFocusStates) {
      recommendations.push(
        'Focus state tokens have been generated. Apply these to interactive elements.'
      );
    }

    if (this.options.generateTouchTargets) {
      recommendations.push(
        'Touch target tokens follow WCAG 2.5.5 (minimum 44x44px). Use for buttons and interactive elements.'
      );
    }

    return recommendations;
  }
}

/**
 * Convenience function to run accessibility audit
 */
export function auditTokensForAccessibility(
  tokens: Token[],
  options?: AccessibilityAuditOptions
): AccessibilityReport {
  const auditor = new AccessibilityAuditor(options);
  return auditor.auditTokens(tokens);
}
