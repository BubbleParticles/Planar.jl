# `utils.jl` — Old (Python) vs New (Gateway) Comparison

## `emptycaches!`

**Old:**
```julia
emptycaches!() = begin
    empty!(tickersCache10Sec)
    Ccxt.exchange_has_cache_empty!()
    empty!(currenciesCache1Hour)
end
```

**New:**
```julia
emptycaches!() = begin
    empty!(TICKERS_CACHE10)
    empty!(TICKERS_CACHE100)
    empty!(TICKERSLIST_LOCK_DICT)
    Ccxt.exchange_has_cache_empty!()
    empty!(currenciesCache1Hour)
end
```

**Changes:** Also clears `TICKERS_CACHE100` and `TICKERSLIST_LOCK_DICT`. More thorough. OK.
