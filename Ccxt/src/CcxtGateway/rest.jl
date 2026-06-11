module Rest

using HTTP
using JSON3
using OrderedCollections
using ..Types

export GatewayClient, build_url
export start_exchange, stop_exchange, exchange_has
export call_exchange
export list_exchanges, exchange_info, exchange_ready, server_info, memory_usage, ping, spawn_gateway
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
    _ensure_gateway_running()
    resp = make_request(client, method, path, exchange_id; query, body)
    get_data(resp)
end

function api_call(client::GatewayClient, method::String, path::String; 
    query=nothing, body=nothing)
    _ensure_gateway_running()
    resp = make_request(client, method, path; query, body)
    get_data(resp)
end

function call_exchange(client::GatewayClient, exchange_id::String, ccxt_method::String; 
    query=nothing, body=nothing)
    path = "/exchanges/$exchange_id/$ccxt_method"
    req_method = body !== nothing ? "POST" : (ccxt_method ∈ ("createOrder", "cancelOrder", "withdraw")) ? "POST" : "GET"
    api_call(client, req_method, path; query, body)
end

const _started_exchanges = Dict{String, Float64}()

function start_exchange(client::GatewayClient, exchange_id::String; 
    exchange_name=exchange_id, api_key="", secret="", password="", uid="", sandbox=false)
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
    if sandbox
        query["sandbox"] = "true"
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

function fetch_exchange_metadata(client::GatewayClient, exchange_id::String)
    result = api_call(client, "GET", "/exchanges/$exchange_id/metadata")
    result
end

function fetch_exchange_metadata(exchange_id::String)
    fetch_exchange_metadata(default_client(), exchange_id)
end

function list_exchanges(client::GatewayClient)
    api_call(client, "GET", "/admin/exchanges")
end

function exchange_info(client::GatewayClient, exchange_id::String)
    api_call(client, "GET", "/exchanges/$exchange_id/status")
end

function exchange_ready(client::GatewayClient, exchange_id::String)
    try
        resp = make_request(client, "GET", "/exchanges/$exchange_id/has")
        return resp.status == 200
    catch
        return false
    end
end

function exchange_ready(exchange_id::String)
    exchange_ready(default_client(), exchange_id)
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
const _gateway_initialized = Ref(false)
const _gateway_init_lock = ReentrantLock()

function _check_gateway_up()
    if isassigned(_gateway_pid) && _gateway_pid[] !== nothing
        try
            run(pipeline(`kill -0 $(_gateway_pid[])`; stderr=devnull))
            return true
        catch
            _gateway_pid[] = nothing
        end
    end
    if isfile(REST_GATEWAY_PIDFILE)
        pid = try
            parse(Int, split(strip(read(REST_GATEWAY_PIDFILE, String)))[1])
        catch
            nothing
        end
        if pid !== nothing
            try
                run(pipeline(`kill -0 $pid`; stderr=devnull))
                _gateway_pid[] = pid
                return true
            catch
            end
        end
    end
    try
        return ping(GatewayClient(; timeout=2.0))
    catch
        return false
    end
end

function _ensure_gateway_running()
    get(ENV, "CCXT_GATEWAY_DISABLE", "") == "true" && return nothing
    _gateway_initialized[] && return nothing
    lock(_gateway_init_lock) do
        _gateway_initialized[] && return nothing
        if !_check_gateway_up()
            spawn_gateway()
            _check_gateway_up() || return nothing
        end
        _gateway_initialized[] = true
    end
end

# Paths for PID and lock files — computed relative to this file's location
function _rest_gateway_dir()
    normpath(joinpath(dirname(dirname(dirname(@__DIR__))), "ccxt-gateway", ".cache"))
end
const REST_GATEWAY_DIR = _rest_gateway_dir()
const REST_GATEWAY_PIDFILE = joinpath(REST_GATEWAY_DIR, "ccxt_gateway.pid")
const REST_GATEWAY_LOCKFILE = joinpath(REST_GATEWAY_DIR, "ccxt_gateway.lock")

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
        if isfile(p)
            @debug "Found $relpath at $p"
            return p
        end
        @debug "Searching for $relpath: $p — not found"
    end
    error("File not found: $relpath (searched: $(join(unique(paths), ", ")))")
end

function _check_python_works(python_exe::String)
    try
        run(pipeline(`$python_exe -c "import decimal; import asyncio; import json"`; stderr=devnull))
        return true
    catch e
        @debug "Python check failed for $python_exe: $e"
        return false
    end
end

