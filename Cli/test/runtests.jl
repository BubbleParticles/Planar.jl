module CliTests

using Test
using Cli

@testset "Cli" begin
    @testset "Module loads" begin
        @test isdefined(Cli, :main)
        @test isdefined(Cli, :run_cli)
    end
end

end