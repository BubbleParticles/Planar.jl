---
title: "Troubleshooting: Exchange Issues"
description: "Solutions for exchange connectivity and API problems"
category: "troubleshooting"
difficulty: "intermediate"
prerequisites: ["exchange-setup", "api-configuration"]
related_topics: ["exchanges", "configuration", "authentication"]
last_updated: "2025-10-04"
estimated_time: "20 minutes"
---

# Troubleshooting: Exchange Issues

This guide covers problems related to exchange connectivity, API authentication, and trading operations.

## Quick Diagnostics

1. **Test Basic Connectivity** - Verify exchange connection
   ```julia
   using Exchanges
   exchange = getexchange(:binance)
   exchange.fetch_ticker("BTC/USDT")
   ```

2. **Check API Credentials** - Ensure authentication is working
   ```julia
   balance = exchange.fetch_balance()
   ```

3. **Verify Network Access** - Test internet connectivity to exchange endpoints

## Exchange Connection Issues

### Unresponsive Exchange Instance

**Symptoms:**
- Timeout errors during API calls
- "Connection refused" messages
- API calls hanging indefinitely

**Cause:**
Network connectivity issues, exchange maintenance, or connection timeouts.

**Solution:**
```julia
using Exchanges

# Step 1: Test basic connectivity
exchange = getexchange(:binance)  # or your exchange
try
    ticker = exchange.fetch_ticker("BTC/USDT")
    @info "Exchange connection working" ticker=ticker.last
catch e
    @error "Connection failed" exception=e
end

# Step 2: Reset exchange instance
exchange = getexchange(:binance, reset=true)

# Step 3: Adjust timeout settings
exchange.timeout = 30000  # 30 seconds
exchange.rateLimit = 1200  # Adjust rate limiting

# Step 4: Test with different endpoints
try
    # Test public endpoint
    markets = exchange.fetch_markets()
    @info "Public API working" market_count=length(markets)
    
    # Test private endpoint (requires authentication)
    balance = exchange.fetch_balance()
    @info "Private API working"
catch e
    @error "API test failed" exception=e
end
```

**Idle Connection Handling:**
```julia
# Implement connection health monitoring
function monitor_exchange_health(exchange, test_interval=300)  # 5 minutes
    last_test = time()
    
    function health_check()
        current_time = time()
        if current_time - last_test > test_interval
            try
                # Simple health check
                exchange.fetch_ticker("BTC/USDT")
                last_test = current_time
                @debug "Exchange health check passed"
            catch e
                @warn "Exchange health check failed, resetting connection" exception=e
                exchange = getexchange(exchange.id, reset=true)
            end
        end
    end
    
    return health_check
end

# Use before important operations
health_check = monitor_exchange_health(exchange)
health_check()
```

### Network Connectivity Problems

**Symptoms:**
- DNS resolution failures
- SSL/TLS handshake errors
- Intermittent connection drops

**Cause:**
Network configuration, firewall restrictions, or ISP issues.

**Solution:**
```julia
# Test network connectivity
using HTTP

function test_exchange_connectivity(exchange_id)
    endpoints = Dict(
        :binance => "https://api.binance.com/api/v3/ping",
        :coinbase => "https://api.exchange.coinbase.com/time",
        :kraken => "https://api.kraken.com/0/public/SystemStatus"
    )
    
    if haskey(endpoints, exchange_id)
        url = endpoints[exchange_id]
        try
            response = HTTP.get(url, timeout=10)
            @info "Network connectivity OK" status=response.status
            return true
        catch e
            @error "Network connectivity failed" url=url exception=e
            return false
        end
    else
        @warn "Unknown exchange for connectivity test" exchange=exchange_id
        return false
    end
end

# Test connectivity
if !test_exchange_connectivity(:binance)
    @error "Cannot reach exchange servers"
end
```

