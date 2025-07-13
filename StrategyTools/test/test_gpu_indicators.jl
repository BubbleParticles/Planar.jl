using Test
using OnlineTechnicalIndicators
using oneAPI
using StrategyTools.GPUIndicators

# Helper function to create a oneAPI.oneArray
function to_oneapi(a)
    oneAPI.oneArray(a)
end

@testset "GPU Indicators" begin
    data = [45.34, 44.95, 45.10, 45.25, 45.50, 45.75, 45.90, 46.10, 46.00, 45.80]
    period = 5

    @testset "SMA" begin
        # CPU SMA
        sma_cpu = SMA(period=period)
        for val in data
            fit!(sma_cpu, val)
        end

        # GPU SMA
        sma_gpu = SMA(period=period)
        sma_gpu.input_values.buffer = to_oneapi(sma_gpu.input_values.buffer)
        for val in data
            fit_gpu!(sma_gpu, val)
        end

        @test value(sma_cpu) ≈ value(sma_gpu) atol=1e-5
    end

    @testset "EMA" begin
        # CPU EMA
        ema_cpu = EMA(period=period)
        for val in data
            fit!(ema_cpu, val)
        end

        # GPU EMA
        ema_gpu = EMA(period=period)
        ema_gpu.input_values.buffer = to_oneapi(ema_gpu.input_values.buffer)
        for val in data
            fit_gpu!(ema_gpu, val)
        end

        @test value(ema_cpu) ≈ value(ema_gpu) atol=1e-5
    end

    @testset "RSI" begin
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
