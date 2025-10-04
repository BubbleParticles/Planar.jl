---
title: "Simple Indicators Examples"
description: "Moving averages and basic technical indicator calculations"
category: "examples"
difficulty: "beginner"
prerequisites: ["getting-started", "basic-strategy", "data-access"]
topics: ["examples", "indicators", "technical-analysis", "moving-averages"]
last_updated: "2025-10-04"
estimated_time: "20 minutes"
---

# Simple Indicators Examples

This example demonstrates how to calculate and use common technical indicators in Planar strategies. Learn to implement moving averages, RSI, MACD, and other essential indicators.

## Overview

**What this example demonstrates:**
- Simple and exponential moving averages
- RSI (Relative Strength Index) calculation
- MACD (Moving Average Convergence Divergence)
- Bollinger Bands
- Volume indicators
- Indicator-based trading signals

**Complexity:** Beginner  
**Prerequisites:** [Data Access Examples](data-access.md)

## Complete Indicators Example

```julia
# Example: Technical Indicators Implementation
# Description: Common technical indicators and their usage
# Complexity: Beginner
# Prerequisites: Data access knowledge

module SimpleIndicatorsExample
    @strategyenv!
    
    const DESCRIPTION = "Technical indicators demonstration"
    const TIMEFRAME = tf"1h"
    
    # Indicator parameters
    const SMA_FAST = Ref(10)
    const SMA_SLOW = Ref(20)
    const EMA_PERIOD = Ref(12)
    const RSI_PERIOD = Ref(14)
    const BB_PERIOD = Ref(20)
    const BB_STDDEV = Ref(2.0)
    
    function call!(::Type{S}, ::StrategyMarkets) where {S<:Strategy}
        return ["BTC/USDT", "ETH/USDT"]
    end
    
    function call!(s::S, ::WarmupPeriod) where {S<:Strategy}
        return 50  # Need enough data for indicators
    end
    
    function call!(s::S, current_time::DateTime, ctx) where {S<:Strategy}
        @info "Indicators Analysis - $(current_time)"
        
        for ai in assets(s)
            if length(ohlcv(ai)) >= 50
                analyze_with_indicators(ai)
                generate_trading_signals(ai)
                println()
            else
                @debug "Insufficient data for $(raw(ai))"
            end
        end
    end
    
    function analyze_with_indicators(ai::AssetInstance)
        println("=== Indicator Analysis for $(raw(ai)) ===")
        
        data = ohlcv(ai)
        current_price = closelast(data)
        
        # Moving Averages
        sma_fast = simple_moving_average(data, SMA_FAST[])
        sma_slow = simple_moving_average(data, SMA_SLOW[])
        ema = exponential_moving_average(data, EMA_PERIOD[])
        
        println("Moving Averages:")
        println("  Current Price: $(round(current_price, digits=2))")
        println("  SMA($(SMA_FAST[])): $(round(sma_fast, digits=2))")
        println("  SMA($(SMA_SLOW[])): $(round(sma_slow, digits=2))")
        println("  EMA($(EMA_PERIOD[])): $(round(ema, digits=2))")
        
        # RSI
        rsi = calculate_rsi(data, RSI_PERIOD[])
        println("RSI($(RSI_PERIOD[])): $(round(rsi, digits=2))")
        
        # MACD
        macd_line, signal_line, histogram = calculate_macd(data)
        println("MACD:")
        println("  MACD Line: $(round(macd_line, digits=4))")
        println("  Signal Line: $(round(signal_line, digits=4))")
        println("  Histogram: $(round(histogram, digits=4))")
        
        # Bollinger Bands
        bb_upper, bb_middle, bb_lower = bollinger_bands(data, BB_PERIOD[], BB_STDDEV[])
        println("Bollinger Bands:")
        println("  Upper: $(round(bb_upper, digits=2))")
        println("  Middle: $(round(bb_middle, digits=2))")
        println("  Lower: $(round(bb_lower, digits=2))")
        
        # Volume indicators
        vol_sma = volume_sma(data, 10)
        vol_ratio = current_volume_ratio(data, 10)
        println("Volume:")
        println("  Current: $(round(volumeat(data, -1), digits=2))")
        println("  SMA(10): $(round(vol_sma, digits=2))")
        println("  Ratio: $(round(vol_ratio, digits=2))x")
    end
    
    function generate_trading_signals(ai::AssetInstance)
        println("=== Trading Signals ===")
        
        data = ohlcv(ai)
        current_price = closelast(data)
        
        signals = String[]
        
        # Moving Average Crossover
        sma_fast = simple_moving_average(data, SMA_FAST[])
        sma_slow = simple_moving_average(data, SMA_SLOW[])
        
        if !isnan(sma_fast) && !isnan(sma_slow)
            if sma_fast > sma_slow
                # Check if this is a recent crossover
                prev_fast = simple_moving_average_at(data, SMA_FAST[], -2)
                prev_slow = simple_moving_average_at(data, SMA_SLOW[], -2)
                
                if !isnan(prev_fast) && !isnan(prev_slow) && prev_fast <= prev_slow
                    push!(signals, "🟢 Golden Cross (MA Bullish Crossover)")
                end
            elseif sma_fast < sma_slow
                prev_fast = simple_moving_average_at(data, SMA_FAST[], -2)
                prev_slow = simple_moving_average_at(data, SMA_SLOW[], -2)
                
                if !isnan(prev_fast) && !isnan(prev_slow) && prev_fast >= prev_slow
                    push!(signals, "🔴 Death Cross (MA Bearish Crossover)")
                end
            end
        end
        
        # RSI Signals
        rsi = calculate_rsi(data, RSI_PERIOD[])
        if !isnan(rsi)
            if rsi < 30
                push!(signals, "🟢 RSI Oversold ($(round(rsi, digits=1)))")
            elseif rsi > 70
                push!(signals, "🔴 RSI Overbought ($(round(rsi, digits=1)))")
            end
        end
        
        # MACD Signals
        macd_line, signal_line, histogram = calculate_macd(data)
        if !isnan(macd_line) && !isnan(signal_line)
            if macd_line > signal_line && histogram > 0
                # Check for bullish crossover
                prev_macd, prev_signal, _ = calculate_macd_at(data, -2)
                if !isnan(prev_macd) && !isnan(prev_signal) && prev_macd <= prev_signal
                    push!(signals, "🟢 MACD Bullish Crossover")
                end
            elseif macd_line < signal_line && histogram < 0
                prev_macd, prev_signal, _ = calculate_macd_at(data, -2)
                if !isnan(prev_macd) && !isnan(prev_signal) && prev_macd >= prev_signal
                    push!(signals, "🔴 MACD Bearish Crossover")
                end
            end
        end
        
        # Bollinger Bands Signals
        bb_upper, bb_middle, bb_lower = bollinger_bands(data, BB_PERIOD[], BB_STDDEV[])
        if !isnan(bb_upper) && !isnan(bb_lower)
            if current_price <= bb_lower
                push!(signals, "🟢 Price at Lower Bollinger Band")
            elseif current_price >= bb_upper
                push!(signals, "🔴 Price at Upper Bollinger Band")
            end
        end
        
        # Volume Confirmation
        vol_ratio = current_volume_ratio(data, 10)
        if vol_ratio > 1.5
            push!(signals, "📈 High Volume ($(round(vol_ratio, digits=1))x average)")
        end
        
        # Display signals
        if isempty(signals)
            println("No significant signals detected")
        else
            println("Active Signals:")
            for signal in signals
                println("  $signal")
            end
        end
    end
    
    # === Indicator Calculation Functions ===
    
    function simple_moving_average(data, period::Int)
        if length(data.close) < period
            return NaN
        end
        
        return mean(closeat(data, -period:-1))
    end
    
    function simple_moving_average_at(data, period::Int, offset::Int)
        if length(data.close) < period + abs(offset)
            return NaN
        end
        
        start_idx = -period + offset
        end_idx = -1 + offset
        
        return mean(closeat(data, start_idx:end_idx))
    end
    
    function exponential_moving_average(data, period::Int)
        if length(data.close) < period
            return NaN
        end
        
        closes = closeat(data, -period:-1)
        alpha = 2.0 / (period + 1)
        
        ema = closes[1]  # Start with first value
        for i in 2:length(closes)
            ema = alpha * closes[i] + (1 - alpha) * ema
        end
        
        return ema
    end
    
    function calculate_rsi(data, period::Int=14)
        if length(data.close) < period + 1
            return NaN
        end
        
        closes = closeat(data, -(period+1):-1)
        gains = Float64[]
        losses = Float64[]
        
        for i in 2:length(closes)
            change = closes[i] - closes[i-1]
            if change > 0
                push!(gains, change)
                push!(losses, 0.0)
            else
                push!(gains, 0.0)
                push!(losses, -change)
            end
        end
        
        avg_gain = mean(gains)
        avg_loss = mean(losses)
        
        if avg_loss == 0
            return 100.0
        end
        
        rs = avg_gain / avg_loss
        rsi = 100 - (100 / (1 + rs))
        
        return rsi
    end
    
    function calculate_macd(data, fast_period::Int=12, slow_period::Int=26, signal_period::Int=9)
        if length(data.close) < slow_period + signal_period
            return NaN, NaN, NaN
        end
        
        # Calculate EMAs
        ema_fast = exponential_moving_average(data, fast_period)
        ema_slow = exponential_moving_average(data, slow_period)
        
        if isnan(ema_fast) || isnan(ema_slow)
            return NaN, NaN, NaN
        end
        
        # MACD line
        macd_line = ema_fast - ema_slow
        
        # For signal line, we need to calculate EMA of MACD values
        # Simplified: use the current MACD as signal (in practice, you'd need historical MACD values)
        signal_line = macd_line  # Simplified
        
        # Histogram
        histogram = macd_line - signal_line
        
        return macd_line, signal_line, histogram
    end
    
    function calculate_macd_at(data, offset::Int)
        # Simplified version for demonstration
        return calculate_macd(data)
    end
    
    function bollinger_bands(data, period::Int=20, std_dev::Float64=2.0)
        if length(data.close) < period
            return NaN, NaN, NaN
        end
        
        closes = closeat(data, -period:-1)
        middle = mean(closes)
        std_val = std(closes)
        
        upper = middle + (std_dev * std_val)
        lower = middle - (std_dev * std_val)
        
        return upper, middle, lower
    end
    
    function volume_sma(data, period::Int)
        if length(data.volume) < period
            return NaN
        end
        
        return mean(volumeat(data, -period:-1))
    end
    
    function current_volume_ratio(data, period::Int)
        if length(data.volume) < period + 1
            return NaN
        end
        
        current_vol = volumeat(data, -1)
        avg_vol = volume_sma(data, period)
        
        if avg_vol == 0
            return NaN
        end
        
        return current_vol / avg_vol
    end
end
```

