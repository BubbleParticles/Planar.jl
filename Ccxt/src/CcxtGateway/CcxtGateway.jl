module CcxtGateway

using HTTP
using JSON3
using OrderedCollections

include("types.jl")
include("rest.jl")
include("websocket.jl")

using .Rest: GatewayClient, ping, list_exchanges, exchange_info, server_info, memory_usage, start_exchange, stop_exchange, call_exchange, spawn_gateway, gateway_pid, stop_gateway, restart_gateway
using .Rest: list_errors, get_ccxt_errors, isccxterror, check_ccxt_update, upgrade_ccxt
using .Rest: fetch_exchange_has
using .WSClient: GatewayWSClient, connect!, disconnect!, is_connected, send_subscribe, send_unsubscribe, WSMessages

export GatewayClient
export start_exchange, stop_exchange, call_exchange
export list_exchanges, exchange_info, server_info, memory_usage, ping, spawn_gateway
export gateway_pid, stop_gateway, restart_gateway
export GatewayWSClient, connect!, disconnect!, is_connected, send_subscribe, send_unsubscribe, WSMessages
export list_errors, get_ccxt_errors, isccxterror, check_ccxt_update, upgrade_ccxt
export fetch_exchange_has

issupported(sym::Symbol) = true

end # module CcxtGateway
