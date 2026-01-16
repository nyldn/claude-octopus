.PHONY: test test-smoke test-unit test-integration test-e2e test-coverage test-all clean-tests help

# Default: smoke + unit (fast feedback)
test: test-smoke test-unit

# Run all tests
test-all: test-smoke test-unit test-integration test-e2e

# Smoke tests (pre-commit, <30s)
test-smoke:
	@echo "Running smoke tests..."
	@./tests/run-all.sh smoke

# Unit tests (1-2min)
test-unit:
	@echo "Running unit tests..."
	@./tests/run-all.sh unit

# Integration tests (5-10min)
test-integration:
	@echo "Running integration tests..."
	@./tests/run-all.sh integration

# E2E tests (15-30min)
test-e2e:
	@echo "Running E2E tests..."
	@./tests/run-all.sh e2e

# Performance tests
test-performance:
	@echo "Running performance tests..."
	@./tests/run-all.sh performance

# Regression tests
test-regression:
	@echo "Running regression tests..."
	@./tests/run-all.sh regression

# Coverage report
test-coverage:
	@echo "Generating coverage report..."
	@./tests/helpers/generate-coverage-report.sh

# Verbose mode for debugging
test-verbose:
	@VERBOSE=true ./tests/run-all.sh all

# Clean test artifacts
clean-tests:
	@echo "Cleaning test artifacts..."
	@rm -rf tests/tmp/
	@rm -f test-results*.xml
	@rm -f coverage*.xml
	@rm -f /tmp/test_*.log
	@echo "Test artifacts cleaned"

# Help
help:
	@echo "Claude Octopus Test Suite"
	@echo ""
	@echo "Usage:"
	@echo "  make test              - Run smoke + unit tests (default)"
	@echo "  make test-all          - Run all test categories"
	@echo "  make test-smoke        - Run smoke tests (<30s)"
	@echo "  make test-unit         - Run unit tests (1-2min)"
	@echo "  make test-integration  - Run integration tests (5-10min)"
	@echo "  make test-e2e          - Run E2E tests (15-30min)"
	@echo "  make test-performance  - Run performance tests"
	@echo "  make test-regression   - Run regression tests"
	@echo "  make test-coverage     - Generate coverage report"
	@echo "  make test-verbose      - Run all tests with verbose output"
	@echo "  make clean-tests       - Clean test artifacts"
	@echo "  make help              - Show this help message"
	@echo ""
	@echo "For more details, see tests/README.md"
