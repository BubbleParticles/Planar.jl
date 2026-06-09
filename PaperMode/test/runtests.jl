module Runtests

using Test
using PaperMode
using HTTP, JSON3

const DateTime = PaperMode.DateTime
const DFT = PaperMode.DFT
const Buy = PaperMode.SimMode.Buy
const Sell = PaperMode.SimMode.Sell
const Order = PaperMode.OrderTypes.Order
const EID = PaperMode.OrderTypes.ExchangeTypes.ExchangeID

using Logging: SimpleLogger, with_logger

# ── Test fixtures ──────────────────────────────────────────
_asset = PaperMode.SimMode.Asset("BTC/USDT")
_eid = EID(:test)
_dt = DateTime(2024, 1, 1)

_limit_buy(; p=100.0, a=1.0) = Order(_asset, _eid, Order{PaperMode.OrderTypes.LimitOrderType{Buy}}; price=p, amount=a, date=_dt)
_limit_sell(; p=100.0, a=1.0) = Order(_asset, _eid, Order{PaperMode.OrderTypes.LimitOrderType{Sell}}; price=p, amount=a, date=_dt)
_market_buy(; p=100.0, a=1.0) = Order(_asset, _eid, Order{PaperMode.OrderTypes.MarketOrderType{Buy}}; price=p, amount=a, date=_dt)
_market_sell(; p=100.0, a=1.0) = Order(_asset, _eid, Order{PaperMode.OrderTypes.MarketOrderType{Sell}}; price=p, amount=a, date=_dt)

# ── Mock HTTP helpers ──────────────────────────────────────
const Rest = PaperMode.Instances.Exchanges.ExchangeTypes.CcxtGateway.Rest

function with_mock_http(f, ticker_volume=1000000.0)
    old_get = Rest._http_get[]
    old_post = Rest._http_post[]
    empty!(PaperMode.Instances.Exchanges.tickersCache10Sec)
    try
        mock_ticker = Dict{String,Any}(
            "symbol" => "BTC/USDT",
            "baseVolume" => Float64(ticker_volume),
            "quoteVolume" => 5e10,
            "last" => 50000.0,
        )
        Rest.set_http_get!(function(url; kwargs...)
            if occursin("fetchTicker", url)
                return HTTP.Response(200, JSON3.write(Dict("result" => mock_ticker)))
            elseif occursin("ping", url)
                return HTTP.Response(200, "pong")
            end
            return HTTP.Response(404, "Not Found")
        end)
        Rest.set_http_post!(function(url; kwargs...)
            return HTTP.Response(200, JSON3.write(Dict("result" => "ok")))
        end)
        f()
    finally
        Rest.set_http_get!(old_get)
        Rest.set_http_post!(old_post)
    end
end

function make_mock_exchange()
    ET = PaperMode.Instances.Exchanges.ExchangeTypes
    OrderedSet = ET.OrderedCollections.OrderedSet
    CcxtExchange = ET.CcxtExchange
    ExchangeID = ET.ExchangeID
    ExcPrecisionMode = ET.ExcPrecisionMode

    id = ExchangeID{:test}()
    CcxtExchange{typeof(id)}(
        id, "test", "", OrderedSet{String}(["1m"]),
        Dict{String,Dict{String,Any}}(
            "BTC/USDT" => Dict{String,Any}(
                "id" => "BTC/USDT", "base" => "BTC", "quote" => "USDT",
                "type" => "spot", "active" => true, "spot" => true, "linear" => true,
                "precision" => Dict{String,Any}("amount" => 8, "price" => 2),
                "limits" => Dict{String,Any}(
                    "amount" => Dict{String,Any}("min" => 1e-6, "max" => 1e8),
                    "price" => Dict{String,Any}("min" => 0.01, "max" => 1e6),
                    "cost" => Dict{String,Any}("min" => 1.0, "max" => 1e8),
                ),
                "taker" => 0.001, "maker" => 0.001, "percentage" => true,
            ),
        ),
        Set{Symbol}([:spot]),
        Dict{Symbol,Any}(:taker => 0.001, :maker => 0.001),
        Dict{Symbol,Any}(:fetchTicker => true, :fetchOHLCV => true),
        ExcPrecisionMode(2), nothing, Symbol[:fetchTicker, :fetchOHLCV], Dict{String,Any}(),
    )
end

