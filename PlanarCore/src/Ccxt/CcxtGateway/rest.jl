module Rest

using HTTP
using JSON3
using OrderedCollections
using ..Types
import TOML
using Base: ReentrantLock

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
 query=nothing, body=nothing, timeout=nothing, kwargs...)
 url = build_url(client, path)

 headers = Pair{String, String}[]
 push!(headers, "Content-Type" => "application/json")
 push!(headers, "Accept" => "application/json")

 kw = Dict{Symbol, Any}()
 t = Int(round(get(kwargs, :timeout, timeout !== nothing ? timeout : client.timeout)))
kw[:timeout] = t
kw[:closeimmediately] = true
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
 query=nothing, body=nothing, timeout=nothing)
 full_path = replace(path, "{exchange_id}" => exchange_id)
 make_request(client, method, full_path; query, body, timeout=timeout)
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
 query=nothing, body=nothing, timeout=nothing)
 _ensure_gateway_running()
 resp = make_request(client, method, path, exchange_id; query, body, timeout=timeout)
 get_data(resp)
end

function api_call(client::GatewayClient, method::String, path::String; 
 query=nothing, body=nothing, timeout=nothing)
 _ensure_gateway_running()
 resp = make_request(client, method, path; query, body, timeout=timeout)
 get_data(resp)
end

function call_exchange(client::GatewayClient, exchange_id::String, ccxt_method::String; 
 query=nothing, body=nothing, timeout::Union{Nothing,Float64}=nothing)
 path = "/exchanges/$exchange_id/$ccxt_method"
 req_method = body !== nothing ? "POST" : (ccxt_method ∈ ("createOrder", "cancelOrder", "withdraw", "setLeverage", "setMarginMode", "setPositionMode", "setSandboxMode", "set_api_key", "enableRateLimit", "timeout", "rateLimit")) ? "POST" : "GET"
 if timeout !== nothing && body !== nothing
     body = copy(body)
     K = keytype(body)
     body[K(:_timeout)] = Float64(timeout)
 end
 api_call(client, req_method, path; query, body, timeout=timeout)
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

const _gateway_use_ssl = Ref(true)  # set by _check_gateway_up or spawn_gateway
_gateway_use_ssl_on_change() = (isassigned(_default_client) && (_default_client[] = GatewayClient(; use_ssl=_gateway_use_ssl[])))
const _default_client = Ref{GatewayClient}()

# Returns the shared GatewayClient, (re)starting the gateway and syncing the SSL
# flag on first use. `_ensure_gateway_running` is a no-op during precompilation
# (Base.generating_output) so this never triggers an install/Pkg.add.
function default_client()
    if !isassigned(_default_client)
        _ensure_gateway_running()
        _default_client[] = GatewayClient(; use_ssl=_gateway_use_ssl[])
    else
        _ensure_gateway_running()
        if _default_client[].use_ssl != _gateway_use_ssl[]
            _default_client[] = GatewayClient(; use_ssl=_gateway_use_ssl[])
        end
    end
    _default_client[]
end
const _gateway_pid = Ref{Union{Int, Nothing}}(nothing)
const _gateway_init_lock = ReentrantLock()
const _gateway_initialized = Ref(false)

