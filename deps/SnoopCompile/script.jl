using Pkg

let lpath = joinpath(dirname(Pkg.project().path), "test")
    lpath ∉ LOAD_PATH && push!(LOAD_PATH, lpath)
end

using Planar
using Planar.Exchanges: fetch!

fetch!() # load fetch_ohlcv func
Planar.setexchange!(:kucoin)
Planar.load_ohlcv("15m")
# User.fetch_ohlcv("1h", ["BTC/USDT", "ETH/USDT"]; update=true)
# User.fetch_ohlcv("1d", "BTC/USDT")
