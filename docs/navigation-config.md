# Navigation Configuration

This file defines the navigation structure for Planar documentation in a format that can be easily maintained and referenced.

## Main Navigation Structure

### 🚀 Getting Started (Order: 1)
**Path:** `getting-started/`  
**Description:** New to Planar? Start here  
**Next Section:** Development Guides

**Pages:**
1. [Overview](getting-started/index.md) - Getting started overview and path selection
2. [Installation](getting-started/installation.md) - Install Planar and dependencies (10 min)
3. [Quick Start](getting-started/quick-start.md) - Get up and running in 15 minutes (15 min)
4. [First Strategy](getting-started/first-strategy.md) - Build your first trading strategy (20 min)

### 📚 Development Guides (Order: 2)
**Path:** `guides/`  
**Description:** Build trading strategies  
**Next Section:** Advanced Topics

**Pages:**
1. [Overview](guides/index.md) - Guide overview and topics
2. [Strategy Development](guides/strategy-development.md) - Core development guide (45 min)
3. [Data Management](guides/data-management.md) - Working with market data (30 min)
4. [Execution Modes](guides/execution-modes.md) - Sim, Paper, and Live trading (25 min)
5. [Optimization](guides/optimization.md) - Parameter tuning and optimization (35 min)
6. [Visualization](guides/visualization.md) - Plotting and analysis (20 min)

### ⚡ Advanced Topics (Order: 3)
**Path:** `advanced/`  
**Description:** Advanced usage and customization  
**Next Section:** API Reference

**Pages:**
1. [Overview](advanced/index.md) - Advanced topics overview
2. [Customization](advanced/customization.md) - Extending Planar functionality (40 min)
3. [Margin Trading](advanced/margin-trading.md) - Advanced trading features (30 min)
4. [Multi-Exchange](advanced/multi-exchange.md) - Complex multi-exchange setups (35 min)
5. [Performance](advanced/performance.md) - Optimization and scaling (25 min)

### 📖 API Reference (Order: 4)
**Path:** `reference/`  
**Description:** Complete function documentation  
**Next Section:** Troubleshooting

**Pages:**
1. [Overview](reference/index.md) - API reference overview
2. [Configuration](reference/configuration.md) - All configuration options
3. [Types](reference/types.md) - Type system reference

**API Subsections:**
- [Core API](reference/api/core.md) - Essential functions
- [Strategy API](reference/api/strategies.md) - Strategy development functions
- [Exchange API](reference/api/exchanges.md) - Exchange integration
- [Data API](reference/api/data.md) - Data management functions

**Examples Subsections:**
- [Basic Examples](reference/examples/basic.md) - Simple usage patterns
- [Advanced Examples](reference/examples/advanced.md) - Complex implementations

### 🔧 Troubleshooting (Order: 5)
**Path:** `troubleshooting/`  
**Description:** Problem resolution  
**Next Section:** Resources

**Pages:**
1. [Overview](troubleshooting/index.md) - Problem categories and quick fixes
2. [Installation Issues](troubleshooting/installation-issues.md) - Setup and dependency problems
3. [Strategy Problems](troubleshooting/strategy-problems.md) - Strategy development issues
4. [Performance Issues](troubleshooting/performance-issues.md) - Speed and memory problems
5. [Exchange Issues](troubleshooting/exchange-issues.md) - Connection and API problems

### 📚 Resources (Order: 6)
**Path:** `resources/`  
**Description:** Additional materials

**Pages:**
1. [Overview](resources/index.md) - Available resources
2. [Glossary](resources/glossary.md) - Terms and concepts
3. [Migration Guides](resources/migration-guides.md) - Version update guides
4. [Community](resources/community.md) - Support and contacts

## User Journey Paths

### New User Journey (90 minutes total)
**Description:** Complete beginner path
1. [Installation](getting-started/installation.md) (10 min)
2. [Quick Start](getting-started/quick-start.md) (15 min)
3. [First Strategy](getting-started/first-strategy.md) (20 min)
4. [Strategy Development](guides/strategy-development.md) (45 min)

### Strategy Developer Journey (3 hours total)
**Description:** Focus on building strategies
1. [Strategy Development](guides/strategy-development.md) (45 min)
2. [Data Management](guides/data-management.md) (30 min)
3. [Execution Modes](guides/execution-modes.md) (25 min)
4. [Optimization](guides/optimization.md) (35 min)
5. [Customization](advanced/customization.md) (40 min)

### Advanced User Journey (2.5 hours total)
**Description:** Customization and scaling
1. [Customization](advanced/customization.md) (40 min)
2. [Margin Trading](advanced/margin-trading.md) (30 min)
3. [Multi-Exchange](advanced/multi-exchange.md) (35 min)
4. [Performance](advanced/performance.md) (25 min)
5. [Core API](reference/api/core.md) (reference)

### Troubleshooter Journey (30 minutes total)
**Description:** Problem resolution
1. [Troubleshooting Overview](troubleshooting/index.md) (5 min)
2. [Installation Issues](troubleshooting/installation-issues.md) (10 min)
3. [Strategy Problems](troubleshooting/strategy-problems.md) (10 min)
4. [Community Support](resources/community.md) (5 min)

## Navigation Patterns

### Breadcrumb Format
`Docs > Section > Subsection > Current Page`

### Next Steps Format
- **Continue:** Next page in sequence
- **Explore:** Related section or advanced topic
- **See also:** Cross-references to related content

### Footer Navigation Format
```
---
**Previous:** [Previous Topic](previous.md) | **Next:** [Next Topic](next.md)
**Section:** [Section Home](index.md) | **Docs Home:** [Documentation](../index.md)
```

## Cross-Reference Rules

### From Getting Started → Suggest:
- Development Guides (primary)
- Troubleshooting (if issues)
- API Reference (for details)

### From Guides → Suggest:
- Advanced Topics (progression)
- API Reference (implementation)
- Troubleshooting (if issues)

### From Advanced → Suggest:
- API Reference (implementation)
- Troubleshooting (complex issues)
- Community (advanced help)

### From Reference → Suggest:
- Guides (learning context)
- Examples (practical usage)
- Troubleshooting (usage issues)

### From Troubleshooting → Suggest:
- Getting Started (basics)
- Guides (learning)
- Community (additional help)