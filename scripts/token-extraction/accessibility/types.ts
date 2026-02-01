/**
 * Accessibility audit types and interfaces
 */

export type WCAGLevel = 'AAA' | 'AA' | 'A' | 'Fail';

export interface ColorPair {
  foreground: string;
  background: string;
  foregroundToken?: string;
  backgroundToken?: string;
  context?: string; // e.g., "button-text", "heading-on-background"
}

export interface ContrastResult {
  ratio: number;
  wcagLevel: WCAGLevel;
  passes: {
    AA_normal: boolean;      // 4.5:1 for normal text
    AA_large: boolean;       // 3:1 for large text (18pt+ or 14pt+ bold)
    AAA_normal: boolean;     // 7:1 for normal text
    AAA_large: boolean;      // 4.5:1 for large text
  };
  foreground: string;
  background: string;
}

export interface ContrastViolation extends ContrastResult {
  severity: 'critical' | 'warning' | 'info';
  message: string;
  recommendation?: string;
  affectedTokens: {
    foreground?: string;
    background?: string;
  };
}

export interface AccessibilityReport {
  timestamp: string;
  totalColorPairs: number;
  violations: ContrastViolation[];
  warnings: string[];
  generatedTokens: {
    focusStates: number;
    touchTargets: number;
    highContrastAlternatives: number;
  };
  summary: {
    passAA: number;
    passAAA: number;
    fail: number;
    percentCompliant: number;
  };
  recommendations: string[];
}

export interface FocusStateConfig {
  baseColor: string;
  colorToken?: string;
  outlineWidth: string;
  outlineOffset: string;
  outlineStyle: 'solid' | 'dashed' | 'dotted';
}

export interface TouchTargetConfig {
  minWidth: string;
  minHeight: string;
  padding: string;
  name: string;
}

export interface AccessibilityAuditOptions {
  /**
   * Minimum contrast ratio for normal text (AA standard: 4.5:1)
   */
  minContrastNormal?: number;

  /**
   * Minimum contrast ratio for large text (AA standard: 3:1)
   */
  minContrastLarge?: number;

  /**
   * Generate focus states automatically
   */
  generateFocusStates?: boolean;

  /**
   * Generate touch target tokens
   */
  generateTouchTargets?: boolean;

  /**
   * Generate high-contrast color alternatives
   */
  generateHighContrastAlternatives?: boolean;

  /**
   * Target WCAG level ('AA' or 'AAA')
   */
  targetLevel?: 'AA' | 'AAA';
}

export const DEFAULT_ACCESSIBILITY_OPTIONS: Required<AccessibilityAuditOptions> = {
  minContrastNormal: 4.5,
  minContrastLarge: 3.0,
  generateFocusStates: true,
  generateTouchTargets: true,
  generateHighContrastAlternatives: false,
  targetLevel: 'AA',
};
