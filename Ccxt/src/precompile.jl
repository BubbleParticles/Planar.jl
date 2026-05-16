# Ccxt module precompile workload
using PrecompileTools
@setup_workload begin
    @compile_workload begin
        _init()
    end
end

# Stop the gateway spawned during precompilation
stop_gateway()