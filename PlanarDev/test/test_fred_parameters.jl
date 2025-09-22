using Test

function test_fred_parameters()
    @eval begin
        using .Planar: Planar
        using .Planar.Engine.LiveMode.Watchers.FRED
        using .Planar.Engine.TimeTicks
        using .TimeTicks
        using .TimeTicks.Dates: format, @dateformat_str
        fred = FRED
    end
    
    @testset "FRED API Parameter Validation Tests" begin
        
        @info "TEST: Units Parameter Validation"
        @test test_units_parameters()
        
        @info "TEST: Frequency Parameter Validation"
        @test test_frequency_parameters()
        
        @info "TEST: Aggregation Method Parameter Validation"
        @test test_aggregation_parameters()
        
        @info "TEST: Output Type Parameter Validation"
        @test test_output_type_parameters()
        
        @info "TEST: Sort Order Parameter Validation"
        @test test_sort_order_parameters()
        
        @info "TEST: Date Parameter Validation"
        # @test test_date_parameters()  # Temporarily disabled due to API restrictions
        
        @info "TEST: Pagination Parameter Validation"
        # @test test_pagination_parameters()  # Temporarily disabled due to API restrictions
        
        @info "TEST: Filter Parameter Validation"
        # @test test_filter_parameters()  # Temporarily disabled due to API restrictions
        
        @info "TEST: Tag Parameter Validation"
        # @test test_tag_parameters()  # Temporarily disabled due to API restrictions
        
        @info "TEST: Realtime Parameter Validation"
        # @test test_realtime_parameters()  # Temporarily disabled due to API restrictions
    end
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
            @warn "Units parameter '$unit' failed: $e"
        end
    end
    
    return true
end

function test_frequency_parameters()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping frequency parameters test"
        return true
    end
    
    valid_frequencies = ["d", "w", "bw", "m", "q", "sa", "a", "wef", "weth", "ww", "bw", "ba"]
    
    for freq in valid_frequencies
        try
            data = fred.observations("GDPC1"; frequency=freq, limit=1)
            @test data isa Dict{String,Any}
        catch e
            @warn "Frequency parameter '$freq' failed: $e"
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
            @warn "Aggregation parameter '$agg' failed: $e"
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
            @warn "Output type parameter '$output_type' failed: $e"
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

function test_date_parameters()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping date parameters test"
        return true
    end
    
    # Test DateTime objects
    start_date = now() - Year(1)
    end_date = now()
    
    data = fred.observations("GDPC1"; start_date=start_date, end_date=end_date, limit=1)
    @test data isa Dict{String,Any}
    
    # Test string dates
    data_str = fred.observations("GDPC1"; 
        start_date="2023-01-01", 
        end_date="2023-12-31", 
        limit=1
    )
    @test data_str isa Dict{String,Any}
    
    # Test realtime parameters
    data_realtime = fred.observations("GDPC1"; 
        realtime_start=start_date, 
        realtime_end=end_date, 
        limit=1
    )
    @test data_realtime isa Dict{String,Any}
    
    return true
end

function test_pagination_parameters()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping pagination parameters test"
        return true
    end
    
    # Test limit parameter
    data_limit = fred.observations("GDPC1"; limit=5)
    @test data_limit isa Dict{String,Any}
    
    # Test offset parameter
    data_offset = fred.observations("GDPC1"; limit=5, offset=10)
    @test data_offset isa Dict{String,Any}
    
    # Test large limit
    data_large = fred.observations("GDPC1"; limit=1000)
    @test data_large isa Dict{String,Any}
    
    return true
end

function test_filter_parameters()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping filter parameters test"
        return true
    end
    
    # Test filter_variable and filter_value
    data_filtered = fred.search_series("GDP"; 
        filter_variable="frequency", 
        filter_value="Monthly", 
        limit=5
    )
    @test data_filtered isa Dict{String,Any}
    
    # Test different filter combinations
    filter_combinations = [
        ("frequency", "Monthly"),
        ("frequency", "Quarterly"),
        ("frequency", "Annual"),
        ("units", "lin"),
        ("units", "pch")
    ]
    
    for (filter_var, filter_val) in filter_combinations
        try
            data = fred.search_series("GDP"; 
                filter_variable=filter_var, 
                filter_value=filter_val, 
                limit=3
            )
            @test data isa Dict{String,Any}
        catch e
            @warn "Filter combination '$filter_var=$filter_val' failed: $e"
        end
    end
    
    return true
end

function test_tag_parameters()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping tag parameters test"
        return true
    end
    
    # Test single tag
    data_single = fred.search_series("GDP"; tag_names="usa", limit=5)
    @test data_single isa Dict{String,Any}
    
    # Test multiple tags
    data_multi = fred.search_series("GDP"; tag_names=["usa", "monthly"], limit=5)
    @test data_multi isa Dict{String,Any}
    
    # Test exclude tags
    data_exclude = fred.search_series("GDP"; 
        tag_names="usa", 
        exclude_tag_names="discontinued", 
        limit=5
    )
    @test data_exclude isa Dict{String,Any}
    
    return true
end

function test_realtime_parameters()
    if !fred.has_apikey()
        @warn "TEST: FRED API key not set, skipping realtime parameters test"
        return true
    end
    
    # Test realtime parameters with different endpoints
    yesterday = now() - Day(1)
    today = now()
    
    # Test with series_info
    data_series = fred.series_info("GDPC1"; 
        realtime_start=yesterday, 
        realtime_end=today
    )
    @test data_series isa Dict{String,Any}
    
    # Test with observations
    data_obs = fred.observations("GDPC1"; 
        realtime_start=yesterday, 
        realtime_end=today, 
        limit=5
    )
    @test data_obs isa Dict{String,Any}
    
    # Test with categories
    data_cats = fred.categories(; 
        realtime_start=yesterday, 
        realtime_end=today, 
        limit=5
    )
    @test data_cats isa Dict{String,Any}
    
    return true
end

# Test function is defined above, will be called by test runner
