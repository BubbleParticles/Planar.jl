"""MCP server exposing tools to write, test, and deploy Planar strategies.

The server runs on stdio by default. The pure-logic helpers
(``write_strategy``, ``test_strategy``, ``deploy_strategy``) are decoupled from
the MCP transport so they can be unit-tested without a running server, a live
gateway, or a live exchange. The MCP tool wrappers only parse arguments and
format the structured result.
"""

from __future__ import annotations

import json
import os
import re
import select
import subprocess
import tempfile
import threading
from pathlib import Path
from typing import Any, Optional

try:  # Python 3.11+ ships tomllib in the stdlib.
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - only for very old Pythons
    import tomli as tomllib  # type: ignore

import tomli_w

from fastmcp import FastMCP

# ---------------------------------------------------------------------------
# Configuration (overridable via environment variables)
# ---------------------------------------------------------------------------

DEFAULT_STRATEGIES_DIR = os.environ.get(
    "PLANAR_STRATEGIES_DIR", "/Planar.jl/user/strategies"
)
DEFAULT_STRATEGIES_TOML = os.environ.get(
    "PLANAR_STRATEGIES_TOML", "/Planar.jl/scripts/strategies.toml"
)
DEFAULT_RUN_JL = os.environ.get("PLANAR_RUN_JL", "/Planar.jl/scripts/run.jl")
DEFAULT_JULIA = os.environ.get("JULIA_BIN", "julia")
DEFAULT_TEST_TIMEOUT = float(os.environ.get("PLANAR_TEST_TIMEOUT", "300"))
DEFAULT_RUN_TIMEOUT = float(os.environ.get("PLANAR_RUN_TIMEOUT", "60"))

# ---------------------------------------------------------------------------
# Pure-logic helpers (no MCP / no network dependency)
# ---------------------------------------------------------------------------

_IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def _is_identifier(segment: str) -> bool:
    return bool(_IDENT_RE.match(segment))


def _sanitize_name(name: str) -> str:
    """Validate a strategy name and return a filesystem-safe relative path.

    A name may be a plain identifier (``MyStrat``) or a sub-path
    (``Sub/MyStrat``). Path traversal outside the strategies directory is
    rejected. An explicit ``.jl`` suffix is preserved.
    """
    if not name or not name.strip():
        raise ValueError("strategy name must not be empty")
    rel = name.strip().replace("\\", "/").lstrip("/")
    if rel.startswith("./"):
        rel = rel[2:]
    segments = rel.split("/")
    for segment in segments:
        if segment in ("", ".", ".."):
            raise ValueError(
                f"invalid strategy name {name!r}: path components must be "
                "non-empty and may not be '.' or '..'"
            )
        # The final segment may carry a ``.jl`` suffix.
        seg = segment[:-3] if segment.endswith(".jl") else segment
        if not _is_identifier(seg):
            raise ValueError(
                f"invalid strategy name {name!r}: only alphanumerics, "
                "underscores and '/' are allowed"
            )
    return rel


def _module_name(rel_path: str) -> str:
    """Derive the Julia module name from a strategy file path."""
    fname = rel_path.rsplit("/", 1)[-1]
    if fname.endswith(".jl"):
        fname = fname[:-3]
    return fname


def write_strategy(
    name: str,
    source: str,
    *,
    strategies_dir: Optional[str] = None,
    overwrite: bool = True,
    description: Optional[str] = None,
) -> dict[str, Any]:
    """Create or update a strategy source file on disk.

    ``name`` is a strategy identifier or sub-path; the file is written as
    ``<strategies_dir>/<name>.jl`` (an explicit ``.jl`` suffix is optional).

    Returns a structured dict describing the action performed.
    """
    strategies_dir = strategies_dir or DEFAULT_STRATEGIES_DIR
    rel = _sanitize_name(name)
    if not rel.endswith(".jl"):
        rel = f"{rel}.jl"
    base = Path(strategies_dir).resolve()
    target = (base / rel).resolve()
    # Guard against a path that escapes the strategies directory.
    if target != base and base not in target.parents:
        raise ValueError(f"refusing to write outside strategies dir: {target}")
    existed = target.exists()
    if existed and not overwrite:
        raise FileExistsError(f"strategy already exists: {target}")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(source, encoding="utf-8")
    return {
        "success": True,
        "name": _module_name(rel),
        "path": str(target),
        "relative_path": rel,
        "action": "updated" if existed else "created",
        "bytes": len(source.encode("utf-8")),
        "description": description,
    }


