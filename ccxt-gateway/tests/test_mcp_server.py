"""Pure-logic tests for the Planar strategy MCP server.

These tests exercise ``write_strategy``, ``test_strategy`` and
``deploy_strategy`` directly. No gateway or live exchange is required. The
Julia-backed test paths are guarded by ``shutil.which("julia")`` so the suite
stays fast and hermetic when Julia is absent, but still drives the *real* Julia
test runner (``julia --project=... test/runtests.jl`` and ``julia --check``)
when it is available.
"""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

import pytest

# Import the module under test through the package when possible.
try:  # pragma: no cover - import shim for editable/installed layouts
    from ccxt_gateway.mcp_server import (
        DEFAULT_JULIA,
        SessionManager,
        _already_registered,
        _module_name,
        _sanitize_name,
        _verdict,
        deploy_strategy,
        test_strategy,
        write_strategy,
    )
except ImportError:  # pragma: no cover
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
    from ccxt_gateway.mcp_server import (  # type: ignore
        DEFAULT_JULIA,
        SessionManager,
        _already_registered,
        _module_name,
        _sanitize_name,
        _verdict,
        deploy_strategy,
        test_strategy,
        write_strategy,
    )

# Alias to avoid pytest collecting the imported helper as a test function.
_run_strategy_test = test_strategy
del test_strategy

HAS_JULIA = shutil.which("julia") is not None


# ---------------------------------------------------------------------------
# _sanitize_name / _module_name
# ---------------------------------------------------------------------------


def test_sanitize_name_plain():
    assert _sanitize_name("MyStrat") == "MyStrat"
    assert _sanitize_name("MyStrat.jl") == "MyStrat.jl"


def test_sanitize_name_subpath():
    assert _sanitize_name("Sub/MyStrat") == "Sub/MyStrat"


@pytest.mark.parametrize(
    "bad", ["", "..", "../x", "a/../b", ".", "a//b", "a b", "a-b"]
)
def test_sanitize_name_rejects(bad):
    with pytest.raises(ValueError):
        _sanitize_name(bad)


@pytest.mark.parametrize("ok", ["/abs", "./x", "Sub/MyStrat.jl"])
def test_sanitize_name_normalizes_valid(ok):
    # Leading "./" and "/" are stripped; a trailing .jl is preserved.
    assert _sanitize_name(ok) == ok.lstrip("/").lstrip("./")


def test_module_name():
    assert _module_name("MyStrat") == "MyStrat"
    assert _module_name("MyStrat.jl") == "MyStrat"
    assert _module_name("Sub/MyStrat.jl") == "MyStrat"


# ---------------------------------------------------------------------------
# write_strategy
# ---------------------------------------------------------------------------


def test_write_strategy_creates(tmp_path):
    res = write_strategy("Demo", "module Demo\nend\n", strategies_dir=str(tmp_path))
    assert res["success"] is True
    assert res["action"] == "created"
    assert res["name"] == "Demo"
    assert Path(res["path"]).read_text() == "module Demo\nend\n"
    assert res["bytes"] == len("module Demo\nend\n".encode("utf-8"))


def test_write_strategy_updates(tmp_path):
    write_strategy("Demo", "module Demo\nend\n", strategies_dir=str(tmp_path))
    res = write_strategy("Demo", "module Demo\n x = 1\nend\n", strategies_dir=str(tmp_path))
    assert res["action"] == "updated"


def test_write_strategy_no_overwrite(tmp_path):
    write_strategy("Demo", "module Demo\nend\n", strategies_dir=str(tmp_path))
    with pytest.raises(FileExistsError):
        write_strategy(
            "Demo", "module Demo\n x = 1\nend\n", overwrite=False, strategies_dir=str(tmp_path)
        )


def test_write_strategy_subpath(tmp_path):
    res = write_strategy(
        "Sub/MyStrat", "module MyStrat\nend\n", strategies_dir=str(tmp_path)
    )
    assert Path(res["path"]) == tmp_path / "Sub" / "MyStrat.jl"
    assert Path(res["path"]).exists()


def test_write_strategy_rejects_traversal(tmp_path):
    with pytest.raises(ValueError):
        write_strategy(
            "../escape", "module X\nend\n", strategies_dir=str(tmp_path)
        )


# ---------------------------------------------------------------------------
# _verdict
# ---------------------------------------------------------------------------


def test_verdict_pass():
    assert _verdict(0, "Test Summary: | Pass  Total", "") == "pass"


