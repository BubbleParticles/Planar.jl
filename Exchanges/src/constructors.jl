import Base: getproperty
import Serialization: deserialize, serialize
using Serialization: AbstractSerializer, serialize_type

using Reexport
using Pbar.Term: RGBColor, tprint
using ExchangeTypes
using Data: Data, DataFrame, eventtrace
@reexport using ExchangeTypes
using ExchangeTypes: OptionsDict, CcxtExchange
using ExchangeTypes.Ccxt: Ccxt, choosefunc
import .Ccxt: issupported
import ExchangeTypes.CcxtGateway: default_client, call_exchange
using JSON
using Instruments
using Instruments: Misc
using .Misc:
    DATA_PATH, dt, futures_exchange, exchange_keys, Misc, NoMargin, LittleDict, isoffline
using .Misc.OrderedCollections: OrderedSet
using .Misc.TimeToLive
using .TimeToLive: ConcurrentDict
using .Misc.TimeTicks
using .Misc.Lang: @lget!
using .Misc.DocStringExtensions

# exchangeid, markettype
@doc "The cache for tickers which lasts for 100 minutes by exchange pair."
const TICKERS_CACHE100 = safettl(Tuple{Symbol,Symbol}, Dict, Minute(100))
const TICKERS_CACHE10 = safettl(Tuple{Symbol,Symbol}, Dict, Second(10))
@doc "Lock held when fetching tickers (list)."
const TICKERSLIST_LOCK_DICT = ConcurrentDict(Dict{Tuple{Symbol,Symbol},ReentrantLock}())

@doc "Define an exchange variable set to its matching exchange instance.

$(TYPEDSIGNATURES)
"
macro exchange!(name)
    exc_var = esc(name)
    exc_str = lowercase(string(name))
    exc_istr = string(name)
    quote
        exc_sym = Symbol($exc_istr)
        $exc_var = if (exc.isset && lowercase(exc.name) === $exc_str)
            exc
        else
            (
                if hasproperty($(__module__), exc_sym)
                    getproperty($(__module__), exc_sym)
                else
                    Exchange(exc_sym)
                end
            )
        end
    end
end

@doc """Checks if a file is younger than a specified period.

$(TYPEDSIGNATURES)

- `f`: a string that represents the path to the file.
- `p`: a Period object that represents the time period.

"""
function isfileyounger(f::AbstractString, p::Period)
    isfile(f) && dt(stat(f).ctime) < now() - p
end

@doc """Converts a nested structure (Dict/Vector) recursively into a standard Julia Dict.

$(TYPEDSIGNATURES)

Handles JSON3.Object and JSON3.Array types from gateway responses.
"""
function _elconvert(v)
    if v isa AbstractDict
        d = Dict{Any,Any}(pairs(v))
        for (k, v) in d
            d[k] = _elconvert(v)
        end
        d
    elseif v isa AbstractVector
        [ _elconvert(x) for x in v ]
    else
        v
    end
end

@doc """Convert a gateway response value into a standard Julia Dict.

$(TYPEDSIGNATURES)
"""
function jlpyconvert(v)
    v === nothing && return nothing
    if v isa AbstractDict
        d = Dict{Any,Any}(pairs(v))
        for (k, v) in d
            d[k] = _elconvert(v)
        end
        d
    else
        v
    end
end

@doc """Load exchange markets from gateway or cache.

$(TYPEDSIGNATURES)

- `exc`: an Exchange object that represents the exchange to load markets from.
- `cache` (optional, default is true): a boolean that indicates whether to rely on storage cache.
- `agemax` (optional, default is Day(1)): a Period object that represents the maximum cache valid period.

"""
function loadmarkets!(exc; cache=true, agemax=Day(1))
    sbox = issandbox(exc) ? "_sandbox" : ""
    mkt = joinpath(DATA_PATH, exc.name, "markets$(sbox).jlz")
    empty!(exc.markets)
    function force_load()
        isoffline() && return nothing
        try
            @debug "Loading markets from gateway and caching at $mkt."
            name = string(exc.id)
            raw = call_exchange(default_client(), name, "markets")
            if raw isa AbstractDict
                mkpath(dirname(mkt))
                cache_dict = Dict{Symbol,String}()
                cache_dict[:markets] = json(Dict(pairs(raw)))
                write(mkt, json(cache_dict))
                conv = jlpyconvert(raw)
                if conv isa AbstractDict
                    merge!(exc.markets, conv)
                end
            end
        catch e
            @warn e
        end
    end
    if (isfileyounger(mkt, agemax) && cache) || isoffline()
        try
            @debug "Loading markets from cache."
            cache_dict = JSON.parse(read(mkt, String))
            merge!(exc.markets, JSON.parse(cache_dict["markets"]))
        catch error
            @debug error
            force_load()
        end
    else
        @debug cache ? "Force loading markets." : "Loading markets because cache is stale."
        force_load()
    end
    types = exc.types
    for m in values(exc.markets)
        push!(types, Symbol(m["type"]))
    end
    nothing
