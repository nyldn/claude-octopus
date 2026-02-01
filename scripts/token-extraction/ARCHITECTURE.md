# Token Extraction Pipeline - Architecture

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     TOKEN EXTRACTION PIPELINE                    │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         INPUT SOURCES                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │  Tailwind    │  │     CSS      │  │    Theme     │         │
│  │  Config      │  │  Variables   │  │    Files     │         │
│  │ .js/.ts      │  │   :root      │  │  theme.ts    │         │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘         │
│         │                  │                  │                  │
│  ┌──────┴──────────────────┴──────────────────┴───────┐        │
│  │                                                      │        │
│  │  ┌──────────────┐           ┌──────────────┐       │        │
│  │  │    Styled    │           │   Emotion    │       │        │
│  │  │  Components  │           │    Theme     │       │        │
│  │  │    Theme     │           │   Provider   │       │        │
│  │  └──────────────┘           └──────────────┘       │        │
│  │                                                      │        │
│  └──────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────┘

                             ▼

┌─────────────────────────────────────────────────────────────────┐
│                        EXTRACTORS LAYER                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │           TailwindExtractor                              │  │
│  │  • Parse JS/TS config files                              │  │
│  │  • Extract theme & theme.extend                          │  │
│  │  • Map Tailwind categories to token types                │  │
│  │  • Handle malformed configs                              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │          CSSVariablesExtractor                           │  │
│  │  • Scan CSS/SCSS/SASS/LESS files                         │  │
│  │  • Extract :root and custom selectors                    │  │
│  │  • Automatic categorization                              │  │
│  │  • Theme variant support                                 │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │           ThemeFileExtractor                             │  │
│  │  • Find theme.js/ts files                                │  │
│  │  • Handle various export patterns                        │  │
│  │  • Strip TypeScript types                                │  │
│  │  • Extract nested structures                             │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │        StyledComponentsExtractor                         │  │
│  │  • Auto-detect styled-components vs Emotion              │  │
│  │  • Extract ThemeProvider themes                          │  │
│  │  • Map styled-system conventions                         │  │
│  │  • Handle TypeScript generics                            │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

                             ▼

┌─────────────────────────────────────────────────────────────────┐
│                      PROCESSING LAYER                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    Type Inference                        │  │
│  │  • Detect token types from values                        │  │
│  │  • Analyze key names for hints                           │  │
│  │  • Use context awareness                                 │  │
│  │  • Apply smart defaults                                  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                             ▼                                    │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                 Name Normalization                       │  │
│  │  • Convert to kebab-case                                 │  │
│  │  • Handle multiple naming conventions                    │  │
│  │  • Create hierarchical paths                             │  │
│  └──────────────────────────────────────────────────────────┘  │
│                             ▼                                    │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                Priority Application                      │  │
│  │  • Apply source priorities                               │  │
│  │  • Sort tokens by priority                               │  │
│  │  • Prepare for merging                                   │  │
│  └──────────────────────────────────────────────────────────┘  │
│                             ▼                                    │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    Token Merger                          │  │
│  │  • Group tokens by path                                  │  │
│  │  • Detect conflicts                                      │  │
│  │  • Apply resolution strategy                             │  │
│  │  • Track conflict metadata                               │  │
│  └──────────────────────────────────────────────────────────┘  │
│                             ▼                                    │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                   Validation                             │  │
│  │  • Validate token types                                  │  │
│  │  • Check value formats                                   │  │
│  │  • Verify W3C compliance                                 │  │
│  │  • Report validation errors                              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

                             ▼

┌─────────────────────────────────────────────────────────────────┐
│                      OUTPUT GENERATORS                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              JSON Output Generator                       │  │
│  │  • W3C Design Tokens format                              │  │
│  │  • Schema reference inclusion                            │  │
│  │  • Nested token structure                                │  │
│  │  • Metadata extensions                                   │  │
│  │  OUTPUT: tokens.json                                     │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              CSS Output Generator                        │  │
│  │  • CSS custom properties                                 │  │
│  │  • Category grouping                                     │  │
│  │  • Media query support                                   │  │
│  │  • Configurable selectors                                │  │
│  │  OUTPUT: tokens.css                                      │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │            Markdown Output Generator                     │  │
│  │  • Human-readable documentation                          │  │
│  │  • Statistics and summaries                              │  │
│  │  • Token tables by category                              │  │
│  │  • Conflict reporting                                    │  │
│  │  OUTPUT: tokens.md                                       │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

                             ▼

