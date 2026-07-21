# daemon-mode

Trigger: when optimizing development workflow / running Julia multiple times.

DaemonMode.jl keeps a persistent Julia process to avoid startup overhead.

Usage:
- Start daemon: `daemon-mode.sh start`
- Stop daemon:  `daemon-mode.sh stop`

Direct Julia invocation (without shell wrapper):
- Start daemon:
  ```bash
  julia --project=PlanarDev -e 'using DaemonMode; run_daemon()' &
  ```
- Send a command:
  ```bash
  DaemonMode.runargs("PlanarDev", "-e", "using Pkg; Pkg.resolve()")
  ```
- Attach a REPL to the running daemon:
  ```bash
  julia --project=PlanarDev -e 'using DaemonMode; DaemonMode.repl_connect()'
  ```
- Stop daemon:
  ```bash
  DaemonMode.stop_daemon()
  ```

Notes: The wrapper script manages a `.daemon_pid` file for tracking.
