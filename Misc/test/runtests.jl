using Test
using Misc
using Misc.TimeToLive: TTL, safettl, isexpired
using Misc.Sandbox: safereval
using Misc: drop, isstrictlysorted, roundfloat, toprecision, rangeafter, rangebefore, rangebetween, after, before, between, rewritekeys!, swapkeys, RightContiguityException, LeftContiguityException
const Dates = Misc.TimeTicks.Dates

# ──────────────────────────────────────────────
# Constants
# ──────────────────────────────────────────────
@testset "Constants" begin
    @test isdefined(Misc, :DFT)
    @test isdefined(Misc, :ZERO)
    @test isdefined(Misc, :ONE)
    @test isdefined(Misc, :ATOL)
    @test isdefined(Misc, :OFFLINE)
    @test Misc.fetch_limits isa IdDict
    @test Misc.futures_exchange isa IdDict
    @test Misc.fetch_limits[:binance] == 20000
    @test Misc.futures_exchange[:kucoin] == :kucoinfutures
end

# ──────────────────────────────────────────────
# ExecMode types
# ──────────────────────────────────────────────
@testset "ExecMode" begin
    @test Sim() isa ExecMode
    @test Paper() isa ExecMode
    @test Live() isa ExecMode
    @test execmode() == Sim()
    @test execmode(:anything) == Sim()
end

# ──────────────────────────────────────────────
# MarginMode types
# ──────────────────────────────────────────────
@testset "MarginMode" begin
    @test NoMargin() isa MarginMode
    @test Isolated() isa MarginMode
    @test Cross() isa MarginMode
    @test Misc.IsolatedHedged() isa MarginMode
    @test Misc.CrossHedged() isa MarginMode
    @test marginmode() == NoMargin()
    @test marginmode("isolated") == Misc.IsolatedMargin
    @test marginmode("cross") == Misc.CrossMargin
    @test_throws ErrorException marginmode("invalid")
end

# ──────────────────────────────────────────────
# PositionSide
# ──────────────────────────────────────────────
@testset "PositionSide" begin
    @test opposite(Long) == Short
    @test opposite(Long()) == Short()
    @test opposite(Short) == Long
    @test opposite(Short()) == Long()
    @test Long() == Long()
    @test Short() == Short()
    @test Long() != Short()
    @test Long() == Long
    @test Short() == Short
    @test Long == Long
    @test Short == Short
end

# ──────────────────────────────────────────────
# drop (NamedTuple key removal)
# ──────────────────────────────────────────────
@testset "drop" begin
    nt = (a=1, b=2, c=3)
    @test drop(nt, (:a,)) == (b=2, c=3)
    @test drop(nt, (:a, :c)) == (b=2,)
    @test drop(nt, ()) == nt
    @test drop((x=10,), (:x,)) == NamedTuple()
end

# ──────────────────────────────────────────────
# Exceptions
# ──────────────────────────────────────────────
@testset "Exceptions" begin
    rce = RightContiguityException(Dates.DateTime(2024,1,1), Dates.DateTime(2024,1,2))
    lce = LeftContiguityException(Dates.DateTime(2024,1,1), Dates.DateTime(2024,1,2))
    @test rce isa ContiguityException
    @test rce isa Exception
    @test lce isa Exception
    @test startswith(sprint(show, rce), "RightContiguityException(")
    @test startswith(sprint(show, lce), "LeftContiguityException(")
end

# ──────────────────────────────────────────────
# Sandbox safereval
# ──────────────────────────────────────────────
@testset "safereval" begin
    @test safereval("42") == 42
    @test safereval("3.14") == 3.14
    @test safereval("Float64") == Float64
    @test_throws ErrorException safereval("1+1")
    @test_throws ErrorException safereval("println(\"hi\")")
end

# ──────────────────────────────────────────────
# isstrictlysorted
# ──────────────────────────────────────────────
@testset "isstrictlysorted" begin
    @test isstrictlysorted(1, 2, 3)
    @test !isstrictlysorted(1, 1, 2)
    @test !isstrictlysorted(3, 2, 1)
    @test isstrictlysorted()
    @test isstrictlysorted(1)
    @test isstrictlysorted(1.0, 2.0, 3.0)
    @test !isstrictlysorted(1.0, 0.5)
