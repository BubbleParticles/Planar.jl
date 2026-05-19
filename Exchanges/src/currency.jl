using .Misc: MM, toprecision, DFT
using .Instruments: AbstractCash, atleast!, Cash
import Instruments: value, addzero!
Instruments.@importcash!
import Base: ==, +, -, ÷, /, *
import .Misc: gtxzero, ltxzero, approxzero, ZERO

@doc "The cache for currencies which lasts for 1 hour by exchange."
const currenciesCache1Hour = safettl(ExchangeID, Any, Hour(1))
@doc "This lock is only used during currency construction."
const currency_lock = ReentrantLock()

@doc "Convert a value to a float number."
function to_float(v, T::Type{<:AbstractFloat}=DFT)
    something(_tonum(v, T), zero(T))
end
to_float(v::Number, ::Type{<:AbstractFloat}=DFT) = v

function _tonum(v, T=DFT)
    v === nothing && return nothing
    v isa Number && return convert(T, v)
    try
        parse(T, string(v))
    catch
        nothing
    end
end

@doc "Convert a value to a number."
function to_num(v)
    v === nothing && return 0.0
    v isa Integer && return Int(v)
    v isa AbstractFloat && return DFT(v)
    v isa String && return something(tryparse(DFT, v), 0.0)
    v isa AbstractVector && !isempty(v) && return to_num(first(v))
    0.0
end

@doc "Returns the limits, precision, and fees for a currency as a named tuple."
function _lpf(exc, cur)
    local limits, precision, fees
    if cur === nothing
        limits = (; min=1e-8, max=1e8)
        precision = 8
        fees = zero(DFT)
    else
        cur_dict = cur isa AbstractDict ? Dict(pairs(cur)) : cur
        limits = let l = get(cur_dict, "limits", nothing)
            if l === nothing
                (min=1e-8, max=1e8)
            elseif haskey(l, "amount")
                MM{DFT}((to_float(l["amount"]["min"]), to_float(l["amount"]["max"])))
            else
                (min=1e-8, max=1e8)
            end
        end
        precision = let p = get(cur_dict, "precision", nothing)
            if p === nothing
                8
            else
                to_num(p)
            end
        end
        fees = to_float(get(cur_dict, "fee", nothing))
    end
    (; limits, precision, fees)
end

@doc "Returns the currency from the exchange if found."
function _cur(exc, sym)
    sym_str = uppercase(string(sym))
    curs = @lget! currenciesCache1Hour exc.id begin
        v = try
            client = default_client()
            name = string(exc.id)
            currencies = call_exchange(client, name, "currencies")
            currencies isa AbstractDict ? currencies : nothing
        catch e
            @debug "Failed to fetch currencies for $(exc.id): $e"
            nothing
        end
        v
    end
    curs === nothing ? nothing : get(Dict(pairs(curs)), sym_str, nothing)
end

@doc "A `CurrencyCash` contextualizes a `Cash` instance w.r.t. an exchange.
Operations are rounded to the currency precision.

$(FIELDS)
"
struct CurrencyCash{C<:Cash,E<:ExchangeID} <: AbstractCash
    cash::C
    limits::MM{DFT}
    precision::T where {T<:Real}
    fees::DFT
    sandbox::Bool
    @doc """Create a CurrencyCash object.

    $(TYPEDSIGNATURES)
    """
    function CurrencyCash(id::Type{<:ExchangeID}, cash_type::Type{<:Cash}, v; sandbox=false, account="")
        @lock currency_lock begin
            exc = getexchange!(Symbol(id); sandbox, account)
            c = cash_type(v)
            lpf = _lpf(exc, _cur(exc, nameof(c)))
            Instruments.cash!(c, toprecision(c.value, lpf.precision))
            new{cash_type,id}(c, lpf..., issandbox(exc))
        end
    end
    function CurrencyCash(exc::Exchange, sym, v=0.0)
        @lock currency_lock begin
            cur = _cur(exc, sym)
            cur === nothing && @debug "$sym not found on $(exc.name) (using defaults)"
            c = Cash(sym, v)
            lpf = _lpf(exc, cur)
            Instruments.cash!(c, toprecision(c.value, lpf.precision))
            new{typeof(c),typeof(exc.id)}(c, lpf..., issandbox(exc))
        end
    end
end

function CurrencyCash{C,E}(v; sandbox=false) where {C<:Cash,E<:ExchangeID}
    CurrencyCash(E, C, v; sandbox)
end

function CurrencyCash(c::CurrencyCash{C,E}, v) where {C<:Cash,E<:ExchangeID}
    CurrencyCash(E, C, v; sandbox=c.sandbox)
end

@doc "The currency cash as a number."
value(cc::CurrencyCash) = value(cc.cash)
Base.getproperty(c::CurrencyCash, s::Symbol) =
    if s == :value
        getfield(_cash(c), :value)[]
    elseif s == :id
        nameof(_cash(c))
    else
        getfield(c, s)
    end
