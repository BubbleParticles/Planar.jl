using ..Lang: @lget!
using ..Misc: Misc
using ..Misc.DocStringExtensions
import Base: ==, +, -, ÷, /, *, ≈
include("cashcur.jl")

@doc "A symbol checked to be a valid quote currency."
const QuoteCurrency = Symbol
@doc "A symbol checked to be a valid base currency."
const BaseCurrency = Symbol

include("consts.jl")

@doc """Check if a string s contains any punctuation characters.

$(TYPEDSIGNATURES)

The function returns true if s contains any punctuation characters, and false otherwise.

Example:

```
s = "Hello, world!"
result = has_punct(s)  # returns true since the string contains a punctuation character
```
"""
has_punct(s::AbstractString) = !isnothing(match(r"[[:punct:]]", s))
@doc """Abstract base type for representing an asset.

Defines the interface and common functionality for all asset types.
"""
abstract type AbstractInstrument end

# TYPENUM
@doc """An `Instrument` represents a parsed raw (usually ccxt) pair of base and quote currency.

- `raw`: The raw underlying string e.g. 'BTC/USDT'
- `bc`: base currency (Symbol)
- `qc`: quote currency (Symbol)
- `fiat`: if both the base and quote currencies match a known fiat symbol e.g. 'USDT/USDC'
- `leveraged`: if parsing matched a leveraged token e.g. 'ETH3L/USDT' or 'ETH3S/USDT'
- `unleveraged_bc`: a leveraged token with the `mod` removed, e.g. `ETH3L` => `ETH`

```julia
> asset = a"BTC/USDT"
> typeof(asset)
Instrument{:BTC, :USDT}
end
```
"""
struct Instrument <: AbstractInstrument
    raw::SubString
    bc::BaseCurrency
    qc::QuoteCurrency
    fiat::Bool
    leveraged::Bool
    unleveraged_bc::BaseCurrency
    function Instrument(s::SubString, b::T, q::T) where {T<:AbstractString}
        B = Symbol(b)
        Q = Symbol(q)
        fiat = isfiatpair(b, q)
        lev = isleveragedpair(s)
        unlev = lev ? deleverage_pair(s; split=true)[1] : B
        new(s, B, Q, fiat, lev, Symbol(unlev))
    end
    Instrument(s::AbstractString) = parse(Instrument, s)
end

_check_parse(pair, s) = begin
    if length(pair) != 2 || has_punct(pair[1]) || has_punct(pair[2])
        throw(InexactError(:Instrument, Instrument, s))
    end
end
function Base.parse(::Type{Instrument}, s::AbstractString)
    pair = splitpair(s)
    _check_parse(pair, s)
    Instrument(SubString(s), pair[1], pair[2])
end
const symbol_rgx_cache = Dict{String,Regex}()
const symbol_rgx_cache_lock = ReentrantLock()
function Base.parse(
    ::Type{<:AbstractInstrument}, s::AbstractString, qc::AbstractString; raise=true
)
    pair = splitpair(s)
    rx = lock(symbol_rgx_cache_lock) do
        get!(symbol_rgx_cache, qc) do
            # Manually escape regex special chars in qc
            escaped = replace(qc, r"[.+*?^${}()|[\]\\]" => s"\\&")
            Regex("(.*)($(escaped))(?:settled?)?\$", "i")
        end
    end
    m = match(rx, pair[1])
    if isnothing(m)
        raise && throw(InexactError(:Instrument, Instrument, s))
        return nothing
    end
    Instrument(SubString(s), m.captures[1], m.captures[2])
end
function Base.parse(
    ::Type{<:AbstractInstrument}, s::AbstractString, qcs::Union{AbstractVector,AbstractSet}
)
    for qc in qcs
        p = parse(Instrument, s, qc; raise=false)
        !isnothing(p) && return p
    end
    throw(InexactError(:Instrument, Instrument, s))
end
_hashtuple(a::AbstractInstrument) = (a.bc, a.qc)
Base.hash(a::AbstractInstrument) = hash(_hashtuple(a))
Base.hash(a::AbstractInstrument, h::UInt) = hash(_hashtuple(a), h)
Base.isequal(a::AbstractInstrument, b::AbstractInstrument) = raw(a) == raw(b)
Base.:(==)(a::AbstractInstrument, b::AbstractInstrument) = raw(a) == raw(b)
Base.convert(::Type{String}, a::AbstractInstrument) = a.raw
Base.string(a::AbstractInstrument) = "Instrument($(a.bc)/$(a.qc))"
Base.show(buf::IO, a::AbstractInstrument) = write(buf, string(a))
Base.display(a::AbstractInstrument) = show(stdout, a)
raw(::Nothing) = ""
raw(v::AbstractString) = v
@doc """Convert an AbstractInstrument object a to its raw representation.

$(TYPEDSIGNATURES)

The function returns a new AbstractInstrument object with special characters escaped using backslashes.

Example:
```julia
a = parse("BTC/USDT")
raw(a) # returns "BTC/USDT"
```
"""
raw(a::AbstractInstrument) = convert(String, a)
@doc " Returns the quote currency of `a`."
qc(a::AbstractInstrument) = a.qc
@doc " Returns the base currency of `a`."
bc(a::AbstractInstrument) = a.bc

