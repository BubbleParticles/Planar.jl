#!/usr/bin/env python3
"""Daemon entrypoint for the ccxt-gateway server.

Run as ``python -m ccxt_gateway.daemon_gateway`` (or via the
``ccxt-gateway-daemon`` console script). The process double-forks into the
background, generates a self-signed SSL certificate (if missing so the gateway
serves HTTPS), writes a PID file, then serves the FastAPI app.

Runtime files (PID file, SSL cert/key) live in a cache directory resolved in
the following order:

1. ``$CCXT_GATEWAY_CACHE_DIR``
2. ``$XDG_CACHE_HOME/ccxt-gateway``  (POSIX)
3. ``~/.cache/ccxt-gateway``         (POSIX)
4. ``%LOCALAPPDATA%/ccxt-gateway``   (Windows)

The Julia side (``PlanarCore.CcxtGateway.Rest``) uses the exact same resolution
so the PID file written here can be read back for lifecycle management.
"""
from __future__ import annotations

import os
import subprocess
import sys


def cache_dir() -> str:
    env = os.environ.get("CCXT_GATEWAY_CACHE_DIR")
    if env:
        return env
    if sys.platform == "win32":
        base = os.environ.get("LOCALAPPDATA", os.path.expanduser("~"))
        return os.path.join(base, "ccxt-gateway")
    xdg = os.environ.get("XDG_CACHE_HOME")
    base = xdg if xdg else os.path.expanduser("~/.cache")
    return os.path.join(base, "ccxt-gateway")


CACHE_DIR = cache_dir()
PIDFILE = os.path.join(CACHE_DIR, "ccxt_gateway.pid")


def _ensure_ssl_cert() -> bool:
    """Generate a self-signed SSL certificate for the gateway if one is missing.

    Returns True when a cert/key pair is available (pre-existing or freshly
    generated), False when generation failed and the gateway should fall back to
    plain HTTP.
    """
    cert_file = os.path.join(CACHE_DIR, "server.crt")
    key_file = os.path.join(CACHE_DIR, "server.key")

    if os.path.exists(cert_file) and os.path.exists(key_file):
        return True

    os.makedirs(CACHE_DIR, exist_ok=True)
    try:
        subprocess.run(
            [
                "openssl",
                "req",
                "-x509",
                "-newkey",
                "rsa:2048",
                "-keyout",
                key_file,
                "-out",
                cert_file,
                "-days",
                "365",
                "-nodes",
                "-subj",
                "/CN=localhost",
                "-addext",
                "subjectAltName=DNS:localhost,IP:127.0.0.1",
            ],
            check=True,
            capture_output=True,
        )
        print(f"Generated self-signed SSL cert: {cert_file}")
        return True
    except Exception as e:
        print(
            f"SSL cert generation failed (gateway will use HTTP): {e}",
            file=sys.stderr,
        )
        return False


def daemonize():
    """Detach from the controlling terminal via the classic double-fork."""
    # First fork
    try:
        pid = os.fork()
        if pid > 0:
            sys.exit(0)
    except OSError as e:
        print(f"First fork failed: {e}", file=sys.stderr)
        sys.exit(1)

    # Decouple from the parent environment. Chdir into the cache dir (not the
    # site-packages install dir, which may live on read-only media).
    os.chdir(CACHE_DIR)
    os.setsid()
    os.umask(0)

    # Second fork
    try:
        pid = os.fork()
        if pid > 0:
            sys.exit(0)
    except OSError as e:
        print(f"Second fork failed: {e}", file=sys.stderr)
        sys.exit(1)

    # Redirect standard file descriptors
    sys.stdout.flush()
    sys.stderr.flush()
    dev_null = open(os.devnull, "r")
    os.dup2(dev_null.fileno(), sys.stdin.fileno())
    log = open("/tmp/gateway.log", "a+")
    os.dup2(log.fileno(), sys.stdout.fileno())
    os.dup2(log.fileno(), sys.stderr.fileno())


def main():
    """Daemonize, set up SSL env, write the PID file, then serve the app."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    daemonize()

    # Generate a self-signed SSL cert so the gateway serves HTTPS. The env
    # vars are consumed by ccxt_gateway.config.ServerConfig (Pydantic) at
    # import time, so they MUST be set before importing the gateway main.
    if _ensure_ssl_cert():
        cert_file = os.path.join(CACHE_DIR, "server.crt")
        key_file = os.path.join(CACHE_DIR, "server.key")
        os.environ["CCXT_GATEWAY_SERVER_USE_SSL"] = "true"
        os.environ["CCXT_GATEWAY_SERVER_SSL_CERT"] = cert_file
        os.environ["CCXT_GATEWAY_SERVER_SSL_KEY"] = key_file

    # Write the PID file so the Julia side can track / adopt the daemon.
    pid = os.getpid()
    with open(PIDFILE, "w") as f:
        f.write(str(pid))
    print(f"Gateway started with PID {pid}")

    # Import lazily — server config reads the env vars above at import time.
    from ccxt_gateway.main import main as gateway_main

    gateway_main()


if __name__ == "__main__":
    main()
