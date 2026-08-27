module DefiLlama

using PlanarCore.Ccxt: HTTP, JSON3
const URIs = HTTP.URIs
using ..Watchers
using PlanarCore.Lang: @kget!, Option
using PlanarCore.Misc
using PlanarCore.Misc.TimeToLive
using PlanarCore.TimeTicks
using PlanarCore.TimeTicks: timestamp
using ..Watchers: jsontodict

const API_URL = "https://api.llama.fi"
const API_HEADERS = ["Accept-Encoding" => "deflate,gzip", "Accept" => "application/json"]

const ApiPaths = (;
    protocols="/protocols",
    protocol="/protocol",
    chains="/chains",
    tvl="/tvl",
    stablecoins="/stablecoins",
    stablecoin="/stablecoin",
    stablecoincharts="/stablecoins",
    stablecoin_charts="/stablecoincharts",
    supply_ratio="/stablecoinSupplyRatio",
)

const last_query = Ref(DateTime(0))
const RATE_LIMIT = Ref(Millisecond(1000))  # 1 second between requests
const STATUS = Ref{Int}(0)
const RETRY_COUNT = Ref(0)
const MAX_RETRIES = 5
const BACKOFF_BASE = 1000

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

function _get(path, query=nothing)
    ratelimit()
    resp = try
        _http_get[](absuri(path, API_URL); query, headers=API_HEADERS)
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
                @warn "defillama: rate limited, retrying" path retry=RETRY_COUNT[] wait_time
                sleep(wait_time)
                return _get(path, query)
            else
                @error "defillama: max retries exceeded" path retries=RETRY_COUNT[]
                RETRY_COUNT[] = 0
            end
        elseif resp.status == 401 || resp.status == 403
            @warn "defillama: auth error" path status=resp.status
        end
        @assert resp.status == 200 "defillama: $path failed with status $(resp.status)"
        RETRY_COUNT[] = 0
        json = JSON3.read(resp.body)
        return json
    else
        throw(resp)
    end
end

@doc """Fetch all protocols from DefiLlama."""
function protocols(; include_tvl=false)
    path = include_tvl ? ApiPaths.protocols * "?includeTvl=true" : ApiPaths.protocols
    _get(path)
end

@doc """Fetch a specific protocol from DefiLlama by slug."""
function protocol(slug::AbstractString; include_tvl=false)
    query = include_tvl ? ("includeTvl" => "true") : nothing
    _get(ApiPaths.protocol * "/" * slug, query)
end

@doc """Fetch TVL for a specific protocol."""
function protocol_tvl(slug::AbstractString)
    protocol(slug; include_tvl=true)
end

@doc """Fetch all chains from DefiLlama."""
function chains()
    _get(ApiPaths.chains)
end

@doc """Fetch all stablecoins from DefiLlama."""
function stablecoins()
    _get(ApiPaths.stablecoins)
end

@doc """Fetch a specific stablecoin from DefiLlama."""
function stablecoin(id::AbstractString)
    _get(ApiPaths.stablecoin * "/" * id)
end

@doc """Fetch stablecoin charts (circulating, unreleased, bridged) from DefiLlama."""
function stablecoin_charts(id::AbstractString)
    _get(ApiPaths.stablecoincharts * "/" * id)
end

@doc """Fetch stablecoin supply ratio for a protocol."""
function protocol_supply_ratio(slug::AbstractString)
    _get(ApiPaths.supply_ratio * "/" * slug)
end

export protocols, protocol, protocol_tvl, chains, stablecoins, stablecoin, stablecoin_charts, protocol_supply_ratio, ratelimit, set_http_get!

end # module DefiLlama