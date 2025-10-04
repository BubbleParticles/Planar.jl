---
title: "Instruments API"
description: "Financial instrument definitions and management"
category: "api-reference"
difficulty: "advanced"
prerequisites: ["getting-started", "strategy-development"]
topics: ["api-reference", "instruments", "assets", "derivatives"]
last_updated: "2025-10-04"
estimated_time: "Reference material"
---

# Instruments API

The Instruments module provides definitions and management for financial instruments in Planar. It handles different asset types, currency management, and derivative instruments for advanced trading strategies.

## Overview

The Instruments module includes:
- Base asset types and currency definitions
- Cash and currency management
- Derivative instruments (futures, options, etc.)
- Asset validation and conversion utilities
- Compact number formatting for financial data

## Core Asset Types

### Base Asset Types

```julia
# Abstract base type for all assets
abstract type AbstractAsset end

# Concrete asset type
struct Asset <: AbstractAsset
    symbol::Symbol
    name::String
    type::Symbol  # :crypto, :stock, :forex, etc.
end

# Cash/Currency type
struct Cash <: AbstractAsset
    currency::Symbol
    amount::Float64
end
```

### Asset Creation and Management

```julia
using Planar
@environment!

# Create basic assets
btc = Asset(:BTC, "Bitcoin", :crypto)
eth = Asset(:ETH, "Ethereum", :crypto)
usdt = Asset(:USDT, "Tether", :stablecoin)

# Create cash instances
usd_cash = Cash(:USD, 10000.0)
btc_cash = Cash(:BTC, 1.5)

# Asset information
println("Asset: $(btc.name) ($(btc.symbol))")
println("Type: $(btc.type)")

# Check if asset is fiat currency
fiat_currencies = fiatnames()  # Returns common fiat currency symbols
is_fiat = btc.symbol in fiat_currencies
println("Is fiat: $is_fiat")
```

### Currency Operations

```julia
# Cash manipulation functions
initial_cash = Cash(:USD, 1000.0)

# Add cash
cash!(initial_cash, 500.0)  # Add $500
println("After addition: $(initial_cash.amount)")

# Subtract cash
cash!(initial_cash, -200.0)  # Subtract $200
println("After subtraction: $(initial_cash.amount)")

# Create zero cash
zero_cash = addzero!(Cash(:USD, 0.0))

# Subtract to zero (safe subtraction)
subzero!(initial_cash, 2000.0)  # Won't go below zero
```

#### Advanced Cash Operations

```julia
# Working with multiple currencies
portfolio_cash = Dict{Symbol, Cash}()

# Initialize portfolio
currencies = [:USD, :EUR, :BTC, :ETH]
for curr in currencies
    portfolio_cash[curr] = Cash(curr, 0.0)
end

# Add funds to different currencies
add!(portfolio_cash[:USD], 10000.0)
add!(portfolio_cash[:BTC], 0.5)
add!(portfolio_cash[:ETH], 2.0)

# Calculate total value (requires exchange rates)
function calculate_portfolio_value(portfolio, base_currency=:USD)
    total_value = 0.0
    
    for (currency, cash_obj) in portfolio
        if currency == base_currency
            total_value += cash_obj.amount
        else
            # Convert to base currency (simplified example)
            exchange_rate = get_exchange_rate(currency, base_currency)
            total_value += cash_obj.amount * exchange_rate
        end
    end
    
    return total_value
end
```

## Derivative Instruments

### Derivative Types

```julia
using .Instruments.Derivatives

# Future contract
struct Future <: Derivative
    underlying::AbstractAsset
    expiry::DateTime
    contract_size::Float64
    tick_size::Float64
end

# Option contract
struct Option <: Derivative
    underlying::AbstractAsset
    strike::Float64
    expiry::DateTime
    option_type::Symbol  # :call or :put
    style::Symbol        # :european or :american
end
```

### Working with Derivatives

