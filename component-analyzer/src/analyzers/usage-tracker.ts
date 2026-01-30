/**
 * Component Usage Tracking System
 * Tracks component usage across the codebase with advanced pattern detection
 */

import * as ts from 'typescript';
import { parse } from '@babel/parser';
import traverse from '@babel/traverse';
import * as t from '@babel/types';
import {
  ComponentUsage,
  ComponentFramework,
  ImportInfo
} from '../types';

export class UsageTracker {
  private program: ts.Program | null = null;

  /**
   * Set TypeScript program for analysis
   */
  setProgram(program: ts.Program): void {
    this.program = program;
  }

  /**
   * Track component usages across files
   */
  trackUsages(
    componentName: string,
    componentFilePath: string,
    files: string[],
    framework: ComponentFramework
  ): ComponentUsage[] {
    const usages: ComponentUsage[] = [];

    for (const filePath of files) {
      if (filePath === componentFilePath) continue;

      const fileUsages = this.trackUsagesInFile(
        componentName,
        componentFilePath,
        filePath,
        framework
      );
      usages.push(...fileUsages);
    }

    return usages;
  }

  /**
   * Track component usages in a single file
   */
  private trackUsagesInFile(
    componentName: string,
    componentFilePath: string,
    filePath: string,
    framework: ComponentFramework
  ): ComponentUsage[] {
    try {
      if (this.program) {
        return this.trackUsagesTypeScript(
          componentName,
          componentFilePath,
          filePath,
          framework
        );
      } else {
        return this.trackUsagesBabel(
          componentName,
          componentFilePath,
          filePath,
          framework
        );
      }
    } catch (error) {
      console.warn(`Failed to track usages in ${filePath}:`, error);
      return [];
    }
  }

  /**
   * Track usages using TypeScript Compiler API
   */
  private trackUsagesTypeScript(
    componentName: string,
    componentFilePath: string,
    filePath: string,
    framework: ComponentFramework
  ): ComponentUsage[] {
    if (!this.program) return [];

    const sourceFile = this.program.getSourceFile(filePath);
    if (!sourceFile) return [];

    const usages: ComponentUsage[] = [];
    const imports = this.extractTypeScriptImports(sourceFile, componentFilePath);

    // Find local names that import this component
    const localNames = new Set<string>();
    imports.forEach((importInfo, localName) => {
      if (this.matchesComponent(importInfo, componentName, componentFilePath)) {
        localNames.add(localName);
      }
    });

    if (localNames.size === 0) return usages;

    // Find JSX usages
    const visit = (node: ts.Node) => {
      if (framework === ComponentFramework.REACT) {
        // JSX element
        if (ts.isJsxOpeningElement(node) || ts.isJsxSelfClosingElement(node)) {
          const tagName = node.tagName.getText();
          if (localNames.has(tagName)) {
            const usage = this.extractTypeScriptUsage(
              node,
              sourceFile,
              imports.get(tagName)!
            );
            usages.push(usage);
          }
        }
      } else if (framework === ComponentFramework.VUE) {
        // Vue template (in JSX or string template)
        // This is simplified - real Vue analysis would need template parsing
        if (ts.isJsxElement(node) || ts.isJsxSelfClosingElement(node)) {
          const tagName = this.getVueTagName(node);
          const kebabName = this.camelToKebab(componentName);
          if (tagName === componentName || tagName === kebabName) {
            const usage = this.extractTypeScriptUsage(
              node,
              sourceFile,
              imports.get(componentName)!
            );
            usages.push(usage);
          }
        }
      }

      ts.forEachChild(node, visit);
    };

    visit(sourceFile);
    return usages;
  }

