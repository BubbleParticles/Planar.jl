module OptTests

using Test
using Opt
using Opt: filtervecs, DEFAULT_OBJ, bbomethods, disabled_methods

@testset "Opt" begin
    @testset "DEFAULT_OBJ constant" begin
        @test DEFAULT_OBJ == float(typemax(Int))
        @test DEFAULT_OBJ > 1e9
    end

    @testset "filtervecs" begin
        # Function iterates across columns (dimension 2)
        vov = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
        filter_func = x -> x > 2
        result = filtervecs(vov, filter_func)
        # Column 1: [1,4,7] -> [4,7]; Column 2: [2,5,8] -> [5,8]; Column 3: [3,6,9] -> [3,6,9]
        @test result == [[4, 7], [5, 8], [3, 6, 9]]

        # Test with default filter (x != DEFAULT_OBJ)
        vov2 = [[1.0, 2.0], [DEFAULT_OBJ, 4.0], [5.0, DEFAULT_OBJ]]
        result2 = filtervecs(vov2)
        # Column 1: [1.0, DEFAULT_OBJ, 5.0] -> [1.0, 5.0]; Column 2: [2.0, 4.0, DEFAULT_OBJ] -> [2.0, 4.0]
        @test result2[1] == [1.0, 5.0]
        @test result2[2] == [2.0, 4.0]

        # Test with empty input
        @test filtervecs(Vector{Vector{Float64}}()) == Vector{Vector{Float64}}()

        # Test with custom default_val
        vov3 = [[1.0, DEFAULT_OBJ], [DEFAULT_OBJ, 2.0]]
        result3 = filtervecs(vov3; default_val=-1.0)
        # Column 1: [1.0, DEFAULT_OBJ] -> [1.0]; Column 2: [DEFAULT_OBJ, 2.0] -> [2.0]
        # Since filtered is not empty, default_val not used
        @test result3[1] == [1.0]
        @test result3[2] == [2.0]

        # Test where filter removes all elements
        vov4 = [[DEFAULT_OBJ], [DEFAULT_OBJ]]
        result4 = filtervecs(vov4; default_val=-99.0)
        @test result4[1] == [-99.0]
    end

    @testset "bbo disabled_methods" begin
        @test disabled_methods isa Set
        @test :simultaneous_perturbation_stochastic_approximation in disabled_methods
        @test :resampling_memetic_search in disabled_methods
        @test :resampling_inheritance_memetic_search in disabled_methods
    end

    @testset "bbomethods" begin
        # Test single-objective methods
        methods_single = bbomethods(false)
        @test methods_single isa Set{Symbol}
        @test !isempty(methods_single)
        @test all(m -> m ∉ disabled_methods, methods_single)

        # Test multi-objective methods
        methods_multi = bbomethods(true)
        @test methods_multi isa Set{Symbol}
        @test all(m -> m ∉ disabled_methods, methods_multi)

        # They should be different
        @test methods_single != methods_multi || isempty(methods_single ∩ methods_multi)
    end
end

end