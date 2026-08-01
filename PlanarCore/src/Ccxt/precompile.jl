# Ccxt module precompile workload
using PrecompileTools
if get(ENV, "CCXT_GATEWAY_DISABLE", "") != "true"
    @setup_workload begin
        @compile_workload begin
            _init()
        end
    end
    # NOTE: Do NOT stop_gateway() here - Exchanges precompile manages the full gateway lifecycle
    # and shuts it down at the very end of precompilation
    # try rm(Ccxt.GATEWAY_PIDFILE; force=true) catch end
    # try rm(Ccxt.GATEWAY_LOCKFILE; force=true) catch end
end# Precompile workload removed to avoid gateway startup issues during compilation
nothing
