/**
 * Component Variant Detection Engine
 * Identifies component variants from union types and discriminated unions
 */

import * as ts from 'typescript';
import {
  PropType,
  ComponentVariant,
  VariantHeuristic
} from '../types';

export class VariantDetector {
  private heuristics: VariantHeuristic[];

  constructor() {
    this.heuristics = [
      this.createDiscriminatedUnionHeuristic(),
      this.createEnumVariantHeuristic(),
      this.createBooleanVariantHeuristic(),
      this.createAsPropsHeuristic(),
      this.createSizeVariantHeuristic(),
      this.createColorVariantHeuristic(),
      this.createVariantPropHeuristic()
    ];
  }

  /**
   * Detect variants from props
   */
  detectVariants(props: PropType[]): ComponentVariant[] {
    const variants: ComponentVariant[] = [];

    for (const heuristic of this.heuristics) {
      const detected = heuristic.detect(props);
      variants.push(...detected);
    }

    // Remove duplicates and merge similar variants
    return this.deduplicateVariants(variants);
  }

  /**
   * Detect variants from TypeScript source
   */
  detectVariantsFromSource(sourceCode: string, propsTypeName: string): ComponentVariant[] {
    try {
      const sourceFile = ts.createSourceFile(
        'temp.tsx',
        sourceCode,
        ts.ScriptTarget.Latest,
        true,
        ts.ScriptKind.TSX
      );

      const variants: ComponentVariant[] = [];

      const visit = (node: ts.Node) => {
        // Check for discriminated union in type alias
        if (ts.isTypeAliasDeclaration(node) && node.name.text === propsTypeName) {
          if (ts.isUnionTypeNode(node.type)) {
            const unionVariants = this.extractUnionVariants(node.type);
            variants.push(...unionVariants);
          }
        }

        ts.forEachChild(node, visit);
      };

      visit(sourceFile);
      return variants;
    } catch (error) {
      return [];
    }
  }

  /**
   * Extract variants from union type node
   */
  private extractUnionVariants(unionType: ts.UnionTypeNode): ComponentVariant[] {
    const variants: ComponentVariant[] = [];

    // Look for discriminated unions
    const discriminator = this.findDiscriminator(unionType);
    if (!discriminator) return variants;

    unionType.types.forEach((typeNode, index) => {
      if (ts.isTypeLiteralNode(typeNode)) {
        const discriminatorProp = typeNode.members.find(
          member =>
            ts.isPropertySignature(member) &&
            member.name &&
            ts.isIdentifier(member.name) &&
            member.name.text === discriminator
        ) as ts.PropertySignature | undefined;

        if (discriminatorProp && discriminatorProp.type) {
          const value = this.extractLiteralValue(discriminatorProp.type);
          if (value !== null) {
            const additionalProps = this.extractAdditionalProps(
              typeNode,
              discriminator
            );

            variants.push({
              name: `${discriminator}_${value}`,
              discriminator,
              discriminatorValue: value,
              additionalProps,
              description: `Variant when ${discriminator} is ${value}`
            });
          }
        }
      }
    });

    return variants;
  }

  /**
   * Find discriminator property in union
   */
  private findDiscriminator(unionType: ts.UnionTypeNode): string | null {
    const commonProps = new Map<string, number>();

    unionType.types.forEach(typeNode => {
      if (ts.isTypeLiteralNode(typeNode)) {
        typeNode.members.forEach(member => {
          if (ts.isPropertySignature(member) && member.name && ts.isIdentifier(member.name)) {
            const propName = member.name.text;
            if (member.type && this.isLiteralType(member.type)) {
              commonProps.set(propName, (commonProps.get(propName) || 0) + 1);
            }
          }
        });
      }
    });

    // Discriminator should appear in all union members
    const unionMemberCount = unionType.types.length;
    for (const [propName, count] of commonProps.entries()) {
      if (count === unionMemberCount) {
        return propName;
      }
    }

    return null;
  }

  /**
   * Check if type is a literal type
   */
  private isLiteralType(typeNode: ts.TypeNode): boolean {
    return (
      ts.isLiteralTypeNode(typeNode) ||
      typeNode.kind === ts.SyntaxKind.StringKeyword ||
      typeNode.kind === ts.SyntaxKind.NumberKeyword ||
      typeNode.kind === ts.SyntaxKind.BooleanKeyword
    );
  }