function Base.isapprox(cc::C, v::N) where {C<:CurrencyCash,N<:Number}
    isapprox(value(cc), v; atol=_atol(cc))
end
Base.isapprox(v::N, cc::C) where {C<:CurrencyCash,N<:Number} = isapprox(cc, v)
Base.setproperty!(::CurrencyCash, ::Symbol, v) = error("CurrencyCash is private.")
Base.zero(c::CurrencyCash) = zero(c.cash)
Base.zero(::Type{<:CurrencyCash{C}}) where {C} = zero(C)
function Base.iszero(c::CurrencyCash{Cash{S,T}}) where {S,T}
    isapprox(value(c), zero(T); atol=_atol(c))
end

function Base.show(io::IO, c::CurrencyCash{<:Cash,E}) where {E<:ExchangeID}
    write(io, "$(c.cash) (on $(E.parameters[1]))")
end
Base.hash(c::CurrencyCash, args...) = hash(_cash(c), args...)
Base.nameof(c::CurrencyCash) = nameof(_cash(c))

Base.promote(c::CurrencyCash, n) = promote(_cash(c), n)
Base.promote(n, c::CurrencyCash) = promote(n, _cash(c))

Base.convert(::Type{T}, c::CurrencyCash) where {T<:Real} = convert(T, _cash(c))
Base.isless(a::CurrencyCash, b::CurrencyCash) = isless(_cash(a), _cash(b))
Base.isless(a::CurrencyCash, b::Number) = isless(promote(a, b)...)
Base.isless(b::Number, a::CurrencyCash) = isless(promote(b, a)...)
Base.isless(a::Cash, b::CurrencyCash) = isless(a, b.cash)

Base.abs(c::CurrencyCash) = _toprec(c, abs(_cash(c)))
Base.real(c::CurrencyCash) = _toprec(c, real(_cash(c)))

_cash(cc::CurrencyCash) = getfield(cc, :cash)
_prec(cc::CurrencyCash) = getfield(cc, :precision)
_toprec(cc::AbstractCash, v) = toprecision(v, _prec(cc))
_toprec(cc::AbstractCash, c::C) where {C<:AbstractCash} = toprecision(value(c), _prec(cc))
_asatol(v::F) where {F<:AbstractFloat} = v
_asatol(v::I) where {I<:Integer} = 1 / 10^v
_atol(cc::CurrencyCash) = _prec(cc) |> _asatol

-(a::CurrencyCash, b::Real) = _toprec(a, a.cash - b)
+(a::CurrencyCash, b::Real) = _toprec(a, a.cash + b)
*(a::CurrencyCash, b::Real) = _toprec(a, a.cash * b)
/(a::CurrencyCash, b::Real) = _toprec(a, a.cash / b)
÷(a::CurrencyCash, b::Real) = a.cash ÷ b

==(a::CurrencyCash{S}, b::CurrencyCash{S}) where {S} = _cash(b) == _cash(a)
÷(a::CurrencyCash{S}, b::CurrencyCash{S}) where {S} = _cash(a) ÷ _cash(b)
*(a::CurrencyCash{S}, b::CurrencyCash{S}) where {S} = _toprec(a, _cash(a) * _cash(b))
/(a::CurrencyCash{S}, b::CurrencyCash{S}) where {S} = _toprec(a, _cash(a) / _cash(b))
+(a::CurrencyCash{S}, b::CurrencyCash{S}) where {S} = _toprec(a, _cash(a) + _cash(b))
-(a::CurrencyCash{S}, b::CurrencyCash{S}) where {S} = _toprec(a, _cash(a) - _cash(b))

_applyop!(op, c, v) =
    let cv = getfield(_cash(c), :value)
        cv[] = _toprec(c, op(cv[], v))
    end

add!(c::CurrencyCash, v) = _applyop!(+, c, v)
sub!(c::CurrencyCash, v) = _applyop!(-, c, v)
mul!(c::CurrencyCash, v) = _applyop!(*, c, v)
rdiv!(c::CurrencyCash, v) = _applyop!(/, c, v)
div!(c::CurrencyCash, v) = div!(_cash(c), v)
mod!(c::CurrencyCash, v) = mod!(_cash(c), v)
cash!(c::CurrencyCash, v) = cash!(_cash(c), _toprec(c, v))
addzero!(c::CurrencyCash, v, args...; atol=_atol(c), kwargs...) = begin
    add!(c, v)
    atleast!(c; atol)
    c
end

gtxzero(c::CurrencyCash) = gtxzero(value(c); atol=_atol(c))
ltxzero(c::CurrencyCash) = ltxzero(value(c); atol=_atol(c))
approxzero(c::CurrencyCash) = approxzero(value(c); atol=_atol(c))
