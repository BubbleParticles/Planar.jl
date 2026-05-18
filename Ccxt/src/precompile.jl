# Ccxt module precompile workload
using PrecompileTools
@setup_workload begin
    @compile_workload begin
        _init()
    end
end

# Stop all processes spawned during precompilation
stop_gateway()
try rm(Ccxt.GATEWAY_PIDFILE; force=true) catch end
try rm(Ccxt.GATEWAY_LOCKFILE; force=true) catch end