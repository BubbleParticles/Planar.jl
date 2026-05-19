@doc "Clears all caches."
function emptycaches!()
    try empty!(TICKERS_CACHE100) catch end
    try empty!(TICKERS_CACHE10) catch end
    try empty!(TICKERSLIST_LOCK_DICT) catch end
    try empty!(tickersCache10Sec) catch end
    try empty!(marketsCache1Min) catch end
    try empty!(activeCache1Min) catch end
    ExchangeTypes._closeall()
end
