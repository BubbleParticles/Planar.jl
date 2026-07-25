using Test
using Planar: Planar

# ──────────────────────────────────────────────
# Module loading
# ──────────────────────────────────────────────
@testset "Planar module" begin
    @test Planar isa Module
end

# ──────────────────────────────────────────────
# Exports
# ──────────────────────────────────────────────
@testset "Exports" begin
    exported = names(Planar; all=false)
    @test :ExchangeID ∈ exported
    @test Symbol("@strategyenv!") ∈ exported
    @test Symbol("@contractsenv!") ∈ exported
    @test Symbol("@optenv!") ∈ exported
    @test Symbol("@environment!") ∈ exported
    @test Symbol("@ldebug") ∈ exported
    @test Symbol("@linfo") ∈ exported
    @test Symbol("@lwarn") ∈ exported
    @test Symbol("@lerror") ∈ exported
    @test :Isolated ∈ exported
    @test :NoMargin ∈ exported
end

# ──────────────────────────────────────────────
# isvalidname (strat.jl)
# ──────────────────────────────────────────────
@testset "isvalidname" begin
    @test Planar.isvalidname("MyStrategy")
    @test Planar.isvalidname("My_Strategy")
    @test Planar.isvalidname("Test123")
    @test Planar.isvalidname("A")
    @test Planar.isvalidname("ABC")
    @test Planar.isvalidname("a.b.c")
    @test Planar.isvalidname("AlphaBeta.Gamma")

    @test !Planar.isvalidname("")
    @test !Planar.isvalidname("123strategy")
    @test !Planar.isvalidname("has space")
    @test !Planar.isvalidname("special!chars")
    @test !Planar.isvalidname(".leading.dot")
end

# ──────────────────────────────────────────────
# relative_path (strat.jl)
# ──────────────────────────────────────────────
@testset "relative_path" begin
    r = Planar.relative_path("/project/Planar/src/strat.jl", "/project/Planar/src/file.jl", 2)
    @test r == "src/file.jl"

    r = Planar.relative_path("/project/Planar/src/sub/dir/file.jl", "/project/Planar/src/other.jl", 3)
    @test r == "src/other.jl"

    r = Planar.relative_path("/nonexistent/file.jl", "/project/Planar/src/orig.jl", 2)
    @test r == "/project/Planar/src/orig.jl"
end

# ──────────────────────────────────────────────
# rmlinums! (strat.jl)
# ──────────────────────────────────────────────
@testset "rmlinums!" begin
    @test Planar.rmlinums!(:(x + y)) == :(x + y)

    ex2 = quote
        x = 1
        y = 2
    end
    @test Planar.rmlinums!(deepcopy(ex2)) isa Expr
end

# ──────────────────────────────────────────────
# _logmsg (logmacros.jl)
# ──────────────────────────────────────────────
@testset "_logmsg SimStrategy" begin
    s = Planar.Engine.Strategies.SimStrategy("test", Planar.NoMargin())
    @test Planar._logmsg(s, Val(:debug), "msg") === nothing
    @test Planar._logmsg(s, Val(:info), "msg") === nothing
    @test Planar._logmsg(s, Val(:warn), "msg") === nothing
    @test Planar._logmsg(s, Val(:error), "msg") === nothing
end

@testset "_logmsg RTStrategy" begin
    s = Planar.Engine.Strategies.RTStrategy("testrt", Planar.NoMargin())
    @test_logs (:info,)  Planar._logmsg(s, Val(:info), "test info")
    @test_logs (:warn,)  Planar._logmsg(s, Val(:warn), "test warn")
    @test_logs (:error,) Planar._logmsg(s, Val(:error), "test error")
end

# ──────────────────────────────────────────────
# isliveorpaper (logmacros.jl)
# ──────────────────────────────────────────────
@testset "isliveorpaper" begin
    sim = Planar.Engine.Strategies.SimStrategy("sim", Planar.NoMargin())
    rt = Planar.Engine.Strategies.RTStrategy("rt", Planar.NoMargin())

    @test !Planar.isliveorpaper(sim)
    @test Planar.isliveorpaper(rt)
end

# ──────────────────────────────────────────────
# Log macros (logmacros.jl)
# ──────────────────────────────────────────────
@testset "Log macros (SimStrategy)" begin
    sim = Planar.Engine.Strategies.SimStrategy("sim", Planar.NoMargin())
    msg = "test log message"

    @test Planar.@ldebug(sim, msg) === nothing
    @test Planar.@linfo(sim, msg) === nothing
    @test Planar.@lwarn(sim, msg) === nothing
    @test Planar.@lerror(sim, msg) === nothing
end

# ──────────────────────────────────────────────
# ask_name (strat.jl)
# ──────────────────────────────────────────────
@testset "ask_name" begin
    @test Planar.ask_name("mystrategy") == "Mystrategy"
    @test Planar.ask_name("hello_world") == "Hello_world"
    @test Planar.ask_name("TEST") == "TEST"
end

# ──────────────────────────────────────────────
# ExchangeID type
# ──────────────────────────────────────────────
@testset "ExchangeID" begin
    @test Planar.ExchangeID(:binance) isa Planar.ExchangeID
    @test Planar.ExchangeID(:kucoin) isa Planar.ExchangeID
    @test Planar.ExchangeID(:okx) isa Planar.ExchangeID
end

# ──────────────────────────────────────────────
# NoMargin / Isolated types
# ──────────────────────────────────────────────
@testset "NoMargin / Isolated" begin
    @test Planar.NoMargin() isa Planar.NoMargin
    @test Planar.Isolated() isa Planar.Isolated
    @test Planar.NoMargin() isa Planar.MarginMode
    @test Planar.Isolated() isa Planar.MarginMode
end

# ──────────────────────────────────────────────
# Planar submodule tests (Engine, LiveMode, PaperMode, Remote)
# ──────────────────────────────────────────────
@testset "Planar Submodules" begin
    include("Engine/runtests.jl")
    include("LiveMode/runtests.jl")
    include("PaperMode/runtests.jl")
    include("Remote/runtests.jl")
end
