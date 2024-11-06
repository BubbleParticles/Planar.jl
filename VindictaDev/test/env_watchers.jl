using Vindicta
using Instruments.Derivatives
using .Vindicta.Watchers: Watchers as wc
using .Vindicta.Data
using TimeTicks
const da = Data
const cg = Vindicta.Watchers.CoinGecko
const cp = Vindicta.Watchers.CoinPaprika
const excs = collect(keys(cg.loadderivatives!()))
const wi = Vindicta.Watchers.WatchersImpls
const pro = wi.Processing
setexchange!(:kucoin)
macro usdt_str(sym)
    s = uppercase(sym) * "/USDT:USDT"
    :($s)
end
usdm(sym) = "$(uppercase(sym))/USDT:USDT"
