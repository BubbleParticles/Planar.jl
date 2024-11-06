module Template
using Vindicta

const DESCRIPTION = "Template"
const EXC = Symbol()
const MARGIN = NoMargin
const TF = tf"1m"

@strategyenv!
# @contractsenv!
# @optenv!

function call!(s::SC, ::ResetStrategy) end

function call!(_::SC, ::WarmupPeriod)
    Day(1)
end

function call!(s::SC, ts::DateTime, _)
    ats = available(s.timeframe, ts)
    foreach(s.universe) do ai
        nothing
    end
end

function call!(::Union{<:SC,Type{<:SC}}, ::StrategyMarkets)
    String[]
end

# function call!(t::Type{<:SC}, config, ::LoadStrategy)
# end

## Optimization
# function call!(s::S, ::OptSetup)
#     (;
#         ctx=Context(Sim(), tf"15m", dt"2020-", now()),
#         params=(),
#         # space=(kind=:MixedPrecisionRectSearchSpace, precision=Int[]),
#     )
# end
# function call!(s::S, params, ::OptRun) end

# function call!(s::S, ::OptScore)::Vector
#     [mt.sharpe(s)]
# end

end
