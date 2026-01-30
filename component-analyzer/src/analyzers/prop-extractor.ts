/**
 * Advanced Prop Extraction System
 * Extracts props from multiple sources with confidence scoring
 */

import * as ts from 'typescript';
import { parse } from '@babel/parser';
import traverse from '@babel/traverse';
import * as t from '@babel/types';
import {
  PropType,
  PropSource,
  PropExtractionResult,
  ComponentFramework
} from '../types';

export class PropExtractor {
  /**
   * Extract props from multiple sources
   */
  extractProps(
    sourceCode: string,
    framework: ComponentFramework,
    componentName: string
  ): PropType[] {
    const results: PropExtractionResult[] = [];

    // Try TypeScript interface/type extraction
    const tsResult = this.extractFromTypeScript(sourceCode, componentName);
    if (tsResult) results.push(tsResult);

    // Try PropTypes extraction
    const propTypesResult = this.extractFromPropTypes(sourceCode, componentName);
    if (propTypesResult) results.push(propTypesResult);

    // Try default props extraction
    const defaultPropsResult = this.extractFromDefaultProps(sourceCode, componentName);
    if (defaultPropsResult) results.push(defaultPropsResult);

    // Try Vue props extraction
    if (framework === ComponentFramework.VUE) {
      const vueResult = this.extractFromVueProps(sourceCode, componentName);
      if (vueResult) results.push(vueResult);
    }

    // Try Svelte export extraction
    if (framework === ComponentFramework.SVELTE) {
      const svelteResult = this.extractFromSvelteExports(sourceCode);
      if (svelteResult) results.push(svelteResult);
    }

    // Merge results with confidence-based priority
    return this.mergeResults(results);
  }

  /**
   * Extract props from TypeScript interfaces/types
   */
  private extractFromTypeScript(
    sourceCode: string,
    componentName: string
  ): PropExtractionResult | null {
    try {
      const sourceFile = ts.createSourceFile(
        'temp.tsx',
        sourceCode,
        ts.ScriptTarget.Latest,
        true,
        ts.ScriptKind.TSX
      );

      const props: PropType[] = [];
      const propsInterfaceName = `${componentName}Props`;

      const visit = (node: ts.Node) => {
        // Interface declaration
        if (ts.isInterfaceDeclaration(node)) {
          if (node.name.text === propsInterfaceName || node.name.text.endsWith('Props')) {
            node.members.forEach(member => {
              if (ts.isPropertySignature(member) && member.name && ts.isIdentifier(member.name)) {
                const prop = this.extractPropFromPropertySignature(member);
                if (prop) props.push(prop);
              }
            });
          }
        }

        // Type alias declaration
        if (ts.isTypeAliasDeclaration(node)) {
          if (node.name.text === propsInterfaceName || node.name.text.endsWith('Props')) {
            if (ts.isTypeLiteralNode(node.type)) {
              node.type.members.forEach(member => {
                if (ts.isPropertySignature(member) && member.name && ts.isIdentifier(member.name)) {
                  const prop = this.extractPropFromPropertySignature(member);
                  if (prop) props.push(prop);
                }
              });
            }
          }
        }

        ts.forEachChild(node, visit);
      };

      visit(sourceFile);

      if (props.length === 0) return null;

      return {
        props,
        source: PropSource.TYPESCRIPT_INTERFACE,
        confidence: 1.0
      };
    } catch (error) {
      return null;
    }
  }

  /**
   * Extract prop from TypeScript property signature
   */
  private extractPropFromPropertySignature(member: ts.PropertySignature): PropType | null {
    if (!member.name || !ts.isIdentifier(member.name)) return null;

    const name = member.name.text;
    const required = !member.questionToken;
    const type = member.type ? this.tsTypeToString(member.type) : 'any';
    const description = this.extractTSJSDoc(member);
    const deprecated = this.isTSDeprecated(member);
    const deprecationMessage = deprecated ? this.getTSDeprecationMessage(member) : undefined;

    return {
      name,
      type,
      required,
      description,
      deprecated,
      deprecationMessage
    };
  }

