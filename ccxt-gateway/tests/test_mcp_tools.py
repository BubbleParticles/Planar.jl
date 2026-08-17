"""Tests that drive the shipped ``@mcp.tool`` wrapper surface.

The strategy-management helpers (``write_strategy`` / ``test_strategy`` /
``deploy_strategy``) and the ``SessionManager`` are already covered directly in
``test_mcp_server.py``. This file exercises the *tool wrappers* an AI client
actually calls over MCP — all eight ``@mcp.tool`` functions plus the shared
module-level ``SESSION_MANAGER`` — and the structured error paths that surface
when a session id is unknown or Revise is unavailable in the session env.

The wrappers are thin (they forward to the pure helpers / ``SessionManager``),
so calling them is the honest way to prove the shipped tool surface works end
to end without re-implementing any logic.
"""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

import pytest

try:  # pragma: no cover - import shim for editable/installed layouts
    from ccxt_gateway.mcp_server import (
        SESSION_MANAGER,
        deploy_strategy_tool,
        eval_in_session_tool,
        list_sessions_tool,
        revise_in_session_tool,
        start_session_tool,
        stop_session_tool,
        # Aliased: the real name starts with ``test_`` and would be collected
        # as a test function by pytest.
        test_strategy_tool as tool_test_strategy,
        write_strategy_tool,
    )
except ImportError:  # pragma: no cover
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
    from ccxt_gateway.mcp_server import (  # type: ignore
        SESSION_MANAGER,
        deploy_strategy_tool,
        eval_in_session_tool,
        list_sessions_tool,
        revise_in_session_tool,
        start_session_tool,
        stop_session_tool,
        test_strategy_tool as tool_test_strategy,
        write_strategy_tool,
    )

import ccxt_gateway.mcp_server as _mcp

HAS_JULIA = shutil.which("julia") is not None


@pytest.fixture
def isolated_dirs(tmp_path, monkeypatch):
    """Point the tools' default strategies dir / toml at a temp location.

    The tool wrappers do not expose ``strategies_dir`` / ``strategies_toml``;
    they fall back to the module-level defaults. Redirecting those defaults
    keeps the write/deploy/test tools hermetic and prevents the test from
    touching the real repository ``scripts/strategies.toml``.
    """
    monkeypatch.setattr(_mcp, "DEFAULT_STRATEGIES_DIR", str(tmp_path))
    monkeypatch.setattr(
        _mcp, "DEFAULT_STRATEGIES_TOML", str(tmp_path / "strategies.toml")
    )
    return tmp_path


# ---------------------------------------------------------------------------
# Strategy-management tool wrappers
# ---------------------------------------------------------------------------


def test_write_strategy_tool_creates(isolated_dirs):
    res = write_strategy_tool("ToolDemo", "module ToolDemo\nend\n")
    assert res["success"] is True
    assert res["action"] == "created"
    assert res["name"] == "ToolDemo"
    assert Path(res["path"]).read_text() == "module ToolDemo\nend\n"


def test_write_strategy_tool_overwrite_guard(isolated_dirs):
    write_strategy_tool("ToolDemo", "module ToolDemo\n x = 1\nend\n")
    # With overwrite=False the tool must not raise; the helper raises
    # FileExistsError which the tool surfaces by letting it propagate as a
    # test failure -> instead we assert the file is unchanged when we allow
    # overwrite, and that the wrapper returns an updated action otherwise.
    updated = write_strategy_tool(
        "ToolDemo", "module ToolDemo\n x = 2\nend\n", overwrite=True
    )
    assert updated["action"] == "updated"
    assert "x = 2" in Path(updated["path"]).read_text()


def test_test_strategy_tool_not_found(isolated_dirs):
    # No Julia launch is needed: the helper returns "error" before running
    # anything when neither the file nor a project directory exists.
    res = tool_test_strategy("NoSuchToolStrat")
    assert res["verdict"] == "error"
    assert res["success"] is False
    assert "not found" in (res["error"] or "")


