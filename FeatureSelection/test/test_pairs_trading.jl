@testset "pairs_trading.jl tests" failfast=true begin
    using .FeatureSelection: pairs_trading_signals, ratio!, find_cointegrated_prices, detect_correlation_regime
    using Random
    
    @testset "pairs_trading_signals function" begin
        # Set random seed for reproducibility
        Random.seed!(123)
        
        # Create cointegrated price series
        n = 100
        spread = cumsum(randn(n))  # Random walk spread
        p1 = cumsum(randn(n))  # Random walk for asset 1
        p2 = p1 + spread  # Asset 2 is cointegrated with asset 1 plus some spread
        
        # Generate signals
        lookback = 20
        result = pairs_trading_signals((p1, p2), lookback)
        
        # Test output structure
        @test result isa DataFrame
        @test names(result) == [:timestamp, :spread, :spread_mean, :spread_std, :zscore, :signal]
        @test size(result, 1) == n
        
        # Test signal generation (basic checks)
        # First lookback-1 entries should have NaN for statistics
        @test all(ismissing, result.spread_mean[1:lookback-1])
        @test all(ismissing, result.spread_std[1:lookback-1])
        @test all(ismissing, result.zscore[1:lookback-1])
        
        # After lookback, we should have valid statistics
        @test all(!ismissing, result.spread_mean[lookback:end])
        @test all(!ismissing, result.spread_std[lookend:end])
        @test all(!ismissing, result.zscore[lookback:end])
        
        # Test signal values (should be -1, 0, or 1)
        @test all(x -> x in (-1, 0, 1), result.signal[lookback:end])
        
        # Test with custom zscore threshold
        result_custom = pairs_trading_signals((p1, p2), lookback, zscore_threshold=1.0)
        @test all(x -> x in (-1, 0, 1), result_custom.signal[lookback:end])
        
        # More signals should be generated with lower threshold
        @test sum(abs.(result_custom.signal)) >= sum(abs.(result.signal))
    end
    
    @testset "find_cointegrated_pairs function" begin
        # Create test data with cointegrated and non-cointegrated pairs
        n = 100
        Random.seed!(123)
        
        # Cointegrated pair
        spread1 = cumsum(randn(n)) .* 0.1  # Stationary spread
        p1 = cumsum(randn(n))
        p2 = p1 + spread1
        
        # Non-cointegrated pair
        p3 = cumsum(randn(n))
        p4 = cumsum(randn(n))
        
        prices = Dict("A" => p1, "B" => p2, "C" => p3, "D" => p4)
        
        # Find cointegrated pairs
        cointegrated = find_cointegrated_prices(prices, pvalue_threshold=0.05)
        
        # Check output structure
        @test cointegrated isa DataFrame
        @test names(cointegrated) == [:asset1, :asset2, :coint_pvalue, :adf_pvalue, :half_life]
        
        # At least the cointegrated pair should be found
        has_ab = any(row -> 
            (row.asset1 == "A" && row.asset2 == "B") || 
            (row.asset1 == "B" && row.asset2 == "A"), 
            eachrow(cointegrated)
        )
        @test has_ab
        
        # Half-life should be positive and finite
        if nrow(cointegrated) > 0
            @test all(isfinite, cointegrated.half_life)
            @test all(>=(0), cointegrated.half_life)
        end
    end
    
    @testset "detect_correlation_regime function" begin
        # Create test data with two correlation regimes
        n = 100
        p = 3  # Number of assets
        
        # First regime: high correlation
        corr_high = 0.9
        Σ_high = fill(corr_high, p, p)
        Σ_high[diagind(Σ_high)] .= 1.0
        
        # Second regime: low correlation
        corr_low = 0.1
        Σ_low = fill(corr_low, p, p)
        Σ_low[diagind(Σ_low)] .= 1.0
        
        # Generate correlation matrices alternating between regimes
        n_matrices = 50
        corr_matrices = zeros(p, p, n_matrices)
        for i in 1:n_matrices
            corr_matrices[:, :, i] = i <= n_matrices/2 ? Σ_high : Σ_low
        end
        
        # Detect regimes
        n_regimes = 2
        regimes = detect_correlation_regime(corr_matrices, window=5, n_regimes=n_regimes)
        
        # Check output
        @test length(regimes) == n_matrices
        @test all(1 .<= regimes .<= n_regimes)
        
        # Most of the first half should be in one regime, second half in the other
        first_half = regimes[1:div(end, 2)]
        second_half = regimes[div(end, 2)+1:end]
        
        # The dominant regime in each half should be different
        mode1 = mode(first_half)
        mode2 = mode(second_half)
        @test mode1 != mode2
        
        # At least 80% of each half should be in the dominant regime
        @test count(==(mode1), first_half) / length(first_half) >= 0.8
        @test count(==(mode2), second_half) / length(second_half) >= 0.8
    end
end
