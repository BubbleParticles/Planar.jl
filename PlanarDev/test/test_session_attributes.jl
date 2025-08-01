using PlanarDev.Stubs
import PlanarDev.Stubs.StubStrategy
using Test
using .Planar.Engine.Simulations: Simulations as sml
using .Planar.Engine.Data: Data as da
using .Planar.Engine.Strategies: Strategies as st
using .Planar.Engine.Executors: Executors as ex
using .Planar.Engine.Misc: Misc as ms
using .Planar.Engine.Lang: Lang as lg
using Optim: Optim as opt

function test_session_attributes()
    @eval begin
        using PlanarDev.Planar.Engine: Engine as egn
        using .egn.Strategies: Strategies as st
        using .egn.Executors: Executors as ex
        using .egn.Data: Data as da
        using .egn.Misc: Misc as ms
        using .egn.Simulations: Simulations as sml
        PlanarDev.@environment!
        
        # Add optimization methods to StubStrategy
        function st.call!(s::StubStrategy.SC{E,M,R}, ::ex.OptSetup) where {E,M,R}
            (;
                ctx=ex.Context(sml.Sim(), ms.DateRange(DateTime(2024, 1, 1), DateTime(2024, 1, 2), Minute(1))),
                params=(param1=1:2, param2=10:10:20),
                space=(kind=:MixedPrecisionRectSearchSpace, precision=Int[0, 0]),
            )
        end
        
        function st.call!(s::StubStrategy.SC{E,M,R}, params, ::ex.OptRun) where {E,M,R}
            s.attrs[:param1] = params[1]
            s.attrs[:param2] = params[2]
        end
        
        function st.call!(s::StubStrategy.SC{E,M,R}, ::ex.OptScore) where {E,M,R}
            [1.0]  # Return a simple score
        end
    end

    @testset "Session Attributes" begin
        # Test that attributes are saved and loaded correctly
        @testset "Progressive Save Attributes" begin
            # Create a temporary directory for testing
            test_dir = mktempdir()
            zi = da.zinstance(test_dir)

            # Create a test strategy using StubStrategy
            s = Stubs.stub_strategy()

            # Clean up any existing sessions to ensure reproducible results
            try
                opt.delete_sessions!(string(nameof(s)); zi=zi)
            catch
                # Ignore errors if no sessions exist
            end

            # Create an optimization session
            sess = opt.optsession(s; seed=42, splits=1, offset=0)

            # Add some test results
            push!(
                sess.results,
                (repeat=1, obj=1.0, cash=1000.0, pnl=0.0, trades=0, param1=1, param2=10),
            )
            push!(
                sess.results,
                (repeat=1, obj=2.0, cash=1100.0, pnl=0.1, trades=1, param1=2, param2=20),
            )

            # Save session initially
            opt.save_session(sess; from=0, zi=zi)

            # Print session key after saving
            k, _ = opt.session_key(sess)
            @info "Session key for save" k
            z = da.load_data(zi, k; serialized=true, as_z=true)[1]
            @test !isempty(z.attrs)
            @test haskey(z.attrs, "name")
            @test haskey(z.attrs, "ctx")
            @test haskey(z.attrs, "params")
            @test haskey(z.attrs, "attrs")

            # Add more results and save progressively
            push!(
                sess.results,
                (repeat=2, obj=3.0, cash=1200.0, pnl=0.2, trades=2, param1=1, param2=10),
            )
            push!(
                sess.results,
                (repeat=2, obj=4.0, cash=1300.0, pnl=0.3, trades=3, param1=2, param2=20),
            )

            # Progressive save
            opt.save_session(sess; from=2, zi=zi)

            # Load session and verify attributes
            k, _ = opt.session_key(sess)
            @info "Session key for load" k
            z = da.load_data(zi, k; serialized=true, as_z=true)[1]
            @test !isempty(z.attrs)
            @test haskey(z.attrs, "name")
            @test haskey(z.attrs, "ctx")
            @test haskey(z.attrs, "params")
            @test haskey(z.attrs, "attrs")

            # Test loading the session
            loaded_sess = opt.load_session(sess; zi=zi)
            @test loaded_sess isa opt.OptSession
            @test size(loaded_sess.results, 1) == 5
            @test loaded_sess.attrs[:seed] == 42
            @test loaded_sess.attrs[:splits] == 1
            @test loaded_sess.attrs[:offset] == 0

            # Clean up
            rm(test_dir; recursive=true)
        end

        @testset "Missing Attributes Recovery" begin
            # Create a temporary directory for testing
            test_dir = mktempdir()
            zi = da.zinstance(test_dir)

            # Create a test strategy using StubStrategy
            s = Stubs.stub_strategy()

            # Clean up any existing sessions to ensure reproducible results
            try
                opt.delete_sessions!(string(nameof(s)); zi=zi)
            catch
                # Ignore errors if no sessions exist
            end

            # Create an optimization session
            sess = opt.optsession(s; seed=42, splits=1, offset=0)

            # Add some test results
            push!(
                sess.results,
                (repeat=1, obj=1.0, cash=1000.0, pnl=0.0, trades=0, param1=1, param2=10),
            )

            # Save session initially
            opt.save_session(sess; from=0, zi=zi)

            # Manually delete attributes to simulate corruption
            k, _ = opt.session_key(sess)
            z = da.load_data(zi, k; serialized=true, as_z=true)[1]
            delete!(z.storage, z.path, ".zattrs")

            # Try to save progressively - should recover attributes
            push!(
                sess.results,
                (repeat=2, obj=2.0, cash=1100.0, pnl=0.1, trades=1, param1=2, param2=20),
            )
            opt.save_session(sess; from=1, zi=zi)

            # Verify attributes are recovered
            z = da.load_data(zi, k; serialized=true, as_z=true)[1]
            @test !isempty(z.attrs)
            @test haskey(z.attrs, "name")
            @test haskey(z.attrs, "ctx")
            @test haskey(z.attrs, "params")
            @test haskey(z.attrs, "attrs")

            # Clean up
            rm(test_dir; recursive=true)
        end
    end
end