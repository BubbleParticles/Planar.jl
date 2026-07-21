# Strategies Package Audit - Critical Bugs Found

## Files Examined
1. `/Planar.jl/Strategies/src/Strategies.jl` - Module entry point
2. `/Planar.jl/Strategies/src/module.jl` - Core type definitions
3. `/Planar.jl/Strategies/src/load.jl` - Strategy loading logic
4. `/Planar.jl/Strategies/src/methods.jl` - Strategy methods (reset!, reload!, etc.)
5. `/Planar.jl/Strategies/src/interface.jl` - Strategy interface definitions
6. `/Planar.jl/Strategies/src/utils.jl` - Utility functions (current_total, etc.)
7. `/Planar.jl/Strategies/src/print.jl` - Printing/display
8. `/Planar.jl/Strategies/src/__multi.jl` - MultiStrategy
9. `/Planar.jl/Strategies/src/precompile.jl` - Precompile workload

---

## Critical Bugs Found

### 1. Silent Async Crashes in `utils.jl` - `current_total` functions (HIGH SEVERITY)

**Location**: Lines 93-107 (`NoMarginStrategy{Paper}`) and 147-165 (`MarginStrategy{Paper}`)

**Bug**: The `@asyncm` macro wraps `@async` with `errormonitor`, which **silently swallows exceptions**. The try/catch inside the async task catches errors but returns `zero(DFT)` (0.0), making it appear as if the computation succeeded.

```julia
# Line 98-106 (NoMarginStrategy{Paper})
@sync for (i, ai) in enumerate(s.holdings)
    @asyncm partials[i] = @errormonitor try
        cash(ai) * price_func(ai)
    catch e
        @error "..." exception = (e, catch_backtrace())
        zero(DFT)  # SILENTLY RETURNS 0.0 ON ERROR
    end
end
```

**Impact**: Pricing errors in parallel tasks are completely hidden - strategy reports 0.0 for failed holdings instead of propagating the error.

**Fix**: Remove `@asyncm`/`@errormonitor` wrapper or re-throw after logging.

---

### 2. Silent Error Swallowing in `load.jl` - `strategy!` function (HIGH SEVERITY)

**Location**: Lines 333-338

**Bug**: The try/catch swallows ALL exceptions from `default_load` with only `@debug_backtrace` and returns `nothing`, falling through to `bare_load`.

```julia
s = @something invokelatest(call_func, s_type, cfg, LoadStrategy()) try
    default_load(mod, s_type, cfg)
catch
    @debug_backtrace  # Only debug log, no error propagation
    nothing
end bare_load(mod, s_type, cfg)
```

**Impact**: Any error in `default_load` (network failure, config error, exchange API error) is silently ignored. Strategy falls back to `bare_load` which may have different behavior.

**Fix**: At minimum log at `@error` level, ideally re-throw or handle specific error types.

---

### 3. Missing Error Handling in Strategy Module Loading (MEDIUM SEVERITY)

**Location**: `load.jl` lines 204-235 (`strategy!(src::Symbol, cfg::Config)`)

**Bug**: The `@eval parent begin ... end` block includes `include($path)` and `using .$src` but has no try/catch around the actual loading. If the strategy file has syntax errors or missing dependencies, the error propagates but Pkg cleanup in `finally` may not run properly if the `@eval` itself throws during compilation.

**Fix**: Wrap the module loading in try/catch with proper error context.

---

### 4. Thread-Safety Issue in `methods.jl` - `symsdict` (MEDIUM SEVERITY)

**Location**: Lines 323-324

**Bug**: Uses `@lock s @lget! attrs(s) :assets_bysym Dict{String,Option{AssetInstance}}()` - while the lock protects the strategy, `attrs(s)` returns a `Dict` which is not thread-safe for concurrent read/write even with the lock if other code accesses `attrs(s)` without locking.

```julia
function symsdict(s::Strategy)
    @lock s @lget! attrs(s) :assets_bysym Dict{String,Option{AssetInstance}}()
end
```

**Fix**: Ensure all accesses to `attrs(s)` go through the strategy lock, or use a thread-safe dictionary.

---

### 5. Type Instability in `_defined_marginmode` (LOW SEVERITY)

**Location**: `load.jl` lines 102-109

**Bug**: Uses try/catch for control flow, returns `nothing` on failure causing type instability.

```julia
function _defined_marginmode(mod)
    try
        S = invokelatest(getfield, mod, :S)
        marginmode(S)
    catch
        SC = invokelatest(getfield, mod, :SC)
        marginmode(SC)
    end  # Returns Union{Nothing, MarginMode} - type unstable
end
```

**Fix**: Use `hasfield`/`isdefined` checks instead of exceptions for control flow.

---

### 6. Missing Error Handling in `reset!` (MEDIUM SEVERITY)

**Location**: `methods.jl` lines 126-165

**Bug**: Calls `call!(s, ResetStrategy())` which can throw. If it throws, strategy state may be partially reset (cash cleared, holdings cleared, etc.) leaving strategy in inconsistent state.

**Fix**: Wrap in try/catch and ensure atomic reset or rollback on error.

---

### 7. No Locking in `reload!` (LOW SEVERITY)

**Location**: `methods.jl` lines 173-178

**Bug**: Iterates `universe(s).data.instance` and calls `empty!` and `load!` without locking the strategy.

```julia
reload!(s::Strategy) = begin
    for inst in universe(s).data.instance
        empty!(inst.data)
        load!(inst; reset=true)
    end
end
```

**Fix**: Add `@lock s` around the loop.

---

## Summary

| Severity | Count | Issues |
|----------|-------|--------|
| HIGH | 2 | Silent async crashes, silent error swallowing in strategy loading |
| MEDIUM | 3 | Missing error handling in module loading, thread-safety in symsdict, missing error handling in reset! |
| LOW | 2 | Type instability, missing lock in reload! |

**Total: 7 bugs found**