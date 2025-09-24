using Test
using PlanarDev.Planar.Watchers
using PlanarDev.Planar.Watchers.DBNomics
using PlanarDev.Planar.Scrapers.DBNomicsData
using Dates
using DataFrames
using DBnomics

include("common.jl")

function test_dbnomics_watcher()
    @eval begin
        using PlanarDev.Planar.Watchers.DBNomics
        using Base.Experimental: @overlay
        PlanarDev.@environment!
    end

    @testset "DBNomics Watcher" begin
        # Mock the DBnomics.rdb function
        mock_called = Ref(false)
        patch = @expr function DBnomics.rdb(ids; kwargs...)
            mock_called[] = true
            return DataFrame(period=["2023-01-01"], value=[1.0])
        end

        @pass [patch] begin
            # Create a watcher
            ids = ["id1"]
            w = DBNomics.watcher(ids; fetch_interval=Second(1))

            # Test that the watcher is created correctly
            @test w.name == "dbnomics"
            @test w.attrs[:ids] == ids

            # Test that fetch works
            Watchers._tryfetch(w)
            @test mock_called[] == true

            # Test that the watcher is stopped correctly
            stop!(w)
            @test isstopped(w)
        end
    end
end
