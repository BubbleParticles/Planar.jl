# CCXT-to-CcxtGateway Refactor Log

Loaded by the LLM when context about past migration bugs or audit findings is needed. This is supplementary to AGENTS.md (which contains the active checklist).

## Audit: All 35 `call_exchange` Sites

| Issue | Location | Severity | Status |
|---|---|---|---|
| `"enable"` should be `"enabled"` for `setSandboxMode` | `constructors.jl:449` | 🔴 Bug (wrong fix reverted) | ✅ Fixed |
| `"flag" => string(flag)` — boolean GET string is truthy | `constructors.jl:493` | 🔴 Bug (fixed via POST body) | ✅ Fixed |
| `issandbox` imported from wrong module | `adhoc/leverage.jl:2` | 🟡 Warning (fixed) | ✅ Fixed |
| `market_limits` duplicate with same signature | `tickers.jl:284,334` | 🟡 Warning (fixed) | ✅ Fixed |
| `"hedged" => "false"` string is truthy in Python | `adhoc/leverage.jl:60,75` | 🟠 Pre-existing (fixed via POST body) | ✅ Fixed |
| `"side" => string(side)` — string `"Long"`/`"Short"` to ccxt | `leverage.jl:35` | 🟢 Acceptable (ccxt coerces) | ✅ OK |
| All other params (`symbol`, `type`, `leverage`, `marginMode`, `value`, `flag`) | 30+ sites | 🟢 Standard ccxt names | ✅ OK |

## Post-Mortem: The `sandbox!` Compound Bug

`sandbox!` had two independent bugs:

1. `"enabled"` was incorrectly changed to `"enable"` (param name audit failure)
2. `bool` `false` was sent as GET string `"false"` which is truthy in Python (`bool("false") == True`) (type audit failure)

Fixing either alone was insufficient — both had to be correct.

### Rule
ALL boolean ccxt params must use `body=` (POST) — GET strings are always truthy. When editing a `call_exchange` site, re-run ALL 5 audits on that call, not just the one you're fixing. After discovering a bug class (e.g., "boolean GET strings are truthy"), grep and fix every call site at once, not one-by-one as discovered. Test the disable path, not just enable.

## JSON3.Object Key Handling

`JSON3.Object` stores keys as `Symbol` when iterating with `pairs()`:
```julia
urls = JSON3.parse("""{"apiBackup": "..."}""")
d = Dict(pairs(urls))          # Dict{Symbol, Any}  ← keys are Symbol!
haskey(d, "apiBackup")         # false — key is Symbol("apiBackup"), not String
```

**Fix:** Always force `string(k)` when creating a lookup dict from JSON3 data:
```julia
Dict{String,Any}(string(k) => v for (k, v) in pairs(urls))
```

## `JSON.jl` Does Not Export `json`

`using JSON` makes `JSON.parse` available but NOT the bare `json` function:
```julia
json(x)    # ERROR: UndefVarError
JSON.json(x)  # ✅ correct
```

## Gatewayconvert (renamed from `jlpyconvert`)

Renamed because it converts gateway responses (JSON3.Object → Julia types), not Python objects. Forces `string()` on all keys from JSON3 data before merging into `Dict{String,Any}`.

## Call Exchange POST Routing

When `body=` is provided to `call_exchange`, the method is automatically routed as POST (preserving native Julia types through JSON). Without `body=`, methods default to GET (all params become strings).

## Fast Test Suite

`runtests_fast.jl` (20+ tests) bypasses gateway dependency by setting mock HTTP at load time via `Rest.set_http_get!`/`set_http_post!`. Default mocks return valid responses for all common gateway endpoints. Stateful mock tracks sandbox mode per exchange for realistic `issandbox` testing.

