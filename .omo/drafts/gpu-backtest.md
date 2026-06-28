---
slug: gpu-backtest
status: drafting
intent: unclear
pending-action: write .omo/plans/gpu-backtest.md
approach: Analyze feasibility of GPU-accelerated backtesting using KernelAbstractions.jl, identify data transfer patterns, design Strategy kernel interface, and verify zero-copy GPU execution.
---

# Draft: gpu-backtest

## Components (topology ledger)
<!-- Lock the SHAPE before depth. One row per top-level component that can succeed or fail independently. -->
<!-- id | outcome (one line) | status: active|deferred | evidence path -->
comp-1 | Data layout analysis: OHLCV/DataFrame to GPU arrays | active | Simulations/src/types.jl:22-29, Data/src/candles.jl:48-52
comp-2 | Hot path identification: backtest loop, order processing, slippage | active | SimMode/src/backtest.jl:111-134, SimMode/src/orders/limit.jl:61-178
comp-3 | Strategy kernel interface design | active | Strategies/src/interface.jl:1-40, Strategies/src/module.jl:69-140
comp-4 | GPU memory management (zero-copy verification) | active | N/A - design phase
comp-5 | Optimization integration (multi-threaded backtest runs) | active | Opt/src/module.jl:467-528

## Open assumptions (announced defaults)
<!-- Intent is UNCLEAR: research resolves ambiguity, defaults are adopted (not asked), and each is surfaced in the plan's human TL;DR for veto. -->
<!-- assumption | adopted default | rationale | reversible? -->
assume-1 | Use KernelAbstractions.jl + CUDA.jl/AMDGPU.jl/Metal.jl backend | Industry standard for Julia GPU kernels, supports multiple backends | Yes, can swap backend
assume-2 | GPU target: NVIDIA CUDA first, then AMD/Metal | CUDA has most mature Julia ecosystem; AMDGPU/Metal follow similar API | Yes
assume-3 | Strategy kernel = pure function (DateTime, OHLCV window, params) -> signals | Backtest loop is synchronous; strategy is called per timestep with OHLCV data | Yes, but limits stateful strategies
assume-4 | OHLCV data stored as columnar GPU arrays (SoA layout) | DataFrame columns map naturally to separate GPU arrays; coalesced access | Yes
assume-5 | Order book state (positions, orders) stays on CPU initially | Complex mutable state hard to express in kernels; can be migrated later | Yes, phased approach
assume-6 | Verification via CUDA.@profile + NSight Compute / AMD ROCm profiler | Zero-copy means no H2D/D2H in hot path; profilers confirm | Yes

## Findings (cited - path:lines)
finding-1 | Backtest loop is in SimMode/src/backtest.jl:111-134 - synchronous for-loop over DateRange, calls update!(s, date) then call!(s, date, ctx) per timestep | path:lines
finding-2 | Strategy call! is the main extension point (Strategies/src/interface.jl:10) - user implements call!(strat, current_time, ctx) | path:lines
finding-3 | OHLCV data accessed via candleat/lowat/highat/closeat/volumeat macros (Data/src/candles.jl:48-88) - these do searchsortedlast on timestamp column | path:lines
finding-4 | Order processing in update! (SimMode/src/orders/updates.jl:90-140) iterates sellorders then buyorders, calls order! per order | path:lines
finding-5 | Slippage calculation (SimMode/src/slippage.jl:73-177) accesses OHLCV via lowat/highat/closeat/openat/volumeat - heavy data access | path:lines
finding-6 | Optimization (Opt/src/module.jl:467-528) runs multiple backtests in parallel via Threads.@threads, each with cloned strategy/context | path:lines
finding-7 | AssetInstance.data is SortedDict{TimeFrame, DataFrame} (Instances/src/module.jl:69) - columnar DataFrame with timestamp, open, high, low, close, volume | path:lines
finding-8 | DataFrames are NOT GPU-friendly; need conversion to CuArrays/ROCArrays with SoA layout | path:lines
finding-9 | Warmup runs a mini-backtest (StrategyTools/src/warmup.jl:100-104) - same code path | path:lines
finding-10 | Strategy params passed via OptRun (Opt/src/module.jl:70-74) - setparams! applies before each backtest run | path:lines

## Decisions (with rationale)
decision-1 | Phase 1: GPU-accelerate indicator computation only (OHLCV -> signals) | Lowest risk, highest impact, keeps order logic on CPU
decision-2 | Phase 2: GPU-accelerate slippage/fill logic (pure math on OHLCV) | Order state stays CPU, but fill price calc on GPU
decision-3 | Phase 3: Full kernel (strategy + order logic) if phases 1-2 succeed | Requires restructuring Strategy as pure kernel
decision-4 | Use KernelAbstractions @kernel with @index(Global, Linear) for timestep parallelism | Each timestep independent in backtest (no intra-timestep deps)
decision-5 | Data transfer: pre-copy ALL OHLCV to GPU before backtest loop | Verify zero-copy with CUDA.@profile showing no H2D/D2H in kernel