**Network Configuration:**
```julia
# Configure proxy if needed
ENV["HTTP_PROXY"] = "http://proxy.company.com:8080"
ENV["HTTPS_PROXY"] = "https://proxy.company.com:8080"

# Disable SSL verification if necessary (not recommended for production)
ENV["JULIA_SSL_NO_VERIFY_HOSTS"] = "api.exchange.com"

# Configure custom CA certificates
ENV["JULIA_SSL_CA_ROOTS_PATH"] = "/path/to/custom/ca-bundle.crt"
```

## API Authentication Issues

### Invalid API Credentials

**Symptoms:**
- "Invalid API key" errors
- "Signature verification failed" messages
- 401 Unauthorized responses

**Cause:**
Incorrect API credentials, expired keys, or configuration errors.

**Solution:**
```julia
# Step 1: Verify credentials format in user/secrets.toml
# Correct format:
# [exchanges.binance]
# apiKey = "your_api_key_here"
# secret = "your_secret_key_here"
# sandbox = false  # Set to true for testnet

# Step 2: Test authentication
exchange = getexchange(:binance)
try
    balance = exchange.fetch_balance()
    @info "Authentication successful" balance_keys=keys(balance)
catch e
    @error "Authentication failed" exception=e
    
    # Check if it's an authentication error
    if occursin("401", string(e)) || occursin("authentication", lowercase(string(e)))
        @error "Invalid API credentials - check your secrets.toml file"
    end
end

# Step 3: Verify API key permissions on exchange
function check_api_permissions(exchange)
    permissions = Dict()
    
    # Test read permissions
    try
        exchange.fetch_balance()
        permissions[:read] = true
    catch
        permissions[:read] = false
    end
    
    # Test trade permissions (with a small test order in sandbox)
    if get(exchange.sandbox, false, false)
        try
            # Only test in sandbox mode
            test_order = exchange.create_order("BTC/USDT", "limit", "buy", 0.001, 1.0)
            exchange.cancel_order(test_order["id"], "BTC/USDT")
            permissions[:trade] = true
        catch
            permissions[:trade] = false
        end
    end
    
    return permissions
end

permissions = check_api_permissions(exchange)
@info "API permissions" permissions
```

### API Key Configuration Issues

**Symptoms:**
- Configuration file not found
- Incorrect key format
- Sandbox/production mode confusion

**Cause:**
Missing or malformed configuration files.

**Solution:**
```julia
# Check configuration file existence and format
config_path = "user/secrets.toml"

if !isfile(config_path)
    @error "Configuration file not found" path=config_path
    
    # Create template configuration
    template = """
    # Exchange API Configuration
    # Copy your API keys from the exchange website
    
    [exchanges.binance]
    apiKey = "your_binance_api_key"
    secret = "your_binance_secret"
    sandbox = false  # Set to true for testnet
    
    [exchanges.coinbase]
    apiKey = "your_coinbase_api_key"
    secret = "your_coinbase_secret"
    passphrase = "your_coinbase_passphrase"
    sandbox = false
    """
    
    write(config_path, template)
    @info "Created template configuration file" path=config_path
else
    # Validate configuration format
    using TOML
    try
        config = TOML.parsefile(config_path)
        @info "Configuration file loaded successfully"
        
        # Check for required fields
        for (exchange_name, exchange_config) in get(config, "exchanges", Dict())
            required_fields = ["apiKey", "secret"]
            missing_fields = [field for field in required_fields if !haskey(exchange_config, field)]
            
            if !isempty(missing_fields)
                @warn "Missing required fields" exchange=exchange_name missing=missing_fields
            end
        end
    catch e
        @error "Configuration file format error" exception=e
    end
end
```

### Signature and Timestamp Issues

**Symptoms:**
- "Invalid signature" errors
- "Timestamp out of sync" messages
- Authentication working intermittently

**Cause:**
System clock synchronization issues or signature generation problems.

