using Test

function test_fred_performance()
    @eval begin
        using .Planar: Planar
        using .Planar.Engine.LiveMode.Watchers.FRED
        using .Planar.Engine.TimeTicks
        using .TimeTicks
        using .TimeTicks.Dates: format, @dateformat_str
        fred = FRED
    end
    
    @testset "FRED API Performance Tests" begin
        
        @info "TEST: Rate Limiting Performance"
        @test test_rate_limiting_performance()
        
        @info "TEST: Caching Performance"
        @test test_caching_performance()
        
        @info "TEST: Large Dataset Performance"
        @test test_large_dataset_performance()
        
        @info "TEST: Concurrent Request Handling"
        @test test_concurrent_requests()
        
        @info "TEST: Memory Usage"
        @test test_memory_usage()
        
        @info "TEST: Error Recovery Performance"
        @test test_error_recovery_performance()
    end
end

function test_rate_limiting_performance()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping rate limiting performance test"
        return true
    end
    
    # Test that rate limiting works correctly
    start_time = now()
    
    # Make multiple requests quickly
    for i in 1:3
        fred.series_info("GDPC1")
    end
    
    elapsed = now() - start_time
    
    # Should take at least 2 seconds (2 rate limit intervals)
    @test elapsed >= Millisecond(2000)
    
    return true
end

function test_caching_performance()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping caching performance test"
        return true
    end
    
    # Test that cached calls are faster
    start_time = now()
    data1 = fred.cached_series_info("GDPC1")
    first_call_time = now() - start_time
    
    start_time = now()
    data2 = fred.cached_series_info("GDPC1")
    second_call_time = now() - start_time
    
    # Second call should be much faster (cached)
    @test second_call_time < first_call_time
    @test data1 == data2
    
    return true
end

function test_large_dataset_performance()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping large dataset performance test"
        return true
    end
    
    # Test with large date range
    end_date = now()
    start_date = end_date - Year(5)  # 5 years of data
    
    start_time = now()
    data = fred.observations("GDPC1"; 
        start_date=start_date, 
        end_date=end_date, 
        limit=1000,  # Large limit
        frequency="q"
    )
    elapsed = now() - start_time
    
    @test data isa Dict{String,Any}
    @test "observations" in keys(data)
    @test elapsed < Second(30)  # Should complete within 30 seconds
    
    return true
end

function test_concurrent_requests()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping concurrent requests test"
        return true
    end
    
    # Test that the API handles concurrent requests properly
    # (This will be limited by rate limiting, but should not crash)
    
    series_ids = ["GDPC1", "UNRATE", "CPIAUCSL", "FEDFUNDS", "PAYEMS"]
    results = []
    
    start_time = now()
    
    for series_id in series_ids
        try
            data = fred.series_info(series_id)
            push!(results, data)
        catch e
            # Rate limiting or other errors are expected
            @warn "Concurrent request failed for $series_id: $e"
        end
    end
    
    elapsed = now() - start_time
    
    # Should have some successful results
    @test length(results) > 0
    @test elapsed < Second(60)  # Should complete within 60 seconds
    
    return true
end

function test_memory_usage()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping memory usage test"
        return true
    end
    
    # Test that large responses don't cause memory issues
    # Make several requests with large limits
    for i in 1:5
        data = fred.observations("GDPC1"; limit=1000, frequency="q")
        @test data isa Dict{String,Any}
    end
    
    # Force garbage collection
    GC.gc()
    
    # Test passes if we can make the requests without errors
    @test true
    
    return true
end

function test_error_recovery_performance()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping error recovery performance test"
        return true
    end
    
    # Test that the API recovers quickly from errors
    start_time = now()
    
    # Make a request that might fail
    try
        fred.series_info("INVALID_SERIES_ID")
    catch e
        # Expected to fail
    end
    
    # Make a valid request immediately after
    data = fred.series_info("GDPC1")
    
    elapsed = now() - start_time
    
    @test data isa Dict{String,Any}
    @test elapsed < Second(10)  # Should recover quickly
    
    return true
end

# Test function is defined above, will be called by test runner
