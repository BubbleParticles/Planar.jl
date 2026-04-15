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
    # When using stub CCXT, avoid ccxt.pro (websocket/pro) classes since they
    # may spawn background coroutines (ccxt.pro) that call internal network
    # methods and raise NotSupported. Prefer async_support in stub mode.
    if get(ENV, "PLANAR_USE_STUB_CCXT", "") != ""
        async = ccxtasync()
        exc_cls = getproperty(async, name)
    else
        ws = ccxtws()
        exc_cls = if hasproperty(ws, name)
            getproperty(ws, name)
        else
            async = ccxtasync()
            getproperty(async, name)
        end
    end
    # Instantiate exchange class (may be replaced by patched subclass below)
    inst = nothing
    # If environment variable set, try to instantiate a patched subclass via stubex
    if get(ENV, "PLANAR_USE_STUB_CCXT", "") != ""
        try
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
                # Attempt to let the patcher create a patched subclass instance
                try
                    inst = pycall(sp.make_patched_instance, Any, exc_cls, params)
                catch
                    # fallback: normal instantiation then instance-level patch
                    inst = isnothing(params) ? exc_cls() : exc_cls(params)
                    try
                        pycall(sp.patch_exchange, Any, inst)
                    catch e
                        @warn "ccxt: stub patch failed" e
                    end
                end
            catch e
                @warn "ccxt: stub patch import failed" e
            end
        catch e
            @warn "ccxt: stub check failed" e
        end
    end
    # Final fallback to normal instantiation if not patched above
    if isnothing(inst)
        inst = isnothing(params) ? exc_cls() : exc_cls(params)
    end
    inst
end

ccxt_exchange_names() = ccxtasync().exchanges

export ccxt_exchange_names
