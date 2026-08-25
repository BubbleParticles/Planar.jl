# Planar.jl Security Audit

**Date:** 2026-08-25 · **Scope:** secrets hygiene, dependencies, code vulnerabilities, containers. Method: git-history scan + full reads of ccxt-gateway Python modules and Julia CcxtGateway client; every claim verified in source.

## Critical

### SEC-001 · Live API key committed in tracked `.env`, present throughout git history (CWE-798/312)
- `git ls-files` lists `.env` at HEAD; contents assign `SMALLCODE_API_KEY=nvapi-…` (NVIDIA NIM provider config; value not reproduced here). Blobs reachable from HEAD across many commits — every clone carries it.
- `user/.keys` and `user/secrets.toml` are correctly ignored (`/user/*`); `.env` matches no ignore rule.
- **Fix:** rotate the key immediately; `git rm --cached .env`; add `.env*` to .gitignore; scrub history (filter-repo) if the repo is or becomes public. Effort S.

### SEC-002 · ccxt-gateway exposes full trading control plane with zero auth on 0.0.0.0 (CWE-306/284)
- `config.py:27-31` host default `0.0.0.0`; no auth middleware on any route in rest.py/admin.py/websocket.py/main.py; `docker-compose.yml:5-8` publishes 8000 to host.
- `POST /admin/shutdown` kills the gateway unauthenticated; exchange creation carries credentials; arbitrary CCXT methods (incl. withdraw-class) callable by anyone network-reachable.
- **Fix:** bind 127.0.0.1 by default; add bearer-token auth dependency; never publish 8000 by default in compose. Effort M.

## High

### SEC-003 · Credentials travel as URL query params and are echoed by admin endpoint (CWE-598/532)
- `api/rest.py:61-65` api_key/secret accepted as Query params → uvicorn/proxy access logs. `admin.py:137-152` returns `proc.config` verbatim incl. secret; plaintext retention at `process_manager.py:139-143`. Julia client mirrors this: `CcxtGateway/rest.jl:155-166`.
- **Fix:** accept credentials only via POST body; redact `apiKey`/`secret` from admin responses. Effort M.

### SEC-004 · Gateway daemon writes SSL private key world-readable (CWE-732/312)
- `daemon_gateway.py:76-78` sets `os.umask(0)` in daemonize() and never restores; `_ensure_ssl_cert()` (:84-100) generates the RSA key AFTER → `~/.cache/ccxt-gateway/server.key` effectively world-readable. Any local user can impersonate the gateway (clients skip verification per SEC-005).
- **Fix:** set restrictive umask after double-fork or chmod 600 the key post-generation. Effort S.

### SEC-005 · Julia client permanently disables TLS verification (CWE-295)
- `rest.jl:78-80` `require_ssl_verification=false` on all HTTPS calls; `websocket.jl:123-125` same for WS. Paired with per-machine self-signed cert (CN=localhost), no pinning → active MITM undetected when gateway runs off-host.
- **Fix:** pin the server cert fingerprint at first connection (TOFU) and verify thereafter. Effort M.

### SEC-006 · Sandbox exchange credentials injected as Docker build args (CWE-798/214)
- `Dockerfile:45-51,72-105` declare PLANAR_BITMEX/PHEMEX_SANDBOX_* as ARG; `scripts/build-image.sh:13-18` forwards live env values; CI forwards GitHub secrets (`build.yml:88-94`). ARG values persist in image metadata — retrievable via `docker history` by anyone with the published image.
- **Fix:** pass at runtime via env file/secrets mount, not build args. Effort M.

## Medium

### SEC-007 · Debug logging leaks request params incl. credentials into persistent logs (CWE-532)
- `subprocess.py:7` unconditional DEBUG print at import; :240 logs full method+params (set_api_key secrets) at INFO; `process_manager.py:266` mirrors subprocess stderr to logger.error.
- **Fix:** remove debug prints; scrub credential keys from param logging. Effort S.

### SEC-008 · ccxt-gateway container runs as root (CWE-250)
- `ccxt-gateway/Dockerfile` has no USER directive (top-level Dockerfile correctly drops to plnuser). Combined with SEC-002 any RCE-class bug is root-in-container.
- **Fix:** create app user + `USER`. Effort S.

### SEC-009 · ZMQ broker accepts unauthenticated local peers that can impersonate exchanges (CWE-287/345)
- `zmq_broker.py:21-22` binds tcp://127.0.0.1 (good) but no CURVE auth; :61-70 trusts any peer's `subprocess_ready` claim of ANY exchange_id → local process can hijack trade-request routing on multi-user hosts.
- **Fix:** shared secret/CURVE handshake between spawner and subprocesses. Effort L.

### SEC-010 · MCP tools expose unsandboxed arbitrary code execution (CWE-78/732) — trust boundary is "local stdio client" only
- `mcp_server.py:755-830`: `eval_in_session_tool` → `include_string(Main, arbitrary)`; `start_session_tool(project=any path)`; `test_strategy_tool(julia=<arbitrary executable>)`; deploy with run=True. Positive control: write_strategy traversal guard is sound and regression-tested (`mcp_server.py:100-120`, `tests/test_strategy_writing.py:119-129`). Julia-side strategy loading evals user code in-process (`Strategies/load.jl:247-315`) — documented by-design.
- **Action:** document the trust boundary prominently; consider an opt-in read-only tool profile for untrusted MCP clients.

## Low / Informational

- **SEC-011** Fixed `/tmp/gateway.log` (world-writable dir): symlink attack/log poisoning (`daemon_gateway.py:105-108`, `rest.jl:723-724`). Use per-user cache dir. Effort S.
- **SEC-012** `PlanarCore/src/Ccxt/certs/server.key` (dev TLS key) tracked at HEAD — minimal impact given SEC-005, but confuses scanners. Remove from tracking. Stub `exckeys.json` files verified placeholder ("123") — benign.
- **SEC-013** Dependencies clean: uv.lock pins current (fastapi 0.136.1, starlette 1.3.1, uvicorn 0.46.0, python-multipart 0.0.32, urllib3 2.7.0, h11 0.16.0, websockets 16.0); Julia compat exact-pinned. Residual: open-ended `>=` floors in pyproject.toml; unauthenticated `POST /admin/update/ccxt` pulls newest PyPI package (supply-chain surface gated only by missing auth — fix SEC-002 first).
- **SEC-014** Reviewed-and-clear: all Julia `run(`…`)` sinks argv-safe (no shell injection); `kill $stale_pid` parses Int first.

## Verified load integrity
Per repo precompile rule: `using PlanarDev` and `using PlanarOptim` both precompile/load end-to-end during audit (PLANARDEV_OK / PLANAROPTIM_OK). Pre-existing Watchers import warnings noted under Maintainability.
