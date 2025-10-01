include("noprecomp.jl")
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
        run(`julia --project=Planar docs/make.jl`)
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
    use(:StrategyTools, "StrategyTools")
    use(:StrategyStats, "StrategyStats")
    using Planar.Data.DataStructures
    @eval using Base: Timer
    ENV["LOADED"] = "true"
end
exit()

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

makedocs(;
    sitename="Planar.jl",
    pages=[
        "Introduction" => ["presentation.md", "index.md"],
        "Types" => "types.md",
        "Strategies" => "strategy.md",
        "Engine" => [
            "Executors" => "engine/engine.md",
            "Backtesting" => "engine/backtesting.md",
            "Paper" => "engine/paper.md",
            "Live" => "engine/live.md",
            "Features" => "engine/features.md",
        ],
        "Exchanges" => "exchanges.md",
        "Data" => "data.md",
        "Watchers" => [
            "Interface" => "watchers/watchers.md",
            "Apis" => [
                "watchers/apis/coingecko.md",
                "watchers/apis/coinpaprika.md",
                "watchers/apis/coinmarketcap.md",
            ],
        ],
        "Metrics" => "metrics.md",
        "Optim" => "optimization.md",
        "Plotting" => "plotting.md",
        "Misc" => [
            "Config" => "config.md",
            "Disambiguation (Glossary)" => "disambiguation.md",
            "Troubleshooting" => "troubleshooting.md",
            "Devdocs" => "devdocs.md",
            "Contacts" => "contacts.md",
        ],
        "Customizations" => [
            "Overview" => "customizations/customizations.md",
            "Orders" => "customizations/orders.md",
            "Backtester" => "customizations/backtest.md",
            "Exchanges" => "customizations/exchanges.md",
        ],
        "API" => [
            "API/collections.md",
            "API/data.md",
            "API/ccxt.md",
            "API/dfutils.md",
            "API/executors.md",
            "API/exchanges.md",
            "API/fetch.md",
            "API/engine.md",
            "API/instances.md",
            "API/instruments.md",
            "API/misc.md",
            "API/optimization.md",
            "API/pbar.md",
            "API/plotting.md",
            "API/prices.md",
            "API/processing.md",
            "API/python.md",
            "API/metrics.md",
            "API/strategies.md",
            "API/strategytools.md",
            "API/strategystats.md",
        ],
    ],
    remotes=nothing,
    format=Documenter.HTML(;
        sidebar_sitename=false,
        size_threshold_ignore=[
            "watchers/watchers.md", "API/instances.md", "API/executors.md"
        ],
    )
)
