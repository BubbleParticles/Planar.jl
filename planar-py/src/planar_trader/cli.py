"""`planar` command-line interface."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

from . import __version__
from .runner import (
    RUN_STRATEGY_SCRIPT,
    PlanarError,
    find_julia,
    install_planar,
    run_julia,
)

PLANAR_TOML_TEMPLATE = """\
# Planar user configuration (see the Planar.jl docs for the full schema).
# Register project-based strategies under [sources], e.g.:
#
#   [sources]
#   MyStrategy = "strategies/MyStrategy/Project.toml"
#
[sources]
"""


def cmd_version(_args: argparse.Namespace) -> int:
    """Print the CLI and engine versions."""
    print(f"planar-trader {__version__} (planar CLI)")
    try:
        print(f"julia: {find_julia()}")
    except PlanarError as err:
        print(f"julia: NOT FOUND ({err})")
        return 1
    return 0


def cmd_init(args: argparse.Namespace) -> int:
    """Bootstrap a Planar project: Julia project + Planar + user/ layout."""
    proj = Path(args.dir).resolve()
    if proj.exists() and any(proj.iterdir()):
        print(f"error: {proj} already exists and is not empty", file=sys.stderr)
        return 1
    proj.mkdir(parents=True, exist_ok=True)

    user_dir = proj / "user"
    strategies_dir = user_dir / "strategies"
    strategies_dir.mkdir(parents=True, exist_ok=True)
    (user_dir / "planar.toml").write_text(PLANAR_TOML_TEMPLATE)

    print(f"Adding the Planar registry and the Planar package to {proj} …")
    print("(first run downloads the packages and may take a few minutes)")
    try:
        install_planar(proj)
    except (PlanarError, subprocess.CalledProcessError) as err:  # noqa: F821
        print(f"error: failed to install Planar: {err}", file=sys.stderr)
        return 1

    print("Done. Next steps:")
    print(f"  cd {proj}")
    print("  create a strategy under user/strategies/ and register it in user/planar.toml")
    print("  planar run <StrategyName> --mode sim")
    return 0


def cmd_run(args: argparse.Namespace) -> int:
    """Run a strategy from the current project directory."""
    julia_args = [args.strategy, "--mode", args.mode]
    if args.exchange:
        julia_args += ["--exchange", args.exchange]
    if args.sandbox:
        julia_args += ["--sandbox"]
    else:
        julia_args += ["--no-sandbox"]
    if args.account:
        julia_args += ["--account", args.account]

    cwd = Path.cwd()
    try:
        run_julia(
            RUN_STRATEGY_SCRIPT,
            julia_args,
            project_dir=cwd,
            cwd=cwd,
        )
    except PlanarError as err:
        print(f"error: {err}", file=sys.stderr)
        return 1
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="planar",
        description="Planar trading framework driver (Julia engine).",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("version", help="print versions")

    p_init = sub.add_parser("init", help="bootstrap a new Planar project")
    p_init.add_argument("dir", nargs="?", default=".", help="project directory (default: .)")

    p_run = sub.add_parser("run", help="run a strategy")
    p_run.add_argument("strategy", help="strategy name (as registered in user/planar.toml)")
    p_run.add_argument(
        "--mode", choices=["sim", "paper", "live"], default="sim",
        help="execution mode (default: sim)",
    )
    p_run.add_argument("--exchange", default=None, help="exchange id, e.g. binanceusdm")
    p_run.add_argument("--sandbox", action="store_true", default=True,
                       help="use the exchange sandbox (default)")
    p_run.add_argument("--no-sandbox", dest="sandbox", action="store_false",
                       help="use the production exchange")
    p_run.add_argument("--account", default="", help="exchange account name")

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "version":
        return cmd_version(args)
    if args.command == "init":
        return cmd_init(args)
    if args.command == "run":
        return cmd_run(args)
    return 2


if __name__ == "__main__":
    sys.exit(main())
