#!/usr/bin/env bash
# Skill: daemon-mode
# Trigger: when running Julia commands, tests, or REPL sessions repeatedly
#
# DaemonMode.jl keeps a persistent Julia process alive, eliminating startup
# overhead for repeated commands. Instead of `julia --project=... -e '...'`
# which forks and precompiles on every invocation, send commands to a running
# daemon that already has packages loaded.

set -euo pipefail

DAEMON_PORT=50123
ENVRC_LOADED=false

# Source .envrc if available to get JULIA_PROJECT and other vars
if [ -f .envrc ]; then
  source .envrc 2>/dev/null || true
  ENVRC_LOADED=true
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [args...]

Commands:
  start [PROJECT]    Start a Julia daemon (default project: PlanarDev)
  stop               Stop the running daemon
  run <ARGS...>      Run Julia code through the daemon
  repl               Connect an interactive REPL to the daemon
  status             Check if daemon is running
  -h, --help         Show this help message

Examples:
  $(basename "$0") start PlanarDev
  $(basename "$0") run -e 'using Pkg; Pkg.resolve()'
  $(basename "$0") run -e 'include("PlanarDev/test/test_aqua.jl")'
  $(basename "$0") repl
  $(basename "$0") stop

EOF
  exit 0
}

# Check if daemon is running
is_running() {
  julia --startup-file=no --project=@. -e '
    try
      using DaemonMode
      println(DaemonMode.isrunning() ? "running" : "stopped")
    catch
      println("not_installed")
    end
  ' 2>/dev/null || echo "error"
}

# Start the daemon
start_daemon() {
  local project="${1:-PlanarDev}"
  echo "Starting Julia daemon with project: $project"
  julia --project="$project" -e '
    using DaemonMode
    println("Daemon starting on port ", DaemonMode.port())
    run_daemon()
  ' &
  DAEMON_PID=$!
  echo "Daemon PID: $DAEMON_PID"
  # Wait for daemon to be ready
  sleep 2
  echo "Daemon ready."
}

# Stop the daemon
stop_daemon() {
  echo "Stopping Julia daemon..."
  julia --startup-file=no -e '
    try
      using DaemonMode
      stop_daemon()
      println("Daemon stopped.")
    catch
      println("Daemon was not running.")
    end
  ' 2>/dev/null
}

# Run code through the daemon
run_code() {
  julia --startup-file=no -e '
    using DaemonMode
    try
      result = runargs(ARGS...)
      println(result)
    catch e
      println("Error: ", e)
      rethrow(e)
    end
  ' "$@"
}

# Connect interactive REPL
connect_repl() {
  echo "Connecting to daemon REPL..."
  julia --startup-file=no -e '
    using DaemonMode
    repl_connect()
  '
}

# Main dispatch
if [ "$#" -eq 0 ]; then
  usage
fi

case "$1" in
  start)
    shift
    start_daemon "$@"
    ;;
  stop)
    stop_daemon
    ;;
  run)
    shift
    run_code "$@"
    ;;
  repl)
    connect_repl
    ;;
  status)
    status
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "Unknown command: $1"
    usage
    ;;
esac
