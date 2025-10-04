# only use eval in CI
if get(ENV, "CI", "false") == "true"
    include("noprecomp.jl")
end
using Pkg: Pkg;
Pkg.activate("Planar")
let dse = expanduser("~/.julia/environments/v$(VERSION.major).$(VERSION.minor)/")
    if dse ∉ LOAD_PATH
        push!(LOAD_PATH, dse)
    end
end
using Documenter, DocStringExtensions, Suppressor

# Modules
using Planar
project_path = dirname(dirname(Pkg.project().path))
function use(name, args...; activate=false)
    activate_and_import() = begin
        prev = Pkg.project().path
        try
            Pkg.activate(path)
            Pkg.instantiate()
            @eval using $name
        catch
        end
        Pkg.activate(prev)
    end

    path = joinpath(project_path, args...)
    @suppress if activate
        activate_and_import()
    else
        try
            if endswith(args[end], ".jl")
                include(path)
                @eval using .$name
            else
                path ∉ LOAD_PATH && push!(LOAD_PATH, path)
                Pkg.instantiate()
                @eval using $name
            end
        catch
            activate_and_import()
        end
    end
end

if isempty(get(ENV, "PLANAR_DOCS_SKIP_BUILD", ""))
    withenv("PLANAR_DOCS_SKIP_BUILD" => "true") do
        run(`$(Base.julia_cmd()) --project=Planar docs/make.jl`)
    end
end

get(ENV, "PLANAR_DOCS_LOADED", "false") == "true" || begin
    use(:Prices, "Data", "src", "prices.jl")
    use(:Fetch, "Fetch")
    use(:Processing, "Processing")
    use(:Instruments, "Instruments")
    use(:Exchanges, "Exchanges")
    use(:Plotting, "Plotting")
    use(:Watchers, "Watchers")
    use(:Engine, "Engine")
    use(:Pbar, "Pbar")
    use(:Metrics, "Metrics")
    use(:Optim, "Optim")
    use(:Ccxt, "Ccxt")
    use(:Python, "Python")
    use(:Strategies, "Strategies")
    use(:StrategyTools, "StrategyTools")
    use(:StrategyStats, "StrategyStats")
    using Planar.Data.DataStructures
    @eval using Base: Timer
    ENV["LOADED"] = "true"
end

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

get(ENV, "PLANAR_DOCS_SKIP_BUILD", "") == "true" && exit()

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
            "What is Planar?" => "index.md"
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
                "Prices" => "API/prices.md",
                "Processing" => "API/processing.md",
                "Python Integration" => "API/python.md",
                "Metrics" => "API/metrics.md",
                "Strategies" => "API/strategies.md",
                "Strategy Tools" => "API/strategytools.md",
                "Strategy Stats" => "API/strategystats.md",
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
