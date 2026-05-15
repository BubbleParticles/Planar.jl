#!/usr/bin/env python3
"""
Daemonize the ccxt-gateway process.
"""
import sys
import os
import signal

PIDFILE = "/tmp/ccxt_gateway.pid"


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
    os.chdir('/project/ccxt-gateway')
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

    # Write PID file
    pid = os.getpid()
    with open(PIDFILE, "w") as f:
        f.write(str(pid))
    print(f"Gateway started with PID {pid}")

    # Import and run
    sys.path.insert(0, 'src')
    from ccxt_gateway.main import main
    main()


if __name__ == '__main__':
    daemonize()
