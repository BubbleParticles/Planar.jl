# gpu-backtest - Work Plan

## TL;DR (For humans)

**What you'll get:** A phased feasibility analysis and implementation plan for running Planar backtests on GPU. The analysis covers: (1) how OHLCV data (currently in `SortedDict{TimeFrame, DataFrame}`) gets laid out as GPU arrays, (2) how the synchronous backtest loop maps to KernelAbstractions.jl kernels, (3) a trait-based `GPUKernel` interface on `Strategy` so users define kernels instead of `call!`, and (4) a zero-copy verification methodology using CUDA.@profile.

**Why this approach:** Three-phased de-risking — GPU-accelerate _indicator computation first_ (pure math on OHLCV columns, highest payoff), then _order fill/slippage_ (still pure math), then _full kernel_ (strategy + order logic). Each phase is independently testable and revertible. The kernel trait interface means existing CPU strategies are untouched; new GPU strategies opt in.

**What it will NOT do:** Rewrite the order book/position state on GPU (Phase 3+), support live trading GPU, write raw CUDA/ptx kernels (KernelAbstractions only), or multi-GPU distribution.

**Effort:** XL (3 phases, ~12-15 weeks)
**Risk:** High - Julia GPU KernelAbstractions interoperability with complex Julia type system (DataFrames, multiple dispatch inside kernels) is unproven at this scale
**Decisions I made for you:**
- Phase approach (indicator first, then fill, then full kernel) to de-risk
- KernelAbstractions.jl as the portable GPU kernel language (not raw CUDA)
- NVIDIA CUDA first, AMD/Metal later
- OHLCV data as column-major GPU arrays (SoA layout) for coalesced memory access
- Strategy state (positions, orders) stays on CPU in Phase 1-2
- Zero-copy verification via `CUDA.@profile` / `rocHPL` showing zero H2D/D2H during kernel execution

Your next move: **Approve or ask for a high-accuracy review** of the plan before execution begins.

---

> TL;DR (machine): XL effort, High risk. 3-phase GPU-acceleration of Planar backtesting: (1) indicator-only GPU kernels, (2) slippage/fill GPU, (3) full strategy kernel. KernelAbstractions.jl, CUDA-first, SoA layout for OHLCV, trait-based Strategy interface, zero-copy profile verification.

## Scope
### Must have
- [P1] OHLCV DataFrame-to-GPUArray conversion layer (SoA layout: timestamp, open, high, low, close, volume as separate CuArrays)
- [P1] GPUIndicatorKernel trait on Strategy — strategy defines `@kernel` function that receives per-timestep OHLCV window and returns signals
- [P1] CPU-backed GPUIndicatorKernel implementation (falls back to plain CPU for testing)
- [P1] Backtest loop variant for Phase 1: CPU order processing + GPU indicator eval for each timestep
- [P2] GPU slippage calculation kernel (access OHLCV arrays on GPU, compute fill price without CPU round-trip)
- [P3] Full GPU kernel where strategy + order logic runs entirely on GPU (no CPU state reads in hot path)
- [P1] Zero-copy verification: `CUDA.@profile` showing no host-device transfers in hot kernel loops

### Must NOT have (guardrails, anti-slop, scope boundaries)
- No custom CUDA/ptx kernels — use KernelAbstractions.jl exclusively
- No live trading GPU support — backtest/optimization only
- No multi-GPU distribution — single GPU only
- No rewriting order book on GPU in Phase 1 or 2 (Phase 3 evaluates this)
- No breaking existing CPU backtest path — GPU is opt-in via trait
- No rewriting the Data package's Zarr persistence layer

## Verification strategy
- Test decision: TDD — write GPU kernel tests against CPU reference BEFORE implementing GPU kernels
- Framework: `CUDA.@profile` for zero-copy validation, `Test` for correctness
- Evidence: Each phase produces `.omo/evidence/phase-<N>-gpu-backtest.md` with profile captures and correctness assertions

## Execution strategy
### Parallel execution waves
Wave 1 (Phase 0 foundation): Todos 1-3 (data layout, kernel interface, CPU reference impl) — can parallelize
Wave 2 (Phase 1): Todos 4-5 (GPU indicator kernel + integrated loop) — sequential
Wave 3 (Phase 2): Todos 6-7 (GPU slippage + fill math) — sequential
Wave 4 (Phase 3): Todo 8 (full kernel) — sequential

