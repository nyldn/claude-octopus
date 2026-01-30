/**
 * TypeScript Compiler API Analyzer
 * Advanced AST traversal for TypeScript-based components
 */

import * as ts from 'typescript';
import {
  ComponentMetadata,
  ComponentFramework,
  ComponentPattern,
  PropType,
  PropSource,
  PropExtractionResult,
  VisitorContext,
  ImportInfo
} from '../types';

export class TypeScriptAnalyzer {
  private program: ts.Program;
  private checker: ts.TypeChecker;

  constructor(
    private configPath?: string,
    private compilerOptions?: ts.CompilerOptions
  ) {
    const config = this.loadTsConfig();
    this.program = ts.createProgram([], config);
    this.checker = this.program.getTypeChecker();
  }

  /**
   * Load TypeScript configuration
   */
  private loadTsConfig(): ts.CompilerOptions {
    if (this.compilerOptions) {
      return this.compilerOptions;
    }

    if (this.configPath) {
      const configFile = ts.readConfigFile(this.configPath, ts.sys.readFile);
      if (configFile.error) {
        console.warn('Failed to load tsconfig:', configFile.error.messageText);
      } else {
        const parsed = ts.parseJsonConfigFileContent(
          configFile.config,
          ts.sys,
          process.cwd()
        );
        return parsed.options;
      }
    }

    return {
      target: ts.ScriptTarget.ES2022,
      module: ts.ModuleKind.ESNext,
      jsx: ts.JsxEmit.React,
      strict: true,
      esModuleInterop: true,
      skipLibCheck: true,
      moduleResolution: ts.ModuleResolutionKind.NodeJs
    };
  }

  /**
   * Update program with new files
   */
  updateProgram(files: string[]): void {
    const config = this.loadTsConfig();
    this.program = ts.createProgram(files, config, undefined, this.program);
    this.checker = this.program.getTypeChecker();
  }

  /**
   * Analyze a TypeScript source file
   */
  analyzeFile(filePath: string): ComponentMetadata[] {
    const sourceFile = this.program.getSourceFile(filePath);
    if (!sourceFile) {
      return [];
    }

    const context: VisitorContext = {
      filePath,
      framework: this.detectFramework(sourceFile),
      components: new Map(),
      imports: this.extractImports(sourceFile),
      sourceFile
    };

    this.visitNode(sourceFile, context);
    return Array.from(context.components.values());
  }

  /**
   * Detect framework from imports
   */
  private detectFramework(sourceFile: ts.SourceFile): ComponentFramework {
    const text = sourceFile.getText();

    if (text.includes('from \'react\'') || text.includes('from "react"')) {
      return ComponentFramework.REACT;
    }
    if (text.includes('from \'vue\'') || text.includes('from "vue"')) {
      return ComponentFramework.VUE;
    }
    if (text.includes('from \'svelte\'') || text.includes('.svelte')) {
      return ComponentFramework.SVELTE;
    }

    return ComponentFramework.UNKNOWN;
  }

