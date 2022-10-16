module Backtest

include("misc/utils.jl"); using .Misc
include("exchanges/exchanges.jl"); using .Exchanges
include("data/data.jl"); using .Data

# load fetch functions, that depend on `.Data`...circ deps...
Exchanges.fetch!()

# include("exchanges/feed.jl")

include("analysis/analysis.jl")
include("plotting/plotting.jl")

using .Analysis
using .Plotting
include("repl.jl")

export get_pairlist, load_pairs, Exchange, explore!, user!

"SNOOP_COMPILER" ∉ keys(ENV) && include("$(@__FILE__)/../../deps/precompiles/precompile_$(@__MODULE__).jl")

end # module