def _run(cmd: list[str], timeout: float) -> tuple[Optional[int], str, str, Optional[str]]:
    """Run a command, returning (returncode, stdout, stderr, system_error).

    ``system_error`` is non-None only when the command could not be launched or
    exceeded ``timeout`` — the caller surfaces it instead of crashing.
    """
    try:
        proc = subprocess.run(
            cmd,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            start_new_session=True,
        )
        return proc.returncode, proc.stdout or "", proc.stderr or "", None
    except FileNotFoundError as exc:
        return None, "", "", f"command not found: {exc}"
    except subprocess.TimeoutExpired as exc:
        out = exc.stdout if isinstance(exc.stdout, str) else ""
        err = exc.stderr if isinstance(exc.stderr, str) else ""
        return None, out, err, f"timed out after {timeout}s"


def _verdict(returncode: Optional[int], out: str, err: str) -> str:
    """Map a Julia test run's output to a verdict.

    Julia's ``Test`` package exits non-zero on any failing test, so a zero exit
    code means the suite passed. Non-zero exits are classified as ``fail`` when
    they carry a test-report signature, otherwise ``error``.
    """
    text = f"{out}\n{err}"
    if returncode == 0:
        return "pass"
    fail_markers = (
        "Error During Test",
        "Test Failed",
        "There was an error during testing",
        "Test Summary",
        "UndefVarError",
        "LoadError",
        "ParseError",
        "ERROR:",
    )
    if any(marker in text for marker in fail_markers):
        return "fail"
    return "error"


def test_strategy(
    name: str,
    *,
    strategies_dir: Optional[str] = None,
    julia: Optional[str] = None,
    timeout: Optional[float] = None,
) -> dict[str, Any]:
    """Run a strategy's Julia test suite and report a pass/fail verdict.

    Resolution order for the test command:

    * directory project with ``test/runtests.jl`` ->
      ``julia --project=<dir> test/runtests.jl``
    * directory project with ``Project.toml`` only ->
      ``julia --project=<dir> -e 'using Pkg; Pkg.test()'``
    * single ``.jl`` file (no project) ->
      ``julia -e 'Meta.parse(read(...))' <file>`` (parse-only check, no deps)

    Returns a structured dict with ``verdict`` in {pass, fail, error, skipped}.
    """
    strategies_dir = strategies_dir or DEFAULT_STRATEGIES_DIR
    julia = julia or DEFAULT_JULIA
    timeout = timeout if timeout is not None else DEFAULT_TEST_TIMEOUT
    rel = _sanitize_name(name)
    base = Path(strategies_dir).resolve()
    candidate_file = base / rel if rel.endswith(".jl") else base / f"{rel}.jl"
    candidate_dir = base / rel

    if candidate_dir.is_dir():
        proj = candidate_dir / "Project.toml"
        test_file = candidate_dir / "test" / "runtests.jl"
        if test_file.is_file():
            cmd = [julia, f"--project={candidate_dir}", str(test_file)]
        elif proj.is_file():
            cmd = [julia, f"--project={candidate_dir}", "-e", "using Pkg; Pkg.test()"]
        else:
            return {
                "success": False,
                "name": _module_name(rel),
                "verdict": "skipped",
                "command": None,
                "returncode": None,
                "output": "",
                "error": "directory has no Project.toml or test/runtests.jl",
            }
    elif candidate_file.is_file():
        # Single-file strategy: parse-check only (no isolated test harness, and
        # no execution so missing Planar deps don't cause a false failure).
        cmd = [julia, "-e", "Meta.parse(read(ARGS[1], String))", str(candidate_file)]
    else:
        return {
            "success": False,
            "name": _module_name(rel),
            "verdict": "error",
            "command": None,
            "returncode": None,
            "output": "",
            "error": (
                f"strategy not found: neither {candidate_file} nor "
                f"{candidate_dir} exist"
            ),
        }

    rc, out, err, syserr = _run(cmd, timeout)
    verdict = _verdict(rc, out, err) if syserr is None else "error"
    return {
        "success": verdict == "pass",
        "name": _module_name(rel),
        "verdict": verdict,
        "command": " ".join(cmd),
        "returncode": rc,
        "output": (out + err)[-4000:],
        "error": syserr,
    }


