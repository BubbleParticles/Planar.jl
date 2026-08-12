"""Tests for the planarjl-py CLI (hermetic — no julia/network required)."""

import argparse
import subprocess
from pathlib import Path

import pytest

from planar_trader import cli, runner


@pytest.fixture
def no_julia(monkeypatch):
    monkeypatch.setattr(runner.shutil, "which", lambda name: None)
    return monkeypatch


@pytest.fixture
def fake_run(monkeypatch):
    """Record run_julia/install_planar calls instead of executing them."""
    calls = []

    def _record(script, args, project_dir=None, cwd=None, check=True):
        calls.append(("run", script, args, project_dir, cwd, check))
        return subprocess.CompletedProcess(["julia"], 0, "", "")

    monkeypatch.setattr(cli, "run_julia", _record)
    monkeypatch.setattr(
        cli, "install_planar",
        lambda project_dir: calls.append(("install", project_dir)),
    )
    return calls


def test_version_reports_cli_and_julia(capsys):
    assert cli.cmd_version(argparse.Namespace()) == 0
    out = capsys.readouterr().out
    assert "planarjl-py" in out
    assert "julia:" in out


def test_version_missing_julia(no_julia, capsys):
    assert cli.cmd_version(argparse.Namespace()) == 1
    assert "NOT FOUND" in capsys.readouterr().out


def test_init_creates_layout_and_installs(tmp_path, fake_run):
    proj = tmp_path / "mybot"
    assert cli.cmd_init(argparse.Namespace(dir=str(proj))) == 0

    assert (proj / "user" / "planar.toml").is_file()
    assert (proj / "user" / "strategies").is_dir()
    toml = (proj / "user" / "planar.toml").read_text()
    assert "[sources]" in toml

    installs = [c for c in fake_run if c[0] == "install"]
    assert len(installs) == 1
    assert installs[0][1] == proj.resolve()


def test_init_refuses_nonempty_dir(tmp_path, capsys):
    proj = tmp_path / "existing"
    proj.mkdir()
    (proj / "file.txt").write_text("x")
    assert cli.cmd_init(argparse.Namespace(dir=str(proj))) == 1
    assert "not empty" in capsys.readouterr().err


def test_run_passes_mode_exchange_sandbox(tmp_path, fake_run, monkeypatch):
    monkeypatch.chdir(tmp_path)
    args = argparse.Namespace(
        strategy="MyStrategy", mode="sim", exchange="binanceusdm",
        sandbox=True, account="",
    )
    assert cli.cmd_run(args) == 0

    runs = [c for c in fake_run if c[0] == "run"]
    assert len(runs) == 1
    _, script, julia_args, project_dir, cwd, check = runs[0]
    assert script == runner.RUN_STRATEGY_SCRIPT
    assert julia_args == ["MyStrategy", "--mode", "sim", "--exchange", "binanceusdm", "--sandbox"]
    assert project_dir == tmp_path.resolve()
    assert cwd == tmp_path.resolve()
    assert check is True


def test_run_no_sandbox_and_account(tmp_path, fake_run, monkeypatch):
    monkeypatch.chdir(tmp_path)
    args = argparse.Namespace(
        strategy="S", mode="live", exchange=None,
        sandbox=False, account="acc1",
    )
    assert cli.cmd_run(args) == 0
    _, _, julia_args, _, _, _ = [c for c in fake_run if c[0] == "run"][0]
    assert julia_args == ["S", "--mode", "live", "--no-sandbox", "--account", "acc1"]


def test_run_missing_julia_fails(no_julia, capsys):
    assert cli.cmd_run(argparse.Namespace(
        strategy="S", mode="sim", exchange=None, sandbox=True, account="",
    )) == 1
    assert "julia executable not found" in capsys.readouterr().err


def test_julia_env_load_path(tmp_path):
    env = runner.julia_env(tmp_path)
    assert str(tmp_path.resolve() / "user" / "strategies") in env["JULIA_LOAD_PATH"]
    assert str(tmp_path.resolve()) in env["JULIA_LOAD_PATH"]
