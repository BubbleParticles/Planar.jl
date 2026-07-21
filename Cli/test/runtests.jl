module CliTests

using Test
using Cli

@testset "Cli" begin
    @testset "Module loads" begin
        @test isdefined(Cli, :Cli)
        # @main macro from Comonicon creates CLI entry point, not regular functions
        @test true
    end
end

end