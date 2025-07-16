# Dispatching for OnlineTechnicalIndicators functions

@doc "Return the inputs for the `fit!` function of the signal."
function stt.indicator_range(
    sig::Union{oti.ChandeKrollStop,oti.VTX,oti.UO,oti.ATR,oti.SOBV}, data, range
)
    ts = data.timestamp
    o = data.open
    h = data.high
    l = data.low
    c = data.close
    v = data.volume
    (Candle(ts[idx], o[idx], h[idx], l[idx], c[idx], v[idx]) for idx in range)
end

Base.ismissing(val::oti.StochRSIVal{Missing}) = true
Base.ismissing(val::oti.StochRSIVal) = ismissing(val.d) || ismissing(val.k)
stt.signal_value(::oti.StochRSI; sig) = begin
    sig.state.value.d
end
function stt.cmptrend(::oti.StochRSI; sig, ov, idx)
    val = sig.state.value
    if iszero(idx) || ismissing(sig.state.value.d)
        sig.trend = stt.MissingTrend
        false
    else
        sig.trend = if val.d < 50
            stt.Up
        elseif 30 < val.d < 90
            stt.Stationary
        else
            stt.Down
        end
        true
    end
end

function stt.cmptrend(::oti.VTX; sig, ov, idx)
    stt.cmpab(sig, :plus_vtx, :minus_vtx)
end

function stt.indicator_scalar(val::oti.VTXVal)
    val.plus_vtx
end