```julia
# Create derivative instruments
btc_future = Future(
    underlying=Asset(:BTC, "Bitcoin", :crypto),
    expiry=DateTime("2024-12-31"),
    contract_size=1.0,
    tick_size=0.01
)

eth_call_option = Option(
    underlying=Asset(:ETH, "Ethereum", :crypto),
    strike=3000.0,
    expiry=DateTime("2024-06-30"),
    option_type=:call,
    style=:european
)

# Derivative calculations
function calculate_option_intrinsic_value(option::Option, current_price::Float64)
    if option.option_type == :call
        return max(0.0, current_price - option.strike)
    else  # put option
        return max(0.0, option.strike - current_price)
    end
end

# Example usage
eth_price = 2800.0
intrinsic_value = calculate_option_intrinsic_value(eth_call_option, eth_price)
println("Option intrinsic value: $intrinsic_value")
```

### Derivative Portfolio Management

```julia
# Manage a portfolio of derivatives
struct DerivativePosition
    instrument::Derivative
    quantity::Float64
    entry_price::Float64
    entry_time::DateTime
end

# Portfolio tracking
derivative_portfolio = DerivativePosition[]

# Add positions
push!(derivative_portfolio, DerivativePosition(
    btc_future, 
    2.0,      # 2 contracts
    45000.0,  # Entry price
    now()
))

push!(derivative_portfolio, DerivativePosition(
    eth_call_option,
    10.0,     # 10 contracts
    150.0,    # Premium paid
    now()
))

# Calculate portfolio P&L
function calculate_derivative_pnl(portfolio, current_prices)
    total_pnl = 0.0
    
    for position in portfolio
        current_price = current_prices[position.instrument.underlying.symbol]
        
        if isa(position.instrument, Future)
            # Future P&L = (current_price - entry_price) * quantity * contract_size
            pnl = (current_price - position.entry_price) * position.quantity * position.instrument.contract_size
        elseif isa(position.instrument, Option)
            # Option P&L = (intrinsic_value - premium_paid) * quantity
            intrinsic = calculate_option_intrinsic_value(position.instrument, current_price)
            pnl = (intrinsic - position.entry_price) * position.quantity
        end
        
        total_pnl += pnl
    end
    
    return total_pnl
end
```

## Number Formatting

### Compact Number Display

```julia
# Format large numbers compactly
large_number = 1_234_567.89
compact_str = compactnum(large_number)
println("Compact: $compact_str")  # Output: "1.23M"

# Format with different precision
compact_precise = compactnum(large_number, digits=3)
println("Precise: $compact_precise")  # Output: "1.235M"

# Format small numbers
small_number = 0.000123
compact_small = compactnum(small_number)
println("Small: $compact_small")  # Output: "123μ"

# Custom formatting for trading
function format_price(price::Float64, asset::AbstractAsset)
    if asset.type == :crypto
        return compactnum(price, digits=6)
    elseif asset.type == :stock
        return compactnum(price, digits=2)
    else
        return compactnum(price, digits=4)
    end
end

# Usage examples
btc_price = 45678.123456
formatted_btc = format_price(btc_price, btc)
println("BTC Price: $formatted_btc")
```

## Asset Validation and Utilities

### Asset Validation

```julia
# Validate asset symbols
function validate_asset_symbol(symbol::Symbol)
    symbol_str = string(symbol)
    
    # Check length
    if length(symbol_str) < 2 || length(symbol_str) > 10
        return false, "Symbol length must be 2-10 characters"
    end
    
    # Check characters (alphanumeric only)
    if !all(isalnum, symbol_str)
        return false, "Symbol must contain only alphanumeric characters"
    end
    
    return true, "Valid symbol"
end

# Asset conversion utilities
function normalize_asset_symbol(symbol::Union{String, Symbol})
    normalized = uppercase(string(symbol))
    return Symbol(normalized)
end

# Example usage
symbols_to_check = [:BTC, :eth, "USDT", "invalid-symbol", :A]

for sym in symbols_to_check
    normalized = normalize_asset_symbol(sym)
    is_valid, message = validate_asset_symbol(normalized)
    println("$sym -> $normalized: $is_valid ($message)")
end
```

### Asset Comparison and Sorting

