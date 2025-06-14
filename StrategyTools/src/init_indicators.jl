# init_indicators.jl

import OnlineTechnicalIndicators as oti
# Assuming oneAPI might be available in Main, and is_oneapi_functional is accessible
# (e.g. through using StrategyTools if this file is part of it, or direct definition/import)
# For this file, we'll rely on is_oneapi_functional being available from gpu_indicators.jl
# which should be part of the same parent module StrategyTools.

"""
    _convert_indicator_buffers_to_oneArray!(indicator_obj, oneAPI_module)

Recursively attempts to find `input_values.buffer` in an indicator object
and its sub-indicator objects (common for indicators like RSI that use internal EMAs)
and converts them to oneAPI.oneArray.
"""
function _convert_indicator_buffers_to_oneArray!(indicator_obj, oneAPI_module)
    # Check current object's buffer
    if hasproperty(indicator_obj, :input_values) &&
       hasproperty(indicator_obj.input_values, :buffer) &&
       !isa(indicator_obj.input_values.buffer, oneAPI_module.oneArray)
        try
            indicator_obj.input_values.buffer = oneAPI_module.oneArray(indicator_obj.input_values.buffer)
        catch e
            @warn "Failed to convert buffer for $(typeof(indicator_obj)) to oneArray: $e"
        end
    end

    # Recursively check for sub-indicators (common for complex indicators like RSI)
    # This is a heuristic based on common OTI patterns (e.g., RSI having avg_gain, avg_loss EMAs)
    for prop_name in propertynames(indicator_obj)
        if prop_name == :input_values || prop_name == :value # Avoid infinite recursion on buffers themselves
            continue
        end
        prop_val = getproperty(indicator_obj, prop_name)
        if isa(prop_val, oti.OnlineIndicator)
            _convert_indicator_buffers_to_oneArray!(prop_val, oneAPI_module) # Recursive call
        elseif isa(prop_val, Tuple) || isa(prop_val, NamedTuple) # Check for collections of indicators
            for item in prop_val
                if isa(item, oti.OnlineIndicator)
                    _convert_indicator_buffers_to_oneArray!(item, oneAPI_module)
                end
            end
        end
        # Add more specific checks here if certain indicators store sub-indicators in specific ways,
        # e.g. `if typeof(indicator_obj) == oti.RSI && (prop_name == :avg_gain || prop_name == :avg_loss)`
    end
end


"""
    initema!(strategy, universe=strategy.universe; period=10, name=:ema, default_type=Float64)

Initializes EMA indicators for each asset in the universe and stores them in `strategy.attrs[name]`.
If oneAPI is functional, attempts to convert internal buffers of the EMA objects to `oneAPI.oneArray`.
"""
function initema!(s, uni=s.universe; period=10, name=:ema, default_type=Float64)
    # Ensure `is_oneapi_functional` is available, typically from the parent module StrategyTools scope
    # which includes gpu_indicators.jl

    ema_dict = LittleDict{eltype(uni), oti.EMA{default_type, default_type}}()
    oneAPI_module = is_oneapi_functional() ? getfield(Main, :oneAPI) : nothing

    for ai in uni
        ema_obj = oti.EMA{default_type}(period=period)

        if oneAPI_module !== nothing
            # Attempt to convert buffer(s) to oneArray
            # For EMA, input_values.buffer is the primary target.
            _convert_indicator_buffers_to_oneArray!(ema_obj, oneAPI_module)
        end
        ema_dict[ai] = ema_obj
    end
    s.attrs[name] = ema_dict
    return s.attrs[name]
end

"""
    initrsi!(strategy, universe=strategy.universe; period=14, name=:rsi, default_type=Float64)

Initializes RSI indicators for each asset in the universe and stores them in `strategy.attrs[name]`.
If oneAPI is functional, attempts to convert internal buffers of the RSI objects (and their
internal EMA-like components for average gain/loss) to `oneAPI.oneArray`.
"""
function initrsi!(s, uni=s.universe; period=14, name=:rsi, default_type=Float64)
    # Ensure `is_oneapi_functional` is available

    rsi_dict = LittleDict{eltype(uni), oti.RSI{default_type, default_type}}()
    oneAPI_module = is_oneapi_functional() ? getfield(Main, :oneAPI) : nothing

    for ai in uni
        rsi_obj = oti.RSI{default_type}(period=period)

        if oneAPI_module !== nothing
            # RSI has internal EMAs for average gain and loss.
            # _convert_indicator_buffers_to_oneArray! will attempt to recursively convert them.
            _convert_indicator_buffers_to_oneArray!(rsi_obj, oneAPI_module)
        end
        rsi_dict[ai] = rsi_obj
    end
    s.attrs[name] = rsi_dict
    return s.attrs[name]
end

export initema!, initrsi!
