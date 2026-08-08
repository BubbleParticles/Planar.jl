# Ccxt module precompile workload
using PrecompileTools
if get(ENV, "CCXT_GATEWAY_DISABLE", "") != "true"
    @setup_workload begin
        @compile_workload begin
            # `_init` is lazy — it does NOT spawn/install the gateway at
            # precompilation time (that would require network during
            # `Pkg.add`). The gateway Python env is resolved and installed on
            # first exchange use via `_ensure_gateway_running` (which sets
            # install=false under Base.generating_output).
            _init()
        end
    end
    # NOTE: Do NOT stop_gateway() here - Exchanges precompile manages the full gateway lifecycle
    # and shuts it down at the very end of precompilation
    # try rm(Ccxt.GATEWAY_PIDFILE; force=true) catch end
    # try rm(Ccxt.GATEWAY_LOCKFILE; force=true) catch end
end

