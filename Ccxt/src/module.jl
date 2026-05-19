# Ccxt main module - Python is now optional (loaded via extension)

using FileWatching
using Misc: DATA_PATH, Misc
using Misc.ConcurrentCollections: ConcurrentDict
using Misc.Lang: @lget!, Option
using Misc.DocStringExtensions

# Use CcxtGateway for HTTP-based ccxt communication
include("CcxtGateway/CcxtGateway.jl")
using .CcxtGateway

const MARKETS_PATH = joinpath(DATA_PATH, "markets")

@doc "Gateway runtime directory (PID file, lock file)."
const GATEWAY_DIR = joinpath(dirname(dirname(@__DIR__)), "ccxt-gateway", ".cache")
const GATEWAY_PIDFILE = joinpath(GATEWAY_DIR, "ccxt_gateway.pid")
const GATEWAY_LOCKFILE = joinpath(GATEWAY_DIR, "ccxt_gateway.lock")

function _with_gateway_lock(f::Function)
    mkpidlock(GATEWAY_LOCKFILE) do
        f()
    end
end

function _check_existing_gateway()
    if !isfile(GATEWAY_PIDFILE)
        return _check_gateway_running()
    end
    pid = try
        content = strip(read(GATEWAY_PIDFILE, String))
        parse(Int, split(content)[1])
    catch
        return _check_gateway_running()
    end
    try
        run(pipeline(`kill -0 $pid`; stderr=devnull))
        CcxtGateway.Rest._gateway_pid[] = pid
        return true
    catch
        @debug "Stale gateway PID file found (PID $pid), removing..."
        try rm(GATEWAY_PIDFILE) catch end
        return _check_gateway_running()
    end
end

function _check_gateway_running()
    try
        client = CcxtGateway.GatewayClient(; timeout=2.0)
        if CcxtGateway.ping(client)
            @debug "Gateway found running on $(client.host):$(client.port)"
            return true
        end
    catch
    end
    false
end

function _init()
    mkpath(MARKETS_PATH)
    _with_gateway_lock() do
        if _check_existing_gateway()
            @debug "CcxtGateway already running (PID $(CcxtGateway.Rest._gateway_pid[]))"
            return
        end
        client = CcxtGateway.GatewayClient()
        if !CcxtGateway.ping(client)
            @debug "CcxtGateway not responding, spawning..."
            try
                CcxtGateway.spawn_gateway()
            catch e
                @warn "Failed to spawn CcxtGateway: $e"
            end
        end
    end
end

function _doinit()
    _init()
end

function _atexit_cleanup()
    CcxtGateway.stop_gateway()
    try
        isdefined(Main, :ExchangeTypes) && Main.ExchangeTypes._closeall()
    catch
    end
    try
        rm(GATEWAY_LOCKFILE; force=true)
    catch
    end
end

atexit(_atexit_cleanup)

# Include exchange functions (Gateway-only, Python functions moved to ext/)
include("exchange_funcs.jl")

# Export CcxtGateway functions
export CcxtGateway

# Python-specific exports are in the extension (ext/CcxtPythonExt.jl)
# ccxt_python, ccxt_ws, choosefunc_python, upgrade_python, ccxt_exchange_python, etc.