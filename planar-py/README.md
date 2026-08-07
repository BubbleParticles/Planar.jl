# planar-trader

Python driver for the [Planar](https://github.com/BubbleParticles/Planar.jl)
trading framework. Planar is a Julia framework for building trading bots —
backtesting, paper and live execution on 100+ exchanges through CCXT.

`pip install planar-trader` gives you the `planar` command, which bootstraps a
Planar project and runs strategies from Python by driving the Julia engine.

> The PyPI name `planar` is taken by an unrelated package, hence `planar-trader`.
> Native *strategy authoring in Python* is the open milestone of
> [issue #7](https://github.com/BubbleParticles/Planar.jl/issues/7); today
> strategies are written in Julia and executed through this CLI.

## Requirements

- Julia ≥ 1.12 on `PATH` (https://julialang.org/downloads/)
- Python ≥ 3.10

## Usage

```bash
pip install planar-trader

# Bootstrap a project: adds the Planar registry, installs the Planar package,
# and creates the user/ layout (first run downloads packages).
planar init mybot
cd mybot

# Run a strategy in backtest (sim) mode
planar run MyStrategy --mode sim --exchange binanceusdm --sandbox

# Paper or live trading
planar run MyStrategy --mode paper
planar run MyStrategy --mode live

planar version
```

Strategies live in `user/strategies/` and are registered in `user/planar.toml`:

```toml
[sources]
MyStrategy = "strategies/MyStrategy/Project.toml"
```

Create a strategy with the `planar`-provided template (see the Planar.jl docs on
strategy authoring), or copy any strategy from the
[Planar.jl examples](https://github.com/BubbleParticles/Planar.jl/tree/master/examples).

## Development

```bash
cd planar-py
uv sync --extra dev    # or: pip install -e .[dev]
pytest
uv build              # build the sdist + wheel
```

## Publishing

See `PACKAGING.md` at the repository root. CI publishes to TestPyPI on `py-v*`
tags and to PyPI on `v*` tags (set the `PYPI_API_TOKEN` repository secret):

```bash
git tag py-v0.1.0 && git push origin py-v0.1.0
```
