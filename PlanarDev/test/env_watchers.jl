using Planar
using Instruments.Derivatives
using .Planar.Watchers: Watchers as wc
using .Planar.Data
using TimeTicks
const da = Data
const cg = Planar.Watchers.CoinGecko
const cp = Planar.Watchers.CoinPaprika
const excs = collect(keys(cg.loadderivatives!()))
const wi = Planar.Watchers.WatchersImpls
const pro = wi.Processing
setexchange!(:kucoin)
macro usdt_str(sym)
    s = uppercase(sym) * "/USDT:USDT"
    :($s)
end
usdm(sym) = "$(uppercase(sym))/USDT:USDT"