end

@doc "Get the global exchange."
getexchange() = exc

using .Misc.Lang: @caller
@doc """getexchange!: Get ccxt exchange by symbol, either from cache or create anew via CcxtGateway.

$(TYPEDSIGNATURES)
"""
function getexchange!(
    x::Symbol, params=nothing; account="", sandbox=true, markets=:yes, kwargs...
)
    @debug "exchanges: getexchange!" x @caller
    @lget!(
        sandbox ? sb_exchanges : exchanges,
        (x, account),
        if x == Symbol()
            Exchange(nothing)
        else
            e = Exchange(x; account)
            sandbox && sandbox!(e; flag=true, remove_keys=false)
            setexchange!(e; markets)
        end,
    )
end
function getexchange!(x::Union{ExchangeID,Type{<:ExchangeID}}, args...; kwargs...)
    getexchange!(Symbol(x), args...; kwargs...)
end

@doc """Initializes a gateway-based exchange struct.

$(TYPEDSIGNATURES)

- `exc`: an Exchange object to be set up.
- `markets` (optional, default is `:yes`): whether to load markets during setup.

Configures the exchange timeframes, loads markets, and sets API keys.
"""
function setexchange!(exc::Exchange, args...; markets::Symbol=:yes, kwargs...)
    @debug "Loading Markets..."
    if markets in (:yes, :force)
        loadmarkets!(exc; cache=(markets != :force))
    end
    @debug "Loaded $(length(exc.markets))."
    exc._trace = eventtrace(nameof(exc))
    exckeys!(exc)
    exc
end

@doc "Ccxt fees can have different forms. Converts to Julia types."
function _setfees!(fees, k, v)
    fees[Symbol(k)] = if v isa Bool
        v
    elseif v isa String
        Symbol(v)
    elseif v isa AbstractFloat
        DFT(v)
    elseif v isa AbstractDict
        LittleDict{Symbol,Vector{Vector{DFT}}}(Symbol(k) => v for (k, v) in pairs(v))
    elseif v isa Number
        DFT(v)
    else
        nothing
    end
end

@doc "Set the ccxt exchange `has` flags (already populated by Exchange constructor)."
setflags!(args...; kwargs...) = nothing

@doc "When serializing an exchange, serialize only its id."
function serialize(s::AbstractSerializer, exc::E) where {E<:Exchange}
    serialize_type(s, E, false)
    serialize(s, (exc.id, issandbox(exc), account(exc), nothing))
end

@doc "When serializing an exchange, serialize only its id."
function serialize(s::AbstractSerializer, exc::E) where {E<:CcxtExchange}
    serialize_type(s, E, false)
    serialize(s, (exc.id, issandbox(exc), account(exc), nothing))
end

@doc "When deserializing an exchange, use the deserialized id to construct the exchange."
deserialize(s::AbstractSerializer, ::Type{<:Exchange}) = begin
    id, sandbox_flag, acc, _ = deserialize(s)
    getexchange!(id, nothing; sandbox=sandbox_flag, account=acc)
end

@doc "Check if exchange has tickers list.

$(TYPEDSIGNATURES)
"
@inline function hastickers(exc::Exchange)
    has(exc, :fetchTickers, :fetchTickersWs, :watchTickers)
end

@doc "Ccxt market types."
MARKET_TYPES = (:spot, :future, :swap, :option, :margin, :delivery)

_lasttype(types) = begin
    len = length(types)
    if len == 0
        nothing
    elseif len == 1
        first(types)
    else
        first(Iterators.drop(types, len - 1))
    end
end
@doc "Any of $MARKET_TYPES"
function markettype(exc, margin=Misc.config.margin)
    types = exc.types
    if margin == NoMargin()
        if :spot ∈ types
            :spot
        else
            _lasttype(types)
        end
    else
        if :linear ∈ types
            :linear
        elseif :swap ∈ types
            :swap
        elseif :future ∈ types
            :future
        else
            _lasttype(types)
        end
    end
end

function markettype(exc::Exchange, sym, margin)
    mkt = get(exc.markets, string(sym), missing)
    if ismissing(mkt)
        markettype(exc, margin)
    else
        mkt["type"]
    end
