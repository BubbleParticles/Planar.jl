# only use eval in CI
if get(ENV, "CI", "false") == "true"
    include("noprecomp.jl")
end
using Pkg: Pkg
Pkg.activate("Planar")
push!(LOAD_PATH, "@stdlib")
using Documenter, DocStringExtensions, Suppressor

# Modules
using Planar
using PlanarCore
using PlanarOptim
using PlanarPython
using PlanarStrategyTools
using PlanarStrategyStats
using PlanarCore.Data.DataStructures
@eval using Base: Timer
# Bind submodules with short names for @docs/@ref resolution
@eval const Metrics = PlanarCore.Metrics
@eval const Strategies = PlanarCore.Strategies
@eval const Engine = Planar.Engine

function filter_strategy(t)
    try
        if startswith(string(nameof(t)), "Strategy")
            false
        else
            true
        end
    catch
        false
    end
end

# Read version from Planar/Project.toml
function get_planar_version()
    project_file = joinpath(@__DIR__, "..", "Planar", "Project.toml")
    if isfile(project_file)
        content = read(project_file, String)
        m = match(r"version\s*=\s*\"([^\"]*)\"", content)
        return m !== nothing ? m[1] : "unknown"
    end
    return "unknown"
end

planar_version = get_planar_version()

makedocs(;
    sitename="Planar.jl",
    pages=[
        "Introduction" => [
            "Overview" => "presentation.md",
            "What is Planar?" => "index.md",
            "Comparison with other frameworks" => "comparison.md",
        ],
        "Getting Started" => [
            "Overview" => "getting-started/index.md",
            "Quick Start" => "getting-started/quick-start.md",
            "Installation" => "getting-started/installation.md",
            "First Strategy" => "getting-started/first-strategy.md",
        ],
        "User Guides" => [
            "Strategy Development" => "strategy.md",
            "Data Management" => "data.md",
            "Execution Modes" => [
                "Overview" => "engine/engine.md",
                "Backtesting" => "engine/backtesting.md",
                "Paper Trading" => "engine/paper.md",
                "Live Trading" => "engine/live.md",
                "Mode Comparison" => "engine/mode-comparison.md",
                "Features" => "engine/features.md",
            ],
            "Optimization" => "optimization.md",
            "Visualization" => "plotting.md",
            "Performance Analysis" => "metrics.md",
        ],
        "Data Sources" => [
            "Exchanges" => "exchanges.md",
            "Watchers" => [
                "Interface" => "watchers/watchers.md",
                "APIs" => [
                    "CoinGecko" => "watchers/apis/coingecko.md",
                    "CoinPaprika" => "watchers/apis/coinpaprika.md",
                    "CoinMarketCap" => "watchers/apis/coinmarketcap.md",
                ],
            ],
        ],
        "Advanced Topics" => [
            "Customization & Extensions" => [
                "Overview" => "customizations/customizations.md",
                "Custom Orders" => "customizations/orders.md",
                "Backtester Customization" => "customizations/backtest.md",
                "Exchange Extensions" => "customizations/exchanges.md",
            ],
            "Type System" => "types.md",
            "Developer Documentation" => "devdocs.md",
        ],
        "Reference" => [
            "Documentation Index" => "documentation-index.md",
            "API Documentation" => [
                "Collections" => "API/collections.md",
                "Data" => "API/data.md",
                "CCXT" => "API/ccxt.md",
                "DataFrame Utils" => "API/dfutils.md",
                "Executors" => "API/executors.md",
                "Exchanges" => "API/exchanges.md",
                "Fetch" => "API/fetch.md",
                "Engine" => "API/engine.md",
                "Instances" => "API/instances.md",
                "Instruments" => "API/instruments.md",
                "Miscellaneous" => "API/misc.md",
                "Optimization" => "API/optimization.md",
                "Progress Bars" => "API/pbar.md",
                "Plotting" => "API/plotting.md",
                "Processing" => "API/processing.md",
                "Python Integration" => "API/python.md",
                "Metrics" => "API/metrics.md",
                "Strategies" => "API/strategies.md",
                "PlanarStrategyTools" => "API/strategytools.md",
                "PlanarStrategyStats" => "API/strategystats.md",
            ],
            "Configuration" => "config.md",
            "Glossary" => "disambiguation.md",
        ],
        "Support" => [
            "Troubleshooting" => "troubleshooting.md",
            "Community" => "contacts.md",
        ],
    ],
    repo="https://github.com/BubbleParticles/Planar.jl",
    format=Documenter.HTML(;
        sidebar_sitename=false,
        repolink="https://github.com/BubbleParticles/Planar.jl",
        inventory_version=planar_version,
        size_threshold_ignore=[
            "watchers/watchers.md", "API/instances.md", "API/executors.md"
        ],
    )
)