## Scope IN
- Feasibility analysis with code references
- Data layout transformation (DataFrame -> GPU arrays)
- Strategy kernel interface design (trait-based)
- Zero-copy verification methodology
- Phased implementation roadmap
- Integration points with Opt multi-threaded optimization

## Scope OUT (Must NOT have)
- Full reimplementation of order book on GPU (Phase 3+ only)
- Live trading GPU support (different architecture)
- Custom CUDA kernels (use KernelAbstractions only)
- Distributed multi-GPU (single GPU first)

## Detailed answers to user questions

### Q1: How would we access data from Dict (OHLCV data store)?

**Current access pattern** (CPU, must be replaced for GPU):

The OHLCV data lives in `AssetInstance.data` as `SortedDict{TimeFrame, DataFrame}` (line 69: `Instances/src/module.jl`). Data access goes through two layers:

**Layer 1 — DataFrame column access:**
```julia
# Instances/src/module.jl:609-610
ohlcv(ai::AssetInstance) = first(ai.data).second          # smallest TF DataFrame
ohlcv(ai::AssetInstance, tf::TimeFrame) = ai.data[tf]     # specific TF
```

**Layer 2 — Candle/OHLCV value extraction** (uses `searchsortedlast` on timestamps):
```julia
# Data/src/candles.jl:48-52
function candleat(df, date; return_idx=false)
    idx = searchsortedlast(df.timestamp, date)  # <-- CPU-only, allocates
    cdl = _candleidx(df, idx, date)             # <-- creates Candle struct
    ...
end
# Data/src/candles.jl:72-88 — similar for openat, highat, lowat, closeat, volumeat
```

**GPU replacement:**
- `searchsortedlast` is a binary search on the timestamp column. This must become a direct array access: `idx = date_to_timestep[date]` via a precomputed lookup table. Since the backtest loop iterates in date order, the timestep index is the loop counter itself — no binary search needed at all.
- `_candleidx` creates a `Candle` struct (heap allocation). GPU kernels cannot allocate `Candle` structs. Instead, read individual float values directly from the SoA GPU arrays.
- The `Dict` (`SortedDict`) is iterated with `for (tf, df) in ai.data` — on GPU this becomes kernel specialization on `TimeFrame` type parameter.

**SoA GPU layout:**
```julia
# New: GpuBacktest/src/layout.jl
struct GpuOHLCVData{Backend,T}
    timestamps::BackendArray{Backend, DateTime, 1}  # 1D
    open::BackendArray{Backend, T, 1}
    high::BackendArray{Backend, T, 1}
    low::BackendArray{Backend, T, 1}
    close::BackendArray{Backend, T, 1}
    volume::BackendArray{Backend, T, 1}
    n_candles::Int
end
```

### Q2: How to execute backtesting like a kernel (KernelAbstractions.jl)?

**Current loop** (`SimMode/src/backtest.jl:111-134`):
```julia
for date in ctx.range                      # synchronous, sequential
    update!(s, date, update_mode)          # order processing (side effects)
    call!(s, date, ctx)                    # strategy logic (side effects)
end
```

**GPU kernel mapping:**
- Each timestep `date` becomes one `@index(Global, Linear)` instance in the kernel.
- Strategy logic that is **pure** (OHLCV input → signal output) maps natively: no cross-timestep dependencies.
- Order processing that is **stateful** (order book, positions, cash) cannot easily run inside a kernel because `Order` objects are heap-allocated and positions are mutable structs.
- Solution: **split the loop** — GPU kernel computes signals for each timestep en masse, CPU loop reads signals and applies stateful order logic.

```julia
# Phase 2 kernel launch pattern (GpuBacktest/src/loop.jl)
# 1. Upload OHLCV -> GPU (once, before loop)
gpu_data = ohclv_to_gpu(s.universe, s.timeframe)

# 2. Launch kernel: compute signals for ALL timesteps
output_signals = similar(gpu_data.close, length(ctx.range))
backend = get_backend(gpu_data.close)
kernel = indicator_kernel(backend, 256)
kernel(gpu_data, collect(ctx.range), params(s), output_signals, ndrange=length(ctx.range))
synchronize(backend)

# 3. CPU loop: read signals, process orders (tiny data movement)
for (i, date) in enumerate(ctx.range)
    signal = Array(output_signals[i])     # <-- only 1 float per timestep copied
    signal ? place_order(s, ai, date) : nothing
    update!(s, date, update_mode)
end
```

This achieves **massive parallelism** for the indicator computation (each timestep independent) while keeping stateful order logic on CPU.

### Q3: How to copy strategy data onto the GPU?

