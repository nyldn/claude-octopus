# Token Extraction Pipeline - Complete File Listing

## Project Statistics

- **Total Files**: 25
- **Total Lines of Code**: ~5,000
- **TypeScript/JavaScript Files**: 19 (~4,300 lines)
- **Documentation Files**: 6 (~2,400 lines)
- **Test Fixtures**: 4 (~570 lines)

## File Structure

```
token-extraction/
├── Core Implementation (9 files, ~2,200 lines)
│   ├── types.ts                     168 lines
│   ├── utils.ts                     347 lines
│   ├── merger.ts                    338 lines
│   ├── pipeline.ts                  394 lines
│   ├── cli.ts                       204 lines
│   ├── index.ts                      33 lines
│   └── package.json                  39 lines
│
├── Extractors (4 files, ~970 lines)
│   ├── extractors/tailwind.ts       255 lines
│   ├── extractors/css-variables.ts  206 lines
│   ├── extractors/theme-file.ts     228 lines
│   └── extractors/styled-components.ts  285 lines
│
├── Output Generators (3 files, ~665 lines)
│   ├── outputs/json.ts               99 lines
│   ├── outputs/css.ts               196 lines
│   └── outputs/markdown.ts          370 lines
│
├── Examples (2 files, ~607 lines)
│   ├── examples/basic-usage.ts      240 lines
│   └── examples/advanced-usage.ts   367 lines
│
├── Test Fixtures (4 files, ~570 lines)
│   ├── test-fixtures/tailwind.config.example.js    102 lines
│   ├── test-fixtures/styles.example.css             78 lines
│   ├── test-fixtures/theme.example.ts              194 lines
│   └── test-fixtures/styled-components.example.tsx 100 lines
│
└── Documentation (6 files, ~2,462 lines)
    ├── README.md                    531 lines
    ├── IMPLEMENTATION.md            562 lines
    ├── ARCHITECTURE.md              485 lines
    ├── SUMMARY.md                   510 lines
    ├── QUICK_START.md               374 lines
    └── FILES.md                     (this file)
```

## Detailed File Descriptions

### Core Implementation

#### types.ts (168 lines)
**Purpose**: TypeScript type definitions for the entire pipeline

**Key Types**:
- `Token`: Internal token representation
- `W3CDesignToken`: W3C format compliance
- `TokenSource`: Enum of supported sources
- `ExtractionResult`: Pipeline output structure
- `TokenConflict`: Conflict detection data
- `ExtractionOptions`: Configuration interface

**Dependencies**: None (pure types)

---

#### utils.ts (347 lines)
**Purpose**: Utility functions for token processing

**Key Functions**:
- `inferTokenType()`: Detect token type from value/key
- `normalizeTokenName()`: Convert to kebab-case
- `createTokenPath()`: Build hierarchical paths
- `toW3CToken()`: Transform to W3C format
- `flattenObject()`: Nested to flat conversion
- `unflattenTokens()`: Flat to nested conversion
- `validateToken()`: Type-specific validation
- `toCSSVariableName()`: Generate CSS var names
- `formatCSSValue()`: Format values for CSS

**Dependencies**: `types.ts`

---

#### merger.ts (338 lines)
**Purpose**: Token merging and conflict resolution

**Key Classes**:
- `TokenMerger`: Main merger implementation

**Key Methods**:
- `merge()`: Merge tokens from multiple sources
- `resolveConflict()`: Apply resolution strategy
- `applyCustomStrategy()`: Use custom merge logic
- `validateTokens()`: Validate merged tokens
- `getConflicts()`: Retrieve conflict list
- `getConflictStats()`: Conflict statistics

**Dependencies**: `types.ts`, `utils.ts`

---

#### pipeline.ts (394 lines)
**Purpose**: Main orchestration pipeline

**Key Classes**:
- `TokenExtractionPipeline`: Orchestrator

**Key Methods**:
- `execute()`: Run full extraction pipeline
- `extractFromAllSources()`: Call all extractors
- `mergeTokens()`: Merge and resolve conflicts
- `validateTokens()`: Validate all tokens
- `generateOutputs()`: Create output files
- `printSummary()`: Display results

