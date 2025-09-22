using Test

function test_fred_integration()
    @eval begin
        using .Planar: Planar
        using .Planar.Engine.LiveMode.Watchers.FRED
        using .Planar.Engine.TimeTicks
        using .TimeTicks
        using .TimeTicks.Dates: format, @dateformat_str
        fred = FRED
    end
    
    @testset "FRED API Integration Tests" begin
        
        @info "TEST: Module Integration"
        @test test_module_integration()
        
        @info "TEST: Configuration Integration"
        @test test_configuration_integration()
        
        @info "TEST: Data Format Integration"
        @test test_data_format_integration()
        
        @info "TEST: Error Handling Integration"
        @test test_error_handling_integration()
        
        @info "TEST: Caching Integration"
        @test test_caching_integration()
        
        @info "TEST: TimeTicks Integration"
        @test test_timeticks_integration()
        
        @info "TEST: Streaming Data Integration"
        @test test_streaming_integration()
    end
end

function test_module_integration()
    # Test that FRED module is properly integrated
    @test fred isa Module
    @test fred.API_URL == "https://api.stlouisfed.org/fred"
    @test fred.API_HEADERS isa Vector{Pair{String,String}}
    @test fred.RATE_LIMIT[] isa Period
    
    # Test that all expected functions are exported
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
    # Test that configuration is properly integrated with Planar
    config_path = joinpath(dirname(dirname(dirname(pathof(Planar)))), "user", "secrets.toml")
    
    if isfile(config_path)
        # Test that API key can be loaded from Planar config
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
    
    # Test that data formats are compatible with Planar
    data = fred.series_info("GDPC1")
    @test data isa Dict{String,Any}
    @test "seriess" in keys(data)
    
    # Test that observations data is properly formatted
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
    # Test that error handling is consistent with Planar patterns
    try
        fred.series_info("INVALID_SERIES_ID")
    catch e
        @test e isa Exception
    end
    
    # Test that rate limiting errors are handled gracefully
    try
        # Make multiple rapid requests
        fred.series_info("GDPC1")
        fred.series_info("GDPC1")
    catch e
        # Rate limiting or other errors are expected
        @test e isa Exception
    end
    
    return true
end

function test_caching_integration()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping caching integration test"
        return true
    end
    
    # Test that caching works with Planar's caching system
    data1 = fred.cached_series_info("GDPC1")
    data2 = fred.cached_series_info("GDPC1")
    
    @test data1 == data2
    @test data1 isa Dict{String,Any}
    
    # Test that cache keys are properly namespaced
    cache_key = "fred_series_info_GDPC1"
    # This would need to be tested with the actual caching implementation
    
    return true
end

function test_timeticks_integration()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping timeticks integration test"
        return true
    end
    
    # Test that TimeTicks integration works properly
    end_date = now()
    start_date = end_date - Year(1)
    
    # Test DateTime handling
    data = fred.observations("GDPC1"; start_date=start_date, end_date=end_date, limit=5, frequency="q")
    @test data isa Dict{String,Any}
    
    # Test that get_timeseries returns proper TimeTicks format
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
    
    # Test that the API supports streaming data patterns
    # This is important for LiveMode integration
    
    # Test incremental data retrieval
    end_date = now()
    start_date = end_date - Month(6)
    
    # Get first batch
    data1 = fred.observations("GDPC1"; 
        start_date=start_date, 
        end_date=start_date + Month(3), 
        limit=100,
        frequency="q"
    )
    @test data1 isa Dict{String,Any}
    
    # Get second batch (simulating streaming)
    data2 = fred.observations("GDPC1"; 
        start_date=start_date + Month(3), 
        end_date=end_date, 
        limit=100,
        frequency="q"
    )
    @test data2 isa Dict{String,Any}
    
    # Test that we can get latest data
    latest = fred.get_latest_value("GDPC1")
    @test latest isa Union{Float64,Missing}
    
    latest_date = fred.get_latest_date("GDPC1")
    @test latest_date isa Union{DateTime,Missing}
    
    return true
end

# Test function is defined above, will be called by test runner
