@doc """ Minimal lock-based replacement for the `ConcurrentCollections.jl` package.

Upstream `ConcurrentCollections@0.1.1` imports `Base.Threads.inttypes` and
`Base.Threads.llvmtypes`, which were removed in Julia 1.13, and ships no
1.13-compatible release. Our in-repo surface is narrow (`ConcurrentDict`,
`modify!`, `Delete`), so we vendor a `Dict` + `ReentrantLock` implementation
under the same module name. Every `Misc.ConcurrentCollections.*` reference —
including `using ..Misc.ConcurrentCollections: ConcurrentDict` in downstream
packages — keeps resolving without changes.

Semantics mirror the upstream functions we relied on:
- `modify!(f, d, key)` throws `KeyError` on a missing key; a function result
  of `Delete(v)` deletes the key instead of storing it.
- `modify!(f, d, key, default)` applies `f` to `default` when the key is absent.
- `keys`/`values`/iteration operate on a snapshot taken under the lock, so
  concurrent mutation during iteration neither errors nor deadlocks.
"""
module ConcurrentCollections

export ConcurrentDict, Delete, modify!

struct Delete{T}
    value::T
end

mutable struct ConcurrentDict{K,V} <: AbstractDict{K,V}
    lock::ReentrantLock
    dict::Dict{K,V}
    ConcurrentDict{K,V}() where {K,V} = new{K,V}(ReentrantLock(), Dict{K,V}())
end
ConcurrentDict{K,V}(d::AbstractDict) where {K,V} = begin
    out = ConcurrentDict{K,V}()
    for (k, v) in d
        out.dict[k] = v
    end
    out
end
ConcurrentDict(d::AbstractDict{K,V}) where {K,V} = ConcurrentDict{K,V}(d)

Base.keytype(::Type{<:ConcurrentDict{K,V}}) where {K,V} = K
Base.valtype(::Type{<:ConcurrentDict{K,V}}) where {K,V} = V
Base.length(d::ConcurrentDict) = lock(() -> length(d.dict), d.lock)
Base.isempty(d::ConcurrentDict) = lock(() -> isempty(d.dict), d.lock)
Base.haskey(d::ConcurrentDict, k) = lock(() -> haskey(d.dict, k), d.lock)
Base.getindex(d::ConcurrentDict, k) = lock(() -> d.dict[k], d.lock)
Base.setindex!(d::ConcurrentDict, v, k) = (lock(() -> d.dict[k] = v, d.lock); d)
Base.get(d::ConcurrentDict, k, default) = lock(() -> get(d.dict, k, default), d.lock)
Base.get(f::Function, d::ConcurrentDict, k) = lock(() -> get(f, d.dict, k), d.lock)
Base.delete!(d::ConcurrentDict, k) = (lock(() -> delete!(d.dict, k), d.lock); d)
Base.empty!(d::ConcurrentDict) = (lock(() -> empty!(d.dict), d.lock); d)
Base.pop!(d::ConcurrentDict, k) = lock(() -> pop!(d.dict, k), d.lock)
Base.pop!(d::ConcurrentDict, k, default) = lock(() -> pop!(d.dict, k, default), d.lock)
Base.sizehint!(d::ConcurrentDict, n) = (lock(() -> sizehint!(d.dict, n), d.lock); d)
Base.keys(d::ConcurrentDict) = lock(() -> collect(keys(d.dict)), d.lock)
Base.values(d::ConcurrentDict) = lock(() -> collect(values(d.dict)), d.lock)

function Base.iterate(d::ConcurrentDict)
    snap = lock(() -> collect(d.dict), d.lock)
    isempty(snap) && return nothing
    return snap[1], (snap, 2)
end
function Base.iterate(::ConcurrentDict, (snap, i))
    i > length(snap) && return nothing
    return snap[i], (snap, i + 1)
end

function _modify_locked!(f::Function, d::ConcurrentDict, key, old, present::Bool)
    nv = f(old)
    if nv isa Delete
        present && delete!(d.dict, key)
    else
        d.dict[key] = nv
    end
    return d
end

function modify!(f::Function, d::ConcurrentDict, key)
    lock(d.lock) do
        haskey(d.dict, key) || throw(KeyError(key))
        _modify_locked!(f, d, key, d.dict[key], true)
    end
end
function modify!(f::Function, d::ConcurrentDict, key, default)
    lock(d.lock) do
        present = haskey(d.dict, key)
        _modify_locked!(f, d, key, present ? d.dict[key] : default, present)
    end
end

end
