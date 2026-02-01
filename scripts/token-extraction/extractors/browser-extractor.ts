/**
 * Browser Extractor
 * Extracts design tokens from live websites using Chrome MCP integration
 */

import {
  Token,
  TokenSource,
  ExtractionError,
  BrowserExtractionResult,
  BrowserElementCapture,
} from '../types';

// MCP tool types (these would be provided by the MCP server)
interface MCPReadPageResult {
  accessibility_tree?: string;
  elements?: Array<{
    ref_id: string;
    role: string;
    name?: string;
    description?: string;
  }>;
}

interface MCPJavaScriptResult {
  result?: any;
  error?: string;
}

export interface BrowserExtractorOptions {
  url: string;
  tabId: number;
  selectors?: string[];
  captureAll?: boolean;
  timeout?: number;
}

/**
 * Browser Extractor Class
 * Uses Claude in Chrome MCP tools to extract tokens from live pages
 */
export class BrowserExtractor {
  private options: BrowserExtractorOptions;
  private errors: ExtractionError[] = [];

  constructor(options: BrowserExtractorOptions) {
    this.options = {
      timeout: 30000,
      captureAll: false,
      selectors: [],
      ...options,
    };
  }

  /**
   * Extract tokens from browser
   */
  async extract(): Promise<BrowserExtractionResult> {
    this.errors = [];
    const tokens: Token[] = [];

    try {
      // Step 1: Navigate to URL if needed
      await this.ensureNavigated();

      // Step 2: Get page elements
      const elements = await this.getPageElements();

      // Step 3: Capture computed styles for each element
      const captures = await this.captureElementStyles(elements);

      // Step 4: Convert captures to tokens
      const extractedTokens = this.capturesToTokens(captures);
      tokens.push(...extractedTokens);

      return {
        tokens,
        errors: this.errors,
        metadata: {
          url: this.options.url,
          timestamp: new Date().toISOString(),
          elementsCaptured: captures.length,
          interactionStatesFound: 0,
        },
      };
    } catch (error) {
      this.errors.push({
        source: TokenSource.BROWSER_EXTRACTION,
        message: `Browser extraction failed: ${error instanceof Error ? error.message : String(error)}`,
        error: error instanceof Error ? error : undefined,
      });

      return {
        tokens: [],
        errors: this.errors,
        metadata: {
          url: this.options.url,
          timestamp: new Date().toISOString(),
          elementsCaptured: 0,
          interactionStatesFound: 0,
        },
      };
    }
  }

  /**
   * Ensure browser is navigated to the target URL
   */
  private async ensureNavigated(): Promise<void> {
    // In actual implementation, this would check if we're on the right page
    // and navigate if needed using mcp__claude-in-chrome__navigate
    // For now, we assume the page is already loaded
    console.log(`Browser extractor: Using page at ${this.options.url}`);
  }

  /**
   * Get elements from the page
   */
  private async getPageElements(): Promise<string[]> {
    const selectors: string[] = [];

    if (this.options.selectors && this.options.selectors.length > 0) {
      // Use provided selectors
      selectors.push(...this.options.selectors);
    } else if (this.options.captureAll) {
      // Default selectors for design tokens
      selectors.push(
        ':root', // CSS variables
        'body',  // Body styles
        'button', // Button styles
        'a',      // Link styles
        'input',  // Input styles
        'h1, h2, h3, h4, h5, h6', // Heading styles
        'p',      // Paragraph styles
      );
    }

    return selectors;
  }

  /**
   * Capture computed styles for elements
   */
  private async captureElementStyles(
    selectors: string[]
  ): Promise<BrowserElementCapture[]> {
    const captures: BrowserElementCapture[] = [];

    for (const selector of selectors) {
      try {
        const capture = await this.captureElementStyle(selector);
        if (capture) {
          captures.push(capture);
        }
      } catch (error) {
        this.errors.push({
          source: TokenSource.BROWSER_EXTRACTION,
          message: `Failed to capture styles for selector "${selector}": ${error instanceof Error ? error.message : String(error)}`,
        });
      }
    }

    return captures;
  }

  /**
   * Capture computed style for a single element
   */
  private async captureElementStyle(
    selector: string
  ): Promise<BrowserElementCapture | null> {
    try {
      // This would use mcp__claude-in-chrome__javascript_tool to execute:
      // const el = document.querySelector(selector);
      // if (!el) return null;
      // const styles = window.getComputedStyle(el);
      // return { tagName: el.tagName, styles: Object.fromEntries([...styles]) };

      // For now, return a mock structure
      // In real implementation, this would call the MCP tool
      const mockStyles = this.getMockComputedStyles(selector);

      return {
        selector,
        tagName: this.getTagNameFromSelector(selector),
        computedStyles: mockStyles,
      };
    } catch (error) {
      return null;
    }
  }

