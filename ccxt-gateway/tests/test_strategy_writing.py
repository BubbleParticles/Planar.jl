"""Tests that drive the shipped *pure* strategy-writing helpers directly.

These exercise ``write_strategy`` / ``test_strategy`` / ``deploy_strategy`` and
their sub-helpers (``_sanitize_name`` / ``_verdict`` / ``_load_strategies_toml``)
without going through the MCP transport. They assert on the structured dicts and
on-disk artifacts (files, TOML) the helpers actually produce — no gateway, no
live exchange, and (for the hermetic branches) no Julia subprocess at all.

The verdict mapping is checked both by calling ``_verdict`` directly and by
driving ``test_strategy`` through its real dispatch branches (not-found,
skipped, and — when Julia is available — parse pass / parse fail).
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

import pytest

try:  # pragma: no cover - import shim for editable/installed layouts
    from ccxt_gateway.mcp_server import (
        _already_registered,
        _load_strategies_toml,
        _sanitize_name,
        _verdict,
        deploy_strategy,
        # Aliased: the real name starts with ``test_`` and would be collected
        # as a test function by pytest.
        test_strategy as pure_test_strategy,
        write_strategy,
    )
except ImportError:  # pragma: no cover
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
    from ccxt_gateway.mcp_server import (  # type: ignore
        _already_registered,
        _load_strategies_toml,
        _sanitize_name,
        _verdict,
        deploy_strategy,
        test_strategy as pure_test_strategy,
        write_strategy,
    )

import ccxt_gateway.mcp_server as _mcp

HAS_JULIA = shutil.which("julia") is not None


@pytest.fixture
def isolated_dirs(tmp_path, monkeypatch):
    """Redirect the helpers' default strategies dir / toml at a temp location.

    The pure helpers accept ``strategies_dir`` / ``strategies_toml`` kwargs, so
    callers pass them explicitly. This fixture keeps them hermetic anyway and
    gives every test a clean working root.
    """
    monkeypatch.setattr(_mcp, "DEFAULT_STRATEGIES_DIR", str(tmp_path))
    monkeypatch.setattr(
        _mcp, "DEFAULT_STRATEGIES_TOML", str(tmp_path / "strategies.toml")
    )
    return tmp_path


# ---------------------------------------------------------------------------
# write_strategy: create / update / overwrite guard / path-traversal
# ---------------------------------------------------------------------------


def test_write_strategy_creates(isolated_dirs):
    res = write_strategy("PureDemo", "module PureDemo\n x = 1\nend\n",
                         strategies_dir=str(isolated_dirs))
    assert res["success"] is True
    assert res["action"] == "created"
    assert res["name"] == "PureDemo"
    assert res["relative_path"] == "PureDemo.jl"
    assert Path(res["path"]).read_text() == "module PureDemo\n x = 1\nend\n"


def test_write_strategy_preserves_explicit_jl(isolated_dirs):
    res = write_strategy(
        "PureDemo.jl", "module PureDemo\nend\n", strategies_dir=str(isolated_dirs)
    )
    assert res["relative_path"] == "PureDemo.jl"
    assert res["name"] == "PureDemo"


def test_write_strategy_subpath_creates_nested_dir(isolated_dirs):
    res = write_strategy(
        "Sub/PureDemo", "module PureDemo\nend\n", strategies_dir=str(isolated_dirs)
    )
    assert res["relative_path"] == "Sub/PureDemo.jl"
    target = isolated_dirs / "Sub" / "PureDemo.jl"
    assert target.exists()
    assert res["action"] == "created"


def test_write_strategy_overwrite_guard(isolated_dirs):
    write_strategy("PureDemo", "module PureDemo\n x = 1\nend\n",
                   strategies_dir=str(isolated_dirs))
    # overwrite=False must refuse the existing file.
    with pytest.raises(FileExistsError):
        write_strategy(
            "PureDemo", "module PureDemo\n x = 2\nend\n",
            overwrite=False, strategies_dir=str(isolated_dirs),
        )
    # The original content is untouched.
    assert "x = 1" in Path(isolated_dirs / "PureDemo.jl").read_text()
    # overwrite=True replaces it and reports the "updated" action.
    updated = write_strategy(
        "PureDemo", "module PureDemo\n x = 2\nend\n",
        overwrite=True, strategies_dir=str(isolated_dirs),
    )
    assert updated["action"] == "updated"
    assert "x = 2" in Path(updated["path"]).read_text()


def test_write_strategy_path_traversal_rejected(isolated_dirs):
    src = "module Evil\nend\n"
    # ``_sanitize_name`` rejects path components that escape the directory.
    for name in ("../../etc/evil", "../evil", "..", "Sub/../evil", "a/../../b"):
        with pytest.raises(ValueError):
            _sanitize_name(name)
    # The public helper must also refuse the write (defense in depth).
    with pytest.raises(ValueError):
        write_strategy("../../evil", src, strategies_dir=str(isolated_dirs))
    # And nothing was written outside the strategies dir.
    assert not (isolated_dirs.parent / "evil.jl").exists()


# ---------------------------------------------------------------------------
# deploy_strategy: TOML registration round-trip / idempotency
# ---------------------------------------------------------------------------


def test_deploy_strategy_registers_once(isolated_dirs):
    toml = isolated_dirs / "strategies.toml"
    res = deploy_strategy(
        "PureDemo", "binance", account="1", mode="Paper",
        strategies_dir=str(isolated_dirs), strategies_toml=str(toml),
    )
    assert res["success"] is True
    assert res["registered"] is True
    assert res["name"] == "PureDemo"
    assert res["exchange"] == "binance"
    assert res["entry"]["account"] == "1"
    # The TOML now holds exactly one entry.
    entries = _load_strategies_toml(toml)
    assert len(entries) == 1
    assert entries[0]["name"] == "PureDemo"
    assert entries[0]["exchange"] == "binance"


def test_deploy_strategy_idempotent(isolated_dirs):
    toml = isolated_dirs / "strategies.toml"
    deploy_strategy("PureDemo", "binance", account="1",
                    strategies_dir=str(isolated_dirs), strategies_toml=str(toml))
    res = deploy_strategy("PureDemo", "binance", account="1",
                          strategies_dir=str(isolated_dirs),
                          strategies_toml=str(toml))
    # Re-registering the same (name, exchange, account) is a no-op.
    assert res["registered"] is False
    entries = _load_strategies_toml(toml)
    assert len(entries) == 1


def test_deploy_strategy_distinct_accounts_both_registered(isolated_dirs):
    toml = isolated_dirs / "strategies.toml"
    deploy_strategy("PureDemo", "binance", account="1",
                    strategies_dir=str(isolated_dirs), strategies_toml=str(toml))
    deploy_strategy("PureDemo", "binance", account="2",
                    strategies_dir=str(isolated_dirs), strategies_toml=str(toml))
    entries = _load_strategies_toml(toml)
    assert len(entries) == 2
    assert {e["account"] for e in entries} == {"1", "2"}


def test_deploy_strategy_env_and_mode_recorded(isolated_dirs):
    toml = isolated_dirs / "strategies.toml"
    res = deploy_strategy(
        "PureDemo", "binance", account="9", mode="Live",
        env={"API_KEY": "V", "SECRET": "S"},
        strategies_dir=str(isolated_dirs), strategies_toml=str(toml),
    )
    assert res["mode"] == "Live"
    assert res["entry"]["env"] == {"API_KEY": "V", "SECRET": "S"}
    entries = _load_strategies_toml(toml)
    assert entries[0]["env"] == {"API_KEY": "V", "SECRET": "S"}


def test_already_registered_helper():
    entries = [{"name": "A", "exchange": "binance", "account": "1"}]
    assert _already_registered(entries, "A", "binance", "1") is True
    assert _already_registered(entries, "A", "binance", "2") is False
    assert _already_registered(entries, "B", "binance", "1") is False


# ---------------------------------------------------------------------------
# test_strategy: dispatch branches + verdict mapping
# ---------------------------------------------------------------------------


def test_test_strategy_not_found(isolated_dirs):
    res = pure_test_strategy("NoSuchStrat", strategies_dir=str(isolated_dirs))
    assert res["verdict"] == "error"
    assert res["success"] is False
    assert "not found" in (res["error"] or "")


def test_test_strategy_dir_without_project_skipped(isolated_dirs):
    d = isolated_dirs / "NoProj"
    d.mkdir()
    (d / "readme.txt").write_text("not a project")
    res = pure_test_strategy("NoProj", strategies_dir=str(isolated_dirs))
    assert res["verdict"] == "skipped"
    assert res["command"] is None


@pytest.mark.skipif(not HAS_JULIA, reason="julia not on PATH")
def test_test_strategy_dir_with_runtests_passes(isolated_dirs):
    d = isolated_dirs / "ProjA"
    (d / "test").mkdir(parents=True)
    (d / "Project.toml").write_text(
        'name = "ProjA"\n'
        'uuid = "33333333-3333-3333-3333-333333333333"\n'
        'version = "0.1.0"\n'
    )
    (d / "test" / "runtests.jl").write_text("using Test\n@Test.test 1 == 1\n")
    res = pure_test_strategy("ProjA", strategies_dir=str(isolated_dirs))
    assert res["verdict"] == "pass"
    assert res["success"] is True


@pytest.mark.skipif(not HAS_JULIA, reason="julia not on PATH")
def test_test_strategy_single_file_parse_pass(isolated_dirs):
    f = isolated_dirs / "ParseGood.jl"
    f.write_text("module ParseGood\n x::Int = 1\nend\n")
    res = pure_test_strategy("ParseGood.jl", strategies_dir=str(isolated_dirs))
    assert res["verdict"] == "pass"
    assert res["success"] is True


@pytest.mark.skipif(not HAS_JULIA, reason="julia not on PATH")
def test_test_strategy_single_file_parse_fail(isolated_dirs):
    f = isolated_dirs / "ParseBad.jl"
    f.write_text("@@@ not valid julia @@@\n")
    res = pure_test_strategy("ParseBad.jl", strategies_dir=str(isolated_dirs))
    # Julia exits non-zero on a parse error -> "fail" (not a system "error").
    assert res["verdict"] == "fail"
    assert res["success"] is False


def test_verdict_mapping():
    """``_verdict`` maps (returncode, output) to pass/fail/error directly."""
    assert _verdict(0, "all good", "") == "pass"
    assert _verdict(0, "Error During Test", "") == "pass"  # rc==0 wins
    assert _verdict(1, "Error During Test summary", "") == "fail"
    assert _verdict(1, "Test Failed at line 3", "") == "fail"
    assert _verdict(1, "UndefVarError: x not defined", "") == "fail"
    # Non-zero exit with no test-report signature -> generic error.
    assert _verdict(1, "some unrelated crash output", "") == "error"
    assert _verdict(None, "out", "err") == "error"