### Dependency matrix
| Todo | Depends on | Blocks | Can parallelize with |
| --- | --- | --- | --- |
| 1. Data layout | — | 4, 5, 6, 7, 8 | 2, 3 |
| 2. Kernel interface | — | 4, 8 | 1, 3 |
| 3. CPU ref kernel | — | 4, 5, 6, 8 | 1, 2 |
| 4. GPU indicator kernel | 1, 2, 3 | 5 | — |
| 5. Integrated loop P1 | 4 | 6 | — |
| 6. GPU slippage kernel | 1, 3 | 7 | — |
| 7. Integrated loop P2 | 5, 6 | 8 | — |
| 8. Full GPU kernel | 1, 2, 3, 4, 5, 6, 7 | — | — |

## Todos

- [ ] 1. **OHLCV DataFrame → GPUArray conversion layer**
  What to do:
  - Create a new package or submodule `GpuBacktest/src/layout.jl` that exposes `ohclv_to_gpu(ai::AssetInstance, tf::TimeFrame) -> NamedTuple` returning `(timestamp=CuArray{DateTime}, open=CuArray{DFT}, high=CuArray{DFT}, low=CuArray{DFT}, close=CuArray{DFT}, volume=CuArray{DFT})`.
  - The conversion must: extract `DataFrame` columns, `cu.(col)` each, wrap in a NamedTuple for SoA access.
  - For non-CUDA backends: `roc.(col)` or `mtl.(col)` based on `KernelAbstractions.get_backend()` or an env var `PLANAR_GPU_BACKEND`.
  - MUST NOT modify existing `AssetInstance.data` field — GPU arrays are a separate cache, computed lazily before kernel launch.
  - Must handle partial data: only upload the required date range window, not the entire history.
  - Must NOT break existing CPU code path — purely additive.
  Parallelization: Wave 1 | Blocked by: — | Blocks: 4
  References: `Instances/src/module.jl:69-70` (data field), `Data/src/candles.jl:10-22` (Candle struct), `Data/src/dataframes.jl` (DataFrame column layout)
  Acceptance criteria: `using GpuBacktest; gpu_data = ohclv_to_gpu(ai, tf"1m"); all(isa.(gpu_data.open, CuArray{DFT}))` returns true
  QA scenarios: happy — `cu(DataFrame(…))` columns match values; failure — empty DataFrame returns empty CuArrays
  Commit: Y | `feat(backtest): add OHLCV DataFrame-to-GPUArray conversion layer`

- [ ] 2. **`GPUKernel` trait interface on Strategy**
  What to do:
  - Define `GPUKernel <: ExecAction` and a trait `GPUKernelStrategy` that a strategy can implement.
  - Create the interface: `call!(s::GPUKernelStrategy, ::GPUKernel, gpu_data::NamedTuple, current_time::DateTime, params) -> NamedTuple` where `gpu_data` is the SoA NamedTuple from Todo 1.
  - The kernel function the user writes is decorated with `@kernel` from KernelAbstractions: `@kernel function my_kernel(gpu_data, current_time, params, output) ... end`.
  - Provide a default fallback that calls the regular `call!(s, current_time, ctx)` for non-GPU strategies (backward compat).
  - MUST NOT change the existing `call!` signature — entirely new dispatch path.
  Parallelization: Wave 1 | Blocked by: — | Blocks: 4
  References: `Strategies/src/interface.jl:10` (existing `call!`), `Strategies/src/module.jl:69-140` (Strategy struct), `Strategies/src/methods.jl` (method dispatch patterns)
  Acceptance criteria: `strategy isa GPUKernelStrategy` returns true for a strategy that defines `call!(::GPUKernel, …)`
  QA scenarios: happy — trait dispatch works; failure — non-GPU strategy still routes to CPU `call!`
  Commit: Y | `feat(backtest): add GPUKernel trait and strategy interface`

- [ ] 3. **CPU reference implementation of GPUKernel (for correctness testing)**
  What to do:
  - Implement `call!(s::Strategy, ::GPUKernel, gpu_data::NamedTuple, current_time::DateTime, params)` on the _CPU path_ that applies the same logic as the GPU kernel but on plain Julia arrays.
  - This serves as the ground truth for GPU kernel correctness — both must produce identical outputs for the same inputs.
  - Implement in `GpuBacktest/src/cpu_reference.jl`.
  - MUST match the GPU kernel signature exactly (same input types, same output format).
  - NOT for production — only for test assertions.
  Parallelization: Wave 1 | Blocked by: — | Blocks: 4, 5, 6
  References: `Strategies/src/interface.jl:10-53` (existing call! dispatch), `StrategyTools/src/oti.jl:5-15` (indicator computation patterns)
  Acceptance criteria: `cpu_reference(s, gpu_data, t, p) == gpu_kernel(s, gpu_data, t, p)` for random data within 1e-12
  QA scenarios: happy — bitwise identical outputs; failure — type mismatch errors
  Commit: Y | `feat(backtest): add CPU reference kernel implementation for GPU correctness testing`

