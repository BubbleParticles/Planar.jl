using Strategies

@eval Strategies begin
    s = strategy(:BareStrat; exchange=:phemex)
    assets(s)
    instances(s)
    exchangeid(typeof(s))
    freecash(s)
    execmode(s)
    nameof(s)
    nameof(typeof(s))
    reset!(s)
    propertynames(s)
    attrs(s)
    s.attrs
    coll.iscashable(s)
    minmax_holdings(s)
    trades_count(s)
    orders(s, Buy)
    orders(s, Sell)
    io = IOBuffer()
    show(io, s)
    close(io)
    ExchangeTypes._closeall()
end
