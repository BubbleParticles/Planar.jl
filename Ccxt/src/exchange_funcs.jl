@doc "Check if the key `k` is in the dictionary `has` and return its boolean value."
_issupported(has::Py, k) = k in has && Bool(has[k])
@doc "Check if the key `k` is supported in the `exc.py.has` dictionary."
issupported(exc, k) = _issupported(exc.py.has, k)

_lazypy(ref, mod) = begin
    if isassigned(ref)
        r = ref[]
        if isnothing(r)
            ref[] = pyimport(mod)
        elseif pyisnull(r)
            pycopy!(r, pyimport(mod))
            r
        else
            r
        end
    else
        ref[] = pyimport(mod)
    end
end

ccxtws() = _lazypy(ccxt_ws, "ccxt.pro")
ccxtasync() = _lazypy(ccxt, "ccxt.async_support")

# @doc "Instantiate a ccxt exchange class matching name."
@doc """Instantiate a CCXT exchange.

$(TYPEDSIGNATURES)

This function creates an instance of a CCXT exchange. It checks if the exchange is available in the WebSocket (ws) module, otherwise it looks in the asynchronous (async) module. If optional parameters are provided, they are passed to the exchange constructor.
"""
function ccxt_exchange(name::Symbol, params=nothing; kwargs...)
    @debug "Instantiating Exchange $name..."
    ws = ccxtws()
    exc_cls = if hasproperty(ws, name)
        getproperty(ws, name)
    else
        async = ccxtasync()
        getproperty(async, name)
    end
    inst = isnothing(params) ? exc_cls() : exc_cls(params)
    # If environment variable set, try to patch the python exchange instance with stubs
    try
        if get(ENV, "PLANAR_USE_STUB_CCXT", "") != ""
            # add local stub_exchanges package path to sys.path so python can import stubex
            stub_path = get(ENV, "PLANAR_CCXT_STUB_PATH", normpath(joinpath(@__DIR__, "..", "..", "stub_exchanges")))
            try
                sys = pyimport("sys")
                Python.pyfetch(sys.path.insert, 0, stub_path)
            catch
                try
                    Python.pyfetch(sys.path.append, stub_path)
                catch
                end
            end
            try
                sp = pyimport("stubex.patch")
                pycall(sp.patch_exchange, Any, inst)
            catch e
                @warn "ccxt: stub patch failed" e
            end
        end
    catch e
        @warn "ccxt: stub check failed" e
    end
    inst
end

ccxt_exchange_names() = ccxtasync().exchanges

export ccxt_exchange_names
