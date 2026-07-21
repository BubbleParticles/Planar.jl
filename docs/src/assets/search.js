/**
 * Planar Documentation Search
 * 
 * Provides full-text search functionality with:
 * - Real-time search as you type
 * - Auto-complete suggestions
 * - Category and difficulty filtering
 * - Result ranking and highlighting
 */

class DocumentationSearch {
    constructor() {
        this.searchIndex = null;
        this.searchInput = null;
        this.suggestionsContainer = null;
        this.resultsContainer = null;
        this.resultsCount = null;
        this.currentQuery = '';
        this.debounceTimer = null;
        
        // Search configuration
        this.config = {
            debounceDelay: 300,
            maxSuggestions: 8,
            maxResults: 50,
            minQueryLength: 2,
            excerptLength: 150
        };
        
        this.init();
    }
    
    async init() {
        // Wait for DOM to be ready
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', () => this.setupDOM());
        } else {
            this.setupDOM();
        }
        
        // Load search index
        await this.loadSearchIndex();
    }
    
    setupDOM() {
        // Get DOM elements
        this.searchInput = document.getElementById('search-input');
        this.suggestionsContainer = document.getElementById('search-suggestions');
        this.resultsContainer = document.getElementById('results-container');
        this.resultsCount = document.getElementById('results-count');
        
        if (!this.searchInput) {
            console.warn('Search input not found - search functionality disabled');
            return;
        }
        
        // Setup event listeners
        this.searchInput.addEventListener('input', (e) => this.handleSearchInput(e));
        this.searchInput.addEventListener('keydown', (e) => this.handleKeyDown(e));
        this.searchInput.addEventListener('focus', () => this.showSuggestions());
        this.searchInput.addEventListener('blur', () => this.hideSuggestions());
        
        // Setup filter listeners
        this.setupFilterListeners();
        
        // Handle URL parameters
        this.handleURLParams();
    }
    
    setupFilterListeners() {
        const filterInputs = document.querySelectorAll('input[type="checkbox"]');
        filterInputs.forEach(input => {
            input.addEventListener('change', () => this.performSearch());
        });
    }
    
    handleURLParams() {
        const urlParams = new URLSearchParams(window.location.search);
        const query = urlParams.get('q');
        if (query) {
            this.searchInput.value = query;
            this.currentQuery = query;
            this.performSearch();
        }
    }
    
    async loadSearchIndex() {
        try {
            const response = await fetch('/assets/search-index.json');
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }
            this.searchIndex = await response.json();
            console.log(`Loaded search index with ${this.searchIndex.documents.length} documents`);
        } catch (error) {
            console.error('Failed to load search index:', error);
            this.showError('Search functionality is currently unavailable.');
        }
    }
    
    handleSearchInput(event) {
        const query = event.target.value.trim();
        this.currentQuery = query;
        
        // Clear previous timer
        if (this.debounceTimer) {
            clearTimeout(this.debounceTimer);
        }
        
        // Debounce search
        this.debounceTimer = setTimeout(() => {
            if (query.length >= this.config.minQueryLength) {
                this.performSearch();
                this.updateSuggestions();
            } else {
                this.clearResults();
                this.hideSuggestions();
            }
        }, this.config.debounceDelay);
    }
    
    handleKeyDown(event) {
        if (event.key === 'Escape') {
            this.hideSuggestions();
            this.searchInput.blur();
        } else if (event.key === 'Enter') {
            event.preventDefault();
            this.hideSuggestions();
            this.performSearch();
        }
    }
    
    performSearch() {
        if (!this.searchIndex || this.currentQuery.length < this.config.minQueryLength) {
            this.clearResults();
            return;
        }
        
        const filters = this.getActiveFilters();
        const results = this.searchDocuments(this.currentQuery, filters);
        this.displayResults(results);
        this.updateURL();
    }
    
    getActiveFilters() {
        const filters = {
            categories: [],
            difficulties: []
        };
        
        // Get active category filters
        const categoryFilters = ['getting-started', 'guides', 'advanced', 'reference', 'troubleshooting'];
        categoryFilters.forEach(category => {
            const checkbox = document.getElementById(`filter-${category}`);
            if (checkbox && checkbox.checked) {
                filters.categories.push(category);
            }
        });
        
        // Get active difficulty filters
        const difficultyFilters = ['beginner', 'intermediate', 'advanced'];
        difficultyFilters.forEach(difficulty => {
            const checkbox = document.getElementById(`difficulty-${difficulty}`);
            if (checkbox && checkbox.checked) {
                filters.difficulties.push(difficulty);
            }
        });
        
        return filters;
    }
    
    searchDocuments(query, filters) {
        const queryTerms = query.toLowerCase().split(/\s+/).filter(term => term.length > 0);
        const results = [];
        
        for (const doc of this.searchIndex.documents) {
            // Apply filters
            if (filters.categories.length > 0 && !filters.categories.includes(doc.category)) {
                continue;
            }
            if (filters.difficulties.length > 0 && !filters.difficulties.includes(doc.difficulty)) {
                continue;
            }
            
            // Calculate relevance score
            const score = this.calculateRelevanceScore(doc, queryTerms);
            if (score > 0) {
                results.push({
                    document: doc,
                    score: score,
                    highlights: this.findHighlights(doc, queryTerms)
                });
            }
        }
        
        // Sort by relevance score (descending)
        results.sort((a, b) => b.score - a.score);
        
        return results.slice(0, this.config.maxResults);
    }
    
    calculateRelevanceScore(doc, queryTerms) {
        let score = 0;
        const titleLower = doc.title.toLowerCase();
        const descriptionLower = doc.description.toLowerCase();
        const keywordsLower = doc.keywords.map(k => k.toLowerCase());
        const headingsLower = doc.headings.map(h => h.toLowerCase());
        
        for (const term of queryTerms) {
            // Title matches (highest weight)
            if (titleLower.includes(term)) {
                score += titleLower === term ? 100 : 50;
            }
            
            // Heading matches (high weight)
            for (const heading of headingsLower) {
                if (heading.includes(term)) {
                    score += heading === term ? 40 : 20;
                }
            }
            
            // Keyword matches (medium weight)
            for (const keyword of keywordsLower) {
                if (keyword.includes(term)) {
                    score += keyword === term ? 30 : 15;
                }
            }
            
            // Description matches (medium weight)
            if (descriptionLower.includes(term)) {
                score += 10;
            }
            
            // Topic matches (low weight)
            for (const topic of doc.topics) {
                if (topic.toLowerCase().includes(term)) {
                    score += 5;
                }
            }
        }
        
        return score;
    }
    
    findHighlights(doc, queryTerms) {
        const highlights = [];
        const text = `${doc.title} ${doc.description} ${doc.excerpt}`.toLowerCase();
        
        for (const term of queryTerms) {
            const regex = new RegExp(`\\b${this.escapeRegex(term)}\\b`, 'gi');
            const matches = [...text.matchAll(regex)];
            highlights.push(...matches.map(match => ({
                term: term,
                start: match.index,
                end: match.index + match[0].length
            })));
        }
        
        return highlights;
    }
    
    escapeRegex(string) {
        return string.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&');
    }
    
    displayResults(results) {
        if (!this.resultsContainer || !this.resultsCount) return;
        
        // Update results count
        const count = results.length;
        const query = this.currentQuery;
        this.resultsCount.textContent = count > 0 
            ? `Found ${count} result${count !== 1 ? 's' : ''} for "${query}"`
            : `No results found for "${query}"`;
        
        // Clear previous results
        this.resultsContainer.innerHTML = '';
        
        if (count === 0) {
            this.showNoResults();
            return;
        }
        
        // Display results
        results.forEach(result => {
            const resultElement = this.createResultElement(result);
            this.resultsContainer.appendChild(resultElement);
        });
    }
    
    createResultElement(result) {
        const { document: doc, score } = result;
        
        const resultDiv = document.createElement('div');
        resultDiv.className = 'search-result';
        
        // Create title with link
        const titleDiv = document.createElement('div');
        titleDiv.className = 'search-result-title';
        const titleLink = document.createElement('a');
        titleLink.href = doc.url;
        titleLink.textContent = doc.title;
        titleDiv.appendChild(titleLink);
        
        // Create metadata
        const metaDiv = document.createElement('div');
        metaDiv.className = 'search-result-meta';
        
        const categorySpan = document.createElement('span');
        categorySpan.className = 'search-result-category';
        categorySpan.textContent = this.formatCategory(doc.category);
        
        const difficultySpan = document.createElement('span');
        difficultySpan.className = 'search-result-difficulty';
        difficultySpan.textContent = this.formatDifficulty(doc.difficulty);
        
        metaDiv.appendChild(categorySpan);
        metaDiv.appendChild(difficultySpan);
        
        // Create excerpt
        const excerptDiv = document.createElement('div');
        excerptDiv.className = 'search-result-excerpt';
        excerptDiv.innerHTML = this.highlightText(doc.description || doc.excerpt);
        
        // Assemble result
        resultDiv.appendChild(titleDiv);
        resultDiv.appendChild(metaDiv);
        resultDiv.appendChild(excerptDiv);
        
        return resultDiv;
    }
    
    formatCategory(category) {
        return category.split('-').map(word => 
            word.charAt(0).toUpperCase() + word.slice(1)
        ).join(' ');
    }
    
    formatDifficulty(difficulty) {
        return difficulty.charAt(0).toUpperCase() + difficulty.slice(1);
    }
    
    highlightText(text) {
        if (!this.currentQuery) return text;
        
        const queryTerms = this.currentQuery.toLowerCase().split(/\s+/);
        let highlightedText = text;
        
        queryTerms.forEach(term => {
            const regex = new RegExp(`\\b(${this.escapeRegex(term)})\\b`, 'gi');
            highlightedText = highlightedText.replace(regex, '<span class="search-highlight">$1</span>');
        });
        
        return highlightedText;
    }
    
    updateSuggestions() {
        if (!this.suggestionsContainer || !this.searchIndex) return;
        
        const suggestions = this.generateSuggestions(this.currentQuery);
        this.displaySuggestions(suggestions);
    }
    
    generateSuggestions(query) {
        if (query.length < 2) return [];
        
        const suggestions = new Set();
        const queryLower = query.toLowerCase();
        
        // Add matching keywords
        for (const doc of this.searchIndex.documents) {
            for (const keyword of doc.keywords) {
                if (keyword.toLowerCase().includes(queryLower) && keyword.length > query.length) {
                    suggestions.add(keyword);
                }
            }
            
            // Add matching titles
            if (doc.title.toLowerCase().includes(queryLower) && doc.title.length > query.length) {
                suggestions.add(doc.title);
            }
        }
        
        return Array.from(suggestions).slice(0, this.config.maxSuggestions);
    }
    
    displaySuggestions(suggestions) {
        if (!this.suggestionsContainer) return;
        
        this.suggestionsContainer.innerHTML = '';
        
        if (suggestions.length === 0) {
            this.hideSuggestions();
            return;
        }
        
        suggestions.forEach(suggestion => {
            const suggestionDiv = document.createElement('div');
            suggestionDiv.className = 'search-suggestion';
            suggestionDiv.textContent = suggestion;
            suggestionDiv.addEventListener('mousedown', (e) => {
                e.preventDefault(); // Prevent blur event
                this.selectSuggestion(suggestion);
            });
            this.suggestionsContainer.appendChild(suggestionDiv);
        });
        
        this.showSuggestions();
    }
    
    selectSuggestion(suggestion) {
        this.searchInput.value = suggestion;
        this.currentQuery = suggestion;
        this.hideSuggestions();
        this.performSearch();
    }
    
    showSuggestions() {
        if (this.suggestionsContainer) {
            this.suggestionsContainer.style.display = 'block';
        }
    }
    
    hideSuggestions() {
        if (this.suggestionsContainer) {
            this.suggestionsContainer.style.display = 'none';
        }
    }
    
    showNoResults() {
        const noResultsDiv = document.createElement('div');
        noResultsDiv.className = 'no-results';
        noResultsDiv.innerHTML = `
            <h3>No results found</h3>
            <p>Try:</p>
            <ul>
                <li>Using different keywords</li>
                <li>Checking your spelling</li>
                <li>Using more general terms</li>
                <li>Adjusting the filters above</li>
            </ul>
            <p>Or browse by category:</p>
            <ul>
                <li><a href="../getting-started/">Getting Started</a></li>
                <li><a href="../guides/">User Guides</a></li>
                <li><a href="../reference/">Reference</a></li>
                <li><a href="../troubleshooting/">Troubleshooting</a></li>
            </ul>
        `;
        this.resultsContainer.appendChild(noResultsDiv);
    }
    
    clearResults() {
        if (this.resultsContainer) {
            this.resultsContainer.innerHTML = '';
        }
        if (this.resultsCount) {
            this.resultsCount.textContent = 'Enter a search term to find relevant documentation';
        }
    }
    
    showError(message) {
        if (this.resultsContainer) {
            this.resultsContainer.innerHTML = `
                <div class="search-error">
                    <p><strong>Error:</strong> ${message}</p>
                    <p>Please try again later or browse the documentation manually.</p>
                </div>
            `;
        }
    }
    
    updateURL() {
        if (this.currentQuery && window.history && window.history.replaceState) {
            const url = new URL(window.location);
            url.searchParams.set('q', this.currentQuery);
            window.history.replaceState({}, '', url);
        }
    }
}

// Initialize search when the script loads
const documentationSearch = new DocumentationSearch();