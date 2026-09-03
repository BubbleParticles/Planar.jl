# Watchers precompile workloads
# This file is included conditionally when JULIA_PRECOMP is set

using PlanarCore.Misc.Lang: Lang, @preset, @precomp, @m_str, @ignore

if get(ENV, "CCXT_GATEWAY_DISABLE", "") != "true"
@preset let
    # Precompile core watcher functionality
    @info "PRECOMP: Watchers core"
    
    # Create a simple watcher to trigger compilation
    w = watcher(Any, "precomp_test"; 
        start=false, 
        load=false, 
        process=false, 
        flush=false,
        fetch_interval=Second(1),
        buffer_capacity=10,
        view_capacity=100,
    )
    
    # Test start/stop cycle
    start!(w)
    @precomp begin
        try
            fetch!(w)
        catch e
            @debug "PRECOMP: fetch! skipped" exception=(e, catch_backtrace())
        end
        try
            process!(w)
        catch e
            @debug "PRECOMP: process! skipped" exception=(e, catch_backtrace())
        end
        try
            flush!(w; force=true, sync=true)
        catch e
            @debug "PRECOMP: flush! skipped" exception=(e, catch_backtrace())
        end
    end
    stop!(w)
    try close(w) catch e @debug "PRECOMP: close skipped" exception=(e, catch_backtrace()) end
    _closeall()
    
    # Explicitly shut down Rocket scheduler if possible
    try
        # Rocket doesn't expose a direct shutdown, but we can try to let GC clean up
        GC.gc()
        GC.safepoint()
    catch
    end
    
    @info "PRECOMP: Watchers done"
end
end