**Solution:**
```julia
using Dates

# Check system time synchronization
function check_time_sync(exchange)
    try
        # Get server time from exchange
        server_time = exchange.fetch_time()
        local_time = now(UTC)
        
        # Calculate time difference
        time_diff = abs(Dates.value(local_time - server_time)) / 1000  # Convert to seconds
        
        @info "Time synchronization" server_time=server_time local_time=local_time diff_seconds=time_diff
        
        if time_diff > 60  # More than 1 minute difference
            @warn "System clock may be out of sync" diff_seconds=time_diff
            @info "Consider synchronizing your system clock with NTP"
        end
        
        return time_diff < 60
    catch e
        @error "Could not check time synchronization" exception=e
        return false
    end
end

# Test time synchronization
is_synced = check_time_sync(exchange)

# Manual time adjustment if needed (Linux/macOS)
if !is_synced
    @info "To sync system time on Linux/macOS, run: sudo ntpdate -s time.nist.gov"
    @info "On Windows, enable automatic time synchronization in Date & Time settings"
end
```

## Rate Limiting Issues

### Rate Limit Exceeded

**Symptoms:**
- "Rate limit exceeded" errors
- 429 HTTP status codes
- Temporary API bans

**Cause:**
Too many API requests in a short time period.

**Solution:**
```julia
# Step 1: Adjust rate limiting settings
exchange = getexchange(:binance)
exchange.rateLimit = 2000  # Increase delay between requests (milliseconds)

# Step 2: Implement request batching
function batch_ticker_requests(exchange, symbols; batch_size=10)
    results = Dict()
    
    for i in 1:batch_size:length(symbols)
        batch_end = min(i + batch_size - 1, length(symbols))
        batch_symbols = symbols[i:batch_end]
        
        try
            # Use batch API if available
            if hasmethod(exchange.fetch_tickers, (Vector{String},))
                batch_tickers = exchange.fetch_tickers(batch_symbols)
                merge!(results, batch_tickers)
            else
                # Fall back to individual requests with rate limiting
                for symbol in batch_symbols
                    results[symbol] = exchange.fetch_ticker(symbol)
                    sleep(exchange.rateLimit / 1000)  # Respect rate limit
                end
            end
        catch e
            @warn "Batch request failed" batch=batch_symbols exception=e
        end
    end
    
    return results
end

# Step 3: Implement exponential backoff for retries
function api_call_with_backoff(f, max_retries=3)
    for attempt in 1:max_retries
        try
            return f()
        catch e
            if occursin("rate limit", lowercase(string(e))) && attempt < max_retries
                wait_time = 2^attempt  # Exponential backoff
                @warn "Rate limit hit, waiting before retry" attempt=attempt wait_seconds=wait_time
                sleep(wait_time)
            else
                rethrow()
            end
        end
    end
end

# Use with API calls
result = api_call_with_backoff(() -> exchange.fetch_ticker("BTC/USDT"))
```

### API Weight Management

**Symptoms:**
- Inconsistent rate limiting behavior
- Some requests work while others fail
- Complex rate limit error messages

**Cause:**
Different API endpoints have different weight costs.

**Solution:**
```julia
# Track API weight usage
mutable struct APIWeightTracker
    current_weight::Int
    max_weight::Int
    reset_time::DateTime
    
    APIWeightTracker(max_weight=1200) = new(0, max_weight, now() + Minute(1))
end

function track_api_call(tracker::APIWeightTracker, endpoint_weight::Int)
    current_time = now()
    
    # Reset counter if time window has passed
    if current_time >= tracker.reset_time
        tracker.current_weight = 0
        tracker.reset_time = current_time + Minute(1)
    end
    
    # Check if we can make the request
    if tracker.current_weight + endpoint_weight > tracker.max_weight
        wait_time = Dates.value(tracker.reset_time - current_time) / 1000
        @warn "API weight limit would be exceeded, waiting" wait_seconds=wait_time
        sleep(wait_time)
        
        # Reset after waiting
        tracker.current_weight = 0
        tracker.reset_time = now() + Minute(1)
    end
    
    # Update weight
    tracker.current_weight += endpoint_weight
end

# Use weight tracker
weight_tracker = APIWeightTracker()

function weighted_api_call(tracker, f, weight)
    track_api_call(tracker, weight)
    return f()
end

# Example usage
ticker = weighted_api_call(weight_tracker, () -> exchange.fetch_ticker("BTC/USDT"), 1)
orderbook = weighted_api_call(weight_tracker, () -> exchange.fetch_order_book("BTC/USDT"), 5)
```

