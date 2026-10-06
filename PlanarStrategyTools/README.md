# PlanarStrategyTools

Indicators and helper functions for Planar strategies, built on top of
[OnlineTechnicalIndicators.jl](https://github.com/baguiyi/OnlineTechnicalIndicators.jl).

## Contents

- **Cross indicators:** stochastic RSI, VTX, Ultimate Oscillator, ATR-based signals,
  sorted OBV with SMA crossovers.
- **Moving extrema:** running `minimum`/`maximum` buffers for signals.
- **Signal infrastructure:** `Signals17` definition handling, trend/slope tracking,
  `ismissingvalue` on indicator state types.

## Usage

```julia
using PlanarStrategyTools

ext = MovingExtrema(3)
push!(ext, 1.0); push!(ext, 3.0); push!(ext, 2.0)
extrema(ext)  # (1.0, 3.0)
```

## Relation to the parent monorepo

This is one of the foundational strategy packages in the
[`Planar.jl`](https://github.com/BubbleParticles/Planar.jl) ecosystem (registered
on [Julia's General registry](https://juliahub.com/ui/P/PlanarStrategyTools)).
It is consumed by downstream packages and user strategies — see the monorepo
[`PACKAGING.md`](../PACKAGING.md) for registry status and layout details.