  /**
   * Convert TypeScript type to string
   */
  private tsTypeToString(typeNode: ts.TypeNode): string {
    return typeNode.getText();
  }

  /**
   * Extract JSDoc from TypeScript node
   */
  private extractTSJSDoc(node: ts.Node): string | undefined {
    const jsDoc = (node as any).jsDoc;
    if (jsDoc && jsDoc.length > 0) {
      const comment = jsDoc[0].comment;
      if (typeof comment === 'string') return comment;
      if (Array.isArray(comment)) {
        return comment.map(c => c.text).join('');
      }
    }
    return undefined;
  }

  /**
   * Check if TypeScript node is deprecated
   */
  private isTSDeprecated(node: ts.Node): boolean {
    const jsDoc = (node as any).jsDoc;
    if (jsDoc && jsDoc.length > 0) {
      const tags = jsDoc[0].tags;
      if (tags) {
        return tags.some((tag: any) => tag.tagName?.text === 'deprecated');
      }
    }
    return false;
  }

  /**
   * Get TypeScript deprecation message
   */
  private getTSDeprecationMessage(node: ts.Node): string | undefined {
    const jsDoc = (node as any).jsDoc;
    if (jsDoc && jsDoc.length > 0) {
      const tags = jsDoc[0].tags;
      if (tags) {
        const deprecatedTag = tags.find((tag: any) => tag.tagName?.text === 'deprecated');
        if (deprecatedTag) {
          return deprecatedTag.comment;
        }
      }
    }
    return undefined;
  }

  /**
   * Extract props from PropTypes
   */
  private extractFromPropTypes(
    sourceCode: string,
    componentName: string
  ): PropExtractionResult | null {
    try {
      const ast = parse(sourceCode, {
        sourceType: 'module',
        plugins: ['jsx', 'typescript']
      });

      const props: PropType[] = [];

      traverse(ast, {
        AssignmentExpression(path) {
          const { left, right } = path.node;

          // ComponentName.propTypes = { ... }
          if (
            t.isMemberExpression(left) &&
            t.isIdentifier(left.object) &&
            left.object.name === componentName &&
            t.isIdentifier(left.property) &&
            left.property.name === 'propTypes' &&
            t.isObjectExpression(right)
          ) {
            right.properties.forEach(prop => {
              if (t.isObjectProperty(prop) && t.isIdentifier(prop.key)) {
                const propType = this.extractPropFromPropType(prop);
                if (propType) props.push(propType);
              }
            });
          }
        }
      });

      if (props.length === 0) return null;

      return {
        props,
        source: PropSource.PROPTYPES,
        confidence: 0.9
      };
    } catch (error) {
      return null;
    }
  }

  /**
   * Extract prop from PropTypes object property
   */
  private extractPropFromPropType(prop: t.ObjectProperty): PropType | null {
    if (!t.isIdentifier(prop.key)) return null;

    const name = prop.key.name;
    let type = 'any';
    let required = false;

    // PropTypes.string.isRequired
    if (t.isMemberExpression(prop.value)) {
      const propTypeChain = this.getPropTypeChain(prop.value);
      type = this.propTypeChainToString(propTypeChain);
      required = propTypeChain.includes('isRequired');
    }
    // PropTypes.string
    else if (t.isMemberExpression(prop.value)) {
      type = this.propTypeToString(prop.value);
    }

    return {
      name,
      type,
      required
    };
  }

  /**
   * Get PropTypes chain
   */
  private getPropTypeChain(node: t.MemberExpression): string[] {
    const chain: string[] = [];

    const traverse = (n: t.Expression | t.V8IntrinsicIdentifier): void => {
      if (t.isMemberExpression(n)) {
        traverse(n.object);
        if (t.isIdentifier(n.property)) {
          chain.push(n.property.name);
        }
      } else if (t.isIdentifier(n)) {
        chain.push(n.name);
      }
    };

    traverse(node);
    return chain;
  }

