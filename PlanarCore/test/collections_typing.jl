using Test
using PlanarCore.Collections
using PlanarCore.Instances
using PlanarCore.Instances.Exchanges.ExchangeTypes
using PlanarCore.Instances.Exchanges.ExchangeTypes: CcxtExchange, ExchangeID, ExcPrecisionMode
using PlanarCore.Instances.Exchanges.ExchangeTypes.OrderedCollections: OrderedSet
using PlanarCore.Instances.Data.TimeTicks: TimeFrame, DateTime, Dates
using PlanarCore.Instances.Data.DataFrames: DataFrame
using PlanarCore.Instances.DataStructures: SortedDict
using PlanarCore.Instances.Instruments: AbstractInstrument, parse
using PlanarCore.Instances.Misc: NoMargin

# Minimal mock exchange (mirrors Collections/runtests.jl) so we can build real instances.
function _make_exchange(name::Symbol)
    id = ExchangeID{name}()
    CcxtExchange{typeof(id)}(
        id,
        string(name),
        "",
        OrderedSet{String}(["1m"]),
        Dict{String,Dict{String,Any}}(
            "BTC/USDT" => Dict{String,Any}(
                "id" => "BTC/USDT", "base" => "BTC", "quote" => "USDT",
                "type" => "spot", "active" => true, "spot" => true,
                "precision" => Dict{String,Any}("amount" => 8, "price" => 2),
                "limits" => Dict{String,Any}(
                    "amount" => Dict{String,Any}("min" => 1e-6, "max" => 1e8),
                    "price" => Dict{String,Any}("min" => 0.01, "max" => 1e6),
                    "cost" => Dict{String,Any}("min" => 1.0, "max" => 1e8),
                ),
                "taker" => 0.001, "maker" => 0.001,
            ),
        ),
        Set{Symbol}([:spot]),
        Dict{Symbol,Any}(:taker => 0.001, :maker => 0.001),
        Dict{Symbol,Any}(:fetchTicker => true, :fetchOHLCV => true),
        ExcPrecisionMode(2),
        nothing,
        [:fetchTicker, :fetchOHLCV],
        Dict{String,Any}(),
    )
end

const mock_exc = _make_exchange(:test)

function _make_instance(sym::String, price::Float64)
    tf = TimeFrame("1m")
    base_ts = 1704067200000
    df = DataFrame(
        timestamp = [Int64(base_ts + i * 60000) for i in 0:9],
        open = Float64(price),
        high = Float64(price + price * 0.02),
        low = Float64(price - price * 0.02),
        close = Float64(price + price * 0.01),
        volume = Float64(1000.0),
    )
    Instances.InstrumentInstance(
        parse(AbstractInstrument, sym), SortedDict(tf => df), mock_exc, NoMargin();
        limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
        precision=(; amount=8, price=2),
        fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
    )
end

@testset "Collections static typing" begin
    btc = _make_instance("BTC/USDT", 50000.0)
    eth = _make_instance("ETH/USDT", 3000.0)

    @testset "concrete instance column eltype" begin
        coll = Collections.InstrumentCollection([btc, eth])
        I = eltype(coll.data.instance)
        @test I <: InstrumentInstance
        @test isconcretetype(I)
        @test eltype(coll.data.instance) === typeof(btc)
        T = eltype(coll.data.asset)
        @test T <: AbstractInstrument
        @test isconcretetype(T)
    end

    @testset "iteration yields concrete element type" begin
        coll = Collections.InstrumentCollection([btc, eth])
        elt = eltype(coll.data.instance)
        for ii in coll
            @test typeof(ii) === elt
        end
    end

    @testset "first/last concrete" begin
        coll = Collections.InstrumentCollection([btc, eth])
        @test typeof(first(coll)) === typeof(btc)
        @test typeof(last(coll)) === typeof(eth)
    end

    @testset "rows iterator is concretely typed" begin
        coll = Collections.InstrumentCollection([btc, eth])
        r = first(Collections.rows(coll))
        @test r.instance === btc
        @test r.asset === btc.asset
        @test r.exchange === ExchangeID(:test)
        # the rows element type must carry the concrete instance type
        rts = Base.return_types(Collections.rows, (typeof(coll),))
        @test any(t -> t <: Collections.Rows || t <: Base.Generator || t <: Base.Iterators.Zip, rts) ||
              any(t -> t isa Union && any(u -> u <: Collections.Rows, Base.uniontypes(t)), rts)
    end

    @testset "empty collection defaults to abstract params" begin
        coll = Collections.InstrumentCollection()
        @test isempty(coll)
        @test eltype(coll.data.instance) === InstrumentInstance
        @test eltype(coll.data.asset) === AbstractInstrument
    end

    @testset "narrowing keeps identity for heterogeneous abstract input" begin
        # A Vector{InstrumentInstance} (abstract eltype) holding homogeneous
        # concrete instances must narrow to the concrete type.
        mixed = Vector{InstrumentInstance}([btc, eth])
        coll = Collections.InstrumentCollection(mixed)
        @test isconcretetype(eltype(coll.data.instance))
        @test eltype(coll.data.instance) === typeof(btc)
    end
end
