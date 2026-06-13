module PythonTests

using Test
using Python
using Python: islist, isdict

@testset "Python" begin
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
        @test isdefined(Python, :clearpypath!)
        @test isdefined(Python, :pytryfloat)
        @test isdefined(Python, Symbol("@pymodule"))
        @test isdefined(Python, Symbol("@pystr"))
        @test isdefined(Python, :pytofloat)
        @test isdefined(Python, :pyisnonzero)
        @test isdefined(Python, :pydicthash)
        @test isdefined(Python, :islist)
        @test isdefined(Python, :isdict)
    end
end

end