  /**
   * Track usages using Babel
   */
  private trackUsagesBabel(
    componentName: string,
    componentFilePath: string,
    filePath: string,
    framework: ComponentFramework
  ): ComponentUsage[] {
    const usages: ComponentUsage[] = [];

    try {
      const fs = require('fs');
      const sourceCode = fs.readFileSync(filePath, 'utf-8');

      const ast = parse(sourceCode, {
        sourceType: 'module',
        plugins: ['jsx', 'typescript']
      });

      const imports = new Map<string, ImportInfo>();

      // Extract imports
      traverse(ast, {
        ImportDeclaration(path) {
          const source = path.node.source.value;

          path.node.specifiers.forEach(specifier => {
            if (t.isImportDefaultSpecifier(specifier)) {
              imports.set(specifier.local.name, {
                source,
                importName: 'default',
                localName: specifier.local.name,
                isDefault: true,
                isNamespace: false
              });
            } else if (t.isImportSpecifier(specifier)) {
              const importName = t.isIdentifier(specifier.imported)
                ? specifier.imported.name
                : specifier.imported.value;
              imports.set(specifier.local.name, {
                source,
                importName,
                localName: specifier.local.name,
                isDefault: false,
                isNamespace: false
              });
            } else if (t.isImportNamespaceSpecifier(specifier)) {
              imports.set(specifier.local.name, {
                source,
                importName: '*',
                localName: specifier.local.name,
                isDefault: false,
                isNamespace: true
              });
            }
          });
        }
      });

      // Find local names that import this component
      const localNames = new Set<string>();
      imports.forEach((importInfo, localName) => {
        if (this.matchesComponent(importInfo, componentName, componentFilePath)) {
          localNames.add(localName);
        }
      });

      if (localNames.size === 0) return usages;

      // Find JSX usages
      traverse(ast, {
        JSXElement(path) {
          const openingElement = path.node.openingElement;
          const tagName = this.getJSXTagName(openingElement.name);

          if (localNames.has(tagName)) {
            const usage = this.extractBabelUsage(
              path.node,
              imports.get(tagName)!,
              filePath
            );
            usages.push(usage);
          }
        },
        JSXFragment(path) {
          const openingElement = path.node.openingElement as any;
          if (openingElement && openingElement.name) {
            const tagName = this.getJSXTagName(openingElement.name);

            if (localNames.has(tagName)) {
              const usage = this.extractBabelUsage(
                path.node as any,
                imports.get(tagName)!,
                filePath
              );
              usages.push(usage);
            }
          }
        }
      });

    } catch (error) {
      // Ignore parse errors
    }

    return usages;
  }

  /**
   * Extract TypeScript imports
   */
  private extractTypeScriptImports(
    sourceFile: ts.SourceFile,
    targetFilePath: string
  ): Map<string, ImportInfo> {
    const imports = new Map<string, ImportInfo>();

    const visit = (node: ts.Node) => {
      if (ts.isImportDeclaration(node)) {
        const moduleSpecifier = node.moduleSpecifier;
        if (ts.isStringLiteral(moduleSpecifier)) {
          const source = moduleSpecifier.text;

          if (node.importClause) {
            // Default import
            if (node.importClause.name) {
              imports.set(node.importClause.name.text, {
                source,
                importName: 'default',
                localName: node.importClause.name.text,
                isDefault: true,
                isNamespace: false
              });
            }

            // Named imports
            if (node.importClause.namedBindings) {
              if (ts.isNamedImports(node.importClause.namedBindings)) {
                node.importClause.namedBindings.elements.forEach(element => {
                  const importName = element.propertyName?.text || element.name.text;
                  imports.set(element.name.text, {
                    source,
                    importName,
                    localName: element.name.text,
                    isDefault: false,
                    isNamespace: false
                  });
                });
              }
            }
          }
        }
      }
      ts.forEachChild(node, visit);
    };

    visit(sourceFile);
    return imports;
  }