## Trading Operation Issues

### Order Execution Failures

**Symptoms:**
- Orders not being placed
- "Insufficient balance" errors
- Order rejection messages

**Cause:**
Balance issues, incorrect order parameters, or market conditions.

**Solution:**
```julia
using OrderTypes

# Step 1: Comprehensive balance check
function check_trading_balance(exchange, symbol, side, amount, price=nothing)
    try
        balance = exchange.fetch_balance()
        market = exchange.fetch_market(symbol)
        
        base_currency = market["base"]
        quote_currency = market["quote"]
        
        if side == :buy
            # Check quote currency balance for buying
            available = get(balance, quote_currency, Dict("free" => 0.0))["free"]
            required = amount * (price !== nothing ? price : exchange.fetch_ticker(symbol)["last"])
            
            @info "Buy order balance check" currency=quote_currency available=available required=required
            
            if available < required
                @error "Insufficient balance for buy order" available=available required=required
                return false
            end
        else
            # Check base currency balance for selling
            available = get(balance, base_currency, Dict("free" => 0.0))["free"]
            
            @info "Sell order balance check" currency=base_currency available=available required=amount
            
            if available < amount
                @error "Insufficient balance for sell order" available=available required=amount
                return false
            end
        end
        
        return true
    catch e
        @error "Balance check failed" exception=e
        return false
    end
end

# Step 2: Validate order parameters
function validate_order_parameters(exchange, symbol, side, amount, price=nothing)
    try
        market = exchange.fetch_market(symbol)
        limits = market["limits"]
        
        # Check minimum amount
        min_amount = get(limits["amount"], "min", 0.0)
        if amount < min_amount
            @error "Order amount below minimum" amount=amount min=min_amount
            return false
        end
        
        # Check maximum amount
        max_amount = get(limits["amount"], "max", Inf)
        if amount > max_amount
            @error "Order amount above maximum" amount=amount max=max_amount
            return false
        end
        
        # Check minimum notional value
        if haskey(limits, "cost")
            min_cost = get(limits["cost"], "min", 0.0)
            estimated_cost = amount * (price !== nothing ? price : exchange.fetch_ticker(symbol)["last"])
            
            if estimated_cost < min_cost
                @error "Order value below minimum notional" cost=estimated_cost min=min_cost
                return false
            end
        end
        
        # Check price precision for limit orders
        if price !== nothing && haskey(market, "precision")
            price_precision = get(market["precision"], "price", 8)
            if length(string(price)) - findfirst('.', string(price)) > price_precision
                @warn "Price precision may be too high" price=price max_precision=price_precision
            end
        end
        
        return true
    catch e
        @error "Order validation failed" exception=e
        return false
    end
end

# Step 3: Safe order placement with validation
function place_order_safely(exchange, symbol, side, amount, price=nothing)
    # Pre-flight checks
    if !check_trading_balance(exchange, symbol, side, amount, price)
        return nothing
    end
    
    if !validate_order_parameters(exchange, symbol, side, amount, price)
        return nothing
    end
    
    # Place order with error handling
    try
        if price !== nothing
            order = exchange.create_limit_order(symbol, side, amount, price)
        else
            order = exchange.create_market_order(symbol, side, amount)
        end
        
        @info "Order placed successfully" order_id=order["id"] symbol=symbol side=side amount=amount
        return order
    catch e
        @error "Order placement failed" exception=e
        return nothing
    end
end

# Example usage
order = place_order_safely(exchange, "BTC/USDT", :buy, 0.001, 50000.0)
```

### Position Management Issues

**Symptoms:**
- Incorrect position calculations
- Margin requirements not met
- Position size limits exceeded

**Cause:**
Margin trading configuration, leverage settings, or position tracking errors.

