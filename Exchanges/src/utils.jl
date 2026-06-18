struct StreamHandler
    stop::Function
    push::Function
end
StreamHandler(; stop=Base.Returns(nothing), push=Base.Returns(nothing)) = StreamHandler(stop, push)

isdict(x) = x isa Dict
islist(x) = x isa Union{AbstractVector, Tuple}

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
