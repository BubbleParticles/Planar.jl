---
inclusion: always
---

# Reports and Analysis Guidelines

## File Organization

### Report Directory Structure
- **`reports/`**: Top-level directory for all reports, audits, and analysis documents
- Use descriptive filenames with date prefixes: `YYYY-MM-DD-report-name.md`
- Group related reports in subdirectories when appropriate: `reports/audits/`, `reports/performance/`

### Report Types
- **Audits**: Code quality, security, and compliance reviews
- **Performance Analysis**: Backtesting results, strategy performance metrics
- **Documentation Reviews**: Content freshness, accuracy assessments
- **System Analysis**: Architecture reviews, dependency audits
- **User Journey Analysis**: UX/workflow improvement studies

## Content Standards

### Report Format
- Use markdown format with proper frontmatter including title, date, and report type
- Include executive summary for reports longer than 2 pages
- Provide actionable recommendations with priority levels
- Reference specific code files, line numbers, or configuration sections when applicable

### Data Presentation
- Use tables for structured data comparison
- Include charts/graphs as images when beneficial for understanding
- Provide raw data or links to data sources for reproducibility
- Use consistent units and formatting across related reports

### Naming Conventions
```
reports/
├── YYYY-MM-DD-audit-name.md          # Security, code quality audits
├── YYYY-MM-DD-performance-name.md    # Strategy/system performance
├── YYYY-MM-DD-documentation-name.md  # Documentation reviews
└── analysis/                         # Ongoing analysis work
    └── strategy-comparison-Q1-2024.md
```

## Integration with Planar

### Strategy Performance Reports
- Reference specific strategy files in `user/strategies/`
- Include backtesting parameters and timeframes
- Link to relevant configuration in `user/planar.toml`
- Document exchange-specific considerations

### Code Quality Reports
- Reference module structure and dependencies
- Include Julia-specific metrics (type stability, compilation time)
- Document adherence to JuliaFormatter standards
- Assess test coverage across modules

### Automation
- Use `scripts/freshness-report.jl` for documentation currency analysis
- Integrate with validation tools: `scripts/validate-examples.jl`, `scripts/check-links.sh`
- Generate reports as part of CI/CD pipeline when applicable