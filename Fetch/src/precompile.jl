using .Misc.Lang: PrecompileTools, @preset, @precomp

@preset let
    pair = "BTC/USDT"
    using .Data: zinstance
    using Exchanges.ExchangeTypes: _closeall
    tmp_zi = zinstance(mktempdir())
    try
        e = getexchange!(:okx)
        @precomp begin
            fetch_ohlcv(e, "1d", [pair]; zi=tmp_zi, from=-100, to=-10)
            fetch_candles(e, "1d", [pair]; from=-100, to=-10)
        end
        _closeall()
    catch e
        @debug "Fetch precompile workload skipped: $e"
    finally
        if hasproperty(tmp_zi.store, :a)
            rm(tmp_zi.store.a)
        end
    end
end
