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
const DEFAULT_HTTP_PARAMS = (;
    connect_timeout = 30,
    read_timeout = 60,
    retry = false,  # we handle retries manually with backoff
)
@doc "Active HTTP parameters used by the PlanarDownloadTool module."
const HTTP_PARAMS = LittleDict{Symbol, Any}(
    :connect_timeout => 30,
    :read_timeout => 60,
    :retry => false,
)

function _doinit()
    zi[] = zinstance()
end

include("utils.jl")
include("bybit.jl")
include("binance.jl")
