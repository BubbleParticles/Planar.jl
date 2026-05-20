# `constructors.jl` — Old (Python) vs New (Gateway) Comparison

## `loadmarkets!`

| Aspect | Old (Python) | New (Gateway) | Missing? |
|--------|-------------|---------------|----------|
| Cache fields | `markets`, `markets_by_id`, `currencies`, `symbols` (4 keys) | `markets` (1 key) | YES — `markets_by_id`, `currencies`, `symbols` dropped |
| Market loading trigger | `pyfetch(exc.loadMarkets, true)` — explicit async call to `load_markets()` | `call_exchange(client, name, "markets")` — subprocess lazy-loads | Fixed by pre-load in subprocess, but cache restore can't restore `markets_by_id`/`currencies`/`symbols` |
| Cache restore | Writes back to `exc.py.markets`, `exc.py.markets_by_id`, `exc.py.symbols`, `exc.py.currencies` | No cache restore (not needed for gateway — struct won't have those fields) | Acceptable — gateway doesn't need serialized Python state |
| Conversion | `jlpyconvert(exc.py.markets)` — Python→Julia | `jlpyconvert(raw)` — JSON→Julia | Equivalent |

## `setexchange!`

| Aspect | Old | New | Missing? |
|--------|-----|-----|----------|
| Timeframes | `empty!(exc.timeframes)` + populate from `exc.py.timeframes` sorted by `timeframe(t)` | Not touched | Relies on Exchange constructor — OK if constructor populated correctly, but `setexchange!` has no fallback |
| Has dict | `setflags!(exc)` — iterates `exc.py.has.items()` and populates `exc.has` | Not called | Relies on Exchange constructor |
| Precision | `exc.precision = ExcPrecisionMode(pyconvert(Int, exc.py.precisionMode))` | Not set | Relies on Exchange constructor |
| Fees | Iterates `exc.py.fees["trading"]`, calls `_setfees!` for each | Not called | Relies on Exchange constructor |
| `exc._trace` | Set via `eventtrace(nameof(exc))` | Same | OK |
| Keys | `exckeys!(exc)` | Same | OK |

**Risk:** Exchange constructor fetches these individually with try/catch. If any fail (e.g. gateway timeout), `setexchange!` never re-tries them.

## `getexchange!`

| Aspect | Old | New | Missing? |
|--------|-----|-----|----------|
| None case | `Exchange(pybuiltins.None)` | `Exchange(nothing)` | Equivalent |
| Normal case | `ccxt_exchange(x, params)` → `Exchange(py, params, account)` | `Exchange(x; account)` | Different path — now uses gateway |
| `params` arg | Passed `PyDict` to `ccxt_exchange` for Python exchange creation | Ignored completely | YES — `params` argument is silently dropped |
| Empty exchange set | `Exchange(pybuiltins.None)` | `Exchange(nothing)` | Equivalent |

## `exckeys!` (5-arg version, sets credentials)

**Old:**
```julia
function exckeys!(exc, key, secret, pass, wa, pk)
    if Symbol(exc.id) ∈ (:kucoin, :kucoinfutures)
        (key, secret) = secret, key
    end
    exc.py.apiKey = key
    exc.py.secret = secret
    exc.py.password = pass
    exc.py.walletAddress = wa
    exc.py.privateKey = pk
    authenticate!(exc)
end
```

**New:**
```julia
function exckeys!(exc, key, secret, pass, wa, pk)
    if Symbol(exc.id) ∈ (:kucoin, :kucoinfutures)
        key, secret = secret, key
    end
    if !isempty(key) || !isempty(secret) || !isempty(pass)
        call_exchange(default_client(), name, "set_api_key",
            query=Dict("apiKey" => key, "secret" => secret,
                       "password" => pass, "walletAddress" => wa, "privateKey" => pk))
    end
    authenticate!(exc)
    nothing
end
```

| Aspect | Old | New | Status |
|--------|-----|-----|--------|
| Kucoin key swap | Swapped key/secret for `kucoin` and `kucoinfutures` | Restored | **FIXED** |
| password | Set via `exc.py.password = pass` | Sent to gateway | **FIXED** |
| walletAddress | Set via `exc.py.walletAddress = wa` | Sent to gateway | **FIXED** |
| privateKey | Set via `exc.py.privateKey = pk` | Sent to gateway | **FIXED** |
| authenticate! | Called after setting keys | Restored | **FIXED** |
| Write when empty | Always writes (even empty strings) | Only writes if any credential is non-empty | Acceptable difference |

## `authenticate!`

**Old (CcxtExchange version):**
```julia
function authenticate!(exc::CcxtExchange, tries=3)
    if hasproperty(exc.py, :authenticate)
        resp = try
            _authenticate!(exc)
        catch e
            @error "exchange auth error" exception = e
        end
        if resp isa Exception
            if tries > 0 && pyisinstance(resp, Ccxt._lazypy(Ccxt.ccxt, "ccxt").RequestTimeout)
                return authenticate!(exc, tries - 1)
            end
            @error "exchange: auth error" resp
            false
        else
            true
        end
    else
        @warn "exchange: no `authenticate` method." exc
        false
    end
end
```

**New:**
```julia
authenticate!(::CcxtExchange, tries=3) = true
authenticate!(::Exchange, tries=3) = nothing
```

| Aspect | Old | New | Status |
|--------|-----|-----|--------|
| Actual auth call | Called `authenticate()` on Python exchange | Returns `true` — gateway handles auth implicitly when keys are set | **Intentional change** |
| Timeout retry | 3 retries on `RequestTimeout` | No retry needed (no actual call) | Acceptable — gateway is stateless for auth |
| `_authenticate!` hook | Calls exchange-specific hook | Hook kept as no-op for Phemex | OK |

## `sandbox!`

| Aspect | Old | New | Status |
|--------|-----|-----|--------|
| Error handling | Rethrows non-sandbox exceptions (`rethrow(e)`) | Restored — checks for "sandbox"/"Not Found"/"404" in error msg | **FIXED** |
| Assertion | `@assert issandbox(exc) "..."` after enable | Restored | **FIXED** |
| 404 handling | Python raises `BadResponse` | 404 from gateway treated as sandbox-unavailable | **FIXED** |
| Key cleanup on sandbox disable | `elseif isempty(exc.py.secret) exckeys!(exc)` | `!flag && exckeys!(exc)` | Acceptable difference |

## `issandbox`

| Aspect | Old | New | Missing? |
|--------|-----|-----|----------|
| Method | `"apiBackup" in exc.py.urls.keys()` | Gateway call `/exchanges/{id}/urls` → check `apiBackup` key | Equivalent (gateway instead of Python) |
| Error handling | Direct Python access (throws on failure) | try/catch returning `false` | More defensive (good) |

## `_setfees!`

Refactored from Python-specific type checks (`pyisbool`, `pyisstr`, `pyisfloat`, `pyisdict`) to Julia type checks (`isa Bool`, `isa String`, `isa AbstractFloat`, `isa AbstractDict`). Equivalent.

## `setflags!`

Now a no-op because `has` dict is populated by Exchange constructor. But the old function was also a no-op for non-CcxtExchange types (`setflags!(args...; kwargs...) = nothing`). Acceptable.

## `serialize` / `deserialize`

| Aspect | Old | New | Status |
|--------|-----|-----|--------|
| Serialized data | `(exc.id, issandbox(exc), account(exc), e.params)` | `(exc.id, issandbox(exc), account(exc), nothing)` | `params` replaced with `nothing`, `issandbox` now correctly captured — **FIXED** |
| Deserialization | `getexchange!(id, params; sandbox, account)` | `getexchange!(id, nothing; sandbox=sandbox_flag, account=acc)` | `params` will be ignored by `getexchange!` — acceptable |

## `ratelimit_njobs`

Present in both versions. OK.

## `check_timeout`

Present in old (lines 583-585). Restored in new via `gettimeout(exc)` call — **FIXED**.

## `_fetchnoerr` / `timestamp` / `time`

Old used `_fetchnoerr` helper with `pyfetch`/`pyconvert`. New calls gateway directly with try/catch. Functionally equivalent after migration.