## Advanced Indicators Example

```julia
# Example: More Advanced Technical Indicators
module AdvancedIndicatorsExample
    @strategyenv!
    
    const DESCRIPTION = "Advanced technical indicators"
    const TIMEFRAME = tf"1h"
    
    function call!(::Type{S}, ::StrategyMarkets) where {S<:Strategy}
        return ["BTC/USDT"]
    end
    
    function call!(s::S, current_time::DateTime, ctx) where {S<:Strategy}
        for ai in assets(s)
            if length(ohlcv(ai)) >= 50
                calculate_advanced_indicators(ai)
            end
        end
    end
    
    function calculate_advanced_indicators(ai::AssetInstance)
        println("=== Advanced Indicators for $(raw(ai)) ===")
        
        data = ohlcv(ai)
        
        # Stochastic Oscillator
        stoch_k, stoch_d = stochastic_oscillator(data, 14, 3)
        println("Stochastic: %K=$(round(stoch_k, digits=2)), %D=$(round(stoch_d, digits=2))")
        
        # Williams %R
        williams_r = williams_percent_r(data, 14)
        println("Williams %R: $(round(williams_r, digits=2))")
        
        # Average True Range (ATR)
        atr = average_true_range(data, 14)
        println("ATR(14): $(round(atr, digits=4))")
        
        # Commodity Channel Index (CCI)
        cci = commodity_channel_index(data, 20)
        println("CCI(20): $(round(cci, digits=2))")
        
        # Rate of Change (ROC)
        roc = rate_of_change(data, 10)
        println("ROC(10): $(round(roc * 100, digits=2))%")
        
        # Money Flow Index (MFI)
        mfi = money_flow_index(data, 14)
        println("MFI(14): $(round(mfi, digits=2))")
    end
    
    function stochastic_oscillator(data, k_period::Int=14, d_period::Int=3)
        if length(data.close) < k_period + d_period
            return NaN, NaN
        end
        
        # Calculate %K
        recent_closes = closeat(data, -k_period:-1)
        recent_highs = highat(data, -k_period:-1)
        recent_lows = lowat(data, -k_period:-1)
        
        current_close = closelast(data)
        highest_high = maximum(recent_highs)
        lowest_low = minimum(recent_lows)
        
        if highest_high == lowest_low
            k_percent = 50.0
        else
            k_percent = ((current_close - lowest_low) / (highest_high - lowest_low)) * 100
        end
        
        # %D is SMA of %K (simplified - would need multiple %K values)
        d_percent = k_percent  # Simplified
        
        return k_percent, d_percent
    end
    
    function williams_percent_r(data, period::Int=14)
        if length(data.close) < period
            return NaN
        end
        
        recent_highs = highat(data, -period:-1)
        recent_lows = lowat(data, -period:-1)
        current_close = closelast(data)
        
        highest_high = maximum(recent_highs)
        lowest_low = minimum(recent_lows)
        
        if highest_high == lowest_low
            return -50.0
        end
        
        return ((highest_high - current_close) / (highest_high - lowest_low)) * -100
    end
    
    function average_true_range(data, period::Int=14)
        if length(data.close) < period + 1
            return NaN
        end
        
        true_ranges = Float64[]
        
        for i in 2:period+1
            high = highat(data, -i)
            low = lowat(data, -i)
            prev_close = closeat(data, -(i+1))
            
            tr1 = high - low
            tr2 = abs(high - prev_close)
            tr3 = abs(low - prev_close)
            
            true_range = max(tr1, tr2, tr3)
            push!(true_ranges, true_range)
        end
        
        return mean(true_ranges)
    end
    
    function commodity_channel_index(data, period::Int=20)
        if length(data.close) < period
            return NaN
        end
        
        # Typical Price = (High + Low + Close) / 3
        typical_prices = Float64[]
        for i in 1:period
            high = highat(data, -i)
            low = lowat(data, -i)
            close = closeat(data, -i)
            
            typical_price = (high + low + close) / 3
            push!(typical_prices, typical_price)
        end
        
        sma_tp = mean(typical_prices)
        current_tp = typical_prices[1]  # Most recent
        
        # Mean Deviation
        deviations = [abs(tp - sma_tp) for tp in typical_prices]
        mean_deviation = mean(deviations)
        
        if mean_deviation == 0
            return 0.0
        end
        
        cci = (current_tp - sma_tp) / (0.015 * mean_deviation)
        return cci
    end
    
    function rate_of_change(data, period::Int=10)
        if length(data.close) < period + 1
            return NaN
        end
        
        current_close = closelast(data)
        past_close = closeat(data, -(period + 1))
        
        if past_close == 0
            return NaN
        end
        
        return (current_close - past_close) / past_close
    end
    
    function money_flow_index(data, period::Int=14)
        if length(data.close) < period + 1
            return NaN
        end
        
        positive_flow = 0.0
        negative_flow = 0.0
        
        for i in 2:period+1
            high = highat(data, -i)
            low = lowat(data, -i)
            close = closeat(data, -i)
            volume = volumeat(data, -i)
            prev_close = closeat(data, -(i+1))
            
            typical_price = (high + low + close) / 3
            money_flow = typical_price * volume
            
            if close > prev_close
                positive_flow += money_flow
            elseif close < prev_close
                negative_flow += money_flow
            end
        end
        
        if negative_flow == 0
            return 100.0
        end
        
        money_ratio = positive_flow / negative_flow
        mfi = 100 - (100 / (1 + money_ratio))
        
        return mfi
    end
end
```