┌─────────────────────────────────────────────────────────────────┐
│                        OUTPUT FILES                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │  tokens.    │  │  tokens.    │  │  tokens.    │            │
│  │   json      │  │    css      │  │     md      │            │
│  │             │  │             │  │             │            │
│  │  W3C Design │  │  CSS Custom │  │  Markdown   │            │
│  │   Tokens    │  │ Properties  │  │    Docs     │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow

```
Project Root
    │
    ├─→ Source Discovery
    │      └─→ Find all token source files
    │
    ├─→ Parallel Extraction
    │      ├─→ Tailwind Extractor → Raw Tokens
    │      ├─→ CSS Extractor → Raw Tokens
    │      ├─→ Theme Extractor → Raw Tokens
    │      └─→ Styled/Emotion Extractor → Raw Tokens
    │
    ├─→ Token Processing
    │      ├─→ Type Inference
    │      ├─→ Name Normalization
    │      └─→ Priority Application
    │
    ├─→ Token Merging
    │      ├─→ Group by Path
    │      ├─→ Detect Conflicts
    │      └─→ Apply Resolution Strategy
    │
    ├─→ Validation
    │      ├─→ Type Validation
    │      ├─→ Format Validation
    │      └─→ W3C Compliance Check
    │
    └─→ Output Generation (Parallel)
           ├─→ JSON Generator → tokens.json
           ├─→ CSS Generator → tokens.css
           └─→ Markdown Generator → tokens.md
```

## Component Dependencies

```
┌─────────────┐
│   cli.ts    │  Command-line interface
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ pipeline.ts │  Main orchestrator
└──────┬──────┘
       │
       ├──────────────────────────────┐
       │                              │
       ▼                              ▼
┌─────────────┐              ┌─────────────┐
│ Extractors  │              │  merger.ts  │
│ Directory   │              │             │
└──────┬──────┘              └──────┬──────┘
       │                            │
       ▼                            ▼
┌─────────────┐              ┌─────────────┐
│  utils.ts   │              │  Outputs    │
│             │◄─────────────┤ Directory   │
└─────────────┘              └─────────────┘
       ▲
       │
┌──────┴──────┐
│  types.ts   │  Core type definitions
└─────────────┘
```

## Conflict Resolution Flow

```
Multiple Tokens with Same Path
        │
        ▼
┌────────────────┐
│  Group by Path │
└───────┬────────┘
        │
        ▼
┌────────────────┐
│ Sort by        │
│ Priority       │
└───────┬────────┘
        │
        ├─────────────────┬─────────────────┐
        ▼                 ▼                 ▼
┌────────────┐   ┌────────────┐   ┌────────────┐
│  Priority  │   │   Merge    │   │   Manual   │
│ Resolution │   │ Resolution │   │ Resolution │
└─────┬──────┘   └─────┬──────┘   └─────┬──────┘
      │                │                │
      └────────┬───────┴────────────────┘
               │
               ▼
      ┌────────────────┐
      │ Resolved Token │
      │ + Conflict Log │
      └────────────────┘
```

## Type System Hierarchy

```
W3CTokensFile
    ├─→ $schema (string)
    ├─→ $description (string)
    └─→ Token Groups (nested)
            ├─→ W3CDesignToken
            │      ├─→ $type (TokenType)
            │      ├─→ $value (any)
            │      ├─→ $description (string)
            │      └─→ $extensions (object)
            └─→ W3CTokenGroup (recursive)

Token (Internal)
    ├─→ name (string)
    ├─→ value (any)
    ├─→ type (TokenType)
    ├─→ category (string)
    ├─→ source (TokenSource)
    ├─→ priority (number)
    ├─→ path (string[])
    ├─→ originalKey (string)
    └─→ metadata (object)

TokenType (enum)
    ├─→ color
    ├─→ dimension
    ├─→ fontFamily
    ├─→ fontWeight
    ├─→ duration
    ├─→ cubicBezier
    ├─→ number
    ├─→ string
    ├─→ shadow
    ├─→ gradient
    ├─→ typography
    ├─→ border
    └─→ transition

TokenSource (enum)
    ├─→ TAILWIND_CONFIG
    ├─→ CSS_VARIABLES
    ├─→ THEME_FILE
    ├─→ STYLED_COMPONENTS
    └─→ EMOTION_THEME
```

