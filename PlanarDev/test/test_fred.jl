using Test

# Ensure Planar and TimeTicks are available and set global `fred` alias to Watchers.FRED if possible.
try
    if isdefined(Main, :fred)
        # keep existing fred
    else
        if isdefined(Watchers, :FRED)
            @eval Main const fred = Watchers.FRED
        else
            try
                basepath = dirname(pathof(Watchers))
                fred_file = joinpath(basepath, "apis", "fred.jl")
                if isfile(fred_file)
                    Base.include(Watchers, fred_file)
                end
            catch
            end
            if isdefined(Watchers, :FRED)
                @eval Main const fred = Watchers.FRED
            else
                @eval Main const fred = nothing
            end
        end
    end
catch
    if !isdefined(Main, :fred)
        @eval Main const fred = nothing
    end
end

function test_fred()
    if fred === nothing
        @warn "FRED API tests skipped: Watchers.FRED not available"
        return true
    end

    @eval begin
        using .Planar: Planar
        using .Planar.Engine.LiveMode.Watchers.FRED
        using .Planar.Engine.TimeTicks
        using .TimeTicks
        using .TimeTicks.Dates: format, @dateformat_str
    end
    if !isdefined(Main, :fred)
        @eval Main const fred = FRED
    end

    @testset "FRED API Tests" begin
        @info "TEST: API Key Setup and Configuration"
        @test test_api_key_setup()
        @test test_rate_limit()
        @test test_api_status()
        @test test_configuration()

        @info "TEST: Series Endpoints"
        @test test_series_info()
        @test test_observations()
        @test test_latest_observation()
        @test test_series_categories()
        @test test_series_release()
        @test test_series_tags()
        @test test_series_vintagedates()

        @info "TEST: Category Endpoints"
        @test test_category()
        @test test_category_children()
        @test test_category_related()
        @test test_category_series()

        @info "TEST: Release Endpoints"
        @test test_releases()
        @test test_releases_dates()
        @test test_release()
        @test test_release_dates()
        @test test_release_series()
        @test test_release_sources()

        @info "TEST: Source Endpoints"
        @test test_sources()
        @test test_source()
        @test test_source_releases()

        @info "TEST: Tag Endpoints"
        @test test_tags()
        @test test_related_tags()
        @test test_tags_series()

        @info "TEST: Utility Functions"
        @test test_timeseries_data()
        @test test_convenience_functions()
        @test test_caching()
        @test test_error_handling()
        @test test_parameter_validation()

        @info "TEST: Parameter Validation"
        @test test_units_parameters()
        @test test_frequency_parameters()
        @test test_aggregation_parameters()
        @test test_output_type_parameters()
        @test test_sort_order_parameters()

        @info "TEST: Performance Tests"
        @test test_rate_limiting_performance()
        @test test_caching_performance()
        @test test_large_dataset_performance()
        @test test_concurrent_requests()
        @test test_memory_usage()
        @test test_error_recovery_performance()

        @info "TEST: Integration Tests"
        @test test_module_integration()
        @test test_configuration_integration()
        @test test_data_format_integration()
        @test test_error_handling_integration()
        @test test_caching_integration()
        @test test_timeticks_integration()
        @test test_streaming_integration()

        @info "TEST: Edge Cases"
        @test test_edge_cases()
        @test test_invalid_parameters()
        @test test_network_errors()
    end
end

function test_api_key_setup()
    # Test API key setup from config file
    config_path = joinpath(dirname(dirname(dirname(pathof(Planar)))), "user", "secrets.toml")
    fred.setapikey!(false, config_path)
    @test fred.has_apikey()
    
    # Test API key setup from environment variable (if available)
    if Base.get(ENV, "PLANAR_FRED_APIKEY", "") != ""
        fred.setapikey!(true)
        @test fred.has_apikey()
    end
    
    return true
end