**Flow**:
1. Source discovery
2. Parallel extraction
3. Priority application
4. Token merging
5. Validation
6. Output generation
7. Reporting

**Dependencies**: All extractors, merger, outputs, utils, types

---

#### cli.ts (204 lines)
**Purpose**: Command-line interface

**Key Functions**:
- `parseArgs()`: Parse CLI arguments
- `printHelp()`: Display help message
- `printVersion()`: Show version
- `main()`: CLI entry point

**Supported Arguments**:
- `-h, --help`
- `-v, --version`
- `-p, --project <path>`
- `-o, --output <path>`
- `-f, --formats <formats>`
- `-c, --conflict-resolution <strategy>`
- `--include-sources <sources>`
- `--exclude-sources <sources>`
- `--no-validate`
- `--preserve-keys`

**Dependencies**: `pipeline.ts`, `types.ts`

---

#### index.ts (33 lines)
**Purpose**: Public API exports

**Exports**:
- Core pipeline
- All extractors
- Merger and utilities
- Output generators
- Types
- CLI functions

**Dependencies**: All modules

---

#### package.json (39 lines)
**Purpose**: Package configuration

**Key Fields**:
- Name: `@claude-octopus/token-extraction`
- Version: 1.0.0
- Main: `index.ts`
- Bin: `cli.ts`
- Scripts: extract, examples
- Dependencies: glob

---

### Extractors

#### extractors/tailwind.ts (255 lines)
**Purpose**: Extract tokens from Tailwind configuration

**Key Classes**:
- `TailwindExtractor`

**Features**:
- Supports `.js`, `.ts`, `.cjs`, `.mjs` files
- Parses `theme.extend` and core theme
- Handles JavaScript/TypeScript syntax
- Maps Tailwind categories to token types
- Error handling for malformed configs

**Token Mapping**:
- colors → color
- spacing → dimension
- fontSize → typography
- fontFamily → typography
- fontWeight → typography
- borderRadius → border
- boxShadow → shadow
- screens → breakpoint

**Dependencies**: `types.ts`, `utils.ts`, fs, path

---

#### extractors/css-variables.ts (206 lines)
**Purpose**: Extract CSS custom properties

**Key Classes**:
- `CSSVariablesExtractor`

**Features**:
- Scans `.css`, `.scss`, `.sass`, `.less` files
- Configurable selectors (`:root`, `[data-theme]`, etc.)
- Automatic categorization by name
- Glob pattern support
- Comment removal

**Selector Support**:
- `:root` (global variables)
- `[data-theme="..."]` (theme variants)
- Custom selectors

**Dependencies**: `types.ts`, `utils.ts`, fs, path, glob

---

#### extractors/theme-file.ts (228 lines)
**Purpose**: Extract tokens from theme.js/ts files

**Key Classes**:
- `ThemeFileExtractor`

**Features**:
- Finds theme files via glob patterns
- Handles various export patterns
- TypeScript type stripping
- Nested structure extraction

**Supported Patterns**:
- `export default { ... }`
- `export const theme = { ... }`
- `module.exports = { ... }`
- `const theme = { ... }`

**Dependencies**: `types.ts`, `utils.ts`, fs, path, glob

---

#### extractors/styled-components.ts (285 lines)
**Purpose**: Extract styled-components/Emotion themes

**Key Classes**:
- `StyledComponentsExtractor`

**Features**:
- Auto-detects styled-components vs Emotion
- Finds theme in ThemeProvider usage
- Maps styled-system conventions
- TypeScript generic handling

**Category Mapping**:
- colors → color
- space/spacing → spacing
- fonts/fontSizes/fontWeights → typography
- radii → border
- shadows → shadow
- zIndices → z-index

**Dependencies**: `types.ts`, `utils.ts`, fs, path, glob

---

### Output Generators

#### outputs/json.ts (99 lines)
**Purpose**: Generate W3C Design Tokens JSON

**Key Classes**:
- `JSONOutputGenerator`

**Features**:
- Full W3C specification compliance
- Schema reference inclusion
- Pretty printing support
- Nested token structure
- Metadata extensions

**Output Format**:
```json
{
  "$schema": "https://tr.designtokens.org/format/",
  "colors": {
    "primary": {
      "$type": "color",
      "$value": "#3b82f6"
    }
  }
}
```