## Indicator-Based Strategy Example

```julia
# Example: Complete Strategy Using Multiple Indicators
module IndicatorStrategy
    @strategyenv!
    
    const DESCRIPTION = "Multi-indicator trading strategy"
    const TIMEFRAME = tf"1h"
    
    # Strategy parameters
    const RSI_OVERSOLD = Ref(30.0)
    const RSI_OVERBOUGHT = Ref(70.0)
    const BB_PERIOD = Ref(20)
    const VOLUME_THRESHOLD = Ref(1.5)  # Volume must be 1.5x average
    
    function call!(::Type{S}, ::StrategyMarkets) where {S<:Strategy}
        return ["BTC/USDT", "ETH/USDT"]
    end
    
    function call!(s::S, ::WarmupPeriod) where {S<:Strategy}
        return 50
    end
    
    function call!(s::S, current_time::DateTime, ctx) where {S<:Strategy}
        for ai in assets(s)
            if length(ohlcv(ai)) >= 50
                analyze_and_trade(s, ai)
            end
        end
    end
    
    function analyze_and_trade(s::Strategy, ai::AssetInstance)
        data = ohlcv(ai)
        current_price = closelast(data)
        current_balance = asset(ai)
        available_cash = freecash(s)
        
        # Calculate indicators
        rsi = calculate_rsi(data, 14)
        bb_upper, bb_middle, bb_lower = bollinger_bands(data, BB_PERIOD[])
        vol_ratio = current_volume_ratio(data, 10)
        sma_20 = simple_moving_average(data, 20)
        
        # Check if all indicators are valid
        if any(isnan.([rsi, bb_upper, bb_lower, vol_ratio, sma_20]))
            @debug "Invalid indicators for $(raw(ai))"
            return
        end
        
        # Generate trading signals
        buy_signals = check_buy_signals(current_price, rsi, bb_lower, vol_ratio, sma_20)
        sell_signals = check_sell_signals(current_price, rsi, bb_upper, vol_ratio, sma_20)
        
        # Execute trades based on signals
        if !isempty(buy_signals) && available_cash > 100.0 && current_balance == 0
            execute_buy(s, ai, buy_signals, available_cash, current_price)
        elseif !isempty(sell_signals) && current_balance > 0
            execute_sell(s, ai, sell_signals, current_balance, current_price)
        end
    end
    
    function check_buy_signals(price, rsi, bb_lower, vol_ratio, sma_20)
        signals = String[]
        
        # RSI oversold
        if rsi < RSI_OVERSOLD[]
            push!(signals, "RSI Oversold")
        end
        
        # Price near lower Bollinger Band
        if price <= bb_lower * 1.02  # Within 2% of lower band
            push!(signals, "Near Lower BB")
        end
        
        # Price above SMA (trend confirmation)
        if price > sma_20
            push!(signals, "Above SMA20")
        end
        
        # Volume confirmation
        if vol_ratio > VOLUME_THRESHOLD[]
            push!(signals, "High Volume")
        end
        
        # Need at least 2 signals for buy
        return length(signals) >= 2 ? signals : String[]
    end
    
    function check_sell_signals(price, rsi, bb_upper, vol_ratio, sma_20)
        signals = String[]
        
        # RSI overbought
        if rsi > RSI_OVERBOUGHT[]
            push!(signals, "RSI Overbought")
        end
        
        # Price near upper Bollinger Band
        if price >= bb_upper * 0.98  # Within 2% of upper band
            push!(signals, "Near Upper BB")
        end
        
        # Price below SMA (trend change)
        if price < sma_20
            push!(signals, "Below SMA20")
        end
        
        # Volume confirmation
        if vol_ratio > VOLUME_THRESHOLD[]
            push!(signals, "High Volume")
        end
        
        # Need at least 2 signals for sell
        return length(signals) >= 2 ? signals : String[]
    end
    
    function execute_buy(s::Strategy, ai::AssetInstance, signals, available_cash, price)
        trade_amount = min(available_cash * 0.2, 500.0)  # Use 20% of cash, max $500
        quantity = trade_amount / price
        
        @info "BUY SIGNAL" asset=raw(ai) price=price amount=trade_amount signals=signals
        
        # Here you would place actual buy order
        # place_market_buy_order(s, ai, quantity)
    end
    
    function execute_sell(s::Strategy, ai::AssetInstance, signals, balance, price)
        @info "SELL SIGNAL" asset=raw(ai) price=price balance=balance signals=signals
        
        # Here you would place actual sell order
        # place_market_sell_order(s, ai, balance)
    end
    
    # Include indicator functions from previous examples
    function calculate_rsi(data, period::Int=14)
        # ... (same as previous example)
    end
    
    function bollinger_bands(data, period::Int=20, std_dev::Float64=2.0)
        # ... (same as previous example)
    end
    
    function current_volume_ratio(data, period::Int)
        # ... (same as previous example)
    end
    
    function simple_moving_average(data, period::Int)
        # ... (same as previous example)
    end
end
```

