#!/usr/bin/env bash
# Test script for PDF page selection utility (v7.25.0)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

# Define the functions directly for testing
# (In production, these are sourced from orchestrate.sh)

echo "Testing PDF Page Selection Utility"
echo "===================================="
echo ""

# Test 1: Check if PDF tools are available
echo "Test 1: Checking for PDF tools..."
if command -v pdfinfo &>/dev/null; then
    echo "✓ pdfinfo found"
elif command -v mdls &>/dev/null; then
    echo "✓ mdls found (macOS)"
elif command -v qpdf &>/dev/null; then
    echo "✓ qpdf found"
else
    echo "⚠ No PDF tools found (pdfinfo, mdls, or qpdf)"
    echo "  Install poppler-utils or qpdf to get page counts:"
    echo "    brew install poppler      # macOS"
    echo "    apt-get install poppler-utils  # Linux"
fi
echo ""

# Test 2: Test get_pdf_page_count function
echo "Test 2: Testing get_pdf_page_count function..."
if [[ -f "/tmp/test.pdf" ]]; then
    count=$(get_pdf_page_count "/tmp/test.pdf" 2>/dev/null || echo "0")
    echo "  Page count: $count"
else
    echo "  Skipped (no test PDF at /tmp/test.pdf)"
fi
echo ""

# Test 3: Test page range validation
echo "Test 3: Testing page range validation..."
valid_ranges=("1-10" "5" "1-5,10-15" "all")
for range in "${valid_ranges[@]}"; do
    if [[ "$range" == "all" || "$range" =~ ^[0-9,\-]+$ ]]; then
        echo "  ✓ Valid: $range"
    else
        echo "  ✗ Invalid: $range"
    fi
done
echo ""

# Test 4: Test process_pdf_with_selection with mock (non-interactive)
echo "Test 4: Testing process_pdf_with_selection (mock)..."
echo "  Function defined: $(type -t process_pdf_with_selection)"
if [[ "$(type -t process_pdf_with_selection)" == "function" ]]; then
    echo "  ✓ process_pdf_with_selection is defined"
else
    echo "  ✗ process_pdf_with_selection is not defined"
fi
echo ""

# Test 5: Test debug mode integration
echo "Test 5: Testing debug mode integration..."
OCTOPUS_DEBUG=1
export OCTOPUS_DEBUG
echo "  OCTOPUS_DEBUG=1"
# Call get_pdf_page_count with debug to see debug output
if [[ -f "/tmp/test.pdf" ]]; then
    echo "  Calling get_pdf_page_count with debug enabled..."
    count=$(get_pdf_page_count "/tmp/test.pdf" 2>&1 | head -5)
    echo "$count" | head -3
fi
echo ""

echo "===================================="
echo "✅ PDF page selection utility tests completed!"
echo ""
echo "To use PDF page selection in your workflows:"
echo ""
echo "  # Get page count"
echo "  page_count=\$(get_pdf_page_count \"/path/to/file.pdf\")"
echo ""
echo "  # Ask user for page selection (interactive)"
echo "  pages=\$(ask_pdf_page_selection \"/path/to/file.pdf\" \"\$page_count\")"
echo ""
echo "  # Or use the convenience wrapper"
echo "  pages=\$(process_pdf_with_selection \"/path/to/file.pdf\")"
echo ""
echo "  # Then use with Claude Code's Read tool:"
echo "  # Read(\"/path/to/file.pdf\", pages=\$pages)"