**Dependencies**: `types.ts`, `utils.ts`, fs, path

---

#### outputs/css.ts (196 lines)
**Purpose**: Generate CSS custom properties

**Key Classes**:
- `CSSOutputGenerator`

**Features**:
- CSS variable generation
- Category grouping with comments
- Media query support
- Configurable selectors
- Human-readable formatting

**Output Format**:
```css
/* Colors */
:root {
  --colors-primary: #3b82f6;
  --spacing-4: 1rem;
}
```

**Dependencies**: `types.ts`, `utils.ts`, fs, path

---

#### outputs/markdown.ts (370 lines)
**Purpose**: Generate documentation

**Key Classes**:
- `MarkdownOutputGenerator`

**Features**:
- Comprehensive token tables
- Statistics and summaries
- Category organization
- Conflict reporting
- CSS variable references

**Sections**:
- Statistics
- Table of contents
- Token tables by category
- Conflict details

**Dependencies**: `types.ts`, `utils.ts`, fs, path

---

### Examples

#### examples/basic-usage.ts (240 lines)
**Purpose**: Demonstrate common use cases

**10 Examples**:
1. Basic extraction
2. Extract from specific sources
3. Custom output formats
4. Manual conflict resolution
5. Custom priorities
6. Direct pipeline usage
7. Error handling
8. Extract and transform
9. Exclude sources
10. Skip validation

**Dependencies**: `../index.ts` (all exports)

---

#### examples/advanced-usage.ts (367 lines)
**Purpose**: Demonstrate advanced features

**10 Examples**:
1. Individual extractors
2. Custom merge strategy
3. Token filtering
4. Multi-theme support
5. Token categorization
6. Token validation
7. Incremental extraction
8. Token aliasing
9. Platform-specific export
10. Conflict analysis

**Dependencies**: `../index.ts` (all exports)

---

### Test Fixtures

#### test-fixtures/tailwind.config.example.js (102 lines)
**Purpose**: Example Tailwind configuration

**Contents**:
- Complete theme.extend configuration
- Colors (primary, secondary, status)
- Spacing (custom sizes)
- Typography (fonts, sizes, weights)
- Shadows, radii, z-index
- Transitions and animations

**Use**: Testing Tailwind extractor, reference example

---

#### test-fixtures/styles.example.css (78 lines)
**Purpose**: Example CSS with custom properties

**Contents**:
- :root variables
- Colors, spacing, typography
- Borders, shadows, z-index
- Transitions
- Theme variants (dark, high-contrast)

**Use**: Testing CSS extractor, reference example

---

#### test-fixtures/theme.example.ts (194 lines)
**Purpose**: Example TypeScript theme file

**Contents**:
- Comprehensive theme object
- Colors, spacing, typography
- Breakpoints, shadows, radii
- Z-index, transitions, opacity
- TypeScript type exports

**Use**: Testing theme file extractor, reference example

---

#### test-fixtures/styled-components.example.tsx (100 lines)
**Purpose**: Example styled-components theme

**Contents**:
- Styled-components theme object
- Colors, space arrays
- Fonts, font sizes, weights
- Radii, shadows, z-indices
- Transitions, breakpoints
- ThemeProvider usage

**Use**: Testing styled-components extractor, reference example

---

### Documentation

#### README.md (531 lines)
**Purpose**: Complete user documentation

**Sections**:
- Features overview
- Installation instructions
- Quick start guide
- Architecture overview
- Configuration options
- API reference
- Error handling guide
- Advanced usage patterns
- Testing guidelines
- Troubleshooting
- Contributing guidelines
- Resources and links

**Audience**: End users, developers integrating the pipeline

---

#### IMPLEMENTATION.md (562 lines)
**Purpose**: Technical implementation details

**Sections**:
- Project structure
- Core component descriptions
- Implementation details
- Type inference algorithms
- Conflict detection logic
- Error handling strategy
- Performance considerations
- Configuration best practices
- Extension points
- Testing strategy
- Deployment options
- Future enhancements

**Audience**: Contributors, maintainers, technical reviewers

---

#### ARCHITECTURE.md (485 lines)
**Purpose**: System architecture documentation