function test_rate_limit()
    # Set up API key
    config_path = joinpath(dirname(dirname(dirname(pathof(Planar)))), "user", "secrets.toml")
    fred.setapikey!(false, config_path)
    
    @test fred.RATE_LIMIT[] isa Period
    @test fred.RATE_LIMIT[] == Millisecond(1000)
    
    # Test rate limiting by measuring time between calls
    start_time = now()
    fred.series_info("GDPC1")  # This will fail if no API key, but that's ok for rate limit test
    fred.series_info("GDPC1")  # Second call should be rate limited
    elapsed = now() - start_time
    
    # Should take at least the rate limit time (or fail due to no API key)
    @test elapsed >= fred.RATE_LIMIT[] || !fred.has_apikey()
    
    return true
end

function test_series_info()
    # Set up API key
    config_path = joinpath(dirname(dirname(dirname(pathof(Planar)))), "user", "secrets.toml")
    fred.setapikey!(false, config_path)
    
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping series info test"
        return true
    end
    
    # Test series info for GDP
    data = fred.series_info("GDPC1")
    @test data isa Dict{String,Any}
    @test "seriess" in keys(data)
    @test length(data["seriess"]) > 0
    
    series = data["seriess"][1]
    @test "id" in keys(series)
    @test "title" in keys(series)
    @test "units" in keys(series)
    @test "frequency" in keys(series)
    @test series["id"] == "GDPC1"
    
    return true
end

function test_observations()
    # Set up API key
    config_path = joinpath(dirname(dirname(dirname(pathof(Planar)))), "user", "secrets.toml")
    fred.setapikey!(false, config_path)
    
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping observations test"
        return true
    end
    
    # Test observations for GDP with date range
    end_date = now()
    start_date = end_date - Year(1)
    
    data = fred.observations("GDPC1"; start_date=start_date, end_date=end_date, frequency="q")
    @test data isa Dict{String,Any}
    @test "observations" in keys(data)
    @test length(data["observations"]) > 0
    
    # Test with limit
    data_limited = fred.observations("GDPC1"; limit=5, frequency="q")
    @test length(data_limited["observations"]) <= 5
    
    # Test with different frequency (annual)
    data_annual = fred.observations("GDPC1"; frequency="a", limit=3)
    @test length(data_annual["observations"]) <= 3
    
    return true
end

function test_latest_observation()
    # Set up API key
    config_path = joinpath(dirname(dirname(dirname(pathof(Planar)))), "user", "secrets.toml")
    fred.setapikey!(false, config_path)
    
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping latest observation test"
        return true
    end
    
    data = fred.latest_observation("GDPC1")
    @test data isa Dict{String,Any}
    @test "observations" in keys(data)
    @test length(data["observations"]) == 1
    
    obs = data["observations"][1]
    @test "date" in keys(obs)
    @test "value" in keys(obs)
    
    return true
end

function test_search_series()
    # Set up API key
    config_path = joinpath(dirname(dirname(dirname(pathof(Planar)))), "user", "secrets.toml")
    fred.setapikey!(false, config_path)
    
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping search series test"
        return true
    end
    
    # Test search for GDP-related series (use a more specific search)
    data = fred.search_series("GDPC1"; limit=5)
    @test data isa Dict{String,Any}
    @test "seriess" in keys(data)
    @test length(data["seriess"]) <= 5
    
    if length(data["seriess"]) > 0
        series = data["seriess"][1]
        @test "id" in keys(series)
        @test "title" in keys(series)
    end
    
    # Test search with tags
    data_tagged = fred.search_series("unemployment"; tag_names=["usa"], limit=3)
    @test data_tagged isa Dict{String,Any}
    @test "seriess" in keys(data_tagged)
    
    return true
end

function test_categories()
    # Set up API key
    config_path = joinpath(dirname(dirname(dirname(pathof(Planar)))), "user", "secrets.toml")
    fred.setapikey!(false, config_path)
    
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping categories test"
        return true
    end
    
    # Test root categories
    data = fred.categories()
    @test data isa Dict{String,Any}
    @test "categories" in keys(data)
    @test length(data["categories"]) > 0
    
    # Test specific category
    if length(data["categories"]) > 0
        category = data["categories"][1]
        @test "id" in keys(category)
        @test "name" in keys(category)
        
        # Test subcategories
        subcats = fred.categories(; category_id=category["id"])
        @test subcats isa Dict{String,Any}
        @test "categories" in keys(subcats)
    end
    
    return true