end

# ──────────────────────────────────────────────
# roundfloat / toprecision
# ──────────────────────────────────────────────
@testset "roundfloat / toprecision" begin
    @test roundfloat(1.23456, 0.01) ≈ 1.23
    @test roundfloat(1.23456, 0.001) ≈ 1.235
    @test toprecision(1.23456, 0.01) ≈ 1.23
    @test toprecision(1.23456, 2) ≈ 1.23
    @test toprecision(1.23456, UInt(3)) ≈ 1.23
    @test toprecision(5, 2) == 4.0
end

# ──────────────────────────────────────────────
# approxzero / gtxzero / ltxzero / positive / negative
# ──────────────────────────────────────────────
@testset "Numeric predicates" begin
    @test approxzero(0.0)
    @test approxzero(1e-15)
    @test !approxzero(1.0)
    @test gtxzero(1.0)
    @test gtxzero(0.0)
    @test !gtxzero(-1.0)
    @test ltxzero(-1.0)
    @test ltxzero(0.0)
    @test !ltxzero(1.0)
    @test positive(-3.0) == 3.0
    @test positive(3.0) == 3.0
    @test negative(3.0) == -3.0
    @test negative(-3.0) == -3.0
end

# ──────────────────────────────────────────────
# inc! / dec!
# ──────────────────────────────────────────────
@testset "inc! / dec!" begin
    r = Ref(5)
    inc!(r)
    @test r[] == 6
    dec!(r)
    @test r[] == 5
end

# ──────────────────────────────────────────────
# shift!
# ──────────────────────────────────────────────
@testset "shift!" begin
    v = [1.0, 2.0, 3.0, 4.0]
    shift!(v, 1, NaN)
    @test isequal(v, [NaN, 1.0, 2.0, 3.0])
    v2 = [1.0, 2.0, 3.0]
    shift!(v2, -1, NaN)
    @test isequal(v2, [2.0, NaN, NaN])
end

# ──────────────────────────────────────────────
# rangeafter / rangebefore / rangebetween
# ──────────────────────────────────────────────
@testset "rangeafter / before / between" begin
    v = [1, 2, 3, 3, 3, 4, 5]
    @test rangeafter(v, 3) == 6:7
    @test rangeafter(v, 3; strict=false) == 4:7
    @test rangebefore(v, 3) == 1:2
    @test rangebefore(v, 3; strict=false) == 1:4
    @test rangebetween(v, 2, 4; strict=true) == 3:5
    @test rangebetween(v, 2, 4; strict=false) == 3:5
    r = rangeafter(v, 99)
    @test isempty(v[r])
end

# ──────────────────────────────────────────────
# after / before / between (views)
# ──────────────────────────────────────────────
@testset "after / before / between views" begin
    v = [1, 2, 3, 4, 5]
    @test collect(after(v, 3)) == [4, 5]
    @test collect(before(v, 3)) == [1, 2]
    @test collect(between(v, 2, 4)) == [3]
end

# ──────────────────────────────────────────────
# rewritekeys! / swapkeys
# ──────────────────────────────────────────────
@testset "rewritekeys! / swapkeys" begin
    d = Dict(:a => 1, :b => 2)
    rewritekeys!(d, k -> Symbol(uppercase(string(k))))
    @test haskey(d, :A)
    @test haskey(d, :B)
    @test d[:A] == 1

    d2 = Dict(:foo => 10, :bar => 20)
    d3 = swapkeys(d2, String, string; dict_type=Dict)
    @test d3 isa Dict{String,Int}
    @test d3["foo"] == 10
end

# ──────────────────────────────────────────────
# UniqueIterator
# ──────────────────────────────────────────────
@testset "UniqueIterator" begin
    v = [1, 1, 2, 2, 3, 1, 2]
    u = collect(UniqueIterator(v))
    @test u == [1, 2, 3]

    v2 = ["a", "A", "b", "B"]
    u2 = collect(UniqueIterator(v2; by=lowercase))
    @test u2 == ["a", "b"]
