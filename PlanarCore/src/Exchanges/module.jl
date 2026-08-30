include("utils.jl")
include("constructors.jl")
include("currency.jl")
include("tickers.jl")
include("data.jl")
include("accounts.jl")
include("adhoc/utils.jl")
include("leverage.jl")
include("trades.jl")
include("adhoc/leverage.jl")
include("adhoc/constructors.jl")
include("adhoc/tickers.jl")
export @exchange!, setexchange!, getexchange!, exckeys!
export loadmarkets!, tickers, pairs
export issandbox, ratelimit!, isratelimited, ispercentage
export timestamp, timeout!, check_timeout
export ticker!, lastprice
export leverage!, marginmode!, check_margin_support!
export islist, isdict

using Reexport
@reexport using ..ExchangeTypes

if occursin("Exchanges", get(ENV, "JULIA_PRECOMP", ""))
    include("precompile.jl")
end