## Error Handling Strategy

```
Pipeline Execution
    │
    ├─→ Try Extract from Source
    │      ├─→ Success → Add tokens
    │      └─→ Error → Log & Continue
    │
    ├─→ Try Merge Tokens
    │      ├─→ Success → Merged tokens
    │      └─→ Error → Log & Use individual
    │
    ├─→ Try Validate
    │      ├─→ Valid → Include
    │      └─→ Invalid → Log & Exclude
    │
    └─→ Try Generate Outputs
           ├─→ Success → File created
           └─→ Error → Log & Skip format

ExtractionError Structure
    ├─→ source (TokenSource)
    ├─→ message (string)
    ├─→ error (Error)
    ├─→ filePath (string)
    ├─→ line (number)
    └─→ column (number)
```

## Performance Optimization

```
┌──────────────────────────────────────┐
│     Parallel Execution Points        │
├──────────────────────────────────────┤
│                                      │
│  1. Source Extraction                │
│     All extractors run in parallel   │
│                                      │
│  2. Output Generation                │
│     JSON, CSS, MD generated together │
│                                      │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│       Lazy Evaluation                │
├──────────────────────────────────────┤
│                                      │
│  • Only load needed extractors       │
│  • Skip excluded sources             │
│  • Generate only requested outputs   │
│                                      │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│      Memory Efficiency               │
├──────────────────────────────────────┤
│                                      │
│  • Stream large files                │
│  • Incremental processing            │
│  • No unnecessary caching            │
│  • Efficient data structures         │
│                                      │
└──────────────────────────────────────┘
```

## Extension Points

```
Custom Extractor Interface
    ↓
┌────────────────────────────────────┐
│  class CustomExtractor             │
│  {                                 │
│    async extract(projectRoot):     │
│      Promise<{                     │
│        tokens: Token[];            │
│        errors: ExtractionError[];  │
│      }>                            │
│  }                                 │
└────────────────────────────────────┘

Custom Merge Strategy Interface
    ↓
┌────────────────────────────────────┐
│  interface MergeStrategy           │
│  {                                 │
│    shouldMerge(existing, incoming):│
│      boolean;                      │
│                                    │
│    onConflict(existing, incoming): │
│      Token;                        │
│  }                                 │
└────────────────────────────────────┘

Custom Output Generator Interface
    ↓
┌────────────────────────────────────┐
│  class CustomOutputGenerator       │
│  {                                 │
│    async generate(tokens: Token[]):│
│      Promise<void>                 │
│  }                                 │
└────────────────────────────────────┘
```

## Security Considerations

```
Input Validation
    │
    ├─→ Config File Parsing
    │      └─→ Use Function constructor (safer than eval)
    │
    ├─→ File Path Validation
    │      └─→ Sanitize paths, prevent traversal
    │
    ├─→ Token Value Validation
    │      └─→ Type-check and format validation
    │
    └─→ Output Path Validation
           └─→ Ensure within project bounds
```

## Testing Architecture

```
Unit Tests
    │
    ├─→ Type Inference Tests
    ├─→ Name Normalization Tests
    ├─→ Token Validation Tests
    └─→ Conflict Detection Tests

Integration Tests
    │
    ├─→ End-to-end Extraction
    ├─→ Multi-source Merging
    ├─→ Output Generation
    └─→ Error Handling

Test Fixtures
    │
    ├─→ tailwind.config.example.js
    ├─→ styles.example.css
    ├─→ theme.example.ts
    └─→ styled-components.example.tsx
```

## Deployment Architecture

```
Development
    └─→ ts-node execution
            └─→ Direct TypeScript execution

Production
    └─→ Compiled JavaScript
            ├─→ NPM Package
            ├─→ CLI Tool
            └─→ Library Import

CI/CD Integration
    └─→ GitHub Actions / GitLab CI
            └─→ Automated token extraction
                    └─→ Commit to repository
```

This architecture provides a scalable, maintainable, and extensible foundation for design token extraction across multiple source types and output formats.
