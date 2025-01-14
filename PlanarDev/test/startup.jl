using Revise

using Planar: @in_repl

# import Pkg; Pkg.activate("test/")
# using BenchmarkTools

exc, zi = @in_repl()
Revise.revise(Planar)

using Fetch
Planar.fetch_ohlcv(Val(:ask), exc, "4h"; qc="USDT", zi, update=true)
