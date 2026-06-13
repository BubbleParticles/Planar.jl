using Test
using TimeTicks
using TimeTicks: timestamp, timeframe, dtfloat, ms, from_to_dt, dt, dtstamp
const Dates = TimeTicks.Dates

# ──────────────────────────────────────────────
# TimeFrame parsing
# ──────────────────────────────────────────────
# ──────────────────────────────────────────────
# nameof — human-readable TimeFrame names
# ──────────────────────────────────────────────
@testset "TimeFrame nameof" begin
    @test TimeTicks.nameof(tf"1ms") == "1ms"
    @test TimeTicks.nameof(tf"1s") == "1s"
    @test TimeTicks.nameof(tf"1m") == "1m"
    @test TimeTicks.nameof(tf"5m") == "5m"
    @test TimeTicks.nameof(tf"1h") == "1h"
    @test TimeTicks.nameof(tf"1d") == "1d"
    @test TimeTicks.nameof(tf"1w") == "7d"
    @test TimeTicks.nameof(tf"1M") == "30d"
    @test TimeTicks.nameof(tf"1y") == "365d"
end

# ──────────────────────────────────────────────
# ms — millisecond conversion
# ──────────────────────────────────────────────
@testset "ms conversion" begin
    @test ms(Dates.Day(1)) == Dates.Millisecond(Dates.Day(1))
    @test ms(Dates.Minute(1)) == Dates.Millisecond(60000)
    @test ms(Dates.Second(30)) == Dates.Millisecond(30000)
    @test ms(Dates.CompoundPeriod(Dates.Minute(1), Dates.Second(30))) == Dates.Millisecond(90000)
    @test ms(1000) == Dates.Millisecond(1000)
end

# ──────────────────────────────────────────────
# compact — period compaction
# ──────────────────────────────────────────────
@testset "compact" begin
    @test compact(Dates.Millisecond(500)) == Dates.Millisecond(500)
    @test compact(Dates.Millisecond(1500)) == Dates.Second(2)
    @test compact(Dates.Millisecond(60000)) == Dates.Minute(1)
    @test compact(Dates.Millisecond(3600000)) == Dates.Hour(1)
    @test compact(Dates.Millisecond(86400000)) == Dates.Day(1)
end

# ──────────────────────────────────────────────
# count — TimeFrame-in-TimeFrame
# ──────────────────────────────────────────────
@testset "count TimeFrames" begin
    @test Base.count(tf"1m", tf"5m") == 5
    @test Base.count(tf"5m", tf"1h") == 12
    @test Base.count(tf"1m", tf"1d") == 1440
    @test Base.count(tf"1h", tf"1d") == 24
end

# ──────────────────────────────────────────────
# available — previous timeframe bound
# ──────────────────────────────────────────────
@testset "available" begin
    base = Dates.DateTime(2024, 1, 15, 10, 30, 0)
    @test available(tf"5m", base) == Dates.DateTime(2024, 1, 15, 10, 25, 0)
    @test available(tf"1h", base) == Dates.DateTime(2024, 1, 15, 9, 0, 0)
    @test available(tf"1d", base) == Dates.DateTime(2024, 1, 14, 0, 0, 0)
end

# ──────────────────────────────────────────────
# dtstamp — DateTime to integer timestamp
# ──────────────────────────────────────────────
@testset "dtstamp" begin
    d = Dates.DateTime(2024, 1, 15, 10, 30, 0)
    @test dtstamp(d) == 1705314600000
    @test dtstamp(d, Val(:round)) == dtstamp(d)
    @test dtstamp(0) == 0
    @test dtstamp(0.0) == dtstamp(Dates.unix2datetime(0))
end

# ──────────────────────────────────────────────
# timestamp — DateTime to unix timestamp
# ──────────────────────────────────────────────
@testset "timestamp" begin
    d = Dates.DateTime(2024, 1, 15, 10, 30, 0)
    @test timestamp(d) == 1705314600
    @test timestamp(d, Val(:trunc)) == 1705314600
    @test timestamp("2024-01-15T10:30:00") == 1705314600
end

# ──────────────────────────────────────────────
# timefloat — string and symbol overloads
# ──────────────────────────────────────────────
@testset "timefloat overloads" begin
    @test timefloat(0.0) == 0.0
    @test timefloat(Int64(5000)) == 5000.0
    @test timefloat("2024-01-01") ≈ dtfloat(Dates.DateTime(2024,1,1))
end

# ──────────────────────────────────────────────
# TimeFrames.apply for numeric types
# ──────────────────────────────────────────────
@testset "TimeFrames.apply numeric" begin
    @test TimeTicks.TimeFrames.apply(5.0, 13.0) ≈ 15.0
    @test TimeTicks.TimeFrames.apply(10.0, 23.0) ≈ 20.0
end

# ──────────────────────────────────────────────
# timeframe from Float64
# ──────────────────────────────────────────────
@testset "timeframe from Float64" begin
    tf1 = timeframe(60000.0)
    @test tf1 isa TimeFrame
    @test ms(tf1) == Dates.Millisecond(60000)
end

# ──────────────────────────────────────────────
# DateRange iteration
# ──────────────────────────────────────────────
@testset "DateRange iteration" begin
    start_dt = Dates.DateTime(2024, 1, 1)
    stop_dt = Dates.DateTime(2024, 1, 3)
    dr = DateRange(start_dt, stop_dt, Dates.Day(1))
    @test length(dr) == 2

    coll = collect(dr)
    @test length(coll) == 2
    @test coll[1] == start_dt
    @test coll[2] == start_dt + Dates.Day(1)

    dr2 = DateRange(start_dt, stop_dt, Dates.Day(1))
    @test isequal(dr, dr2)

    dr3 = DateRange(start_dt, stop_dt + Dates.Day(1), Dates.Day(1))
    @test !isequal(dr, dr3)

    @test isapprox(DateRange(start_dt, stop_dt), DateRange(start_dt - Dates.Day(1), stop_dt))

    sim = similar(dr)
    @test sim.start == dr.start
    @test sim.stop == dr.stop
    @test sim.step == dr.step
end

# ──────────────────────────────────────────────
# Base.isless for Week vs Month
# ──────────────────────────────────────────────
@testset "Week vs Month comparison" begin
    @test Dates.Week(1) < Dates.Month(1)
    @test Dates.Week(4) < Dates.Month(1)
    @test !(Dates.Week(5) < Dates.Month(1))
    @test Dates.Week(4) != Dates.Month(1)
end

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
