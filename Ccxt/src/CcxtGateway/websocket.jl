module WSClient

using HTTP
using JSON3
using MbedTLS

export GatewayWSClient, WSMessages
export connect!, disconnect!, is_connected, send_subscribe, send_unsubscribe
export generate_uuid

"""
    GatewayWSClient(; host="localhost", port=8999, use_ssl=true)

A WebSocket client for connecting to the ccxt-gateway's `/ws` endpoint.

Manages a persistent WebSocket connection with a background read loop that
dispatches incoming messages (updates) to registered subscription callbacks.

Fields:
- `subscriptions`: Maps subscription IDs to their data callbacks.
                   Also stores the WebSocket ref under internal key `"_ws_conn"`.
- `task`: The background read-loop Task.
"""
mutable struct GatewayWSClient
    host::String
    port::Int
    url::String
    use_ssl::Bool
    ssl_config::Union{MbedTLS.SSLConfig, Nothing}
    subscriptions::Dict{String, Any}
    task::Union{Task, Nothing}

    function GatewayWSClient(;
        host::String="localhost",
        port::Int=8999,
        use_ssl::Bool=true,
    )
        protocol = use_ssl ? "wss" : "ws"
        url = "$protocol://$host:$port/ws"
        ssl_cfg = use_ssl ? MbedTLS.SSLConfig(false) : nothing
        new(host, port, url, use_ssl, ssl_cfg, Dict{String, Any}(), nothing)
    end
end

Base.show(io::IO, client::GatewayWSClient) = print(io, "GatewayWSClient($(client.host):$(client.port))")

# --- Internal helpers ---

"""Run the read loop for an established WebSocket connection."""
function _run_read_loop(client::GatewayWSClient, ws)
    while isopen(ws)
        try
            msg = read(ws)
            data = JSON3.read(String(msg))
            _dispatch_message(client, data)
        catch e
            if e isa EOFError
                break  # clean close
            elseif isopen(ws)
                @error "WebSocket read error" exception = (e, catch_backtrace())
            else
                break
            end
        end
    end
end

"""Dispatch a parsed JSON message to the matching subscription callback."""
function _dispatch_message(client::GatewayWSClient, data)
    msg_type = get(data, "type", "")
    if msg_type == "update"
        sub_id = get(data, "subscription_id", "")
        callback = get(client.subscriptions, sub_id, nothing)
        if callback !== nothing
            callback(get(data, "data", nothing))
        end
    elseif msg_type == "subscribed"
        sub_id = get(data, "subscription_id", "")
        @debug "WebSocket subscription confirmed: $sub_id"
    elseif msg_type == "error"
        @error "WebSocket error" error = get(data, "error", "") subscription_id = get(data, "subscription_id", "")
    end
end

# --- Public API ---

"""
    connect!(client::GatewayWSClient) -> Bool

Open a persistent WebSocket connection to the gateway's `/ws` endpoint.
Launches a background read loop that dispatches `"update"` messages to the
registered subscription callbacks (set via `send_subscribe`).

Returns `true` if the connection was established, `false` on failure.
Is idempotent — returns `true` immediately if already connected.
"""
function connect!(client::GatewayWSClient)
    if is_connected(client)
        return true
    end
    if client.task !== nothing && istaskrunning(client.task)
        return true
    end

    barrier = Condition()
    conn_error = Ref{Union{Exception, Nothing}}(nothing)

    client.task = @async begin
        try
            WebSockets.open(client.url;
                sslconfig=client.ssl_config,
                require_ssl_verification=false,
            ) do ws
                client.subscriptions["_ws_conn"] = ws
                notify(barrier)
                _run_read_loop(client, ws)
            end
        catch e
            conn_error[] = e
            notify(barrier)
        finally
            delete!(client.subscriptions, "_ws_conn", nothing)
            client.task = nothing
        end
    end

    # Wait for either the connection to be established or an error
    wait(barrier)
    if conn_error[] !== nothing
        @error "WebSocket connection failed" exception = conn_error[]
        return false
    end
    return true
end

"""
    disconnect!(client::GatewayWSClient)

Close the WebSocket connection and clear all subscriptions.
"""
function disconnect!(client::GatewayWSClient)
    ws = get(client.subscriptions, "_ws_conn", nothing)
    if ws !== nothing
        try
            close(ws)
        catch
        end
    end
    empty!(client.subscriptions)
    client.task = nothing
end

"""
    is_connected(client::GatewayWSClient) -> Bool

Check whether the WebSocket connection is active.
"""
function is_connected(client::GatewayWSClient)
    ws = get(client.subscriptions, "_ws_conn", nothing)
    ws !== nothing && isopen(ws)
end

"""
    send_message(client::GatewayWSClient, message::Dict{String,Any})

Send a JSON message over the WebSocket connection.
"""
function send_message(client::GatewayWSClient, message::Dict{String, Any})
    ws = get(client.subscriptions, "_ws_conn", nothing)
    if ws === nothing
        error("WebSocket not connected")
    end
    write(ws, JSON3.write(message))
end

"""
    send_subscribe(client, exchange_id, method; subscription_id=nothing, params=Dict(), callback=nothing) -> sub_id

Subscribe to a watch method on an exchange via the gateway WebSocket.

- `exchange_id`: e.g. `"binance"`
- `method`: e.g. `"watchTrades"`
- `params`: Dict of keyword arguments passed to the method
- `callback`: function called with `data` for each `"update"` message
- Returns the generated (or provided) subscription UUID.
"""
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

"""
    send_unsubscribe(client, subscription_id)

Unsubscribe from a watch subscription.
Removes the callback and sends an unsubscribe message to the gateway.
"""
function send_unsubscribe(client::GatewayWSClient, subscription_id::String)
    delete!(client.subscriptions, subscription_id)

    message = Dict{String, Any}(
        "type" => "unsubscribe",
        "subscription_id" => subscription_id,
    )
    try
        send_message(client, message)
    catch
        @debug "Could not send unsubscribe (connection may be closed)"
    end
end

# --- WSMessages (kept for backward compatibility) ---

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

# --- UUID ---

uuid4() = string(Base.UUID(rand(UInt128)))
const generate_uuid = uuid4

# --- Default singleton client ---

const _default_ws_client = Ref{Union{GatewayWSClient, Nothing}}(nothing)

function default_ws_client()
    if !isassigned(_default_ws_client) || _default_ws_client[] === nothing
        _default_ws_client[] = GatewayWSClient()
    end
    _default_ws_client[]
end

function connect!()
    connect!(default_ws_client())
end

function disconnect!()
    disconnect!(default_ws_client())
end

function is_connected()
    is_connected(default_ws_client())
end

function send_subscribe(exchange_id::String, method::String; kwargs...)
    send_subscribe(default_ws_client(), exchange_id, method; kwargs...)
end

function send_unsubscribe(subscription_id::String)
    send_unsubscribe(default_ws_client(), subscription_id)
end

end # module WSClient