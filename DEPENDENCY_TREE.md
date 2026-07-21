# Dependency Tree

Packages are listed from foundational (few/no local deps) to application-level. Each package's direct local and external dependencies are shown.

## Rules

- Arrows point **downstream** (foundational → application-level). An upstream package must never `using` a downstream one.
- A package must list all directly-imported packages in its `[deps]`; accessing a module as `Dep.SubModule` is OK as long as `Dep` is in `[deps]`.
- `test/Project.toml` must have **no** `name`, `uuid`, `version`, or `authors` header.
- Test dependencies should be minimized via `const` aliases through already-loaded parent modules.
- `Manifest.toml` paths must be relative to the `test/` directory, not absolute.

---

## Foundational Layer

```
Lang
  Deps: Distributed, DocStringExtensions, Logging, PrecompileTools, Preferences
  ↓

TimeTicks
  Deps: Lang, Dates, Reexport, Serialization, TimeFrames
  @reexport using Dates
  ↓

Pbar
  Deps: TimeTicks, Term
  ↓

Misc
  Deps: TimeTicks, [ConcurrentCollections, Dates, Distributed, DocStringExtensions,
        FunctionalCollections, JSON3, Logging, LoggingExtras, OrderedCollections,
        Pkg, PrecompileTools, Reexport, Serialization, TOML]
  @reexport using TimeTicks
```

## Exchange & Data Layer

```
Python
  Deps: Lang, [Dates, DocStringExtensions, Pkg, PrecompileTools, PythonCall, Reexport]
  ↓

Ccxt
  Deps: Misc, [FileWatching, HTTP, JSON3, MbedTLS, OrderedCollections,
        PrecompileTools, WebSockets]
  └── CcxtGateway (submodule: HTTP, JSON3, OrderedCollections, WebSockets)
  └── [weak dep] Python → CcxtPythonExt
  ↓

ExchangeTypes
  Deps: Ccxt, [FunctionalCollections, JSON3, OrderedCollections, Serialization]
  (Misc reexported via Ccxt)
  ↓

Data
  Deps: Misc, [CodecZlib, DataFrames, DataFramesMeta, DataStructures, LMDB,
        Reexport, Serialization, Zarr]
  ↓

Instruments
  Deps: Lang, Misc, [Printf]
  (Misc, TimeTicks reexported)
```

## Processing Layer

```
Processing
  Deps: Data, [Pbar, StatsBase]
  └── uses Data.Misc.Lang, Data.Misc.TimeTicks
  ↓

Exchanges
  Deps: ExchangeTypes, Data, Instruments, [Coverage, JSON, Pbar, Reexport, Serialization]
  @reexport using ExchangeTypes
  └── uses ExchangeTypes.Ccxt, Instruments.Misc, etc.
  ↓

OrderTypes
  Deps: ExchangeTypes, Instruments
  ↓

Instances
  Deps: Exchanges, OrderTypes
  └── deeply accesses Exchanges.ExchangeTypes, Exchanges.Data, Exchanges.Instruments,
        Exchanges.Misc, Data.DataFrames, Data.DataStructures
```

## Application Layer

