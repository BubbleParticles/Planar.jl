using Test
using Lang

@testset "Option" begin
    @test Option{Int} == Union{Nothing,Int}
    @test Option{String} == Union{Nothing,String}
end

@testset "passkwargs" begin
    expr = passkwargs(:(a=1), :(b=2))
    @test expr isa Vector
    @test length(expr) == 2
end

@testset "filterkws / splitkws / withoutkws" begin
    kws = Dict(:a => 1, :b => 2, :c => 3)
    filtered = collect(filterkws(:a, :c; kwargs=kws))
    @test filtered == [(:a, 1), (:c, 3)]

    splitted = splitkws(:b; kwargs=kws)
    @test collect(splitted.filtered) == [(:b, 2)]
    @test collect(splitted.rest) == [(:a, 1), (:c, 3)]

    rest = withoutkws(:a; kwargs=kws)
    @test collect(rest) == [(:b, 2), (:c, 3)]
end

@testset "@lget! / @kget!" begin
    d = Dict(:a => 1)
    v = @lget!(d, :a, 99)
    @test v == 1
    v2 = @lget!(d, :b, 42)
    @test v2 == 42
    @test d[:b] == 42

    d2 = Dict(:x => 10)
    v3 = @kget!(d2, :x, 999)
    @test v3 == 10
    v4 = @kget!(d2, :y, 77)
    @test v4 == 77
    @test d2[:y] == 77
end

@testset "fromstruct" begin
    struct Point
        x::Int
        y::Int
    end
    p = Point(3, 4)
    nt = Lang.fromstruct(p)
    @test nt isa NamedTuple
    @test nt.x == 3
    @test nt.y == 4
end

@testset "@sym_str" begin
    s = sym"hello"
    @test s isa Symbol
    @test s == :hello
end

@testset "MatchString / @m_str" begin
    m = Lang.@m_str("test")
    @test m isa Lang.MatchString
    @test m.s == "test"
end

@testset "ifproperty! / ifkey!" begin
    mutable struct PropTest
        x::Int
    end
    st = PropTest(1)
    result = Lang.ifproperty!(>, st, :x, 0)
    @test st.x == 0

    d = Dict(:a => 5)
    Lang.ifkey!(>, d, :a, 3)
    @test d[:a] == 3
    Lang.ifkey!(<, d, :a, 10)
    @test d[:a] == 10
end

@testset "isowned / isownable" begin
    l = ReentrantLock()
    @test !islocked(l)
    @test isownable(l)
end

@testset "toggle!" begin
    mutable struct Tog
        flag::Bool
    end
    t = Tog(true)
    Lang.toggle!(t, :flag)
    @test !t.flag
    Lang.toggle!(t, :flag)
    @test t.flag
end

@testset "waitref / waitfunc" begin
    r = Ref(true)
    @test Lang.waitref(r) === nothing

    f = () -> true
    @test Lang.waitfunc(f) === nothing
end

@testset "@caller" begin
    s = @caller()
    @test s isa String
end
