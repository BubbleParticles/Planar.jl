# Stream handler stubs for non-Python mode
# Without Python websocket streams, watchers fall back to polling.
# These stubs are only reached when watch functions are unavailable via CcxtGateway.
function stream_handler(coro_func, f_push)
    (; stop=Returns(nothing), push=f_push)
end
start_handler!(h) = nothing
stop_handler!(h) = nothing