- [ ] 4. **GPU indicator kernel (Phase 1 core)**
  What to do:
  - Implement the `@kernel` function that strategy authors write: `@kernel function indicator_kernel(gpu_data, current_time, params, output)`.
  - The kernel loops over timesteps using `@index(Global, Linear)` and evaluates the strategy's indicator logic on the GPU-resident OHLCV data.
  - For each timestep, the kernel reads a window of OHLCV data (configurable lookback), computes indicators, and writes signals to the output array.
  - MUST NOT perform any `searchsortedlast` (CPU function) inside the kernel — replace with direct array indexing.
  - The kernel returns per-timestep signals as a GPU array that the CPU loop reads for order processing.
  - Integrate with KernelAbstractions: `backend = get_backend(gpu_data.open); kernel = indicator_kernel(backend, 256); kernel(gpu_data, times, params, output, ndrange=n_timesteps)`.
  Parallelization: Wave 2 | Blocked by: 1, 2, 3 | Blocks: 5
  References: `SimMode/src/backtest.jl:111-134` (backtest loop), `Data/src/candles.jl:48-88` (candleat/closeat patterns), `StrategyTools/src/oti.jl` (indicator computation)
  Acceptance criteria: `kernel_output = run_gpu_indicator(s, gpu_data); cpu_output = run_cpu_indicator(s, cpu_data); all(isapprox.(kernel_output, cpu_output; atol=1e-10))` passes
  QA scenarios: happy — same results as CPU reference; failure — KernelAbstractions compilation errors on `DateTime` in kernel
  Commit: Y | `feat(backtest): implement GPU indicator kernel`

- [ ] 5. **Integrated Phase 1 backtest loop (CPU orders + GPU indicators)**
  What to do:
  - Create `start_gpu!(s::Strategy{Sim}, ctx::Context; kwargs...)` variant of the backtest loop.
  - Before the loop: upload OHLCV data to GPU via Todo 1, compile kernel via Todo 4.
  - During the loop: launch GPU kernel for current timestep batch (or single timestep), read resulting signal from GPU output array, run CPU order processing (existing `update!`).
  - After each batch: copy only the tiny signal/output array back to CPU (not OHLCV data).
  - MUST keep OHLCV data GPU-resident across timesteps — never re-upload each iteration.
  - Measure and verify with `CUDA.@profile` that the hot path has zero `H2D`/`D2H` transfers on OHLCV arrays.
  Parallelization: Wave 2 | Blocked by: 4 | Blocks: 6
  References: `SimMode/src/backtest.jl:57-138` (full backtest loop), `Opt/src/module.jl:467-528` (how optimization calls start!)
  Acceptance criteria: `CUDA.@profile start_gpu!(s, ctx)` shows no H2D/D2H transfers for OHLCV arrays during loop
  QA scenarios: happy — identical PnL to CPU run; failure — profile reveals OHLCV host-device copies
  Commit: Y | `feat(backtest): integrate GPU indicator kernel into backtest loop`

- [ ] 6. **GPU slippage/fill calculation kernel (Phase 2)**
  What to do:
  - Port the slippage math from `SimMode/src/slippage.jl:73-217` to a `@kernel` that runs on GPU.
  - The kernel receives: OHLCV GPU arrays (from Todo 1), the order's price and side, the commit amount, the candle index.
  - Kernel computes: `_priceskew`, `_volumeskew`, `_addslippage`, `_doclamp` all on GPU.
  - Returns the fill price and the actual fill amount (may differ due to volume constraints).
  - CPU `limitorder_ifprice!` reads the GPU-computed fill price instead of calling `lowat/highat/closeat/openat/volumeat` (which would trigger CPU DataFrame access).
  - This eliminates ALL CPU-side OHLCV data reads during order processing.
  Parallelization: Wave 3 | Blocked by: 1, 3 | Blocks: 7
  References: `SimMode/src/slippage.jl:36-217` (slippage functions), `SimMode/src/orders/limit.jl:84-178` (limitorder_ifprice!, limitorder_ifvol!, _fill_happened)
  Acceptance criteria: `gpu_fill_price = gpu_slippage(ai, order, date, amount); cpu_fill_price = cpu_slippage(ai, order, date, amount); abs(gpu - cpu) < 1e-8`
  QA scenarios: happy — per-order fill prices match; failure — low/high/close access from DataFrame inside kernel (illegal)
  Commit: Y | `feat(backtest): add GPU slippage and fill calculation kernel`