**Sections**:
- System architecture diagrams
- Data flow visualization
- Component dependencies
- Conflict resolution flow
- Type system hierarchy
- Error handling strategy
- Performance optimization
- Extension points
- Security considerations
- Testing architecture
- Deployment architecture

**Audience**: Architects, senior developers, technical leads

---

#### SUMMARY.md (510 lines)
**Purpose**: High-level project overview

**Sections**:
- Project overview
- Delivered components
- Key features
- Usage examples
- Architecture highlights
- Code statistics
- Testing coverage
- Integration points
- Performance characteristics
- Future enhancements
- Dependencies
- Quick start guide

**Audience**: Project managers, stakeholders, quick reference

---

#### QUICK_START.md (374 lines)
**Purpose**: Fast getting-started guide

**Sections**:
- Installation steps
- Immediate usage
- Common use cases
- Example outputs
- CLI options reference
- Priority system
- Error handling
- Integration examples
- Troubleshooting
- Quick reference card

**Audience**: New users, quick reference

---

#### FILES.md (this file)
**Purpose**: Complete file listing and descriptions

**Sections**:
- Project statistics
- File structure tree
- Detailed file descriptions
- Dependencies for each file
- Purpose and key features
- Line counts and metrics

**Audience**: All stakeholders, documentation reference

---

## Dependency Graph

```
types.ts (base types)
    ↓
utils.ts (uses types)
    ↓
extractors/*.ts (use utils + types)
    ↓
merger.ts (uses utils + types)
    ↓
outputs/*.ts (use utils + types)
    ↓
pipeline.ts (uses all above)
    ↓
cli.ts (uses pipeline)
    ↓
index.ts (exports all)
```

## External Dependencies

```json
{
  "runtime": {
    "glob": "^10.3.10"
  },
  "development": {
    "@types/node": "^20.10.0",
    "ts-node": "^10.9.2",
    "typescript": "^5.3.3"
  }
}
```

## File Categories by Purpose

### Execution Flow Files
- `cli.ts` - Entry point (CLI)
- `index.ts` - Entry point (API)
- `pipeline.ts` - Orchestration

### Data Processing Files
- `extractors/*.ts` - Source parsing
- `merger.ts` - Token combination
- `outputs/*.ts` - File generation

### Support Files
- `types.ts` - Type system
- `utils.ts` - Helper functions
- `package.json` - Configuration

### Documentation Files
- `README.md` - User guide
- `IMPLEMENTATION.md` - Technical docs
- `ARCHITECTURE.md` - System design
- `SUMMARY.md` - Overview
- `QUICK_START.md` - Getting started
- `FILES.md` - This file

### Example Files
- `examples/basic-usage.ts` - Common patterns
- `examples/advanced-usage.ts` - Advanced patterns

### Test Files
- `test-fixtures/*.{js,ts,css,tsx}` - Sample configs

## Metrics Summary

### Code Distribution
- **Core Logic**: 40% (2,200 lines)
- **Extractors**: 19% (970 lines)
- **Outputs**: 13% (665 lines)
- **Examples**: 12% (607 lines)
- **Tests**: 11% (570 lines)
- **Docs**: 48% (2,462 lines)

### File Count by Type
- TypeScript: 15 files
- JavaScript: 1 file
- TypeScript React: 1 file
- CSS: 1 file
- JSON: 1 file
- Markdown: 6 files

### Lines by Category
- Implementation: 4,442 lines (88%)
- Documentation: 2,462 lines (48%)
- Tests: 570 lines (11%)

Total unique content: ~5,000 lines

## Quick File Access

**Need to...**
- Understand types? → `types.ts`
- See utilities? → `utils.ts`
- Check extraction? → `extractors/`
- View merging? → `merger.ts`
- Output formats? → `outputs/`
- Pipeline flow? → `pipeline.ts`
- CLI usage? → `cli.ts`
- Get started? → `QUICK_START.md`
- Deep dive? → `IMPLEMENTATION.md`
- Architecture? → `ARCHITECTURE.md`
- Overview? → `SUMMARY.md`
- Examples? → `examples/`

## File Locations

All files located at:
```
/Users/chris/git/claude-octopus/plugin/scripts/token-extraction/
```

Ready for immediate use, testing, or integration.