  /**
   * Get tag name from selector (helper for mock)
   */
  private getTagNameFromSelector(selector: string): string {
    if (selector === ':root') return 'HTML';
    if (selector === 'body') return 'BODY';
    if (selector.startsWith('h')) return selector.toUpperCase();
    return selector.split(/[.,#\[\s]/)[0]?.toUpperCase() || 'DIV';
  }

  /**
   * Mock computed styles (in real implementation, this comes from browser)
   */
  private getMockComputedStyles(selector: string): Record<string, string> {
    // This is a mock - real implementation would get actual computed styles
    const baseStyles: Record<string, string> = {
      color: '#000000',
      backgroundColor: '#ffffff',
      fontSize: '16px',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
      lineHeight: '1.5',
      padding: '0px',
      margin: '0px',
    };

    if (selector === ':root' || selector === 'body') {
      return {
        '--color-primary': '#3b82f6',
        '--color-secondary': '#64748b',
        '--spacing-sm': '0.5rem',
        '--spacing-md': '1rem',
        '--spacing-lg': '1.5rem',
        '--font-size-base': '16px',
        '--font-family-sans': baseStyles.fontFamily,
      };
    }

    return baseStyles;
  }

  /**
   * Convert element captures to design tokens
   */
  private capturesToTokens(captures: BrowserElementCapture[]): Token[] {
    const tokens: Token[] = [];

    for (const capture of captures) {
      // Extract CSS custom properties (variables)
      if (capture.selector === ':root' || capture.selector === 'body') {
        for (const [prop, value] of Object.entries(capture.computedStyles)) {
          if (prop.startsWith('--')) {
            const tokenName = prop.substring(2); // Remove '--' prefix
            const path = this.cssVariableToPath(tokenName);

            tokens.push({
              name: tokenName,
              value,
              type: this.inferTypeFromValue(value),
              category: path[0],
              source: TokenSource.BROWSER_EXTRACTION,
              priority: 50, // Lower priority than code-defined
              path,
              description: `Extracted from ${capture.selector} in browser`,
              metadata: {
                extractedFrom: 'browser',
                selector: capture.selector,
                originalProperty: prop,
              },
            });
          }
        }
      }

      // Extract standard properties as tokens
      const relevantProps = ['color', 'backgroundColor', 'fontSize', 'fontFamily', 'lineHeight'];
      for (const prop of relevantProps) {
        if (capture.computedStyles[prop]) {
          const tokenName = `${capture.selector}-${this.camelToKebab(prop)}`;
          const path = this.propertyToPath(capture.selector, prop);

          tokens.push({
            name: tokenName,
            value: capture.computedStyles[prop],
            type: this.inferTypeFromProperty(prop),
            category: path[0],
            source: TokenSource.BROWSER_EXTRACTION,
            priority: 40, // Even lower priority for computed styles
            path,
            description: `Computed ${prop} for ${capture.selector}`,
            metadata: {
              extractedFrom: 'browser',
              selector: capture.selector,
              property: prop,
              computed: true,
            },
          });
        }
      }
    }

    return tokens;
  }

  /**
   * Convert CSS variable name to token path
   */
  private cssVariableToPath(varName: string): string[] {
    // Convert 'color-primary' to ['color', 'primary']
    const parts = varName.split('-');
    return parts.length > 1 ? parts : ['custom', varName];
  }

  /**
   * Convert property to token path
   */
  private propertyToPath(selector: string, property: string): string[] {
    const selectorPart = selector.replace(/[^a-zA-Z0-9]/g, '-');
    const propPart = this.camelToKebab(property);
    return ['browser', selectorPart, propPart];
  }

  /**
   * Convert camelCase to kebab-case
   */
  private camelToKebab(str: string): string {
    return str.replace(/([a-z])([A-Z])/g, '$1-$2').toLowerCase();
  }

  /**
   * Infer token type from value
   */
  private inferTypeFromValue(value: string): any {
    if (/^#[0-9a-f]{3,8}$/i.test(value) || /^rgb/i.test(value)) {
      return 'color';
    }
    if (/^\d+(\.\d+)?(px|rem|em|%)$/.test(value)) {
      return 'dimension';
    }
    if (/^[0-9.]+$/.test(value)) {
      return 'number';
    }
    return 'string';
  }

  /**
   * Infer token type from CSS property
   */
  private inferTypeFromProperty(property: string): any {
    const typeMap: Record<string, string> = {
      color: 'color',
      backgroundColor: 'color',
      fontSize: 'dimension',
      lineHeight: 'number',
      fontFamily: 'fontFamily',
      fontWeight: 'fontWeight',
    };
    return typeMap[property] || 'string';
  }
}

/**
 * Convenience function to extract tokens from browser
 */
export async function extractFromBrowser(
  url: string,
  tabId: number,
  options?: Partial<BrowserExtractorOptions>
): Promise<BrowserExtractionResult> {
  const extractor = new BrowserExtractor({
    url,
    tabId,
    ...options,
  });

  return extractor.extract();
}
