module Exchanges

include("module.jl")
__init__() = _doinit()
if occursin(string(@__MODULE__), get(ENV, "JULIA_PRECOMP", ""))
    include("precompile.jl")
end

end # module Exchanges
