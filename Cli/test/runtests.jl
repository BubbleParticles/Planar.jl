module CliTests

using Test
using Cli

@testset "Cli" begin
    @testset "Module loads" begin
        @test isdefined(Cli, :Cli)
    end
end

end