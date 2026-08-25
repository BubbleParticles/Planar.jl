module Glassnode

using PlanarCore.Ccxt: HTTP, URIs, JSON3
using ..Watchers
using PlanarCore.Lang: @kget!, Option
using PlanarCore.Misc
using PlanarCore.Misc.TimeToLive
using PlanarCore.TimeTicks
using PlanarCore.TimeTicks: timestamp
using ..Watchers: jsontodict

const API_URL = "https://api.glassnode.com"
const API_HEADERS = ["Accept-Encoding" => "deflate,gzip", "Accept" => "application/json"]

const ApiPaths = (;
    active_addresses="/v1/metrics/addresses/active_count",
    new_addresses="/v1/metrics/addresses/new_count",
    zero_balance_addresses="/v1/metrics/addresses/zero_balance_count",
    holders_profit="/v1/metrics/holders/profit_count",
    holders_loss="/v1/metrics/holders/loss_count",
    holders_breakeven="/v1/metrics/holders/breakeven_count",
    supply_in_profit="/v1/metrics/supply/in_profit",
    supply_in_loss="/v1/metrics/supply/in_loss",
    large_tx_count="/v1/metrics/transactions/count_large",
    large_tx_volume_usd="/v1/metrics/transactions/volume_large_usd",
    large_tx_volume_native="/v1/metrics/transactions/volume_large_native",
    large_tx_avg_size_usd="/v1/metrics/transactions/avg_size_large_usd",
    large_tx_avg_size_native="/v1/metrics/transactions/avg_size_large_native",
)

const last_query = Ref(DateTime(0))
const RATE_LIMIT = Ref(Millisecond(2000))  # 2 seconds between requests
const STATUS = Ref{Int}(0)
const RETRY_COUNT = Ref(0)
const MAX_RETRIES = 5
const BACKOFF_BASE = 2000

@doc "Allows only 1 query every $(RATE_LIMIT[]) seconds."
ratelimit() = sleep(max(Second(0), (last_query[] - now()) + RATE_LIMIT[]))

# Injectable HTTP function for testing
const _http_get = Ref{Function}(HTTP.get)

@doc """
Set a custom HTTP GET function for testing purposes.
This allows mocking HTTP responses in tests.
"""
function set_http_get!(f::Function)
    _http_get[] = f
end

function _apikey()
    key = get(ENV, "GLASSNODE_API_KEY", "")
    if isempty(key)
        @warn "GLASSNODE_API_KEY not set in environment"
    end
    key
end

function _get(path, query=nothing)
    ratelimit()
    query_dict = query isa Nothing ? Dict{String,String}() : Dict{String,String}(query...)
    query_dict["a"] = _apikey()
    query_dict["i"] = "24h"  # Default interval
    
    resp = try
        _http_get[](absuri(path, API_URL); query=query_dict, headers=API_HEADERS)
    catch e
        e
    end
    last_query[] = now()
    if hasproperty(resp, :status)
        STATUS[] = resp.status
        if resp.status == 429
            RETRY_COUNT[] += 1
            if RETRY_COUNT[] <= MAX_RETRIES
                wait_time = RATE_LIMIT[] + Millisecond(BACKOFF_BASE * RETRY_COUNT[])
                @warn "glassnode: rate limited, retrying" path retry=RETRY_COUNT[] wait_time
                sleep(wait_time)
                return _get(path, query)
            else
                @error "glassnode: max retries exceeded" path retries=RETRY_COUNT[]
                RETRY_COUNT[] = 0
            end
        elseif resp.status == 401 || resp.status == 403
            @warn "glassnode: auth error" path status=resp.status
        end
        @assert resp.status == 200 "glassnode: $path failed with status $(resp.status)"
        RETRY_COUNT[] = 0
        json = JSON3.read(resp.body)
        return json
    else
        throw(resp)
    end
end

@doc """Fetch active addresses for an asset."""
function active_addresses(asset::AbstractString; interval="24h")
    _get(ApiPaths.active_addresses, ("a" => _apikey(), "s" => asset, "i" => interval))
