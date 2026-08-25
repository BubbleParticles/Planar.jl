module BlockchainAPI

using PlanarCore.Ccxt: HTTP, JSON3, URIs
using PlanarCore.Data.DataFrames
import Dates: DateTime, Millisecond, now, unix2datetime, datetime2unix
using PlanarCore.Misc
using PlanarCore.Lang: Option
using ..Watchers: jsontodict
export DefiLlama, Glassnode, tvl, stablecoins, stablecoin_chart, supply_ratio, active_addresses, holders_profit, large_movements, set_mock_defillama_get!, set_mock_stablecoins_get!, set_mock_glassnode_get!, clear_mocks!

# =============================================================================
# DefiLlama API (no API key required)
# =============================================================================

const DEFI_LLAMA_URL = "https://api.llama.fi"
const STABLECOINS_URL = "https://stablecoins.llama.fi"
const DEFI_LLAMA_HEADERS = ["Accept" => "application/json", "Accept-Encoding" => "deflate,gzip"]

const DefiLlamaPaths = (
    chains = "/v2/chains",
    chain_tvl = "/v2/chains",           # /v2/chains/{chain}
    protocols = "/protocols",            # /protocols/{protocol}
    protocol_tvl = "/protocol",          # /protocol/{protocol}
    yields = "/yields/pools",
    stablecoins = "/stablecoins",
    stablecoin_charts = "/stablecoincharts",  # /stablecoincharts/{stablecoin} or /stablecoincharts/all
)

const last_defillama_query = Ref(DateTime(0))
const DEFI_LLAMA_RATE_LIMIT = Ref(Millisecond(1000))

ratelimit_defillama() = sleep(max(Millisecond(0), (last_defillama_query[] - now()) + DEFI_LLAMA_RATE_LIMIT[]))

function defillama_get(path::String, query=nothing; base_url=DEFI_LLAMA_URL)
    ratelimit_defillama()
    url = URIs.URI(base_url; path=path, query=query)
    resp = try
        HTTP.get(url; headers=DEFI_LLAMA_HEADERS)
    catch e
        @error "DefiLlama request failed" path exception=e
        rethrow(e)
    end
    last_defillama_query[] = now()
    if resp.status != 200
        @error "DefiLlama API error" path status=resp.status body=String(resp.body)
        error("DefiLlama: $path failed with status $(resp.status)")
    end
    JSON3.read(resp.body)
end

function stablecoins_get(path::String, query=nothing)
    defillama_get(path, query; base_url=STABLECOINS_URL)
end

"""
    tvl(chain::Union{String, Nothing}=nothing)

Get TVL data from DefiLlama.
- If `chain` is `nothing`, returns TVL for all chains.
- If `chain` is a string (e.g., "Ethereum"), returns historical TVL for that chain.
"""
function tvl(chain::Union{String, Nothing}=nothing)
    if isnothing(chain)
        json = _defillama_get(DefiLlamaPaths.chains)
        return _parse_chains_tvl(json)
    else
        path = joinpath(DefiLlamaPaths.chain_tvl, chain)
        json = _defillama_get(path)
        return _parse_chain_tvl_history(json, chain)
    end
end

function _parse_chains_tvl(json)
    results = Vector{NamedTuple{(:name, :symbol, :gecko_id, :chain_id, :tvl, :timestamp), Tuple{String, String, String, Int, Float64, DateTime}}}()
    now_ts = now()
    for item in json
        push!(results, (
            name = get(item, "name", ""),
            symbol = get(item, "tokenSymbol", ""),
            gecko_id = get(item, "gecko_id", ""),
            chain_id = get(item, "chainId", 0),
            tvl = Float64(get(item, "tvl", 0.0)),
            timestamp = now_ts,
        ))
    end
    DataFrame(results)
end

function _parse_chain_tvl_history(json, chain::String)
    # Response is array of {date: timestamp, totalLiquidityUSD: float}
    results = Vector{NamedTuple{(:chain, :date, :tvl), Tuple{String, DateTime, Float64}}}()
    for item in json
        ts = get(item, "date", 0)
        tvl = Float64(get(item, "totalLiquidityUSD", 0.0))
        push!(results, (chain=chain, date=unix2datetime(ts), tvl=tvl))
    end
    DataFrame(results)
end

"""
    stablecoins()

Get all stablecoins data from DefiLlama.
Returns a DataFrame with stablecoin info including circulating supply by chain.
"""
function stablecoins()
    json = _stablecoins_get(DefiLlamaPaths.stablecoins)
    _parse_stablecoins(json)
end

function _parse_stablecoins(json)
    results = Vector{NamedTuple{(:id, :name, :symbol, :gecko_id, :peg_type, :peg_mechanism, :circulating_usd, :timestamp), Tuple{String, String, String, String, String, String, Float64, DateTime}}}()
    now_ts = now()
    pegged_assets = get(json, "peggedAssets", json)
    for asset in pegged_assets
        circulating = get(asset, "circulating", Dict())
        circulating_usd = Float64(get(circulating, "peggedUSD", 0.0))
        push!(results, (
            id = string(get(asset, "id", "")),
            name = get(asset, "name", ""),
            symbol = get(asset, "symbol", ""),
            gecko_id = get(asset, "gecko_id", ""),
            peg_type = get(asset, "pegType", ""),
            peg_mechanism = get(asset, "pegMechanism", ""),
            circulating_usd = circulating_usd,
            timestamp = now_ts,
        ))
    end
    DataFrame(results)
