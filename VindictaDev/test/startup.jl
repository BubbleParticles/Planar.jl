using Revise

using Vindicta: @in_repl

# import Pkg; Pkg.activate("test/")
# using BenchmarkTools

exc, zi = @in_repl()
Revise.revise(Vindicta)

using Fetch
Vindicta.fetch_ohlcv(Val(:ask), exc, "4h"; qc="USDT", zi, update=true)