end

# ──────────────────────────────────────────────
# attrs family
# ──────────────────────────────────────────────
@testset "attrs / attr / hasattr" begin
    struct FakeObj
        attrs::Dict{Any,Any}
    end
    obj = FakeObj(Dict(:x => 1, :y => 2))
    @test attrs(obj) == Dict(:x => 1, :y => 2)
    @test attr(obj, :x) == 1
    @test attr(obj, :z, 99) == 99
    @test hasattr(obj, :x)
    @test !hasattr(obj, :z)
    setattr!(obj, 42, :z)
    @test attr(obj, :z) == 42
end

# ──────────────────────────────────────────────
# SortedArray — basic
# ──────────────────────────────────────────────
@testset "SortedArray basic" begin
    sa = SortedArray(Int[3, 1, 2])
    @test collect(sa) == [1, 2, 3]
    @test issorted(sa)
    @test length(sa) == 3
    @test sort(sa) == sa

    sa_rev = SortedArray(Int[1, 3, 2]; rev=true)
    @test collect(sa_rev) == [3, 2, 1]
    @test issorted(sa_rev)

    sa_by = SortedArray(["aa", "b", "ccc"]; by=length)
    @test collect(sa_by) == ["b", "aa", "ccc"]

    sa_empty = SortedArray(Int[])
    @test isempty(sa_empty)
    @test length(sa_empty) == 0
end

@testset "SortedArray push!" begin
    sa = SortedArray(Int[1, 3, 5])
    push!(sa, 4)
    @test collect(sa) == [1, 3, 4, 5]
    push!(sa, 0)
    @test collect(sa) == [0, 1, 3, 4, 5]
    push!(sa, 6)
    @test collect(sa) == [0, 1, 3, 4, 5, 6]

    sa_rev = SortedArray(Int[1, 3, 5]; rev=true)
    push!(sa_rev, 4)
    @test collect(sa_rev) == [5, 4, 3, 1]

    sa_by = SortedArray(["aa", "cccc"]; by=length)
    push!(sa_by, "bbb")
    @test collect(sa_by) == ["aa", "bbb", "cccc"]
end

@testset "SortedArray append!" begin
    sa = SortedArray(Int[1, 4])
    append!(sa, [3, 2, 5])
    @test collect(sa) == [1, 2, 3, 4, 5]
end

@testset "SortedArray error paths" begin
    sa = SortedArray(Int[1, 2, 3])
    @test_throws ErrorException sa[1] = 99
    @test_throws ErrorException pushfirst!(sa, 0)
    @test_throws ErrorException insert!(sa, 1, 0)
    @test_throws ErrorException permute!(sa)
    @test_throws ErrorException invpermute!(sa)
end

@testset "SortedArray pop" begin
    sa = SortedArray(Int[1, 2, 3])
    @test pop!(sa) == 3
    @test collect(sa) == [1, 2]
    @test popfirst!(sa) == 1
    @test collect(sa) == [2]
end

@testset "SortedArray map / filter" begin
    sa = SortedArray(Int[1, 2, 3])
    sa2 = map(x -> x * 10, sa)
    @test collect(sa2) == [10, 20, 30]
    @test issorted(sa2)

    sa3 = filter(x -> x > 1, sa)
    @test collect(sa3) == [2, 3]
    @test issorted(sa3)
end

@testset "SortedArray set operations" begin
    sa1 = SortedArray(Int[1, 2, 3, 4])
    sa2 = SortedArray(Int[3, 4, 5, 6])
    @test collect(intersect(sa1, sa2)) == [3, 4]
    @test collect(union(sa1, sa2)) == [1, 2, 3, 4, 5, 6]
    @test collect(setdiff(sa1, sa2)) == [1, 2]
end

@testset "SortedArray vcat" begin
    sa1 = SortedArray(Int[1, 3])
    sa2 = SortedArray(Int[2, 4])
    sa3 = vcat(sa1, sa2)
    @test collect(sa3) == [1, 2, 3, 4]
    @test issorted(sa3)