function make_asset_instance(exc)
    ai = PaperMode.Instances.AssetInstance(
        _asset,
        PaperMode.Instances.DataStructures.SortedDict(),
        exc,
        PaperMode.Instances.Misc.NoMargin();
        limits=(; leverage=(; min=1.0, max=10.0), amount=(; min=1e-8, max=1e8), price=(; min=1e-8, max=1e8), cost=(; min=1e-8, max=1e8)),
        precision=(; amount=1e-8, price=1e-8),
        fees=(; taker=0.01, maker=0.01, min=0.01, max=0.01),
    )
end

@testset "PaperMode" begin

@testset "_asdate (orders/limit.jl)" begin
    @test PaperMode._asdate("2024-01-01T12:00:00Z") == DateTime(2024, 1, 1, 12, 0, 0)
    @test PaperMode._asdate("2024-01-01T00:00:00Z") == DateTime(2024, 1, 1)
    @test PaperMode._asdate("2024-01-01T12:00:00") == DateTime(2024, 1, 1, 12, 0, 0)
    @test PaperMode._asdate("2024-06-15T08:30:00.000Z") == DateTime(2024, 6, 15, 8, 30, 0)
    @test PaperMode._asdate("2024-12-31T23:59:59.999Z") == DateTime(2024, 12, 31, 23, 59, 59, 999)
end

@testset "_istriggered (orders/utils.jl)" begin
    ob = _limit_buy(p=100.0)
    @test PaperMode._istriggered(ob, 99.0)
    @test PaperMode._istriggered(ob, 100.0)
    @test !PaperMode._istriggered(ob, 101.0)

    os = _limit_sell(p=100.0)
    @test PaperMode._istriggered(os, 101.0)
    @test PaperMode._istriggered(os, 100.0)
    @test !PaperMode._istriggered(os, 99.0)

    omb = _market_buy()
    @test PaperMode._istriggered(omb, nothing)
    @test PaperMode._istriggered(omb, 0.0)
    @test PaperMode._istriggered(omb, -1.0)
    @test PaperMode._istriggered(omb, missing)

    oms = _market_sell()
    @test PaperMode._istriggered(oms, nothing)
    @test PaperMode._istriggered(oms, 0.0)
end

@testset "_compressor (module.jl)" begin
    if Sys.which("gzip") !== nothing
        mktemp() do path, io
            write(io, "test content for gzip compression")
            close(io)
            PaperMode._compressor(path)
            gz_path = path * ".gz"
            @test isfile(gz_path)
            rm(gz_path)
        end
    else
        @warn "gzip not available, skipping _compressor test"
    end
end

@testset "timestamp_logger (utils.jl)" begin
    buf = IOBuffer()
    inner = SimpleLogger(buf)
    ts_logger = PaperMode.timestamp_logger(inner)
    @test ts_logger isa PaperMode.LoggingExtras.TransformerLogger
    with_logger(ts_logger) do
        @info "hello papermode"
    end
    str = String(take!(buf))
    @test occursin("hello papermode", str)
    @test occursin("20", str)
end

@testset "_basevol with mock HTTP (orders/utils.jl)" begin
    exc = make_mock_exchange()
    ai = make_asset_instance(exc)

    with_mock_http(500000.0) do
        vol = PaperMode._basevol(ai)
        @test vol == 500000.0
        @test vol isa Float64
    end
end

@testset "_ticker_volume with mock HTTP (orders/utils.jl)" begin
    exc = make_mock_exchange()
    ai = make_asset_instance(exc)

    with_mock_http(2500000.0) do
        tv = PaperMode._ticker_volume(ai)
        @test tv isa Tuple{Base.RefValue{DateTime}, Base.RefValue{Float64}, Base.RefValue{Float64}}
        @test tv[3][] == 2500000.0
        @test tv[2][] == 0.0
    end
end

@testset "_basevol returns 1.0 for missing baseVolume" begin
    exc = make_mock_exchange()
    ai = make_asset_instance(exc)

    old_get = Rest._http_get[]
    old_post = Rest._http_post[]
    empty!(PaperMode.Instances.Exchanges.tickersCache10Sec)
    try
        mock_ticker = Dict{String,Any}("symbol" => "BTC/USDT", "last" => 50000.0)
        Rest.set_http_get!(function(url; kwargs...)
            if occursin("fetchTicker", url)
                return HTTP.Response(200, JSON3.write(Dict("result" => mock_ticker)))
            end
            return HTTP.Response(404, "Not Found")
        end)
        Rest.set_http_post!(function(url; kwargs...)
            return HTTP.Response(200, JSON3.write(Dict("result" => "ok")))
        end)
        vol = PaperMode._basevol(ai)
        @test vol == 1.0
    finally
        Rest.set_http_get!(old_get)
        Rest.set_http_post!(old_post)
    end
end

end  # @testset PaperMode
end  # module Runtests
