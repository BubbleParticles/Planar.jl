module Runtests

using Test
using Executors
using Executors.TimeTicks: DateTime, Day, Second, DateRange, TimeFrame
using Executors.Misc: Sim
using Executors.Misc: Long, Short, DFT

# Access Instances through Executors for mock setup
using Executors.Instances.Instruments: @a_str
using Executors.Instances.DataStructures: SortedDict
using Executors.Instances.Data: DataFrame
using Executors.Instances.TimeTicks: @tf_str
using Executors.Instances.Misc: NoMargin
const Inst = Executors.Instances

# Mock exchange setup
const exc = Executors.Instances.Exchanges.Exchange(:mocktest)
exc.markets["BTC/USDT"] = Dict{String,Any}(
    "id" => "BTC/USDT", "type" => "spot",
    "base" => "BTC", "quote" => "USDT",
    "taker" => 0.001, "maker" => 0.001,
    "precision" => Dict("amount" => 0.0001, "price" => 0.01),
    "limits" => Dict(
        "amount" => Dict("min" => 0.0001, "max" => 1000.0),
        "price" => Dict("min" => 0.01, "max" => 1000000.0),
        "cost" => Dict("min" => 1.0, "max" => 10000000.0)))
push!(exc.types, :spot)
const a = a"BTC/USDT"

const _mock_limits = (leverage=(min=1.0, max=10.0), amount=(min=1e-8, max=1e8),
                       price=(min=1e-8, max=1e8), cost=(min=1e-8, max=1e8))
const _mock_precision = (amount=1e-8, price=1e-8)
const _mock_fees = (taker=0.01, maker=0.01, min=0.01, max=0.01)

function _make_ai()
    data = SortedDict{TimeFrame,DataFrame}(tf"1m" => DataFrame())
    Inst.AssetInstance(a, data, exc, NoMargin();
        limits=_mock_limits, precision=_mock_precision, fees=_mock_fees)
end

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

        @testset "OrderIterator full merge" begin
            i1 = [(1.0 => "a"), (4.0 => "d")]
            i2 = [(2.0 => "b"), (3.0 => "c")]
            oi = Executors.OrderIterator(i1, i2)
            @test Executors.Base.last(oi) == (4.0 => "d")
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
            @test Executors.unfillment(Executors.OrderTypes.BuyOrder, 0.0) == 0.0
            @test Executors.unfillment(Executors.OrderTypes.SellOrder, 0.0) == 0.0
        end
    end

    @testset "context.jl" begin
        @testset "Context with mode and daterange" begin
            dr = DateRange(DateTime(2020, 1, 1), DateTime(2020, 1, 31), TimeFrame("1h"))
            ctx = Executors.Context(Sim(), dr)
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

    @testset "Checks pure functions" begin
        @testset "checkamount" begin
            @test isnothing(Executors.Checks.checkamount(1.0))
            @test isnothing(Executors.Checks.checkamount(0.0))
            @test_throws AssertionError Executors.Checks.checkamount(-1.0)
        end

        @testset "_cost_msg" begin
            msg = Executors.Checks._cost_msg("BTC/USDT", "below", 10.0, 5.0)
            @test occursin("BTC/USDT", msg)
            @test occursin("below", msg)
        end
    end

    @testset "positions/state pure functions" begin
        @testset "_buffered" begin
            using Executors.Misc: Long, Short
            price = 100.0
            buffered_long = Executors._buffered(price, Long())
            @test buffered_long < price
            buffered_short = Executors._buffered(price, Short())
            @test buffered_short > price
        end

        @testset "_checkbuffered" begin
            using Executors.Misc: Long, Short
            @test Executors._checkbuffered(95.0, 100.0, Long())
            @test Executors._checkbuffered(100.0, 100.0, Long())
            @test !Executors._checkbuffered(101.0, 100.0, Long())
            @test Executors._checkbuffered(105.0, 100.0, Short())
            @test Executors._checkbuffered(100.0, 100.0, Short())
            @test !Executors._checkbuffered(99.0, 100.0, Short())
        end

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

    @testset "orders/state pure functions" begin
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

    @testset "Checks with AssetInstance" begin
        ai = _make_ai()

        @testset "ismincost" begin
            @test Executors.Checks.ismincost(ai, 100.0, 1.0)
            @test !Executors.Checks.ismincost(ai, 100.0, 1e-12)
        end

        @testset "ismaxcost" begin
            @test Executors.Checks.ismaxcost(ai, 1.0, 1.0)
            @test !Executors.Checks.ismaxcost(ai, 1e9, 1e9)
        end

        @testset "checkcost" begin
            @test Executors.Checks.checkcost(ai, 1.0, 100.0)
        end

        @testset "checkcost keyword" begin
            @test Executors.Checks.checkcost(ai; amount=1.0, price=100.0)
        end

        @testset "iscost" begin
            @test Executors.Checks.iscost(ai, 1.0, 100.0)
            @test !Executors.Checks.iscost(ai, 1e-12, 1e-12)
        end

        @testset "iscost keyword" begin
            @test Executors.Checks.iscost(ai; amount=1.0, price=100.0)
            @test !Executors.Checks.iscost(ai; amount=1e-12, price=1e-12)
        end

        @testset "sanitize_amount" begin
            @test Executors.Checks.sanitize_amount(ai, 5.0) ≈ 5.0
            @test Executors.Checks.sanitize_amount(ai, 0.0) ≈ 1e-8
        end

        @testset "sanitize_price" begin
            @test Executors.Checks.sanitize_price(ai, 50000.0) ≈ 50000.0
        end
    end

    @testset "committment for NoMarginInstance" begin
        ai = _make_ai()

        @testset "IncreaseOrder" begin
            comm = Executors.committment(Executors.OrderTypes.IncreaseOrder, ai, 100.0, 2.0)
            expected_cost = Executors.Checks.cost(100.0, 2.0)
            expected_fees = expected_cost * 0.01
            @test comm ≈ expected_cost + expected_fees
        end

        @testset "SellOrder" begin
            comm = Executors.committment(Executors.OrderTypes.SellOrder, ai, 100.0, 2.0)
            @test comm ≈ 2.0
        end

        @testset "ShortBuyOrder" begin
            comm = Executors.committment(Executors.OrderTypes.ShortBuyOrder, ai, 100.0, 2.0)
            @test comm ≈ -2.0
        end
    end

    @testset "committed, unfilled, unfillment on basic_order_state" begin
        c = Ref(200.0)
        u = Ref(-2.0)
        state = Executors.basic_order_state(nothing, nothing, c, u)
        @test Executors.Base.getfield(state, :committed)[] ≈ 200.0
        @test Executors.Base.getfield(state, :unfilled)[] ≈ -2.0
    end
end

end
