---
category: "exchanges"
difficulty: "advanced"
topics: [exchanges]
last_updated: "2025-10-04"---
---

The bot is primarily designed for cryptocurrency trading; however, it can be adapted for stock trading by interfacing with various brokers' APIs. To do this, you will need to create a custom implementation of the `Exchange` abstract type.

Here is a basic structure of how you can define your broker-specific exchange:

```julia
# Activate Planar project
import Pkg
Pkg.activate("Planar")

try
    using Planar
    
    # Example custom exchange implementation
    abstract type Exchange end  # This would be imported from Planar in real usage
    
    struct MyBroker <: Exchange
        api_key::String
        secret::String
        sandbox::Bool
        
        # Constructor
        MyBroker(api_key, secret; sandbox=true) = new(api_key, secret, sandbox)
    end
    
    println("Custom exchange MyBroker defined")
    println("Note: Real implementation requires full Exchange interface")
    
catch e
    @warn "Planar not available: $e"
end
```

To understand the requirements for substituting the default exchange implementation, review the `check` function located in the `Exchanges` module. It is worth noting that creating a fully compatible `Exchange` type may be more complex and less efficient than extending the CCXT library with broker support to avoid the overhead of calling Python code.

In future updates, the bot may include direct support for decentralized exchanges (DEX). This could be achieved by integrating middleware from hummingbot connectors, developing custom API communications between the bot and DEX nodes, or potentially through enhancements to the [CCXT](../exchanges.md#ccxt-integration) library, should it expand to accommodate DEX functionalities.

## See Also

- **[Exchanges](../exchanges.md)** - Exchange integration and configuration
- **[Config](../config.md)** - Exchange integration and configuration