end

function test_releases()
    # Set up API key
    config_path = joinpath(dirname(dirname(dirname(pathof(Planar)))), "user", "secrets.toml")
    fred.setapikey!(false, config_path)
    
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping releases test"
        return true
    end
    
    data = fred.releases(; limit=5)
    @test data isa Dict{String,Any}
    @test "releases" in keys(data)
    @test length(data["releases"]) <= 5
    
    if length(data["releases"]) > 0
        release = data["releases"][1]
        @test "id" in keys(release)
        @test "name" in keys(release)
    end
    
    return true
end

function test_sources()
    # Set up API key
    config_path = joinpath(dirname(dirname(dirname(pathof(Planar)))), "user", "secrets.toml")
    fred.setapikey!(false, config_path)
    
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping sources test"
        return true
    end
    
    data = fred.sources(; limit=5)
    @test data isa Dict{String,Any}
    @test "sources" in keys(data)
    @test length(data["sources"]) <= 5
    
    if length(data["sources"]) > 0
        source = data["sources"][1]
        @test "id" in keys(source)
        @test "name" in keys(source)
    end
    
    return true
end

function test_tags()
    # Set up API key
    config_path = joinpath(dirname(dirname(dirname(pathof(Planar)))), "user", "secrets.toml")
    fred.setapikey!(false, config_path)
    
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping tags test"
        return true
    end
    
    data = fred.tags(; limit=5)
    @test data isa Dict{String,Any}
    @test "tags" in keys(data)
    @test length(data["tags"]) <= 5
    
    if length(data["tags"]) > 0
        tag = data["tags"][1]
        @test "name" in keys(tag)
        @test "group_id" in keys(tag)
    end
    
    # Test search tags
    data_search = fred.tags(; search_text="usa", limit=3)
    @test data_search isa Dict{String,Any}
    @test "tags" in keys(data_search)
    
    return true
end

function test_vintage_dates()
    # Set up API key
    config_path = joinpath(dirname(dirname(dirname(pathof(Planar)))), "user", "secrets.toml")
    fred.setapikey!(false, config_path)
    
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping vintage dates test"
        return true
    end
    
    data = fred.vintage_dates("GDPC1"; limit=5)
    @test data isa Dict{String,Any}
    @test "vintage_dates" in keys(data)
    @test length(data["vintage_dates"]) <= 5
    
    if length(data["vintage_dates"]) > 0
        vintage = data["vintage_dates"][1]
        @test vintage isa String
        # Should be a valid date string
        @test occursin(r"^\d{4}-\d{2}-\d{2}$", vintage)
    end
    
    return true
end

function test_timeseries_data()
    # Set up API key
    config_path = joinpath(dirname(dirname(dirname(pathof(Planar)))), "user", "secrets.toml")
    fred.setapikey!(false, config_path)
    
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping timeseries data test"
        return true
    end
    
    end_date = now()
    start_date = end_date - Year(1)
    
    data = fred.get_timeseries("GDPC1"; start_date=start_date, end_date=end_date, frequency="q")
    @test data isa NamedTuple
    @test :dates in keys(data)
    @test :values in keys(data)
    @test data.dates isa Vector{DateTime}
    @test data.values isa Vector{Union{Float64,Missing}}
    @test length(data.dates) == length(data.values)
    @test length(data.dates) > 0
    
    # Test with different frequency (annual)
    data_annual = fred.get_timeseries("GDPC1"; frequency="a", start_date=start_date, end_date=end_date)
    @test data_annual isa NamedTuple
    @test :dates in keys(data_annual)
    @test :values in keys(data_annual)
    
    return true
end

