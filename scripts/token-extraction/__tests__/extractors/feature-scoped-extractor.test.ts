/**
 * Feature Scoped Extractor Tests
 * Verify token and error filtering by feature scope
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { FeatureScopedExtractor } from '../../extractors/feature-scoped-extractor';
import { Token, TokenSource, FeatureScope, ExtractionError } from '../../types';

describe('FeatureScopedExtractor', () => {
  const mockScope: FeatureScope = {
    name: 'authentication',
    includePaths: ['src/auth/**/*', 'src/features/auth/**/*'],
    excludePaths: ['src/auth/tests/**/*'],
    keywords: ['auth', 'login', 'session'],
  };

  let extractor: FeatureScopedExtractor;

  // Helper to create test tokens
  const createToken = (name: string, filePath?: string, path?: string[]): Token => ({
    name,
    value: '#000000',
    type: 'color',
    source: TokenSource.TAILWIND_CONFIG,
    priority: 80,
    path: path || ['colors', name],
    metadata: filePath ? { filePath } : undefined,
  });

  beforeEach(() => {
    extractor = new FeatureScopedExtractor(mockScope);
  });

  describe('filterTokens', () => {
    it('should filter tokens by file path', () => {
      const tokens = [
        createToken('primary', 'src/auth/theme.ts'),
        createToken('secondary', 'src/payment/theme.ts'),
        createToken('accent', 'src/auth/colors.ts'),
      ];

      const filtered = extractor.filterTokens(tokens);

      expect(filtered.length).toBe(2);
      expect(filtered.every(t => t.feature === 'authentication')).toBe(true);
      expect(filtered.map(t => t.name)).toContain('primary');
      expect(filtered.map(t => t.name)).toContain('accent');
      expect(filtered.map(t => t.name)).not.toContain('secondary');
    });

    it('should respect exclude paths', () => {
      const tokens = [
        createToken('primary', 'src/auth/theme.ts'),
        createToken('test-color', 'src/auth/tests/fixtures.ts'),
        createToken('accent', 'src/auth/colors.ts'),
      ];

      const filtered = extractor.filterTokens(tokens);

      expect(filtered.length).toBe(2);
      expect(filtered.map(t => t.name)).not.toContain('test-color');
    });

    it('should filter by keywords when file path not available', () => {
      const tokens = [
        createToken('auth-primary', undefined, ['auth', 'colors', 'primary']),
        createToken('payment-primary', undefined, ['payment', 'colors', 'primary']),
        createToken('login-bg', undefined, ['login', 'background']),
      ];

      const filtered = extractor.filterTokens(tokens);

      // Should match by keywords in path
      expect(filtered.length).toBeGreaterThan(0);
      expect(filtered.map(t => t.name)).toContain('auth-primary');
      expect(filtered.map(t => t.name)).toContain('login-bg');
    });

    it('should filter by keywords in token name', () => {
      const tokens = [
        createToken('auth-primary'),
        createToken('payment-primary'),
        createToken('session-timeout'),
      ];

      const filtered = extractor.filterTokens(tokens);

      // Should match 'auth' and 'session' keywords
      expect(filtered.length).toBeGreaterThanOrEqual(2);
      expect(filtered.some(t => t.name === 'auth-primary')).toBe(true);
      expect(filtered.some(t => t.name === 'session-timeout')).toBe(true);
    });

    it('should tag filtered tokens with feature name', () => {
      const tokens = [
        createToken('primary', 'src/auth/theme.ts'),
        createToken('secondary', 'src/auth/colors.ts'),
      ];

      const filtered = extractor.filterTokens(tokens);

      expect(filtered.every(t => t.feature === 'authentication')).toBe(true);
    });

    it('should exclude tokens already assigned to different feature', () => {
      const tokens = [
        { ...createToken('primary', 'src/auth/theme.ts'), feature: 'other-feature' },
        createToken('secondary', 'src/auth/colors.ts'),
      ];

      const filtered = extractor.filterTokens(tokens);

      expect(filtered.length).toBe(1);
      expect(filtered[0].name).toBe('secondary');
    });

    it('should handle tokens with source metadata', () => {
      const tokens = [
        {
          ...createToken('primary'),
          metadata: { source: 'src/auth/theme.ts' },
        },
        {
          ...createToken('secondary'),
          metadata: { source: 'src/payment/theme.ts' },
        },
      ];

      const filtered = extractor.filterTokens(tokens);

      expect(filtered.length).toBe(1);
      expect(filtered[0].name).toBe('primary');
    });

    it('should log filtering summary', () => {
      const tokens = [
        createToken('primary', 'src/auth/theme.ts'),
        createToken('secondary', 'src/payment/theme.ts'),
        createToken('accent', 'src/auth/colors.ts'),
      ];

      const consoleSpy = vi.spyOn(console, 'log');

      extractor.filterTokens(tokens);

      expect(consoleSpy).toHaveBeenCalledWith(
        expect.stringContaining('Filtered tokens for feature "authentication": 2/3')
      );

      consoleSpy.mockRestore();
    });
  });

  describe('filterErrors', () => {
    it('should filter errors by file path', () => {
      const errors: ExtractionError[] = [
        {
          source: TokenSource.TAILWIND_CONFIG,
          message: 'Parse error',
          filePath: 'src/auth/config.ts',
        },
        {
          source: TokenSource.CSS_VARIABLES,
          message: 'Invalid syntax',
          filePath: 'src/payment/styles.css',
        },
        {
          source: TokenSource.THEME_FILE,
          message: 'Missing theme',
          filePath: 'src/auth/theme.ts',
        },
      ];

      const filtered = extractor.filterErrors(errors);

      expect(filtered.length).toBe(2);
      expect(filtered.every(e => e.filePath?.includes('auth'))).toBe(true);
    });

    it('should keep errors without file paths', () => {
      const errors: ExtractionError[] = [
        {
          source: TokenSource.TAILWIND_CONFIG,
          message: 'Global error',
        },
        {
          source: TokenSource.CSS_VARIABLES,
          message: 'Another error',
          filePath: 'src/payment/styles.css',
        },
      ];

      const filtered = extractor.filterErrors(errors);

      // Should include global error (no filePath)
      expect(filtered.some(e => !e.filePath)).toBe(true);
      expect(filtered.some(e => e.message === 'Global error')).toBe(true);
    });
  });

  describe('isFileInScope', () => {
    it('should match include paths with glob patterns', () => {
      expect(extractor.isFileInScope('src/auth/login.ts')).toBe(true);
      expect(extractor.isFileInScope('src/auth/utils/helper.ts')).toBe(true);
      expect(extractor.isFileInScope('src/features/auth/session.ts')).toBe(true);
    });

    it('should exclude paths matching exclude patterns', () => {
      expect(extractor.isFileInScope('src/auth/tests/login.test.ts')).toBe(false);
      expect(extractor.isFileInScope('src/auth/tests/utils/helper.test.ts')).toBe(false);
    });

    it('should match by keywords as fallback', () => {
      // File not matching include paths but contains keyword
      const result = extractor.isFileInScope('src/components/login-form.tsx');

      expect(result).toBe(true);
    });

    it('should normalize paths before matching', () => {
      expect(extractor.isFileInScope('src/auth/../auth/login.ts')).toBe(true);
      expect(extractor.isFileInScope('src/auth/./login.ts')).toBe(true);
    });

    it('should handle Windows paths', () => {
      expect(extractor.isFileInScope('src\\auth\\login.ts')).toBe(true);
    });
  });

  describe('getScope', () => {
    it('should return the current scope', () => {
      const scope = extractor.getScope();

      expect(scope).toBe(mockScope);
      expect(scope.name).toBe('authentication');
    });
  });

  describe('edge cases', () => {
    it('should handle empty token list', () => {
      const filtered = extractor.filterTokens([]);

      expect(filtered).toEqual([]);
    });

    it('should handle scope without exclude paths', () => {
      const scopeWithoutExclude: FeatureScope = {
        name: 'test',
        includePaths: ['src/**/*'],
      };

      const extractorNoExclude = new FeatureScopedExtractor(scopeWithoutExclude);
      const tokens = [createToken('primary', 'src/theme.ts')];

      const filtered = extractorNoExclude.filterTokens(tokens);

      expect(filtered.length).toBe(1);
    });

    it('should handle scope without keywords', () => {
      const scopeWithoutKeywords: FeatureScope = {
        name: 'test',
        includePaths: ['src/test/**/*'],
      };

      const extractorNoKeywords = new FeatureScopedExtractor(scopeWithoutKeywords);
      const tokens = [
        createToken('primary', 'src/test/theme.ts'),
        createToken('secondary'), // No file path, no keywords
      ];

      const filtered = extractorNoKeywords.filterTokens(tokens);

      // Should only match the one with file path
      expect(filtered.length).toBe(1);
      expect(filtered[0].name).toBe('primary');
    });

    it('should be case-insensitive for keywords', () => {
      const tokens = [
        createToken('AUTH-PRIMARY', undefined, ['AUTH', 'colors']),
        createToken('login-BG', undefined, ['LOGIN', 'background']),
      ];

      const filtered = extractor.filterTokens(tokens);

      expect(filtered.length).toBe(2);
    });
  });

  describe('complex scenarios', () => {
    it('should handle mixed token sources', () => {
      const tokens = [
        createToken('primary', 'src/auth/tailwind.config.ts'),
        {
          ...createToken('secondary'),
          metadata: { source: 'src/auth/theme.js' },
        },
        {
          ...createToken('accent'),
          metadata: { filePath: 'src/auth/styles.css' },
        },
      ];

      const filtered = extractor.filterTokens(tokens);

      expect(filtered.length).toBe(3);
    });

    it('should handle overlapping include/exclude patterns', () => {
      const complexScope: FeatureScope = {
        name: 'complex',
        includePaths: ['src/**/*'],
        excludePaths: ['src/tests/**/*', 'src/*/tests/**/*'],
      };

      const complexExtractor = new FeatureScopedExtractor(complexScope);

      expect(complexExtractor.isFileInScope('src/auth/login.ts')).toBe(true);
      expect(complexExtractor.isFileInScope('src/tests/auth.test.ts')).toBe(false);
      expect(complexExtractor.isFileInScope('src/auth/tests/login.test.ts')).toBe(false);
    });
  });
});
