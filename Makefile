.PHONY: test test-smoke test-unit test-symlink-sensitive test-integration test-live test-root test-coverage test-all test-plugin-name validate-plugin-assembly clean-tests help sync sync-check ci-changed ci-local

# Default: smoke + unit (fast feedback)
test: test-smoke test-unit

# Regenerate ALL derived artifacts (run after changing commands/skills/agents or plugin.json)
# See RELEASING.md step 3 for the artifact-to-generator map.
sync:
	@./scripts/sync-readme.py
	@./scripts/sync-marketplace.sh
	@./scripts/build-openclaw.sh
	@./scripts/build-factory-skills.sh

# Verify derived artifacts are current (what CI enforces)
sync-check:
	@./scripts/sync-readme.py --check
	@./scripts/sync-marketplace.sh --check
	@./scripts/build-openclaw.sh --check
	@./scripts/build-factory-skills.sh --check

# CI parity: everything the required checks run, locally.
# Local green here predicts remote green; targeted suites alone do not.
ci-local: sync-check test-smoke test-unit test-integration
	@echo "ci-local complete: matches required checks (Smoke/Unit/Integration) + CI-only verifications"

# Proportional pre-push gate. The selector always runs sync/smoke coverage and
# fails closed to ci-local for shared, generated, manifest, or unmapped changes.
ci-changed:
	@./scripts/ci-changed.sh

# Validate plugin name (critical - prevents command prefix breakage)
test-plugin-name:
	@./tests/validate-plugin-name.sh

# Validate skills, commands, agents, connector metadata, and plugin manifests
validate-plugin-assembly:
	@./scripts/validate-plugin-assembly.py --root .

# Run all tests
test-all: test-smoke test-unit test-integration

# Smoke tests (pre-commit, <30s)
test-smoke: test-plugin-name
	@echo "Running smoke tests..."
	@./tests/run-all.sh smoke

# Unit tests (1-2min)
test-unit:
	@echo "Running unit tests..."
	@./tests/run-all.sh unit

# Pull-request symlink lane: avoid a third full unit pass while preserving every
# suite that explicitly exercises logical and physical path behavior.
test-symlink-sensitive:
	@echo "Running symlink-sensitive unit tests..."
	@./tests/run-all.sh symlink-sensitive

# Integration tests (5-10min)
test-integration:
	@echo "Running integration tests..."
	@./tests/run-all.sh integration

# Live tests - real Claude Code sessions (2-5min per test, uses API)
test-live:
	@echo "Running live tests (real Claude Code sessions)..."
	@echo "WARNING: This makes real API calls"
	@./tests/run-all.sh live

# tests/ root category (see #741 — not run by any CI gate)
test-root:
	@echo "Running tests/ root suites..."
	@./tests/run-all.sh root

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
	@echo "  make ci-changed        - Run fail-closed tests selected from changed files"
	@echo "  make ci-local          - Run the complete pre-merge/release matrix"
	@echo "  make          - Run E2E tests (15-30min)"
	@echo "  make test-live         - Run live tests (real Claude sessions, real API cost)"
	@echo "  make test-root         - Run tests/ root suites (not in CI, see #741)"
	@echo "  make  - Run performance tests"
	@echo "  make   - Run regression tests"
	@echo "  make test-coverage     - Generate coverage report"
	@echo "  make validate-plugin-assembly - Validate plugin assembly structure"
	@echo "  make test-verbose      - Run all tests with verbose output"
	@echo "  make clean-tests       - Clean test artifacts"
	@echo "  make help              - Show this help message"
	@echo ""
	@echo "For more details, see tests/README.md"