def test_verdict_fail():
    assert _verdict(1, "", "Error During Test") == "fail"
    assert _verdict(1, "Test Summary: | Fail  Total", "") == "fail"
    assert _verdict(1, "", "UndefVarError: x not defined") == "fail"


def test_verdict_error():
    assert _verdict(127, "", "command not found") == "error"


# ---------------------------------------------------------------------------
# test_strategy
# ---------------------------------------------------------------------------


def test_test_strategy_not_found(tmp_path):
    res = _run_strategy_test("Nope", strategies_dir=str(tmp_path))
    assert res["verdict"] == "error"
    assert res["success"] is False
    assert "not found" in (res["error"] or "")


def test_test_strategy_single_file_check(tmp_path):
    if not HAS_JULIA:
        pytest.skip("julia not on PATH")
    write_strategy("OkFile", "module OkFile\n x = 1\nend\n", strategies_dir=str(tmp_path))
    res = _run_strategy_test("OkFile", strategies_dir=str(tmp_path))
    assert res["verdict"] == "pass"
    assert res["success"] is True
    assert "Meta.parse" in res["command"]


def test_test_strategy_single_file_syntax_error(tmp_path):
    if not HAS_JULIA:
        pytest.skip("julia not on PATH")
    write_strategy("BadFile", "module BadFile\n this is not valid julia ((( \nend\n",
                  strategies_dir=str(tmp_path))
    res = _run_strategy_test("BadFile", strategies_dir=str(tmp_path))
    assert res["verdict"] == "fail"
    assert res["success"] is False


def _make_pkg(root: Path, name: str, test_body: str) -> Path:
    pkg = root / name
    (pkg / "src").mkdir(parents=True)
    (pkg / "test").mkdir(parents=True)
    (pkg / "Project.toml").write_text(
        f'name = "{name}"\n'
        f'uuid = "11111111-1111-1111-1111-{name.encode().hex()[:12]}"\n'
        'version = "0.1.0"\n'
    )
    (pkg / "src" / f"{name}.jl").write_text(
        f"module {name}\nexport addone\naddone(x) = x + 1\nend\n"
    )
    (pkg / "test" / "runtests.jl").write_text(
        f'using {name}\nusing Test\n{test_body}\nprintln("GATEWAY_TEST_DONE")\n'
    )
    return pkg


def test_test_strategy_real_pass(tmp_path):
    if not HAS_JULIA:
        pytest.skip("julia not on PATH")
    _make_pkg(tmp_path, "PassPkg", 'println("PASS_MARKER")\n@test addone(1) == 2')
    res = _run_strategy_test("PassPkg", strategies_dir=str(tmp_path))
    assert res["verdict"] == "pass", res
    assert res["success"] is True
    assert "PASS_MARKER" in res["output"]


def test_test_strategy_real_fail(tmp_path):
    if not HAS_JULIA:
        pytest.skip("julia not on PATH")
    _make_pkg(tmp_path, "FailPkg", "@test 1 == 2")
    res = _run_strategy_test("FailPkg", strategies_dir=str(tmp_path))
    assert res["verdict"] == "fail", res
    assert res["success"] is False


# ---------------------------------------------------------------------------
# deploy_strategy
# ---------------------------------------------------------------------------


def test_deploy_registers(tmp_path):
    toml = tmp_path / "strategies.toml"
    res = deploy_strategy(
        "Demo", "bitmex", strategies_toml=str(toml), strategies_dir=str(tmp_path)
    )
    assert res["success"] is True
    assert res["registered"] is True
    assert res["name"] == "Demo"
    assert res["exchange"] == "bitmex"
    assert res["entry"]["account"] == "1"
    assert res["entry"]["env"] == {}
    # File written and parseable with the new entry.
    import tomllib

    data = tomllib.loads(toml.read_text())
    assert data["strategy"][0]["name"] == "Demo"


def test_deploy_idempotent(tmp_path):
    toml = tmp_path / "strategies.toml"
    deploy_strategy("Demo", "bitmex", strategies_toml=str(toml))
    res = deploy_strategy("Demo", "bitmex", strategies_toml=str(toml))
    assert res["registered"] is False
    import tomllib

    data = tomllib.loads(toml.read_text())
    assert len(data["strategy"]) == 1


def test_deploy_env_and_account(tmp_path):
    toml = tmp_path / "strategies.toml"
    res = deploy_strategy(
        "Demo",
        "binance",
        account="7",
        mode="Live",
        env={"API_KEY": "xyz"},
        strategies_toml=str(toml),
    )
    assert res["entry"]["account"] == "7"
    assert res["entry"]["env"] == {"API_KEY": "xyz"}
    assert res["mode"] == "Live"