**Step 1: Data upload before backtest loop:**
```julia
# GpuBacktest/src/layout.jl
function ohclv_to_gpu(ai::AssetInstance, tf::TimeFrame, range::DateRange)
    df = ohlcv(ai, tf)
    # SoA layout — each column becomes a separate GPU array
    first_idx = searchsortedfirst(df.timestamp, range.start)
    last_idx  = searchsortedlast(df.timestamp, range.stop)
    GpuOHLCVData(
        cu(df.timestamp[first_idx:last_idx]),
        cu(DFT.(df.open[first_idx:last_idx])),
        cu(DFT.(df.high[first_idx:last_idx])),
        cu(DFT.(df.low[first_idx:last_idx])),
        cu(DFT.(df.close[first_idx:last_idx])),
        cu(DFT.(df.volume[first_idx:last_idx])),
        last_idx - first_idx + 1
    )
end
```

**Step 2: Strategy parameters as kernel constants:**
```julia
# Parameters are small (< 1KB), passed as kernel arguments via @Const
@kernel function indicator_kernel(
    @Const(gpu_data::GpuOHLCVData),
    @Const(params::NamedTuple),
    @Const(times::Vector{DateTime}),  # or use index as timestep offset
    output::AbstractArray{DFT}
)
    i = @index(Global, Linear)
    # Read directly from GPU arrays — no searchsortedlast needed
    window_start = max(1, i - lookback + 1)  # or use params.lookback
    close_window = @view(gpu_data.close[window_start:i])
    # ... compute indicators on GPU
    output[i] = result
end
```

**Step 3: Strategy-defined kernel — trait-based interface:**
```julia
# GpuBacktest/src/interface.jl
abstract type GPUKernel <: ExecAction end

# Trait: strategy opts into GPU by defining this method
function call!(
    ::Type{<:Strategy},
    ::GPUKernel,
    gpu_data::GpuOHLCVData,
    params::NamedTuple,
    output::AbstractArray{DFT}
) end  # <-- user implements with @kernel

# Default: CPU fallback (non-GPU strategies work unchanged)
function call!(s::Strategy, ::GPUKernel, gpu_data, params, output)
    for i in 1:gpu_data.n_candles
        output[i] = some_default_indicator(gpu_data, i, params)
    end
end

# Detection: does the strategy define a GPU kernel?
function has_gpu_kernel(::Type{<:Strategy})
    false  # by default, override for GPU strategies
end
```

### Q4: Zero-copy verification methodology

**Verification plan:**

1. **Profile the entire `start_gpu!` call:**
   ```julia
   using CUDA
   CUDA.@profile begin
       GPUKernel.@profile start_gpu!(s, ctx)
   end
   ```
   Look for:
   - `H2D (Host-to-Device)` transfers — should appear ONLY BEFORE the loop (data upload)
   - `D2H (Device-to-Host)` transfers — should appear ONLY AFTER the loop (results read), or for tiny signal arrays each timestep
   - Zero OHLCV-sized transfers (< 48 bytes per timestep = one float signal)

2. **Verify with `CUDA.@memory` snapshots:**
   ```julia
   CUDA.@memory before = CUDA.used_memory()
   start_gpu!(s, ctx)
   CUDA.@memory after = CUDA.used_memory()
   # after - before should be approximately OHLCV data size (upload) + output array size
   @assert after - before < sizeof(gpu_data) + sizeof(output) * 1.1  # <10% overhead
   ```

3. **NSight Compute (for NVIDIA) kernel analysis:**
   ```
   ncu --target-processes all --kernel-name indicator_kernel \
       --set full -o gpu_backtest_profile julia run_backtest.jl
   ```
   Check for:
   - `MemUtil` section: `H2D` and `D2H` bytes — should be near 0 during kernel execution
   - `Duration` section: kernel time dominates total time (>80%)

4. **Fail-fast assertion in code:**
   ```julia
   # GpuBacktest/src/verify.jl
   function assert_gpu_only!(s, ctx)
       @assert CUDA.functional() "CUDA GPU required"
       # Patch any CPU-side OHLCV accessor to error when called during GPU mode
       # Monkey-patch candleat, lowat, etc. to throw if called
   end
   ```

## Open questions
question-1 | Can KernelAbstractions handle dynamic dispatch for different strategy types? | Need to test kernel compilation with Strategy as type parameter
question-2 | How to handle variable-length lookback windows per strategy? | May need dynamic shared memory or max window pre-allocation
question-3 | Order state (pending orders, positions) - keep on CPU or migrate? | Phase 1-2 keep CPU; Phase 3 evaluates
question-4 | Memory capacity: how many candles fit on GPU? (e.g., 1M candles * 6 cols * 8 bytes = ~48MB) | Feasible for most backtests; chunking for larger
question-5 | Can KernelAbstractions `@kernel` handle `DateTime` arrays? | DateTime is a struct of (Int64, Int64, Int32); kernel must treat as raw bytes or convert to Unix timestamps
question-6 | Does `cu(::DataFrame)` work for all column types? | DataFrame columns must extract and `.=` a copy; `cu(DateTime)` may fail — may need `cu(Int64.(df.timestamp))` workaround
question-7 | How does GPU backtest interact with Opt's `Threads.@threads`? | Each thread can share the same GPU context (OK) or need separate streams; CUDA.jl has stream-per-thread model

## Approval gate
status: awaiting-approval
