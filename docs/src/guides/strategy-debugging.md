# Strategy Debugging Guide

## MCP session errors
`eval_in_session` returns `error_type` (Julia exception type) and trimmed backtrace (2000 chars). Use to distinguish `UndefVarError` vs `ArgumentError`.

## Debug flags
- `JULIA_DEBUG=LogWatchLocks,LogOHLCVTickers julia ...` traces locks and OHLCV ticker watcher (rule 22).
- `JULIA_DEBUG=LogWatchLocks` for lock acquire/release.

## Remote redaction
`Remote._redact` replaces values for keys matching `r"api[_-]?key|secret|token|pass|psw|private|auth"i` with `[redacted]` before sending via Telegram.