end

@doc """Fetch new addresses for an asset."""
function new_addresses(asset::AbstractString; interval="24h")
    _get(ApiPaths.new_addresses, ("a" => _apikey(), "s" => asset, "i" => interval))
end

@doc """Fetch zero balance addresses for an asset."""
function zero_balance_addresses(asset::AbstractString; interval="24h")
    _get(ApiPaths.zero_balance_addresses, ("a" => _apikey(), "s" => asset, "i" => interval))
end

@doc """Fetch holders in profit for an asset."""
function holders_profit(asset::AbstractString; interval="24h")
    _get(ApiPaths.holders_profit, ("a" => _apikey(), "s" => asset, "i" => interval))
end

@doc """Fetch holders in loss for an asset."""
function holders_loss(asset::AbstractString; interval="24h")
    _get(ApiPaths.holders_loss, ("a" => _apikey(), "s" => asset, "i" => interval))
end

@doc """Fetch holders at breakeven for an asset."""
function holders_breakeven(asset::AbstractString; interval="24h")
    _get(ApiPaths.holders_breakeven, ("a" => _apikey(), "s" => asset, "i" => interval))
end

@doc """Fetch supply in profit for an asset."""
function supply_in_profit(asset::AbstractString; interval="24h")
    _get(ApiPaths.supply_in_profit, ("a" => _apikey(), "s" => asset, "i" => interval))
end

@doc """Fetch supply in loss for an asset."""
function supply_in_loss(asset::AbstractString; interval="24h")
    _get(ApiPaths.supply_in_loss, ("a" => _apikey(), "s" => asset, "i" => interval))
end

@doc """Fetch large transaction count for an asset."""
function large_tx_count(asset::AbstractString; interval="24h")
    _get(ApiPaths.large_tx_count, ("a" => _apikey(), "s" => asset, "i" => interval))
end

@doc """Fetch large transaction volume USD for an asset."""
function large_tx_volume_usd(asset::AbstractString; interval="24h")
    _get(ApiPaths.large_tx_volume_usd, ("a" => _apikey(), "s" => asset, "i" => interval))
end

@doc """Fetch large transaction volume native for an asset."""
function large_tx_volume_native(asset::AbstractString; interval="24h")
    _get(ApiPaths.large_tx_volume_native, ("a" => _apikey(), "s" => asset, "i" => interval))
end

@doc """Fetch large transaction avg size USD for an asset."""
function large_tx_avg_size_usd(asset::AbstractString; interval="24h")
    _get(ApiPaths.large_tx_avg_size_usd, ("a" => _apikey(), "s" => asset, "i" => interval))
end

@doc """Fetch large transaction avg size native for an asset."""
function large_tx_avg_size_native(asset::AbstractString; interval="24h")
    _get(ApiPaths.large_tx_avg_size_native, ("a" => _apikey(), "s" => asset, "i" => interval))
end

# Combined endpoints for watchers
@doc """Fetch combined holders profit data (profit, loss, breakeven, supply in profit/loss)."""
function holders_profit_combined(asset::AbstractString; interval="24h")
    # Glassnode returns combined data for holders profit endpoint
    _get(ApiPaths.holders_profit, ("a" => _apikey(), "s" => asset, "i" => interval))
end

@doc """Fetch combined large movements data."""
function large_movements(asset::AbstractString; interval="24h")
    # Glassnode returns combined data for large transactions
    _get(ApiPaths.large_tx_count, ("a" => _apikey(), "s" => asset, "i" => interval))
end

export active_addresses, new_addresses, zero_balance_addresses, holders_profit, holders_loss, holders_breakeven, supply_in_profit, supply_in_loss, large_tx_count, large_tx_volume_usd, large_tx_volume_native, large_tx_avg_size_usd, large_tx_avg_size_native, holders_profit_combined, large_movements, ratelimit, set_http_get!

end # module Glassnode