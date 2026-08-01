using ..Lang: @preset, @precomp
@preset begin
    funcs = [*, +, -, *, ÷]
    funcs2 = [sub!, add!, cash!, mul!, div!, rdiv!]
    @precomp begin
        a = parse(Asset, first(DEFAULT_ASSETS))
        a.bc
        a.qc
        parse(Derivatives.Derivative, first(DEFAULT_ASSETS))
        parse(AbstractAsset, first(DEFAULT_ASSETS))
        isfiatpair(first(DEFAULT_ASSETS))
        ca = cash!(c(string(QUOTE_CURRENCY)), 1000.0)
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
