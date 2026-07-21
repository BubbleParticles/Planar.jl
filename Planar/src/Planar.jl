module Planar

include(joinpath(@__DIR__, "module.jl"))
__init__() = _doinit()
include(joinpath(@__DIR__, "precompile.jl"))

end # module Planar
