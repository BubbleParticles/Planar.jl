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
const GATEWAY_PIDFILE = "/tmp/ccxt_gateway.pid"

function _with_gateway_lock(f::Function)
    mkpidlock(GATEWAY_PIDFILE) do
        f()
    end
end

function _check_existing_gateway()
    if !isfile(GATEWAY_PIDFILE)
        return _check_gateway_running()
    end
    pid = try
        parse(Int, strip(read(GATEWAY_PIDFILE, String)))
    catch
        return _check_gateway_running()
    end
    try
        run(`kill -0 $pid`)
        CcxtGateway._gateway_pid[] = pid
        return true
    catch
        @warn "Stale gateway PID file found (PID $pid), removing..."
        try rm(GATEWAY_PIDFILE) catch end
        return _check_gateway_running()
    end
end

function _check_gateway_running()
    try
        client = CcxtGateway.GatewayClient(; timeout=2.0)
        if CcxtGateway.ping(client)
            @info "Gateway found running on $(client.host):$(client.port)"
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
            @info "CcxtGateway already running (PID $(CcxtGateway._gateway_pid[]))"
            return
        end
        client = CcxtGateway.GatewayClient()
        if !CcxtGateway.ping(client)
            @info "CcxtGateway not responding, spawning..."
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
        rm(GATEWAY_PIDFILE * ".lock"; force=true)
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