end

@testset "SortedArray searchsorted" begin
    sa = SortedArray(Int[1, 2, 3, 3, 3, 4, 5])
    r = searchsorted(sa, 3)
    @test r == 3:5
    @test searchsortedfirst(sa, 3) == 3
    @test searchsortedlast(sa, 3) == 5
end

@testset "SortedArray broadcast" begin
    sa = SortedArray(Int[1, 2, 3])
    result = sa .* 10
    @test collect(result) == [10, 20, 30]
    @test issorted(result)
end

@testset "SortedArray serialization" begin
    sa = SortedArray(Int[3, 1, 2])
    buf = IOBuffer()
    Misc.serialize(buf, sa)
    seekstart(buf)
    sa2 = Misc.deserialize(buf)
    @test collect(sa2) == [1, 2, 3]
    @test issorted(sa2)
end

@testset "SortedArray copy / reverse" begin
    sa = SortedArray(Int[3, 1, 2])
    sa_copy = copy(sa)
    @test collect(sa_copy) == [1, 2, 3]
    sa_rev = reverse(sa)
    @test collect(sa_rev) == [3, 2, 1]
    @test issorted(sa_rev)
end

# ──────────────────────────────────────────────
# TTL cache
# ──────────────────────────────────────────────
@testset "TTL basic" begin
    ttl = TTL{String,Int}(Dates.Minute(60))
    ttl["a"] = 1
    ttl["b"] = 2
    @test ttl["a"] == 1
    @test ttl["b"] == 2
    @test length(ttl) == 2
    @test haskey(ttl, "a")
end

@testset "TTL not yet expired" begin
    ttl = TTL{String,Int}(Dates.Hour(1))
    ttl["key"] = 42
    @test get(ttl, "key", -1) == 42
end

@testset "TTL get with default" begin
    ttl = TTL{String,Int}(Dates.Hour(1))
    @test get(ttl, "nonexistent", -1) == -1
    ttl["x"] = 10
    @test get(ttl, "x", -1) == 10
end

@testset "TTL getkey" begin
    ttl = TTL{String,Int}(Dates.Hour(1))
    @test getkey(ttl, "x", "default") == "default"
    ttl["x"] = 10
    @test getkey(ttl, "x", "default") == "x"
end

@testset "TTL delete!" begin
    ttl = TTL{String,Int}(Dates.Hour(1))
    ttl["a"] = 1
    ttl["b"] = 2
    delete!(ttl, "a")
    @test !haskey(ttl, "a")
    @test haskey(ttl, "b")
end

@testset "TTL empty!" begin
    ttl = TTL{String,Int}(Dates.Hour(1))
    ttl["a"] = 1
    ttl["b"] = 2
    empty!(ttl)
    @test length(ttl) == 0
end

@testset "TTL push!" begin
    ttl = TTL{String,Int}(Dates.Hour(1))
    push!(ttl, "a" => 10)
    @test ttl["a"] == 10
end

@testset "TTL safettl" begin
    sttl = safettl(String, Int, Dates.Minute(5))
    sttl["x"] = 99
    @test sttl["x"] == 99
end

@testset "TTL expired" begin
    ttl = TTL{String,Int}(Dates.Millisecond(1))
    ttl["flash"] = 999
    sleep(0.01)
    @test get(ttl, "flash", -1) == -1
    @test_throws KeyError ttl["flash"]
end

# ──────────────────────────────────────────────
# Config — basic
# ──────────────────────────────────────────────
@testset "Config default" begin
    c = Config()
    @test c isa Config
    @test c.mode === nothing
    @test c.sandbox == true
    @test c.leverage == 0.0
    @test c.qc == :USDT
end

@testset "Config copy / reset" begin
    c = Config()
    c.qc = :BTC
    c.sandbox = false
    c2 = copy(c)
    @test c2.qc == :BTC
    @test c2.sandbox == false
    c2.qc = :ETH
    @test c.qc == :BTC
    reset!(c)
    @test c.qc == :USDT
    @test c.sandbox == true
end
