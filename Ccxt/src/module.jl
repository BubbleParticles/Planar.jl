# Ccxt main module - Python is now optional (loaded via extension)

using Misc: DATA_PATH, Misc
using Misc.ConcurrentCollections: ConcurrentDict
using Misc.Lang: @lget!, Option
using Misc.DocStringExtensions

# Use CcxtGateway for HTTP-based ccxt communication
include("CcxtGateway/CcxtGateway.jl")
using .CcxtGateway

const MARKETS_PATH = joinpath(DATA_PATH, "markets")
const GATEWAY_PIDFILE = "/tmp/ccxt_gateway.pid"

function _check_existing_gateway()
    if !isfile(GATEWAY_PIDFILE)
        return false
    end
    pid = try
        parse(Int, strip(read(GATEWAY_PIDFILE, String)))
    catch
        return false
    end
    try
        run(`kill -0 $pid`)
        CcxtGateway._gateway_pid[] = pid
        return true
    catch
        @warn "Stale gateway PID file found (PID $pid), removing..."
        try rm(GATEWAY_PIDFILE) catch end
        return false
    end
end

function _init()
    mkpath(MARKETS_PATH)
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

function _doinit()
    _init()
end

# Include exchange functions (Gateway-only, Python functions moved to ext/)
include("exchange_funcs.jl")

# Export CcxtGateway functions
export CcxtGateway

# Python-specific exports are in the extension (ext/CcxtPythonExt.jl)
# ccxt_python, ccxt_ws, choosefunc_python, upgrade_python, ccxt_exchange_python, etc.