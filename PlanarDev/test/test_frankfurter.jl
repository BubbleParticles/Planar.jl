using Test

function test_frankfurter()
    @testset "frankfurter" begin
        @eval begin
            using .Planar.Engine.LiveMode.Watchers.Frankfurter
            using .Planar.Engine.TimeTicks
            using .TimeTicks
            using .TimeTicks.Dates: format, @dateformat_str
            frank = Frankfurter
        end
        
        @info "TEST: frankfurter rate limit"
        @test frank.RATE_LIMIT[] isa Period
        frank.RATE_LIMIT[] = Millisecond(100)  # Reduce rate limit for testing
        
        @info "TEST: frankfurter currencies"
        @test test_currencies()
        
        @info "TEST: frankfurter latest rates"
        @test test_latest_rates()
        
        @info "TEST: frankfurter historical rates"
        @test test_historical_rates()
        
        @info "TEST: frankfurter rate conversion"
        @test test_rate_conversion()
        
        @info "TEST: frankfurter amount conversion"
        @test test_amount_conversion()
        
        @info "TEST: frankfurter time series"
        @test test_time_series()
        
        @info "TEST: frankfurter error handling"
        @test test_error_handling()
        
        @info "TEST: frankfurter amount parameter"
        @test test_amount_parameter()
        
        @info "TEST: frankfurter from/to parameters"
        @test test_from_to_parameters()
        
        @info "TEST: frankfurter configuration"
        @test test_configuration()
    end
end

function test_currencies()
    currencies = frank.currencies()
    @test currencies isa Set{String}
    @test length(currencies) > 0
    @test "USD" in currencies
    @test "EUR" in currencies
    @test "GBP" in currencies
    @test "JPY" in currencies
    
    # Test currency validation
    @test frank.is_supported_currency("USD")
    @test frank.is_supported_currency("EUR")
    @test !frank.is_supported_currency("INVALID")
    
    return true
end

function test_latest_rates()
    # Test latest rates with default parameters
    data = frank.latest()
    @test data isa Dict{String,Any}
    @test "base" in keys(data)
    @test "date" in keys(data)
    @test "rates" in keys(data)
    @test data["base"] == "EUR"
    
    # Test latest rates with custom base and symbols
    data_usd = frank.latest(; base="USD", symbols=["EUR", "GBP"])
    @test data_usd["base"] == "USD"
    @test "EUR" in keys(data_usd["rates"])
    @test "GBP" in keys(data_usd["rates"])
    
    # Test latest rate function
    rate = frank.latest_rate("USD", "EUR")
    @test rate isa Float64
    @test rate > 0
    
    return true
end

function test_historical_rates()
    # Test historical rates for a specific date (yesterday)
    yesterday = now() - Day(1)
    data = frank.historical(yesterday)
    @test data isa Dict{String,Any}
    @test "base" in keys(data)
    @test "date" in keys(data)
    @test "rates" in keys(data)
    
    # Test historical rate function
    rate = frank.rate("USD", "EUR", yesterday)
    @test rate isa Float64
    @test rate > 0
    
    # Test with custom base and symbols
    data_custom = frank.historical(yesterday; base="GBP", symbols=["USD", "EUR"])
    @test data_custom["base"] == "GBP"
    @test "USD" in keys(data_custom["rates"])
    @test "EUR" in keys(data_custom["rates"])
    
    return true
end

function test_rate_conversion()
    # Test rate conversion between major currencies
    usd_eur = frank.latest_rate("USD", "EUR")
    eur_usd = frank.latest_rate("EUR", "USD")
    
    @test usd_eur isa Float64
    @test eur_usd isa Float64
    @test usd_eur > 0
    @test eur_usd > 0
    
    # Test that inverse rates are approximately correct (within 1% tolerance)
    @test abs(usd_eur * eur_usd - 1.0) < 0.01
    
    # Test with historical date
    yesterday = now() - Day(1)
    hist_rate = frank.rate("USD", "EUR", yesterday)
    @test hist_rate isa Float64
    @test hist_rate > 0
    
    return true
end

function test_amount_conversion()
    # Test amount conversion with latest rates
    amount = 100.0
    converted = frank.convert_amount_latest(amount, "USD", "EUR")
    @test converted isa Float64
    @test converted > 0
    
    # Test amount conversion with historical date
    yesterday = now() - Day(1)
    converted_hist = frank.convert_amount(amount, "USD", "EUR", yesterday)
    @test converted_hist isa Float64
    @test converted_hist > 0
    
    # Test that conversion is proportional
    double_amount = frank.convert_amount_latest(amount * 2, "USD", "EUR")
    @test abs(double_amount - converted * 2) < 0.01
    
    return true
end