end

@doc """Fetch and cache tickers data via gateway.

$(TYPEDSIGNATURES)
"""
macro tickers!(type=nothing, force=false, cache=TICKERS_CACHE100)
    exc = esc(:exc)
    tickers = esc(:tickers)
    type = type ∈ MARKET_TYPES ? QuoteNode(type) : esc(type)
    cache = esc(cache)
    quote
        local $tickers
        tp = @something($type, markettype($exc), missing)
        nm = nameof($(exc))
        k = (nm, tp)
        l = @lget! $(TICKERSLIST_LOCK_DICT) k ReentrantLock()
        @lock l begin
            if ismissing(tp)
                @warn "tickers: no market type found (offline?)" type = tp $exc.id
                $tickers = Dict{String,Dict{String,Any}}()
            elseif $force || !haskey($cache, k)
                @assert hastickers($exc) "Exchange doesn't provide tickers list."
                name = string($(exc).id)
                raw = call_exchange(default_client(), name, "fetchTickers"; query=Dict("type" => string(tp)))
                $cache[k] = $tickers = raw isa Dict ? Dict{String,Dict{String,Any}}(pairs(raw)) : Dict{String,Dict{String,Any}}()
            else
                $tickers = $cache[k]
            end
        end
    end
end

@doc """Get the markets of the `ccxt` instance, according to `min_volume` and `quote` currency.

$(TYPEDSIGNATURES)
"""
function filter_markets(exc; min_volume=10e4, quot="USDT", sep='/', type=:spot)
    markets = exc.markets
    @tickers! type
    f_markets = Dict()
    for (p, tick) in tickers
        if !haskey(markets, p)
            continue
        end
        _, pquot_frag = split(p, sep)
        pquot = spotpair(pquot_frag)
        if pquot == quot && tickers[p]["quoteVolume"] > min_volume
            f_markets[p] = markets[p]
        end
    end
    f_markets
end

@doc """Get price from ticker.

$(TYPEDSIGNATURES)
"""
function tickerprice(tkr)
    @something get(tkr, "average", nothing) get(tkr, "last", nothing) get(tkr, "bid", nothing)
end

@doc """Get price ranges using tickers data from exchange.

$(TYPEDSIGNATURES)
"""
function price_ranges(pair::AbstractString, args...; exc, kwargs...)
    type = markettype(exc)
    tkrs = @tickers! type true
    price_ranges(tkrs[pair]["last"], args...; kwargs...)
end

@doc """Get quote volume from ticker.

$(TYPEDSIGNATURES)
"""
function quotevol(tkr::AbstractDict)
    v1 = get(tkr, "quoteVolume", nothing)
    isnothing(v1) || return float(v1)
    v2 = get(tkr, "baseVolume", nothing)
    # NOTE: this is not the actual quote volume, since vol from trades
    # have different prices
    isnothing(v2) || return float(v2) * tickerprice(tkr)
    0
end

@doc "Trims the settlement currency in futures. (`mkt` is a ccxt market.)

$(TYPEDSIGNATURES)
"
@inline function spotsymbol(sym, mkt)
    if "quote" ∈ keys(mkt)
        "$(mkt["base"])/$(mkt["quote"])"
    else
        split(sym, ":")[1]
    end
end

issupported(tf::AbstractString, exc) = tf ∈ exc.timeframes
@doc """Check if a timeframe is supported by an exchange.

$(TYPEDSIGNATURES)
"""
issupported(tf::TimeFrame, exc) = issupported(string(tf), exc)

_authenticate!(::Exchange) = nothing

@doc "Exchange authentication is handled by the gateway subprocess automatically when keys are set."
authenticate!(::Exchange, tries=3) = true

@doc "Set exchange API keys directly on the gateway exchange instance."
function exckeys!(exc, key, secret, pass, wa, pk)
    if Symbol(exc.id) ∈ (:kucoin, :kucoinfutures)
        key, secret = secret, key
    end
    if !isempty(key) || !isempty(secret) || !isempty(pass)
        try
            name = string(exc.id)
            call_exchange(default_client(), name, "set_api_key", query=Dict(
                "apiKey" => key, "secret" => secret,
                "password" => pass, "walletAddress" => wa, "privateKey" => pk,
            ))
        catch
            @debug "exckeys! via gateway not supported"
        end
    end
    authenticate!(exc)
    nothing
end

