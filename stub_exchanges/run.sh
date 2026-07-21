#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
VENV="$ROOT_DIR/venv"
if [ ! -d "$VENV" ]; then
  echo "Creating venv..."
  python3 -m venv "$VENV"
  "$VENV/bin/python" -m pip install --upgrade pip setuptools wheel
  "$VENV/bin/pip" install -r "$ROOT_DIR/requirements.txt"
fi

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 exchange [host] [port]"
  exit 2
fi
EXC="$1"
HOST=${2:-127.0.0.1}
PORT=${3:-8000}

source "$VENV/bin/activate"
python "$ROOT_DIR/cli.py" --exchange "$EXC" --host "$HOST" --port "$PORT"
