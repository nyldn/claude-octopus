/**
 * Accessibility Audit Tests
 * Verify the accessibility auditor generates correct reports
 */

import { describe, it, expect } from 'vitest';
import { AccessibilityAuditor } from '../../accessibility/accessibility-audit';
import { Token, TokenSource } from '../../types';

describe('AccessibilityAuditor', () => {
  const createMockTokens = (): Token[] => [
    {
      name: 'text-primary',
      value: '#000000',
      type: 'color',
      category: 'colors',
      source: TokenSource.THEME_FILE,
      priority: 100,
      path: ['colors', 'text', 'primary'],
    },
    {
      name: 'background-primary',
      value: '#ffffff',
      type: 'color',
      category: 'colors',
      source: TokenSource.THEME_FILE,
      priority: 100,
      path: ['colors', 'background', 'primary'],
    },
    {
      name: 'text-secondary',
      value: '#cccccc',
      type: 'color',
      category: 'colors',
      source: TokenSource.THEME_FILE,
      priority: 100,
      path: ['colors', 'text', 'secondary'],
    },
  ];

  describe('auditTokens', () => {
    it('should generate accessibility report', () => {
      const auditor = new AccessibilityAuditor();
      const tokens = createMockTokens();
      const report = auditor.auditTokens(tokens);

      expect(report).toBeDefined();
      expect(report.timestamp).toBeDefined();
      expect(report.totalColorPairs).toBeGreaterThan(0);
      expect(report.summary).toBeDefined();
      expect(report.violations).toBeDefined();
    });

    it('should detect WCAG AA compliance', () => {
      const auditor = new AccessibilityAuditor({ targetLevel: 'AA' });
      const tokens = createMockTokens();
      const report = auditor.auditTokens(tokens);

      // Black on white should pass AA
      expect(report.summary.passAA).toBeGreaterThan(0);
    });

    it('should identify violations', () => {
      const auditor = new AccessibilityAuditor();
      const tokens: Token[] = [
        {
          name: 'text-low-contrast',
          value: '#dddddd',
          type: 'color',
          category: 'colors',
          source: TokenSource.THEME_FILE,
          priority: 100,
          path: ['colors', 'text', 'low-contrast'],
        },
        {
          name: 'background-light',
          value: '#ffffff',
          type: 'color',
          category: 'colors',
          source: TokenSource.THEME_FILE,
          priority: 100,
          path: ['colors', 'background', 'light'],
        },
      ];

      const report = auditor.auditTokens(tokens);

      // Light gray on white should have violations
      expect(report.violations.length).toBeGreaterThan(0);
    });

    it('should provide recommendations', () => {
      const auditor = new AccessibilityAuditor();
      const tokens = createMockTokens();
      const report = auditor.auditTokens(tokens);

      expect(report.recommendations).toBeDefined();
      expect(report.recommendations.length).toBeGreaterThan(0);
    });
  });

  describe('generateFocusStates', () => {
    it('should generate focus state tokens', () => {
      const auditor = new AccessibilityAuditor({ generateFocusStates: true });
      const tokens = createMockTokens();
      const focusTokens = auditor.generateFocusStates(tokens);

      expect(focusTokens.length).toBeGreaterThan(0);
      expect(focusTokens.some(t => t.name.includes('focus'))).toBe(true);
    });

    it('should include outline width and offset', () => {
      const auditor = new AccessibilityAuditor({ generateFocusStates: true });
      const tokens = createMockTokens();
      const focusTokens = auditor.generateFocusStates(tokens);

      const hasOutlineWidth = focusTokens.some(t => t.name.includes('outline-width'));
      const hasOutlineOffset = focusTokens.some(t => t.name.includes('outline-offset'));

      expect(hasOutlineWidth).toBe(true);
      expect(hasOutlineOffset).toBe(true);
    });
  });

  describe('generateTouchTargets', () => {
    it('should generate touch target tokens', () => {
      const auditor = new AccessibilityAuditor({ generateTouchTargets: true });
      const touchTargets = auditor.generateTouchTargets();

      expect(touchTargets.length).toBeGreaterThan(0);
      expect(touchTargets.some(t => t.name.includes('touch-target'))).toBe(true);
    });

    it('should have minimum 44px dimensions', () => {
      const auditor = new AccessibilityAuditor({ generateTouchTargets: true });
      const touchTargets = auditor.generateTouchTargets();

      const widthToken = touchTargets.find(t => t.name.includes('width'));
      expect(widthToken).toBeDefined();
      expect(widthToken?.value).toContain('44px');
    });
  });

  describe('generateColorPairs', () => {
    it('should generate color pairs from tokens', () => {
      const auditor = new AccessibilityAuditor();
      const tokens = createMockTokens();
      const pairs = auditor.generateColorPairs(tokens);

      expect(pairs.length).toBeGreaterThan(0);
      expect(pairs[0].foreground).toBeDefined();
      expect(pairs[0].background).toBeDefined();
    });

    it('should match foreground and background tokens', () => {
      const auditor = new AccessibilityAuditor();
      const tokens = createMockTokens();
      const pairs = auditor.generateColorPairs(tokens);

      const hasTextOnBackground = pairs.some(
        p => p.foregroundToken?.includes('text') && p.backgroundToken?.includes('background')
      );

      expect(hasTextOnBackground).toBe(true);
    });
  });
});