  /**
   * Convert PropTypes chain to type string
   */
  private propTypeChainToString(chain: string[]): string {
    const typeMap: Record<string, string> = {
      string: 'string',
      number: 'number',
      bool: 'boolean',
      func: 'Function',
      object: 'object',
      array: 'any[]',
      node: 'React.ReactNode',
      element: 'React.ReactElement',
      any: 'any'
    };

    for (const key of Object.keys(typeMap)) {
      if (chain.includes(key)) {
        return typeMap[key];
      }
    }

    if (chain.includes('arrayOf')) return 'any[]';
    if (chain.includes('objectOf')) return 'Record<string, any>';
    if (chain.includes('shape')) return 'object';
    if (chain.includes('oneOf')) return 'string | number';
    if (chain.includes('oneOfType')) return 'any';

    return 'any';
  }

  /**
   * Convert PropTypes to type string
   */
  private propTypeToString(node: t.MemberExpression): string {
    const chain = this.getPropTypeChain(node);
    return this.propTypeChainToString(chain);
  }

  /**
   * Extract props from defaultProps
   */
  private extractFromDefaultProps(
    sourceCode: string,
    componentName: string
  ): PropExtractionResult | null {
    try {
      const ast = parse(sourceCode, {
        sourceType: 'module',
        plugins: ['jsx', 'typescript']
      });

      const props: PropType[] = [];

      traverse(ast, {
        AssignmentExpression(path) {
          const { left, right } = path.node;

          // ComponentName.defaultProps = { ... }
          if (
            t.isMemberExpression(left) &&
            t.isIdentifier(left.object) &&
            left.object.name === componentName &&
            t.isIdentifier(left.property) &&
            left.property.name === 'defaultProps' &&
            t.isObjectExpression(right)
          ) {
            right.properties.forEach(prop => {
              if (t.isObjectProperty(prop) && t.isIdentifier(prop.key)) {
                const name = prop.key.name;
                const defaultValue = this.getDefaultValue(prop.value);
                props.push({
                  name,
                  type: 'any',
                  required: false,
                  defaultValue
                });
              }
            });
          }
        }
      });

      if (props.length === 0) return null;

      return {
        props,
        source: PropSource.DEFAULT_PROPS,
        confidence: 0.7
      };
    } catch (error) {
      return null;
    }
  }

  /**
   * Get default value from expression
   */
  private getDefaultValue(node: t.Expression | t.PatternLike): string | undefined {
    if (t.isStringLiteral(node)) return `"${node.value}"`;
    if (t.isNumericLiteral(node)) return String(node.value);
    if (t.isBooleanLiteral(node)) return String(node.value);
    if (t.isNullLiteral(node)) return 'null';
    if (t.isIdentifier(node) && node.name === 'undefined') return 'undefined';
    if (t.isArrayExpression(node)) return '[]';
    if (t.isObjectExpression(node)) return '{}';
    if (t.isArrowFunctionExpression(node) || t.isFunctionExpression(node)) return '() => {}';
    return undefined;
  }

  /**
   * Extract props from Vue component props option
   */
  private extractFromVueProps(
    sourceCode: string,
    componentName: string
  ): PropExtractionResult | null {
    try {
      const ast = parse(sourceCode, {
        sourceType: 'module',
        plugins: ['jsx', 'typescript']
      });

      const props: PropType[] = [];

      traverse(ast, {
        ObjectExpression(path) {
          const propsProperty = path.node.properties.find(
            p => t.isObjectProperty(p) && t.isIdentifier(p.key) && p.key.name === 'props'
          );

          if (propsProperty && t.isObjectProperty(propsProperty)) {
            if (t.isObjectExpression(propsProperty.value)) {
              propsProperty.value.properties.forEach(prop => {
                if (t.isObjectProperty(prop) && t.isIdentifier(prop.key)) {
                  const propType = this.extractVueProp(prop);
                  if (propType) props.push(propType);
                }
              });
            } else if (t.isArrayExpression(propsProperty.value)) {
              propsProperty.value.elements.forEach(element => {
                if (t.isStringLiteral(element)) {
                  props.push({
                    name: element.value,
                    type: 'any',
                    required: false
                  });
                }
              });
            }
          }
        }
      });

      if (props.length === 0) return null;

      return {
        props,
        source: PropSource.VUE_PROPS,
        confidence: 0.95
      };
    } catch (error) {
      return null;
    }
  }