**Solution:**
```julia
# Comprehensive position and margin management
function check_margin_requirements(exchange, symbol, side, amount, leverage=1.0)
    try
        # Get account information
        account = exchange.fetch_account()
        balance = exchange.fetch_balance()
        
        # Calculate required margin
        ticker = exchange.fetch_ticker(symbol)
        position_value = amount * ticker["last"]
        required_margin = position_value / leverage
        
        # Check available margin
        available_margin = get(balance, "USDT", Dict("free" => 0.0))["free"]  # Adjust currency as needed
        
        @info "Margin check" required=required_margin available=available_margin leverage=leverage
        
        if available_margin < required_margin
            @error "Insufficient margin" required=required_margin available=available_margin
            return false
        end
        
        # Check position limits
        if haskey(account, "positions")
            current_position = 0.0
            for position in account["positions"]
                if position["symbol"] == symbol
                    current_position = position["contracts"]
                    break
                end
            end
            
            new_position = current_position + (side == :buy ? amount : -amount)
            max_position = get_max_position_size(exchange, symbol)  # Implement based on exchange
            
            if abs(new_position) > max_position
                @error "Position would exceed maximum size" new_position=new_position max=max_position
                return false
            end
        end
        
        return true
    catch e
        @error "Margin check failed" exception=e
        return false
    end
end

# Position tracking and management
mutable struct PositionTracker
    positions::Dict{String, Float64}
    entry_prices::Dict{String, Float64}
    unrealized_pnl::Dict{String, Float64}
    
    PositionTracker() = new(Dict(), Dict(), Dict())
end

function update_position(tracker::PositionTracker, symbol, side, amount, price)
    current_position = get(tracker.positions, symbol, 0.0)
    
    if side == :buy
        new_position = current_position + amount
    else
        new_position = current_position - amount
    end
    
    # Update entry price (weighted average)
    if haskey(tracker.entry_prices, symbol) && current_position != 0.0
        current_entry = tracker.entry_prices[symbol]
        total_value = abs(current_position) * current_entry + amount * price
        total_amount = abs(current_position) + amount
        tracker.entry_prices[symbol] = total_value / total_amount
    else
        tracker.entry_prices[symbol] = price
    end
    
    tracker.positions[symbol] = new_position
    
    @info "Position updated" symbol=symbol position=new_position entry_price=tracker.entry_prices[symbol]
end

# Example usage
position_tracker = PositionTracker()
if check_margin_requirements(exchange, "BTC/USDT", :buy, 0.1, 2.0)
    order = place_order_safely(exchange, "BTC/USDT", :buy, 0.1)
    if order !== nothing
        update_position(position_tracker, "BTC/USDT", :buy, 0.1, order["price"])
    end
end
```

## Exchange-Specific Issues

### Binance-Specific Problems

**Common Issues:**
- Futures vs Spot API confusion
- Testnet configuration
- IP restrictions

**Solutions:**
```julia
# Binance-specific configuration
function configure_binance_properly()
    # For spot trading
    spot_exchange = getexchange(:binance)
    spot_exchange.sandbox = false  # Production
    
    # For futures trading
    futures_exchange = getexchange(:binance)
    futures_exchange.urls["api"] = "https://fapi.binance.com"  # Futures API
    
    # For testnet
    testnet_exchange = getexchange(:binance)
    testnet_exchange.sandbox = true
    testnet_exchange.urls["api"] = "https://testnet.binance.vision"
    
    return spot_exchange, futures_exchange, testnet_exchange
end

# Check IP restrictions
function check_binance_ip_restrictions(exchange)
    try
        # This call requires API key and will fail if IP is not whitelisted
        account_info = exchange.fetch_account()
        @info "IP restrictions check passed"
        return true
    catch e
        if occursin("IP", string(e)) || occursin("whitelist", string(e))
            @error "IP address not whitelisted on Binance"
            @info "Add your IP address to the API key whitelist on Binance"
            return false
        else
            @warn "Unknown error during IP check" exception=e
            return false
        end
    end
end
```

### Coinbase-Specific Problems

**Common Issues:**
- Passphrase configuration
- Sandbox environment setup
- Advanced trade API vs Exchange API

