module DBNomics
using PlanarCore.Ccxt: HTTP, URIs, JSON3
using ..Watchers
using PlanarCore.Lang: Option, @kget!
using PlanarCore.Misc: Config
using PlanarCore.Misc.TimeToLive: safettl
using PlanarCore.TimeTicks
using PlanarCore.TimeTicks: timestamp
using ..Watchers: jsontodict

const API_URL = "https://api.db.nomics.world"
const API_HEADERS = ["Accept-Encoding" => "deflate,gzip", "Accept" => "application/json"]

const ApiPaths = (
    providers="/v22/providers",
    provider="/v22/providers",
    datasets="/v22/datasets",
    dataset="/v22/datasets",
    series="/v22/series",
    series_values="/v22/series/values",
)

const last_query = Ref(DateTime(0))
const RATE_LIMIT = Ref(Millisecond(1000))  # 1 second between requests
const STATUS = Ref{Int}(0)

# Injectable HTTP function for testing
const _http_get = Ref{Function}(HTTP.get)

@doc """
Set the HTTP GET function for testing/mocking.
"""
function set_http_get!(f::Function)
    _http_get[] = f
end

@doc """Allows only 1 query every $(RATE_LIMIT[]) seconds."""
ratelimit() = sleep(max(Second(0), (last_query[] - now()) + RATE_LIMIT[]))

function get(path, query=nothing)
    ratelimit()
    
    # Construct the full URL
    full_url = string(API_URL, path)
    
    resp = try
        _http_get[](full_url; query, headers=API_HEADERS)
    catch e
        e
    end
    last_query[] = now()
    if hasproperty(resp, :status)
        STATUS[] = resp.status
        if resp.status == 429
            @warn "dbnomics: rate limited" path
            sleep(Second(5))
            return get(path, query)
        elseif resp.status == 401 || resp.status == 403
            @warn "dbnomics: auth error" path status=resp.status
        end
        @assert resp.status == 200 "dbnomics: $path failed with status $(resp.status)"
        json = JSON3.read(resp.body)
        return json
    else
        throw(resp)
    end
end

@doc """Fetch provider list."""
function providers(; code=false)
    json = get(ApiPaths.providers)
    if code
        return [String(d["code"]) for d in json["providers"]]
    end
    return json
end

@doc """Fetch datasets for a provider."""
function datasets(provider::AbstractString; code=false)
    json = get(ApiPaths.datasets, ("provider_code" => provider))
    if code
        return [String(d["code"]) for d in json["datasets"]]
    end
    return json
end

@doc """Fetch series for a provider/dataset."""
function series(provider::AbstractString, dataset::AbstractString; simplify=false, kwargs...)
    query = Dict{String,Any}("provider_code" => provider, "dataset_code" => dataset)
    for (k, v) in kwargs
        query[String(k)] = v
    end
    json = get(ApiPaths.series, query)
    if simplify
        return [String(s["series_code"]) for s in json["series"]]
    end
    return json
end

@doc """Fetch series values (observations) for one or more series IDs.

Series IDs should be in format `\"provider/dataset/series_code\"`.
"""
function series_values(ids::AbstractVector{String}; kwargs...)
    # DBNomics API accepts series_ids as comma-separated string
    ids_str = join(ids, ",")
    query = Dict{String,Any}("series_ids" => ids_str)
    for (k, v) in kwargs
        query[String(k)] = v
    end
    json = get(ApiPaths.series_values, query)
    return json
end

@doc """Fetch a single series values by provider/dataset/series_code."""
function series_values(provider::AbstractString, dataset::AbstractString, series_code::AbstractString; kwargs...)
    ids = ["$provider/$dataset/$series_code"]
    return series_values(ids; kwargs...)
end

# Helper to parse DBNomics series values response into a DataFrame per series
function parse_series_values(json)
    # Response structure: {"series": {"provider/dataset/code": {"period": [...], "value": [...], ...}}}
    series_dict = Base.get(json, "series", Dict{String,Any}())
    result = Dict{String,Vector{NamedTuple}}()
    for (series_id, data) in series_dict
        periods = Base.get(data, "period", String[])
        values = Base.get(data, "value", Float64[])
        # Other possible fields: "frequency", "unit", "last_updated"
        n = length(periods)
        entries = Vector{NamedTuple}(undef, n)
        for i in 1:n
            # Parse period as DateTime (various formats possible)
            ts = try
                DateTime(periods[i])
            catch
                try
                    Date(periods[i]) |> DateTime
                catch
                    DateTime(0)
                end
            end
            entries[i] = (timestamp=ts, value=values[i])
        end
        result[string(series_id)] = entries
    end
    return result
end

# ============================================================
# High-level API functions matching the vendored DBNomicsData interface
# ============================================================

"""
    fetch_series(id::AbstractString; kwargs...)

Fetch a single series from DBnomics by its full ID (e.g., "ECB/EXR/D.USD.EUR.SP00.A").

# Arguments
- `id::AbstractString`: Full series ID in format "provider/dataset/series_code"
- `kwargs...`: Additional query parameters passed to the API

# Returns
- `Vector{NamedTuple}` with (timestamp, value) pairs, or empty vector if not found.
"""
function fetch_series(id::AbstractString; kwargs...)
    result = series_values([id]; kwargs...)
    parsed = parse_series_values(result)
    return get(parsed, id, Vector{NamedTuple}())
end

"""
    fetch_series(ids::AbstractVector{<:AbstractString}; kwargs...)

Fetch multiple series from DBnomics.

# Returns
- `Dict{String, Vector{NamedTuple}}` mapping each ID to its data.
"""
function fetch_series(ids::AbstractVector{<:AbstractString}; kwargs...)
    result = series_values(ids; kwargs...)
    return parse_series_values(result)
end

"""
    rdb_series_cached(provider::AbstractString, dataset::AbstractString; reset::Bool=false, kwargs...)

Get series metadata for a provider/dataset combination with transparent caching.

# Arguments
- `provider::AbstractString`: DBnomics provider code (e.g., "ECB", "IMF", "WB")
- `dataset::AbstractString`: Dataset code within the provider (e.g., "EXR", "WEO:2023-10")
- `reset::Bool = false`: If true, ignore cache and re-fetch
- `kwargs...`: Additional query parameters

# Returns
- `Vector{String}` of series codes (when simplify=true).

# Notes
- Cache key: "DBNomics/series/\$(provider)/\$(dataset)"
- This function caches the *series metadata* (list of series codes), not the values.
- By default enforces `simplify=true` to return a simple vector of series codes.
"""
function rdb_series_cached(provider::AbstractString, dataset::AbstractString; 
                           reset::Bool=false, kwargs...)
    cache_key = "DBNomics/series/$(provider)/$(dataset)"
    
    # Check cache first
    if !reset
        cached = try
            PlanarCore.Data.Cache.Cache.load_cache(cache_key, raise=false)
        catch
            nothing
        end
        if cached !== nothing
            return cached
        end
    end
    
    # Fetch from API (simplify=true returns just series codes)
    codes = series(provider, dataset; simplify=true, kwargs...)
    
    # Save to cache
    try
        PlanarCore.Data.Cache.Cache.save_cache(cache_key, codes)
    catch e
        @warn "Failed to cache DBnomics series metadata" key=cache_key exception=e
    end
    
    return codes
end

export providers, datasets, series, series_values, parse_series_values, ratelimit, get
export fetch_series, rdb_series_cached

end # module DBNomics