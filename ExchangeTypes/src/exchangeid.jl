@doc "All possible exchanges that can be instantiated by ccxt."
const exchangeIds = Symbol[]
const _ccxt_exchange_set = Set{Symbol}()

function _populate_exchange_set!()
    isempty(_ccxt_exchange_set) || return
    prev = Set{Symbol}()
    try
        for name in ccxt_exchange_names()
            id = Symbol(name)
            if id ∉ prev
                push!(exchangeIds, id)
                push!(prev, id)
                push!(_ccxt_exchange_set, id)
            end
        end
    catch
    end
end

@doc """A structure for handling Exchange IDs in CCXT.

$(FIELDS)

This structure is used to manage Exchange IDs in the CCXT library.
"""
struct ExchangeID{I}
    function ExchangeID(sym::Symbol=Symbol())
        sym == Symbol() && return new{sym}()
        _populate_exchange_set!()
        if sym ∉ exchangeIds
            push!(exchangeIds, sym)
        end
        new{sym}()
    end
    function ExchangeID(name::String)
        ExchangeID(Symbol(name))
    end
    function ExchangeID{sym}() where {sym}
        ExchangeID(sym)
    end
end

const EIDType = Type{<:ExchangeID}
Base.getproperty(::T, ::Symbol) where {T<:ExchangeID} = T.parameters[1]
Base.nameof(::ExchangeID{T}) where {T} = T
Base.show(io::IO, id::ExchangeID) = begin
    write(io, "ExchangeID(:")
    write(io, string(id.sym))
    write(io, ")")
end
Base.convert(::Type{<:AbstractString}, id::ExchangeID) = string(id.sym)
Base.convert(::Type{Symbol}, id::ExchangeID) = id.sym
Base.Symbol(::Type{<:ExchangeID{T}}) where {T} = T
Base.Symbol(id::ExchangeID) = id.sym
Base.string(id::ExchangeID) = string(id.sym)
function Base.display(
    ids::T
) where {T<:Union{AbstractVector{ExchangeID},AbstractSet{ExchangeID}}}
    s = String[]
    for id in ids
        push!(s, string(id.sym))
    end
    Base.display(s)
end
Base.Broadcast.broadcastable(q::ExchangeID) = Ref(q)
import Base.==
==(id::ExchangeID, s::Symbol) = Base.isequal(nameof(id), s)

@doc "Create an ExchangeID instance from a symbol."
exchangeid(sym::Symbol) = ExchangeID(sym)
@doc "Create an ExchangeID instance from a string."
exchangeid(name::String) = ExchangeID(Symbol(name))
@doc "Return the given ExchangeID instance."
exchangeid(id::ExchangeID) = id
@doc "Union type of many exchange ids (from `Symbol` arguments)"
eids(ids...) = Union{((ExchangeID{i}) for i in ids)...}
