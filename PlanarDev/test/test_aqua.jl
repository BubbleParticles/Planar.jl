using Test

include("../../resolve.jl")
function run_aqua_test(test_func; skip=[:StrategyStats, :Cli, :zarr, :test, :PlanarDev, :Plotting, :PlanarInteractive, :Temporal, :Scrapers, :Query], skip2=[])
    prev = Base.active_project()
    append!(skip, skip2)
    try
        recurse_projects((path, fullpath; kwargs...) -> begin
            projpath = path
            # Activate the project's environment and read its declared name
            Pkg.activate(projpath, io=devnull)
            pname = Pkg.project().name
            if isnothing(pname)
                return
            end
            id = Symbol(pname)
            id in skip && return
            @eval using $(id)
            try
                @eval using Aqua
            catch
                # Aqua may not be available in some environments; skip test if so
                return
            end
            @eval $(test_func)($(id))
        end, io=devnull)
    finally
        Pkg.activate(prev, io=devnull)
    end
end

test_aqua() = @testset "aqua" begin
    # By default only run the dependency check (quick). To run the full Aqua test
    # suite set the environment variable PLANAR_RUN_FULL_AQUA_TESTS=1.
    run_aqua_test(Aqua.test_stale_deps, skip2=[:Data])
    if get(ENV, "PLANAR_RUN_FULL_AQUA_TESTS", "0") == "1"
        run_aqua_test(Aqua.test_unbound_args)
        run_aqua_test(Aqua.test_undefined_exports)
    else
        @info "Skipping full Aqua tests; set PLANAR_RUN_FULL_AQUA_TESTS=1 to enable."
    end
end
