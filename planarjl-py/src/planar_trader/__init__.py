"""planarjl-py — Python driver for the Planar trading framework.

Planar is a Julia framework for building trading bots (backtesting, paper and
live execution on 100+ exchanges through CCXT). This package installs the
`planar` command-line tool, which bootstraps a Planar project and runs
strategies from Python by driving the Julia engine.

Strategies are written in Julia and live under ``user/strategies/`` in your
project (native strategy authoring in Python is planned, see
https://github.com/BubbleParticles/Planar.jl/issues/7).
"""

try:
    from importlib.metadata import PackageNotFoundError, version as _metadata_version

    __version__ = _metadata_version("planarjl-py")
except PackageNotFoundError:
    __version__ = "0.0.0"
