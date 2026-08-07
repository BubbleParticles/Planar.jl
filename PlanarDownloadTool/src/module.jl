using PlanarCore.Processing: TradesOHLCV as tra, cleanup_ohlcv_data, trail!
using PlanarCore.Processing: Processing, Pbar, Data
using CSV
using PlanarCore.Instruments
using ZipFile: ZipFile as zip
using HTTP
using PlanarCore.Data: zi, zinstance
using PlanarCore.Misc
using CodecZlib: CodecZlib as zlib

using PlanarCore.TimeTicks
using PlanarCore.Lang
using PlanarCore.Lang: @ifdebug, @acquire, splitkws
using PlanarCore.Misc: LittleDict
using PlanarCore.Misc.DocStringExtensions
using PlanarCore.Data.Cache: Cache as ca
using PlanarCore.Data.DFUtils: lastdate, firstdate
using PlanarCore.Data.DataFrames
using PlanarCore.Pbar

@doc "Controls the number of workers used by the PlanarDownloadTool module to download chunks (1 chunk == 1 request).
See also [`SEM`](@ref)
"
const WORKERS = Ref(4)
@doc "The time frame used by the PlanarDownloadTool module."
const TF = Ref(tf"1m")
@doc "A samaphore for parallel downloads. Controls how many symbols are downloaded in parallel.
When downloading archives from scratch use more [`WORKERS`](@ref) and smaller `sem_size`, when updating use larer `sem_size` and fewer workers.
"
const SEM = Base.Semaphore(3)

@doc "Default HTTP parameters used by the PlanarDownloadTool module."
const DEFAULT_HTTP_PARAMS = (; connect_timeout=30)
@doc "Active HTTP parameters used by the PlanarDownloadTool module."
const HTTP_PARAMS = LittleDict{Symbol, Any}(:connect_timeout => 30)

function _doinit()
    zi[] = zinstance()
    _load_dbnomics!()
end

include("utils.jl")
include("bybit.jl")
include("binance.jl")

"""
    _load_dbnomics!()

Load the vendored DBnomics package (optional) and define the `DBNomicsData`
module. Called from `__init__` at runtime, NOT at module top level: the vendored
package is not a declared dependency (it is not resolvable via Pkg — its compat
bounds cap DataFrames at 1.2, JSON at 0.21, older than the repo's versions), so
`using DBnomics` must not run from inside the package module's namespace — Julia
rejects it with "Package PlanarDownloadTool does not have DBnomics in its
dependencies", both during precompilation and at runtime. Instead, load DBnomics
into an anonymous module (no package namespace, no deps check) and bind the
resulting module as `PlanarDownloadTool.DBnomics`; the `using DBnomics` inside
`DBNomicsData` then resolves to the parent binding without a new `require`.
"""
function _load_dbnomics!()
    dbnomics_path = joinpath(@__DIR__, "..", "vendor", "DBnomics.jl")
    if isdir(dbnomics_path)
        pushfirst!(LOAD_PATH, dbnomics_path)
        Base.LOADING_CACHE[] = nothing  # force load_path() to re-expand LOAD_PATH
        try
            loader = Module()
            Base.eval(loader, :(import DBnomics))
            dbnomics = Base.invokelatest(getfield, loader, :DBnomics)
            @eval const DBnomics = $dbnomics
            include(joinpath(@__DIR__, "DBNomics.jl"))
        catch e
            @warn "DBnomics not available - DBNomicsData module disabled: $(sprint(showerror, e))"
        finally
            filter!(p -> p != dbnomics_path, LOAD_PATH)
        end
    else
        @warn "Vendored DBnomics not found at $dbnomics_path - DBNomicsData module disabled"
    end
end
