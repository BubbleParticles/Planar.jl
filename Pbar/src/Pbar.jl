@doc "Progress bar wrapper."
module Pbar

    include("module.jl")
    __init__() = _doinit()
    include("precompile.jl")

end
