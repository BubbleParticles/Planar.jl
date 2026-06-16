EXCHANGE = Symbol(get!(ENV, "PLANAR_TEST_EXCHANGE", :binance))
EXCHANGE_MM = Symbol(@something get(ENV, "PLANAR_TEST_EXCHANGE_MM", nothing) :binanceusdm)
# Use stub ccxt by default for tests
ENV["PLANAR_USE_STUB_CCXT"] = get(ENV, "PLANAR_USE_STUB_CCXT", "1")
# Skip external API tests when using stub (they fail without real API keys)
using_stub() = get(ENV, "PLANAR_USE_STUB_CCXT", "") == "1"
skip_external_tests() = using_stub()
# Skip heavy precomp during tests
ENV["JULIA_PRECOMP"] = ""
# Tests rely on output consistency
ENV["JULIA_DEBUG"] = ""
# Disable TMP project path
NO_TMP = "JULIA_NO_TMP" ∈ keys(ENV)
if NO_TMP
    using Pkg: Pkg
    # activate main project
    root = "."
    if isnothing(Pkg.project().name) && ispath(joinpath(dirname(pwd()), "Project.toml"))
        root = ".."
    end
    Pkg.activate(root)
    @assert Pkg.project().name == "PlanarDev"
    if ispath(joinpath(root, ".CondaPkg", "env"))
        ENV["JULIA_CONDAPKG_OFFLINE"] = "yes"
    end
end

using PlanarDev

PROJECT_PATH = pathof(PlanarDev) |> dirname |> dirname
push!(LOAD_PATH, dirname(PROJECT_PATH))
FAILFAST = true # parse(Bool, get(ENV, "FAILFAST", "0"))

const _INCLUDED_TEST_FILES = Set{String}()
