#!/usr/bin/env python3
"""
Daemonize the ccxt-gateway process.
"""
import sys
import os
import signal
import subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CACHE_DIR = os.path.join(SCRIPT_DIR, ".cache")
PIDFILE = os.path.join(CACHE_DIR, "ccxt_gateway.pid")


def _ensure_ssl_cert() -> bool:
    """Generate a self-signed SSL certificate for the gateway if one doesn't exist.

    Returns True if cert/key are available (either pre-existing or freshly generated),
    False if generation failed and the gateway should fall back to HTTP.
    """
    cert_file = os.path.join(CACHE_DIR, "server.crt")
    key_file = os.path.join(CACHE_DIR, "server.key")

    if os.path.exists(cert_file) and os.path.exists(key_file):
        return True

    os.makedirs(CACHE_DIR, exist_ok=True)

    try:
        subprocess.run(
            [
                "openssl", "req", "-x509", "-newkey", "rsa:2048",
                "-keyout", key_file, "-out", cert_file,
                "-days", "365", "-nodes",
                "-subj", "/CN=localhost",
                "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1",
            ],
            check=True,
            capture_output=True,
        )
        print(f"Generated self-signed SSL cert: {cert_file}")
        return True
    except Exception as e:
        print(f"SSL cert generation failed (gateway will use HTTP): {e}", file=sys.stderr)
        return False


def daemonize():
    # First fork
    try:
        pid = os.fork()
        if pid > 0:
            sys.exit(0)
    except OSError as e:
        print(f"First fork failed: {e}", file=sys.stderr)
        sys.exit(1)

    # Decouple from parent environment
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)
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
    dev_null = open(os.devnull, 'r')
    os.dup2(dev_null.fileno(), sys.stdin.fileno())
    log = open('/tmp/gateway.log', 'a+')
    os.dup2(log.fileno(), sys.stdout.fileno())
    os.dup2(log.fileno(), sys.stderr.fileno())

    # Generate self-signed SSL certificate so the gateway serves HTTPS.
    # The env vars are consumed by ccxt_gateway.config.ServerConfig via Pydantic.
    if _ensure_ssl_cert():
        cert_file = os.path.join(CACHE_DIR, "server.crt")
        key_file = os.path.join(CACHE_DIR, "server.key")
        os.environ["CCXT_GATEWAY_SERVER_USE_SSL"] = "true"
        os.environ["CCXT_GATEWAY_SERVER_SSL_CERT"] = cert_file
        os.environ["CCXT_GATEWAY_SERVER_SSL_KEY"] = key_file
    # Write PID file
    pid = os.getpid()
    with open(PIDFILE, "w") as f:
        f.write(str(pid))
    print(f"Gateway started with PID {pid}")

    # Import and run — settings will pick up env vars set above
    sys.path.insert(0, 'src')
    from ccxt_gateway.main import main
    main()


if __name__ == '__main__':
    daemonize()