  /**
   * Extract Vue prop definition
   */
  private extractVueProp(prop: t.ObjectProperty): PropType | null {
    if (!t.isIdentifier(prop.key)) return null;

    const name = prop.key.name;
    let type = 'any';
    let required = false;
    let defaultValue: string | undefined;

    if (t.isObjectExpression(prop.value)) {
      prop.value.properties.forEach(p => {
        if (t.isObjectProperty(p) && t.isIdentifier(p.key)) {
          if (p.key.name === 'type') {
            type = this.getVueType(p.value);
          } else if (p.key.name === 'required' && t.isBooleanLiteral(p.value)) {
            required = p.value.value;
          } else if (p.key.name === 'default') {
            defaultValue = this.getDefaultValue(p.value);
          }
        }
      });
    }

    return {
      name,
      type,
      required,
      defaultValue
    };
  }

  /**
   * Get Vue type string
   */
  private getVueType(node: t.Expression | t.PatternLike): string {
    if (t.isIdentifier(node)) {
      const typeMap: Record<string, string> = {
        String: 'string',
        Number: 'number',
        Boolean: 'boolean',
        Array: 'any[]',
        Object: 'object',
        Function: 'Function',
        Date: 'Date'
      };
      return typeMap[node.name] || 'any';
    }

    if (t.isArrayExpression(node)) {
      const types = node.elements
        .filter((e): e is t.Identifier => t.isIdentifier(e))
        .map(e => this.getVueType(e));
      return types.join(' | ');
    }

    return 'any';
  }

  /**
   * Extract props from Svelte exports
   */
  private extractFromSvelteExports(sourceCode: string): PropExtractionResult | null {
    const props: PropType[] = [];
    const exportRegex = /export\s+let\s+(\w+)(?:\s*:\s*([^=;]+))?(?:\s*=\s*([^;]+))?;/g;

    let match;
    while ((match = exportRegex.exec(sourceCode)) !== null) {
      const name = match[1];
      const type = match[2]?.trim() || 'any';
      const defaultValue = match[3]?.trim();

      props.push({
        name,
        type,
        required: !defaultValue,
        defaultValue
      });
    }

    if (props.length === 0) return null;

    return {
      props,
      source: PropSource.SVELTE_EXPORT,
      confidence: 0.95
    };
  }

  /**
   * Merge prop extraction results with confidence-based priority
   */
  private mergeResults(results: PropExtractionResult[]): PropType[] {
    if (results.length === 0) return [];

    // Sort by confidence (highest first)
    results.sort((a, b) => b.confidence - a.confidence);

    const mergedProps = new Map<string, PropType>();

    for (const result of results) {
      for (const prop of result.props) {
        if (!mergedProps.has(prop.name)) {
          mergedProps.set(prop.name, prop);
        } else {
          // Merge with existing prop
          const existing = mergedProps.get(prop.name)!;
          mergedProps.set(prop.name, {
            ...existing,
            type: existing.type === 'any' ? prop.type : existing.type,
            defaultValue: existing.defaultValue || prop.defaultValue,
            description: existing.description || prop.description,
            deprecated: existing.deprecated || prop.deprecated,
            deprecationMessage: existing.deprecationMessage || prop.deprecationMessage
          });
        }
      }
    }

    return Array.from(mergedProps.values());
  }
}
