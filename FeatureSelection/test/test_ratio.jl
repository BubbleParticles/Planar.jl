using Test
using FeatureSelection
using LinearAlgebra
using FeatureSelection: ratio!, ratio, roc_ratio

@testset "ratio.jl tests" failfast=true begin
    @testset "ratio! function" begin
        # Test 1D array
        x = [1.0, 2.0, 4.0, 8.0]
        output = zeros(length(x)-1)
        ratio!(output, x)
        @test output ≈ [1.0, 1.0, 1.0]  # [(2-1)/1, (4-2)/2, (8-4)/4] = [1, 1, 1]
        
        # Test 2D array along first dimension
        A = [1.0 4.0 9.0; 2.0 8.0 18.0]
        output = zeros(1, 3)
        ratio!(output, A, dims=1)
        @test output ≈ [1.0 1.0 1.0]  # [(2-1)/1, (8-4)/4, (18-9)/9] = [1, 1, 1]
        
        # Test 2D array along second dimension
        output = zeros(2, 2)
        ratio!(output, A, dims=2)
        @test output ≈ [3.0 1.25; 3.0 1.25]  # [(4-1)/1, (9-4)/4; (8-2)/2, (18-8)/8] = [3, 1.25; 3, 1.25]
        
        # Test error handling for wrong output size
        output_wrong = zeros(2)
        @test_throws ArgumentError ratio!(output_wrong, x)
    end
    
    @testset "ratio function" begin
        # Test 1D array
        x = [1.0, 2.0, 4.0, 8.0]
        result = ratio(x)
        @test result ≈ [1.0, 1.0, 1.0]
        
        # Test 2D array along first dimension
        A = [1.0 4.0 9.0; 2.0 8.0 18.0]
        @test ratio(A, dims=1) ≈ [1.0 1.0 1.0]
        
        # Test 2D array along second dimension
        @test ratio(A, dims=2) ≈ [3.0 1.25; 3.0 1.25]
    end
    
    @testset "roc_ratio function" begin
        # Test basic ROC calculation
        x = [100.0, 105.0, 110.25, 115.76]  # 5% increase each step
        result = roc_ratio(x, period=1)
        @test result ≈ [0.05, 0.05, 0.05] atol=1e-4
        
        # Test with different period
        result = roc_ratio(x, period=2)
        @test result ≈ [0.0, 0.05] atol=1e-4  # (1.05^2 - 1) for each period
        
        # Test 2D array
        A = [100.0 200.0; 105.0 210.0; 110.25 220.5; 115.76 231.52]
        result = roc_ratio(A, period=1, dims=1)
        @test size(result) == (3, 2)
        @test all(isapprox.(result, 0.05, atol=1e-4))
    end
    
    @testset "Vector of Vectors" begin
        # Test ratio with vector of vectors
        v = [[1.0, 2.0, 4.0], [4.0, 8.0, 16.0], [16.0, 32.0, 64.0]]
        result = ratio(v, dims=1)
        @test result ≈ [1.0 1.0 1.0; 1.0 1.0 1.0]
        
        # Test roc_ratio with vector of vectors
        v = [[100.0, 200.0], [105.0, 210.0], [110.25, 220.5], [115.76, 231.52]]
        result = roc_ratio(v, period=1)
        @test result ≈ [1.0 1.0 1.0 1.0] atol=1e-8
    end
end
