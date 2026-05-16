module Rest

using HTTP
using JSON3
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

mutable struct GatewayClient
    host::String
    port::Int
    base_url::String
    timeout::Float64
    use_ssl::Bool
    
    function GatewayClient(;
        host::String=DEFAULT_HOST,
        port::Int=DEFAULT_PORT,
        timeout::Float64=30.0,
        use_ssl::Bool=true,
    )
        if use_ssl
            new(host, port, "https://$host:$port", timeout, true)
        else
            new(host, port, "http://$host:$port", timeout, false)
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
        kw[:require_ssl_verification] = false
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

function _find_gateway_file(relpath::String)
    paths = String[]
    try
        p = normpath(joinpath(dirname(pathof(Ccxt)), "..", "..", "ccxt-gateway", relpath))
        push!(paths, p)
    catch
    end
    try
        p = normpath(joinpath(dirname(Base.active_project()), "..", "ccxt-gateway", relpath))
        push!(paths, p)
    catch
    end
    env_dir = get(ENV, "CCXT_GATEWAY_DIR", "")
    if !isempty(env_dir)
        push!(paths, normpath(joinpath(env_dir, relpath)))
    end
    for base in (homedir(), homedir() * "/dev/Planar.jl", "/project", "/var/home/fra/dev/Planar.jl", pwd())
        push!(paths, normpath(joinpath(base, "ccxt-gateway", relpath)))
    end
    for p in paths
        isfile(p) && return p
    end
    error("File not found: $relpath (searched: $(join(unique(paths), ", ")))")
end

function _ensure_gateway_venv(gateway_dir::String)
    venv_python = normpath(joinpath(gateway_dir, ".venv", "bin", "python"))
    isfile(venv_python) && return venv_python
    # Symlink exists but is broken, or venv doesn't exist — recreate it
    venv_dir = normpath(joinpath(gateway_dir, ".venv"))
    @info "Recreating broken/absent venv at $venv_dir..."
    try
        run(`uv venv $venv_dir`)
        run(`uv pip install --python $venv_dir -e $gateway_dir`)
    catch
        # Fallback to system python3 if uv is not available
        run(`python3 -m venv $venv_dir`)
        run(`$venv_dir/bin/pip install -e $gateway_dir`)
    end
    isfile(venv_python) || error("Failed to create venv at $venv_dir")
    return venv_python
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
    
    # Kill any process found in the pidfile (stale gateway)
    pidfile = "/tmp/ccxt_gateway.pid"
    if isfile(pidfile)
        try
            content = strip(read(pidfile, String))
            pid_str = split(content)[1]
            stale_pid = parse(Int, pid_str)
            run(`kill $stale_pid`)
            @info "Killed stale gateway PID $stale_pid"
            sleep(2)
        catch
        end
        try rm(pidfile; force=true) catch end
    end
    
    # Find the daemon script
    daemon_script = _find_gateway_file("daemon_gateway.py")
    gateway_dir = dirname(daemon_script)
    
    # Find the venv python (may be a broken symlink if cache is shared)
    python_cmd = _ensure_gateway_venv(gateway_dir)
    
    # Run the daemon script
    # Truncate log so we only see this attempt
    try open("/tmp/gateway.log", "w") do f; end catch end
    run(`$python_cmd $daemon_script`, wait=false)
    
    # Wait for pidfile AND gateway responsiveness
    pidfile = "/tmp/ccxt_gateway.pid"
    for attempt in 1:10
        sleep(1)
        if isfile(pidfile)
            content = strip(read(pidfile, String))
            pid_str = split(content)[1]
            pid = parse(Int, pid_str)
            _gateway_pid[] = pid
            @debug "spawn: attempt $attempt, pidfile found (PID $pid)"
            # Use a lightweight non-SSL ping to avoid SSL handshake issues
            if ping(GatewayClient(; timeout=2.0))
                return pid
            end
            @debug "spawn: PID $pid exists but gateway not responding yet"
        else
            @debug "spawn: attempt $attempt, no pidfile yet"
        end
    end
    
    # Dump gateway log for diagnostics
    logfile = "/tmp/gateway.log"
    if isfile(logfile)
        loglines = readlines(logfile)
        last_lines = max(1, length(loglines) - 20)
        @warn "Gateway log (last 20 lines):\n$(join(loglines[last_lines:end], "\n"))"
    end
    
    error("Gateway failed to start (not responsive after 10s)")
end

function stop_gateway()
    if isassigned(_gateway_pid) && _gateway_pid[] !== nothing && _gateway_pid[] > 1
        pid = _gateway_pid[]
        try
            run(`kill $pid`)
            sleep(1)
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