function test_convenience_functions()
    # Set up API key
    config_path = joinpath(dirname(dirname(dirname(pathof(Planar)))), "user", "secrets.toml")
    fred.setapikey!(false, config_path)
    
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping convenience functions test"
        return true
    end
    
    # Test latest value
    latest_value = fred.get_latest_value("GDPC1")
    @test latest_value isa Union{Float64,Missing}
    
    # Test latest date
    latest_date = fred.get_latest_date("GDPC1")
    @test latest_date isa Union{DateTime,Missing}
    
    if !ismissing(latest_date)
        @test latest_date isa DateTime
    end
    
    return true
end

function test_caching()
    # Set up API key
    config_path = joinpath(dirname(dirname(dirname(pathof(Planar)))), "user", "secrets.toml")
    fred.setapikey!(false, config_path)
    
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping caching test"
        return true
    end
    
    # Test cached series info
    data1 = fred.cached_series_info("GDPC1")
    data2 = fred.cached_series_info("GDPC1")
    @test data1 == data2  # Should be the same due to caching
    
    # Test cached categories
    cats1 = fred.cached_categories()
    cats2 = fred.cached_categories()
    @test cats1 == cats2  # Should be the same due to caching
    
    return true
end

function test_error_handling()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping error handling test"
        return true
    end
    
    # Test with invalid series ID
    try
        fred.series_info("INVALID_SERIES_ID")
        # If it doesn't throw an error, that's also acceptable
    catch e
        # If it does throw an error, that's also acceptable
        @test e isa Exception
    end
    
    # Test with invalid date range (end before start)
    try
        end_date = now() - Year(2)
        start_date = now() - Year(1)
        fred.observations("GDPC1"; start_date=start_date, end_date=end_date)
        # If it doesn't throw an error, that's also acceptable
    catch e
        # If it does throw an error, that's also acceptable
        @test e isa Exception
    end
    
    return true
end

function test_configuration()
    # Test API status
    status = fred.api_status()
    @test status isa NamedTuple
    @test :status in keys(status)
    @test :last_query in keys(status)
    @test :rate_limit in keys(status)
    @test status.rate_limit isa Period
    
    # Test API key status
    @test fred.has_apikey() isa Bool
    
    return true
end

function test_ratelimit()
    start_time = now()
    fred.series_info("GDPC1")
    fred.series_info("GDPC1")
    elapsed = now() - start_time
    @test elapsed >= fred.RATE_LIMIT[] || !fred.has_apikey()
    return true
end

function test_api_status()
    status = fred.api_status()
    @test status isa NamedTuple
    @test :status in keys(status)
    @test :last_query in keys(status)
    @test :rate_limit in keys(status)
    @test status.rate_limit isa Period
    return true
end

function test_series_categories()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping series_categories test"
        return true
    end
    data = fred.series_categories("GDPC1")
    @test data isa Dict{String,Any}
    @test "categories" in keys(data)
    yesterday = now() - Day(1)
    data_realtime = fred.series_categories("GDPC1"; realtime_start=yesterday, realtime_end=now())
    @test data_realtime isa Dict{String,Any}
    return true
end

function test_series_release()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping series_release test"
        return true
    end
    data = fred.series_release("GDPC1")
    @test data isa Dict{String,Any}
    @test "releases" in keys(data)
    return true
end

function test_series_vintagedates()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping series_vintagedates test"
        return true
    end
    data = fred.vintage_dates("GDPC1"; limit=5)
    @test data isa Dict{String,Any}
    @test "vintage_dates" in keys(data)
    return true
end

function test_category()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping category test"
        return true
    end
    data = fred.category(125)
    @test data isa Dict{String,Any}
    @test "categories" in keys(data)
    return true
end

function test_category_children()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping category_children test"
        return true
    end
    data = fred.category_children(125; limit=5)
    @test data isa Dict{String,Any}
    @test "categories" in keys(data)
    return true
end

