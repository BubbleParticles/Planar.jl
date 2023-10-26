# This imports are for optimizing loading time
using Reexport
@reexport using Zarr
using Misc: Misc, DATA_PATH, isdirempty, Lang, TimeTicks
using DataFramesMeta

include("utils.jl")
include("dictview.jl")
include("load.jl")
include("dataframes.jl")
include("series.jl")
include("cache.jl")

_doinit() = begin
    Base.empty!(zcache)
    zi[] = ZarrInstance()
end
