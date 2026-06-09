module Runtests

using Test
using Executors
using Executors.TimeTicks: DateTime, Day, Second, DateRange, TimeFrame
using Executors.Misc: Sim

@testset "Executors" begin
    @testset "checks.jl" begin
        @testset "cost" begin
            @test Executors.Checks.cost(100.0, 2.0) == 200.0
            @test Executors.Checks.cost(100.0, 2.0, 5.0) == 40.0
            @test Executors.Checks.cost(-100.0, 2.0) == 200.0
        end

        @testset "withfees" begin
            @test Executors.Checks.withfees(100.0, 0.01, Executors.OrderTypes.IncreaseOrder) ≈ 101.0
            @test Executors.Checks.withfees(100.0, 0.01, Executors.OrderTypes.ReduceOrder) ≈ 99.0
        end

        @testset "ismonotonic" begin
            @test Executors.Checks.ismonotonic(1.0, 2.0, 3.0) == true
            @test Executors.Checks.ismonotonic(3.0, 2.0, 1.0) == false
            @test Executors.Checks.ismonotonic(1.0, nothing, 3.0) == true
            @test Executors.Checks.ismonotonic(1.0) == true
        end

        @testset "Sanitize types" begin
            @test Executors.Checks.SanitizeOn() isa Executors.Checks.SanitizeOn
            @test Executors.Checks.SanitizeOff() isa Executors.Checks.SanitizeOff
        end
    end

    @testset "orders/iter.jl" begin
        @testset "OrderIterator empty" begin
            oi = Executors.OrderIterator()
            @test isempty(collect(oi))
            @test Executors.Base.isdone(oi) == true
        end

        @testset "OrderIterator single iter" begin
            items = [(1.0 => "a"), (2.0 => "b"), (3.0 => "c")]
            oi = Executors.OrderIterator(items)  # hits OrderIterator(gen)
            @test Executors.Base.isdone(oi) == false
            @test length(oi.iters) == 3
        end

        @testset "OrderIterator multi iter merge" begin
            i1 = [(1.0 => "a"), (3.0 => "c")]
            i2 = [(2.0 => "b")]
            oi = Executors.OrderIterator(i1, i2)  # hits args... constructor
            @test count(oi) == 3
        end

        @testset "OrderIterator last" begin
            i1 = [(1.0 => "a"), (3.0 => "c")]
            i2 = [(2.0 => "b")]
            oi = Executors.OrderIterator(i1, i2)
            @test Executors.Base.last(oi) == (3.0 => "c")
        end

        @testset "isdone" begin
            oi = Executors.OrderIterator()
            @test Executors.Base.isdone(oi) == true
            oi2 = Executors.OrderIterator([(1.0 => "a")])
            @test Executors.Base.isdone(oi2) == false
        end
    end

    @testset "orders/utils.jl" begin
        @testset "type aliases" begin
            @test Executors.AnyLimitOrder <: Executors.Order
            @test Executors.AnyMarketOrder <: Executors.Order
            @test Executors.AnyFOKOrder <: Executors.Order
            @test Executors.AnyIOCOrder <: Executors.Order
            @test Executors.AnyGTCOrder <: Executors.Order
            @test Executors.AnyPostOnlyOrder <: Executors.Order
        end

        @testset "unfillment" begin
            @test Executors.unfillment(Executors.OrderTypes.BuyOrder, 10.0) == -10.0
            @test Executors.unfillment(Executors.OrderTypes.SellOrder, 10.0) == 10.0
        end
    end

    @testset "orders/state.jl" begin
        @testset "basic_order_state" begin
            comm = Ref(100.0)
            unf = Ref(-10.0)
            state = Executors.basic_order_state(nothing, nothing, comm, unf)
            @test state.committed[] == 100.0
            @test state.unfilled[] == -10.0
            @test state.take === nothing
            @test state.stop === nothing
            @test state.trades == Executors.Trade[]
        end

        @testset "LIQUIDATION constants" begin
            @test Executors.LIQUIDATION_BUFFER < 0.0
            @test Executors.LIQUIDATION_FEES > 0.0
        end
    end

    @testset "positions/state.jl" begin
        @testset "_inv" begin
            @test Executors._inv(Executors.Misc.Long(), 10.0, 0.01) ≈ 1.0 - 1.0/10.0 + 0.01
            @test Executors._inv(Executors.Misc.Short(), 10.0, 0.01) ≈ 1.0 + 1.0/10.0 - 0.01
        end

        @testset "liqprice" begin
            lp = Executors.liqprice(Executors.Misc.Long(), 100.0, 10.0, 0.01)
            @test lp ≈ 100.0 * (1.0 - 1.0/10.0 + 0.01)

            lp2 = Executors.liqprice(Executors.Misc.Short(), 100.0, 10.0, 0.01)
            @test lp2 ≈ 100.0 * (1.0 + 1.0/10.0 - 0.01)
        end
    end

    @testset "context.jl" begin
        @testset "Context with mode and daterange" begin
            dr = DateRange(DateTime(2020, 1, 1), DateTime(2020, 1, 31), TimeFrame("1h"))
            ctx = Executors.Context(Sim(), dr)
            @test ctx isa Executors.Context{Sim}
        end

        @testset "Context with string timeframe, from, to" begin
            ctx = Executors.Context(Sim(), "1h", "2020-01-01", "2020-01-31")
            @test ctx isa Executors.Context{Sim}
        end

        @testset "Context with since period" begin
            ctx = Executors.Context(Sim(), TimeFrame("1h"), Day(7))
            @test ctx isa Executors.Context{Sim}
        end

        @testset "execmode" begin
            dr = DateRange(DateTime(2020, 1, 1), DateTime(2020, 1, 31), TimeFrame("1h"))
            ctx = Executors.Context(Sim(), dr)
            @test Executors.execmode(ctx) == Sim
        end
    end

    @testset "functions.jl" begin
        @testset "priceat fallback throws" begin
            @test_throws MethodError Executors.priceat(
                Sim(), Executors.OrderTypes.BuyOrder, nothing, DateTime(2020,1,1)
            )
        end
    end
end

end
