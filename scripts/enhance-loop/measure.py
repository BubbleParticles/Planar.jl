#!/usr/bin/env python3
"""Measure MCP tool latency and deps vulnerabilities."""
import json, time, subprocess, pathlib, os

def mcp_latency():
    try:
        from ccxt_gateway.mcp_server import SessionManager
        sm = SessionManager()
        sid = sm.start_session()
        t0 = time.perf_counter()
        sm.eval_in_session(sid, "1+1")
        t1 = time.perf_counter()
        sm.stop_session(sid)
        return t1 - t0
    except Exception as e:
        return None

def cache_size():
    d = pathlib.Path.home() / ".julia" / "compiled"
    if not d.exists():
        return 0
    return sum(f.stat().st_size for f in d.rglob("*") if f.is_file())

def main():
    metrics = {
        "timestamp": time.time(),
        "cache_bytes": cache_size(),
        "mcp_eval_s": mcp_latency(),
        "python": os.sys.version,
    }
    out = pathlib.Path(__file__).resolve().parents[2] / "reports" / "enhance-loop-baseline.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    # merge with julia metrics if exists
    if out.exists():
        try:
            prev = json.loads(out.read_text())
            metrics = {**prev, **metrics}
        except: pass
    out.write_text(json.dumps(metrics, indent=2))
    print(json.dumps(metrics, indent=2))

if __name__ == "__main__":
    main()
