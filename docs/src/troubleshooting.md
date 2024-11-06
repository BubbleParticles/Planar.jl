# Troubleshooting

## Precompilation Issues

- **Dependency Conflicts:** After updating the repository, new dependencies may cause precompilation to fail. Ensure all packages are fully resolved by running:

```julia
include("resolve.jl")
recurse_projects() # Optionally set update=true
```

- **Starting the REPL:** Rather than starting a REPL and then activating the project, launch Julia directly with the project as an argument to avoid precompilation issues:

```julia
julia --project=./Vindicta
```

- **Python-Dependent Precompilation:** Precompiling code that relies on Python, such as exchange functions, may lead to segmentation faults. To prevent this:
  - Clear global caches, like `TICKERS_CACHE100`, before precompilation. Ensure global constants are empty, as their contents are serialized during precompilation.
  - Avoid using macros that directly insert Python objects, such as `@py`, in precompilable functions.
  
- **Persistent Precompilation Skipping:** If a package consistently skips precompilation, check if `JULIA_NOPRECOMP` environment variable includes dependencies of the package.

- **`_debug_` not found** happens when trying to precompile a strategy with debug enabled (`JULIA_DEBUG="all"`) while the module (`Vindicta` or a submodule like `SimMode`) has been not precompiled with debug enabled.

## Python Module Discovery

- **Missing Python Dependencies:** If Python reports missing modules, execute the following in the Julia REPL with the current repository activated:

```julia
; find ./ -name .CondaPkg | xargs -I {} rm -r {} # Removes existing Conda environments
using Python # Activates our Python wrapper with CondaPkg environment variable fixes
import Pkg; Pkg.instantiate()
```

- **Force CondaPkg Environment Resolution:** In the case of persistent issues, force resolution of the CondaPkg environment by running:

```julia
using Python.PythonCall.C.CondaPkg
CondaPkg.resolve(force=true)
```

Then, restart the REPL.

## Unresponsive Exchange Instance

- **Idle Connection Closure:** If an exchange instance remains idle for an extended period, the connection may close. It should time out according to the `ccxt` exchange timeout. Following a timeout error, the connection will re-establish, and API-dependent functions will resume normal operation.

## Data Saving Issues

- **LMDB Size Limitations:** When using LMDB with Zarr, the initial database size is set to 64MB by default. To increase the maximum size:

```julia
using Data
zi = zinstance()
Data.mapsize!(zi, 1024) # Sets the DB size to 1GB
Data.mapsize!!(zi, 100) # Adds 100MB to the current mapsize (resulting in 1.1GB total)
```

Increase the mapsize before reaching the limit to continue saving data.

## Misaligned Plotting Tooltips

- **Rendering Bugs:** If you encounter misaligned tooltips with `WGLMakie`, switch to `GLMakie` to resolve rendering issues:

```julia
using GLMakie
GLMakie.activate!()
```

## Segfaults when saving ohlcv
The default `ZarrInstance` uses an `LMDB` store. It is possible that the underlying lmdb database has been corrupted. To fix this the database must be re-created. Either delete the database manually (default path is in under `Data.DATA_PATH`) or run this code on a fresh repl:

``` julia
using Data
Data.zinstance(force=true)
```

## LMDB not available
LMDB requires a precompiled binary. If it is not available for your platform you can disable it by setting the `data_store` preference in your strategy (or top package) `Project.toml`.

``` toml
[preferences.Data]
data_store = "" # Disables lmdb (set it back to "lmdb" to enable lmdb)
```

## Debugging in vscode
To trigger breakpoints inside functions wrapped with a custom logger, like when executing a strategy with `start!(::Strategy)`, it might be necessary to disable loading of `Base.CoreLogging` compiled module. Inside your user settings modify the option `julia.debuggerDefaultCompiled` as shown below:

``` json
    "julia.debuggerDefaultCompiled": [
        "ALL_MODULES_EXCEPT_MAIN",
        "-Base.CoreLogging"
    ],
```