## Usage Examples

### Basic Indicators
```julia
using Planar
@environment!

# Test simple indicators
s = strategy(:SimpleIndicatorsExample)
load_ohlcv(s)

# Run analysis
call!(s, now(), nothing)
```

### Advanced Indicators
```julia
# Test advanced indicators
s_adv = strategy(:AdvancedIndicatorsExample)
load_ohlcv(s_adv)
call!(s_adv, now(), nothing)
```

### Complete Strategy
```julia
# Test indicator-based strategy
s_strategy = strategy(:IndicatorStrategy)
load_ohlcv(s_strategy)

# Run backtest
results = backtest(s_strategy, 
    from=DateTime("2024-01-01"),
    to=DateTime("2024-06-30")
)
```

## Performance Tips

1. **Cache Calculations**: Store indicator values to avoid recalculation
2. **Vectorize Operations**: Use array operations when possible
3. **Limit Lookback**: Only calculate indicators for required periods
4. **Validate Inputs**: Always check for sufficient data before calculation
5. **Handle Edge Cases**: Account for division by zero and invalid data

## Common Indicator Patterns

### Trend Following
```julia
# Moving average crossover
sma_fast > sma_slow  # Bullish trend
sma_fast < sma_slow  # Bearish trend

# MACD confirmation
macd_line > signal_line && histogram > 0  # Bullish momentum
```

### Mean Reversion
```julia
# RSI extremes
rsi < 30  # Oversold, potential buy
rsi > 70  # Overbought, potential sell

# Bollinger Bands
price <= bb_lower  # Potential bounce up
price >= bb_upper  # Potential pullback
```

### Volume Confirmation
```julia
# High volume confirmation
volume_ratio > 1.5 && price_change > 0.02  # Strong bullish move
volume_ratio > 1.5 && price_change < -0.02  # Strong bearish move
```

## See Also

- **[Data Access Examples](data-access.md)** - Working with market data
- **[Technical Analysis Examples](technical-analysis.md)** - Advanced analysis techniques
- **[Risk Management Examples](risk-management.md)** - Position sizing and stops
- **[Multi-Asset Strategies](multi-asset.md)** - Trading multiple assets