```julia
# Custom comparison for assets
function Base.isless(a1::AbstractAsset, a2::AbstractAsset)
    return string(a1.symbol) < string(a2.symbol)
end

# Sort assets
asset_list = [
    Asset(:ETH, "Ethereum", :crypto),
    Asset(:BTC, "Bitcoin", :crypto),
    Asset(:ADA, "Cardano", :crypto),
    Asset(:USDT, "Tether", :stablecoin)
]

sorted_assets = sort(asset_list)
println("Sorted assets:")
for asset in sorted_assets
    println("  $(asset.symbol): $(asset.name)")
end

# Group assets by type
function group_assets_by_type(assets::Vector{<:AbstractAsset})
    groups = Dict{Symbol, Vector{AbstractAsset}}()
    
    for asset in assets
        if !haskey(groups, asset.type)
            groups[asset.type] = AbstractAsset[]
        end
        push!(groups[asset.type], asset)
    end
    
    return groups
end

grouped = group_assets_by_type(asset_list)
for (type, assets) in grouped
    println("$type assets: $(length(assets))")
end
```

## Integration with Strategy Framework

### Asset Instance Integration

```julia
# Working with asset instances in strategies
function analyze_strategy_assets(s::Strategy)
    println("Strategy Asset Analysis")
    println("=" ^ 30)
    
    for ai in instances(s)
        asset = ai.asset
        
        # Basic asset info
        println("Asset: $(asset.symbol) ($(asset.name))")
        println("Type: $(asset.type)")
        
        # Current data
        if !isempty(ohlcv(ai))
            current_price = lastprice(ai)
            formatted_price = format_price(current_price, asset)
            println("Current Price: $formatted_price")
            
            # Volume analysis
            recent_volume = volumeat(ohlcv(ai), -1)
            avg_volume = mean(volumeat(ohlcv(ai), -20:-1))
            volume_ratio = recent_volume / avg_volume
            
            println("Volume Ratio: $(round(volume_ratio, digits=2))x")
        end
        
        # Cash information
        if isa(asset, Cash)
            println("Cash Amount: $(compactnum(asset.amount))")
        end
        
        println()
    end
end

# Asset filtering utilities
function filter_crypto_assets(s::Strategy)
    return filter(ai -> ai.asset.type == :crypto, instances(s))
end

function filter_high_volume_assets(s::Strategy, volume_threshold=1.5)
    return filter(instances(s)) do ai
        if !isempty(ohlcv(ai)) && length(ohlcv(ai).volume) >= 20
            recent_volume = volumeat(ohlcv(ai), -1)
            avg_volume = mean(volumeat(ohlcv(ai), -20:-1))
            return recent_volume / avg_volume > volume_threshold
        end
        return false
    end
end
```

## Performance Considerations

### Efficient Asset Operations

```julia
# Pre-allocate asset collections
function create_asset_lookup(assets::Vector{<:AbstractAsset})
    lookup = Dict{Symbol, AbstractAsset}()
    for asset in assets
        lookup[asset.symbol] = asset
    end
    return lookup
end

# Batch asset operations
function batch_update_cash!(cash_dict::Dict{Symbol, Cash}, updates::Dict{Symbol, Float64})
    for (currency, amount) in updates
        if haskey(cash_dict, currency)
            cash!(cash_dict[currency], amount)
        else
            cash_dict[currency] = Cash(currency, amount)
        end
    end
end

# Memory-efficient asset processing
function process_assets_efficiently(assets::Vector{<:AbstractAsset}, processor_func)
    results = Vector{Any}(undef, length(assets))
    
    @sync for (i, asset) in enumerate(assets)
        @async begin
            results[i] = processor_func(asset)
        end
    end
    
    return results
end
```

## Complete API Reference

```@autodocs
Modules = [Instruments, Instruments.Derivatives]
Order = [:type]
```

```@autodocs
Modules = [Instruments, Instruments.Derivatives]
Order = [:function]
```

```@autodocs
Modules = [Instruments, Instruments.Derivatives]
Order = [:macro, :constant]
```

## See Also

- **[Instances API](instances.md)** - Asset instance management
- **[Strategies API](strategies.md)** - Strategy base classes and interfaces
- **[Data API](data.md)** - Data structures and management
- **[Strategy Development Guide](../guides/strategy-development.md)** - Building trading strategies
- **[Advanced Trading Guide](../advanced/margin-trading.md)** - Margin and derivative trading