def test_deploy_missing_julia_run_is_structured_error(tmp_path):
    toml = tmp_path / "strategies.toml"
    res = deploy_strategy(
        "Demo",
        "bitmex",
        strategies_toml=str(toml),
        run=True,
        julia="this-binary-does-not-exist-xyz",
        run_timeout=10,
    )
    assert res["success"] is True  # registration still succeeded
    assert res["run"]["started"] is False
    assert "command not found" in (res["run"]["error"] or "")


def test_already_registered_helper():
    entries = [{"name": "Demo", "exchange": "bitmex", "account": "1"}]
    assert _already_registered(entries, "Demo", "bitmex", "1") is True
    assert _already_registered(entries, "Demo", "binance", "1") is False
    assert _already_registered(entries, "Demo", "bitmex", "2") is False


# ---------------------------------------------------------------------------
# SessionManager (persistent Julia REPL sessions + Revise trigger)
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def julia_session():
    """A single shared session for stateful/persistence tests."""
    if not HAS_JULIA:
        pytest.skip("julia not on PATH")
    mgr = SessionManager()
    sid = mgr.start_session()
    try:
        yield mgr, sid
    finally:
        mgr.stop_session(sid)


def test_session_eval_persists_state(julia_session):
    mgr, sid = julia_session
    r1 = mgr.eval_in_session(sid, "x = 41 + 1")
    assert r1["ok"] is True
    r2 = mgr.eval_in_session(sid, "x")
    assert r2["ok"] is True
    assert r2["value"] == "42"


def test_session_list_contains_active(julia_session):
    mgr, sid = julia_session
    listing = mgr.list_sessions()
    assert sid in listing
    assert listing[sid]["pid"] == mgr._sessions[sid].proc.pid


def test_session_revise_applies_change(tmp_path, julia_session):
    mgr, sid = julia_session
    # A unique module file so Revise can track and reload it.
    mod = f"ReviseTester_{os.getpid()}"
    src = tmp_path / f"{mod}.jl"
    src.write_text(f"module {mod}\nf() = 1\nend\n")
    load = mgr.eval_in_session(
        sid, f'using Revise; Revise.includet("{src}"); {mod}.f()'
    )
    if not load.get("ok"):
        val = str(load.get("value", "")) + str(load.get("error", ""))
        if "Revise" in val:
            pytest.skip("Revise not installed in this Julia environment")
    assert load["ok"] is True
    assert load["value"] == "1"
    # Edit the source on disk, then trigger Revise.
    src.write_text(f"module {mod}\nf() = 2\nend\n")
    rv = mgr.revise_in_session(sid)
    assert rv["ok"] is True
    assert rv["revised"] is True
    after = mgr.eval_in_session(sid, f"{mod}.f()")
    assert after["ok"] is True
    assert after["value"] == "2"

def test_session_stop_removes_and_kills():
    if not HAS_JULIA:
        pytest.skip("julia not on PATH")
    mgr = SessionManager()
    sid = mgr.start_session()
    assert sid in mgr.list_sessions()
    res = mgr.stop_session(sid)
    assert res["stopped"] is True
    assert res["session"] == sid
    assert sid not in mgr.list_sessions()
    # The Julia process should have exited.
    assert mgr._sessions.get(sid) is None


def test_session_unknown_id_returns_error():
    mgr = SessionManager()
    # Unknown ids must surface a structured error, never raise.
    res = mgr.eval_in_session("does-not-exist", "1")
    assert res["ok"] is False
    assert "does-not-exist" in res["error"]
    stop = mgr.stop_session("does-not-exist")
    assert stop["stopped"] is False
    assert "unknown session" in stop["error"]


def test_revise_unavailable_returns_structured_error(tmp_path):
    """A session whose env lacks Revise must report a structured error.

    We start the session in an isolated, empty project so Revise is not
    loadable, then assert the trigger fails gracefully (no crash).
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
    mgr = SessionManager()
    # Point the depot at an empty directory so no packages (incl. Revise) load.
    empty_depot = tmp_path / "empty_depot"
    empty_depot.mkdir()
    sid = mgr.start_session(project=str(proj), env={"JULIA_DEPOT_PATH": str(empty_depot)})
    try:
        rv = mgr.revise_in_session(sid)
        assert rv["ok"] is False
        assert rv["revised"] is False
        assert "Revise unavailable" in rv["error"]
    finally:
        mgr.stop_session(sid)


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))
