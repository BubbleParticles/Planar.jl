module AlphaVantage
using HTTP
using URIs
using JSON3
using ..Watchers
using PlanarCore.Lang: @kget!, Option
using PlanarCore.Misc
using PlanarCore.TimeTicks
using PlanarCore.TimeTicks: timestamp
using ..Watchers: jsontodict

const API_URL = "https://www.alphavantage.co"
const API_HEADERS = ["Accept-Encoding" => "deflate,gzip", "Accept" => "application/json"]

const ApiPaths = (
    query="/query",
)

const last_query = Ref(DateTime(0))
const RATE_LIMIT = Ref(Millisecond(12000))  # 5 requests per minute for free tier

@doc "Allows only 1 query every $(RATE_LIMIT[]) milliseconds."
function ratelimit()
    sleep(max(Second(0), (last_query[] - now()) + RATE_LIMIT[]))
end

# Injectable HTTP function for testing
const _http_get = Ref{Function}(HTTP.get)

@doc """
    set_http_get!(f::Function)

Inject a custom HTTP GET function for testing. The function should have the signature
`f(url::String; query=nothing, headers=nothing) -> HTTP.Response`.
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
        if resp.status == 429
            @warn "alphavantage: rate limited" path
        elseif resp.status == 401 || resp.status == 403
            @warn "alphavantage: auth error" path status=resp.status
        end
        @assert resp.status == 200 "alphavantage: $path failed with status $(resp.status)"
        json = JSON3.read(resp.body)
        return json
    else
        throw(resp)
    end
end

function _apikey()
    key = get(ENV, "ALPHA_VANTAGE_KEY", nothing)
    isnothing(key) && return "mock"
    key
end

"""
    fetch_daily(symbol::AbstractString; outputsize="compact", datatype="json")

Fetch daily time series for a stock symbol.

# Arguments
- `symbol`: Stock symbol (e.g., "AAPL", "MSFT")
- `outputsize`: "compact" (last 100 data points) or "full" (full history)
- `datatype`: "json" or "csv"

# Returns
Parsed JSON3 data with time series.
"""
function fetch_daily(symbol::AbstractString; outputsize="compact", datatype="json")
    query = (
        "function" => "TIME_SERIES_DAILY",
        "symbol" => symbol,
        "outputsize" => outputsize,
        "datatype" => datatype,
        "apikey" => _apikey(),
    )
    _get(ApiPaths.query, query)
end

"""
    fetch_fx(from_currency::AbstractString, to_currency::AbstractString; outputsize="compact", datatype="json")

Fetch daily FX (foreign exchange) rates.

# Arguments
- `from_currency`: Base currency (e.g., "USD", "EUR")
- `to_currency`: Quote currency (e.g., "EUR", "JPY")
- `outputsize`: "compact" or "full"
- `datatype`: "json" or "csv"

# Returns
Parsed JSON3 data with FX time series.
"""
function fetch_fx(from_currency::AbstractString, to_currency::AbstractString; outputsize="compact", datatype="json")
    query = (
        "function" => "FX_DAILY",
        "from_symbol" => from_currency,
        "to_symbol" => to_currency,
        "outputsize" => outputsize,
        "datatype" => datatype,
        "apikey" => _apikey(),
    )
    _get(ApiPaths.query, query)
end

"""
    fetch_crypto(symbol::AbstractString; market="USD", datatype="json")

Fetch cryptocurrency data.

# Arguments
- `symbol`: Crypto symbol (e.g., "BTC", "ETH")
- `market`: Market currency (default "USD")
- `datatype`: "json" or "csv"

# Returns
Parsed JSON3 data with crypto time series.
"""
function fetch_crypto(symbol::AbstractString; market="USD", datatype="json")
    query = (
        "function" => "DIGITAL_CURRENCY_DAILY",
        "symbol" => symbol,
        "market" => market,
        "datatype" => datatype,
        "apikey" => _apikey(),
    )
    _get(ApiPaths.query, query)
end

# Convenience function to parse daily time series response
function parse_daily_response(json)
    # Alpha Vantage returns "Time Series (Daily)" key (JSON3 yields Symbol keys)
    ks = collect(keys(json)); ts_key = findfirst(k -> occursin("Time Series", string(k)), ks)
    if isnothing(ts_key)
        @warn "alphavantage: unexpected response format" keys=collect(keys(json))
        return nothing
    end
    json[ks[ts_key]]
end

function parse_fx_response(json)
    ks = collect(keys(json)); ts_key = findfirst(k -> occursin("Time Series FX", string(k)), ks)
    if isnothing(ts_key)
        @warn "alphavantage: unexpected FX response format" keys=collect(keys(json))
        return nothing
    end
    json[ks[ts_key]]
end

function parse_crypto_response(json)
    ks = collect(keys(json)); ts_key = findfirst(k -> occursin("Time Series", string(k)), ks)
    if isnothing(ts_key)
        @warn "alphavantage: unexpected crypto response format" keys=collect(keys(json))
        return nothing
    end
    json[ks[ts_key]]
end

export
    fetch_daily,
    fetch_fx,
    fetch_crypto,
    parse_daily_response,
    parse_fx_response,
    parse_crypto_response,
    set_http_get!

end # module AlphaVantage