function _check_gateway_up()
    # Check if tracked PID is alive AND responds to HTTPS
    lock(_gateway_init_lock) do
        if isassigned(_gateway_pid) && _gateway_pid[] !== nothing
            pid = _gateway_pid[]
            try
                run(pipeline(`kill -0 $pid`; stderr=devnull))
                if ping(GatewayClient(; use_ssl=true, timeout=5.0))
                    return true
                end
                @debug "Tracked PID $pid is alive but not HTTPS — treating as stale"
                _gateway_pid[] = nothing
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
                    if ping(GatewayClient(; use_ssl=true, timeout=5.0))
                        _gateway_pid[] = pid
                        return true
                    end
                    @debug "Pidfile PID $pid is alive but not HTTPS — treating as stale"
                catch
                end
            end
        end
        # Try HTTPS first, then fall back to HTTP (gateway may be running without SSL).
        # Set _gateway_use_ssl so default_client() creates the right client.
        for (use_ssl, label) in [(true, "HTTPS"), (false, "HTTP")]
            try
                if ping(GatewayClient(; use_ssl=use_ssl, timeout=5.0))
                    @debug "_check_gateway_up: $label ping succeeded"
                    _gateway_use_ssl[] = use_ssl
                    _gateway_use_ssl_on_change()
                    return true
                end
            catch
            end
        end
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
            _check_gateway_up() || error("Failed to start ccxt-gateway")
        end
        _gateway_initialized[] = true
    end
    return nothing
end

# Cache dir for runtime gateway files (PID file, SSL cert). Mirrors the
# resolution in ccxt_gateway.daemon_gateway so the PID file the daemon writes
# is where Julia looks it up. Set CCXT_GATEWAY_CACHE_DIR to override.
function _rest_gateway_dir()
    env = get(ENV, "CCXT_GATEWAY_CACHE_DIR", "")
    !isempty(env) && return env
    base = get(ENV, "XDG_CACHE_HOME",
        Sys.iswindows() ? get(ENV, "LOCALAPPDATA", homedir()) :
        joinpath(homedir(), ".cache"))
    joinpath(base, "ccxt-gateway")
end
const REST_GATEWAY_DIR = _rest_gateway_dir()
mkpath(REST_GATEWAY_DIR)
const REST_GATEWAY_PIDFILE = joinpath(REST_GATEWAY_DIR, "ccxt_gateway.pid")
const REST_GATEWAY_LOCKFILE = joinpath(REST_GATEWAY_DIR, "ccxt_gateway.lock")

_venv_python(venv_dir::String) =
    Sys.iswindows() ? joinpath(venv_dir, "Scripts", "python.exe") :
    joinpath(venv_dir, "bin", "python")

# Read `[ccxt-gateway] venv = "path"` from the active/strategy Project.toml.
# Resolved relative to that Project.toml directory. Returns the venv dir as an
# absolute path, or `nothing`.
function _configured_venv_dir(start::AbstractString=abspath(pwd()))
    candidates = String[]
    ap = Base.active_project()
    isempty(ap) || push!(candidates, ap)
    cur = start
    while true
        p = joinpath(cur, "Project.toml")
        isfile(p) && push!(candidates, p)
        parent = dirname(cur)
        parent == cur && break
        cur = parent
    end
    for p in unique(candidates)
        toml = try TOML.parsefile(p) catch; continue end
        gw = get(toml, "ccxt-gateway", nothing)
        (gw isa Dict) || continue
        v = get(gw, "venv", nothing)
        (v isa AbstractString && !isempty(v)) || continue
        return isabspath(v) ? v : normpath(joinpath(dirname(p), v))
    end
    return nothing
end

# Ordered venv directories to probe for a working gateway Python.
function _local_venv_dirs()
    dirs = String[]
    c = _configured_venv_dir()
    c !== nothing && push!(dirs, c)
    ap = Base.active_project()
    if !isempty(ap)
        pd = dirname(ap)
        push!(dirs, joinpath(pd, ".venv"))
        push!(dirs, joinpath(pd, "venv"))
    end
    gw = get(ENV, "CCXT_GATEWAY_VENV", "")
    !isempty(gw) && push!(dirs, gw)
    gwdir = get(ENV, "CCXT_GATEWAY_DIR", "")
    isempty(gwdir) || push!(dirs, joinpath(gwdir, ".venv"))
    unique!(dirs)
end

