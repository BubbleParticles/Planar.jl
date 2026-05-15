module WSClient

using HTTP
using JSON3
using MbedTLS

export GatewayWSClient, WSMessages
export connect!, disconnect!, is_connected, send_subscribe, send_unsubscribe
export generate_uuid

const _ws_type = HTTP.WebSockets.WebSocket

mutable struct GatewayWSClient
    host::String
    port::Int
    url::String
    use_ssl::Bool
    ssl_config::Union{MbedTLS.SSLConfig, Nothing}
    subscriptions::Dict{String, Function}
    
    function GatewayWSClient(;
        host::String="localhost",
        port::Int=8999,
        use_ssl::Bool=true,
    )
        protocol = use_ssl ? "wss" : "ws"
        url = "$protocol://$host:$port/ws"
        ssl_cfg = use_ssl ? MbedTLS.SSLConfig(false) : nothing
        new(host, port, url, use_ssl, ssl_cfg, Dict{String, Function}())
    end
end

Base.show(io::IO, client::GatewayWSClient) = print(io, "GatewayWSClient($(client.host):$(client.port))")

function connect!(client::GatewayWSClient)
    local ws
    try
        WebSockets.open(client.url;
            sslconfig=client.ssl_config,
            require_ssl_verification=false
        ) do socket
            ws = socket
            client.subscriptions[:_ws] = ws
        end
        return true
    catch e
        @error "WebSocket connection failed: $e"
        delete!(client.subscriptions, :_ws, nothing)
        return false
    end
end

function disconnect!(client::GatewayWSClient)
    ws = get(client.subscriptions, :_ws, nothing)
    if ws !== nothing
        try
            close(ws)
        catch
        end
        delete!(client.subscriptions, :_ws)
    end
    empty!(client.subscriptions)
end

function is_connected(client::GatewayWSClient)
    ws = get(client.subscriptions, :_ws, nothing)
    ws !== nothing
end

function send_message(client::GatewayWSClient, message::Dict{String, Any})
    ws = get(client.subscriptions, :_ws, nothing)
    if ws === nothing
        error("WebSocket not connected")
    end
    write(ws, JSON3.write(message))
end

function send_subscribe(client::GatewayWSClient, exchange_id::String, method::String; 
    subscription_id::Union{String, Nothing}=nothing,
    params::Dict{String, Any}=Dict{String, Any}(),
    callback::Union{Function, Nothing}=nothing,
)
    sub_id = subscription_id === nothing ? string(uuid4()) : subscription_id
    
    if callback !== nothing
        client.subscriptions[sub_id] = callback
    end
    
    message = Dict{String, Any}(
        "type" => "subscribe",
        "subscription_id" => sub_id,
        "exchange_id" => exchange_id,
        "method" => method,
        "params" => params,
    )
    
    send_message(client, message)
    sub_id
end

function send_unsubscribe(client::GatewayWSClient, subscription_id::String)
    delete!(client.subscriptions, subscription_id)
    
    message = Dict{String, Any}(
        "type" => "unsubscribe",
        "subscription_id" => subscription_id,
    )
    
    send_message(client, message)
end

struct WSMessages
    type::String
    data::Any
    subscription_id::Union{String, Nothing}
    error::Union{String, Nothing}
    exchange_id::Union{String, Nothing}
    method::Union{String, Nothing}
end

function WSMessages(d::Dict{String, Any})
    WSMessages(
        get(d, "type", ""),
        get(d, "data", nothing),
        get(d, "subscription_id", nothing),
        get(d, "error", nothing),
        get(d, "exchange_id", nothing),
        get(d, "method", nothing),
    )
end

uuid4() = string(Base.UUID(rand(UInt128)))
const generate_uuid = uuid4

end # module WSClient