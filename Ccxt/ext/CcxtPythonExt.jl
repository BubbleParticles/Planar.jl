"""Python extension for Ccxt - loaded only when Python is available"""
module CcxtPythonExt

using Ccxt
using Python
using Misc: DATA_PATH, Misc
using Misc.ConcurrentCollections: ConcurrentDict
using Misc.Lang: @lget!, Option
using Misc.DocStringExtensions
using Python: pynew, pyisnone, islist, isdict
using Python.PythonCall: pyisnull, pycopy!, pybuiltins
using Python: py_except_name

# Export Python-specific functions (with _python suffix)
export ccxt, ccxt_ws, isccxterror_python, choosefunc_python, upgrade_python, ccxt_exchange_python

@doc "The ccxt python module reference"
const ccxt = Ref{Option{Py}}(nothing)

@doc "The ccxt.pro (websockets) python module reference"
const ccxt_ws = Ref{Option{Py}}(nothing)

@doc "Ccxt exception names"
const ccxt_errors = Set{String}()

@doc """ Checks if the ccxt object is initialized.
$(TYPEDSIGNATURES)

This function checks if the global variable `ccxt` is initialized by checking if it's not `nothing` and not `null` in the Python context.
"""
function isinitialized_python()
    val = ccxt[]
    !isnothing(val) && !pyisnull(val)
end

@doc """ Determines if an exception is a ccxt error.

$(TYPEDSIGNATURES)

This function checks if the exception is a ccxt-related error by looking for common ccxt error indicators in the error message.
"""
function isccxterror_python(err)
    err_str = string(err)
    ccxt_keywords = ["ccxt", "exchange", "symbol", "invalid", "not supported", "authentication"]
    return any(kw -> occursin(kw, lowercase(err_str)), ccxt_keywords)
end

const MARKETS_PATH = joinpath(DATA_PATH, "markets")

@doc """ Chooses a function based on the provided parameters and executes it.

$(TYPEDSIGNATURES)

This function selects a function based on the provided exception, suffix, and inputs. It then executes the chosen function with the provided inputs and keyword arguments. The function can handle multiple types of inputs and can execute multiple functions concurrently if necessary.
"""
function _multifunc_python(exc, suffix, hasinputs=false)
    py = exc.py
    fname = "fetch" * suffix * "sWs"
    if issupported(exc, fname) || begin
        fname = "fetch" * suffix * "s"
        issupported(exc, fname)
    end
        getproperty(py, fname), :multi
    else
        fname = "fetch" * suffix * "Ws"
        if !issupported(exc, fname)
            fname = "fetch" * suffix
        end
        @assert issupported(exc, fname) "Exchange $(exc.name) does not support $fname"
        @assert hasinputs "Single function needs inputs."
        getproperty(py, fname), :single
    end
end

function _out_as_input_python(inputs, data; elkey=nothing)
    if islist(data)
        if length(data) == length(inputs)
            Dict(i => v for (v, i) in zip(data, inputs))
        else
            @assert !isnothing(elkey) "Functions returned a list, but element key not provided."
            Dict(v[elkey] => v for v in data)
        end
    elseif isdict(data)
        Dict(i => data[i] for i in inputs if haskey(data, i))
    else
        Dict(i => data for i in inputs)
    end
end

function choosefunc_python(exc, suffix, inputs::AbstractVector; elkey=nothing, kwargs...)
    hasinputs = length(inputs) > 0
    f, kind = _multifunc_python(exc, suffix, hasinputs)
    if hasinputs
        if kind == :multi
            function multi_func()
                args = isempty(inputs) ? () : (inputs,)
                data = pyfetch(f, args...; kwargs...)
                _out_as_input_python(inputs, data; elkey)
            end
        else
            function single_func()
                out = Dict{eltype(inputs),Union{Task,Py}}()
                try
                    for i in inputs
                        out[i] = pytask(f(i); kwargs...)
                    end
                    for (i, task) in out
                        out[i] = fetch(task)
                    end
                catch e
                    @sync for v in values(out)
                        if v isa Task && !istaskdone(v)
                            pycancel(v)
                        end
                    end
                    e isa PyException && rethrow(e)
                    filter!(p -> p isa Task, out)
                end
                _out_as_input_python(inputs, out; elkey)
            end
        end
    else
        args = isempty(inputs) ? () : (inputs,)
        default_func() = pyfetch(f, args...; kwargs...)
    end
end

function choosefunc_python(exc, suffix, inputs...; kwargs...)
    choosefunc_python(exc, suffix, [inputs...]; kwargs...)
end

@doc """ Upgrades the ccxt library to the latest version.

$(TYPEDSIGNATURES)

This function upgrades the ccxt library to the latest version available. It checks the current version of the ccxt library, and if a newer version is available, it upgrades the library using pip.
"""
function upgrade_python()
    @eval begin
        version = pyimport("ccxt").__version__
        using Python.PythonCall.C.CondaPkg: CondaPkg
        try
            CondaPkg.add_pip("ccxt"; version=">$version")
        catch
            # if the version is latest than we have to adjust
            # the version to GTE
            CondaPkg.add_pip("ccxt"; version=">=$version")
        end
    end
    Python.pyimport("ccxt").__version__
end

end # module CcxtPythonExt
