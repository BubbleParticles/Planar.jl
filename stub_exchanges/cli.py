"""Simple CLI to run the stub exchange server.

Usage:
    python cli.py --exchange binance --host 127.0.0.1 --port 8000

Activate the venv: source venv/bin/activate
"""
import argparse
import sys


def main():
    parser = argparse.ArgumentParser(description="Run a local stub exchange server")
    parser.add_argument("--exchange", "-e", required=True, help="Exchange name (as in ccxt.exchanges)")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8000, type=int)
    args = parser.parse_args()

    # Lazy import so that CLI can be run without venv activated if desired
    try:
        from stubex import server
    except Exception as exc:
        print("Failed to import stubex.server. Ensure the venv is activated and dependencies installed.")
        print(exc)
        sys.exit(1)

    print(f"Starting stub server for exchange {args.exchange} on {args.host}:{args.port}")
    server.run(args.exchange, host=args.host, port=args.port)


if __name__ == "__main__":
    main()