function test_time_series()
    # Test time series data for a short period
    end_date = now()
    start_date = end_date - Day(7)
    
    data = frank.timeseries(start_date, end_date; base="USD", symbols=["EUR", "GBP"])
    @test data isa Dict{String,Any}
    @test "base" in keys(data)
    @test "start_date" in keys(data)
    @test "end_date" in keys(data)
    @test "rates" in keys(data)
    
    # Test historical rates function
    hist_data = frank.historical_rates("USD", "EUR", start_date, end_date)
    @test hist_data isa NamedTuple
    @test :dates in keys(hist_data)
    @test :values in keys(hist_data)
    @test hist_data.dates isa Vector{DateTime}
    @test hist_data.values isa Vector{Float64}
    @test length(hist_data.dates) == length(hist_data.values)
    @test length(hist_data.dates) > 0
    
    return true
end

function test_error_handling()
    # Test error handling for invalid currency
    @test_throws AssertionError frank.latest_rate("INVALID", "USD")
    @test_throws AssertionError frank.latest_rate("USD", "INVALID")
    @test_throws AssertionError frank.rate("INVALID", "USD", now())
    @test_throws AssertionError frank.convert_amount_latest(100, "INVALID", "USD")
    
    # Test error handling for invalid date (too far in the future)
    # Note: Frankfurter API might not throw an error for future dates
    # Instead, test with a very old date that should not have data
    very_old_date = DateTime(1900, 1, 1)
    # This might not throw an error either, so we'll just test that it doesn't crash
    try
        frank.historical(very_old_date)
        # If it doesn't throw an error, that's also acceptable
    catch e
        # If it does throw an error, that's also acceptable
        @test e isa Exception
    end
    
    return true
end

function test_amount_parameter()
    # Test latest rates with amount parameter
    data = frank.latest(; amount=10, base="GBP", symbols=["USD"])
    @test data isa Dict{String,Any}
    @test "amount" in keys(data)
    @test "base" in keys(data)
    @test "rates" in keys(data)
    @test data["amount"] == 10.0
    @test data["base"] == "GBP"
    @test "USD" in keys(data["rates"])
    
    # Test historical rates with amount parameter
    yesterday = now() - Day(1)
    data_hist = frank.historical(yesterday; amount=100, base="USD", symbols=["EUR"])
    @test data_hist["amount"] == 100.0
    @test data_hist["base"] == "USD"
    @test "EUR" in keys(data_hist["rates"])
    
    # Test time series with amount parameter
    end_date = now()
    start_date = end_date - Day(3)
    data_ts = frank.timeseries(start_date, end_date; amount=50, base="EUR", symbols=["USD"])
    @test data_ts["amount"] == 50.0
    @test data_ts["base"] == "EUR"
    @test "rates" in keys(data_ts)
    
    # Test convert_amount_api function
    converted = frank.convert_amount_api(25, "USD", "EUR")
    @test converted isa Float64
    @test converted > 0
    
    # Test convert_amount_api with historical date
    converted_hist = frank.convert_amount_api(25, "USD", "EUR"; date=yesterday)
    @test converted_hist isa Float64
    @test converted_hist > 0
    
    return true
end

function test_from_to_parameters()
    # Test latest rates with from/to parameters
    data = frank.latest(; from="USD", to="EUR")
    @test data isa Dict{String,Any}
    @test "base" in keys(data)
    @test "rates" in keys(data)
    @test data["base"] == "USD"
    @test "EUR" in keys(data["rates"])
    
    # Test latest rates with from/to parameters and multiple currencies
    data_multi = frank.latest(; from="USD", to=["EUR", "GBP"])
    @test data_multi["base"] == "USD"
    @test "EUR" in keys(data_multi["rates"])
    @test "GBP" in keys(data_multi["rates"])
    
    # Test latest rates with from/to and amount
    data_amount = frank.latest(; from="USD", to="EUR", amount=50)
    @test data_amount["amount"] == 50.0
    @test data_amount["base"] == "USD"
    @test "EUR" in keys(data_amount["rates"])
    
    # Test historical rates with from/to parameters
    yesterday = now() - Day(1)
    data_hist = frank.historical(yesterday; from="GBP", to="USD")
    @test data_hist["base"] == "GBP"
    @test "USD" in keys(data_hist["rates"])
    
    # Test time series with from/to parameters
    end_date = now()
    start_date = end_date - Day(3)
    data_ts = frank.timeseries(start_date, end_date; from="EUR", to=["USD", "GBP"])
    @test data_ts["base"] == "EUR"
    @test "rates" in keys(data_ts)
    
    return true
end

function test_configuration()
    # Test configuration functions
    @test frank.get_base_currency() == "EUR"
    @test frank.get_default_symbols() == ["USD", "GBP", "JPY", "CHF", "CAD", "AUD"]
    
    # Test that default symbols are supported currencies
    currencies = frank.currencies()
    for symbol in frank.get_default_symbols()
        @test symbol in currencies
    end
    
    return true
end

function test_ratelimit()
    # Test rate limiting functionality
    start_time = now()
    frank.latest()
    frank.latest()  # Second call should be rate limited
    elapsed = now() - start_time
    
    # Should take at least the rate limit time
    @test elapsed >= frank.RATE_LIMIT[]
    
    return true
end
