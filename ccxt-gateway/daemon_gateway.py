#!/usr/bin/env python3
"""
Daemonize the ccxt-gateway process.
"""
import sys
import os
import signal

# Double-fork to daemonize
def daemonize():
    # First fork
    try:
        pid = os.fork()
        if pid > 0:
            # Parent exits
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
            # Parent exits
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
    
    # Now run the gateway
    print("Daemon started")
    sys.stdout.flush()
    
    # Import and run
    sys.path.insert(0, 'src')
    from ccxt_gateway.main import main
    main()

if __name__ == '__main__':
    daemonize()
