import .egn: ExecAction, call!
using .egn: WarmupPeriod
using .egn: issandbox

struct SimWarmup <: ExecAction end
struct InitSimWarmup <: ExecAction end

@doc """
Initializes warmup attributes for a strategy.

$(TYPEDSIGNATURES)
"""
function call!(s::Strategy, ::InitSimWarmup; timeout=Minute(15), n_candles=999)
    attrs = s.attrs
    attrs[:warmup] = Dict(ai => false for ai in s.universe)
    attrs[:warmup_lock] = ReentrantLock()
    attrs[:warmup_timeout] = timeout
    attrs[:warmup_candles] = n_candles
    attrs[:warmup_running] = false
end

function call!(
    cb::Function, s::SimStrategy, ai, ats, ::SimWarmup; n_candles=s.warmup_candles
)
    if !s.warmup[ai] && !s.warmup_running
        _warmup!(cb, s, ai, ats; n_candles)
    end
end

@doc """
Initiates the warmup process for a real-time strategy instance.

$(TYPEDSIGNATURES)

If warmup has not been previously completed for the given asset instance, it performs the necessary preparations.
"""
function call!(
    cb::Function,
    s::RTStrategy,
    ai::AssetInstance,
    ats::DateTime,
    ::SimWarmup;
    n_candles=s.warmup_candles,
)
    # give up on warmup after `warmup_timeout`
    if now() - s.is_start < s.warmup_timeout
        if !s[:warmup][ai]
            warmup_lock = @lock s @lget! s.attrs :warmup_lock ReentrantLock()
            @lock warmup_lock _warmup!(cb, s, ai, ats; n_candles)
        end
    end
end

@doc """
Executes the warmup routine with a custom callback for a strategy.

$(TYPEDSIGNATURES)

The function prepares the trading strategy by simulating past data before live execution starts.
"""
function _warmup!(
    callback::Function,
    s::Strategy,
    ai::AssetInstance,
    ats::DateTime;
    n_candles=s.warmup_candles,
)
    # wait until ohlcv data is available
    @debug "warmup: checking ohlcv data"
    since = ats - min(call!(s, WarmupPeriod()), (s.timeframe * n_candles).period)
    for ohlcv in values(ohlcv_dict(ai))
        if dateindex(ohlcv, since) < 1
            @debug "warmup: no data" ai = raw(ai) ats
            return nothing
        end
    end
    s_sim = @lget! s.attrs :simstrat strategy(nameof(s), mode=Sim(), sandbox=issandbox(s))
    ai_dict = @lget! s.attrs :siminstances Dict(raw(ai) => ai for ai in s_sim.universe)
    ai_sim = ai_dict[raw(ai)]
    copyohlcv!(ai_sim, ai)
    uni_df = s_sim.universe.data
    empty!(uni_df)
    push!(uni_df, (exchangeid(ai_sim)(), ai_sim.asset, ai_sim))
    @assert nrow(s_sim.universe.data) == 1
    # run sim
    @debug "warmup: running sim"
    ctx = Context(Sim(), s.timeframe, since, since + s.timeframe * n_candles)
    reset!(s_sim)
    s_sim[:warmup_running] = true
    start!(s_sim, ctx; doreset=false)
    # callback
    callback(s, ai, s_sim, ai_sim)
    @debug "warmup: completed" ai = raw(ai)
end

export SimWarmup, InitSimWarmup
