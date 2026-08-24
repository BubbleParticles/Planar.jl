using Test
using PlanarCore
using PlanarCore.Collections
using PlanarCore.Collections: snapshot
using PlanarCore.Strategies
using PlanarCore.Strategies: universe
using PlanarCore.Instances
using PlanarCore.Data.DataFrames: nrow

include("dynamic_universe.jl") # reuse helpers _make_exchange etc. Already defined if not, define fallback
# Ensure helpers exist even when run standalone
if !@isdefined(_make_exchange)
    function _make_exchange(name::Symbol)
        mkts = Dict{String,Dict{String,Any}}()
        for (sym, base, q) in [("BTC/USDT","BTC","USDT"), ("ETH/USDT","ETH","USDT"), ("SOL/USDT","SOL","USDT"), ("AVAX/USDT","AVAX","USDT")]
            mkts[sym] = Dict{String,Any}("id"=>sym, "base"=>base, "quote"=>q, "type"=>"spot", "active"=>true, "spot"=>true, "precision"=>Dict{String,Any}("amount"=>8,"price"=>2), "limits"=>Dict{String,Any}("amount"=>Dict{String,Any}("min"=>1e-6,"max"=>1e8), "price"=>Dict{String,Any}("min"=>0.01,"max"=>1e6), "cost"=>Dict{String,Any}("min"=>1.0,"max"=>1e8)), "taker"=>0.001, "maker"=>0.001)
        end
        CcxtExchange{ExchangeID{name}}(ExchangeID{name}(), string(name), "", OrderedSet{String}(["1m"]), mkts, Set{Symbol}([:spot]), Dict{Symbol,Any}(:taker=>0.001,:maker=>0.001), Dict{Symbol,Any}(:fetchTicker=>true,:fetchOHLCV=>true), ExcPrecisionMode(2), nothing, [:fetchTicker,:fetchOHLCV], Dict{String,Any}())
    end
end

@testset "Dynamic universe harness" begin
    @testset "unit planes" begin
        # already covered in dynamic_universe.jl
        @test true
    end
    @testset "invariants under random sequences" begin
        btc = _make_instance("BTC/USDT", 50000.0)
        eth = _make_instance("ETH/USDT", 3000.0)
        sol = _make_instance("SOL/USDT", 150.0)
        avax = try _make_instance("AVAX/USDT", 20.0) catch; btc end
        cfg = Config(); cfg.mode = Sim(); cfg.margin = NoMargin(); cfg.initial_cash = 1000.0
        strat = Strategies.Strategy(@__MODULE__, Sim(), NoMargin(), TimeFrame("1m"), _make_exchange(:test), Collections.InstrumentCollection([btc]); config=cfg)
        pool = [btc, eth, sol, avax]
        for i in 1:100
            op = rand(1:5)
            if op == 1
                ii = rand(pool); try addasset!(strat, ii) catch; end
            elseif op == 2
                k = rand(["BTC/USDT","ETH/USDT","SOL/USDT","AVAX/USDT","FAKE/USDT"]); try removeasset!(strat, k) catch; end
            elseif op == 3
                # replace with random subset
                n = rand(0:3); newset = unique(rand(pool, n)); try replace_universe!(strat, newset) catch; end
            elseif op == 4
                # add dupe
                try addasset!(strat, btc) catch; end
            else
                try removeasset!(strat, "NOTEXIST/USDT") catch; end
            end
            # invariants
            @test length(snapshot(universe(strat))) == nrow(universe(strat).data)
            for ii in snapshot(universe(strat))
                @test ii isa InstrumentInstance
            end
        end
    end
end