**Solutions:**
```julia
# Coinbase Pro/Advanced Trade configuration
function configure_coinbase_properly()
    # Check if using correct API
    exchange = getexchange(:coinbase)
    
    # Verify passphrase is configured
    if !haskey(exchange.secret, "passphrase")
        @error "Coinbase requires passphrase in addition to API key and secret"
        @info "Add passphrase to your secrets.toml: passphrase = \"your_passphrase\""
        return nothing
    end
    
    # Configure for sandbox if needed
    if get(exchange.sandbox, false, false)
        exchange.urls["api"] = "https://api-public.sandbox.exchange.coinbase.com"
    end
    
    return exchange
end
```

## Advanced Diagnostics

### Exchange Health Monitoring

```julia
# Comprehensive exchange health check
function comprehensive_exchange_health_check(exchange)
    health_report = Dict()
    
    # Test 1: Basic connectivity
    try
        ping_result = exchange.fetch_status()
        health_report[:connectivity] = "OK"
    catch e
        health_report[:connectivity] = "FAILED: $(e)"
    end
    
    # Test 2: Public API
    try
        ticker = exchange.fetch_ticker("BTC/USDT")
        health_report[:public_api] = "OK"
    catch e
        health_report[:public_api] = "FAILED: $(e)"
    end
    
    # Test 3: Private API (if authenticated)
    try
        balance = exchange.fetch_balance()
        health_report[:private_api] = "OK"
    catch e
        health_report[:private_api] = "FAILED: $(e)"
    end
    
    # Test 4: Rate limiting
    start_time = time()
    try
        for i in 1:5
            exchange.fetch_ticker("BTC/USDT")
        end
        elapsed = time() - start_time
        health_report[:rate_limiting] = "OK ($(elapsed)s for 5 requests)"
    catch e
        health_report[:rate_limiting] = "FAILED: $(e)"
    end
    
    return health_report
end

# Run health check
health = comprehensive_exchange_health_check(exchange)
for (test, result) in health
    println("$test: $result")
end
```

### Network Diagnostics

```julia
using Sockets

# Network diagnostic tools
function diagnose_network_issues(exchange_id)
    endpoints = Dict(
        :binance => ("api.binance.com", 443),
        :coinbase => ("api.exchange.coinbase.com", 443),
        :kraken => ("api.kraken.com", 443)
    )
    
    if !haskey(endpoints, exchange_id)
        @error "Unknown exchange for network diagnostics"
        return
    end
    
    host, port = endpoints[exchange_id]
    
    # Test DNS resolution
    try
        ip = Sockets.getaddrinfo(host)
        @info "DNS resolution successful" host=host ip=ip
    catch e
        @error "DNS resolution failed" host=host exception=e
        return
    end
    
    # Test TCP connection
    try
        sock = Sockets.connect(host, port)
        close(sock)
        @info "TCP connection successful" host=host port=port
    catch e
        @error "TCP connection failed" host=host port=port exception=e
        return
    end
    
    # Test HTTPS
    try
        response = HTTP.get("https://$host", timeout=10)
        @info "HTTPS connection successful" status=response.status
    catch e
        @error "HTTPS connection failed" host=host exception=e
    end
end

# Run network diagnostics
diagnose_network_issues(:binance)
```

## When to Seek Help

Contact the community if:
- Exchange-specific errors persist after following troubleshooting steps
- API authentication fails despite correct configuration
- Network connectivity issues cannot be resolved
- Trading operations fail consistently with proper setup

## Getting Help

- [Community Resources](../resources/community.md)
- [GitHub Issues](https://github.com/defnlnotme/Planar.jl/issues)
- [Exchange Documentation](../exchanges.md)
- [Configuration Guide](../config.md)

## See Also

- [Exchanges](../exchanges.md) - Exchange setup and configuration
- [Configuration](../config.md) - API key and settings management
- [Installation Issues](installation-issues.md) - Setup problems
- [Strategy Problems](strategy-problems.md) - Strategy execution issues