# Find a Python interpreter able to run the gateway. If no existing venv / system
# Python has ccxt-gateway installed and `install` is true, install it (uv
# preferred, pip fallback). Set `install=false` to probe without side effects
# (e.g. during precompilation).
#
# When `_local_gateway_source()` finds the in-repo `ccxt-gateway` source tree
# (dev mode, e.g. running from the git clone), that tree takes priority: probes
# only accept an interpreter whose `ccxt_gateway` import resolves into the
# local tree, and installs are editable so local Python edits are picked up on
# the next gateway restart. In released installs (no local tree found), any
# working ccxt-gateway is accepted and installs come from PyPI. A relative
# source path is honored, resolved against cwd.
function _find_gateway_python(; install::Bool=true)
    local_source = _local_gateway_source()
    for vd in _local_venv_dirs()
        py = _venv_python(vd)
        isfile(py) || continue
        _check_gateway_python(py) || continue
        (local_source === nothing || _python_uses_local_source(py, local_source)) && (return py)
    end
    sys = _find_system_python()
    if sys !== nothing && _check_gateway_python(sys) &&
            (local_source === nothing || _python_uses_local_source(sys, local_source))
        return sys
    end
    install || error(
        "ccxt-gateway is not installed. Set `CCXT_GATEWAY_DIR` to a checked-out " *
        "ccxt-gateway tree, declare `[ccxt-gateway] venv = \"...\"` in your " *
        "strategy Project.toml, install the `ccxt-gateway` pip package, or " *
        "let Planar install it on first exchange use.")
    return _install_gateway_python()
end

# True when `python_exe`'s `ccxt_gateway` package resolves into `local_source`
# (the in-repo tree) — i.e. an editable install of the dev checkout rather than
# a site-packages copy from PyPI.
function _python_uses_local_source(python_exe::String, local_source::String)
    try
        out = readchomp(pipeline(
            `$python_exe -c "import ccxt_gateway, os; print(os.path.realpath(ccxt_gateway.__file__))"`;
            stderr=devnull))
        path = normpath(strip(out))
        # `abspath` resolves a relative source path against cwd, matching how
        # uv/pip would resolve `--editable <relative>` at install time.
        startswith(path, normpath(abspath(local_source)))
    catch
        false
    end
end

# True when `dir` is the ccxt-gateway package source tree: it carries a
# pyproject.toml whose `[project] name` identifies it as the gateway package.
# A directory merely *named* `ccxt-gateway` is not sufficient.
function _is_ccxt_gateway_tree(dir::AbstractString)
    pp = joinpath(dir, "pyproject.toml")
    isfile(pp) || return false
    try
        toml = TOML.parsefile(pp)
        prj = get(toml, "project", nothing)
        return prj isa Dict && get(prj, "name", nothing) == "ccxt-gateway"
    catch
        return false
    end
end

# Locate the in-repo `ccxt-gateway` source tree (Planar.jl/ccxt-gateway).
# Installing from this path (rather than the PyPI name, which is only available
# after a release publish) lets the gateway be installed offline / pre-release
# from the repository checkout that ships alongside the Julia code. Returns the
# verified tree path if found (identity checked via its pyproject.toml), else
# `nothing` to install the `ccxt-gateway` pip package from PyPI.
function _local_gateway_source()
    # Walk up from this file (PlanarCore/src/Ccxt/CcxtGateway/rest.jl):
    # `dirname` x5 lands at the repo root that contains `ccxt-gateway/`.
    # `abspath` guards against the module being loaded via a relative include
    # path (normal loads resolve `@__FILE__` to an absolute path already).
    cur = dirname(dirname(dirname(dirname(dirname(abspath(@__FILE__))))))
    while true
        cand = joinpath(cur, "ccxt-gateway")
        _is_ccxt_gateway_tree(cand) && return cand
        parent = dirname(cur)
        parent == cur && break
        cur = parent
    end
    return nothing
end

