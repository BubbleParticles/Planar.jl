import .egn: ExecAction, call!
using .egn: WarmupPeriod
using .egn: issandbox

struct SimWarmup <: ExecAction end
struct InitSimWarmup <: ExecAction end

@doc """
Initializes warmup attributes for a strategy.

$(TYPEDSIGNATURES)
"""
function call!(
    s::Strategy,
    ::InitSimWarmup;
    timeout=Minute(15),
    warmup_period=attr!(s, :warmup_period, Day(1)),
)
    attrs = s.attrs
    attrs[:warmup_lock] = ReentrantLock()
    attrs[:warmup_timeout] = timeout
    attrs[:warmup_running] = false
    # If this strategy instance is itself the temporary warmup simulator,
    # don't trigger nested warmups. Mark as warm and skip.
    if get(attrs, :is_warmup_sim, false)
        attrs[:warmup] = Dict(ai => true for ai in s.universe)
        attrs[:warmup_candles] = 0
        return nothing
    end
    attrs[:warmup] = Dict(ai => false for ai in s.universe)
    attrs[:warmup_candles] = max(100, count(s.timeframe, TimeFrame(warmup_period)))
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
    # Build a dedicated sim strategy and flag it as a warmup simulator
    s_sim = @lget! s.attrs :simstrat strategy(nameof(s), mode=Sim(), sandbox=issandbox(s))
    s_sim[:is_warmup_sim] = true
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

@doc """
Initiates the warmup process for all assets in the universe for a simulation strategy.

$(TYPEDSIGNATURES)

Runs warmup simulation on all assets in the strategy's universe simultaneously.
"""
function call!(
    cb::Function, s::SimStrategy, ::SimWarmup; n_candles=s.warmup_candles
)
    if !s.warmup_running && any(!warmed for warmed in values(s.warmup))
        _warmup!(cb, s; n_candles)
    end
end

@doc """
Initiates the warmup process for all assets in the universe for a real-time strategy.

$(TYPEDSIGNATURES)

Runs warmup simulation on all assets in the strategy's universe simultaneously.
"""
function call!(
    cb::Function,
    s::RTStrategy,
    ats::DateTime,
    ::SimWarmup;
    n_candles=s.warmup_candles,
)
    # give up on warmup after `warmup_timeout`
    if now() - s.is_start < s.warmup_timeout
        if any(!warmed for warmed in values(s[:warmup]))
            warmup_lock = @lock s @lget! s.attrs :warmup_lock ReentrantLock()
            @lock warmup_lock _warmup!(cb, s, ats; n_candles)
        end
    end
end

@doc """
Executes the warmup routine for all assets in the universe with a custom callback.

$(TYPEDSIGNATURES)

The function prepares the trading strategy by simulating past data for all assets 
in the universe before live execution starts.
"""
function _warmup!(
    callback::Function,
    s::Strategy,
    ats::DateTime;
    n_candles=s.warmup_candles,
)
    # wait until ohlcv data is available for all assets
    @debug "warmup: checking ohlcv data for all assets"
    since = ats - min(call!(s, WarmupPeriod()), (s.timeframe * n_candles).period)
    
    # Check data availability for all assets
    for ai in s.universe
        for ohlcv in values(ohlcv_dict(ai))
            if dateindex(ohlcv, since) < 1
                @debug "warmup: no data for asset" ai = raw(ai) ats
                return nothing
            end
        end
    end
    
    # Build a dedicated sim strategy and flag it as a warmup simulator
    s_sim = @lget! s.attrs :simstrat strategy(nameof(s), mode=Sim(), sandbox=issandbox(s))
    s_sim[:is_warmup_sim] = true
    
    # Copy OHLCV data for all assets
    for ai in s.universe
        ai_dict = @lget! s.attrs :siminstances Dict(raw(ai) => ai for ai in s_sim.universe)
        ai_sim = ai_dict[raw(ai)]
        copyohlcv!(ai_sim, ai)
    end
    
    # run sim on full universe
    @debug "warmup: running sim on all assets"
    ctx = Context(Sim(), s.timeframe, since, since + s.timeframe * n_candles)
    reset!(s_sim)
    s_sim[:warmup_running] = true
    start!(s_sim, ctx; doreset=false)
    
    # callback with full strategy instances
    callback(s, s_sim)
    @debug "warmup: completed for all assets"
end

@doc """
Executes the warmup routine for all assets in a simulation strategy.

$(TYPEDSIGNATURES)

Simplified version for simulation strategies that don't need timestamp parameter.
"""
function _warmup!(
    callback::Function,
    s::SimStrategy;
    n_candles=s.warmup_candles,
)
    # For sim strategies, we can use the strategy's current context timestamp
    # or derive a reasonable warmup period
    warmup_period = min(call!(s, WarmupPeriod()), (s.timeframe * n_candles).period)
    
    # Build a dedicated sim strategy and flag it as a warmup simulator
    s_sim = @lget! s.attrs :simstrat strategy(nameof(s), mode=Sim(), sandbox=issandbox(s))
    s_sim[:is_warmup_sim] = true
    
    # Copy OHLCV data for all assets
    for ai in s.universe
        ai_dict = @lget! s.attrs :siminstances Dict(raw(ai) => ai for ai in s_sim.universe)
        ai_sim = ai_dict[raw(ai)]
        copyohlcv!(ai_sim, ai)
    end
    
    # Determine warmup time range - use current strategy context or reasonable default
    end_time = get(s.attrs, :current_time, now())
    since = end_time - warmup_period
    
    @debug "warmup: running sim on all assets" since end_time
    ctx = Context(Sim(), s.timeframe, since, end_time)
    reset!(s_sim)
    s_sim[:warmup_running] = true
    start!(s_sim, ctx; doreset=false)
    
    # callback with full strategy instances
    callback(s, s_sim)
    @debug "warmup: completed for all assets"
end

export SimWarmup, InitSimWarmup
