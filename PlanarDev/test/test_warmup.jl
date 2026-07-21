using PlanarDev.Stubs
using Test
using .Planar.Engine.Simulations: Simulations as sml
using .Planar.Engine.Data: Data as da
using .Planar.Engine.Strategies: Strategies as st
using .Planar.Engine.Executors: Executors as ex
using .Planar.Engine.Misc: Misc as ms
using .Planar.Engine.Lang: Lang as lg

# Test helper functions
function create_mock_strategy()
    @eval begin
        using PlanarDev.Planar.Engine: Engine as egn
        using .egn.Strategies: Strategies as st
        PlanarDev.@environment!
    end

    cfg = Config(exchange=EXCHANGE)
    s = st.strategy!(:Example, cfg)
    return s
end

function test_init_sim_warmup()
    @eval begin
        using PlanarDev.Planar.Engine: Engine as egn
        using .egn.Strategies: Strategies as st
        using .egn.TimeTicks: Minute, Day, Hour
        PlanarDev.@environment!
        PlanarDev.tools!()  # Load StrategyTools
    end

    @testset "InitSimWarmup Tests" begin
        s = create_mock_strategy()

        # Test that we can access the InitSimWarmup action
        @test isdefined(stt, :InitSimWarmup)
        @test isdefined(stt, :SimWarmup)

        init_action = stt.InitSimWarmup()

        @testset "Basic initialization" begin
            st.call!(s, init_action)

            # Check that warmup attributes are properly initialized
            @test haskey(s.attrs, :warmup_lock)
            @test s.attrs[:warmup_lock] isa ReentrantLock
            @test haskey(s.attrs, :warmup_timeout)
            @test s.attrs[:warmup_timeout] == Minute(15)  # default timeout
            @test haskey(s.attrs, :warmup_running)
            @test s.attrs[:warmup_running] == false
            @test haskey(s.attrs, :warmup)
            @test s.attrs[:warmup] isa Dict
            @test haskey(s.attrs, :warmup_candles)
            @test s.attrs[:warmup_candles] >= 100

            # Check that all assets in universe are marked as not warmed up
            for ai in s.universe
                @test haskey(s.attrs[:warmup], ai)
                @test s.attrs[:warmup][ai] == false
            end
        end

        @testset "Custom timeout and warmup period" begin
            s = create_mock_strategy()
            custom_timeout = Minute(30)
            custom_period = Day(2)

            st.call!(s, init_action; timeout=custom_timeout, warmup_period=custom_period)

            @test s.attrs[:warmup_timeout] == custom_timeout
            # warmup_candles should be calculated based on custom period
            @test s.attrs[:warmup_candles] >= 100
        end

        @testset "Warmup simulator flag handling" begin
            s = create_mock_strategy()
            s.attrs[:is_warmup_sim] = true

            st.call!(s, init_action)

            # When marked as warmup sim, all assets should be marked as warmed up
            for ai in s.universe
                @test s.attrs[:warmup][ai] == true
            end
            @test s.attrs[:warmup_candles] == 0
        end
    end
end

function test_sim_warmup_basic()
    @eval begin
        using PlanarDev.Planar.Engine: Engine as egn
        using .egn.Strategies: Strategies as st
        using .egn.TimeTicks: Minute, Day, Hour
        using .egn.Instances: AssetInstance
        PlanarDev.@environment!
        PlanarDev.tools!()  # Load StrategyTools
    end

    @testset "SimWarmup Basic Tests" begin
        s = create_mock_strategy()
        st.call!(s, stt.InitSimWarmup())
        warmup_action = stt.SimWarmup()

        @testset "Skip warmup if already warmed" begin
            ai = first(s.universe)
            s.attrs[:warmup][ai] = true  # Mark as already warmed

            callback_called = false
            test_callback = (args...) -> callback_called = true

            st.call!(test_callback, s, ai, DateTime(2024, 1, 15), warmup_action)

            @test !callback_called  # Should not call callback if already warmed
        end

        @testset "Skip warmup if already running" begin
            s = create_mock_strategy()
            st.call!(s, stt.InitSimWarmup())
            ai = first(s.universe)
            s.attrs[:warmup_running] = true  # Mark as running

            callback_called = false
            test_callback = (args...) -> callback_called = true

            st.call!(test_callback, s, ai, DateTime(2024, 1, 15), warmup_action)

            @test !callback_called  # Should not call callback if warmup already running
        end

        @testset "All assets warmup skip conditions" begin
            s = create_mock_strategy()
            st.call!(s, stt.InitSimWarmup())

            # Test skip if warmup already running
            s.attrs[:warmup_running] = true
            callback_called = false
            test_callback = (args...) -> callback_called = true
            st.call!(test_callback, s, warmup_action)
            @test !callback_called

            # Test skip if all assets already warmed
            s.attrs[:warmup_running] = false
            for ai in s.universe
                s.attrs[:warmup][ai] = true
            end
            st.call!(test_callback, s, warmup_action)
            @test !callback_called
        end
    end