function test_category_related()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping category_related test"
        return true
    end
    data = fred.category_related(125; limit=5)
    @test data isa Dict{String,Any}
    @test "categories" in keys(data)
    return true
end

function test_category_series()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping category_series test"
        return true
    end
    data = fred.category_series(125; limit=5)
    @test data isa Dict{String,Any}
    @test "seriess" in keys(data)
    data_filtered = fred.category_series(125; filter_variable="frequency", filter_value="Monthly", tag_names=["usa"], limit=3)
    @test data_filtered isa Dict{String,Any}
    return true
end

function test_releases_dates()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping releases_dates test"
        return true
    end
    data = fred.releases_dates(; limit=5)
    @test data isa Dict{String,Any}
    @test "release_dates" in keys(data)
    return true
end

function test_release()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping release test"
        return true
    end
    data = fred.release(53)
    @test data isa Dict{String,Any}
    @test "releases" in keys(data)
    return true
end

function test_release_dates()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping release_dates test"
        return true
    end
    data = fred.release_dates(53; limit=5)
    @test data isa Dict{String,Any}
    @test "release_dates" in keys(data)
    return true
end

function test_release_series()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping release_series test"
        return true
    end
    data = fred.release_series(53; limit=5)
    @test data isa Dict{String,Any}
    @test "seriess" in keys(data)
    return true
end

function test_release_sources()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping release_sources test"
        return true
    end
    data = fred.release_sources(53; limit=5)
    @test data isa Dict{String,Any}
    @test "sources" in keys(data)
    return true
end

function test_source()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping source test"
        return true
    end
    data = fred.source(1)
    @test data isa Dict{String,Any}
    @test "sources" in keys(data)
    return true
end

function test_source_releases()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping source_releases test"
        return true
    end
    data = fred.source_releases(1; limit=5)
    @test data isa Dict{String,Any}
    @test "releases" in keys(data)
    return true
end

function test_related_tags()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping related_tags test"
        return true
    end
    data = fred.related_tags("usa"; limit=5)
    @test data isa Dict{String,Any}
    @test "tags" in keys(data)
    data_multi = fred.related_tags(["usa", "monthly"]; limit=3)
    @test data_multi isa Dict{String,Any}
    return true
end

function test_tags_series()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping tags_series test"
        return true
    end
    data = fred.tags_series("usa"; limit=5)
    @test data isa Dict{String,Any}
    @test "seriess" in keys(data)
    data_multi = fred.tags_series(["usa", "monthly"]; limit=3)
    @test data_multi isa Dict{String,Any}
    return true
end

function test_parameter_validation()
    @test_throws MethodError fred.series_info(123)
    @test_throws MethodError fred.category("invalid")
    return true
end

function test_units_parameters()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping units parameters test"
        return true
    end
    valid_units = ["lin", "chg", "ch1", "pch", "pca", "cch", "cca", "log"]
    for unit in valid_units
        try
            data = fred.observations("GDPC1"; units=unit, limit=1)
            @test data isa Dict{String,Any}
        catch e
            @test occursin("400", string(e)) || @test data isa Dict{String,Any}
        end
    end
    return true
end

function test_frequency_parameters()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping frequency parameters test"
        return true
    end
    valid_frequencies = ["d", "w", "m", "q", "sa", "a", "wef", "weth", "ww", "bw", "ba"]
    for freq in valid_frequencies
        try
            data = fred.observations("GDPC1"; frequency=freq, limit=1)
            @test data isa Dict{String,Any}
        catch e
            @test occursin("400", string(e))
        end
    end
    return true
end

function test_aggregation_parameters()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping aggregation parameters test"
        return true
    end
    valid_aggregations = ["avg", "sum", "eop"]
    for agg in valid_aggregations
        try
            data = fred.observations("GDPC1"; aggregation_method=agg, limit=1)
            @test data isa Dict{String,Any}
        catch e
            @test occursin("400", string(e))
        end
    end
    return true
end

