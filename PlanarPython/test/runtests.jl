module PlanarPythonTests

using Test
using PlanarPython
using PlanarPython: islist, isdict

@testset "PlanarPython" begin
    @testset "islist with Julia types" begin
        @test islist([1, 2, 3]) == true
        @test islist(Vector{Int}()) == true
        @test islist((1, 2, 3)) == false  # Tuple is not AbstractVector
        @test islist("string") == false
        @test islist(123) == false
        @test islist(nothing) == false
    end

    @testset "isdict with Julia types" begin
        @test isdict(Dict("a" => 1)) == true
        @test isdict(Dict{String,Int}()) == true
        @test isdict(["a" => 1]) == false  # Vector of pairs is not AbstractDict
        @test isdict((a=1,)) == false  # NamedTuple is not AbstractDict
        @test isdict("string") == false
        @test isdict(123) == false
        @test isdict(nothing) == false
    end

    @testset "exports" begin
        @test isdefined(PlanarPython, :clearpypath!)
        @test isdefined(PlanarPython, :pytryfloat)
        @test isdefined(PlanarPython, Symbol("@pymodule"))
        @test isdefined(PlanarPython, Symbol("@pystr"))
        @test isdefined(PlanarPython, :pytofloat)
        @test isdefined(PlanarPython, :pyisnonzero)
        @test isdefined(PlanarPython, :pydicthash)
        @test isdefined(PlanarPython, :islist)
        @test isdefined(PlanarPython, :isdict)
    end
end

end