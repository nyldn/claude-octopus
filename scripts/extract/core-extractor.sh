#!/usr/bin/env bash
# Core extraction orchestrator for /octo:extract command
# Implements PRD v2.0 - Design System & Product Reverse-Engineering

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=../lib/common.sh
source "${PLUGIN_ROOT}/scripts/lib/common.sh" 2>/dev/null || true

# Configuration
EXTRACTION_VERSION="1.0.0"
DEFAULT_OUTPUT_DIR="./octopus-extract"
CONSENSUS_THRESHOLD=0.67

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
  echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
  echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
  echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
  echo -e "${RED}✗${NC} $*" >&2
}

# Usage information
usage() {
  cat <<EOF
Usage: extract.sh <target> [options]

Extract design tokens, components, architecture, and PRDs from codebases or URLs.

Arguments:
  target                  URL or local directory path

Options:
  --mode MODE            Extraction mode: design|product|both|auto (default: auto)
  --depth DEPTH          Analysis depth: quick|standard|deep (default: standard)
  --output DIR           Output directory (default: ./octopus-extract)
  --storybook BOOL       Generate Storybook scaffold: true|false (default: true)
  --multi-ai MODE        Multi-AI mode: auto|force|false (default: auto)
  --with-debate          Enable multi-AI debate for token validation
  --debate-rounds NUM    Number of debate rounds (default: 2)
  --ignore PATTERNS      Comma-separated glob patterns to ignore
  --help                 Show this help message

Examples:
  extract.sh ./my-app
  extract.sh https://example.com --mode design --depth deep
  extract.sh ./my-app --output ./results --multi-ai force
  extract.sh ./my-app --with-debate --debate-rounds 2

EOF
}

# Parse command-line arguments
parse_args() {
  TARGET=""
  MODE="auto"
  DEPTH="standard"
  OUTPUT_DIR="${DEFAULT_OUTPUT_DIR}"
  STORYBOOK="true"
  MULTI_AI="auto"
  IGNORE_PATTERNS=""
  WITH_DEBATE="false"
  DEBATE_ROUNDS="2"

  while [[ $# -gt 0 ]]; do
    case $1 in
      --mode)
        MODE="$2"
        shift 2
        ;;
      --depth)
        DEPTH="$2"
        shift 2
        ;;
      --output)
        OUTPUT_DIR="$2"
        shift 2
        ;;
      --storybook)
        STORYBOOK="$2"
        shift 2
        ;;
      --multi-ai)
        MULTI_AI="$2"
        shift 2
        ;;
      --ignore)
        IGNORE_PATTERNS="$2"
        shift 2
        ;;
      --with-debate)
        WITH_DEBATE="true"
        shift
        ;;
      --debate-rounds)
        DEBATE_ROUNDS="$2"
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      -*)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
      *)
        if [[ -z "${TARGET}" ]]; then
          TARGET="$1"
        else
          log_error "Multiple targets specified. Only one target is allowed."
          exit 1
        fi
        shift
        ;;
    esac
  done

  if [[ -z "${TARGET}" ]]; then
    log_error "Target is required"
    usage
    exit 1
  fi
}

# Check if multi-AI providers are available
check_multi_ai_availability() {
  local codex_available=false
  local gemini_available=false

  if command -v codex &> /dev/null; then
    codex_available=true
  fi

  if command -v gemini &> /dev/null; then
    gemini_available=true
  fi

  if [[ "${codex_available}" == "true" ]] && [[ "${gemini_available}" == "true" ]]; then
    echo "both"
  elif [[ "${codex_available}" == "true" ]] || [[ "${gemini_available}" == "true" ]]; then
    echo "partial"
  else
    echo "none"
  fi
}

