# `currency.jl` — Old (Python) vs New (Gateway) Comparison

## `to_float`

**Old:**
```julia
function to_float(py::Py, T::Type{<:AbstractFloat}=DFT)
    something(pyconvert(Option{T}, py), zero(T))
end
to_float(v::Number) = v
```

**New:**
```julia
function to_float(v, T::Type{<:AbstractFloat}=DFT)
    something(_tonum(v, T), zero(T))
end
to_float(v::Number, ::Type{<:AbstractFloat}=DFT) = v
```

Old had a specialized method for `Py` types. New has a general method with `_tonum` helper. Equivalent functionality.

## `to_num`

**Old (20-35):** Python-specific type dispatch:
```julia
function to_num(py::Py)
    @something if pyisnone(py)
        0.0
    elseif pyisinstance(py, pybuiltins.int)
        pyconvert(Option{Int}, py)
    elseif pyisinstance(py, pybuiltins.float)
        pyconvert(Option{DFT}, py)
    elseif pyisinstance(py, (pybuiltins.tuple, pybuiltins.list)) && length(py) > 0
        to_num(py[0])
    elseif pyisinstance(py, pybuiltins.str)
        isempty(py) ? 0 : pyconvert(DFT, pyfloat(py))
    else
        pyconvert(Option{DFT}, pyfloat(py))
    end 0.0
end
```

**New (30-37):** Julia-native type dispatch:
```julia
function to_num(v)
    v === nothing && return 0.0
    v isa Integer && return Int(v)
    v isa AbstractFloat && return DFT(v)
    v isa String && return something(tryparse(DFT, v), 0.0)
    v isa AbstractVector && !isempty(v) && return to_num(first(v))
    0.0
end
```

Equivalent for post-gateway (JSON parsed) data. OK.

## `_lpf` — limits, precision, fees extraction

**Old (43-69):** Python-aware — checked `pyisnone`, accessed nested dicts with `get`.
**New (40-67):** Julia-native — checks `=== nothing`, accesses dicts with `get`, converts JSON3.Object via `Dict(pairs(cur))`.

| Aspect | Old | New | Missing? |
|--------|-----|-----|----------|
| Currency dict type | Python `Py` dict | `JSON3.Object` or `Dict` | Equivalent after conversion with `Dict(pairs(cur))` |
| `limits` extraction | `get(cur, "limits", nothing)` + `pyisnone` | `get(cur_dict, "limits", nothing)` | Equivalent |

## `_cur` — currency fetch

**Old (72-90):**
```julia
function _cur(exc, sym)
    sym_str = uppercase(string(sym))
    curs = @lget! currenciesCache1Hour exc.id begin
        v = try
            if hasproperty(exc.py, :currencies) && !pyisnone(exc.py.currencies) && !isempty(exc.py.currencies)
                exc.py.currencies                        # Fast path: direct attr
            else
                pyfetch(exc.fetchCurrencies)             # Slow path: REST call
            end
        catch e
            exc.currencies                                # Fallback: exchange property
        end
        v isa PyException ? exc.currencies : v           # Fallback: if error
    end
    (pyisnone(curs) || isempty(curs)) ? nothing : get(curs, sym_str, nothing)
end
```

**New (70-85):**
```julia
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
```

| Aspect | Old | New | Missing? |
|--------|-----|-----|----------|
| Fast path | `exc.py.currencies` — direct Python attr access | Not available | Acceptable (gateway path) |
| Slow path | `pyfetch(exc.fetchCurrencies)` | `call_exchange(client, name, "currencies")` | Equivalent |
| Fallback on error | `exc.currencies` — property access | `nothing` — no fallback | **YES** — old would try `exc.currencies` (goes through Python), new returns nothing |
| PyException check | Additional fallback `v isa PyException ? exc.currencies : v` | Not present | **YES** — old had extra PyException guard |

## `CurrencyCash`

Straightforward migration — replaced `pyisinstance(cur, pybuiltins.dict)` with `cur === nothing` check (line 114). Equivalent.

## All operator definitions

Unchanged — no Python-specific code in these. OK.