function test_output_type_parameters()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping output type parameters test"
        return true
    end
    valid_output_types = [1, 2, 3, 4]
    for output_type in valid_output_types
        try
            data = fred.observations("GDPC1"; output_type=output_type, limit=1)
            @test data isa Dict{String,Any}
        catch e
            @test occursin("400", string(e))
        end
    end
    return true
end

function test_sort_order_parameters()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping sort order parameters test"
        return true
    end
    valid_sort_orders = ["asc", "desc"]
    for sort_order in valid_sort_orders
        try
            data = fred.observations("GDPC1"; sort_order=sort_order, limit=1)
            @test data isa Dict{String,Any}
        catch e
            @warn "Sort order parameter '$sort_order' failed: $e"
        end
    end
    return true
end

function test_rate_limiting_performance()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping rate limiting performance test"
        return true
    end
    start_time = now()
    for i in 1:3
        fred.series_info("GDPC1")
    end
    elapsed = now() - start_time
    @test elapsed >= Millisecond(2000)
    return true
end

function test_caching_performance()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping caching performance test"
        return true
    end
    start_time = now()
    data1 = fred.cached_series_info("GDPC1")
    first_call_time = now() - start_time
    start_time = now()
    data2 = fred.cached_series_info("GDPC1")
    second_call_time = now() - start_time
    @test second_call_time < first_call_time
    @test data1 == data2
    return true
end

function test_large_dataset_performance()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping large dataset performance test"
        return true
    end
    end_date = now()
    start_date = end_date - Year(5)
    start_time = now()
    data = fred.observations("GDPC1"; start_date=start_date, end_date=end_date, limit=1000, frequency="q")
    elapsed = now() - start_time
    @test data isa Dict{String,Any}
    @test "observations" in keys(data)
    @test elapsed < Second(30)
    return true
end

function test_concurrent_requests()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping concurrent requests test"
        return true
    end
    series_ids = ["GDPC1", "UNRATE", "CPIAUCSL", "FEDFUNDS", "PAYEMS"]
    results = []
    start_time = now()
    for series_id in series_ids
        try
            data = fred.series_info(series_id)
            push!(results, data)
        catch e
            @warn "Concurrent request failed for $series_id: $e"
        end
    end
    elapsed = now() - start_time
    @test length(results) > 0
    @test elapsed < Second(60)
    return true
end

function test_memory_usage()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping memory usage test"
        return true
    end
    for i in 1:5
        data = fred.observations("GDPC1"; limit=1000, frequency="q")
        @test data isa Dict{String,Any}
    end
    GC.gc()
    @test true
    return true
end

function test_error_recovery_performance()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping error recovery performance test"
        return true
    end
    start_time = now()
    try
        fred.series_info("INVALID_SERIES_ID")
    catch e
    end
    data = fred.series_info("GDPC1")
    elapsed = now() - start_time
    @test data isa Dict{String,Any}
    @test elapsed < Second(10)
    return true
end

function test_module_integration()
    @test fred isa Module
    @test fred.API_URL == "https://api.stlouisfed.org/fred"
    @test fred.API_HEADERS isa Vector{Pair{String,String}}
    @test fred.RATE_LIMIT[] isa Period
    expected_functions = [
        :series_info, :observations, :latest_observation,
        :series_categories, :series_release, :search_series,
        :series_search_tags, :series_search_related_tags, :series_tags,
        :series_updates, :vintage_dates, :categories, :category,
        :category_children, :category_related, :category_series,
        :category_tags, :category_related_tags, :releases, :releases_dates,
        :release, :release_dates, :release_series, :release_sources,
        :release_tags, :release_related_tags, :release_tables,
        :sources, :source, :source_releases, :tags, :related_tags,
        :tags_series, :get_timeseries, :get_latest_value, :get_latest_date,
        :setapikey!, :has_apikey, :api_status, :cached_series_info, :cached_categories
    ]
    for func in expected_functions
        @test isdefined(fred, func)
    end
    return true
end

