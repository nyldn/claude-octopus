---
name: skill-extract
version: 1.0.0
description: "Reverse-engineer design systems, tokens, components, and product architectures from codebases or URLs into structured documentation. Use when: user says 'extract design tokens', 'reverse-engineer this app', 'extract components', 'analyze this codebase structure', or runs /octo:extract."
---

# Extract Skill

Transforms undocumented codebases into structured, implementation-ready documentation by extracting design tokens, components, APIs, and architecture.

## Capabilities

### Design System Extraction
- **Token Extraction**: Colors, typography, spacing, shadows from code or CSS
- **Component Analysis**: Props, variants, usage patterns across React/Vue/Svelte
- **Pattern Detection**: Layout patterns, design rules, accessibility guidelines
- **Storybook Generation**: Auto-generated stories with variants and controls

### Product Architecture Extraction
- **Service Detection**: Microservice boundaries, modules, domain boundaries
- **API Mapping**: REST, GraphQL, tRPC, gRPC endpoint cataloging
- **Data Modeling**: ORM schema extraction (Prisma, TypeORM, Sequelize)
- **Feature Inventory**: Route-based and domain-based feature detection
- **C4 Diagrams**: Automated architecture visualization (Mermaid)

## Token Extraction Pipeline

**Priority Order** (High to Low Confidence):
1. **Code-Defined** (95%): `theme.ts`, `tokens.json`, Tailwind config
2. **CSS Variables** (90%): `:root` declarations
3. **Computed Styles** (60%): DOM analysis
4. **Inferred** (40-60%): Color clustering (CIEDE2000, K-means++, k=8 default)

## Multi-AI Orchestration

- **Claude**: Synthesis, conflict resolution, documentation
- **Codex**: Code-level analysis, type extraction, architecture
- **Gemini**: Pattern recognition, alternative interpretations, UX insights
- Consensus threshold: 67% (2/3 must agree)

## Output Structure

```
octopus-extract/
└── project-name/
    └── timestamp/
        ├── README.md
        ├── metadata.json
        ├── 00_intent/          # User intent, stack detection
        ├── 10_design/          # Tokens (W3C), components, patterns, storybook
        ├── 20_product/         # Overview, features, architecture, PRD, APIs
        └── 90_evidence/        # Quality report, disagreements, logs
```

## Quality Gates

1. **Token Coverage**: Fail if 0 tokens in design mode
2. **Component Coverage**: Warn if < 50% detected
3. **Architecture Completeness**: Warn if no services detected
4. **Multi-AI Consensus**: Fail if < 50% agreement

## Usage

```bash
/octo:extract ./my-app                                    # Basic extraction
/octo:extract ./my-app --mode design --storybook true     # Design-only
/octo:extract ./my-app --depth deep --multi-ai force      # Deep multi-AI
/octo:extract https://example.com --mode design --depth quick  # URL extraction
```

## Performance Targets

| Depth | Time Target | Coverage Target |
|-------|-------------|-----------------|
| Quick | < 2 min | 70% coverage |
| Standard | 2-5 min | 85% coverage |
| Deep | 5-15 min | 95% coverage, multi-AI validation |

## Integration

- **/octo:review**: Review extracted outputs for quality
- **/octo:deliver**: Validate extraction completeness
- **/octo:docs**: Generate additional documentation from extractions
