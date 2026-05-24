using Exchanges: ExchangeID
using Exchanges.Ccxt: _multifunc, default_client, call_exchange
using Exchanges.Misc: LittleDict
@enum OrderBookLevel L1 L2 L3
Base.convert(::Type{OrderBookLevel}, n::Integer) = OrderBookLevel(n - 1)

@doc "Defines an array representing possible numbers of orders to fetch."
const MAX_ORDERS = [5, 10, 20, 50, 100, 500, 1000]
@doc "Initializes a LittleDict for storing order book method names keyed by order book level and exchange ID."
const OB_METHODS = LittleDict{Tuple{OrderBookLevel,ExchangeID},String}()
@doc "Defines the time-to-live (TTL) for an order book as 5 seconds (after which it is stale)."
const OB_TTL = Ref(Second(5))
@doc "Defines the eviction time-to-live (TTL) for an order book as 5 minutes."
const OB_EVICTION_TTL = Ref(Minute(5))
@doc "Defines a NamedTuple structure for order book data."
const OrderBookTuple = NamedTuple{
    (:busy, :timestamp, :asks, :bids),
    Tuple{Ref{Bool},Ref{DateTime},Vector{Tuple{DFT,DFT}},Vector{Tuple{DFT,DFT}}},
}
@doc "Initializes a safe TTL cache for storing order book data with the default eviction TTL."
const OB_CACHE = safettl(
    Tuple{String,OrderBookLevel,ExchangeID}, OrderBookTuple, OB_EVICTION_TTL[]
)

@doc """Generates an order book of depth `N`.

$(TYPEDSIGNATURES)

The `_orderbook` function generates an order book of depth `N`. The order book contains `N` levels of bid and ask prices along with their corresponding quantities.
"""
function _orderbook(N)
    OrderBookTuple((
        Ref(false),
        Ref(DateTime(0)),
        Vector{Tuple{DFT,DFT}}(undef, N),
        Vector{Tuple{DFT,DFT}}(undef, N),
    ))
end
@doc """Returns the name of an order book level.

$(TYPEDSIGNATURES)

The `_levelname` function takes an order book `level` and returns its name.
"""
_levelname(level) =
    let lvl = convert(OrderBookLevel, level)
        if lvl == L1
            "OrderBook"
        elseif lvl == L2
            "L2OrderBook"
        else
            "L3OrderBook"
        end
    end

@doc """Updates an order book in place with new data.

$(TYPEDSIGNATURES)

The `_update_orderbook!` function takes an exchange `exc`, an order book `ob`, a symbol `sym`, an order book level `lvl`, and a limit `limit`, and updates the order book in place with new data. If `init` is set, the function will initialize the order book before updating it.
"""
function _update_orderbook!(exc, ob, sym, lvl, limit; init)
    ob.busy[] && return ob
    method_str = @lget! OB_METHODS (lvl, exc.id) begin
        m, _ = _multifunc(string(exc.id), _levelname(lvl), true)
        m
    end
    t = @async begin
        ob.busy[] = true
        try
            result = call_exchange(default_client(), string(exc.id), method_str, body=Dict("symbol" => sym, "limit" => limit))
            if result isa Exception
                @error "update ob: " result
                ob.busy[] = false
                return nothing
            end
            let v = get(result, "timestamp", 0)
                ob.timestamp[] = dt(v === nothing ? 0 : Float64(v))
            end
            let asks = ob.asks
                empty!(asks)
                for a in result["asks"]
                    push!(asks, (Float64(a[1]), Float64(a[2])))
                end
            end
            let bids = ob.bids
                empty!(bids)
                for b in result["bids"]
                    push!(bids, (Float64(b[1]), Float64(b[2])))
                end
            end
        finally
            ob.busy[] = false
        end
    end
    if init
        wait(t)
    else
        slept = 0.0
        while !istaskdone(t) && slept < 0.5
            sleep(0.1)
            slept += 0.1
        end
    end
    ob
end

@doc """Fetches an order book from an exchange for a symbol.

$(TYPEDSIGNATURES)

The `orderbook` function fetches an order book from an exchange `exc` for a symbol `sym`. The `limit` parameter can be used to limit the depth of the order book. The `level` parameter specifies the level of the order book to fetch.
"""
function orderbook(exc, sym; limit=100, level=L1)
    lvl = convert(OrderBookLevel, level)
    ob = @lget! OB_CACHE (sym, lvl, exc.id) begin
        limit = MAX_ORDERS[min(7, searchsortedlast(MAX_ORDERS, limit))]
        ob = _orderbook(limit)
        sizehint!(ob.asks, limit)
        sizehint!(ob.bids, limit)
        _update_orderbook!(exc, ob, sym, lvl, limit; init=true)
        ob
    end
    if now() > ob.timestamp[] + OB_TTL[]
        _update_orderbook!(exc, ob, sym, lvl, limit; init=false)
    end
    ob
end
