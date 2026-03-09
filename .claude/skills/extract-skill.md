---
name: skill-extract
description: "Reverse-engineer design systems, tokens, and components from live products or screenshots"
---

# Extract Skill - Implementation Guide

## Overview

The `extract` skill provides comprehensive reverse-engineering capabilities for design systems and product architectures. It transforms undocumented codebases into structured, implementation-ready documentation.

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

## Technical Implementation

### Token Extraction Pipeline

**Priority Order** (High to Low Confidence):
1. **Code-Defined** (95%): `theme.ts`, `tokens.json`, Tailwind config
2. **CSS Variables** (90%): `:root` declarations
3. **Computed Styles** (60%): DOM analysis
4. **Inferred** (40-60%): Color clustering, scale detection

**Color Clustering Algorithm**:
- Uses CIEDE2000 for perceptually-accurate color distance
- K-means++ initialization for stable clustering
- Default k=8 clusters for primary palettes
- ΔE < 2 threshold for duplicate detection

### Component Analysis

**Detection Strategies**:
- AST parsing for TypeScript/JavaScript
- Prop extraction from interfaces and PropTypes
- Variant detection from union types
- Usage tracking across codebase

**Supported Frameworks**:
- React (functional, class, hooks)
- Vue (SFC, Composition API, Options API)
- Svelte (script/template separation)

### Architecture Detection

**Service Boundary Heuristics**:
- Package.json in subdirectories
- Independent deployment configs
- Team ownership boundaries
- Communication pattern analysis

**API Endpoint Detection**:
- Decorator-based routing (NestJS, routing-controllers)
- Express/Fastify route definitions
- GraphQL resolver classes
- tRPC router procedures
- Protocol Buffer (.proto) files

## Multi-AI Orchestration

When enabled, the extract feature uses multiple AI providers for higher accuracy:

**Provider Roles**:
- **Claude**: Synthesis, conflict resolution, documentation
- **Codex**: Code-level analysis, type extraction, architecture
- **Gemini**: Pattern recognition, alternative interpretations, UX insights

**Consensus Mechanism**:
- Threshold: 67% (2/3 providers must agree)
- Disagreements logged in `90_evidence/disagreements.md`
- Confidence scores attached to all outputs

## Output Structure

```
octopus-extract/
└── project-name/
    └── timestamp/
        ├── README.md                   # Navigation and summary
        ├── metadata.json               # Extraction parameters
        │
        ├── 00_intent/
        │   ├── answers.json            # User intent responses
        │   ├── intent-contract.md      # Human-readable summary
        │   └── detection-report.md     # Stack auto-detection results
        │
        ├── 10_design/
        │   ├── tokens.json             # W3C Design Tokens format
        │   ├── tokens.css              # CSS custom properties
        │   ├── tokens.md               # Human-readable token docs
        │   ├── components.csv          # Component inventory (tabular)
        │   ├── components.json         # Structured component data
        │   ├── patterns.md             # Layout and design patterns
        │   └── storybook/              # Storybook scaffold (optional)
        │       ├── .storybook/
        │       └── stories/
        │
        ├── 20_product/
        │   ├── product-overview.md     # What, who, key journeys
        │   ├── feature-inventory.md    # Features by domain
        │   ├── architecture.md         # C4 text description
        │   ├── architecture.mmd        # Mermaid C4 diagrams
        │   ├── PRD.md                  # AI-agent executable PRD
        │   ├── user-stories.md         # Gherkin-style scenarios
        │   ├── api-contracts.md        # Endpoint specifications
        │   ├── data-model.md           # Entity relationships
        │   └── implementation-plan.md  # Phased milestones
        │
        └── 90_evidence/
            ├── quality-report.md       # Coverage and confidence metrics
            ├── disagreements.md        # Multi-AI conflicts
            ├── extraction-log.md       # Timestamped progress log
            └── references.json         # File paths per claim
```

## Quality Gates

Automated validation ensures extraction quality:

1. **Token Coverage**: Fail if 0 tokens in design mode
2. **Component Coverage**: Warn if < 50% of component files detected
3. **Architecture Completeness**: Warn if no services detected in product mode
4. **Multi-AI Consensus**: Fail if < 50% agreement on key outputs

## Usage Patterns

### Basic Extraction
```bash
/octo:extract ./my-app
```

### Design-Only Extraction
```bash
/octo:extract ./my-app --mode design --storybook true
```

### Deep Analysis with Multi-AI
```bash
/octo:extract ./my-app --depth deep --multi-ai force
```

### URL Extraction
```bash
/octo:extract https://example.com --mode design --depth quick
```

## Integration with Other Skills

- **/octo:review**: Review extracted outputs for quality
- **/octo:deliver**: Validate extraction completeness
- **/octo:docs**: Generate additional documentation from extractions

## Error Handling

Common error codes:
- `ERR-001`: Invalid input (path/URL not found)
- `ERR-002`: Network timeout (URL extraction)
- `ERR-003`: Permission denied
- `ERR-004`: Out of memory (use `--depth quick`)
- `VAL-001`: Validation failed (no tokens detected)
- `VAL-004`: Low multi-AI consensus

## Performance Targets

| Depth | Time Target | Coverage Target |
|-------|-------------|-----------------|
| Quick | < 2 min | 70% coverage, basic analysis |
| Standard | 2-5 min | 85% coverage, comprehensive |
| Deep | 5-15 min | 95% coverage, multi-AI validation |

## Research Sources

This skill is informed by research on:
- [Tokens Studio](https://tokens.studio/) - Design token automation
- [Superposition](https://superposition.design/) - Token extraction from websites
- [W3C Design Tokens](https://www.designtokens.org/) - Token format standard
- [C4 Model](https://c4model.com/) - Architecture diagramming
- Modern reverse-engineering practices (2026)

## Implementation Status

**Current Version**: 1.0.0 (Skeleton)

**Implemented**:
- ✅ Command structure
- ✅ CLI argument parsing
- ✅ Output directory setup
- ✅ Metadata generation
- ✅ Multi-AI detection

**In Progress**:
- 🚧 Token extraction pipeline
- 🚧 Component analysis engine
- 🚧 Architecture detection
- 🚧 PRD generation
- 🚧 Quality gates

**Planned**:
- ⏳ Storybook scaffold generation
- ⏳ C4 diagram generation
- ⏳ URL extraction mode
- ⏳ CSS inference algorithms

## Contributing

See implementation plan in project documentation.

Implementation phases:
1. Foundation & CLI (Week 1)
2. Auto-Detection Engine (Week 2)
3. Design Extraction (Week 3-4)
4. Product Extraction (Week 5-6)
5. Multi-AI Orchestration (Week 7)
6. Quality Gates (Week 8)
7. Testing & Documentation (Week 10)

---

*This skill implements the design specified in PRD v2.0 (AI-Executable)*
