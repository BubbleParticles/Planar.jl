# Minimal runner for Collections tests only
# Run: julia --project=/Planar.jl/PlanarCore/test /Planar.jl/PlanarCore/test/run_collections_only.jl

using Pkg
Pkg.develop(Pkg.PackageSpec(path=joinpath(@__DIR__, "..")))
Pkg.resolve()

# Load everything needed
using Test
using PlanarCore
using PlanarCore.Collections
using PlanarCore.Instances
using PlanarCore.Instances.Exchanges.ExchangeTypes: CcxtExchange, ExchangeID, ExcPrecisionMode
using PlanarCore.Instances.Exchanges.ExchangeTypes.OrderedCollections: OrderedSet
using PlanarCore.Instances.Data.TimeTicks: TimeFrame, DateTime, now, Dates
using PlanarCore.Instances.Data.DataFrames: DataFrame
using PlanarCore.Instances.Data.TimeTicks.Lang: Option
using PlanarCore.Instances: NoMarginInstance
using PlanarCore.Instances.Instruments: AbstractAsset, parse
using PlanarCore.Instances.Misc: NoMargin, TimeTicks, Lang
using PlanarCore.Instances.DataStructures: SortedDict

@info "Imports done at $(time())"

# Include the test file
include(joinpath(@__DIR__, "Collections", "runtests.jl"))

@info "Collections test done at $(time())"
