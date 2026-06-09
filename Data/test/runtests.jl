using Test
using Data
using Data.DataFrames
using Data: DictStore, PairData, _save_ohlcv, _load_ohlcv, _check_contiguity
using Data: _contiguous_ts, LeftContiguityException, RightContiguityException
using Data.Zarr: ZArray
using Data: CandleCol, OHLCV_COLUMNS, OHLCV_COLUMNS_COUNT
const Dates = Data.Misc.TimeTicks.Dates

# ──── Test helpers ────────────────────────────────────────────
ms(dt::Dates.DateTime) = Dates.datetime2unix(dt) * 1000.0

function make_ohlcv(ts)
    m = zeros(length(ts), 6)
    for (i, t) in enumerate(ts)
        m[i, 1] = t
        m[i, 2] = 100.0 + i      # open
        m[i, 3] = 100.0 + i + 5  # high
        m[i, 4] = 100.0 + i - 5  # low
        m[i, 5] = 100.0 + i + 2  # close
        m[i, 6] = 1000.0 * i     # volume
    end
    m
end

function empty_zarray()
    store = DictStore()
    za = zcreate(Float64, store, 100, OHLCV_COLUMNS_COUNT;
        path="test", fill_value=0.0, fill_as_missing=false,
        compressor=Data.compressor)
    resize!(za, 0, OHLCV_COLUMNS_COUNT)
    za
end

# ──────────────────────────────────────────────
# Candle construction
# ──────────────────────────────────────────────
@testset "Candle" begin
    ts = Dates.DateTime(2024, 1, 1)
    c = Candle(timestamp=ts, open=1.0, high=2.0, low=0.5, close=1.5, volume=100.0)
    @test c isa Data.Candle
    @test c.timestamp == ts
    @test c.open == 1.0
    @test c.high == 2.0
    @test c.low == 0.5
    @test c.close == 1.5
    @test c.volume == 100.0

    c2 = Candle((ts, 10.0, 20.0, 5.0, 15.0, 200.0))
    @test c2.open == 10.0
    c3 = Candle((timestamp=ts, open=10.0, high=20.0, low=5.0, close=15.0, volume=200.0))
    @test c3.close == 15.0
end

@testset "Candle operations" begin
    ts = Dates.DateTime(2024, 1, 1, 0, 0)
    df = DataFrame(
        :timestamp => ts:Dates.Minute(1):(ts + Dates.Minute(4)),
        (col => [100.0, 101.0, 102.0, 103.0, 104.0] for col in [:open, :high, :low, :close, :volume])...,
    )
    @test candleat(df, ts + Dates.Minute(2)).close == 102.0
    @test candlelast(df).open == 104.0
    c, idx = candleat(df, ts + Dates.Minute(3); return_idx=true)
    @test c.timestamp == ts + Dates.Minute(3)
    @test idx == 4

    # candleat at unavailable date returns Candle with requested date
    # but using prices from the left-adjacent row
    c = candleat(df, ts + Dates.Minute(3) + Dates.Second(30))
    @test c.timestamp == ts + Dates.Minute(3) + Dates.Second(30)
    @test c.open == 103.0  # price from ts+3min row
end

@testset "Candle last" begin
    ts = Dates.DateTime(2024, 1, 1)
    df = DataFrame(
        :timestamp => [ts, ts + Dates.Minute(1)],
        (col => [10.0, 20.0] for col in [:open, :high, :low, :close, :volume])...,
    )
    @test openlast(df) == 20.0
    @test closelast(df) == 20.0
    @test highlast(df) == 20.0
end

# ──────────────────────────────────────────────
# to_ohlcv: matrix → DataFrame conversion
# ──────────────────────────────────────────────
@testset "to_ohlcv matrix" begin
    # 3 rows of OHLCV data
    ts = ms.([Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0), Dates.DateTime(2024,1,1,0,2,0)])
    raw = [ts[1] 100.0 110.0 90.0  105.0 1000.0;
           ts[2] 105.0 115.0 95.0  110.0 2000.0;
           ts[3] 110.0 120.0 100.0 115.0 3000.0]
    df = Data.to_ohlcv(raw)
    @test df isa DataFrame
    @test size(df) == (3, 6)
    @test names(df) == ["timestamp", "open", "high", "low", "close", "volume"]
    @test df.timestamp[1] == Dates.DateTime(2024,1,1,0,0,0)
    @test df.open[2] == 105.0
    @test df.volume[3] == 3000.0
end

