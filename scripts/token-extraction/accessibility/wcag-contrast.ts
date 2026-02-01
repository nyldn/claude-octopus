/**
 * WCAG 2.1 Contrast Ratio Calculations
 * @see https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html
 */

import tinycolor from 'tinycolor2';
import { WCAGLevel, ContrastResult } from './types';

/**
 * Convert sRGB color component to linear RGB
 * @param component - RGB component value (0-255)
 */
function sRGBtoLinear(component: number): number {
  const normalized = component / 255;

  if (normalized <= 0.03928) {
    return normalized / 12.92;
  }

  return Math.pow((normalized + 0.055) / 1.055, 2.4);
}

/**
 * Calculate relative luminance of a color
 * @param color - Color string (hex, rgb, named, etc.)
 * @returns Relative luminance (0-1)
 */
export function calculateRelativeLuminance(color: string): number {
  const rgb = tinycolor(color).toRgb();

  const R = sRGBtoLinear(rgb.r);
  const G = sRGBtoLinear(rgb.g);
  const B = sRGBtoLinear(rgb.b);

  // WCAG formula: L = 0.2126 * R + 0.7152 * G + 0.0722 * B
  return 0.2126 * R + 0.7152 * G + 0.0722 * B;
}

/**
 * Calculate contrast ratio between two colors
 * @param foreground - Foreground color string
 * @param background - Background color string
 * @returns Contrast ratio (1-21)
 */
export function calculateContrastRatio(foreground: string, background: string): number {
  const l1 = calculateRelativeLuminance(foreground);
  const l2 = calculateRelativeLuminance(background);

  const lighter = Math.max(l1, l2);
  const darker = Math.min(l1, l2);

  // WCAG formula: (L1 + 0.05) / (L2 + 0.05)
  return (lighter + 0.05) / (darker + 0.05);
}

/**
 * Determine WCAG level based on contrast ratio and text size
 * @param ratio - Contrast ratio
 * @param isLargeText - Whether text is large (18pt+ or 14pt+ bold)
 * @returns WCAG level
 */
export function getWCAGLevel(ratio: number, isLargeText: boolean = false): WCAGLevel {
  if (isLargeText) {
    if (ratio >= 4.5) return 'AAA';
    if (ratio >= 3.0) return 'AA';
    return 'Fail';
  } else {
    if (ratio >= 7.0) return 'AAA';
    if (ratio >= 4.5) return 'AA';
    if (ratio >= 3.0) return 'A';
    return 'Fail';
  }
}

/**
 * Check if contrast ratio passes specific WCAG criteria
 * @param ratio - Contrast ratio
 * @returns Object with pass/fail for different criteria
 */
export function checkWCAGCompliance(ratio: number): ContrastResult['passes'] {
  return {
    AA_normal: ratio >= 4.5,
    AA_large: ratio >= 3.0,
    AAA_normal: ratio >= 7.0,
    AAA_large: ratio >= 4.5,
  };
}

/**
 * Get contrast result for a foreground/background pair
 * @param foreground - Foreground color
 * @param background - Background color
 * @param isLargeText - Whether text is large
 * @returns Complete contrast analysis
 */
export function getContrastResult(
  foreground: string,
  background: string,
  isLargeText: boolean = false
): ContrastResult {
  const ratio = calculateContrastRatio(foreground, background);
  const passes = checkWCAGCompliance(ratio);
  const wcagLevel = getWCAGLevel(ratio, isLargeText);

  return {
    ratio,
    wcagLevel,
    passes,
    foreground,
    background,
  };
}

/**
 * Find a color that meets contrast requirements
 * @param baseColor - Starting color
 * @param backgroundColor - Background to contrast against
 * @param targetRatio - Target contrast ratio (default: 4.5 for AA normal text)
 * @returns Adjusted color that meets target ratio
 */
export function adjustColorForContrast(
  baseColor: string,
  backgroundColor: string,
  targetRatio: number = 4.5
): string {
  const bgLuminance = calculateRelativeLuminance(backgroundColor);
  let color = tinycolor(baseColor);

  let currentRatio = calculateContrastRatio(color.toHexString(), backgroundColor);

  // Determine if we should lighten or darken
  const shouldLighten = bgLuminance < 0.5;

  // Binary search for the right luminance
  let attempts = 0;
  const maxAttempts = 50;

  while (Math.abs(currentRatio - targetRatio) > 0.1 && attempts < maxAttempts) {
    if (currentRatio < targetRatio) {
      // Need more contrast
      if (shouldLighten) {
        color = color.lighten(2);
      } else {
        color = color.darken(2);
      }
    } else {
      // Too much contrast, back off slightly
      if (shouldLighten) {
        color = color.darken(1);
      } else {
        color = color.lighten(1);
      }
    }

    currentRatio = calculateContrastRatio(color.toHexString(), backgroundColor);
    attempts++;
  }

  return color.toHexString();
}

/**
 * Generate a high-contrast version of a color
 * @param color - Original color
 * @param targetLevel - Target WCAG level ('AA' or 'AAA')
 * @returns High-contrast color string
 */
export function generateHighContrastColor(
  color: string,
  backgroundColor: string,
  targetLevel: 'AA' | 'AAA' = 'AA'
): string {
  const targetRatio = targetLevel === 'AAA' ? 7.0 : 4.5;
  return adjustColorForContrast(color, backgroundColor, targetRatio);
}