function _install_gateway_python()
    # Venv target: explicit CCXT_GATEWAY_VENV override > Project.toml
    # `[ccxt-gateway] venv` > active project's .venv. Matches the probe order
    # in `_local_venv_dirs` so an env-pinned venv is reused, not recreated.
    env_venv = get(ENV, "CCXT_GATEWAY_VENV", "")
    vd = isempty(env_venv) ? _configured_venv_dir() : env_venv
    if vd === nothing
        ap = Base.active_project()
        pd = isempty(ap) ? abspath(pwd()) : dirname(ap)
        vd = joinpath(pd, ".venv")
    end
    mkpath(vd)
    py = _venv_python(vd)

    # Create the venv: uv venv (preferred), else python3 -m venv.
    venv_ok = false
    if Sys.which("uv") !== nothing
        try
            rm(vd; recursive=true, force=true)
            run(`uv venv $vd`)
            venv_ok = isfile(py)
        catch e
            @debug "uv venv failed ($e), falling back to python3 -m venv"
        end
    end
    if !venv_ok
        sys = _find_system_python()
        sys === nothing && error("No Python on PATH to create a venv for ccxt-gateway")
        try
            run(`$sys -m venv $vd`)
            venv_ok = isfile(py)
        catch e
            error("python3 venv creation failed: $e")
        end
    end
    # Install the gateway: when a verified in-repo source tree is present (dev
    # mode) install it EDITABLE so local Python edits are live on the next
    # gateway restart; otherwise install the `ccxt-gateway` pip package from
    # PyPI.
    install_source = _local_gateway_source()
    install_args = install_source === nothing ? ("ccxt-gateway",) : ("--editable", install_source)
    if Sys.which("uv") !== nothing
        try
            run(`uv pip install --python $py --quiet $install_args`)
        catch e
            @debug "uv pip install failed ($e), falling back to pip"
            run(`$py -m pip install --quiet $install_args`)
        end
    else
        run(`$py -m pip install --quiet $install_args`)
    end

    _check_gateway_python(py) ||
        error("ccxt-gateway installed into $vd but Python check failed (missing uvicorn or ccxt_gateway)")
    @info "Installed ccxt-gateway into $vd"
    return py
end

# Verify `python_exe` runs a working CPython interpreter.
function _check_python_works(python_exe::String)
    try
        run(pipeline(`$python_exe -c "import decimal; import asyncio; import json"`; stderr=devnull))
        return true
    catch e
        @debug "Python check failed for $python_exe: $e"
        return false
    end
end

# True when `python_exe` can import the gateway runtime (uvicorn + ccxt_gateway).
function _check_gateway_python(python_exe::String)
    _check_python_works(python_exe) || return false
    try
        run(pipeline(`$python_exe -c "import uvicorn, ccxt_gateway"`; stdout=devnull, stderr=devnull))
        return true
    catch e
        @debug "Gateway deps missing for $python_exe (uvicorn/ccxt_gateway): $e"
        return false
    end
end

# _check_python_works / _check_gateway_python / _find_system_python /
# _kill_process_on_port below — shared by the gateway-env resolution above.
function _find_system_python()
    for candidate in ["python3", "python3.14", "python3.13", "python3.12", "python3.11"]
        exe = Sys.which(candidate)
        exe !== nothing && return exe
    end
    return nothing
end

function _kill_process_on_port(port::Int)
    try
        pid_str = readchomp(pipeline(`lsof -ti :$port`; stderr=devnull))
        if !isempty(strip(pid_str))
            stale_pid = parse(Int, strip(pid_str))
            @debug "Killing process $stale_pid on port $port"
            run(pipeline(`kill $stale_pid`; stderr=devnull))
            sleep(1)
        end
    catch
        @debug "No process found on port $port or lsof unavailable"
    end
end

