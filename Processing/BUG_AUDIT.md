# Processing Package - Bug Audit Report

## Files Examined
1. `/Planar.jl/Processing/src/align.jl` - 166 lines
2. `/Planar.jl/Processing/src/ohlcv.jl` - 261 lines
3. `/Planar.jl/Processing/src/propagate.jl` - 112 lines
4. `/Planar.jl/Processing/src/resample.jl` - 231 lines
5. `/Planar.jl/Processing/src/tradesohlcv.jl` - 84 lines
6. `/Planar.jl/Processing/src/normalize.jl` - 54 lines

## Critical Bugs Found & Fixed

### 1. BUG: `resample.jl:136` - Thread Safety: Default `ReentrantLock()` creates new lock each call
**File:** `resample.jl` line 136
**Issue:** `lk = ReentrantLock()` as default argument creates a NEW lock on every function call, making `@lock lk` useless for thread safety across threads.
**Fix:** Remove default, require caller to pass lock, or use a global lock.

### 2. BUG: `resample.jl:147` - `return` inside `@threads` loop returns from thread, not function
**File:** `resample.jl` line 147
**Issue:** `isnothing(v) && return` inside `Threads.@threads` only exits the current thread, not the outer function. The function continues and returns partial results.
**Fix:** Use a shared flag or channel to signal early termination, or collect errors and check after loop.

### 3. BUG: `align.jl:68-89` - `empty_unaligned!` crashes on empty dict / wrong logic
**File:** `align.jl` lines 68-89
**Issues:**
- `maximum(tsdict).first` throws on empty dict (line 82: `check_ohlcvs(first(values(data)))` runs before any entries)
- Logic finds max KEY not most FREQUENT timestamp
- `common = 0` unused
**Fix:** Find most common timestamp, handle empty dict.

### 4. BUG: `align.jl:35-51` - `trim_to!` incorrect `@something` fallback and reversed index bug
**File:** `align.jl` lines 35-51
**Issues:**
- `@something findfirst(...) 1` defaults to 1 when not found - wrong index
- `findfirst` on `@view(df.timestamp[end:-1:1])` returns index in REVERSED view, not original
**Fix:** Proper bounds checking, convert reversed index to original index.

### 5. BUG: `propagate.jl:19-66` - Potential infinite loop in `propagate_ohlcv!`
**File:** `propagate.jl` lines 19-66
**Issues:**
- `while true` with multiple `continue` paths; `tf_idx` incremented in two places (46, 60) but some paths don't increment
- If `nrow(src_data) < count(src_tf, dst_tf)` and `src_tf >= dst_tf`, it breaks; but if not, it continues without incrementing `tf_idx` in all paths
**Fix:** Restructure loop with clear increment logic.

### 6. BUG: `ohlcv.jl:118-123` - Bare `catch` loses error info
**File:** `ohlcv.jl` lines 118-123
**Issue:** `catch` without binding exception variable loses error details.
**Fix:** Bind exception and log it.

### 7. BUG: `tradesohlcv.jl:74-77` - Type instability in `apply.(tf, data[1])` assignment
**File:** `tradesohlcv.jl` lines 74-77
**Issue:** `data[1][:] = apply.(tf, data[1])` broadcasts creating new vector, then assigns element-wise. Type unstable.
**Fix:** Direct assignment: `data[1] = apply.(tf, data[1])`

### 8. BUG: `resample.jl:17-29` - `_left_and_right` infinite loop risk
**File:** `resample.jl` lines 17-29
**Issue:** `while` loops increment/decrement `left`/`right` with NO bounds checking. If condition never met, infinite loop.
**Fix:** Add bounds checks: `left <= size(data,1)` and `right >= 1`.

### 9. BUG: `resample.jl:42-51` / `resample.jl:91` - `_deltas` returns `empty_ohlcv()` but caller checks `isnothing(abort)`
**File:** `resample.jl` lines 42-51, 91
**Issue:** `_deltas` returns `(f, s, t, abort)` where `abort=empty_ohlcv()` (a DataFrame), but line 91 checks `isnothing(abort)` which is always false for DataFrame.
**Fix:** Return `nothing` for abort, or check `abort !== nothing`.

### 10. BUG: `propagate.jl:49` - No try/catch around `update_func` call
**File:** `propagate.jl` line 49
**Issue:** `update_func(src_tf, src_data, dst_tf, dst_data)` can throw, leaving `dst_data` in inconsistent state.
**Fix:** Wrap in try/catch, log error.

### 11. BUG: `align.jl:119-132` - `check_alignment` assumes dict structure
**File:** `align.jl` lines 119-132
**Issue:** `first(data)[2][1]` assumes values are `Vector{DataFrame}`. Crashes if empty or different structure.
**Fix:** Add safety checks.

### 12. BUG: `ohlcv.jl:36-41` - `_update_timestamps` `left` is immutable
**File:** `ohlcv.jl` lines 36-41
**Issue:** `left` is `DateTime` (immutable), `left += prd` creates new DateTime but doesn't affect caller. Only `ts[i] = left` works.
**Fix:** This function appears unused or buggy - the `left` modification is local only.

### 13. BUG: Missing error handling on cache/data loading (per AGENTS.md guideline #69)
**Files:** Multiple - any place calling `load_data` or similar
**Issue:** `load_data` returns `nothing` when cache missing/corrupt. Callers must check `isnothing` before using.
**Fix:** Add `isnothing` guards where data loading results are used.

### 14. BUG: `normalize.jl:25-54` - `maptf` no error handling on `resample` or `f` calls
**File:** `normalize.jl` lines 37-42
**Issue:** Calls `resample(data, tf; ...)` and `f(data_r; kwargs...)` without try/catch. Failures propagate and crash the loop.
**Fix:** Wrap in try/catch, log errors, continue or collect errors.