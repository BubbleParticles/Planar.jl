using Test
using OnlineTechnicalIndicators
using Main.oneAPI
using StrategyTools.GPUIndicators

# Helper function to create a oneAPI.oneArray
function to_oneapi(a)
    oneAPI.oneArray(a)
end

@testset "GPU Indicators" begin
    @testset "RSI" begin
        # Test data
        data = [45.34, 44.95, 45.10, 45.25, 45.50, 45.75, 45.90, 46.10, 46.00, 45.80]
        period = 5

        # CPU RSI
        rsi_cpu = RSI(period=period)
        for val in data
            fit!(rsi_cpu, val)
        end

        # GPU RSI
        rsi_gpu = RSI(period=period)
        # Manually convert internal buffers to oneAPI arrays for testing
        rsi_gpu.avg_gain.input_values.buffer = to_oneapi(rsi_gpu.avg_gain.input_values.buffer)
        rsi_gpu.avg_loss.input_values.buffer = to_oneapi(rsi_gpu.avg_loss.input_values.buffer)

        for val in data
            fit_gpu!(rsi_gpu, val)
        end

        @test value(rsi_cpu) ≈ value(rsi_gpu) atol=1e-5
    end
end
