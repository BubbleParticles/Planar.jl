# Ccxt module precompile workload
using PrecompileTools
if get(ENV, "CCXT_GATEWAY_DISABLE", "") != "true"
    @setup_workload begin
        @compile_workload begin
            # Keep the ccxt-gateway venv in sync with uv.lock before Ccxt
            # precompiles — a stale venv (e.g. missing uvicorn) breaks the
            # gateway that later precompile workloads (Exchanges) spawn.
            # `_sync_gateway_venv` runs `uv sync` in the project dir and falls
            # back to `_ensure_gateway_venv` if uv is unavailable.
            CcxtGateway.Rest._sync_gateway_venv()
            _init()
        end
    end
    # NOTE: Do NOT stop_gateway() here - Exchanges precompile manages the full gateway lifecycle
    # and shuts it down at the very end of precompilation
    # try rm(Ccxt.GATEWAY_PIDFILE; force=true) catch end
    # try rm(Ccxt.GATEWAY_LOCKFILE; force=true) catch end
end
