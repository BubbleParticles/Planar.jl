# Test the ccxt-gateway venv sync used during PlanarCore precompilation
# (_sync_gateway_venv: runs `uv sync` in the ccxt-gateway project dir so the
# venv matches uv.lock, falling back to _ensure_gateway_venv).
# Run with: julia --project=PlanarCore -e 'using Pkg; Pkg.test()'

using Test
using HTTP
using JSON3

include("../../src/Ccxt/CcxtGateway/types.jl")
using .Types
include("../../src/Ccxt/CcxtGateway/rest.jl")
using .Rest

@testset "venv sync" begin
    if Sys.which("uv") !== nothing
        gwdir = try
            dirname(Rest._find_gateway_file("daemon_gateway.py"))
        catch
            nothing
        end
        if gwdir !== nothing
            py = Rest._sync_gateway_venv(gwdir)
            @test isfile(py)
            @test Rest._check_python_works(py)
        else
            @info "ccxt-gateway dir not found; skipping venv sync test"
        end
    else
        @info "uv not on PATH; skipping venv sync test"
    end
end

println("Venv sync tests passed!")