end

"""
    stablecoin_chart(stablecoin_id::String)

Get historical supply chart for a specific stablecoin.
"""
function stablecoin_chart(stablecoin_id::String)
    path = joinpath(DefiLlamaPaths.stablecoin_charts, stablecoin_id)
    json = _stablecoins_get(path)
    _parse_stablecoin_chart(json, stablecoin_id)
end

"""
    supply_ratio()

Get total stablecoin supply ratio (all stablecoins combined).
"""
function supply_ratio()
    path = joinpath(DefiLlamaPaths.stablecoin_charts, "all")
    json = _stablecoins_get(path)
    _parse_supply_ratio(json)
end

function _parse_stablecoin_chart(json, stablecoin_id::String)
    results = Vector{NamedTuple{(:stablecoin, :date, :circulating, :circulating_usd), Tuple{String, DateTime, Float64, Float64}}}()
    for item in json
        ts = get(item, "date", 0)
        circulating = Float64(get(get(item, "totalCirculating", Dict()), "peggedUSD", 0.0))
        circulating_usd = Float64(get(get(item, "totalCirculatingUSD", Dict()), "peggedUSD", 0.0))
        push!(results, (
            stablecoin = stablecoin_id,
            date = unix2datetime(ts),
            circulating = circulating,
            circulating_usd = circulating_usd,
        ))
    end
    DataFrame(results)
end

function _parse_supply_ratio(json)
    results = Vector{NamedTuple{(:date, :total_circulating, :total_circulating_usd), Tuple{DateTime, Float64, Float64}}}()
    for item in json
        ts = get(item, "date", 0)
        circulating = Float64(get(get(item, "totalCirculating", Dict()), "peggedUSD", 0.0))
        circulating_usd = Float64(get(get(item, "totalCirculatingUSD", Dict()), "peggedUSD", 0.0))
        push!(results, (
            date = unix2datetime(ts),
            total_circulating = circulating,
            total_circulating_usd = circulating_usd,
        ))
    end
    DataFrame(results)
end

# =============================================================================
# Glassnode API (requires GLASSNODE_KEY environment variable)
# =============================================================================

const GLASSNODE_URL = "https://api.glassnode.com"
const GLASSNODE_HEADERS = ["Accept" => "application/json"]

const GlassnodePaths = (
    active_addresses = "/v1/metrics/addresses/active_count",
    holders_profit = "/v1/metrics/indicators/holders_profit",
    large_movements = "/v1/metrics/transactions/transfers_volume_large",
    nvt_ratio = "/v1/metrics/indicators/nvt",
    mvrv_ratio = "/v1/metrics/indicators/mvrv",
    exchange_balance = "/v1/metrics/distribution/balance_exchanges",
)

function _glassnode_key()
    key = get(ENV, "GLASSNODE_KEY", nothing)
    isnothing(key) && error("GLASSNODE_KEY environment variable not set")
    key
end

const last_glassnode_query = Ref(DateTime(0))
const GLASSNODE_RATE_LIMIT = Ref(Millisecond(2000))

ratelimit_glassnode() = sleep(max(Millisecond(0), (last_glassnode_query[] - now()) + GLASSNODE_RATE_LIMIT[]))

function glassnode_get(path::String, query=nothing; asset="BTC")
    ratelimit_glassnode()
    key = _glassnode_key()
    q = merge(Dict("a" => asset, "api_key" => key), query !== nothing ? Dict(query) : Dict())
    url = URIs.URI(GLASSNODE_URL; path=path, query=q)
    resp = try
        HTTP.get(url; headers=GLASSNODE_HEADERS)
    catch e
        @error "Glassnode request failed" path exception=e
        rethrow(e)
    end
    last_glassnode_query[] = now()
    if resp.status != 200
        @error "Glassnode API error" path status=resp.status body=String(resp.body)
        error("Glassnode: $path failed with status $(resp.status)")
    end
    JSON3.read(resp.body)
end

"""
    active_addresses(asset::String="BTC"; since::Union{DateTime, Nothing}=nothing, until::Union{DateTime, Nothing}=nothing, interval::String="24h")

Get active addresses count for an asset from Glassnode.
Returns DataFrame with columns: asset, date, active_addresses
"""
function active_addresses(asset::String="BTC"; since::Union{DateTime, Nothing}=nothing, until::Union{DateTime, Nothing}=nothing, interval::String="24h")
    q = Dict("i" => interval)
    !isnothing(since) && (q["s"] = string(round(Int, datetime2unix(since))))
    !isnothing(until) && (q["u"] = string(round(Int, datetime2unix(until))))
    json = _glassnode_get(GlassnodePaths.active_addresses, q; asset=asset)
    _parse_active_addresses(json, asset)
