module Python

abstract type Py end

struct StreamHandler
    stop::Function
    push::Function
end
StreamHandler(; stop=Base.Returns(nothing), push=Base.Returns(nothing)) = StreamHandler(stop, push)

module pybuiltins
    const None = nothing
    const True = true
    const False = false
    const float = Float64
    const int = Int
    const str = String
    const bool = Bool
    const list = Vector
    const dict = Dict
    const Exception = Base.Exception
    const BaseException = Base.Exception
end

py_except_name(e) = string(typeof(e))

isdict(x) = x isa Dict
islist(x) = x isa Union{AbstractVector, Tuple}

pyisnone(x) = isnothing(x)
pyisnotnone(x) = !isnothing(x)

pyisinstance(x, t) = x isa t

pytofloat(x) = Float64(x)
pytobool(x) = Bool(x)
pytoint(x) = Int(x)

pydict(; kwargs...) = Dict(kwargs...)
pydict(x::Dict) = x
pydict(x::Pair...) = Dict(x...)

pylist(x) = collect(x)
pylist() = Any[]

pyfetch(f, args...; kwargs...) = error("pyfetch called but Python is not available")

export pybuiltins, py_except_name, isdict, islist, pyisnone, pyisnotnone
export pyisinstance, pytofloat, pytobool, pytoint, pydict, pylist, pyfetch
export @py, pyconvert, StreamHandler, Py

function pyconvert end

pynew(x) = x

end
