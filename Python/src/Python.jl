@doc """
Defines the Python module which sets up the Python interpreter and imports
required modules and constants.
"""
module Python

using PrecompileTools: @compile_workload
using DocStringExtensions

include("consts.jl")
include("module.jl")
__init__() = _doinit()
@compile_workload include("precompile.jl")
_setup!()

end