def _load_strategies_toml(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    with path.open("rb") as handle:
        data = tomllib.load(handle)
    return list(data.get("strategy", []))


def _already_registered(
    entries: list[dict[str, Any]], name: str, exchange: str, account: str
) -> bool:
    return any(
        str(entry.get("name")) == name
        and str(entry.get("exchange")) == exchange
        and str(entry.get("account")) == str(account)
        for entry in entries
    )


def _write_strategies_toml(path: Path, entries: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as handle:
        tomli_w.dump({"strategy": entries}, handle)


def _write_temp_config(parent: Path, entries: list[dict[str, Any]]) -> Path:
    tmp = parent / ".mcp_deploy_tmp.toml"
    with tmp.open("wb") as handle:
        tomli_w.dump({"strategy": entries}, handle)
    return tmp


def deploy_strategy(
    name: str,
    exchange: str,
    *,
    account: str = "1",
    mode: str = "Paper",
    env: Optional[dict[str, str]] = None,
    strategies_dir: Optional[str] = None,
    strategies_toml: Optional[str] = None,
    run_jl: Optional[str] = None,
    julia: Optional[str] = None,
    run: bool = False,
    run_timeout: Optional[float] = None,
) -> dict[str, Any]:
    """Register a strategy in ``strategies.toml`` and optionally launch it.

    Registration is always performed (it does not require Julia). When ``run``
    is True the strategy is launched via ``scripts/run.jl --config <toml>`` with
    a bounded timeout; the captured startup output is returned so callers can see
    whether the deployment actually started (e.g. a precompilation failure is
    surfaced as a structured error rather than a crash).
    """
    strategies_dir = strategies_dir or DEFAULT_STRATEGIES_DIR
    strategies_toml = strategies_toml or DEFAULT_STRATEGIES_TOML
    run_jl = run_jl or DEFAULT_RUN_JL
    julia = julia or DEFAULT_JULIA
    run_timeout = run_timeout if run_timeout is not None else DEFAULT_RUN_TIMEOUT

    rel = _sanitize_name(name)
    module_name = _module_name(rel)
    toml_path = Path(strategies_toml)
    entries = _load_strategies_toml(toml_path)
    entry: dict[str, Any] = {
        "name": module_name,
        "exchange": exchange,
        "account": str(account),
        "env": dict(env or {}),
    }
    already = _already_registered(entries, module_name, exchange, str(account))
    if not already:
        entries.append(entry)
        _write_strategies_toml(toml_path, entries)

    result: dict[str, Any] = {
        "success": True,
        "name": module_name,
        "exchange": exchange,
        "account": str(account),
        "mode": mode,
        "registered": not already,
        "strategies_toml": str(toml_path),
        "entry": entry,
    }

    if run:
        cfg = _write_temp_config(toml_path.parent, [entry])
        cmd = [julia, str(run_jl), "--config", str(cfg)]
        rc, out, err, syserr = _run(cmd, run_timeout)
        result["run"] = {
            "command": " ".join(cmd),
            "returncode": rc,
            "started": syserr is None,
            "output": (out + err)[-4000:],
            "error": syserr,
        }
    return result


# ---------------------------------------------------------------------------
# Persistent Julia REPL session manager
# ---------------------------------------------------------------------------
#
# Each session is a long-running Julia process (started from an embedded
# bootstrap) whose stdin/stdout are dedicated pipes — fully isolated from the
# MCP server's own stdio, so a session's death cannot take the server down.
# The Julia side runs a read-eval-print loop framed as:
#
#   Python -> Julia : "EVAL <n>\n" + <n bytes of code> + "\n"
#   Julia  -> Python : "RESULT <m>\n" + <m bytes of JSON>   (no trailing newline)
#   Python -> Julia : "QUIT\n"   (graceful exit of the loop)
#
# ``include_string(Main, code)`` evaluates at the session's top level, so a
# binding such as ``x = 1`` persists across calls. Per-call eval errors are
# caught inside Julia and returned as a structured result, never killing the
# process. The revise trigger ensures Revise is loaded then calls
# ``Revise.revise()`` to reload any tracked file edited on disk.

_BOOT_TEMPLATE = r'''function json_escape(s::String)
    b = IOBuffer()
    write(b, '"')
    for c in s
        if c == '"'
            write(b, "\\\"")
        elseif c == '\\'
            write(b, "\\\\")
        elseif c == '\n'
            write(b, "\\n")
        elseif c == '\t'
            write(b, "\\t")
        elseif c == '\r'
            write(b, "\\r")
        elseif iscntrl(c)
            write(b, "\\u$(string(UInt32(c); base=16, pad=4))")
        else
            write(b, c)
        end
    end
    write(b, '"')
    return String(take!(b))
end

function doeval(code::String)
    local val
    ok = true
    orig = stdout
    rd, wr = redirect_stdout()
    try
        try
            val = include_string(Main, code)
        catch e
            ok = false
            val = e
        end
    finally
        redirect_stdout(orig)
    end
    close(wr)
    printed = String(read(rd))
    close(rd)
    value = ok ? (val === nothing ? "nothing" : string(val)) : sprint(showerror, val)
    return "{\"ok\":" * (ok ? "true" : "false") * ",\"value\":" * json_escape(value) * ",\"printed\":" * json_escape(printed) * "}"
end

println(stdout, "READY")
flush(stdout)

while true
    line = readline(stdin)
    if line == "QUIT"
        break
    elseif startswith(line, "EVAL ")
        n = parse(Int, line[6:end])
        code = String(read(stdin, n))
        read(stdin, 1)
        result = doeval(code)
        println(stdout, "RESULT")
        println(stdout, result)
        println(stdout, "ENDOFRESULT")
        flush(stdout)
    end
end
'''


class Session:
    """Bookkeeping for one running Julia session subprocess."""

    __slots__ = ("id", "proc", "bootfile", "project")

    def __init__(self, id: str, proc: subprocess.Popen, bootfile: str, project):
        self.id = id
        self.proc = proc
        self.bootfile = bootfile
        self.project = project


class SessionError(Exception):
    """Raised for unrecoverable session-manager failures."""


class SessionManager:
    """Spawn and drive isolated, persistent Julia REPL sessions."""

    def __init__(self, julia: Optional[str] = None, boot_template: Optional[str] = None):
        self.julia = julia or DEFAULT_JULIA
        self._boot_template = boot_template or _BOOT_TEMPLATE
        self._bootfile: Optional[str] = None
        self._sessions: dict[str, Session] = {}
        self._counter = 0
        self.start_timeout = 90.0
        self.eval_timeout = 60.0

    # -- bootstrap file ----------------------------------------------------
    def _ensure_bootfile(self) -> str:
        if self._bootfile is None:
            fd, path = tempfile.mkstemp(suffix=".jl", prefix="planar_mcp_boot_")
            os.close(fd)
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(self._boot_template)
            self._bootfile = path
        return self._bootfile

    # -- raw IO helpers ----------------------------------------------------
    @staticmethod
    def _read_line(stream, timeout: float) -> bytes:
        rlist, _, _ = select.select([stream], [], [], timeout)
        if not rlist:
            raise TimeoutError("no response from Julia session within timeout")
        return stream.readline()

    @staticmethod
    def _read_line_blocking(stream, timeout: float) -> bytes:
        """Read one line with a real timeout.

        ``readline()`` buffers ahead, so a ``select`` guard on the raw fd
        misses buffered lines and would spuriously time out. Instead we read in
        a daemon thread and ``join`` with a timeout, which uses the stream
        buffer correctly and still bounds a stalled/hung session.

        Used for eval results: the Julia session always answers a well-formed
        ``RESULT`` / JSON / ``ENDOFRESULT`` triple, so the only failure modes
        are a dead process (EOF) or an over-long stall, both surfaced as an
        error result rather than a hang.
        """
        box: list = [None]

        def _target() -> None:
            try:
                box[0] = stream.readline()
            except Exception as exc:  # pragma: no cover - defensive
                box[0] = exc

        worker = threading.Thread(target=_target, daemon=True)
        worker.start()
        worker.join(timeout)
        if worker.is_alive():
            raise TimeoutError("no response from Julia session within timeout")
        if isinstance(box[0], Exception):
            raise box[0]
        return box[0]

    # -- lifecycle ---------------------------------------------------------
    def start_session(
        self, project: Optional[str] = None, env: Optional[dict] = None
    ) -> str:
        """Spawn a Julia REPL session; return a stable session id.

        ``project`` is passed as ``--project=<dir>``. ``env`` (if given) is
        merged into the current environment so the session subprocess keeps
        ``PATH`` etc. (e.g. pass ``{"JULIA_DEPOT_PATH": "/empty"}`` to start a
        session in which Revise cannot be loaded).
        """
        boot = self._ensure_bootfile()
        cmd = [self.julia]
        if project:
            cmd.append(f"--project={project}")
        cmd.append(boot)
        full_env = dict(os.environ)
        if env:
            full_env.update({str(k): str(v) for k, v in env.items()})
        proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
            env=full_env,
        )
        try:
            ready = self._read_line(proc.stdout, self.start_timeout)
            if ready.strip() != b"READY":
                err = b""
                try:
                    err = proc.stderr.read(4096)
                except Exception:
                    pass
                raise SessionError(
                    f"session did not start cleanly: {ready!r} {err!r}"
                )
        except Exception:
            proc.kill()
            raise
        self._counter += 1
        sid = f"session-{self._counter}"
        self._sessions[sid] = Session(sid, proc, boot, project)
        return sid

    def stop_session(self, sid: str) -> dict[str, Any]:
        """Terminate a session and its Julia process."""
        sess = self._sessions.pop(sid, None)
        if sess is None:
            return {"session": sid, "stopped": False, "error": "unknown session"}
        proc = sess.proc
        try:
            proc.stdin.write(b"QUIT\n")
            proc.stdin.flush()
        except Exception:
            pass
        try:
            proc.wait(timeout=10)
        except Exception:
            proc.kill()
        return {"session": sid, "stopped": True, "pid": proc.pid}

    def list_sessions(self) -> dict[str, dict[str, Any]]:
        """Return active sessions keyed by id."""
        return {
            sid: {
                "session": sid,
                "pid": s.proc.pid,
                "project": s.project,
            }
            for sid, s in self._sessions.items()
        }

    def _get(self, sid: str) -> Session:
        sess = self._sessions.get(sid)
        if sess is None:
            raise KeyError(sid)
        return sess

    # -- evaluation --------------------------------------------------------
    def eval_in_session(
        self, sid: str, code: str, timeout: Optional[float] = None
    ) -> dict[str, Any]:
        """Evaluate ``code`` in ``sid``; returns ``ok``/``value``/``printed``.

        State defined at the session's top level persists across calls.
        """
        data = code.encode("utf-8")
        try:
            sess = self._get(sid)
            proc = sess.proc
            proc.stdin.write(b"EVAL " + str(len(data)).encode() + b"\n")
            proc.stdin.write(data)
            proc.stdin.write(b"\n")
            proc.stdin.flush()
            header = self._read_line_blocking(
                proc.stdout, timeout or self.eval_timeout
            )
            if not header.startswith(b"RESULT"):
                raise RuntimeError(f"unexpected session response: {header!r}")
            json_line = self._read_line_blocking(
                proc.stdout, timeout or self.eval_timeout
            )
            trailer = self._read_line_blocking(
                proc.stdout, timeout or self.eval_timeout
            )
            if not trailer.startswith(b"ENDOFRESULT"):
                raise RuntimeError(f"malformed session response: {trailer!r}")
            return json.loads(json_line.decode("utf-8"))
        except (TimeoutError, EOFError, ValueError, RuntimeError, KeyError) as exc:
            return {"ok": False, "value": None, "printed": "", "error": str(exc)}

    def revise_in_session(
        self, sid: str, timeout: Optional[float] = None
    ) -> dict[str, Any]:
        """Load Revise (if needed) in ``sid`` and apply pending source changes.

        Returns ``ok=True, revised=True`` on success, or a structured error
        (``ok=False``) when Revise cannot be loaded in the session's env.
        """
        to = timeout or self.eval_timeout
        load = self.eval_in_session(
            sid,
            "try\n  using Revise\n  \"loaded\"\n"
            "catch e\n  \"ERROR: \" * sprint(showerror, e)\nend",
            timeout=to,
        )
        if not load.get("ok") or not str(load.get("value", "")).startswith("loaded"):
            return {
                "ok": False,
                "revised": False,
                "error": "Revise unavailable in this session",
                "detail": load,
            }
        res = self.eval_in_session(sid, "Revise.revise()", timeout=to)
        return {
            "ok": bool(res.get("ok")),
            "revised": bool(res.get("ok")),
            "error": None if res.get("ok") else res.get("value"),
            "detail": res,
        }


# ---------------------------------------------------------------------------
# MCP transport layer
# ---------------------------------------------------------------------------

mcp = FastMCP("planar-strategy-manager")

# One shared session manager backing the session tools. Tests may also
# instantiate ``SessionManager`` directly for isolated coverage.
SESSION_MANAGER = SessionManager()


@mcp.tool()
def write_strategy_tool(
    name: str,
    source: str,
    overwrite: bool = True,
    description: Optional[str] = None,
) -> dict:
    """Create or update a strategy source file on disk.

    Args:
        name: Strategy identifier or sub-path (e.g. ``MyStrat`` or ``Sub/MyStrat``).
        source: Julia source code for the strategy module.
        overwrite: Replace an existing file when True.
        description: Optional human description (returned in the result only).

    Returns a structured dict with the written ``path``, ``action`` and byte count.
    """
    return write_strategy(name, source, overwrite=overwrite, description=description)


@mcp.tool()
def test_strategy_tool(
    name: str,
    julia: Optional[str] = None,
    timeout: Optional[float] = None,
) -> dict:
    """Run a strategy's Julia test suite and report a pass/fail verdict.

    Args:
        name: Strategy identifier or sub-path.
        julia: Path/command for the Julia executable (default ``julia``).
        timeout: Maximum seconds for the test run.

    Returns a structured dict with ``verdict`` in {pass, fail, error, skipped}.
    """
    return test_strategy(name, julia=julia, timeout=timeout)


@mcp.tool()
def deploy_strategy_tool(
    name: str,
    exchange: str,
    account: str = "1",
    mode: str = "Paper",
    env: Optional[dict[str, str]] = None,
    run: bool = False,
    run_timeout: Optional[float] = None,
) -> dict:
    """Register a strategy in strategies.toml and optionally launch it.

    Args:
        name: Strategy identifier or sub-path.
        exchange: Exchange id (e.g. ``binance``, ``bitmex``).
        account: Account id (default ``"1"``).
        mode: Run mode (``Sim``/``Paper``/``Live``) — recorded in the result.
        env: Optional dict of environment variables for the strategy process.
        run: Launch the strategy via scripts/run.jl after registering.
        run_timeout: Maximum seconds for the launch probe.

    Returns a structured dict including the registered ``entry`` and, when
    ``run`` is True, a ``run`` sub-dict with the captured launch output.
    """
    return deploy_strategy(
        name,
        exchange,
        account=account,
        mode=mode,
        env=env,
        run=run,
        run_timeout=run_timeout,
    )


@mcp.tool()
def start_session_tool(project: Optional[str] = None) -> dict:
    """Start a persistent Julia REPL session.

    Args:
        project: Optional Julia project directory passed as ``--project=``. The
            session loads that project's environment (use a project that has
            Revise installed for the revise trigger to work).

    Returns a dict with the stable ``session`` id, ``pid``, and ``project``.
    """
    sid = SESSION_MANAGER.start_session(project=project)
    sess = SESSION_MANAGER._sessions[sid]
    return {
        "session": sid,
        "status": "started",
        "pid": sess.proc.pid,
        "project": sess.project,
    }


@mcp.tool()
def stop_session_tool(session: str) -> dict:
    """Stop a Julia REPL session and terminate its process.

    Args:
        session: The session id returned by ``start_session``.

    Returns a dict with ``stopped`` and the ``session`` id (or an error when
    the id is unknown).
    """
    return SESSION_MANAGER.stop_session(session)


@mcp.tool()
def list_sessions_tool() -> dict:
    """List active Julia REPL sessions.

    Returns a dict mapping each session id to its ``pid`` and ``project``.
    """
    return SESSION_MANAGER.list_sessions()


@mcp.tool()
def eval_in_session_tool(
    session: str, code: str, timeout: Optional[float] = None
) -> dict:
    """Evaluate Julia code in a persistent session.

    Args:
        session: The session id returned by ``start_session``.
        code: Julia source to evaluate. Bindings such as ``x = 1`` persist
            across calls within the same session.
        timeout: Maximum seconds to wait for the result.

    Returns a structured dict with ``ok``, ``value``, and ``printed``. A
    per-call eval error is reported via ``ok=false`` rather than killing the
    session.
    """
    return SESSION_MANAGER.eval_in_session(session, code, timeout=timeout)


@mcp.tool()
def revise_in_session_tool(session: str, timeout: Optional[float] = None) -> dict:
    """Apply pending source changes in a session via Revise.

    Loads Revise (if not already loaded) in the target session, then calls
    ``Revise.revise()`` to reload any tracked file whose source changed on
    disk (e.g. after the AI edited a strategy module).

    Args:
        session: The session id returned by ``start_session``.
        timeout: Maximum seconds to wait for the result.

    Returns a dict with ``ok``, ``revised``, and ``error`` — ``error`` is set
    (with ``ok=false``) when Revise is unavailable in the session's env.
    """
    return SESSION_MANAGER.revise_in_session(session, timeout=timeout)


def main() -> None:
    """Entry point: serve the strategy tools over stdio."""
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