end

function _parse_active_addresses(json, asset::String)
    results = Vector{NamedTuple{(:asset, :date, :active_addresses), Tuple{String, DateTime, Int64}}}()
    for item in json
        t = get(item, "t", 0)
        v = get(item, "v", 0)
        push!(results, (asset=asset, date=unix2datetime(t), active_addresses=Int64(v)))
    end
    DataFrame(results)
end

"""
    holders_profit(asset::String="BTC"; since::Union{DateTime, Nothing}=nothing, until::Union{DateTime, Nothing}=nothing, interval::String="24h")

Get holders in profit percentage for an asset from Glassnode.
Returns DataFrame with columns: asset, date, holders_profit_pct
"""
function holders_profit(asset::String="BTC"; since::Union{DateTime, Nothing}=nothing, until::Union{DateTime, Nothing}=nothing, interval::String="24h")
    q = Dict("i" => interval)
    !isnothing(since) && (q["s"] = string(round(Int, datetime2unix(since))))
    !isnothing(until) && (q["u"] = string(round(Int, datetime2unix(until))))
    json = _glassnode_get(GlassnodePaths.holders_profit, q; asset=asset)
    _parse_holders_profit(json, asset)
end

function _parse_holders_profit(json, asset::String)
    results = Vector{NamedTuple{(:asset, :date, :holders_profit_pct), Tuple{String, DateTime, Float64}}}()
    for item in json
        t = get(item, "t", 0)
        v = Float64(get(item, "v", 0.0))
        push!(results, (asset=asset, date=unix2datetime(t), holders_profit_pct=v))
    end
    DataFrame(results)
end

"""
    large_movements(asset::String="BTC"; since::Union{DateTime, Nothing}=nothing, until::Union{DateTime, Nothing}=nothing, interval::String="24h")

Get large transaction volume (whale movements) for an asset from Glassnode.
Returns DataFrame with columns: asset, date, volume_usd, count
"""
function large_movements(asset::String="BTC"; since::Union{DateTime, Nothing}=nothing, until::Union{DateTime, Nothing}=nothing, interval::String="24h")
    q = Dict("i" => interval)
    !isnothing(since) && (q["s"] = string(round(Int, datetime2unix(since))))
    !isnothing(until) && (q["u"] = string(round(Int, datetime2unix(until))))
    json = _glassnode_get(GlassnodePaths.large_movements, q; asset=asset)
    _parse_large_movements(json, asset)
end

function _parse_large_movements(json, asset::String)
    results = Vector{NamedTuple{(:asset, :date, :volume_usd, :count), Tuple{String, DateTime, Float64, Int64}}}()
    for item in json
        t = get(item, "t", 0)
        v = Float64(get(item, "v", 0.0))
        # Glassnode large movements returns volume in USD
        push!(results, (asset=asset, date=unix2datetime(t), volume_usd=v, count=Int64(0)))
    end
    DataFrame(results)
end

# =============================================================================
# Test Helpers - Mock injection for testing
# =============================================================================

const _mock_defillama_get = Ref{Union{Function, Nothing}}(nothing)
const _mock_stablecoins_get = Ref{Union{Function, Nothing}}(nothing)
const _mock_glassnode_get = Ref{Union{Function, Nothing}}(nothing)

"""
    set_mock_defillama_get!(f::Function)

Set a mock function for DefiLlama API calls (for testing).
The mock function should accept (path, query) and return parsed JSON.
"""
function set_mock_defillama_get!(f::Function)
    _mock_defillama_get[] = f
end

"""
    set_mock_stablecoins_get!(f::Function)

Set a mock function for Stablecoins API calls (for testing).
"""
function set_mock_stablecoins_get!(f::Function)
    _mock_stablecoins_get[] = f
end

"""
    set_mock_glassnode_get!(f::Function)

Set a mock function for Glassnode API calls (for testing).
"""
function set_mock_glassnode_get!(f::Function)
    _mock_glassnode_get[] = f
end

"""
    clear_mocks!()

Clear all mock functions.
"""
function clear_mocks!()
    _mock_defillama_get[] = nothing
    _mock_stablecoins_get[] = nothing
    _mock_glassnode_get[] = nothing
end

# Internal functions that check for mocks (used by the public API functions)
function _defillama_get(path::String, query=nothing; base_url=DEFI_LLAMA_URL)
    if !isnothing(_mock_defillama_get[])
        return _mock_defillama_get[](path, query)
    end
    defillama_get(path, query; base_url=base_url)
end

function _stablecoins_get(path::String, query=nothing)
    if !isnothing(_mock_stablecoins_get[])
        return _mock_stablecoins_get[](path, query)
    end
    stablecoins_get(path, query)
end

function _glassnode_get(path::String, query=nothing; asset="BTC")
    if !isnothing(_mock_glassnode_get[])
        return _mock_glassnode_get[](path, query; asset=asset)
    end
    glassnode_get(path, query; asset=asset)
end

# Override the public functions to use mockable internals
# (The public functions tvl, stablecoins, etc. will call these internal versions)

end # module BlockchainAPI