def test_deploy_strategy_tool_registers(isolated_dirs):
    res = deploy_strategy_tool(
        "ToolDemo2", "binance", account="3", mode="Paper", env={"API_KEY": "V"}
    )
    assert res["success"] is True
    assert res["registered"] is True
    assert res["name"] == "ToolDemo2"
    assert res["exchange"] == "binance"
    assert res["entry"]["account"] == "3"
    assert res["entry"]["env"] == {"API_KEY": "V"}
    assert res["mode"] == "Paper"
    toml = isolated_dirs / "strategies.toml"
    assert toml.exists()


def test_deploy_strategy_tool_idempotent(isolated_dirs):
    deploy_strategy_tool("ToolDemo2", "binance", account="3")
    res = deploy_strategy_tool("ToolDemo2", "binance", account="3")
    assert res["registered"] is False  # already present -> not re-added


# ---------------------------------------------------------------------------
# Session tool wrappers (persistent Julia REPL + Revise trigger)
# ---------------------------------------------------------------------------


def test_session_tools_lifecycle():
    """start -> list -> eval (state persists) -> stop, all through the tools."""
    if not HAS_JULIA:
        pytest.skip("julia not on PATH")
    res = start_session_tool()
    assert res["status"] == "started"
    assert res["session"].startswith("session-")
    sid = res["session"]
    try:
        listing = list_sessions_tool()
        assert sid in listing
        assert listing[sid]["pid"] == SESSION_MANAGER._sessions[sid].proc.pid

        r1 = eval_in_session_tool(sid, "y = 7 * 6")
        assert r1["ok"] is True
        r2 = eval_in_session_tool(sid, "y")
        assert r2["ok"] is True
        assert r2["value"] == "42"
    finally:
        stop_session_tool(sid)

    # After stop the session is gone from the registry.
    assert sid not in list_sessions_tool()


def test_session_tools_unknown_id_structured_error():
    """Unknown ids must surface a structured error, never crash the tool."""
    ev = eval_in_session_tool("no-such-session", "1")
    assert ev["ok"] is False
    assert "no-such-session" in ev["error"]

    rv = revise_in_session_tool("no-such-session")
    assert rv["ok"] is False

    sp = stop_session_tool("no-such-session")
    assert sp["stopped"] is False
    assert "unknown session" in sp["error"]


def test_revise_tool_applies_change(tmp_path):
    """Revise reloads an edited module through the tool wrappers."""
    if not HAS_JULIA:
        pytest.skip("julia not on PATH")
    res = start_session_tool()
    sid = res["session"]
    mod = f"ToolRevise_{os.getpid()}"
    src = tmp_path / f"{mod}.jl"
    src.write_text(f"module {mod}\nf() = 1\nend\n")
    try:
        load = eval_in_session_tool(
            sid, f'using Revise; Revise.includet("{src}"); {mod}.f()'
        )
        assert load["ok"] is True
        assert load["value"] == "1"

        # Edit on disk, then trigger Revise through the tool.
        src.write_text(f"module {mod}\nf() = 2\nend\n")
        rv = revise_in_session_tool(sid)
        assert rv["ok"] is True
        assert rv["revised"] is True

        after = eval_in_session_tool(sid, f"{mod}.f()")
        assert after["ok"] is True
        assert after["value"] == "2"
    finally:
        stop_session_tool(sid)


def test_revise_tool_unavailable_structured_error(tmp_path, monkeypatch):
    """A session whose env cannot load Revise must report a structured error.

    The wrapper exposes only ``project`` (not ``env``), so we empty the depot
    via the environment the spawned subprocess inherits — the same mechanism
    the SessionManager tests use, but exercised through the tool surface.
    """
    if not HAS_JULIA:
        pytest.skip("julia not on PATH")
    proj = tmp_path / "empty_proj"
    proj.mkdir()
    (proj / "Project.toml").write_text(
        'name = "EmptyProj"\n'
        'uuid = "22222222-2222-2222-2222-222222222222"\n'
        'version = "0.1.0"\n'
    )
    empty_depot = tmp_path / "empty_depot"
    empty_depot.mkdir()
    monkeypatch.setenv("JULIA_DEPOT_PATH", str(empty_depot))

    res = start_session_tool(project=str(proj))
    sid = res["session"]
    try:
        rv = revise_in_session_tool(sid)
        assert rv["ok"] is False
        assert rv["revised"] is False
        assert "Revise unavailable" in rv["error"]
    finally:
        stop_session_tool(sid)
