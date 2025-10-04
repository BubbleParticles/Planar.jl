# Documentation Makefile

.PHONY: help test test-examples test-links test-format test-file clean validate-links link-dashboard test-code-examples validate-content qa-all

# Default target
help:
	@echo "Planar Documentation Testing"
	@echo ""
	@echo "Available targets:"
	@echo "  test          - Run all documentation tests"
	@echo "  test-examples - Run code example tests only"
	@echo "  test-links    - Run link validation tests only"
	@echo "  validate-links - Run automated link validation with dashboard"
	@echo "  link-dashboard - Generate link health monitoring dashboard"
	@echo "  test-code-examples - Test all Julia code examples in documentation"
	@echo "  validate-content - Run content consistency and template validation"
	@echo "  qa-all         - Run all quality assurance checks"
	@echo "  test-format   - Run format consistency tests only"
	@echo "  test-file     - Test a specific file (use FILE=path/to/file.md)"
	@echo "  test-multi    - Test with multiple Julia versions"
	@echo "  report        - Generate HTML report from latest test results"
	@echo "  quick-test    - Fast test for development (reduced timeout)"
	@echo "  watch         - Continuously test on file changes"
	@echo "  build         - Build documentation"
	@echo "  clean         - Clean test artifacts"
	@echo ""
	@echo "Examples:"
	@echo "  make test"
	@echo "  make test-examples"
	@echo "  make test-file FILE=docs/src/strategy.md"
	@echo "  make test-multi"
	@echo "  make report"

# Run all tests
test:
	@mkdir -p test/results
	julia --project=Planar test/runtests.jl --verbose --output=test/results/test-results.toml

# Run code example tests only
test-examples:
	@mkdir -p test/results
	julia --project=Planar test/runtests.jl --skip-links --skip-format --verbose --output=test/results/examples-results.toml

# Run link validation tests only
test-links:
	@mkdir -p test/results
	julia --project=Planar test/runtests.jl --skip-examples --skip-format --verbose --output=test/results/links-results.toml

# Run automated link validation with dashboard
validate-links:
	@echo "Running automated link validation..."
	julia --project=Planar scripts/link_validator.jl

# Generate link health dashboard
link-dashboard:
	@echo "Generating link health dashboard..."
	julia --project=Planar scripts/link_validator.jl
	@echo "Dashboard available at: docs/reports/link_health_dashboard.html"

# Run code example testing
test-code-examples:
	@echo "Testing all code examples in documentation..."
	julia --project=Planar scripts/code_example_tester.jl

# Run content consistency validation
validate-content:
	@echo "Validating content consistency and template compliance..."
	julia --project=Planar scripts/content_consistency_validator.jl

# Run all quality assurance checks
qa-all:
	@echo "Running all documentation quality assurance checks..."
	@echo "1. Validating links..."
	julia --project=Planar scripts/simple_link_validator.jl
	@echo "2. Testing code examples..."
	julia --project=Planar scripts/code_example_tester.jl
	@echo "3. Validating content consistency..."
	julia --project=Planar scripts/content_consistency_validator.jl
	@echo "All QA checks completed. Check docs/reports/ for detailed results."

# Run format consistency tests only
test-format:
	@mkdir -p test/results
	julia --project=Planar test/runtests.jl --skip-examples --skip-links --verbose --output=test/results/format-results.toml

# Test a specific file
test-file:
ifndef FILE
	@echo "Error: Please specify FILE=path/to/file.md"
	@exit 1
endif
	julia --project=Planar test/test_file.jl $(FILE) --verbose

# Build documentation
build:
	julia --project=Planar make.jl

# Generate test reports
report:
	@if [ -f test/results/test-results.toml ]; then \
		julia --project=Planar -e "push!(LOAD_PATH, \"test\"); using TestResultsReporter; generate_html_report(\"test/results/test-results.toml\", \"test/results/report.html\"); generate_summary_report(\"test/results/test-results.toml\")"; \
	else \
		echo "No test results found. Run 'make test' first."; \
	fi

# Clean test artifacts
clean:
	rm -rf test/results/
	rm -rf test/tmp/
	find . -name "*.tmp" -delete

# Quick test for development
quick-test:
	@mkdir -p test/results
	julia --project=Planar test/runtests.jl --skip-links --timeout=10 --output=test/results/quick-results.toml

# Test with specific Julia version
test-julia-%:
	@mkdir -p test/results
	julia-$* --project=Planar test/runtests.jl --verbose --output=test/results/test-results-julia-$*.toml

# Test multiple Julia versions (if available)
test-multi:
	@for version in 1.10 1.11; do \
		if command -v julia-$$version >/dev/null 2>&1; then \
			echo "Testing with Julia $$version..."; \
			make test-julia-$$version; \
		else \
			echo "Julia $$version not found, skipping..."; \
		fi; \
	done

# Continuous testing (watch for changes)
watch:
	@echo "Watching for changes in docs/src/..."
	@while true; do \
		inotifywait -r -e modify docs/src/ 2>/dev/null && \
		echo "Changes detected, running tests..." && \
		make test-examples; \
	done