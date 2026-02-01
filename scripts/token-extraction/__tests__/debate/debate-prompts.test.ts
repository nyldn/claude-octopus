/**
 * Debate Prompts Tests
 * Verify debate prompt generation and response parsing
 */

import { describe, it, expect } from 'vitest';
import {
  generateDebatePrompts,
  parseDebateResponse,
  DebatePromptContext,
} from '../../debate/debate-prompts';

// Mock context for testing
const mockContext: DebatePromptContext = {
  tokens: [
    {
      name: 'primary-500',
      value: '#3b82f6',
      type: 'color',
      path: ['colors', 'primary', '500'],
      source: 'tailwind.config',
    },
    {
      name: 'spacing-4',
      value: '16px',
      type: 'dimension',
      path: ['spacing', '4'],
      source: 'css-variables',
    },
  ],
  extractionSource: 'token-extraction-pipeline',
  projectName: 'test-project',
  round: 1,
};

describe('Debate Prompts', () => {
  describe('generateDebatePrompts', () => {
    it('should generate all three prompt types', () => {
      const prompts = generateDebatePrompts(mockContext);

      expect(prompts).toHaveProperty('proposer');
      expect(prompts).toHaveProperty('critic');
      expect(prompts).toHaveProperty('synthesis');

      expect(typeof prompts.proposer).toBe('string');
      expect(typeof prompts.critic).toBe('function');
      expect(typeof prompts.synthesis).toBe('function');
    });

    it('should include context in proposer prompt', () => {
      const prompts = generateDebatePrompts(mockContext);

      expect(prompts.proposer).toContain('Round 1');
      expect(prompts.proposer).toContain('2 total');
      expect(prompts.proposer).toContain('primary-500');
      expect(prompts.proposer).toContain('spacing-4');
    });

    it('should include validation criteria in proposer prompt', () => {
      const prompts = generateDebatePrompts(mockContext);

      expect(prompts.proposer).toContain('Naming Consistency');
      expect(prompts.proposer).toContain('Value Accuracy');
      expect(prompts.proposer).toContain('Hierarchy');
      expect(prompts.proposer).toContain('Completeness');
      expect(prompts.proposer).toContain('Type Safety');
    });

    it('should request JSON output format in proposer prompt', () => {
      const prompts = generateDebatePrompts(mockContext);

      expect(prompts.proposer).toContain('```json');
      expect(prompts.proposer).toContain('issues');
      expect(prompts.proposer).toContain('improvements');
      expect(prompts.proposer).toContain('overallAssessment');
    });

    it('should generate critic prompt with proposer output', () => {
      const prompts = generateDebatePrompts(mockContext);
      const proposerOutput = JSON.stringify({
        issues: [{ issue: 'Test issue' }],
        improvements: [],
        overallAssessment: 'Test assessment',
      });

      const criticPrompt = prompts.critic(proposerOutput);

      expect(criticPrompt).toContain('Round 1');
      expect(criticPrompt).toContain('Test issue');
      expect(criticPrompt).toContain('Test assessment');
    });

    it('should include challenge criteria in critic prompt', () => {
      const prompts = generateDebatePrompts(mockContext);
      const criticPrompt = prompts.critic('{}');

      expect(criticPrompt).toContain('Are the proposed changes actually improvements?');
      expect(criticPrompt).toContain('Could the changes break existing patterns?');
      expect(criticPrompt).toContain('Are there edge cases not considered?');
      expect(criticPrompt).toContain('alternative solutions');
    });

    it('should generate synthesis prompt with both outputs', () => {
      const prompts = generateDebatePrompts(mockContext);
      const proposerOutput = JSON.stringify({
        issues: [{ issue: 'Proposer issue' }],
      });
      const criticOutput = JSON.stringify({
        agreements: [{ proposerIssue: 'Proposer issue', reasoning: 'Good point' }],
      });

      const synthesisPrompt = prompts.synthesis(proposerOutput, criticOutput);

      expect(synthesisPrompt).toContain('Round 1');
      expect(synthesisPrompt).toContain('Proposer issue');
      expect(synthesisPrompt).toContain('Good point');
    });

    it('should include synthesis tasks in synthesis prompt', () => {
      const prompts = generateDebatePrompts(mockContext);
      const synthesisPrompt = prompts.synthesis('{}', '{}');

      expect(synthesisPrompt).toContain('Identify consensus');
      expect(synthesisPrompt).toContain('Resolve conflicts');
      expect(synthesisPrompt).toContain('Prioritize actions');
      expect(synthesisPrompt).toContain('confidence scores');
    });

    it('should request structured output in synthesis prompt', () => {
      const prompts = generateDebatePrompts(mockContext);
      const synthesisPrompt = prompts.synthesis('{}', '{}');

      expect(synthesisPrompt).toContain('```json');
      expect(synthesisPrompt).toContain('consensus');
      expect(synthesisPrompt).toContain('resolvedConflicts');
      expect(synthesisPrompt).toContain('finalRecommendations');
      expect(synthesisPrompt).toContain('summary');
    });

    it('should include previous feedback when provided', () => {
      const contextWithFeedback: DebatePromptContext = {
        ...mockContext,
        previousFeedback: 'Previous round feedback here',
      };

      const prompts = generateDebatePrompts(contextWithFeedback);

      expect(prompts.proposer).toContain('Previous Round Feedback');
      expect(prompts.proposer).toContain('Previous round feedback here');
    });

    it('should handle large token lists', () => {
      const largeContext: DebatePromptContext = {
        ...mockContext,
        tokens: Array(100).fill(mockContext.tokens[0]),
      };

      const prompts = generateDebatePrompts(largeContext);

      expect(prompts.proposer).toContain('100 total');
      expect(prompts.proposer).toContain('and 50 more tokens');
    });
  });

  describe('parseDebateResponse', () => {
    it('should parse valid JSON from markdown code block', () => {
      const response = '```json\n{"issues": [], "improvements": []}\n```';

      const parsed = parseDebateResponse(response);

      expect(parsed).toEqual({ issues: [], improvements: [] });
    });

    it('should parse valid JSON without code block', () => {
      const response = '{"issues": [], "improvements": []}';

      const parsed = parseDebateResponse(response);

      expect(parsed).toEqual({ issues: [], improvements: [] });
    });

    it('should handle proposer response format', () => {
      const response = `\`\`\`json
{
  "issues": [
    {
      "tokenPath": "colors.primary.500",
      "severity": "medium",
      "issue": "Color value might not meet WCAG AA contrast requirements",
      "suggestion": "Verify contrast ratio against background colors"
    }
  ],
  "improvements": [
    {
      "category": "naming",
      "description": "Consider using semantic naming over descriptive",
      "examples": ["Use 'brand-primary' instead of 'blue-500'"]
    }
  ],
  "overallAssessment": "Tokens are well-structured"
}
\`\`\``;

      const parsed = parseDebateResponse(response);

      expect(parsed.issues).toHaveLength(1);
      expect(parsed.issues[0].tokenPath).toBe('colors.primary.500');
      expect(parsed.improvements).toHaveLength(1);
      expect(parsed.overallAssessment).toBe('Tokens are well-structured');
    });

    it('should handle critic response format', () => {
      const response = `\`\`\`json
{
  "agreements": [
    {
      "proposerIssue": "WCAG contrast concern",
      "reasoning": "Accessibility is critical"
    }
  ],
  "disagreements": [
    {
      "proposerIssue": "Semantic naming suggestion",
      "reasoning": "Current naming is clear",
      "alternative": "Keep current naming but add semantic aliases"
    }
  ],
  "additionalConcerns": [],
  "overallAssessment": "Proposer raised valid concerns"
}
\`\`\``;

      const parsed = parseDebateResponse(response);

      expect(parsed.agreements).toHaveLength(1);
      expect(parsed.disagreements).toHaveLength(1);
      expect(parsed.additionalConcerns).toHaveLength(0);
    });

    it('should handle synthesis response format', () => {
      const response = `\`\`\`json
{
  "consensus": [
    {
      "issue": "WCAG contrast validation needed",
      "recommendation": "Run accessibility audit",
      "confidence": 0.9,
      "priority": "high"
    }
  ],
  "resolvedConflicts": [
    {
      "conflictArea": "Naming convention",
      "resolution": "Keep current naming, add aliases",
      "reasoning": "Preserves clarity while enabling semantic usage",
      "confidence": 0.8
    }
  ],
  "finalRecommendations": [
    {
      "action": "Add accessibility metadata",
      "affectedTokens": ["colors.*"],
      "expectedImpact": "Enable automatic WCAG validation",
      "confidence": 0.85,
      "autoApplicable": true
    }
  ],
  "summary": {
    "totalIssues": 1,
    "criticalIssues": 0,
    "confidenceLevel": 0.85,
    "recommendApply": true,
    "reasoning": "High-confidence improvements"
  }
}
\`\`\``;

      const parsed = parseDebateResponse(response);

      expect(parsed.consensus).toHaveLength(1);
      expect(parsed.resolvedConflicts).toHaveLength(1);
      expect(parsed.finalRecommendations).toHaveLength(1);
      expect(parsed.summary).toBeDefined();
      expect(parsed.summary.confidenceLevel).toBe(0.85);
    });

    it('should handle parse errors gracefully', () => {
      const response = 'This is not JSON at all!';

      const parsed = parseDebateResponse(response);

      expect(parsed).toHaveProperty('raw');
      expect(parsed).toHaveProperty('parseError');
      expect(parsed).toHaveProperty('error');
      expect(parsed.raw).toBe(response);
      expect(parsed.parseError).toBe(true);
    });

    it('should handle malformed JSON in code block', () => {
      const response = '```json\n{invalid json}\n```';

      const parsed = parseDebateResponse(response);

      expect(parsed.parseError).toBe(true);
      expect(parsed.error).toBeDefined();
      expect(typeof parsed.error).toBe('string');
      expect(parsed.error.length).toBeGreaterThan(0);
    });

    it('should extract JSON from text with surrounding content', () => {
      const response = `
Here is my analysis:

\`\`\`json
{
  "issues": [],
  "improvements": []
}
\`\`\`

That's all!
`;

      const parsed = parseDebateResponse(response);

      expect(parsed).toEqual({ issues: [], improvements: [] });
    });

    it('should handle empty response', () => {
      const response = '';

      const parsed = parseDebateResponse(response);

      expect(parsed.parseError).toBe(true);
    });

    it('should preserve nested structures', () => {
      const response = `\`\`\`json
{
  "improvements": [
    {
      "category": "accessibility",
      "examples": ["example1", "example2"],
      "metadata": {
        "source": "WCAG",
        "level": "AA"
      }
    }
  ]
}
\`\`\``;

      const parsed = parseDebateResponse(response);

      expect(parsed.improvements[0].metadata.source).toBe('WCAG');
      expect(parsed.improvements[0].metadata.level).toBe('AA');
      expect(parsed.improvements[0].examples).toEqual(['example1', 'example2']);
    });
  });
});
