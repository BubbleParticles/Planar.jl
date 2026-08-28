"""Subprocess management for the Planar Julia engine."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

RESOURCES_DIR = Path(__file__).parent / "resources"
RUN_STRATEGY_SCRIPT = RESOURCES_DIR / "run_strategy.jl"

#: Registry that hosts the Planar.jl packages (see PACKAGING.md at the repo root).
REGISTRY_URL = "https://github.com/BubbleParticles/PlanarRegistry.git"


class PlanarError(RuntimeError):
    """Raised when the Julia engine cannot be found or fails to run."""


def find_julia() -> str:
    """Return the path to the `julia` executable, or raise :class:`PlanarError`."""
    julia = shutil.which("julia")
    if julia is None:
        raise PlanarError(
            "julia executable not found on PATH. Install Julia >= 1.12 "
            "(https://julialang.org/downloads/) and add it to your PATH."
        )
    return julia


def julia_env(project_dir: Path | None) -> dict[str, str]:
    """Environment for a Julia subprocess.

    Mirrors the repository's `.envrc`: strategies are loaded from
    ``<project>/user/strategies`` and the project dir stays on the load path.
    """
    env = os.environ.copy()
    if project_dir is not None:
        project_dir = Path(project_dir).resolve()
        env["JULIA_LOAD_PATH"] = (
            f":{project_dir / 'user' / 'strategies'}:{project_dir}"
        )
    return env


def run_julia(
    script: Path,
    args: list[str],
    project_dir: Path | None = None,
    cwd: Path | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    """Run a Julia script, streaming its output to the terminal."""
    julia = find_julia()
    cmd = [julia]
    if project_dir is not None:
        cmd.append(f"--project={project_dir}")
    cmd += [str(script), *args]
    return subprocess.run(
        cmd,
        env=julia_env(project_dir),
        cwd=cwd,
        text=True,
        check=check,
    )


def install_planar(project_dir: Path) -> None:
    """Add the Planar registry and the `Planar` package to `project_dir`."""
    code = (
        "using Pkg; "
        "regs = Pkg.Registry.reachable_registries(); "
        'if !any(r.name == "General" for r in regs) '
        '  Pkg.Registry.add(Pkg.RegistrySpec(name="General")); '
        "end; "
        f'if !any(r.name == "PlanarRegistry" for r in Pkg.Registry.reachable_registries()) '
        f'  Pkg.Registry.add(Pkg.RegistrySpec(url="{REGISTRY_URL}")); '
        "else "
        "  Pkg.Registry.update(); "
        "end; "
        'Pkg.add("Planar")'
    )
    subprocess.run(
        [find_julia(), f"--project={project_dir}", "-e", code],
        env=julia_env(project_dir),
        check=True,
    )