function _fix_venv_pyvenv_cfg(venv_cfg::String)
    system_python = _find_system_python()
    system_python === nothing && return false
    system_bin_dir = dirname(system_python)
    try
        cfg = read(venv_cfg, String)
        new_home = "home = $system_bin_dir"
        if occursin(r"^home\s*="m, cfg)
            cfg = replace(cfg, r"^home\s*=.*"m => new_home)
        else
            cfg = new_home * "\n" * cfg
        end
        write(venv_cfg, cfg)
        @debug "Fixed pyvenv.cfg home -> $system_bin_dir"
        return true
    catch e
        @debug "Failed to fix pyvenv.cfg: $e"
        return false
    end
end

function _ensure_gateway_venv(gateway_dir::String)
    venv_dir = normpath(joinpath(gateway_dir, ".venv"))
    venv_python = normpath(joinpath(venv_dir, "bin", "python"))
    venv_cfg = normpath(joinpath(venv_dir, "pyvenv.cfg"))
    # Fast path: venv is fully intact AND functional
    if isfile(venv_python) && _check_python_works(venv_python)
        @debug "Venv python found and verified at $venv_python"
        return venv_python
    end
    # Venv exists but Python is broken — try repair
    if isdir(venv_dir) && isfile(venv_cfg)
        @debug "Venv exists at $venv_dir but Python is broken; attempting repair..."
        # First check: pyvenv.cfg might point to a broken uv-managed Python
        # Try fixing it to point to the system Python instead
        if _fix_venv_pyvenv_cfg(venv_cfg) && _check_python_works(venv_python)
            @debug "Venv repaired via pyvenv.cfg fix at $venv_python"
            return venv_python
        end
        # Second check: symlink might be broken — repair symlink
        _repair_venv_python(venv_dir)
        if isfile(venv_python) && _check_python_works(venv_python)
            @debug "Venv repaired via symlink fix at $venv_python"
            return venv_python
        end
    end
    # No valid venv — recreate
    @debug "Recreating absent venv at $venv_dir..."
    if islink(venv_dir)
        @debug "Removing stale symlink at $venv_dir (target: $(readlink(venv_dir)))"
        try rm(venv_dir) catch end
    end
    try
        @debug "Trying uv venv..."
        run(`uv venv --clear $venv_dir`)
        run(`uv pip install --python $venv_dir --quiet -e $gateway_dir`)
        @debug "Venv created with uv successfully"
        if !_check_python_works(venv_python)
            @debug "uv venv produced broken Python, falling back to python3..."
            error("uv Python is broken")
        end
    catch e
        @debug "uv approach failed ($e), falling back to python3 -m venv..."
        try rm(venv_dir; recursive=true) catch end
        try
            run(`python3 -m venv $venv_dir`)
            run(`$venv_dir/bin/pip install --quiet --no-input -e $gateway_dir`)
            @debug "Venv created with python3 successfully"
        catch e2
            @debug "python3 -m venv failed ($e2), trying without ensurepip..."
            try rm(venv_dir; recursive=true) catch end
            run(`python3 -m venv --without-pip $venv_dir`)
            run(`uv pip install --python $venv_dir --quiet -e $gateway_dir`)
            @debug "Venv created with python3 (--without-pip) + uv pip install"
        end
    end
    isfile(venv_python) || error("Failed to create venv at $venv_dir")
    _check_python_works(venv_python) || error("Created venv at $venv_dir has broken Python (system python3 may be missing modules)")
    return venv_python
end

function _repair_venv_python(venv_dir::String)
    # Remove venv-internal symlinks to avoid loops (e.g. python3 -> python)
    # but keep the main `python` symlink if it points to a valid real file.
    for name in ["python3", "python3.11", "python3.12", "python3.13", "python3.14"]
        candidate = normpath(joinpath(venv_dir, "bin", name))
        if islink(candidate)
            target = try readlink(candidate) catch; "" end
            if startswith(target, "python") || !isfile(candidate)
                try rm(candidate) catch end
            end
        end
    end
    # If `python` exists, check it resolves to a working interpreter
    python_link = normpath(joinpath(venv_dir, "bin", "python"))
    if isfile(python_link) && !islink(python_link)
        return  # Real python binary exists — nothing to repair
    end
    if islink(python_link)
        target = try readlink(python_link) catch; "" end
        # If it points to a relative name within the venv, it may be stale
        if startswith(target, "python")
            try rm(python_link) catch end
        elseif isfile(python_link)
            return  # Absolute symlink to a working python — OK
        end
    end
    # Try each candidate — must be a REAL file (not a venv-internal symlink)
    for candidate in ["python3", "python3.11", "python3.12", "python3.13", "python3.14"]
        exe = normpath(joinpath(venv_dir, "bin", candidate))
        if isfile(exe) && !islink(exe)
            @debug "Found valid python at $exe; symlinking bin/python -> $candidate"
            try rm(python_link) catch end
            try symlink(candidate, python_link) catch end
            return
        end
    end
    # No valid python in venv — try system
    system_python = _find_system_python()
    if system_python !== nothing
        @debug "Symlinking bin/python -> $system_python"
        try rm(python_link) catch end
        try symlink(system_python, python_link) catch end
    end