const QuoteTuple = @NamedTuple{q::Symbol}
const BaseTuple = @NamedTuple{b::Symbol}
const BaseQuoteTuple = @NamedTuple{b::Symbol, q::Symbol}
const CurrencyTuple = Union{QuoteTuple,BaseTuple,BaseQuoteTuple}
Base.Broadcast.broadcastable(q::Instrument) = Ref(q)
Base.in(a::Instrument, t::QuoteTuple) = a.qc == t.q
Base.in(a::Instrument, t::BaseTuple) = a.bc == t.b
Base.in(a::Instrument, t::BaseQuoteTuple) = a.bc == t.b && a.qc == t.q
==(a::AbstractInstrument, s::AbstractString) = a.raw == s
==(a::Instrument, b::Instrument) = a.qc == b.qc && a.bc == b.bc

isbase(a::AbstractInstrument, b) = a.bc == b
isquote(a::AbstractInstrument, q) = a.qc == q

@doc "A regular expression pattern used to match leveraged naming conventions in market symbols. It captures the separator used in leveraged pairs."
const leverage_pair_rgx = r"(?:(?:BULL)|(?:BEAR)|(?:[0-9]+L)|(?:[0-9]+S)|(?:UP)|(?:DOWN)|(?:[0-9]+LONG)|(?:[0-9+]SHORT))([\/\-\_\.])"

@doc "Test if pair has leveraged naming."
isleveragedpair(pair) = !isnothing(match(leverage_pair_rgx, pair))
@doc """Split a CCXT pair (symbol) pair into its base and quote currencies.

$(TYPEDSIGNATURES)

The function returns a tuple containing the base currency and quote currency.

Example:
pair = "BTC/USDT"
base, quote = splitpair(pair)  # returns ("BTC", "USDT")
"""
splitpair(pair::AbstractString) = split(spotpair(pair), r"\/|\-|\_|\.")
@doc "Strips the settlement currency from a symbol."
spotpair(pair::AbstractString) = split(pair, ":")[1]

@doc "Remove leveraged pair pre/suffixes from base currency."
@inline function deleverage_pair(pair::T; split=false, sep="/") where {T<:AbstractString}
    # Remove leverage suffixes/prefixes from base currency
    # Pattern matches: 3L, 3S, BULL, BEAR, UP, DOWN, 3LONG, 3SHORT
    # Keep the separator (\1) to maintain pair format
    dlv = splitpair(replace(pair, leverage_pair_rgx => s"\1"))
    if isempty(dlv[1])
        # If base currency is empty after deleveraging, extract from prefix
        # e.g., "BULL/USDT" -> "BTC/USDT" is an assumption, better to throw
        throw(ArgumentError("Cannot deleverage pair $pair: base currency became empty"))
    end
    split ? dlv : join(dlv, sep)
end

@doc """Remove the leverage component from a CCXT quote currency quote.

$(TYPEDSIGNATURES)

The function returns a new string with the leverage component removed.

Example:
```julia
quote = "3BTC/USDT"
deleveraged_quote = deleverage_qc(quote)  # returns "USDT"
```
"""
function deleverage_qc(dlv::Vector{T}) where {T<:AbstractString}
    deleverage_pair(dlv; split=true)[1]
end
deleverage_qc(pair::AbstractString) = deleverage_pair(pair; split=true)[1]

@doc "Check if both base and quote are fiat currencies."
isfiatpair(b::T, q::T) where {T<:AbstractString} = begin
    b ∈ fiatnames && q ∈ fiatnames
end
isfiatpair(p::Vector{T}) where {T<:AbstractString} = isfiatpair(p[1], p[2])
isfiatpair(pair::AbstractString) = isfiatpair(splitpair(pair))
@doc "Check if quote currency is a stablecoin."
isfiatquote(aa::AbstractInstrument) = aa.qc ∈ fiatsyms
isfiatquote(pair::AbstractString) = isfiatquote(parse(AbstractInstrument, pair))

@doc """Parses `pair` to an `Instrument` type.
```julia
> typeof(a"BTC/USDT")
Instruments.Instrument
"""
macro a_str(pair)
    :($(parse(Instrument, pair)))
end

@doc """Rewrites `sym` as a perpetual usdt symbol.
```julia
> pusdt"btc"
BTC/USDT:USDT
```
"""
macro pusdt_str(sym)
    :($(uppercase(sym) * "/USDT:USDT"))
end

export Cash, Instrument, AbstractInstrument
export raw, bc, qc
export isfiatpair, deleverage_pair, isleveragedpair
export @a_str, @c_str

include("derivatives.jl")
