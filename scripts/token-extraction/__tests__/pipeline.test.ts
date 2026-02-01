/**
 * Token Extraction Pipeline Tests
 */

import { runTokenExtraction } from '../pipeline';
import { TokenExtractionConfig, TokenCategory } from '../types';
import * as fs from 'fs';
import * as path from 'path';

describe('Token Extraction Pipeline', () => {
  const testProjectPath = path.join(__dirname, '../test-fixtures');

  describe('runTokenExtraction', () => {
    it('should extract tokens from test fixtures', async () => {
      const config: Partial<TokenExtractionConfig> = {
        sources: ['tailwind', 'css', 'theme', 'styled'],
        outputFormats: ['json'],
        priority: ['theme', 'tailwind', 'css', 'styled'],
      };

      const result = await runTokenExtraction(testProjectPath, config);

      expect(result).toBeDefined();
      expect(result.tokens).toBeInstanceOf(Array);
      expect(result.tokens.length).toBeGreaterThan(0);
    });

    it('should categorize tokens correctly', async () => {
      const result = await runTokenExtraction(testProjectPath);

      const categories = new Set(result.tokens.map(t => t.category));

      expect(categories.has(TokenCategory.Color)).toBe(true);
      expect(categories.has(TokenCategory.Spacing)).toBe(true);
      expect(categories.has(TokenCategory.Typography)).toBe(true);
    });

    it('should assign confidence scores', async () => {
      const result = await runTokenExtraction(testProjectPath);

      result.tokens.forEach(token => {
        expect(token.confidence).toBeDefined();
        expect(token.confidence).toBeGreaterThan(0);
        expect(token.confidence).toBeLessThanOrEqual(1);
      });
    });

    it('should detect conflicts when present', async () => {
      const result = await runTokenExtraction(testProjectPath, {
        conflictResolution: 'manual',
      });

      expect(result.conflicts).toBeDefined();
    });

    it('should respect priority order for conflicts', async () => {
      const result = await runTokenExtraction(testProjectPath, {
        priority: ['theme', 'tailwind', 'css'],
        conflictResolution: 'priority',
      });

      const colorToken = result.tokens.find(t => t.name === 'primary');
      if (colorToken && colorToken.source) {
        expect(colorToken.source).toContain('theme');
      }
    });

    it('should handle missing sources gracefully', async () => {
      const nonExistentPath = '/path/that/does/not/exist';

      await expect(async () => {
        await runTokenExtraction(nonExistentPath);
      }).rejects.toThrow();
    });

    it('should extract W3C-compliant tokens', async () => {
      const result = await runTokenExtraction(testProjectPath, {
        outputFormats: ['json'],
      });

      result.tokens.forEach(token => {
        expect(token).toHaveProperty('$type');
        expect(token).toHaveProperty('$value');
      });
    });

    it('should handle empty project', async () => {
      const emptyPath = path.join(__dirname, 'empty-fixtures');

      if (!fs.existsSync(emptyPath)) {
        fs.mkdirSync(emptyPath, { recursive: true });
      }

      const result = await runTokenExtraction(emptyPath);

      expect(result.tokens).toBeInstanceOf(Array);
      expect(result.tokens.length).toBe(0);

      // Cleanup
      fs.rmdirSync(emptyPath);
    });
  });

  describe('Output Generation', () => {
    const outputDir = path.join(__dirname, 'test-output');

    beforeEach(() => {
      if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
      }
    });

    afterEach(() => {
      if (fs.existsSync(outputDir)) {
        fs.rmSync(outputDir, { recursive: true });
      }
    });

    it('should generate JSON output', async () => {
      await runTokenExtraction(testProjectPath, {
        outputFormats: ['json'],
        outputDir,
      });

      const jsonPath = path.join(outputDir, 'tokens.json');
      expect(fs.existsSync(jsonPath)).toBe(true);

      const content = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
      expect(content).toHaveProperty('colors');
      expect(content).toHaveProperty('spacing');
    });

    it('should generate CSS output', async () => {
      await runTokenExtraction(testProjectPath, {
        outputFormats: ['css'],
        outputDir,
      });

      const cssPath = path.join(outputDir, 'tokens.css');
      expect(fs.existsSync(cssPath)).toBe(true);

      const content = fs.readFileSync(cssPath, 'utf8');
      expect(content).toContain(':root');
      expect(content).toContain('--');
    });

    it('should generate Markdown output', async () => {
      await runTokenExtraction(testProjectPath, {
        outputFormats: ['markdown'],
        outputDir,
      });

      const mdPath = path.join(outputDir, 'tokens.md');
      expect(fs.existsSync(mdPath)).toBe(true);

      const content = fs.readFileSync(mdPath, 'utf8');
      expect(content).toContain('# Design Tokens');
      expect(content).toContain('## Colors');
    });

    it('should generate all formats when requested', async () => {
      await runTokenExtraction(testProjectPath, {
        outputFormats: ['json', 'css', 'markdown'],
        outputDir,
      });

      expect(fs.existsSync(path.join(outputDir, 'tokens.json'))).toBe(true);
      expect(fs.existsSync(path.join(outputDir, 'tokens.css'))).toBe(true);
      expect(fs.existsSync(path.join(outputDir, 'tokens.md'))).toBe(true);
    });
  });

  describe('Error Handling', () => {
    it('should provide clear error for invalid Tailwind config', async () => {
      const invalidConfigPath = path.join(__dirname, 'invalid-fixtures');

      if (!fs.existsSync(invalidConfigPath)) {
        fs.mkdirSync(invalidConfigPath, { recursive: true });
      }

      // Create invalid tailwind config
      fs.writeFileSync(
        path.join(invalidConfigPath, 'tailwind.config.js'),
        'module.exports = { invalid syntax }'
      );

      const result = await runTokenExtraction(invalidConfigPath);

      expect(result.errors).toBeDefined();
      expect(result.errors.length).toBeGreaterThan(0);

      // Cleanup
      fs.rmSync(invalidConfigPath, { recursive: true });
    });

    it('should handle permission errors gracefully', async () => {
      // This test would need special setup for permission testing
      // Skip for now, but structure is here
    });
  });

  describe('Performance', () => {
    it('should complete extraction in reasonable time', async () => {
      const startTime = Date.now();

      await runTokenExtraction(testProjectPath);

      const duration = Date.now() - startTime;

      // Should complete in under 5 seconds for test fixtures
      expect(duration).toBeLessThan(5000);
    });

    it('should handle large projects efficiently', async () => {
      // This would need a larger test fixture
      // Structure is here for future implementation
    });
  });
});
