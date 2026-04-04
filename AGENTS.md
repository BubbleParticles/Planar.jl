AGENTS
======

Developer notes for running the repository tools and tests.

Before running or developing the bot, or executing the test suite locally, ensure the environment variables from the project's .envrc are loaded. The .envrc sets critical variables used by tests and the development environment (JULIA_PROJECT, JULIA_LOAD_PATH, JULIA_CONDAPKG_ENV, etc.).

To load .envrc locally (recommended):

- Use direnv: run `direnv allow` in the repository root to automatically load .envrc into your shell.
- Or source the file manually: `source .envrc`.

Failing to load .envrc may cause missing package errors during test runs (e.g., packages installed into user/.conda, missing JULIA_PROJECT), unexpected precompilation behavior, or other environment-dependent failures.

Include this check in your developer workflow before running `julia --project=PlanarDev test` or `julia --project=PlanarDev PlanarDev/test/runtests.jl`.

Note: resolve.jl utilities

The repository provides a resolve.jl helper that includes utilities for dependency management and cache cleanup. In particular, the purge_compilecache utility in resolve.jl can be used to clear Julia's compiled cache and help resolve precompilation or stale-artifact issues. The same resolve.jl file also contains helpers to update and synchronize project package dependencies across the repository; use these utilities when dependency resolution or precompilation problems arise.