end

function _find_system_python()
    for candidate in ["python3", "python3.14", "python3.13", "python3.12", "python3.11"]
        exe = Sys.which(candidate)
        exe !== nothing && return exe
    end
    return nothing
end

function spawn_gateway(; python_path=nothing, gateway_path="ccxt_gateway.main")
    @debug "spawn_gateway: starting"
    # Check if gateway is already running
    if isassigned(_gateway_pid) && _gateway_pid[] !== nothing && _gateway_pid[] > 1
        pid = _gateway_pid[]
        try
            run(pipeline(`kill -0 $pid`; stderr=devnull))
            @debug "spawn_gateway: gateway already running with PID $pid"
            return pid
        catch
            @debug "spawn_gateway: tracked PID $pid is stale"
        end
    end
    
    # Kill any process found in the pidfile (stale gateway)
    pidfile = REST_GATEWAY_PIDFILE
    if isfile(pidfile)
        try
            content = strip(read(pidfile, String))
            pid_str = split(content)[1]
            stale_pid = parse(Int, pid_str)
            @debug "spawn_gateway: killing stale PID $stale_pid from pidfile"
            run(pipeline(`kill $stale_pid`; stderr=devnull))
            @debug "Killed stale gateway PID $stale_pid"
            sleep(2)
        catch e
            @debug "spawn_gateway: failed to kill stale PID: $e"
        end
        try rm(pidfile; force=true) catch end
    end
    
    # Find the daemon script
    @debug "spawn_gateway: locating daemon_gateway.py..."
    daemon_script = _find_gateway_file("daemon_gateway.py")
    @debug "Found gateway daemon at $daemon_script"
    gateway_dir = dirname(daemon_script)
    @debug "Gateway directory: $gateway_dir"
    
    # Find the venv python (may be a broken symlink if cache is shared)
    @debug "spawn_gateway: ensuring venv..."
    python_cmd = _ensure_gateway_venv(gateway_dir)
    @debug "Using python: $python_cmd"
    
    # Run the daemon script — capture output so user can see errors
    @debug "spawn_gateway: truncating gateway log..."
    try open("/tmp/gateway.log", "w") do f; end catch end
    @debug "spawn_gateway: running: $python_cmd $daemon_script"
    run(pipeline(`$python_cmd $daemon_script`, stdout="/tmp/gateway.log", stderr="/tmp/gateway.log"), wait=false)
    @debug "spawn_gateway: daemon process launched"
    
    # Wait for pidfile AND gateway responsiveness
    pidfile = REST_GATEWAY_PIDFILE
    seen_log_lines = 0
    for attempt in 1:10
        sleep(1)
        # Dump new gateway log lines
        if isfile("/tmp/gateway.log")
            lines = readlines("/tmp/gateway.log")
            for i in (seen_log_lines + 1):length(lines)
                @debug "gateway: $(lines[i])"
            end
            seen_log_lines = length(lines)
        end
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
    # Try graceful shutdown via HTTP endpoint first (works across containers)
    try
        client = default_client()
        api_call(client, "POST", "/admin/shutdown")
        sleep(2)
    catch e
        @debug "stop_gateway: HTTP shutdown failed: $e"
    end
    
    # Fallback: kill by PID (works for local gateway)
    if isassigned(_gateway_pid) && _gateway_pid[] !== nothing && _gateway_pid[] > 1
        pid = _gateway_pid[]
        try
            run(pipeline(`kill $pid`; stderr=devnull))
            sleep(1)
        catch
        end
        _gateway_pid[] = nothing
    end
    empty!(_started_exchanges)
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

# Convenience methods: omit GatewayClient, use default_client()
(server_info)(; kwargs...) = server_info(default_client(); kwargs...)
(memory_usage)(; kwargs...) = memory_usage(default_client(); kwargs...)
(ping)(; kwargs...) = ping(default_client(); kwargs...)
(list_exchanges)(; kwargs...) = list_exchanges(default_client(); kwargs...)
exchange_info(exchange_id::String) = exchange_info(default_client(), exchange_id)
start_exchange(exchange_id::String; kwargs...) = start_exchange(default_client(), exchange_id; kwargs...)
stop_exchange(exchange_id::String) = stop_exchange(default_client(), exchange_id)
exchange_has(exchange_id::String; kwargs...) = exchange_has(default_client(), exchange_id; kwargs...)
restart_exchange(exchange_id::String) = restart_exchange(default_client(), exchange_id)
call_exchange(exchange_id::String, ccxt_method::String; kwargs...) = call_exchange(default_client(), exchange_id, ccxt_method; kwargs...)

const RestClient = GatewayClient()

end # module Rest
