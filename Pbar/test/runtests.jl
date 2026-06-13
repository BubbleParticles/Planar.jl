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

    @testset "RunningJob struct" begin
        Pbar._doinit()
        job = Pbar.Term.Progress.addjob!(Pbar.pbar[]; description="test", N=10)
        rj = Pbar.RunningJob(; job=job)
        @test rj.counter == 1
        @test rj.job === job
        @test rj.updated_at isa Pbar.DateTime
    end

    @testset "transient! toggles flag" begin
        Pbar._doinit()
        orig = Pbar.pbar[].transient
        Pbar.transient!()
        @test Pbar.pbar[].transient != orig
    end

    @testset "frequency! sets min_delta" begin
        old = Pbar.min_delta[]
        Pbar.frequency!(Pbar.Millisecond(100))
        @test Pbar.min_delta[] == Pbar.Millisecond(100)
        Pbar.frequency!(old)  # restore
    end
end

end # module Runtests
