# Documentation Makefile

.PHONY: help test test-examples test-links test-format test-file clean

# Default target
help:
	@echo "Planar Documentation Testing"
	@echo ""
	@echo "Available targets:"
	@echo "  test          - Run all documentation tests"
	@echo "  test-examples - Run code example tests only"
	@echo "  test-links    - Run link validation tests only"
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