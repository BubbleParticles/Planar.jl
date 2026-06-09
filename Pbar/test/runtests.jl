module Runtests

using Test
using Pbar

@testset "Pbar" begin
    @testset "exports" begin
        @test isdefined(Pbar, :RunningJob)
        @test isdefined(Pbar, :ProgressJob)
    end

    @testset "clearpbar with jobs" begin
        Pbar._doinit()
        Pbar.Term.Progress.addjob!(Pbar.pbar[]; description="test", N=10)
        @test length(Pbar.pbar[].jobs) == 1
        Pbar.clearpbar()
        @test length(Pbar.pbar[].jobs) == 0
    end

    @testset "pbclose! with pbar" begin
        Pbar._doinit()
        Pbar.pbclose!()
        @test true
    end

    @testset "dorender" begin
        Pbar._doinit()
        result = Pbar.dorender(Pbar.pbar[])
        @test result == false
    end

    @testset "complete!" begin
        Pbar._doinit()
        job = Pbar.Term.Progress.addjob!(Pbar.pbar[]; description="test", N=10)
        Pbar.complete!(Pbar.pbar[], job)
        @test true
    end

    @testset "pbclose! two-arg" begin
        Pbar._doinit()
        job = Pbar.Term.Progress.addjob!(Pbar.pbar[]; description="test", N=10)
        Pbar.pbclose!(job)
        @test true
    end
end

end # module Runtests
