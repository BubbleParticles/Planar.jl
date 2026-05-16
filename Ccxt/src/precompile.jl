# Ccxt module precompile workload
using PrecompileTools
@setup_workload begin
    @compile_workload begin
        _init()
    end
end

# Stop all processes spawned during precompilation
stop_gateway()
try rm("/tmp/ccxt_gateway.pid"; force=true) catch end
try rm("/tmp/ccxt_gateway.lock"; force=true) catch end