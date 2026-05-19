@doc "Clears all caches."
function emptycaches!()
    empty!(TICKERS_CACHE100)
    empty!(TICKERS_CACHE10)
    empty!(TICKERSLIST_LOCK_DICT)
    empty!(tickersCache10Sec)
    empty!(marketsCache1Min)
    empty!(activeCache1Min)
    ExchangeTypes._closeall()
end