  /**
   * Extract imports from source file
   */
  private extractImports(sourceFile: ts.SourceFile): Map<string, ImportInfo> {
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
              } else if (ts.isNamespaceImport(node.importClause.namedBindings)) {
                // Namespace import
                imports.set(node.importClause.namedBindings.name.text, {
                  source,
                  importName: '*',
                  localName: node.importClause.namedBindings.name.text,
                  isDefault: false,
                  isNamespace: true
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
   * Visit AST node
   */
  private visitNode(node: ts.Node, context: VisitorContext): void {
    // Function component
    if (this.isFunctionComponent(node, context)) {
      const component = this.analyzeFunctionComponent(node as ts.FunctionDeclaration, context);
      if (component) {
        context.components.set(component.name, component);
      }
    }

    // Arrow function component
    if (this.isArrowFunctionComponent(node, context)) {
      const component = this.analyzeArrowFunctionComponent(node as ts.VariableStatement, context);
      if (component) {
        context.components.set(component.name, component);
      }
    }

    // Class component
    if (this.isClassComponent(node, context)) {
      const component = this.analyzeClassComponent(node as ts.ClassDeclaration, context);
      if (component) {
        context.components.set(component.name, component);
      }
    }

    // HOC
    if (this.isHOC(node, context)) {
      const component = this.analyzeHOC(node, context);
      if (component) {
        context.components.set(component.name, component);
      }
    }

    ts.forEachChild(node, child => this.visitNode(child, context));
  }

  /**
   * Check if node is a function component
   */
  private isFunctionComponent(node: ts.Node, context: VisitorContext): boolean {
    if (!ts.isFunctionDeclaration(node)) return false;
    if (!node.name) return false;

    const name = node.name.text;
    if (!/^[A-Z]/.test(name)) return false;

    if (context.framework === ComponentFramework.REACT) {
      return this.returnsJSX(node);
    }

    return false;
  }

  /**
   * Check if node is an arrow function component
   */
  private isArrowFunctionComponent(node: ts.Node, context: VisitorContext): boolean {
    if (!ts.isVariableStatement(node)) return false;

    const declaration = node.declarationList.declarations[0];
    if (!declaration || !declaration.name || !ts.isIdentifier(declaration.name)) return false;

    const name = declaration.name.text;
    if (!/^[A-Z]/.test(name)) return false;

    if (declaration.initializer && ts.isArrowFunction(declaration.initializer)) {
      if (context.framework === ComponentFramework.REACT) {
        return this.returnsJSX(declaration.initializer);
      }
    }

    return false;
  }

  /**
   * Check if node is a class component
   */
  private isClassComponent(node: ts.Node, context: VisitorContext): boolean {
    if (!ts.isClassDeclaration(node)) return false;
    if (!node.name) return false;

    const name = node.name.text;
    if (!/^[A-Z]/.test(name)) return false;

    if (context.framework === ComponentFramework.REACT) {
      return this.extendsReactComponent(node, context);
    }

    return false;
  }

  /**
   * Check if node is a Higher-Order Component
   */
  private isHOC(node: ts.Node, context: VisitorContext): boolean {
    if (!ts.isVariableStatement(node) && !ts.isFunctionDeclaration(node)) {
      return false;
    }

    let func: ts.FunctionDeclaration | ts.ArrowFunction | undefined;
    let name: string | undefined;

    if (ts.isFunctionDeclaration(node)) {
      func = node;
      name = node.name?.text;
    } else if (ts.isVariableStatement(node)) {
      const declaration = node.declarationList.declarations[0];
      if (declaration && ts.isIdentifier(declaration.name)) {
        name = declaration.name.text;
        if (declaration.initializer && ts.isArrowFunction(declaration.initializer)) {
          func = declaration.initializer;
        }
      }
    }

    if (!func || !name) return false;

    // HOCs typically start with "with" or "enhance"
    if (/^(with|enhance|wrap)/.test(name)) {
      // Returns a component (function that returns JSX)
      return true;
    }

    return false;
  }

  /**
   * Check if function returns JSX
   */
  private returnsJSX(node: ts.FunctionDeclaration | ts.ArrowFunction): boolean {
    let hasJSX = false;

    const visit = (n: ts.Node) => {
      if (ts.isJsxElement(n) || ts.isJsxSelfClosingElement(n) || ts.isJsxFragment(n)) {
        hasJSX = true;
        return;
      }
      ts.forEachChild(n, visit);
    };

    visit(node);
    return hasJSX;
  }

  /**
   * Check if class extends React.Component
   */
  private extendsReactComponent(node: ts.ClassDeclaration, context: VisitorContext): boolean {
    if (!node.heritageClauses) return false;

    for (const clause of node.heritageClauses) {
      if (clause.token === ts.SyntaxKind.ExtendsKeyword) {
        for (const type of clause.types) {
          const typeName = type.expression.getText();
          if (typeName === 'Component' || typeName === 'PureComponent' ||
              typeName === 'React.Component' || typeName === 'React.PureComponent') {
            return true;
          }
        }
      }
    }

    return false;
  }

  /**
   * Analyze function component
   */
  private analyzeFunctionComponent(
    node: ts.FunctionDeclaration,
    context: VisitorContext
  ): ComponentMetadata | null {
    if (!node.name) return null;

    const name = node.name.text;
    const props = this.extractPropsFromFunction(node);
    const pattern = this.detectComponentPattern(node, context);

    return {
      name,
      filePath: context.filePath,
      framework: context.framework,
      pattern,
      props,
      variants: [],
      usages: [],
      exports: this.getExportInfo(node),
      dependencies: this.extractDependencies(node, context),
      complexity: this.calculateComplexity(node),
      sourceLocation: this.getSourceLocation(node)
    };
  }

  /**
   * Analyze arrow function component
   */
  private analyzeArrowFunctionComponent(
    node: ts.VariableStatement,
    context: VisitorContext
  ): ComponentMetadata | null {
    const declaration = node.declarationList.declarations[0];
    if (!declaration || !ts.isIdentifier(declaration.name)) return null;
    if (!declaration.initializer || !ts.isArrowFunction(declaration.initializer)) return null;

    const name = declaration.name.text;
    const arrowFunc = declaration.initializer;
    const props = this.extractPropsFromFunction(arrowFunc);
    const pattern = this.detectComponentPattern(arrowFunc, context);

    return {
      name,
      filePath: context.filePath,
      framework: context.framework,
      pattern,
      props,
      variants: [],
      usages: [],
      exports: this.getExportInfo(node),
      dependencies: this.extractDependencies(arrowFunc, context),
      complexity: this.calculateComplexity(arrowFunc),
      sourceLocation: this.getSourceLocation(node)
    };
  }

  /**
   * Analyze class component
   */
  private analyzeClassComponent(
    node: ts.ClassDeclaration,
    context: VisitorContext
  ): ComponentMetadata | null {
    if (!node.name) return null;

    const name = node.name.text;
    const props = this.extractPropsFromClass(node);

    return {
      name,
      filePath: context.filePath,
      framework: context.framework,
      pattern: ComponentPattern.CLASS,
      props,
      variants: [],
      usages: [],
      exports: this.getExportInfo(node),
      dependencies: this.extractDependencies(node, context),
      complexity: this.calculateComplexity(node),
      sourceLocation: this.getSourceLocation(node)
    };
  }

  /**
   * Analyze Higher-Order Component
   */
  private analyzeHOC(node: ts.Node, context: VisitorContext): ComponentMetadata | null {
    let name: string | undefined;
    let func: ts.Node = node;

    if (ts.isFunctionDeclaration(node)) {
      name = node.name?.text;
    } else if (ts.isVariableStatement(node)) {
      const declaration = node.declarationList.declarations[0];
      if (declaration && ts.isIdentifier(declaration.name)) {
        name = declaration.name.text;
        if (declaration.initializer) {
          func = declaration.initializer;
        }
      }
    }

    if (!name) return null;

    return {
      name,
      filePath: context.filePath,
      framework: context.framework,
      pattern: ComponentPattern.HOC,
      props: [],
      variants: [],
      usages: [],
      exports: this.getExportInfo(node),
      dependencies: this.extractDependencies(func, context),
      complexity: this.calculateComplexity(func),
      sourceLocation: this.getSourceLocation(node)
    };
  }

  /**
   * Extract props from function component
   */
  private extractPropsFromFunction(
    node: ts.FunctionDeclaration | ts.ArrowFunction
  ): PropType[] {
    if (!node.parameters.length) return [];

    const propsParam = node.parameters[0];
    if (!propsParam.type) return [];

    return this.extractPropsFromType(propsParam.type);
  }

  /**
   * Extract props from class component
   */
  private extractPropsFromClass(node: ts.ClassDeclaration): PropType[] {
    if (!node.heritageClauses) return [];

    for (const clause of node.heritageClauses) {
      if (clause.token === ts.SyntaxKind.ExtendsKeyword) {
        for (const type of clause.types) {
          if (type.typeArguments && type.typeArguments.length > 0) {
            const propsType = type.typeArguments[0];
            return this.extractPropsFromType(propsType);
          }
        }
      }
    }

    return [];
  }

  /**
   * Extract props from TypeScript type
   */
  private extractPropsFromType(typeNode: ts.TypeNode): PropType[] {
    const props: PropType[] = [];

    if (ts.isTypeLiteralNode(typeNode)) {
      typeNode.members.forEach(member => {
        if (ts.isPropertySignature(member) && member.name) {
          const prop = this.extractPropFromMember(member);
          if (prop) props.push(prop);
        }
      });
    } else if (ts.isTypeReferenceNode(typeNode)) {
      const symbol = this.checker.getSymbolAtLocation(typeNode.typeName);
      if (symbol) {
        const type = this.checker.getDeclaredTypeOfSymbol(symbol);
        const properties = this.checker.getPropertiesOfType(type);

        properties.forEach(prop => {
          const propType = this.extractPropFromSymbol(prop);
          if (propType) props.push(propType);
        });
      }
    } else if (ts.isIntersectionTypeNode(typeNode)) {
      typeNode.types.forEach(type => {
        props.push(...this.extractPropsFromType(type));
      });
    }

    return props;
  }

  /**
   * Extract prop from property signature
   */
  private extractPropFromMember(member: ts.PropertySignature): PropType | null {
    if (!member.name || !ts.isIdentifier(member.name)) return null;

    const name = member.name.text;
    const required = !member.questionToken;
    const type = member.type ? this.typeToString(member.type) : 'any';

    return {
      name,
      type,
      required,
      description: this.extractJSDocComment(member)
    };
  }

  /**
   * Extract prop from symbol
   */
  private extractPropFromSymbol(symbol: ts.Symbol): PropType | null {
    const name = symbol.getName();
    const type = this.checker.getTypeOfSymbolAtLocation(symbol, symbol.valueDeclaration!);
    const required = !(symbol.flags & ts.SymbolFlags.Optional);

    return {
      name,
      type: this.checker.typeToString(type),
      required,
      description: ts.displayPartsToString(symbol.getDocumentationComment(this.checker))
    };
  }

  /**
   * Convert TypeNode to string
   */
  private typeToString(typeNode: ts.TypeNode): string {
    return typeNode.getText();
  }

  /**
   * Extract JSDoc comment
   */
  private extractJSDocComment(node: ts.Node): string | undefined {
    const jsDoc = (node as any).jsDoc;
    if (jsDoc && jsDoc.length > 0) {
      return jsDoc[0].comment;
    }
    return undefined;
  }

  /**
   * Detect component pattern
   */
  private detectComponentPattern(node: ts.Node, context: VisitorContext): ComponentPattern {
    const text = node.getText();

    if (text.includes('React.forwardRef')) return ComponentPattern.FORWARD_REF;
    if (text.includes('React.memo')) return ComponentPattern.MEMO;
    if (text.includes('React.lazy')) return ComponentPattern.LAZY;

    if (ts.isFunctionDeclaration(node) || ts.isArrowFunction(node)) {
      return ComponentPattern.FUNCTION;
    }

    return ComponentPattern.FUNCTION;
  }

  /**
   * Get export information
   */
  private getExportInfo(node: ts.Node): { isDefault: boolean; isNamed: boolean; aliases: string[] } {
    const modifiers = ts.canHaveModifiers(node) ? ts.getModifiers(node) : undefined;
    let isDefault = false;
    let isNamed = false;

    if (modifiers) {
      isDefault = modifiers.some(m => m.kind === ts.SyntaxKind.DefaultKeyword);
      isNamed = modifiers.some(m => m.kind === ts.SyntaxKind.ExportKeyword);
    }

    return { isDefault, isNamed, aliases: [] };
  }

  /**
   * Extract component dependencies
   */
  private extractDependencies(node: ts.Node, context: VisitorContext): string[] {
    const dependencies = new Set<string>();

    const visit = (n: ts.Node) => {
      if (ts.isJsxSelfClosingElement(n) || ts.isJsxOpeningElement(n)) {
        const tagName = n.tagName.getText();
        if (/^[A-Z]/.test(tagName)) {
          dependencies.add(tagName);
        }
      }
      ts.forEachChild(n, visit);
    };

    visit(node);
    return Array.from(dependencies);
  }

  /**
   * Calculate complexity metrics
   */
  private calculateComplexity(node: ts.Node): {
    cyclomaticComplexity: number;
    cognitiveComplexity: number;
    linesOfCode: number;
  } {
    let cyclomaticComplexity = 1;
    let cognitiveComplexity = 0;
    let nestingLevel = 0;

    const visit = (n: ts.Node, nesting: number) => {
      // Cyclomatic complexity
      if (ts.isIfStatement(n) || ts.isConditionalExpression(n) ||
          ts.isWhileStatement(n) || ts.isForStatement(n) ||
          ts.isCaseClause(n) || ts.isCatchClause(n)) {
        cyclomaticComplexity++;
      }

      // Cognitive complexity
      if (ts.isIfStatement(n) || ts.isWhileStatement(n) ||
          ts.isForStatement(n) || ts.isCatchClause(n)) {
        cognitiveComplexity += (1 + nesting);
        nestingLevel = Math.max(nestingLevel, nesting + 1);
        ts.forEachChild(n, child => visit(child, nesting + 1));
        return;
      }

      ts.forEachChild(n, child => visit(child, nesting));
    };

    visit(node, 0);

    const sourceFile = node.getSourceFile();
    const start = node.getStart(sourceFile);
    const end = node.getEnd();
    const text = sourceFile.text.substring(start, end);
    const linesOfCode = text.split('\n').filter(line => line.trim().length > 0).length;

    return {
      cyclomaticComplexity,
      cognitiveComplexity,
      linesOfCode
    };
  }

  /**
   * Get source location
   */
  private getSourceLocation(node: ts.Node): {
    start: { line: number; column: number };
    end: { line: number; column: number };
  } {
    const sourceFile = node.getSourceFile();
    const start = sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile));
    const end = sourceFile.getLineAndCharacterOfPosition(node.getEnd());

    return {
      start: { line: start.line + 1, column: start.character + 1 },
      end: { line: end.line + 1, column: end.character + 1 }
    };
  }
}
