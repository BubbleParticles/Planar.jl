using Test
using TimeTicks
using TimeTicks: timestamp, timeframe, dtfloat, ms, from_to_dt, dt
const Dates = TimeTicks.Dates

# ──────────────────────────────────────────────
# TimeFrame parsing
# ──────────────────────────────────────────────
@testset "TimeFrame parsing" begin
    tf1 = tf"1m"
    @test tf1 isa TimeFrame
    @test string(tf1) == "1m"

    tf2 = tf"1h"
    @test string(tf2) == "1h"

    tf3 = tf"1d"
    @test string(tf3) == "1d"

    tf4 = parse(TimeFrame, "5m")
    @test string(tf4) == "5m"

    tf5 = parse(TimeFrame, "1w")
    @test string(tf5) == "7d"

    tf6 = parse(TimeFrame, "1M")
    @test string(tf6) == "30d"

    tf7 = parse(TimeFrame, "1y")
    @test string(tf7) == "365d"
end

# ──────────────────────────────────────────────
# TimeFrame comparison
# ──────────────────────────────────────────────
@testset "TimeFrame comparison" begin
    tf1 = tf"1m"
    tf2 = tf"5m"
    tf3 = tf"1h"
    @test tf1 < tf2
    @test tf2 < tf3
    @test tf1 == tf"1m"
    @test tf1 != tf2
end

# ──────────────────────────────────────────────
# dt/now helpers
# ──────────────────────────────────────────────
@testset "Date/time helpers" begin
    d = Dates.DateTime(2024, 1, 15, 10, 30, 0)
    @test dt(d) == d
    @test dt(0.0) == Dates.DateTime(1970, 1, 1, 0, 0, 0)
    @test dt(Float64(dtfloat(d))) == d

    tf = dtfloat(d)
    @test tf ≈ dtfloat(Dates.DateTime(2024, 1, 15, 10, 30, 0))
end

# ──────────────────────────────────────────────
# Time conversion
# ──────────────────────────────────────────────
@testset "Time conversion" begin
    @test ms(Dates.Day(1)) == Dates.Millisecond(Dates.Day(1))
    @test timefloat(Dates.Millisecond(1000)) == 1000.0
    @test timestamp(Dates.DateTime(2024, 1, 1)) == 1704067200
    @test timeframe("1h") isa TimeFrame
end

# ──────────────────────────────────────────────
# from_to_dt
# ──────────────────────────────────────────────
@testset "from_to_dt" begin
    f, t = from_to_dt(tf"1d", "-10", "")
    @test t == ""  # empty to string returns as-is
    d10 = now() - Dates.Day(10)
    @test abs(Dates.value(f - d10)) <= 5000  # within 5 seconds (in ms)
end

# ──────────────────────────────────────────────
# String macros
# ──────────────────────────────────────────────
@testset "String macros" begin
    @test tf"15m" isa TimeFrame
    @test string(tf"15m") == "15m"
    @test dt"2024-01-15T10:30:00" == Dates.DateTime(2024, 1, 15, 10, 30, 0)
    @test dt"2024-01-15T10:30:00.123" == Dates.DateTime(2024, 1, 15, 10, 30, 0, 123)
end

# ──────────────────────────────────────────────
# DateRange (ported from PlanarDev/test/test_time.jl)
# ──────────────────────────────────────────────
@testset "DateRange" begin
    d = dtr"2020-01-..2020-03"
    @test d.start == Dates.DateTime(2020, 1, 1)
    @test d.stop == Dates.DateTime(2020, 3, 1)
    @test isnothing(d.step)

    d = dtr"2020-01-02T23:12:..2021-02-03T00:00:05"
    @test d.start == Dates.DateTime(2020, 1, 2, 23, 12)
    @test d.stop == Dates.DateTime(2021, 2, 3, 0, 0, 5)

    d = dtr"2020-..2021-;1d"
    @test d.step == Dates.Day(1)

    d = dtr"2020-..2021-;15m"
    @test d.step == Dates.Minute(15)
end