  /**
   * Extract literal value from type node
   */
  private extractLiteralValue(typeNode: ts.TypeNode): string | number | boolean | null {
    if (ts.isLiteralTypeNode(typeNode)) {
      const literal = typeNode.literal;
      if (ts.isStringLiteral(literal)) return literal.text;
      if (ts.isNumericLiteral(literal)) return Number(literal.text);
      if (literal.kind === ts.SyntaxKind.TrueKeyword) return true;
      if (literal.kind === ts.SyntaxKind.FalseKeyword) return false;
    }
    return null;
  }

  /**
   * Extract additional props for variant
   */
  private extractAdditionalProps(
    typeNode: ts.TypeLiteralNode,
    discriminator: string
  ): PropType[] {
    const props: PropType[] = [];

    typeNode.members.forEach(member => {
      if (ts.isPropertySignature(member) && member.name && ts.isIdentifier(member.name)) {
        const propName = member.name.text;
        if (propName !== discriminator) {
          props.push({
            name: propName,
            type: member.type ? member.type.getText() : 'any',
            required: !member.questionToken
          });
        }
      }
    });

    return props;
  }

  /**
   * Create discriminated union heuristic
   */
  private createDiscriminatedUnionHeuristic(): VariantHeuristic {
    return {
      name: 'discriminated-union',
      confidence: 1.0,
      detect: (props: PropType[]): ComponentVariant[] => {
        const variants: ComponentVariant[] = [];

        // Look for props with union types containing literal values
        for (const prop of props) {
          const unionMatch = prop.type.match(/^(['"][\w-]+['"](?:\s*\|\s*['"][\w-]+['"])+)$/);
          if (unionMatch) {
            const values = unionMatch[1]
              .split('|')
              .map(v => v.trim().replace(/['"]/g, ''));

            values.forEach(value => {
              variants.push({
                name: `${prop.name}_${value}`,
                discriminator: prop.name,
                discriminatorValue: value,
                additionalProps: [],
                description: `Variant when ${prop.name} is "${value}"`
              });
            });
          }
        }

        return variants;
      }
    };
  }

  /**
   * Create enum variant heuristic
   */
  private createEnumVariantHeuristic(): VariantHeuristic {
    return {
      name: 'enum-variant',
      confidence: 0.9,
      detect: (props: PropType[]): ComponentVariant[] => {
        const variants: ComponentVariant[] = [];

        for (const prop of props) {
          // Check for enum-like types
          if (
            prop.name.toLowerCase().includes('variant') ||
            prop.name.toLowerCase().includes('type') ||
            prop.name.toLowerCase().includes('kind')
          ) {
            const enumMatch = prop.type.match(/(\w+(?:\.\w+)?)/);
            if (enumMatch && /^[A-Z]/.test(enumMatch[1])) {
              // This is likely an enum reference
              // We can't determine actual values without type checking,
              // but we can mark it as a variant discriminator
              variants.push({
                name: `${prop.name}_enum`,
                discriminator: prop.name,
                discriminatorValue: 'enum',
                additionalProps: [],
                description: `Variants based on ${prop.name} enum`
              });
            }
          }
        }

        return variants;
      }
    };
  }

  /**
   * Create boolean variant heuristic
   */
  private createBooleanVariantHeuristic(): VariantHeuristic {
    return {
      name: 'boolean-variant',
      confidence: 0.7,
      detect: (props: PropType[]): ComponentVariant[] => {
        const variants: ComponentVariant[] = [];

        for (const prop of props) {
          if (prop.type === 'boolean' || prop.type === 'bool') {
            // Boolean props create two variants
            variants.push(
              {
                name: `${prop.name}_true`,
                discriminator: prop.name,
                discriminatorValue: true,
                additionalProps: [],
                description: `Variant when ${prop.name} is true`
              },
              {
                name: `${prop.name}_false`,
                discriminator: prop.name,
                discriminatorValue: false,
                additionalProps: [],
                description: `Variant when ${prop.name} is false`
              }
            );
          }
        }

        return variants;
      }
    };
  }

  /**
   * Create 'as' prop heuristic (polymorphic components)
   */
  private createAsPropsHeuristic(): VariantHeuristic {
    return {
      name: 'as-prop',
      confidence: 0.95,
      detect: (props: PropType[]): ComponentVariant[] => {
        const variants: ComponentVariant[] = [];

        const asProp = props.find(p => p.name === 'as' || p.name === 'component');
        if (!asProp) return variants;

        // Common HTML elements
        const elements = ['div', 'span', 'button', 'a', 'section', 'article'];
        elements.forEach(element => {
          variants.push({
            name: `as_${element}`,
            discriminator: asProp.name,
            discriminatorValue: element,
            additionalProps: [],
            description: `Renders as <${element}>`
          });
        });

        return variants;
      }
    };
  }

  /**
   * Create size variant heuristic
   */
  private createSizeVariantHeuristic(): VariantHeuristic {
    return {
      name: 'size-variant',
      confidence: 0.8,
      detect: (props: PropType[]): ComponentVariant[] => {
        const variants: ComponentVariant[] = [];

        const sizeProp = props.find(p => p.name === 'size');
        if (!sizeProp) return variants;

        const sizeMatch = sizeProp.type.match(/['"](\w+)['"](?:\s*\|\s*['"](\w+)['"])?/g);
        if (sizeMatch) {
          const sizes = sizeMatch.map(s => s.replace(/['"]/g, ''));
          sizes.forEach(size => {
            variants.push({
              name: `size_${size}`,
              discriminator: 'size',
              discriminatorValue: size,
              additionalProps: [],
              description: `Size variant: ${size}`
            });
          });
        }

        return variants;
      }
    };
  }

  /**
   * Create color variant heuristic
   */
  private createColorVariantHeuristic(): VariantHeuristic {
    return {
      name: 'color-variant',
      confidence: 0.8,
      detect: (props: PropType[]): ComponentVariant[] => {
        const variants: ComponentVariant[] = [];

        const colorProp = props.find(
          p => p.name === 'color' || p.name === 'variant' || p.name === 'theme'
        );
        if (!colorProp) return variants;

        const colorMatch = colorProp.type.match(/['"](\w+)['"](?:\s*\|\s*['"](\w+)['"])?/g);
        if (colorMatch) {
          const colors = colorMatch.map(c => c.replace(/['"]/g, ''));
          colors.forEach(color => {
            variants.push({
              name: `${colorProp.name}_${color}`,
              discriminator: colorProp.name,
              discriminatorValue: color,
              additionalProps: [],
              description: `${colorProp.name} variant: ${color}`
            });
          });
        }

        return variants;
      }
    };
  }

  /**
   * Create generic variant prop heuristic
   */
  private createVariantPropHeuristic(): VariantHeuristic {
    return {
      name: 'variant-prop',
      confidence: 0.85,
      detect: (props: PropType[]): ComponentVariant[] => {
        const variants: ComponentVariant[] = [];

        const variantProp = props.find(p => p.name === 'variant');
        if (!variantProp) return variants;

        const variantMatch = variantProp.type.match(/['"](\w+)['"](?:\s*\|\s*['"](\w+)['"])?/g);
        if (variantMatch) {
          const variantNames = variantMatch.map(v => v.replace(/['"]/g, ''));
          variantNames.forEach(variantName => {
            variants.push({
              name: `variant_${variantName}`,
              discriminator: 'variant',
              discriminatorValue: variantName,
              additionalProps: [],
              description: `Variant: ${variantName}`
            });
          });
        }

        return variants;
      }
    };
  }

  /**
   * Deduplicate and merge similar variants
   */
  private deduplicateVariants(variants: ComponentVariant[]): ComponentVariant[] {
    const seen = new Map<string, ComponentVariant>();

    for (const variant of variants) {
      const key = `${variant.discriminator}:${variant.discriminatorValue}`;
      if (!seen.has(key)) {
        seen.set(key, variant);
      } else {
        // Merge additional props
        const existing = seen.get(key)!;
        const merged = {
          ...existing,
          additionalProps: this.mergeProps(
            existing.additionalProps,
            variant.additionalProps
          )
        };
        seen.set(key, merged);
      }
    }

    return Array.from(seen.values());
  }

  /**
   * Merge prop arrays
   */
  private mergeProps(props1: PropType[], props2: PropType[]): PropType[] {
    const merged = new Map<string, PropType>();

    for (const prop of [...props1, ...props2]) {
      if (!merged.has(prop.name)) {
        merged.set(prop.name, prop);
      }
    }

    return Array.from(merged.values());
  }
}