# Validate target
validate_target() {
  local target="$1"

  if [[ "${target}" =~ ^https?:// ]]; then
    # URL target
    log_info "Target is a URL: ${target}"
    if ! curl --output /dev/null --silent --head --fail "${target}"; then
      log_error "URL is not accessible: ${target}"
      return 1
    fi
    echo "url"
  elif [[ -d "${target}" ]]; then
    # Directory target
    log_info "Target is a directory: ${target}"
    if [[ ! -r "${target}" ]]; then
      log_error "Directory is not readable: ${target}"
      return 1
    fi
    echo "directory"
  elif [[ -f "${target}" ]]; then
    log_error "Target is a file. Please provide a directory or URL."
    return 1
  else
    log_error "Target does not exist: ${target}"
    return 1
  fi
}

# Setup output directory structure
setup_output_directory() {
  local output_dir="$1"
  local project_name="$2"
  local timestamp
  timestamp=$(date +"%Y%m%d_%H%M%S")

  local extraction_dir="${output_dir}/${project_name}/${timestamp}"

  mkdir -p "${extraction_dir}"/{00_intent,10_design,20_product,90_evidence}
  mkdir -p "${extraction_dir}/10_design/storybook"

  echo "${extraction_dir}"
}

# Generate extraction metadata
generate_metadata() {
  local extraction_dir="$1"
  local target="$2"
  local target_type="$3"
  local mode="$4"
  local depth="$5"
  local multi_ai_mode="$6"

  cat > "${extraction_dir}/metadata.json" <<EOF
{
  "version": "${EXTRACTION_VERSION}",
  "extraction": {
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "target": "${target}",
    "targetType": "${target_type}",
    "mode": "${mode}",
    "depth": "${depth}"
  },
  "providers": {
    "multiAI": "${multi_ai_mode}",
    "consensusThreshold": ${CONSENSUS_THRESHOLD}
  }
}
EOF

  log_success "Generated metadata.json"
}

# Main extraction logic
main() {
  parse_args "$@"

  echo ""
  log_info "🐙 Claude Octopus - /octo:extract v${EXTRACTION_VERSION}"
  echo ""

  # Validate target
  local target_type
  target_type=$(validate_target "${TARGET}") || exit 1

  # Check multi-AI availability
  local multi_ai_availability
  multi_ai_availability=$(check_multi_ai_availability)

  if [[ "${MULTI_AI}" == "auto" ]]; then
    if [[ "${multi_ai_availability}" == "none" ]]; then
      log_warning "Multi-AI providers not detected. Running in single-provider mode."
      log_warning "For best results, run '/octo:setup' to configure Codex and Gemini."
      MULTI_AI="false"
    else
      MULTI_AI="true"
    fi
  elif [[ "${MULTI_AI}" == "force" ]]; then
    if [[ "${multi_ai_availability}" == "none" ]]; then
      log_error "Cannot force multi-AI mode: No providers available."
      exit 1
    fi
    MULTI_AI="true"
  fi

  # Extract project name from target
  local project_name
  if [[ "${target_type}" == "url" ]]; then
    project_name=$(echo "${TARGET}" | sed -e 's|https\?://||' -e 's|/||g' | tr '.' '-')
  else
    project_name=$(basename "${TARGET}")
  fi

  # Setup output directory
  local extraction_dir
  extraction_dir=$(setup_output_directory "${OUTPUT_DIR}" "${project_name}")
  log_success "Created output directory: ${extraction_dir}"

  # Generate metadata
  generate_metadata "${extraction_dir}" "${TARGET}" "${target_type}" "${MODE}" "${DEPTH}" "${MULTI_AI}"

  # Log extraction start
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") - Extraction started" > "${extraction_dir}/90_evidence/extraction-log.md"

  echo ""
  log_info "📋 Extraction Configuration"
  log_info "  Target: ${TARGET}"
  log_info "  Type: ${target_type}"
  log_info "  Mode: ${MODE}"
  log_info "  Depth: ${DEPTH}"
  log_info "  Multi-AI: ${MULTI_AI}"
  log_info "  Debate: ${WITH_DEBATE}"
  if [[ "${WITH_DEBATE}" == "true" ]]; then
    log_info "  Debate Rounds: ${DEBATE_ROUNDS}"
  fi
  log_info "  Output: ${extraction_dir}"
  echo ""

  # Run token extraction pipeline
  log_info "🚀 Starting token extraction pipeline..."
  echo ""

  # Build CLI arguments
  local cli_args=(
    "--project" "${TARGET}"
    "--output" "${extraction_dir}/10_design"
    "--formats" "json,css,markdown,typescript,tailwind,styled-components,style-dictionary,schema"
  )

  # Add debate flags if enabled
  if [[ "${WITH_DEBATE}" == "true" ]]; then
    cli_args+=("--with-debate")
    cli_args+=("--debate-rounds" "${DEBATE_ROUNDS}")
  fi

  # Execute TypeScript CLI
  cd "${PLUGIN_ROOT}/scripts/token-extraction" || exit 1

  if npx tsx cli.ts "${cli_args[@]}"; then
    log_success "✅ Token extraction completed successfully"
  else
    log_error "❌ Token extraction failed"
    exit 1
  fi

  echo ""

  echo ""
  log_success "✅ Extraction setup complete!"
  log_info "📁 Results will be saved to: ${extraction_dir}"
  echo ""
}

# Run main function
main "$@"