@doc "Load exchange API keys from config and set on gateway exchange."
function exckeys!(exc; sandbox=false, acc=account(exc))
    eid = Symbol(exc.id)
    exc_keys = exchange_keys(eid; sandbox, account=acc)
    if isempty(exc_keys) && eid ∈ values(futures_exchange)
        id = argmax(x -> x[2] == eid, futures_exchange)
        merge!(exc_keys, exchange_keys(id.first; sandbox, account=acc))
    end
    if !isempty(exc_keys)
        @debug "Setting exchange keys..."
        exckeys!(
            exc,
            (get(exc_keys, k, "") for k in ("apiKey", "secret", "password", "walletAddress", "privateKey"))...,
        )
    end
end

@doc """Enable sandbox mode for exchange via gateway.

$(TYPEDSIGNATURES)
"""
function sandbox!(exc::Exchange; flag=!issandbox(exc), remove_keys=true)
    name = string(exc.id)
    success = try
        call_exchange(default_client(), name, "setSandboxMode", query=Dict("enable" => string(flag)))
        true
    catch e
        msg = string(e)
        if occursin("sandbox", msg) || occursin("Not Found", msg) || occursin("404", msg)
            @warn "sandbox! failed: $e"
            false
        else
            rethrow(e)
        end
    end
    if flag && success
        @assert issandbox(exc) "Exchange sandbox mode couldn't be enabled. (disable sandbox mode with `sandbox=false`)"
        remove_keys && exckeys!(exc, "", "", "", "", "")
    else
        exckeys!(exc)
    end
    nothing
end

@doc "Check if exchange is in sandbox mode via gateway."
function issandbox(exc::Exchange)
    try
        name = string(exc.id)
        urls = call_exchange(default_client(), name, "urls")
        if urls isa AbstractDict
            urls_dict = Dict(pairs(urls))
            haskey(urls_dict, "apiBackup") || get(urls_dict, "apiBackup", nothing) !== nothing
        else
            false
        end
    catch
        false
    end
end

@doc "Check if market has percentage or absolute fees."
function ispercentage(mkt)
    something(get(mkt, "percentage", true), true)
end

@doc "Enable or disable rate limit via gateway."
function ratelimit!(exc::Exchange, flag=true)
    try
        name = string(exc.id)
        call_exchange(default_client(), name, "enableRateLimit", query=Dict("flag" => string(flag)))
    catch
        @debug "ratelimit! via gateway failed"
    end
end

@doc "Get exchange rate limit."
function ratelimit(exc::Exchange)
    try
        name = string(exc.id)
        rl = call_exchange(default_client(), name, "rateLimit")
        rl isa Number ? Float64(rl) : 0.0
    catch
        0.0
    end
end

@doc "Check if rate limit is enabled via gateway."
function isratelimited(exc::Exchange)
    try
        name = string(exc.id)
        enabled = call_exchange(default_client(), name, "enableRateLimit")
        enabled == true
    catch
        false
    end
end

@doc "Get exchange rate limit tokens."
function ratelimit_tokens(exc::Exchange)
    try
        name = string(exc.id)
        rlt = call_exchange(default_client(), name, "rateLimitTokens")
        rlt isa Number ? Float64(rlt) : 0.0
    catch
        0.0
    end
end

@doc "Calculate max concurrent requests from rate limits."
function ratelimit_njobs(exc::Exchange)
    rl = ratelimit(exc)
    rlt = ratelimit_tokens(exc)
    rlt > 0 ? round(Int, rl / rlt, RoundDown) : 1
end

@doc "Set exchange timeout (milliseconds) via gateway."
function timeout!(exc::Exchange, v=5000)
    try
        name = string(exc.id)
        call_exchange(default_client(), name, "timeout", query=Dict("value" => string(v)))
    catch
        @debug "timeout! via gateway failed"
    end
end

@doc "Get exchange timeout in milliseconds."
function gettimeout(exc::Exchange)::Millisecond
    try
        name = string(exc.id)
        to = call_exchange(default_client(), name, "timeout")
        to isa Number ? Millisecond(Int(to)) : Millisecond(5000)
    catch
        Millisecond(5000)
    end
end

@doc "Check that the exchange timeout is not too low wrt the interval."
function check_timeout(exc::Exchange, interval=Second(5))
    t = gettimeout(exc)
    @assert Millisecond(interval) <= t "Interval ($interval) shouldn't be lower than the exchange set timeout ($t)"
end

@doc "The current timestamp from the exchange via gateway."
function timestamp(exc::Exchange)
    try
        name = string(exc.id)
        ts = call_exchange(default_client(), name, "fetchTime")
        ts isa Number ? Int64(ts) : Int64(0)
    catch
        Int64(0)
    end
