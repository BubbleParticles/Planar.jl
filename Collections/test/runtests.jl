using Test
using Collections
using Instances.Exchanges.ExchangeTypes
using Instances.Exchanges.ExchangeTypes: CcxtExchange, ExchangeID, ExcPrecisionMode
using Instances.Exchanges.ExchangeTypes.OrderedCollections: OrderedSet
using Instances.Data.TimeTicks: TimeFrame, DateTime, now, Dates
using Instances.Data.DataFrames: DataFrame
using Instances.Data.TimeTicks.Lang: Option
using Instances
using Instances: NoMarginInstance
using Instances.Instruments: AbstractAsset, parse
using Instances.Misc: NoMargin, TimeTicks, Lang
using Instances.DataStructures: SortedDict

# Create a minimal mock exchange object
function _make_exchange(name::Symbol)
    id = ExchangeID{name}()
    CcxtExchange{typeof(id)}(
        id,                          # id
        string(name),                # name
        "",                          # account
        OrderedSet{String}(["1m"]),  # timeframes
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
            "ETH/USDT" => Dict{String,Any}(
                "id" => "ETH/USDT", "base" => "ETH", "quote" => "USDT",
                "type" => "spot", "active" => true, "spot" => true,
                "precision" => Dict{String,Any}("amount" => 8, "price" => 2),
                "limits" => Dict{String,Any}(
                    "amount" => Dict{String,Any}("min" => 1e-6, "max" => 1e8),
                    "price" => Dict{String,Any}("min" => 0.01, "max" => 1e6),
                    "cost" => Dict{String,Any}("min" => 1.0, "max" => 1e8),
                ),
                "taker" => 0.001, "maker" => 0.001,
            ),
        ),                       # markets
        Set{Symbol}([:spot]),    # types
        Dict{Symbol,Any}(:taker => 0.001, :maker => 0.001), # fees
        Dict{Symbol,Any}(:fetchTicker => true, :fetchOHLCV => true), # has
        ExcPrecisionMode(2),     # precision
        nothing,                 # _trace
        [:fetchTicker, :fetchOHLCV], # _propnames
        Dict{String,Any}(),      # options
    )
end

function _make_ohlcv(price, n=100)
    start_dt = DateTime(2024, 1, 1, 0, 0, 0)
    rows = [(Dates.value(DateTime(2024, 1, 1)) + i*60, price + randn()*0.1, price + randn()*0.1, price - 0.1, price + 0.1, 1000.0) for i in 0:n-1]
    df = DataFrame(
        timestamp = [r[1] for r in rows],
        open = [r[2] for r in rows],
        high = [r[3] for r in rows],
        low = [r[4] for r in rows],
        close = [r[5] for r in rows],
        volume = [r[6] for r in rows],
    )
    df
end

const mock_exc = _make_exchange(:test)