function spawn_gateway(; python_path=nothing, gateway_path="ccxt_gateway.main")
    @debug "spawn_gateway: starting"
    lock(_gateway_init_lock) do
        # Check if gateway is already running (must respond to HTTPS ping)
        if isassigned(_gateway_pid) && _gateway_pid[] !== nothing && _gateway_pid[] > 1
            pid = _gateway_pid[]
            try
                run(pipeline(`kill -0 $pid`; stderr=devnull))
                # Verify the gateway responds to HTTPS (not an old HTTP-only gateway)
                if ping(GatewayClient(; use_ssl=true, timeout=5.0))
                    @debug "spawn_gateway: gateway already running with PID $pid (HTTPS)"
                    return pid
                end
                @debug "spawn_gateway: tracked PID $pid is alive but not HTTPS — treating as stale"
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
        # Before killing, check if a gateway is already running on the port
        # (no pidfile and no tracked PID — orphaned from an earlier session)
        for use_ssl in (true, false)
            try
                if ping(GatewayClient(; use_ssl=use_ssl, timeout=3.0))
                    @debug "spawn_gateway: gateway already running on port $DEFAULT_PORT (SSL=$use_ssl)"
                    _gateway_use_ssl[] = use_ssl
                    _gateway_use_ssl_on_change()
                    pid_str = try
                        strip(readchomp(pipeline(`lsof -ti :$DEFAULT_PORT`; stderr=devnull)))
                    catch
                        ""
                    end
                    if !isempty(pid_str)
                        pid = parse(Int, split(pid_str)[1])
                        _gateway_pid[] = pid
                        @debug "spawn_gateway: adopting existing PID $pid"
                        return pid
                    else
                        @debug "spawn_gateway: could not determine PID, but gateway is alive — no-op"
                        return 0
                    end
                end
            catch
            end
        end

        # Locate a Python interpreter with ccxt-gateway installed, installing
        # it from PyPI (uv preferred, pip fallback) on first use. Skipped
        # during precompilation (Base.generating_output) to avoid network on
        # `Pkg.add`; the gateway is started lazily on first exchange use anyway.
        @debug "spawn_gateway: resolving gateway Python..."
        allow_install = !Base.generating_output()
        python_cmd = _find_gateway_python(; install=allow_install)
        @info "Planar will use ccxt-gateway via $(python_cmd)"

        # Run the daemon module — capture output so user can see errors.
        @debug "spawn_gateway: truncating gateway log..."
        try open("/tmp/gateway.log", "w") do f; end catch end
        # Pass idle timeout env to gateway subprocess
        if haskey(ENV, "CCXT_GATEWAY_IDLE_TIMEOUT_MINUTES")
            withenv("CCXT_GATEWAY_IDLE_TIMEOUT_MINUTES" => ENV["CCXT_GATEWAY_IDLE_TIMEOUT_MINUTES"]) do
                run(pipeline(`$python_cmd -m ccxt_gateway.daemon_gateway`, stdout="/tmp/gateway.log", stderr="/tmp/gateway.log"), wait=false)
            end
        else
            run(pipeline(`$python_cmd -m ccxt_gateway.daemon_gateway`, stdout="/tmp/gateway.log", stderr="/tmp/gateway.log"), wait=false)
        end
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
                # Try HTTPS first, then HTTP
                for use_ssl in (true, false)
                    if ping(GatewayClient(; use_ssl=use_ssl, timeout=5.0))
                        _gateway_use_ssl[] = use_ssl
                        _gateway_use_ssl_on_change()
                        return pid
                    end
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
            err_msg = join(loglines[last_lines:end], "\n  ")
            @error "Gateway failed to start. Last 20 log lines:\n  $err_msg"
        end
        error("Failed to spawn ccxt-gateway within 10 seconds")
    end
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
    _gateway_initialized[] = false
    empty!(_started_exchanges)
end

function gateway_pid()
    lock(_gateway_init_lock) do
        if !isassigned(_gateway_pid) || _gateway_pid[] === nothing
            try
                return spawn_gateway()
            catch
                return nothing
            end
        end
        _gateway_pid[]
    end
end

function restart_gateway()
    lock(_gateway_init_lock) do
        stop_gateway()
        sleep(1)
        spawn_gateway()
    end
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
end
