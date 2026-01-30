/**
 * Component Analysis Engine Tests
 */

import { ComponentAnalyzer } from '../engine';
import { AnalyzerConfig, ComponentType } from '../types';
import * as path from 'path';

describe('ComponentAnalyzer', () => {
  let analyzer: ComponentAnalyzer;
  const testProjectPath = path.join(__dirname, '../../examples');

  beforeEach(() => {
    analyzer = new ComponentAnalyzer();
  });

  describe('analyze', () => {
    it('should detect React components', async () => {
      const config: Partial<AnalyzerConfig> = {
        frameworks: ['react'],
      };

      const result = await analyzer.analyze(testProjectPath, config);

      expect(result).toBeDefined();
      expect(result.components).toBeInstanceOf(Array);
      expect(result.components.length).toBeGreaterThan(0);

      const reactComponents = result.components.filter(
        c => c.framework === 'react'
      );
      expect(reactComponents.length).toBeGreaterThan(0);
    });

    it('should extract TypeScript props', async () => {
      const result = await analyzer.analyze(testProjectPath);

      const componentWithProps = result.components.find(c => c.props.length > 0);

      expect(componentWithProps).toBeDefined();
      if (componentWithProps) {
        expect(componentWithProps.props).toBeInstanceOf(Array);
        componentWithProps.props.forEach(prop => {
          expect(prop).toHaveProperty('name');
          expect(prop).toHaveProperty('type');
          expect(prop).toHaveProperty('required');
        });
      }
    });

    it('should detect component variants', async () => {
      const result = await analyzer.analyze(testProjectPath);

      const componentWithVariants = result.components.find(
        c => c.variants && c.variants.length > 0
      );

      expect(componentWithVariants).toBeDefined();
      if (componentWithVariants) {
        expect(componentWithVariants.variants).toBeInstanceOf(Array);
        componentWithVariants.variants.forEach(variant => {
          expect(variant).toHaveProperty('discriminator');
          expect(variant).toHaveProperty('discriminatorValue');
        });
      }
    });

    it('should track component usage', async () => {
      const config: Partial<AnalyzerConfig> = {
        trackUsage: true,
      };

      const result = await analyzer.analyze(testProjectPath, config);

      const componentWithUsage = result.components.find(
        c => c.usageCount && c.usageCount > 0
      );

      expect(componentWithUsage).toBeDefined();
    });

    it('should categorize component types', async () => {
      const result = await analyzer.analyze(testProjectPath);

      const types = new Set(result.components.map(c => c.type));

      // Should detect multiple component types
      expect(types.size).toBeGreaterThan(0);
    });

    it('should calculate complexity metrics', async () => {
      const result = await analyzer.analyze(testProjectPath);

      result.components.forEach(component => {
        expect(component.complexity).toBeDefined();
        expect(component.complexity).toBeGreaterThanOrEqual(0);
      });
    });

    it('should handle empty directories', async () => {
      const emptyPath = path.join(__dirname, 'empty-test');

      const result = await analyzer.analyze(emptyPath);

      expect(result.components).toBeInstanceOf(Array);
      expect(result.components.length).toBe(0);
    });

    it('should respect ignore patterns', async () => {
      const config: Partial<AnalyzerConfig> = {
        ignorePatterns: ['**/*.test.tsx', '**/*.stories.tsx'],
      };

      const result = await analyzer.analyze(testProjectPath, config);

      const testFiles = result.components.filter(c =>
        c.filePath.includes('.test.') || c.filePath.includes('.stories.')
      );

      expect(testFiles.length).toBe(0);
    });
  });

  describe('detectFramework', () => {
    it('should detect React from imports', async () => {
      const framework = await analyzer.detectFramework(testProjectPath);

      expect(['react', 'vue', 'svelte', 'angular']).toContain(framework);
    });
  });

  describe('generateInventory', () => {
    it('should generate CSV inventory', async () => {
      const result = await analyzer.analyze(testProjectPath);
      const csv = await analyzer.generateInventory(result, 'csv');

      expect(csv).toContain('name,type,framework');
      expect(csv.split('\n').length).toBeGreaterThan(1);
    });

    it('should generate JSON inventory', async () => {
      const result = await analyzer.analyze(testProjectPath);
      const json = await analyzer.generateInventory(result, 'json');

      const parsed = JSON.parse(json);
      expect(parsed).toHaveProperty('components');
      expect(parsed.components).toBeInstanceOf(Array);
    });

    it('should generate Markdown inventory', async () => {
      const result = await analyzer.analyze(testProjectPath);
      const markdown = await analyzer.generateInventory(result, 'markdown');

      expect(markdown).toContain('# Component Inventory');
      expect(markdown).toContain('##');
    });
  });

  describe('Summary Generation', () => {
    it('should generate accurate summary statistics', async () => {
      const result = await analyzer.analyze(testProjectPath);

      expect(result.summary).toBeDefined();
      expect(result.summary.totalComponents).toBe(result.components.length);
      expect(result.summary.frameworks).toBeInstanceOf(Object);
    });

    it('should count components by type', async () => {
      const result = await analyzer.analyze(testProjectPath);

      expect(result.summary.byType).toBeDefined();
      expect(typeof result.summary.byType).toBe('object');
    });

    it('should identify most used components', async () => {
      const config: Partial<AnalyzerConfig> = {
        trackUsage: true,
      };

      const result = await analyzer.analyze(testProjectPath, config);

      expect(result.summary.mostUsed).toBeDefined();
      expect(result.summary.mostUsed).toBeInstanceOf(Array);
    });
  });

  describe('Error Handling', () => {
    it('should handle non-existent paths', async () => {
      const invalidPath = '/path/that/does/not/exist';

      await expect(async () => {
        await analyzer.analyze(invalidPath);
      }).rejects.toThrow();
    });

    it('should handle malformed TypeScript files', async () => {
      // Would need special test fixtures for this
      // Structure is here for future implementation
    });
  });

  describe('Performance', () => {
    it('should analyze project in reasonable time', async () => {
      const startTime = Date.now();

      await analyzer.analyze(testProjectPath);

      const duration = Date.now() - startTime;

      // Should complete in under 10 seconds for example project
      expect(duration).toBeLessThan(10000);
    });
  });
});
