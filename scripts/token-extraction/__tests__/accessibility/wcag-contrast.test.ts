/**
 * WCAG Contrast Tests
 * Verify contrast ratio calculations meet WCAG standards
 */

import { describe, it, expect } from 'vitest';
import {
  calculateContrastRatio,
  calculateRelativeLuminance,
  getWCAGLevel,
  checkWCAGCompliance,
  adjustColorForContrast,
} from '../../accessibility/wcag-contrast';

describe('WCAG Contrast Calculations', () => {
  describe('calculateRelativeLuminance', () => {
    it('should calculate correct luminance for black', () => {
      const luminance = calculateRelativeLuminance('#000000');
      expect(luminance).toBe(0);
    });

    it('should calculate correct luminance for white', () => {
      const luminance = calculateRelativeLuminance('#ffffff');
      expect(luminance).toBe(1);
    });

    it('should handle RGB colors', () => {
      const luminance = calculateRelativeLuminance('rgb(255, 0, 0)');
      expect(luminance).toBeGreaterThan(0);
      expect(luminance).toBeLessThan(1);
    });
  });

  describe('calculateContrastRatio', () => {
    it('should return 21:1 for black on white', () => {
      const ratio = calculateContrastRatio('#000000', '#ffffff');
      expect(ratio).toBeCloseTo(21, 1);
    });

    it('should return 21:1 for white on black', () => {
      const ratio = calculateContrastRatio('#ffffff', '#000000');
      expect(ratio).toBeCloseTo(21, 1);
    });

    it('should return 1:1 for identical colors', () => {
      const ratio = calculateContrastRatio('#ff0000', '#ff0000');
      expect(ratio).toBeCloseTo(1, 1);
    });

    it('should calculate correct ratio for blue on white', () => {
      const ratio = calculateContrastRatio('#0000ff', '#ffffff');
      expect(ratio).toBeGreaterThan(8);
      expect(ratio).toBeLessThan(9);
    });

    it('should handle short hex colors', () => {
      const ratio = calculateContrastRatio('#000', '#fff');
      expect(ratio).toBeCloseTo(21, 1);
    });
  });

  describe('getWCAGLevel', () => {
    it('should return AAA for 7:1+ on normal text', () => {
      const level = getWCAGLevel(7.5, false);
      expect(level).toBe('AAA');
    });

    it('should return AA for 4.5:1+ on normal text', () => {
      const level = getWCAGLevel(4.6, false);
      expect(level).toBe('AA');
    });

    it('should return A for 3:1+ on normal text', () => {
      const level = getWCAGLevel(3.2, false);
      expect(level).toBe('A');
    });

    it('should return Fail for less than 3:1 on normal text', () => {
      const level = getWCAGLevel(2.5, false);
      expect(level).toBe('Fail');
    });

    it('should return AAA for 4.5:1+ on large text', () => {
      const level = getWCAGLevel(4.6, true);
      expect(level).toBe('AAA');
    });

    it('should return AA for 3:1+ on large text', () => {
      const level = getWCAGLevel(3.2, true);
      expect(level).toBe('AA');
    });

    it('should return Fail for less than 3:1 on large text', () => {
      const level = getWCAGLevel(2.8, true);
      expect(level).toBe('Fail');
    });
  });

  describe('checkWCAGCompliance', () => {
    it('should pass all levels for 21:1 ratio', () => {
      const compliance = checkWCAGCompliance(21);
      expect(compliance.AA_normal).toBe(true);
      expect(compliance.AA_large).toBe(true);
      expect(compliance.AAA_normal).toBe(true);
      expect(compliance.AAA_large).toBe(true);
    });

    it('should pass AA but not AAA for 5:1 ratio', () => {
      const compliance = checkWCAGCompliance(5);
      expect(compliance.AA_normal).toBe(true);
      expect(compliance.AA_large).toBe(true);
      expect(compliance.AAA_normal).toBe(false);
      expect(compliance.AAA_large).toBe(true);
    });

    it('should fail all for 2:1 ratio', () => {
      const compliance = checkWCAGCompliance(2);
      expect(compliance.AA_normal).toBe(false);
      expect(compliance.AA_large).toBe(false);
      expect(compliance.AAA_normal).toBe(false);
      expect(compliance.AAA_large).toBe(false);
    });
  });

  describe('adjustColorForContrast', () => {
    it('should adjust color to meet target ratio', () => {
      const adjusted = adjustColorForContrast('#666666', '#ffffff', 4.5);
      const ratio = calculateContrastRatio(adjusted, '#ffffff');
      expect(ratio).toBeGreaterThanOrEqual(4.3); // Allow small margin
    });

    it('should adjust dark color on light background', () => {
      const adjusted = adjustColorForContrast('#333333', '#f0f0f0', 7.0);
      const ratio = calculateContrastRatio(adjusted, '#f0f0f0');
      expect(ratio).toBeGreaterThanOrEqual(6.8);
    });

    it('should adjust light color on dark background', () => {
      const adjusted = adjustColorForContrast('#cccccc', '#222222', 7.0);
      const ratio = calculateContrastRatio(adjusted, '#222222');
      expect(ratio).toBeGreaterThanOrEqual(6.8);
    });
  });
});
