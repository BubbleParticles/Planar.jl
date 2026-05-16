module Rest

using HTTP
using JSON3
using MbedTLS
using OrderedCollections
using ..Types

export GatewayClient, build_url
export start_exchange, stop_exchange, exchange_has
export call_exchange
export list_exchanges, exchange_info, server_info, memory_usage, ping, spawn_gateway
export gateway_pid, stop_gateway, restart_gateway
export set_http_get!, set_http_post!, set_http_delete!

# Injectable HTTP functions (for testing/mocking)
const _http_get = Ref{Function}(HTTP.get)
const _http_post = Ref{Function}(HTTP.post)
const _http_delete = Ref{Function}(HTTP.delete)

export set_http_get!, set_http_post!, set_http_delete!

set_http_get!(f::Function) = (_http_get[] = f)
set_http_post!(f::Function) = (_http_post[] = f)
set_http_delete!(f::Function) = (_http_delete[] = f)

const DEFAULT_HOST = "localhost"
const DEFAULT_PORT = 8999
const CERT_DIR = joinpath(@__DIR__, "..", "..", "certs")
const DEFAULT_CRT = joinpath(CERT_DIR, "server.crt")
const DEFAULT_KEY = joinpath(CERT_DIR, "server.key")

_load_ssl_config(crt::String, key::String) = MbedTLS.SSLConfig(crt, key)

mutable struct GatewayClient
    host::String
    port::Int
    base_url::String
    timeout::Float64
    use_ssl::Bool
    ssl_config::Union{MbedTLS.SSLConfig, Nothing}
    
    function GatewayClient(;
        host::String=DEFAULT_HOST,
        port::Int=DEFAULT_PORT,
        timeout::Float64=30.0,
        use_ssl::Bool=true,
        ssl_cert::Union{String, Nothing}=nothing,
        ssl_key::Union{String, Nothing}=nothing,
    )
        if use_ssl
            crt = ssl_cert !== nothing ? ssl_cert : DEFAULT_CRT
            key = ssl_key !== nothing ? ssl_key : DEFAULT_KEY
            ssl_cfg = isfile(crt) && isfile(key) ? _load_ssl_config(crt, key) : nothing
            new(host, port, "https://$host:$port", timeout, true, ssl_cfg)
        else
            new(host, port, "http://$host:$port", timeout, false, nothing)
        end
    end
end

Base.show(io::IO, client::GatewayClient) = print(io, "GatewayClient($(client.host):$(client.port))")

function build_url(client::GatewayClient, path::String)
    base = rstrip(client.base_url, '/')
    if startswith(path, "/")
        base * path
    else
        base * "/" * path
    end
end

function make_request(client::GatewayClient, method::String, path::String; 
    query=nothing, body=nothing, kwargs...)
    url = build_url(client, path)
    
    headers = Pair{String, String}[]
    push!(headers, "Content-Type" => "application/json")
    push!(headers, "Accept" => "application/json")
    
    kw = Dict{Symbol, Any}()
    t = Int(round(get(kwargs, :timeout, client.timeout)))
    kw[:timeout] = t
    kw[:readtimeout] = t
    kw[:connect_timeout] = t
    if client.use_ssl
        kw[:ssl] = true
        if client.ssl_config !== nothing
            kw[:sslconfig] = client.ssl_config
        else
            kw[:require_ssl_verification] = false
        end
    end
    
    if query !== nothing
        kw[:query] = query
    end
    
    if body !== nothing
        kw[:body] = JSON3.write(body)
    end
    
    if method == "GET"
        resp = _http_get[](url; kw...)
    elseif method == "POST"
        resp = _http_post[](url; headers=headers, kw...)
    elseif method == "DELETE"
        if body !== nothing
            resp = _http_delete[](url; headers=headers, kw...)
        else
            resp = _http_delete[](url; kw...)
        end
    else
        error("Unsupported method: $method")
    end
    
    resp
end

function make_request(client::GatewayClient, method::String, path::String, exchange_id::String; 
    query=nothing, body=nothing)
    full_path = replace(path, "{exchange_id}" => exchange_id)
    make_request(client, method, full_path; query, body)
end

function check_response(resp::HTTP.Response)::GatewayResponse
    parsed = parse_response(resp)
    if has_error(parsed)
        err_msg = parsed.error !== nothing ? parsed.error : parsed.error_code
        error("Gateway error: $err_msg")
    end
    parsed
end

function get_data(resp::HTTP.Response)
    parsed = check_response(resp)
    get_result(parsed)
end

function api_call(client::GatewayClient, method::String, path::String, exchange_id::String; 
    query=nothing, body=nothing)
    resp = make_request(client, method, path, exchange_id; query, body)
    get_data(resp)
end

function api_call(client::GatewayClient, method::String, path::String; 
    query=nothing, body=nothing)
    resp = make_request(client, method, path; query, body)
    get_data(resp)
end

function call_exchange(client::GatewayClient, exchange_id::String, ccxt_method::String; 
    query=nothing, body=nothing)
    path = "/exchanges/$exchange_id/$ccxt_method"
    req_method = (ccxt_method ∈ ("createOrder", "cancelOrder", "withdraw")) ? "POST" : "GET"
    api_call(client, req_method, path; query, body)
end

const _started_exchanges = Dict{String, Float64}()

function start_exchange(client::GatewayClient, exchange_id::String; 
    exchange_name=exchange_id, api_key="", secret="", password="", uid="")
    if haskey(_started_exchanges, exchange_id)
        return Dict("status" => "already_started", "exchange_id" => exchange_id, "started_at" => _started_exchanges[exchange_id])
    end
    query = Dict{String, String}()
    query["exchange_name"] = exchange_name
    if !isempty(api_key)
        query["api_key"] = api_key
    end
    if !isempty(secret)
        query["secret"] = secret
    end
    if !isempty(password)
        query["password"] = password
    end
    if !isempty(uid)
        query["uid"] = uid
    end
    result = api_call(client, "POST", "/exchanges/$exchange_id"; query=query)
    _started_exchanges[exchange_id] = time()
    result
