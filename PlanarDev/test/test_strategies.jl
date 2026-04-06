_strategies_load() = begin
    @eval begin
        using .Planar.Engine.TimeTicks
        using .Planar.Engine.Simulations: Simulations as sml
        using .Planar.Engine.Data: Data as da
        using .Planar.Engine
        PlanarDev.@environment!
        @info get(ENV, "JULIA_TEST", "NO TEST")
        @info get(ENV, "TEST", "NO TEST2")
        if isnothing(Base.find_package("BlackBoxOptim")) && @__MODULE__() == Main
            import Pkg
            Pkg.add("BlackBoxOptim")
        end
    end
end

function test_strategies()
    _strategies_load()
    @testset "strategies" begin
        cfg = Planar.Engine.Misc.Config(exchange=Main.EXCHANGE)
        @test cfg isa Planar.Engine.Misc.Config
        @test cfg.exchange == Main.EXCHANGE
        s = Planar.Engine.Strategies.strategy!(:Example, cfg)
        @test s isa Planar.Engine.Strategies.Strategy
        @test nameof(Planar.Engine.Strategies.cash(s)) == :USDT
        @test Planar.Engine.Strategies.execmode(s) == Planar.Engine.Strategies.Sim()
        @test Planar.Engine.Strategies.marginmode(s) == Planar.Engine.Misc.NoMargin()
        @test typeof(s).parameters[3] <: PlanarDev.Planar.ExchangeTypes.ExchangeID
        @test nameof(s) == :Example
        @test nameof(Planar.Engine.Strategies.exchange(s)) == Main.EXCHANGE
        @test sort!(Planar.Engine.Instruments.raw.(s.universe.data.asset)) == sort!(["ETH/USDT", "BTC/USDT", "SOL/USDT"])
    end
end
