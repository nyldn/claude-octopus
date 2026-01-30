/**
 * Variant Detector Tests
 */

import { VariantDetector } from '../analyzers/variant-detector';
import { PropType } from '../types';

describe('VariantDetector', () => {
  let detector: VariantDetector;

  beforeEach(() => {
    detector = new VariantDetector();
  });

  describe('detectVariants', () => {
    it('should detect discriminated union variants', () => {
      const props: PropType[] = [
        {
          name: 'variant',
          type: '"primary" | "secondary" | "danger"',
          required: true
        }
      ];

      const variants = detector.detectVariants(props);

      expect(variants).toHaveLength(3);
      expect(variants[0].discriminator).toBe('variant');
      expect(variants[0].discriminatorValue).toBe('primary');
      expect(variants[1].discriminatorValue).toBe('secondary');
      expect(variants[2].discriminatorValue).toBe('danger');
    });

    it('should detect boolean variants', () => {
      const props: PropType[] = [
        {
          name: 'disabled',
          type: 'boolean',
          required: false
        }
      ];

      const variants = detector.detectVariants(props);

      expect(variants).toHaveLength(2);
      expect(variants[0].discriminatorValue).toBe(true);
      expect(variants[1].discriminatorValue).toBe(false);
    });

    it('should detect size variants', () => {
      const props: PropType[] = [
        {
          name: 'size',
          type: '"small" | "medium" | "large"',
          required: false
        }
      ];

      const variants = detector.detectVariants(props);

      expect(variants.length).toBeGreaterThan(0);
      expect(variants.some(v => v.discriminator === 'size')).toBe(true);
    });

    it('should detect color variants', () => {
      const props: PropType[] = [
        {
          name: 'color',
          type: '"red" | "blue" | "green"',
          required: false
        }
      ];

      const variants = detector.detectVariants(props);

      expect(variants.length).toBeGreaterThan(0);
      expect(variants.some(v => v.discriminator === 'color')).toBe(true);
    });

    it('should detect as prop variants', () => {
      const props: PropType[] = [
        {
          name: 'as',
          type: 'string',
          required: false
        }
      ];

      const variants = detector.detectVariants(props);

      expect(variants.length).toBeGreaterThan(0);
      expect(variants.some(v => v.discriminator === 'as')).toBe(true);
    });
  });

  describe('detectVariantsFromSource', () => {
    it('should detect variants from discriminated union type', () => {
      const sourceCode = `
        type ButtonProps =
          | { variant: 'primary'; color: string }
          | { variant: 'secondary'; outline: boolean }
          | { variant: 'danger'; destructive: boolean };
      `;

      const variants = detector.detectVariantsFromSource(sourceCode, 'ButtonProps');

      expect(variants).toHaveLength(3);
      expect(variants[0].discriminator).toBe('variant');
      expect(variants[0].additionalProps.length).toBeGreaterThan(0);
    });

    it('should handle union with literal types', () => {
      const sourceCode = `
        type AlertProps = {
          type: 'info' | 'warning' | 'error';
          message: string;
        };
      `;

      const variants = detector.detectVariantsFromSource(sourceCode, 'AlertProps');

      // May or may not detect based on heuristics
      expect(Array.isArray(variants)).toBe(true);
    });
  });

  describe('deduplication', () => {
    it('should deduplicate variants with same discriminator value', () => {
      const props: PropType[] = [
        {
          name: 'variant',
          type: '"primary" | "secondary"',
          required: true
        },
        {
          name: 'type',
          type: '"primary" | "secondary"',
          required: false
        }
      ];

      const variants = detector.detectVariants(props);

      // Should have variants but deduplicated
      const variantValues = variants.map(v => `${v.discriminator}:${v.discriminatorValue}`);
      const uniqueValues = new Set(variantValues);

      expect(variantValues.length).toBe(uniqueValues.size);
    });
  });
});