end

function stop_exchange(client::GatewayClient, exchange_id::String)
    delete!(_started_exchanges, exchange_id)
    api_call(client, "DELETE", "/exchanges/$exchange_id")
end

function fetch_exchange_has(client::GatewayClient, exchange_id::String)
    result = api_call(client, "GET", "/exchanges/$exchange_id/has")
    result
end

function fetch_exchange_has(exchange_id::String)
    fetch_exchange_has(default_client(), exchange_id)
end

function list_exchanges(client::GatewayClient)
    api_call(client, "GET", "/admin/exchanges")
end

function exchange_info(client::GatewayClient, exchange_id::String)
    api_call(client, "GET", "/exchanges/$exchange_id/status")
end

function server_info(client::GatewayClient)
    api_call(client, "GET", "/admin/info")
end

function ping(client::GatewayClient; timeout::Float64=3.0)
    try
        resp = make_request(client, "GET", "/ping"; timeout=timeout)
        return resp.status == 200
    catch e
        false
    end
end

function fetch_exchange_names(client::GatewayClient)
    api_call(client, "GET", "/admin/exchange_names")
end

function fetch_exchange_names()
    fetch_exchange_names(default_client())
end

function memory_usage(client::GatewayClient)
    api_call(client, "GET", "/admin/memory")
end

function restart_exchange(client::GatewayClient, exchange_id::String)
    resp = make_request(client, "POST", "/admin/exchanges/{exchange_id}/restart", exchange_id)
    get_data(resp)
end

const _ccxt_errors = Ref{Vector{String}}(String[])

function list_errors(client::GatewayClient)
    api_call(client, "GET", "/admin/errors")
end

function list_errors()
    list_errors(default_client())
end

function get_ccxt_errors(client::GatewayClient)
    if isempty(_ccxt_errors[])
        try
            errors = list_errors(client)
            if errors isa Vector{String}
                _ccxt_errors[] = errors
            end
        catch
        end
    end
    _ccxt_errors[]
end

function get_ccxt_errors()
    get_ccxt_errors(default_client())
end

function isccxterror(err::Exception)
    err_str = string(err)
    isempty(_ccxt_errors[]) && get_ccxt_errors()
    ccxt_keywords = ["ccxt", "exchange", "symbol", "invalid", "not supported", "authentication"]
    any(kw -> occursin(kw, lowercase(err_str)), ccxt_keywords)
end

function check_ccxt_update(client::GatewayClient)
    api_call(client, "GET", "/admin/update/check")
end

function check_ccxt_update()
    check_ccxt_update(default_client())
end

function upgrade_ccxt(client::GatewayClient)
    api_call(client, "POST", "/admin/update/ccxt")
end

function upgrade_ccxt()
    upgrade_ccxt(default_client())
end

const _default_client = Ref{GatewayClient}()
const _gateway_pid = Ref{Union{Int, Nothing}}(nothing)

function default_client()
    if !isassigned(_default_client)
        _default_client[] = GatewayClient()
    end
    _default_client[]
end

function spawn_gateway(; python_path=nothing, gateway_path="ccxt_gateway.main")
    # Check if gateway is already running
    if isassigned(_gateway_pid) && _gateway_pid[] !== nothing && _gateway_pid[] > 1
        pid = _gateway_pid[]
        try
            run(`kill -0 $pid`)
            return pid
        catch
        end
    end
    
    # Find the daemon script
    daemon_script = joinpath(@__DIR__, "..", "..", "..", "ccxt-gateway", "daemon_gateway.py")
    if !isfile(daemon_script)
        error("Gateway daemon script not found: $daemon_script")
    end
    
    # Find the venv python
    venv_python = joinpath(@__DIR__, "..", "..", "..", "ccxt-gateway", ".venv", "bin", "python")
    python_cmd = isfile(venv_python) ? venv_python : "python3"
    
    # Run the daemon script
    run(`$python_cmd $daemon_script`, wait=false)
    sleep(3)
    
    # Read the PID from the pidfile
    pidfile = "/tmp/ccxt_gateway.pid"
    if isfile(pidfile)
        pid = parse(Int, strip(read(pidfile, String)))
        _gateway_pid[] = pid
        return pid
    end
    
    error("Gateway failed to start (no pidfile at $pidfile)")
end

function stop_gateway()
    if isassigned(_gateway_pid) && _gateway_pid[] !== nothing && _gateway_pid[] > 1
        pid = _gateway_pid[]
        try
            run(`kill $pid`)
            sleep(1)
            # Kill exchange subprocesses spawned by this gateway
            for (ex_id, _) in _started_exchanges
                stop_exchange(ex_id)
            end
        catch
        end
        _gateway_pid[] = nothing
    end
end

function gateway_pid()
    if !isassigned(_gateway_pid) || _gateway_pid[] === nothing
        try
            return spawn_gateway()
        catch
            nothing
        end
    end
    _gateway_pid[]
end

function restart_gateway()
    stop_gateway()
    sleep(1)
    spawn_gateway()
end

function set_default_client!(client::GatewayClient)
    _default_client[] = client
end

for fname in (:call_exchange, :start_exchange, :stop_exchange, :exchange_has, 
    :list_exchanges, :exchange_info, :server_info, :memory_usage, :restart_exchange, :ping)
    @eval begin
        ($fname)(args...; kwargs...) = ($fname)(default_client(), args...; kwargs...)
    end
end

const RestClient = GatewayClient()

end # module Rest
