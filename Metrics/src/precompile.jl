using ect.Lang: PrecompileTools, @preset, @precomp, @ignore

# FIXME: This precompilation bloats the module
# maybe we should just input the precompile statements here.
@preset let
    using Stubs
    # FIXME: see Stubs pkg precomp fixme
    s = try
        Stubs.stub_strategy(dostub=false)
    catch e
        @warn "precomp: could not load stub strategy (gateway unavailable): $e"
        nothing
    end
    if !isnothing(s)
        ai = first(s.universe)
        @precomp @ignore begin
            resample_trades(ai, tf"1d")
            resample_trades(s, tf"1d")
            trades_balance(ai; tf=tf"1d")
            trades_balance(s; tf=tf"1d")
        end
    end
end