  /**
   * Extract TypeScript usage
   */
  private extractTypeScriptUsage(
    node: ts.JsxOpeningElement | ts.JsxSelfClosingElement,
    sourceFile: ts.SourceFile,
    importInfo: ImportInfo
  ): ComponentUsage {
    const position = sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile));
    const propsUsed = this.extractPropsFromTSJSX(node);

    return {
      filePath: sourceFile.fileName,
      line: position.line + 1,
      column: position.character + 1,
      propsUsed,
      importSource: importInfo.source,
      isDefaultImport: importInfo.isDefault
    };
  }

  /**
   * Extract props from TypeScript JSX
   */
  private extractPropsFromTSJSX(
    node: ts.JsxOpeningElement | ts.JsxSelfClosingElement
  ): string[] {
    const props: string[] = [];

    node.attributes.properties.forEach(attr => {
      if (ts.isJsxAttribute(attr)) {
        const name = attr.name.getText();
        props.push(name);
      } else if (ts.isJsxSpreadAttribute(attr)) {
        props.push('...spread');
      }
    });

    return props;
  }

  /**
   * Extract Babel usage
   */
  private extractBabelUsage(
    node: t.JSXElement,
    importInfo: ImportInfo,
    filePath: string
  ): ComponentUsage {
    const location = node.loc || { start: { line: 0, column: 0 } };
    const propsUsed = this.extractPropsFromBabelJSX(node.openingElement);

    return {
      filePath,
      line: location.start.line,
      column: location.start.column,
      propsUsed,
      importSource: importInfo.source,
      isDefaultImport: importInfo.isDefault
    };
  }

  /**
   * Extract props from Babel JSX
   */
  private extractPropsFromBabelJSX(openingElement: t.JSXOpeningElement): string[] {
    const props: string[] = [];

    openingElement.attributes.forEach(attr => {
      if (t.isJSXAttribute(attr) && t.isJSXIdentifier(attr.name)) {
        props.push(attr.name.name);
      } else if (t.isJSXSpreadAttribute(attr)) {
        props.push('...spread');
      }
    });

    return props;
  }

  /**
   * Get JSX tag name from Babel node
   */
  private getJSXTagName(name: t.JSXIdentifier | t.JSXMemberExpression | t.JSXNamespacedName): string {
    if (t.isJSXIdentifier(name)) {
      return name.name;
    } else if (t.isJSXMemberExpression(name)) {
      return this.getJSXMemberName(name);
    } else if (t.isJSXNamespacedName(name)) {
      return `${name.namespace.name}:${name.name.name}`;
    }
    return '';
  }

  /**
   * Get JSX member expression name
   */
  private getJSXMemberName(expr: t.JSXMemberExpression): string {
    const object = t.isJSXIdentifier(expr.object)
      ? expr.object.name
      : this.getJSXMemberName(expr.object as t.JSXMemberExpression);
    return `${object}.${expr.property.name}`;
  }

  /**
   * Get Vue tag name
   */
  private getVueTagName(node: ts.Node): string {
    if (ts.isJsxOpeningElement(node) || ts.isJsxSelfClosingElement(node)) {
      return node.tagName.getText();
    }
    return '';
  }

  /**
   * Convert camelCase to kebab-case
   */
  private camelToKebab(str: string): string {
    return str.replace(/([a-z0-9])([A-Z])/g, '$1-$2').toLowerCase();
  }

  /**
   * Check if import matches component
   */
  private matchesComponent(
    importInfo: ImportInfo,
    componentName: string,
    componentFilePath: string
  ): boolean {
    // Check if import name matches
    if (importInfo.importName === componentName || importInfo.importName === 'default') {
      // Check if source matches (relative or absolute path)
      const normalizedSource = this.normalizePath(importInfo.source);
      const normalizedTarget = this.normalizePath(componentFilePath);

      if (normalizedSource === normalizedTarget) {
        return true;
      }

      // Check if source path points to target file
      if (normalizedTarget.includes(normalizedSource)) {
        return true;
      }
    }

    return false;
  }

  /**
   * Normalize file path
   */
  private normalizePath(path: string): string {
    return path
      .replace(/\\/g, '/')
      .replace(/\.(tsx?|jsx?)$/, '')
      .replace(/\/index$/, '');
  }
}