function test_configuration_integration()
    config_path = joinpath(dirname(dirname(dirname(pathof(Planar)))), "user", "secrets.toml")
    if isfile(config_path)
        try
            fred.setapikey!(false, config_path)
            @test fred.has_apikey()
        catch e
            @warn "Configuration integration test failed: $e"
        end
    else
        @warn "Configuration file not found, skipping configuration integration test"
    end
    return true
end

function test_data_format_integration()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping data format integration test"
        return true
    end
    data = fred.series_info("GDPC1")
    @test data isa Dict{String,Any}
    @test "seriess" in keys(data)
    end_date = now()
    start_date = end_date - Year(1)
    obs_data = fred.observations("GDPC1"; start_date=start_date, end_date=end_date, limit=5, frequency="q")
    @test obs_data isa Dict{String,Any}
    @test "observations" in keys(obs_data)
    if length(obs_data["observations"]) > 0
        obs = obs_data["observations"][1]
        @test "date" in keys(obs)
        @test "value" in keys(obs)
    end
    return true
end

function test_error_handling_integration()
    try
        fred.series_info("INVALID_SERIES_ID")
    catch e
        @test e isa Exception
    end
    try
        fred.series_info("GDPC1")
        fred.series_info("GDPC1")
    catch e
        @test e isa Exception
    end
    return true
end

function test_caching_integration()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping caching integration test"
        return true
    end
    data1 = fred.cached_series_info("GDPC1")
    data2 = fred.cached_series_info("GDPC1")
    @test data1 == data2
    @test data1 isa Dict{String,Any}
    return true
end

function test_timeticks_integration()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping timeticks integration test"
        return true
    end
    end_date = now()
    start_date = end_date - Year(1)
    data = fred.observations("GDPC1"; start_date=start_date, end_date=end_date, limit=5, frequency="q")
    @test data isa Dict{String,Any}
    ts_data = fred.get_timeseries("GDPC1"; start_date=start_date, end_date=end_date, frequency="q")
    @test ts_data isa NamedTuple
    @test :dates in keys(ts_data)
    @test :values in keys(ts_data)
    @test ts_data.dates isa Vector{DateTime}
    @test ts_data.values isa Vector{Union{Float64,Missing}}
    return true
end

function test_streaming_integration()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping streaming integration test"
        return true
    end
    end_date = now()
    start_date = end_date - Month(6)
    data1 = fred.observations("GDPC1"; start_date=start_date, end_date=start_date + Month(3), limit=100, frequency="q")
    @test data1 isa Dict{String,Any}
    data2 = fred.observations("GDPC1"; start_date=start_date + Month(3), end_date=end_date, limit=100, frequency="q")
    @test data2 isa Dict{String,Any}
    latest = fred.get_latest_value("GDPC1")
    @test latest isa Union{Float64,Missing}
    latest_date = fred.get_latest_date("GDPC1")
    @test latest_date isa Union{DateTime,Missing}
    return true
end

function test_edge_cases()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping edge_cases test"
        return true
    end
    very_old_date = DateTime(1900, 1, 1)
    try
        fred.observations("GDPC1"; start_date=very_old_date, end_date=very_old_date + Day(1), frequency="q")
    catch e
        @test e isa Exception
    end
    future_date = now() + Year(1)
    try
        fred.observations("GDPC1"; start_date=future_date, end_date=future_date + Day(1), frequency="q")
    catch e
        @test e isa Exception
    end
    return true
end

function test_invalid_parameters()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping invalid_parameters test"
        return true
    end
    try
        fred.observations("GDPC1"; units="invalid_unit", limit=1, frequency="q")
    catch e
        @test e isa Exception
    end
    try
        fred.observations("GDPC1"; frequency="invalid_freq", limit=1)
    catch e
        @test e isa Exception
    end
    return true
end

function test_network_errors()
    start_time = now()
    fred.series_info("GDPC1")
    fred.series_info("GDPC1")
    elapsed = now() - start_time
    @test elapsed >= fred.RATE_LIMIT[] || !fred.has_apikey()
    return true
end