end

@doc "Get exchange time as DateTime via gateway."
function Base.time(exc::Exchange)
    ts = timestamp(exc)
    ts > 0 ? dt(Float64(ts)) : dt(0.0)
end

@doc "Returns the matching *futures* exchange instance, if it exists, or the input exchange otherwise."
function futures(exc::Exchange)
    futures_sym = get(futures_exchange, exc.id, exc.id)
    futures_sym != exc.id ? getexchange!(futures_sym; sandbox=false, account=account(exc)) : exc
end

const CCXT_REQUIRED_LOCAL4 = (
    (nothing, :fetchOHLCV),
    (:fetchBalance,),
    (:fetchPosition, :fetchPositions),
    (:cancelOrder, :cancelOrders, :cancelAllOrders),
    (:createOrder, :createPostOnlyOrder, :createReduceOnlyOrder),
    (:fetchMarkets,),
    (:fetchTrades, :watchTrades),
    (:fetchOrder, :fetchOrders, :watchOrders),
    (nothing, :fetchLeverageTiers),
    (:fetchTickers, :fetchTicker, :watchTickers, :watchTicker),
    (:fetchOrderBooks, :fetchOrderBook, :watchOrderBooks, :watchOrderBook),
    (nothing, :fetchCurrencies),
)
function _print_missing(exc, missing_funcs, func_type)
    nmis = length(missing_funcs)
    if nmis == 0
        tprint("{cyan}$(exc.name){/cyan} supports {bold}all{/bold} $func_type functions!")
    else
        tprint(
            "{bold}$nmis{/bold} functions are {bold}not{/bold} supported by {cyan}$(exc.name){/cyan}\n",
        )
        for f in missing_funcs
            tprint(stdout, string("{yellow}", f, "{/yellow}\n"))
        end
        flush(stdout)
    end
end
function _checkfunc(exc, funcs, missing_funcs, total)
    any = isnothing(first(funcs))
    for func in funcs
        isnothing(func) && continue
        if has(exc, func)
            any = true
            total[] += 1
        else
            push!(missing_funcs, func)
        end
    end
    any
end
function _print_total(total, max_total)
    red = RGB(1, 0, 0)
    green = RGB(0, 1, 0)
    x = total / max_total
    color = interpolate_color(green, red, x)
    tprint(
        string("\n{bold}Total score:{/bold} {$color}$total/$max_total{/$color}\n");
        highlight=false,
    )
end

function _print_blockers(exc, blockers, func_type)
    nblocks = length(blockers)
    if nblocks == 0
        tprint("\n{cyan}$(exc.name){/cyan} supports {bold}$func_type{/bold} functionality!")
    else
        tprint(
            "\nThere are {bold}$nblocks{/bold} blockers for {bold}$func_type{/bold} functionality for {cyan}$(exc.name){/cyan}\n",
        )
        for funcs in blockers
            tprint(
                stdout,
                string(
                    "\n {white}{bold}-{/bold}{/white} ",
                    (string("{red}", f, "{/red} ") for f in funcs)...,
                ),
            )
        end
        tprint("\n")
        flush(stdout)
    end
end

function interpolate_color(c1, c2, x)
    v = clamp(x, 0.01, 0.99)
    r = c1.r + (c2.r - c1.r) * v
    g = c1.g + (c2.g - c1.g) * v
    b = c1.b + (c2.b - c1.b) * v
    return RGB(r, g, b)
end

const CCXT_REQUIRED_LIVE2 = ((:setMarginMode,), (:setPositionMode,))

@doc """Checks if the exchange instance supports all the calls required by Planar.

$(TYPEDSIGNATURES)

- `exc`: an Exchange object to perform the check on.
- `type` (optional, default is `:basic`): a symbol representing the type of check to perform.
"""
function check(exc::Exchange; type=:basic)
    missing_funcs = Set()
    blockers = Set()
    total = Ref(0)
    max_total = 0
    allfuncs = if type == :basic
        CCXT_REQUIRED_LOCAL4
    elseif type == :live
        CCXT_REQUIRED_LIVE2
    else
        error()
    end
    for funcs in allfuncs
        max_total += length(funcs) - ifelse(isnothing(first(funcs)), 1, 0)
        any = _checkfunc(exc, funcs, missing_funcs, total)
        any || push!(blockers, funcs)
    end
    _print_missing(exc, missing_funcs, type)
    _print_blockers(exc, blockers, type)
    _print_total(total[], max_total)
end
