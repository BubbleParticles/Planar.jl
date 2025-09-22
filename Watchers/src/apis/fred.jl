module FRED
using HTTP
using URIs
using JSON3
using ..Watchers
using ..Lang: Option, @kget!
using ..Misc: Config
using ..Misc.TimeToLive: safettl
using ..TimeTicks
using ..TimeTicks: timestamp
using ..Watchers: jsontodict

const API_URL = "https://api.stlouisfed.org/fred"
const API_HEADERS = ["Accept-Encoding" => "deflate,gzip", "Accept" => "application/json"]

const ApiPaths = (;
    # Series endpoints
    series="/series",
    series_categories="/series/categories",
    series_observations="/series/observations",
    series_release="/series/release",
    series_search="/series/search",
    series_search_tags="/series/search/tags",
    series_search_related_tags="/series/search/related_tags",
    series_tags="/series/tags",
    series_updates="/series/updates",
    series_vintagedates="/series/vintagedates",
    
    # Category endpoints
    categories="/categories",
    category="/category",
    category_children="/category/children",
    category_related="/category/related",
    category_series="/category/series",
    category_tags="/category/tags",
    category_related_tags="/category/related_tags",
    
    # Release endpoints
    releases="/releases",
    releases_dates="/releases/dates",
    release="/release",
    release_dates="/release/dates",
    release_series="/release/series",
    release_sources="/release/sources",
    release_tags="/release/tags",
    release_related_tags="/release/related_tags",
    release_tables="/release/tables",
    
    # Source endpoints
    sources="/sources",
    source="/source",
    source_releases="/source/releases",
    
    # Tag endpoints
    tags="/tags",
    related_tags="/related_tags",
    tags_series="/tags/series",
)

const API_KEY_CONFIG = "fred_apikey"
const API_KEY = Ref("")
const last_query = Ref(DateTime(0))
const RATE_LIMIT = Ref(Millisecond(1000))  # 1 second between requests
const STATUS = Ref{Int}(0)

@doc """Sets FRED API key.

- from env var `PLANAR_FRED_APIKEY`
- or from config key $(API_KEY_CONFIG)
"""
function setapikey!(from_env=false, config_path=joinpath(pwd(), "user", "secrets.toml"))
    apikey = if from_env
        Base.get(ENV, "PLANAR_FRED_APIKEY", "")
    else
        cfg = Config(:default, config_path)
        @assert API_KEY_CONFIG ∈ keys(cfg.attrs) "$API_KEY_CONFIG not found in secrets."
        cfg.attrs[API_KEY_CONFIG]
    end
    API_KEY[] = apikey
    nothing
end

@doc "Allows only 1 query every $(RATE_LIMIT[]) seconds."
ratelimit() = sleep(max(Second(0), (last_query[] - now()) + RATE_LIMIT[]))

function get(path, query=nothing)
    ratelimit()
    
    # Add API key to query parameters
    if isnothing(query)
        query = Dict{String,Any}()
    end
    query["api_key"] = API_KEY[]
    query["file_type"] = "json"
    
    # Construct the full URL manually
    full_url = API_URL * path
    
    resp = try
        HTTP.get(full_url; query, headers=API_HEADERS)
    catch e
        e
    end
    last_query[] = now()
    
    if hasproperty(resp, :status)
        STATUS[] = resp.status
        @assert resp.status == 200 "FRED API error: $(resp.status)"
        json = JSON3.read(resp.body)
        return json
    else
        # Handle HTTP exceptions properly
        if isa(resp, HTTP.Exceptions.StatusError)
            throw(AssertionError("FRED API error: $(resp.status)"))
        else
            throw(resp)
        end
    end
end