- [ ] 7. **Integrated Phase 2 backtest loop (GPU indicators + GPU slippage)**
  What to do:
  - Modify `start_gpu!` to also use GPU-based slippage for order fills.
  - The only CPU operations remaining: order book management (queue, cancel, commit, trade creation), position management, strategy state.
  - Profile to verify zero OHLCV data reads from CPU — all OHLCV access happens inside GPU kernels.
  - The CPU still reads: committed amounts, order lists, position sizes (all small, not OHLCV-sized).
  Parallelization: Wave 3 | Blocked by: 5, 6 | Blocks: 8
  References: `SimMode/src/orders/updates.jl:90-140` (update! loop that calls order!), `SimMode/src/trades.jl` (trade! function)
  Acceptance criteria: `CUDA.@profile start_gpu!(s, ctx)` shows zero array H2D/D2H transfers — only scalar results per timestep
  QA scenarios: happy — 95%+ GPU utilization in NSight Compute; failure — CPU-side `lowat(ai, date)` calls remain
  Commit: Y | `feat(backtest): integrate GPU slippage into full Phase 2 backtest`

- [ ] 8. **Full GPU kernel (Phase 3 — strategy + order logic)**
  What to do:
  - Evaluate whether the complete backtest loop (strategy call + order matching + position update) can run as a single GPU kernel.
  - This requires representing order book state as GPU-resident arrays (buy order prices, amounts, sell order prices, amounts).
  - Strategy + order processing per timestep become one compound kernel with shared state arrays.
  - The challenge: branching on strategy logic + conditional order matching within a kernel is complex and may have warp divergence.
  - Open questions: (a) how to handle `cancel!`, `trade!`, position updates (mutable state) on GPU, (b) how to avoid `Order` object allocation (heap alloc) inside kernel.
  - This Phase 3 may conclude "not feasible without major restructuring" — accept that and document for future work.
  Parallelization: Wave 4 | Blocked by: 1, 2, 3, 4, 5, 6, 7 | Blocks: —
  References: `Executors/src/orders/market.jl:11-34` (marketorder), `SimMode/src/orders/limit.jl:61-178` (order!), `SimMode/src/positions/state.jl` (position updates)
  Acceptance criteria: A working prototype that runs 3 backtests on GPU with identical results to CPU (same PnL curve, same trade list)
  QA scenarios: happy — full GPU backtest matches CPU; failure — warp divergence causes slowdown >2x CPU
  Commit: Y | `feat(backtest): full GPU backtest kernel (Phase 3 prototype)`

## Final verification wave
- [ ] F1. **Phase 1 zero-copy verification** — `CUDA.@profile start_gpu!(s, ctx)` captures showing no H2D/D2H on OHLCV arrays
- [ ] F2. **Phase 2 zero-copy verification** — All OHLCV Data access eliminated from CPU during kernel runtime
- [ ] F3. **Result correctness** — GPU backtest PnL matches CPU reference within floating point tolerance (`1e-10` relative)
- [ ] F4. **LSP diagnostics clean on all new code** — `lsp_diagnostics` on `GpuBacktest/src/` returns zero errors
- [ ] F5. **Optimization integration** — `Opt` multi-threaded optimization works with Phase 2 GPU backtest (each thread on same GPU, or serialized)

## Commit strategy
1. `feat(backtest): add OHLCV DataFrame-to-GPUArray conversion layer`
2. `feat(backtest): add GPUKernel trait and strategy interface`
3. `feat(backtest): add CPU reference kernel implementation for GPU correctness testing`
4. `feat(backtest): implement GPU indicator kernel`
5. `feat(backtest): integrate GPU indicator kernel into backtest loop`
6. `feat(backtest): add GPU slippage and fill calculation kernel`
7. `feat(backtest): integrate GPU slippage into full Phase 2 backtest`
8. `feat(backtest): full GPU backtest kernel (Phase 3 prototype)`

## Success criteria
- A `GpuBacktest` package (or module) exists in the monorepo
- Phase 1 indicator GPU backtest shows identical PnL to CPU reference
- `CUDA.@profile` on Phase 2 confirms zero OHLCV data transfer during kernel loop
- GPU backtest is at least 2x faster than single-thread CPU backtest for large universes (10+ assets, 500K+ candles)
- Opt multi-threaded optimization can use GPU-accelerated backtest function
- All existing tests pass (CPU backtest path untouched)
