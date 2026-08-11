"""ccxt-gateway: High-performance self-hosted gateway for 100+ crypto exchanges via CCXT."""

try:
    from importlib.metadata import PackageNotFoundError, version as _metadata_version

    __version__ = _metadata_version("ccxt-gateway")
except PackageNotFoundError:
    __version__ = "0.0.0"