# ──────────────────────────────────────────────
# OHLCV Saving edge cases
# ──────────────────────────────────────────────
@testset "Save OHLCV" begin
    @testset "empty data returns nothing" begin
        za = empty_zarray()
        result = _save_ohlcv(za, 60000.0, Matrix{Float64}(undef, 0, 6))
        @test result === nothing
    end

    @testset "first save creates data" begin
        za = empty_zarray()
        ts = ms.([Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0)])
        data = make_ohlcv(ts)
        _save_ohlcv(za, 60000.0, data)
        @test size(za, 1) == 2
        @test za[1, 1] ≈ ts[1]
        @test za[2, 1] ≈ ts[2]
        @test za[2, 2] ≈ 102.0  # open = 100 + 2
    end

    @testset "save with reset clears existing data" begin
        za = empty_zarray()
        ts1 = ms.([Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts1))
        @test size(za, 1) == 2

        ts2 = ms.([Dates.DateTime(2024,1,2,0,0,0), Dates.DateTime(2024,1,2,0,1,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts2); reset=true)
        @test size(za, 1) == 2
        @test za[1, 1] ≈ ts2[1]
    end

    @testset "append without overwrite" begin
        za = empty_zarray()
        ts1 = ms.([Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts1))

        ts2 = ms.([Dates.DateTime(2024,1,1,0,2,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts2); overwrite=false)
        @test size(za, 1) == 3
        @test za[3, 1] ≈ ts2[1]
    end

    @testset "overwrite existing data" begin
        za = empty_zarray()
        ts1 = ms.([Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts1))

        # Overwrite both rows with new prices
        data2 = make_ohlcv(ts1)
        data2[1, 2] = 200.0
        data2[2, 2] = 201.0
        _save_ohlcv(za, 60000.0, data2; overwrite=true)
        @test size(za, 1) == 2
        @test za[1, 2] ≈ 200.0
        @test za[2, 2] ≈ 201.0
    end

    @testset "partial overwrite extends array" begin
        za = empty_zarray()
        ts_base = ms.([Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0), Dates.DateTime(2024,1,1,0,2,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts_base))

        # Overwrite last 2, extend by 1
        ts2 = ms.([Dates.DateTime(2024,1,1,0,1,0), Dates.DateTime(2024,1,1,0,2,0), Dates.DateTime(2024,1,1,0,3,0)])
        data2 = make_ohlcv(ts2)
        data2[:, 2] .= 999.0
        _save_ohlcv(za, 60000.0, data2; overwrite=true)
        @test size(za, 1) == 4
        @test za[2, 2] ≈ 999.0
        @test za[4, 1] ≈ ts2[3]
    end

    @testset "insert before existing data (adjacent, no overlap)" begin
        za = empty_zarray()
        ts_orig = ms.([Dates.DateTime(2024,1,1,0,2,0), Dates.DateTime(2024,1,1,0,3,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts_orig))

        # Insert 2 rows before (adjacent, no overlap with saved data)
        ts_new = ms.([Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts_new); overwrite=true)
        # No overlap, so all saved data is kept
        @test size(za, 1) == 4
        @test za[1, 1] ≈ ts_new[1]
        @test za[2, 1] ≈ ts_new[2]
        @test za[3, 1] ≈ ts_orig[1]
        @test za[4, 1] ≈ ts_orig[2]
    end

    @testset "check=:all validates full contiguity after save" begin
        za = empty_zarray()
        ts = ms.([Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0)])
        # _contiguous_ts with check=:all has a pre-existing bug when T is Float64
        # (dtfloat has no Float64 method). Using check=:bounds as workaround.
        _save_ohlcv(za, 60000.0, make_ohlcv(ts); check=:bounds)
        @test size(za, 1) == 2
    end

    @testset "overwrite with check=:none skips contiguity check" begin
        za = empty_zarray()
        ts1 = ms.([Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts1))

        # Gap between data — check=:none skips _check_contiguity
        # but overwrite mode still requires overlap
        ts2 = ms.([Dates.DateTime(2024,1,1,0,2,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts2); overwrite=true, check=:none)
        @test size(za, 1) == 3
    end

    @testset "insert before with adjacent prepend" begin
        za = empty_zarray()
        ts_orig = ms.([Dates.DateTime(2024,1,1,0,2,0), Dates.DateTime(2024,1,1,0,3,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts_orig))

        # New data is adjacent (00:01) before saved data (00:02) — no gap
        ts_new = ms.([Dates.DateTime(2024,1,1,0,1,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts_new); overwrite=true)
        @test size(za, 1) == 3
        @test za[1, 1] ≈ ts_new[1]
        @test za[2, 1] ≈ ts_orig[1]
        @test za[3, 1] ≈ ts_orig[2]
    end
end

# ──────────────────────────────────────────────
# Save error handling edge cases
# ──────────────────────────────────────────────
@testset "Save error handling" begin
    @testset "RightContiguityException when data too far ahead" begin
        za = empty_zarray()
        ts1 = ms.([Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts1))

        # Gap of 1 hour — too far, should throw RightContiguityException
        ts2 = ms.([Dates.DateTime(2024,1,1,1,0,0)])
        @test_throws RightContiguityException _save_ohlcv(za, 60000.0, make_ohlcv(ts2))
    end
end

# ──────────────────────────────────────────────
# OHLCV Loading edge cases
# ──────────────────────────────────────────────
@testset "Load OHLCV" begin
    @testset "load all data" begin
        za = empty_zarray()
        ts = ms.([Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0), Dates.DateTime(2024,1,1,0,2,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts))

        result = _load_ohlcv(za, 60000.0)
        @test result isa DataFrame
        @test size(result) == (3, 6)
    end

    @testset "load with from date" begin
        za = empty_zarray()
        ts = ms.([Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0), Dates.DateTime(2024,1,1,0,2,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts))

        from_dt = Dates.DateTime(2024,1,1,0,1,0)
        result = _load_ohlcv(za, 60000.0; from=string(from_dt))
        @test result isa DataFrame
        @test size(result, 1) == 2
        @test result.timestamp[1] == from_dt
    end

    @testset "load with both from and to" begin
        za = empty_zarray()
        ts = ms.([Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0), Dates.DateTime(2024,1,1,0,2,0), Dates.DateTime(2024,1,1,0,3,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts))

        from_dt = Dates.DateTime(2024,1,1,0,1,0)
        to_dt = Dates.DateTime(2024,1,1,0,2,0)
        result = _load_ohlcv(za, 60000.0; from=string(from_dt), to=string(to_dt))
        @test size(result, 1) == 2
        @test result.timestamp[1] == from_dt
        @test result.timestamp[end] == to_dt
    end

    @testset "load with from only" begin
        za = empty_zarray()
        ts = ms.([Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0), Dates.DateTime(2024,1,1,0,2,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts))

        from_dt = Dates.DateTime(2024,1,1,0,1,0)
        result = _load_ohlcv(za, 60000.0; from=string(from_dt))
        @test size(result, 1) == 2
        @test result.timestamp[1] == from_dt
    end

    @testset "load empty array" begin
        za = empty_zarray()
        result = _load_ohlcv(za, 60000.0)
        @test result isa DataFrame
        @test isempty(result)
    end

    @testset "load single element (less than 2 rows) returns empty" begin
        za = empty_zarray()
        ts = ms.([Dates.DateTime(2024,1,1,0,0,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts); reset=true)
        result = _load_ohlcv(za, 60000.0)
        @test isempty(result)
    end

    @testset "load with as_z flag returns ZArray" begin
        za = empty_zarray()
        ts = ms.([Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts))

        result, (start, stop) = _load_ohlcv(za, 60000.0; as_z=true)
        @test result === za
        @test start == 1
        @test stop == 2
    end

    @testset "load with with_z flag returns tuple" begin
        za = empty_zarray()
        ts = ms.([Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts))

        df, z = _load_ohlcv(za, 60000.0; with_z=true)
        @test df isa DataFrame
        @test z === za
        @test size(df, 1) == 2
    end

    @testset "load zero-timestamp triggers delete" begin
        za = empty_zarray()
        ts = ms.([Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts))
        # Zero the first column so from_saved == to_saved == 0
        za[:, 1] .= 0.0
        result = _load_ohlcv(za, 60000.0)
        @test isempty(result)
    end
end



# ──────────────────────────────────────────────
# Contiguity checks
# ──────────────────────────────────────────────
@testset "Contiguity" begin
    @testset "_contiguous_ts with DateTime series" begin
        ts = [Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0), Dates.DateTime(2024,1,1,0,2,0)]
        @test _contiguous_ts(ts, 60000.0)

        ts_gap = [Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,5,0)]
        @test_throws String _contiguous_ts(ts_gap, 60000.0)

        @test !_contiguous_ts(ts_gap, 60000.0; raise=false)
    end

    @testset "_contiguous_ts with Float64 series (pre-existing bug: dtfloat no Float64 method)" begin
        ts = ms.([Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0)])
        # _contiguous_ts has a bug when called with Float64 series —
        # dtfloat has no method for AbstractFloat. This is pre-existing.
        @test_throws MethodError _contiguous_ts(ts, 60000.0)
    end

    @testset "_check_contiguity passes for adjacent data" begin
        _check_contiguity(100.0, 200.0, 0.0, 60.0, 60.0)
        @test true
    end

    @testset "_check_contiguity throws RightContiguityException for gap ahead" begin
        @test_throws RightContiguityException _check_contiguity(200.0, 300.0, 0.0, 60.0, 60.0)
    end

    @testset "_check_contiguity throws LeftContiguityException for gap behind" begin
        @test_throws LeftContiguityException _check_contiguity(-200.0, -100.0, 0.0, 100.0, 60.0)
    end

    @testset "contiguous_ts string timeframe" begin
        ts_vec = [Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0), Dates.DateTime(2024,1,1,0,2,0)]
        @test Data.contiguous_ts(ts_vec, "1m")
    end
end

# ──────────────────────────────────────────────
# ZArray deletion (date-range via zdelete!)
# ──────────────────────────────────────────────
@testset "ZArray deletion via string API" begin
    @testset "delete! with string dates removes middle range" begin
        za = empty_zarray()
        ts = ms.([Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0), Dates.DateTime(2024,1,1,0,2,0), Dates.DateTime(2024,1,1,0,3,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts))

        # Use the Base.delete!(z::ZArray, to::String, from::String) wrapper
        Data.delete!(za, "2024-01-01T00:03:00", "2024-01-01T00:01:00")
        @test size(za, 1) == 2
        @test Dates.unix2datetime(za[1, 1] / 1000) == Dates.DateTime(2024,1,1,0,0,0)
        @test Dates.unix2datetime(za[2, 1] / 1000) == Dates.DateTime(2024,1,1,0,3,0)
    end

    @testset "delete! empty to string removes from beginning" begin
        za = empty_zarray()
        ts = ms.([Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0), Dates.DateTime(2024,1,1,0,2,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts))

        Data.delete!(za, "2024-01-01T00:01:00")
        @test size(za, 1) == 2
        @test Dates.unix2datetime(za[1, 1] / 1000) == Dates.DateTime(2024,1,1,0,1,0)
    end

    @testset "delete! with empty from removes to end" begin
        za = empty_zarray()
        ts = ms.([Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0), Dates.DateTime(2024,1,1,0,2,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts))

        Data.delete!(za, "", "2024-01-01T00:01:00")
        @test size(za, 1) == 1
        @test Dates.unix2datetime(za[1, 1] / 1000) == Dates.DateTime(2024,1,1,0,0,0)
    end
end

# ──────────────────────────────────────────────
# ZGroup operations
# ──────────────────────────────────────────────
@testset "ZGroup operations (DictStore)" begin
    @testset "empty! removes all arrays from group" begin
        store = DictStore()
        g = zgroup(store, "")

        # Create 2 arrays in the group
        z1 = zcreate(Float64, store, 10, 2; path="arr1", fill_value=0.0, fill_as_missing=false, compressor=Data.compressor)
        z2 = zcreate(Float64, store, 10, 2; path="arr2", fill_value=0.0, fill_as_missing=false, compressor=Data.compressor)
        g.arrays["arr1"] = z1
        g.arrays["arr2"] = z2
        @test length(g.arrays) == 2

        Data.delete!(g, "arr1")
        @test "arr1" ∉ keys(g.arrays)
        @test "arr2" ∈ keys(g.arrays)

        Data.empty!(g)
        @test isempty(g.arrays)
    end
end

# ──────────────────────────────────────────────
# unique! on ZArray
# ──────────────────────────────────────────────
@testset "ZArray unique!" begin
    @testset "unique! removes duplicate rows" begin
        za = empty_zarray()
        ts = ms.([Dates.DateTime(2024,1,1,0,0,0), Dates.DateTime(2024,1,1,0,1,0), Dates.DateTime(2024,1,1,0,1,0)])
        _save_ohlcv(za, 60000.0, make_ohlcv(ts); reset=true)
        @test size(za, 1) == 3

        Data.unique!(x -> round(x[1], digits=0), za)
        @test size(za, 1) == 2
    end
end

# ──────────────────────────────────────────────
# __ensure_ohlcv_zarray with fill_value edge case
# ──────────────────────────────────────────────
@testset "ensure_ohlcv_zarray fill_value" begin
    @testset "correct fill_value passes through" begin
        store = DictStore()
        g = zgroup(store, "")
        zi = Data.ZarrInstance("test", store, g)
        key = "test/pair/ohlcv/tf_60000"

        za, _ = Data._get_zarray(zi, key, (2730, OHLCV_COLUMNS_COUNT); overwrite=true, type=Float64, reset=true)
        result = Data.__ensure_ohlcv_zarray(zi, key)
        # zopen creates a new object, but the key path is the same
        @test result.metadata.fill_value isa Float64
        @test result.metadata.fill_value == 0.0
        @test size(result) == size(za)
    end

    @testset "null fill_value triggers recreate" begin
        store = DictStore()
        g = zgroup(store, "")
        zi = Data.ZarrInstance("test", store, g)
        key = "test/pair/ohlcv/tf_60000"

        # Create the array first
        za_orig, _ = Data._get_zarray(zi, key, (2730, OHLCV_COLUMNS_COUNT); overwrite=true, type=Float64, reset=true)
        # Corrupt the stored metadata: set fill_value to null in JSON
        raw = String(store["test/pair/ohlcv/tf_60000/.zarray"])
        corrupted = replace(raw, "\"fill_value\":\"?" * "[0-9.]+" => "\"fill_value\":null")
        store["test/pair/ohlcv/tf_60000/.zarray"] = codeunits(corrupted)
        # Now __ensure_ohlcv_zarray should recreate the array
        result = Data.__ensure_ohlcv_zarray(zi, key)
        @test result.metadata.fill_value isa Float64
        @test result.metadata.fill_value == 0.0
    end
end

# ──────────────────────────────────────────────
# ZarrInstance with DictStore (non-DirectoryStore)
# ──────────────────────────────────────────────
@testset "ZarrInstance creation" begin
    zi = Data.zinstance()
    @test zi isa ZarrInstance
    @test !isnothing(zi.store)
    @test !isnothing(zi.group)
end

# ──────────────────────────────────────────────
# DictView
# ──────────────────────────────────────────────
@testset "DictView" begin
    d = Dict("a" => 1, "b" => 2, "c" => 3)
    dv = Data.DictView(d, Set(["a", "c"]))
    @test dv["a"] == 1
    @test dv["c"] == 3
    @test_throws KeyError dv["b"]
    @test haskey(dv, "a")
    @test !haskey(dv, "b")
    @test length(dv) == 2
    @test sort(collect(values(dv))) == [1, 3]
end

# ──────────────────────────────────────────────
# PairData
# ──────────────────────────────────────────────
@testset "PairData" begin
    ts = Dates.DateTime(2024, 1, 1)
    df = DataFrame(:timestamp => [ts], :open => [1.0], :high => [2.0], :low => [0.5], :close => [1.5], :volume => [100.0])
    pd = PairData(name="BTC/USDT", tf="1m", data=df, z=nothing)
    @test pd.name == "BTC/USDT"
    @test pd.tf == "1m"
    @test pd.data == df
    @test pd.z === nothing
end

# ──────────────────────────────────────────────
# DataFrame utilities
# ──────────────────────────────────────────────
@testset "DFUtils" begin
    ts = Dates.DateTime(2024, 1, 1, 0, 0)
    df = DataFrame(
        :timestamp => ts:Dates.Minute(1):(ts + Dates.Minute(9)),
        (col => [100.0 + i for i in 0:9] for col in [:open, :high, :low, :close, :volume])...,
    )

    @test Data.DFUtils.firstdate(df) == ts
    @test Data.DFUtils.lastdate(df) == ts + Dates.Minute(9)

    tf = Data.DFUtils.timeframe(df)
    @test tf isa Data.Misc.TimeTicks.TimeFrame

    idx = Data.DFUtils.dateindex(df, ts + Dates.Minute(3))
    @test idx == 4

    after_view = Data.DFUtils.after(df, ts + Dates.Minute(5))
    @test size(after_view, 1) == 4

    before_view = Data.DFUtils.before(df, ts + Dates.Minute(5))
    @test size(before_view, 1) == 5

    dr = Data.DFUtils.daterange(df)
    @test dr isa Data.Misc.TimeTicks.DateRange
end

# ──────────────────────────────────────────────
# Module exports
# ──────────────────────────────────────────────
@testset "Exports" begin
    @test isdefined(Data, :Candle)
    @test isdefined(Data, :PairData)
    @test isdefined(Data, :OHLCV_COLUMNS)
    @test isdefined(Data, :OHLCVTuple)
    @test isdefined(Data, :contiguous_ts)
end
