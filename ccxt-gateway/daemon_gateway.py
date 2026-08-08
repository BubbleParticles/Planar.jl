#!/usr/bin/env python3
"""Dev-only shim: run the gateway daemon from a source checkout.

Delegates to the installed ``ccxt_gateway`` package. If the package is not
installed (plain source checkout without ``pip install -e .``), it falls back to
importing from the sibling ``src/`` directory so `python daemon_gateway.py`
still works during development.

For installed usage, always invoke the package directly:

    python -m ccxt_gateway.daemon_gateway
"""
import os
import sys

try:
    from ccxt_gateway.daemon_gateway import main
except ImportError:
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "src"))
    from ccxt_gateway.daemon_gateway import main

if __name__ == "__main__":
    main()