@testset "Collections" begin
    @testset "empty constructor" begin
        coll = Collections.AssetCollection()
        @test isempty(coll)
        @test length(coll) == 0
        @test size(coll) == (0, 3)
        @test names(coll.data) == ["exchange", "asset", "instance"]
    end

    @testset "from instances" begin
        a_btc = parse(AbstractAsset, "BTC/USDT")
        a_eth = parse(AbstractAsset, "ETH/USDT")
        tf = TimeFrame("1m")
        data_btc = SortedDict(tf => _make_ohlcv(50000.0, 10))
        data_eth = SortedDict(tf => _make_ohlcv(3000.0, 10))

        ai_btc = Instances.AssetInstance(
            a_btc, data_btc, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )
        ai_eth = Instances.AssetInstance(
            a_eth, data_eth, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )

        coll = Collections.AssetCollection([ai_btc, ai_eth])
        @test length(coll) == 2
        @test coll.data.exchange[1] == ExchangeID(:test)
        @test coll.data.asset[1] == a_btc
        @test coll.data.asset[2] == a_eth
        @test coll.data.instance[1] === ai_btc
        @test coll.data.instance[2] === ai_eth
    end

    @testset "getindex by exchange" begin
        a_btc = parse(AbstractAsset, "BTC/USDT")
        a_eth = parse(AbstractAsset, "ETH/USDT")
        tf = TimeFrame("1m")
        data_btc = SortedDict(tf => _make_ohlcv(50000.0, 10))
        data_eth = SortedDict(tf => _make_ohlcv(3000.0, 10))

        ai_btc = Instances.AssetInstance(
            a_btc, data_btc, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )
        ai_eth = Instances.AssetInstance(
            a_eth, data_eth, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )

        coll = Collections.AssetCollection([ai_btc, ai_eth])
        # By exchange ID
        sub = coll[ExchangeID(:test)]
        @test size(sub, 1) == 2
        # Non-existent exchange
        sub2 = coll[ExchangeID(:nonexistent)]
        @test size(sub2, 1) == 0
    end

    @testset "getindex by asset" begin
        a_btc = parse(AbstractAsset, "BTC/USDT")
        a_eth = parse(AbstractAsset, "ETH/USDT")
        tf = TimeFrame("1m")
        data_btc = SortedDict(tf => _make_ohlcv(50000.0, 10))
        data_eth = SortedDict(tf => _make_ohlcv(3000.0, 10))

        ai_btc = Instances.AssetInstance(
            a_btc, data_btc, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )
        ai_eth = Instances.AssetInstance(
            a_eth, data_eth, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )

        coll = Collections.AssetCollection([ai_btc, ai_eth])
        # By asset
        sub = coll[a_btc]
        @test size(sub, 1) == 1
        @test sub.asset[1] == a_btc

        # By string
        sub2 = coll["ETH/USDT"]
        @test size(sub2, 1) == 1
        @test sub2.asset[1] == a_eth
    end

    @testset "getindex with bqe keywords" begin
        a_btc = parse(AbstractAsset, "BTC/USDT")
        a_eth = parse(AbstractAsset, "ETH/USDT")
        tf = TimeFrame("1m")
        data_btc = SortedDict(tf => _make_ohlcv(50000.0, 10))
        data_eth = SortedDict(tf => _make_ohlcv(3000.0, 10))

        ai_btc = Instances.AssetInstance(
            a_btc, data_btc, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )
        ai_eth = Instances.AssetInstance(
            a_eth, data_eth, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )

        coll = Collections.AssetCollection([ai_btc, ai_eth])
        # b=base, q=quote, e=exchange
        sub = getindex(coll; b=:BTC, q=:USDT, e=:test)
        @test size(sub, 1) == 1
        @test sub.asset[1] == a_btc

        # Only quote
        sub2 = getindex(coll; q=:USDT)
        @test size(sub2, 1) == 2

        # Only base
        sub3 = getindex(coll; b=:ETH)
        @test size(sub3, 1) == 1
        @test sub3.asset[1] == a_eth

        # Non-existent base
        sub4 = getindex(coll; b=:XRP)
        @test size(sub4, 1) == 0
    end

    @testset "getindex chained" begin
        a_btc = parse(AbstractAsset, "BTC/USDT")
        a_eth = parse(AbstractAsset, "ETH/USDT")
        tf = TimeFrame("1m")
        data_btc = SortedDict(tf => _make_ohlcv(50000.0, 10))
        data_eth = SortedDict(tf => _make_ohlcv(3000.0, 10))

        ai_btc = Instances.AssetInstance(
            a_btc, data_btc, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )
        ai_eth = Instances.AssetInstance(
            a_eth, data_eth, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )

        coll = Collections.AssetCollection([ai_btc, ai_eth])
        sub = coll[ExchangeID(:test), :instance]
        @test length(sub) == 2
    end

    @testset "get with default" begin
        a_btc = parse(AbstractAsset, "BTC/USDT")
        a_eth = parse(AbstractAsset, "ETH/USDT")
        tf = TimeFrame("1m")
        data_btc = SortedDict(tf => _make_ohlcv(50000.0, 10))
        data_eth = SortedDict(tf => _make_ohlcv(3000.0, 10))

        ai_btc = Instances.AssetInstance(
            a_btc, data_btc, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )
        ai_eth = Instances.AssetInstance(
            a_eth, data_eth, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )

        coll = Collections.AssetCollection([ai_btc, ai_eth])
        @test get(coll, 1, nothing) == ai_btc
        @test get(coll, 99, nothing) === nothing
    end

    @testset "flatten" begin
        a_btc = parse(AbstractAsset, "BTC/USDT")
        tf = TimeFrame("1m")
        df1 = _make_ohlcv(50000.0, 10)
        df2 = _make_ohlcv(3000.0, 5)
        data_btc = SortedDict(tf => df1)
        data_eth = SortedDict(tf => df2)

        ai_btc = Instances.AssetInstance(
            a_btc, data_btc, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )
        ai_eth = Instances.AssetInstance(
            parse(AbstractAsset, "ETH/USDT"), data_eth, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )

        coll = Collections.AssetCollection([ai_btc, ai_eth])
        flat = Collections.flatten(coll)
        @test flat isa SortedDict
        @test length(flat) == 1  # one timeframe "1m"
        @test length(first(values(flat))) == 2  # two dataframes
    end

    @testset "flatten noempty" begin
        a_btc = parse(AbstractAsset, "BTC/USDT")
        tf = TimeFrame("1m")
        df1 = _make_ohlcv(50000.0, 10)
        data_btc = SortedDict(tf => df1)
        data_eth = SortedDict(tf => DataFrame())  # empty

        ai_btc = Instances.AssetInstance(
            a_btc, data_btc, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )
        ai_eth = Instances.AssetInstance(
            parse(AbstractAsset, "ETH/USDT"), data_eth, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )

        coll = Collections.AssetCollection([ai_btc, ai_eth])
        flat = Collections.flatten(coll; noempty=true)
        @test length(first(values(flat))) == 1  # only BTC's non-empty df
    end

    @testset "similar" begin
        a_btc = parse(AbstractAsset, "BTC/USDT")
        tf = TimeFrame("1m")
        data_btc = SortedDict(tf => _make_ohlcv(50000.0, 10))
        ai_btc = Instances.AssetInstance(
            a_btc, data_btc, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )
        coll = Collections.AssetCollection([ai_btc])
        similar = Base.similar(coll)
        @test similar isa Collections.AssetCollection
        @test length(similar) == length(coll)
    end

    @testset "iterate" begin
        a_btc = parse(AbstractAsset, "BTC/USDT")
        a_eth = parse(AbstractAsset, "ETH/USDT")
        tf = TimeFrame("1m")
        data_btc = SortedDict(tf => _make_ohlcv(50000.0, 10))
        data_eth = SortedDict(tf => _make_ohlcv(3000.0, 10))

        ai_btc = Instances.AssetInstance(
            a_btc, data_btc, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )
        ai_eth = Instances.AssetInstance(
            a_eth, data_eth, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )

        coll = Collections.AssetCollection([ai_btc, ai_eth])
        instances = collect(coll)
        @test length(instances) == 2
        @test instances[1] === ai_btc
        @test instances[2] === ai_eth
    end

    @testset "first/last" begin
        a_btc = parse(AbstractAsset, "BTC/USDT")
        a_eth = parse(AbstractAsset, "ETH/USDT")
        tf = TimeFrame("1m")
        data_btc = SortedDict(tf => _make_ohlcv(50000.0, 10))
        data_eth = SortedDict(tf => _make_ohlcv(3000.0, 10))

        ai_btc = Instances.AssetInstance(
            a_btc, data_btc, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )
        ai_eth = Instances.AssetInstance(
            a_eth, data_eth, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )

        coll = Collections.AssetCollection([ai_btc, ai_eth])
        @test first(coll) === ai_btc
        @test last(coll) === ai_eth
    end

    @testset "iscashable" begin
        a_btc = parse(AbstractAsset, "BTC/USDT")
        a_eth = parse(AbstractAsset, "ETH/USDT")
        tf = TimeFrame("1m")
        data_btc = SortedDict(tf => _make_ohlcv(50000.0, 10))
        data_eth = SortedDict(tf => _make_ohlcv(3000.0, 10))

        ai_btc = Instances.AssetInstance(
            a_btc, data_btc, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )
        ai_eth = Instances.AssetInstance(
            a_eth, data_eth, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )

        coll = Collections.AssetCollection([ai_btc, ai_eth])
        @test Collections.iscashable(Instances.Instruments.Cash("USDT", 1000.0), coll)
    end

    @testset "_daterange" begin
        a_btc = parse(AbstractAsset, "BTC/USDT")
        a_eth = parse(AbstractAsset, "ETH/USDT")
        tf = TimeFrame("1min")
        # Unix ms timestamp for 2024-01-01T00:00:00Z
        base_ts = 1704067200000

        # BTC: 100 rows starting at 2024-01-01 (1-minute candles = 60000 ms apart)
        df1 = DataFrame(
            timestamp = [Int64(base_ts + i*60000) for i in 0:99],
            open = 50000.0, high = 50100.0, low = 49900.0, close = 50050.0, volume = 1000.0,
        )
        # ETH: 50 rows starting at 2024-01-01 00:30 (30 min later), so intersection starts later
        df2 = DataFrame(
            timestamp = [Int64(base_ts + (30+i)*60000) for i in 0:49],
            open = 3000.0, high = 3020.0, low = 2980.0, close = 3010.0, volume = 500.0,
        )

        data_btc = SortedDict(tf => df1)
        data_eth = SortedDict(tf => df2)

        ai_btc = Instances.AssetInstance(
            a_btc, data_btc, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )
        ai_eth = Instances.AssetInstance(
            a_eth, data_eth, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )

        coll = Collections.AssetCollection([ai_btc, ai_eth])

        # _daterange (intersection): latest start = 2024-01-01 00:30, earliest end = 2024-01-01 01:19
        dr = Collections._daterange(coll)
        @test dr.start == DateTime(2024, 1, 1, 0, 30, 0)
        @test dr.stop == DateTime(2024, 1, 1, 1, 19, 0)

        # _daterange_full (union): earliest start = 2024-01-01 00:00, latest end = 2024-01-01 01:39 + 1min
        dr2 = Collections._daterange_full(coll)
        @test dr2.start == DateTime(2024, 1, 1, 0, 0, 0)
        @test dr2.stop == DateTime(2024, 1, 1, 1, 40, 0)  # M + tf
    end

    @testset "getindex chained triple" begin
        a_btc = parse(AbstractAsset, "BTC/USDT")
        a_eth = parse(AbstractAsset, "ETH/USDT")
        tf = TimeFrame("1min")
        data_btc = SortedDict(tf => _make_ohlcv(50000.0, 10))
        data_eth = SortedDict(tf => _make_ohlcv(300.0, 10))

        ai_btc = Instances.AssetInstance(
            a_btc, data_btc, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )
        ai_eth = Instances.AssetInstance(
            a_eth, data_eth, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )

        coll = Collections.AssetCollection([ai_btc, ai_eth])
        # Triple-arg getindex: (exc, :col, idx)
        result = coll[ExchangeID(:test), :instance, 1]
        @test result === ai_btc
    end

    @testset "first with asset" begin
        a_btc = parse(AbstractAsset, "BTC/USDT")
        tf = TimeFrame("1m")
        data_btc = SortedDict(tf => _make_ohlcv(50000.0, 10))

        ai_btc = Instances.AssetInstance(
            a_btc, data_btc, mock_exc, NoMargin();
            limits=(; leverage=(; min=1.0, max=1.0), amount=(; min=1e-6, max=1e8), price=(; min=0.01, max=1e6), cost=(; min=1.0, max=1e8)),
            precision=(; amount=8, price=2),
            fees=(; taker=0.001, maker=0.001, min=0.0, max=0.002),
        )

        coll = Collections.AssetCollection([ai_btc])
        df = first(coll, a_btc)
        @test df isa DataFrame
        @test first(df.timestamp) == Dates.value(DateTime(2024, 1, 1))
    end
end
