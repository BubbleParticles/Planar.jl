# JULIA_NOPRECOMP has been removed from all package source files.
# Package entry files now unconditionally include("module.jl") with
# optional include("precompile.jl") conditional on JULIA_PRECOMP.
# See docs/src/devdocs.md for the current precompilation strategy.
ENV["JULIA_PRECOMP"] = ""