@doc "Get series information for a given series ID."
function series_info(series_id::String; 
                     realtime_start=nothing,
                     realtime_end=nothing)
    query = Dict{String,Any}(
        "series_id" => series_id
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    json = get(ApiPaths.series, query)
    return jsontodict(json)
end

@doc "Get observations for a series within a date range."
function observations(series_id::String; 
                     start_date=nothing, 
                     end_date=nothing, 
                     limit=nothing,
                     offset=nothing,
                     sort_order="asc",
                     units="lin",
                     frequency="d",
                     aggregation_method="avg",
                     output_type=1,
                     realtime_start=nothing,
                     realtime_end=nothing,
                     vintage_dates=nothing)
    
    query = Dict{String,Any}(
        "series_id" => series_id,
        "sort_order" => sort_order,
        "units" => units,
        "frequency" => frequency,
        "aggregation_method" => aggregation_method,
        "output_type" => output_type
    )
    
    if !isnothing(start_date)
        start_str = isa(start_date, DateTime) ? Dates.format(start_date, dateformat"yyyy-mm-dd") : string(start_date)
        query["observation_start"] = start_str
    end
    
    if !isnothing(end_date)
        end_str = isa(end_date, DateTime) ? Dates.format(end_date, dateformat"yyyy-mm-dd") : string(end_date)
        query["observation_end"] = end_str
    end
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(vintage_dates)
        query["vintage_dates"] = isa(vintage_dates, Vector) ? join(vintage_dates, ",") : vintage_dates
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    json = get(ApiPaths.series_observations, query)
    return jsontodict(json)
end

@doc "Get latest observation for a series."
function latest_observation(series_id::String; 
                           realtime_start=nothing,
                           realtime_end=nothing)
    query = Dict{String,Any}(
        "series_id" => series_id,
        "limit" => 1,
        "sort_order" => "desc"
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    json = get(ApiPaths.series_observations, query)
    return jsontodict(json)
end

@doc "Get categories information."
function categories(; category_id=nothing, parent_id=nothing, limit=nothing, offset=nothing, sort_order="asc")
    query = Dict{String,Any}(
        "sort_order" => sort_order
    )
    
    if !isnothing(category_id)
        query["category_id"] = category_id
    end
    
    if !isnothing(parent_id)
        query["parent_id"] = parent_id
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    json = get(ApiPaths.categories, query)
    return jsontodict(json)
end

@doc "Get details of a specific category."
function category(category_id::Int; realtime_start=nothing, realtime_end=nothing)
    query = Dict{String,Any}(
        "category_id" => category_id
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    json = get(ApiPaths.category, query)
    return jsontodict(json)
end

@doc "Get child categories for a given parent category."
function category_children(category_id::Int; 
                          realtime_start=nothing, 
                          realtime_end=nothing, 
                          limit=nothing, 
                          offset=nothing, 
                          sort_order="asc")
    query = Dict{String,Any}(
        "category_id" => category_id,
        "sort_order" => sort_order
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    json = get(ApiPaths.category_children, query)
    return jsontodict(json)
end

@doc "Get related categories for a specified category."
function category_related(category_id::Int; 
                         realtime_start=nothing, 
                         realtime_end=nothing, 
                         limit=nothing, 
                         offset=nothing, 
                         sort_order="asc")
    query = Dict{String,Any}(
        "category_id" => category_id,
        "sort_order" => sort_order
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    json = get(ApiPaths.category_related, query)
    return jsontodict(json)
end

@doc "Get all series within a particular category."
function category_series(category_id::Int; 
                        realtime_start=nothing, 
                        realtime_end=nothing, 
                        limit=nothing, 
                        offset=nothing, 
                        sort_order="asc",
                        order_by="series_id",
                        filter_variable=nothing,
                        filter_value=nothing,
                        tag_names=nothing,
                        exclude_tag_names=nothing)
    query = Dict{String,Any}(
        "category_id" => category_id,
        "sort_order" => sort_order,
        "order_by" => order_by
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    if !isnothing(filter_variable)
        query["filter_variable"] = filter_variable
    end
    
    if !isnothing(filter_value)
        query["filter_value"] = filter_value
    end
    
    if !isnothing(tag_names)
        query["tag_names"] = isa(tag_names, Vector) ? join(tag_names, ";") : tag_names
    end
    
    if !isnothing(exclude_tag_names)
        query["exclude_tag_names"] = isa(exclude_tag_names, Vector) ? join(exclude_tag_names, ";") : exclude_tag_names
    end
    
    json = get(ApiPaths.category_series, query)
    return jsontodict(json)
end

@doc "Get tags associated with a category."
function category_tags(category_id::Int; 
                      realtime_start=nothing, 
                      realtime_end=nothing, 
                      limit=nothing, 
                      offset=nothing, 
                      sort_order="series_count",
                      order_by="series_count",
                      tag_names=nothing,
                      tag_group_id=nothing,
                      search_text=nothing)
    query = Dict{String,Any}(
        "category_id" => category_id,
        "sort_order" => sort_order,
        "order_by" => order_by
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    if !isnothing(tag_names)
        query["tag_names"] = isa(tag_names, Vector) ? join(tag_names, ";") : tag_names
    end
    
    if !isnothing(tag_group_id)
        query["tag_group_id"] = tag_group_id
    end
    
    if !isnothing(search_text)
        query["search_text"] = search_text
    end
    
    json = get(ApiPaths.category_tags, query)
    return jsontodict(json)
end

@doc "Get tags related to a category."
function category_related_tags(category_id::Int; 
                              realtime_start=nothing, 
                              realtime_end=nothing, 
                              limit=nothing, 
                              offset=nothing, 
                              sort_order="series_count",
                              order_by="series_count",
                              tag_names=nothing,
                              exclude_tag_names=nothing,
                              tag_group_id=nothing,
                              search_text=nothing)
    query = Dict{String,Any}(
        "category_id" => category_id,
        "sort_order" => sort_order,
        "order_by" => order_by
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    if !isnothing(tag_names)
        query["tag_names"] = isa(tag_names, Vector) ? join(tag_names, ";") : tag_names
    end
    
    if !isnothing(exclude_tag_names)
        query["exclude_tag_names"] = isa(exclude_tag_names, Vector) ? join(exclude_tag_names, ";") : exclude_tag_names
    end
    
    if !isnothing(tag_group_id)
        query["tag_group_id"] = tag_group_id
    end
    
    if !isnothing(search_text)
        query["search_text"] = search_text
    end
    
    json = get(ApiPaths.category_related_tags, query)
    return jsontodict(json)
end

@doc "Get releases information."
function releases(; release_id=nothing, limit=nothing, offset=nothing, sort_order="asc", realtime_start=nothing, realtime_end=nothing)
    query = Dict{String,Any}(
        "sort_order" => sort_order
    )
    
    if !isnothing(release_id)
        query["release_id"] = release_id
    end
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    json = get(ApiPaths.releases, query)
    return jsontodict(json)
end

@doc "Get release dates for all economic data releases."
function releases_dates(; limit=nothing, offset=nothing, sort_order="asc", realtime_start=nothing, realtime_end=nothing, include_release_dates_with_no_data=nothing)
    query = Dict{String,Any}(
        "sort_order" => sort_order
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(include_release_dates_with_no_data)
        query["include_release_dates_with_no_data"] = include_release_dates_with_no_data
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    json = get(ApiPaths.releases_dates, query)
    return jsontodict(json)
end

@doc "Get details of a specific release."
function release(release_id::Int; realtime_start=nothing, realtime_end=nothing)
    query = Dict{String,Any}(
        "release_id" => release_id
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    json = get(ApiPaths.release, query)
    return jsontodict(json)
end

@doc "Get release dates for a particular release."
function release_dates(release_id::Int; 
                      limit=nothing, 
                      offset=nothing, 
                      sort_order="asc", 
                      realtime_start=nothing, 
                      realtime_end=nothing, 
                      include_release_dates_with_no_data=nothing)
    query = Dict{String,Any}(
        "release_id" => release_id,
        "sort_order" => sort_order
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(include_release_dates_with_no_data)
        query["include_release_dates_with_no_data"] = include_release_dates_with_no_data
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    json = get(ApiPaths.release_dates, query)
    return jsontodict(json)
end

@doc "Get series associated with a specific release."
function release_series(release_id::Int; 
                       limit=nothing, 
                       offset=nothing, 
                       sort_order="asc", 
                       order_by="series_id",
                       realtime_start=nothing, 
                       realtime_end=nothing,
                       filter_variable=nothing,
                       filter_value=nothing,
                       tag_names=nothing,
                       exclude_tag_names=nothing)
    query = Dict{String,Any}(
        "release_id" => release_id,
        "sort_order" => sort_order,
        "order_by" => order_by
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(filter_variable)
        query["filter_variable"] = filter_variable
    end
    
    if !isnothing(filter_value)
        query["filter_value"] = filter_value
    end
    
    if !isnothing(tag_names)
        query["tag_names"] = isa(tag_names, Vector) ? join(tag_names, ";") : tag_names
    end
    
    if !isnothing(exclude_tag_names)
        query["exclude_tag_names"] = isa(exclude_tag_names, Vector) ? join(exclude_tag_names, ";") : exclude_tag_names
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    json = get(ApiPaths.release_series, query)
    return jsontodict(json)
end

@doc "Get sources for a given release."
function release_sources(release_id::Int; 
                        limit=nothing, 
                        offset=nothing, 
                        sort_order="asc", 
                        realtime_start=nothing, 
                        realtime_end=nothing)
    query = Dict{String,Any}(
        "release_id" => release_id,
        "sort_order" => sort_order
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    json = get(ApiPaths.release_sources, query)
    return jsontodict(json)
end

@doc "Get tags associated with a release."
function release_tags(release_id::Int; 
                     limit=nothing, 
                     offset=nothing, 
                     sort_order="series_count",
                     order_by="series_count",
                     realtime_start=nothing, 
                     realtime_end=nothing,
                     tag_names=nothing,
                     tag_group_id=nothing,
                     search_text=nothing)
    query = Dict{String,Any}(
        "release_id" => release_id,
        "sort_order" => sort_order,
        "order_by" => order_by
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(tag_names)
        query["tag_names"] = isa(tag_names, Vector) ? join(tag_names, ";") : tag_names
    end
    
    if !isnothing(tag_group_id)
        query["tag_group_id"] = tag_group_id
    end
    
    if !isnothing(search_text)
        query["search_text"] = search_text
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    json = get(ApiPaths.release_tags, query)
    return jsontodict(json)
end

@doc "Get tags related to a release."
function release_related_tags(release_id::Int; 
                             limit=nothing, 
                             offset=nothing, 
                             sort_order="series_count",
                             order_by="series_count",
                             realtime_start=nothing, 
                             realtime_end=nothing,
                             tag_names=nothing,
                             exclude_tag_names=nothing,
                             tag_group_id=nothing,
                             search_text=nothing)
    query = Dict{String,Any}(
        "release_id" => release_id,
        "sort_order" => sort_order,
        "order_by" => order_by
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(tag_names)
        query["tag_names"] = isa(tag_names, Vector) ? join(tag_names, ";") : tag_names
    end
    
    if !isnothing(exclude_tag_names)
        query["exclude_tag_names"] = isa(exclude_tag_names, Vector) ? join(exclude_tag_names, ";") : exclude_tag_names
    end
    
    if !isnothing(tag_group_id)
        query["tag_group_id"] = tag_group_id
    end
    
    if !isnothing(search_text)
        query["search_text"] = search_text
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    json = get(ApiPaths.release_related_tags, query)
    return jsontodict(json)
end

@doc "Get release tables for a specific release."
function release_tables(release_id::Int; 
                       element_id=nothing,
                       include_observation_values=nothing,
                       observation_date=nothing,
                       realtime_start=nothing, 
                       realtime_end=nothing)
    query = Dict{String,Any}(
        "release_id" => release_id
    )
    
    if !isnothing(element_id)
        query["element_id"] = element_id
    end
    
    if !isnothing(include_observation_values)
        query["include_observation_values"] = include_observation_values
    end
    
    if !isnothing(observation_date)
        obs_str = isa(observation_date, DateTime) ? Dates.format(observation_date, dateformat"yyyy-mm-dd") : string(observation_date)
        query["observation_date"] = obs_str
    end
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    json = get(ApiPaths.release_tables, query)
    return jsontodict(json)
end

@doc "Get sources information."
function sources(; source_id=nothing, limit=nothing, offset=nothing, sort_order="asc", realtime_start=nothing, realtime_end=nothing)
    query = Dict{String,Any}(
        "sort_order" => sort_order
    )
    
    if !isnothing(source_id)
        query["source_id"] = source_id
    end
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    json = get(ApiPaths.sources, query)
    return jsontodict(json)
end

@doc "Get details of a specific source."
function source(source_id::Int; realtime_start=nothing, realtime_end=nothing)
    query = Dict{String,Any}(
        "source_id" => source_id
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    json = get(ApiPaths.source, query)
    return jsontodict(json)
end

@doc "Get releases associated with a particular source."
function source_releases(source_id::Int; 
                        limit=nothing, 
                        offset=nothing, 
                        sort_order="asc", 
                        realtime_start=nothing, 
                        realtime_end=nothing)
    query = Dict{String,Any}(
        "source_id" => source_id,
        "sort_order" => sort_order
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    json = get(ApiPaths.source_releases, query)
    return jsontodict(json)
end

@doc "Search for series by text."
function search_series(search_text::String; 
                      search_type="full_text",
                      realtime_start=nothing,
                      realtime_end=nothing,
                      limit=nothing,
                      offset=nothing,
                      sort_order="search_rank",
                      filter_variable="frequency",
                      filter_value="Monthly",
                      tag_names=nothing,
                      exclude_tag_names=nothing)
    
    query = Dict{String,Any}(
        "search_text" => search_text,
        "search_type" => search_type,
        "sort_order" => sort_order
    )
    
    # Only add filter parameters if they are not empty
    if !isempty(filter_variable) && !isempty(filter_value)
        query["filter_variable"] = filter_variable
        query["filter_value"] = filter_value
    end
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    if !isnothing(tag_names)
        query["tag_names"] = isa(tag_names, Vector) ? join(tag_names, ";") : tag_names
    end
    
    if !isnothing(exclude_tag_names)
        query["exclude_tag_names"] = isa(exclude_tag_names, Vector) ? join(exclude_tag_names, ";") : exclude_tag_names
    end
    
    json = get(ApiPaths.series_search, query)
    return jsontodict(json)
end

@doc "Get categories associated with a series."
function series_categories(series_id::String; realtime_start=nothing, realtime_end=nothing)
    query = Dict{String,Any}(
        "series_id" => series_id
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    json = get(ApiPaths.series_categories, query)
    return jsontodict(json)
end

@doc "Get the release associated with a series."
function series_release(series_id::String; realtime_start=nothing, realtime_end=nothing)
    query = Dict{String,Any}(
        "series_id" => series_id
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    json = get(ApiPaths.series_release, query)
    return jsontodict(json)
end

@doc "Get tags for a series search."
function series_search_tags(search_text::String; 
                           realtime_start=nothing, 
                           realtime_end=nothing, 
                           limit=nothing, 
                           offset=nothing, 
                           sort_order="series_count",
                           order_by="series_count",
                           tag_names=nothing,
                           tag_group_id=nothing,
                           search_text_tags=nothing)
    query = Dict{String,Any}(
        "search_text" => search_text,
        "sort_order" => sort_order,
        "order_by" => order_by
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(tag_names)
        query["tag_names"] = isa(tag_names, Vector) ? join(tag_names, ";") : tag_names
    end
    
    if !isnothing(tag_group_id)
        query["tag_group_id"] = tag_group_id
    end
    
    if !isnothing(search_text_tags)
        query["search_text"] = search_text_tags
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    json = get(ApiPaths.series_search_tags, query)
    return jsontodict(json)
end

@doc "Get related tags for a series search."
function series_search_related_tags(search_text::String; 
                                   realtime_start=nothing, 
                                   realtime_end=nothing, 
                                   limit=nothing, 
                                   offset=nothing, 
                                   sort_order="series_count",
                                   order_by="series_count",
                                   tag_names=nothing,
                                   exclude_tag_names=nothing,
                                   tag_group_id=nothing,
                                   search_text_tags=nothing)
    query = Dict{String,Any}(
        "search_text" => search_text,
        "sort_order" => sort_order,
        "order_by" => order_by
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(tag_names)
        query["tag_names"] = isa(tag_names, Vector) ? join(tag_names, ";") : tag_names
    end
    
    if !isnothing(exclude_tag_names)
        query["exclude_tag_names"] = isa(exclude_tag_names, Vector) ? join(exclude_tag_names, ";") : exclude_tag_names
    end
    
    if !isnothing(tag_group_id)
        query["tag_group_id"] = tag_group_id
    end
    
    if !isnothing(search_text_tags)
        query["search_text"] = search_text_tags
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    json = get(ApiPaths.series_search_related_tags, query)
    return jsontodict(json)
end

@doc "Get tags associated with a series."
function series_tags(series_id::String; 
                    realtime_start=nothing, 
                    realtime_end=nothing, 
                    limit=nothing, 
                    offset=nothing, 
                    sort_order="series_count",
                    order_by="series_count",
                    tag_names=nothing,
                    tag_group_id=nothing,
                    search_text=nothing)
    query = Dict{String,Any}(
        "series_id" => series_id,
        "sort_order" => sort_order,
        "order_by" => order_by
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(tag_names)
        query["tag_names"] = isa(tag_names, Vector) ? join(tag_names, ";") : tag_names
    end
    
    if !isnothing(tag_group_id)
        query["tag_group_id"] = tag_group_id
    end
    
    if !isnothing(search_text)
        query["search_text"] = search_text
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    json = get(ApiPaths.series_tags, query)
    return jsontodict(json)
end

@doc "Get series sorted by recent updates."
function series_updates(; realtime_start=nothing, 
                       realtime_end=nothing, 
                       limit=nothing, 
                       offset=nothing, 
                       filter_value=nothing,
                       start_time=nothing,
                       end_time=nothing)
    query = Dict{String,Any}()
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(filter_value)
        query["filter_value"] = filter_value
    end
    
    if !isnothing(start_time)
        start_str = isa(start_time, DateTime) ? Dates.format(start_time, dateformat"yyyy-mm-dd") : string(start_time)
        query["start_time"] = start_str
    end
    
    if !isnothing(end_time)
        end_str = isa(end_time, DateTime) ? Dates.format(end_time, dateformat"yyyy-mm-dd") : string(end_time)
        query["end_time"] = end_str
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    json = get(ApiPaths.series_updates, query)
    return jsontodict(json)
end

@doc "Get tags information."
function tags(; tag_names=nothing, 
              tag_group_id=nothing,
              search_text=nothing,
              limit=nothing,
              offset=nothing,
              sort_order="series_count",
              order_by="series_count")
    
    query = Dict{String,Any}(
        "sort_order" => sort_order,
        "order_by" => order_by
    )
    
    if !isnothing(tag_names)
        query["tag_names"] = isa(tag_names, Vector) ? join(tag_names, ";") : tag_names
    end
    
    if !isnothing(tag_group_id)
        query["tag_group_id"] = tag_group_id
    end
    
    if !isnothing(search_text)
        query["search_text"] = search_text
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    json = get(ApiPaths.tags, query)
    return jsontodict(json)
end

@doc "Get vintage dates for a series."
function vintage_dates(series_id::String; 
                       realtime_start=nothing,
                       realtime_end=nothing,
                       limit=nothing,
                       offset=nothing,
                       sort_order="asc")
    
    query = Dict{String,Any}(
        "series_id" => series_id,
        "sort_order" => sort_order
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    json = get(ApiPaths.series_vintagedates, query)
    return jsontodict(json)
end

@doc "Get tags related to one or more specified tags."
function related_tags(tag_names::Union{String,Vector{String}}; 
                     realtime_start=nothing, 
                     realtime_end=nothing, 
                     limit=nothing, 
                     offset=nothing, 
                     sort_order="series_count",
                     order_by="series_count",
                     exclude_tag_names=nothing,
                     tag_group_id=nothing,
                     search_text=nothing)
    query = Dict{String,Any}(
        "tag_names" => isa(tag_names, Vector) ? join(tag_names, ";") : tag_names,
        "sort_order" => sort_order,
        "order_by" => order_by
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(exclude_tag_names)
        query["exclude_tag_names"] = isa(exclude_tag_names, Vector) ? join(exclude_tag_names, ";") : exclude_tag_names
    end
    
    if !isnothing(tag_group_id)
        query["tag_group_id"] = tag_group_id
    end
    
    if !isnothing(search_text)
        query["search_text"] = search_text
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    json = get(ApiPaths.related_tags, query)
    return jsontodict(json)
end

@doc "Get series matching specific tags."
function tags_series(tag_names::Union{String,Vector{String}}; 
                    realtime_start=nothing, 
                    realtime_end=nothing, 
                    limit=nothing, 
                    offset=nothing, 
                    sort_order="series_id",
                    order_by="series_id",
                    exclude_tag_names=nothing,
                    filter_variable=nothing,
                    filter_value=nothing)
    query = Dict{String,Any}(
        "tag_names" => isa(tag_names, Vector) ? join(tag_names, ";") : tag_names,
        "sort_order" => sort_order,
        "order_by" => order_by
    )
    
    if !isnothing(realtime_start)
        start_str = isa(realtime_start, DateTime) ? Dates.format(realtime_start, dateformat"yyyy-mm-dd") : string(realtime_start)
        query["realtime_start"] = start_str
    end
    
    if !isnothing(realtime_end)
        end_str = isa(realtime_end, DateTime) ? Dates.format(realtime_end, dateformat"yyyy-mm-dd") : string(realtime_end)
        query["realtime_end"] = end_str
    end
    
    if !isnothing(exclude_tag_names)
        query["exclude_tag_names"] = isa(exclude_tag_names, Vector) ? join(exclude_tag_names, ";") : exclude_tag_names
    end
    
    if !isnothing(filter_variable)
        query["filter_variable"] = filter_variable
    end
    
    if !isnothing(filter_value)
        query["filter_value"] = filter_value
    end
    
    if !isnothing(limit)
        query["limit"] = limit
    end
    
    if !isnothing(offset)
        query["offset"] = offset
    end
    
    json = get(ApiPaths.tags_series, query)
    return jsontodict(json)
end

@doc "Get time series data as a simple array of (date, value) tuples."
function get_timeseries(series_id::String; 
                       start_date=nothing, 
                       end_date=nothing,
                       frequency="d",
                       units="lin")
    
    data = observations(series_id; 
                       start_date=start_date, 
                       end_date=end_date,
                       frequency=frequency,
                       units=units)
    
    obs_data = data["observations"]
    dates = DateTime[]
    values = Union{Float64,Missing}[]
    
    for obs in obs_data
        date_str = obs["date"]
        value_str = obs["value"]
        
        # Parse date
        date = parse(DateTime, date_str)
        push!(dates, date)
        
        # Parse value (handle missing values represented as ".")
        if value_str == "."
            push!(values, missing)
        else
            push!(values, parse(Float64, value_str))
        end
    end
    
    return (; dates, values)
end

@doc "Get latest value for a series."
function get_latest_value(series_id::String)
    data = latest_observation(series_id)
    observations = data["observations"]
    
    if isempty(observations)
        return missing
    end
    
    latest_obs = first(observations)
    value_str = latest_obs["value"]
    
    if value_str == "."
        return missing
    else
        return parse(Float64, value_str)
    end
end

@doc "Get latest date for a series."
function get_latest_date(series_id::String)
    data = latest_observation(series_id)
    observations = data["observations"]
    
    if isempty(observations)
        return missing
    end
    
    latest_obs = first(observations)
    date_str = latest_obs["date"]
    
    return parse(DateTime, date_str)
end

@doc "Check if API key is set."
function has_apikey()
    return !isempty(API_KEY[])
end

@doc "Get API status."
function api_status()
    return (; status=STATUS[], last_query=last_query[], rate_limit=RATE_LIMIT[])
end

# Cache for frequently accessed data
const series_info_cache = safettl(String, Dict{String,Any}, Hour(24))
const categories_cache = safettl(Nothing, Dict{String,Any}, Hour(24))

@doc "Get series info with caching."
function cached_series_info(series_id::String)
    @kget! series_info_cache series_id begin
        series_info(series_id)
    end
end

@doc "Get categories with caching."
function cached_categories(; category_id=nothing, parent_id=nothing)
    cache_key = isnothing(category_id) ? "root" : string(category_id)
    @kget! categories_cache cache_key begin
        categories(; category_id=category_id, parent_id=parent_id)
    end
end

# Series exports
export series_info, observations, latest_observation, series_categories, series_release
export series_search_tags, series_search_related_tags, series_tags, series_updates, series_vintagedates
export search_series, get_timeseries, get_latest_value, get_latest_date

# Category exports
export categories, category, category_children, category_related, category_series
export category_tags, category_related_tags

# Release exports
export releases, releases_dates, release, release_dates, release_series
export release_sources, release_tags, release_related_tags, release_tables

# Source exports
export sources, source, source_releases

# Tag exports
export tags, related_tags, tags_series

# Utility exports
export setapikey!, has_apikey, api_status, cached_series_info, cached_categories

end
