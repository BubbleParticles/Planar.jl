using Lang: @preset, @precomp
@preset begin
    funcs = [*, +, -, *, ÷]
    funcs2 = [sub!, add!, cash!, mul!, div!, rdiv!]
    @precomp begin
        a = parse(Asset, "BTC/USDT")
        a.bc
        a.qc
        parse(Derivatives.Derivative, "BTC/USDT")
        parse(AbstractAsset, "BTC/USDT")
        isfiatpair("BTC/USDT")
        ca = cash!(c"USDT", 1000.0)
        for f in funcs
            f(ca, 1)
            f(ca, 1.0)
        end
        for f in funcs2
            f(ca, 1)
            f(ca, 1.0)
        end
    end
end