```
Fetch
  Deps: Exchanges, Processing
  └── uses Exchanges.Instruments, Exchanges.Ccxt, Exchanges.Data, Processing.Pbar
  ↓

Collections
  Deps: Instances
  ↓

Strategies
  Deps: Collections, [Pkg]
  └── accesses Instances.Exchanges, Instances.Data through Collections
  ↓

Simulations
  Deps: Data, [IterTools, Random, Statistics, StatsBase]
  └── uses Data.Misc, Data.Misc.Lang, Data.Misc.TimeTicks
  ↓

Executors
  Deps: Strategies
  └── uses Strategies.OrderTypes, Strategies.Instances, Strategies.Instruments,
        Strategies.Misc through Strategies
  ↓

SimMode
  Deps: Executors, Simulations, [Pbar]
  ↓

Stubs
  Deps: SimMode, [CSV, Pkg, Serialization]
  └── accesses Strategies.Exchanges through SimMode
  ↓

Watchers
  Deps: Fetch, [HTTP, JSON3, Statistics, URIs]
  └── uses Fetch.Data, Fetch.Python, Fetch.Misc
  ↓

PaperMode
  Deps: Fetch, SimMode
  └── deeply accesses SimMode.Executors, Executors.*, Instances.Exchanges, Instances.Data
  ↓

LiveMode
  Deps: PaperMode, Watchers, [LRUCache]
  └── deeply accesses PaperMode.Executors, Executors.*, Instances.Exchanges,
        Exchanges.Python, Watchers.WatchersImpls
  ↓

Remote
  Deps: LiveMode, [JSON, PrettyTables, Telegram]
  └── uses LiveMode.Misc, LiveMode.Executors, LiveMode.Strategies
  ↓

Engine
  Deps: LiveMode
  └── deeply accesses LiveMode.PaperMode, PaperMode.SimMode, SimMode.*,
        Strategies.Instances, Instances.Exchanges, Simulations.Processing
```

## Analysis & Tooling Layer

```
Scrapers
  Deps: Processing, Instruments, [CSV, CodecZlib, DBnomics, EzXML, HTTP, URIs, ZipFile]
  ↓

Metrics
  Deps: Executors, Simulations, [Pkg, Stubs]
  ↓

StrategyStats
  Deps: Data, ExchangeTypes, [Logging, OnlineTechnicalIndicators]
  └── Query (submodule)
  └── [weak deps] CausalityTools, EffectSizes, StatsBase, StatsModels → CorrExt
  ↓

FeatureSelection
  Deps: Processing, Strategies, [Clustering, Distances, Distributions, GLM,
        LinearAlgebra, OnlineStats, OnlineTechnicalIndicators, Statistics, StatsBase]
  ↓

StrategyTools
  Deps: Planar, [OnlineTechnicalIndicators, Pkg, Statistics]
  ↓

Plotting
  Deps: Metrics, Processing, [Makie, Random]
  └── [weak dep] Opt → OptimizationExt
  ↓

Opt
  Deps: Metrics, Pbar, SimMode, [BlackBoxOptim, Optimization, OptimizationBBO,
        OptimizationCMAEvolutionStrategy, OptimizationEvolutionary, OptimizationManopt,
        OptimizationMetaheuristics, OptimizationOptimJL, Pkg, Printf, REPL, Random, Symbolics]
  └── [weak deps] BayesianOptimization → BayesExt, ModelingToolkit
  ↓

Planar
  Deps: Engine, Remote, [MacroTools, Pkg, REPL, Random]
```

## Top-Level Packages

```
PlanarDev
  Deps: Opt, Planar, Scrapers, Stubs, [Pkg, Random, Reexport]
  ↓

PlanarInteractive
  Deps: Metrics, Opt, Planar, Plotting, Scrapers, Watchers,
        [PackageCompiler, Pkg, WGLMakie]
  ↓

Cli
  Deps: Data, Exchanges, Fetch, Misc, Processing, [Comonicon]
```

## User Strategy Packages

```
BBWithOpt:     Planar, Opt, OnlineTechnicalIndicators
ExampleMargin: Planar, Metrics, Opt, Watchers
TwoIntervals:  Planar, OnlineTechnicalIndicators
BollingerBands: Planar, OnlineTechnicalIndicators
TwoParameters: Planar, OnlineTechnicalIndicators
MarginStrat:   Planar, OnlineTechnicalIndicators
SimpleStrategy: Planar
Load:           Planar, Metrics, Scrapers, Stubs, PackageCompiler, PrecompileTools
```

## Total: 40 packages (+7 user strategies)

### Legend

- Local dependencies are listed first (package name only).
- External dependencies are grouped in `[...]`.
- `└──` indicates submodules or weak dependencies/extensions.
- `@reexport` means the package re-exports another package's exports via `Reexport.jl`.
- Arrows (`↓`) indicate the direction of dependencies: upstream → downstream.
