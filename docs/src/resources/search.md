# Documentation Search

<div id="search-container">
  <div class="search-box">
    <input type="text" id="search-input" placeholder="Search documentation..." autocomplete="off">
    <div id="search-suggestions" class="search-suggestions"></div>
  </div>
  
  <div class="search-filters">
    <label>
      <input type="checkbox" id="filter-getting-started" checked> Getting Started
    </label>
    <label>
      <input type="checkbox" id="filter-guides" checked> Guides
    </label>
    <label>
      <input type="checkbox" id="filter-advanced" checked> Advanced
    </label>
    <label>
      <input type="checkbox" id="filter-reference" checked> Reference
    </label>
    <label>
      <input type="checkbox" id="filter-troubleshooting" checked> Troubleshooting
    </label>
  </div>
  
  <div class="difficulty-filter">
    <label>Difficulty:</label>
    <label>
      <input type="checkbox" id="difficulty-beginner" checked> Beginner
    </label>
    <label>
      <input type="checkbox" id="difficulty-intermediate" checked> Intermediate
    </label>
    <label>
      <input type="checkbox" id="difficulty-advanced" checked> Advanced
    </label>
  </div>
</div>

<div id="search-results">
  <div class="search-stats">
    <span id="results-count">Enter a search term to find relevant documentation</span>
  </div>
  <div id="results-container"></div>
</div>

## Popular Searches

- [Strategy Development](../guides/strategy-development.md)
- [Installation](../getting-started/installation.md)
- [API Reference](../reference/api/index.md)
- [Troubleshooting](../troubleshooting/index.md)
- [Configuration](../reference/configuration.md)
- [Data Management](../guides/data-management.md)

## Search Tips

- **Use specific terms**: "margin trading" instead of just "trading"
- **Try different keywords**: "backtest" vs "simulation" vs "testing"
- **Use filters**: Narrow results by category or difficulty
- **Check suggestions**: Auto-complete shows related terms as you type

## Browse by Category

- **[Getting Started](../getting-started/index.md)** - New user guides and tutorials
- **[User Guides](../guides/index.md)** - Comprehensive development guides
- **[Advanced Topics](../advanced/index.md)** - Expert-level customization
- **[API Reference](../reference/api/index.md)** - Function documentation
- **[Troubleshooting](../troubleshooting/index.md)** - Problem resolution

<style>
.search-box {
  position: relative;
  margin-bottom: 1rem;
}

#search-input {
  width: 100%;
  padding: 12px 16px;
  font-size: 16px;
  border: 2px solid #e1e5e9;
  border-radius: 8px;
  outline: none;
  transition: border-color 0.2s;
}

#search-input:focus {
  border-color: #007acc;
}

.search-suggestions {
  position: absolute;
  top: 100%;
  left: 0;
  right: 0;
  background: white;
  border: 1px solid #e1e5e9;
  border-top: none;
  border-radius: 0 0 8px 8px;
  max-height: 200px;
  overflow-y: auto;
  z-index: 1000;
  display: none;
}

.search-suggestion {
  padding: 8px 16px;
  cursor: pointer;
  border-bottom: 1px solid #f0f0f0;
}

.search-suggestion:hover {
  background-color: #f8f9fa;
}

.search-suggestion:last-child {
  border-bottom: none;
}

.search-filters, .difficulty-filter {
  margin-bottom: 1rem;
  display: flex;
  flex-wrap: wrap;
  gap: 1rem;
}

.search-filters label, .difficulty-filter label {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  cursor: pointer;
}

.search-stats {
  margin-bottom: 1rem;
  color: #666;
  font-style: italic;
}

.search-result {
  border: 1px solid #e1e5e9;
  border-radius: 8px;
  padding: 1rem;
  margin-bottom: 1rem;
  background: white;
}

.search-result-title {
  font-size: 1.2rem;
  font-weight: bold;
  margin-bottom: 0.5rem;
}

.search-result-title a {
  color: #007acc;
  text-decoration: none;
}

.search-result-title a:hover {
  text-decoration: underline;
}

.search-result-meta {
  display: flex;
  gap: 1rem;
  margin-bottom: 0.5rem;
  font-size: 0.9rem;
  color: #666;
}

.search-result-category {
  background: #e3f2fd;
  color: #1976d2;
  padding: 2px 8px;
  border-radius: 4px;
}

.search-result-difficulty {
  background: #f3e5f5;
  color: #7b1fa2;
  padding: 2px 8px;
  border-radius: 4px;
}

.search-result-excerpt {
  line-height: 1.5;
}

.search-highlight {
  background-color: #fff3cd;
  padding: 1px 2px;
  border-radius: 2px;
}

@media (max-width: 768px) {
  .search-filters, .difficulty-filter {
    flex-direction: column;
    gap: 0.5rem;
  }
}
</style>

<script src="../assets/search.js"></script>