end

function test_warmup_edge_cases()
    @eval begin
        using PlanarDev.Planar.Engine: Engine as egn
        using .egn.Strategies: Strategies as st
        using .egn.TimeTicks: Minute, Day, Hour
        PlanarDev.@environment!
        PlanarDev.tools!()  # Load StrategyTools
    end

    @testset "Warmup Edge Cases" begin
        @testset "Thread safety with warmup_lock" begin
            s = create_mock_strategy()
            st.call!(s, stt.InitSimWarmup())

            # Test that warmup_lock exists and is properly typed
            @test haskey(s.attrs, :warmup_lock)
            @test s.attrs[:warmup_lock] isa ReentrantLock

            # Test basic lock functionality
            lock_acquired = false
            lock(s.attrs[:warmup_lock]) do
                lock_acquired = true
            end
            @test lock_acquired
        end

        @testset "Warmup period calculation" begin
            s = create_mock_strategy()

            # Test different warmup periods
            periods = [Day(1), Hour(12), Minute(30)]
            for period in periods
                st.call!(s, stt.InitSimWarmup(); warmup_period=period)
                # Should always be at least 100 candles
                @test s.attrs[:warmup_candles] >= 100
            end
        end

        @testset "Custom n_candles parameter behavior" begin
            s = create_mock_strategy()
            st.call!(s, stt.InitSimWarmup())

            # Test that custom n_candles can be passed
            custom_candles = 200
            callback_called = false

            # Test with single asset
            ai = first(s.universe)
            test_callback = (args...) -> begin
                callback_called = true
                # Just verify callback receives expected number of arguments
                @test length(args) >= 2
            end

            # This should not crash even if underlying data is insufficient
            st.call!(test_callback, s, ai, DateTime(2024, 1, 15),
                    stt.SimWarmup(); n_candles=custom_candles)
        end
    end
end

function test_warmup_attributes()
    @eval begin
        using PlanarDev.Planar.Engine: Engine as egn
        using .egn.Strategies: Strategies as st
        using .egn.TimeTicks: Minute, Day, Hour
        PlanarDev.@environment!
        PlanarDev.tools!()  # Load StrategyTools
    end

    @testset "Warmup Attributes Tests" begin
        @testset "Attribute initialization and types" begin
            s = create_mock_strategy()
            init_action = stt.InitSimWarmup()

            st.call!(s, init_action)

            # Verify all expected attributes are created with correct types
            @test haskey(s.attrs, :warmup_lock)
            @test s.attrs[:warmup_lock] isa ReentrantLock

            @test haskey(s.attrs, :warmup_timeout)
            @test s.attrs[:warmup_timeout] isa Dates.Period

            @test haskey(s.attrs, :warmup_running)
            @test s.attrs[:warmup_running] isa Bool
            @test s.attrs[:warmup_running] == false

            @test haskey(s.attrs, :warmup)
            @test s.attrs[:warmup] isa Dict

            @test haskey(s.attrs, :warmup_candles)
            @test s.attrs[:warmup_candles] isa Integer
            @test s.attrs[:warmup_candles] > 0
        end

        @testset "Universe asset warmup tracking" begin
            s = create_mock_strategy()
            st.call!(s, stt.InitSimWarmup())

            # All assets should initially be marked as not warmed
            @test length(s.attrs[:warmup]) == length(s.universe)
            for ai in s.universe
                @test haskey(s.attrs[:warmup], ai)
                @test s.attrs[:warmup][ai] == false
            end
        end
    end
end

function test_warmup()
    @eval begin
        using PlanarDev.Planar.Engine: Engine as egn
        using .egn.Strategies: Strategies as st
        PlanarDev.@environment!
        PlanarDev.tools!()  # Load StrategyTools
    end

    @testset failfast=FAILFAST "warmup" begin
        @testset "InitSimWarmup" begin
            test_init_sim_warmup()
        end

        @testset "SimWarmup Basic" begin
            test_sim_warmup_basic()
        end

        @testset "Warmup Attributes" begin
            test_warmup_attributes()
        end

        @testset "Edge Cases" begin
            test_warmup_edge_cases()
        end
    end
end
