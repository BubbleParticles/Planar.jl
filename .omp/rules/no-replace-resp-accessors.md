---
name: no-replace-resp-accessors
description: "Do not replace or rewrite resp_* accessor functions; they exist so exchanges can override them for exchange-specific hotfixes"
condition: "resp_isfilled|resp_order_remaining|resp_order_filled|resp_order_status"
scope: "tool:edit(*.jl)"
---

Do NOT replace, rewrite, or reimplement `resp_*` accessor functions (e.g. `resp_order_status`, `resp_order_remaining`, `resp_order_filled`, `resp_isfilled`). They are intentionally isolated so individual exchanges can override them for exchange-specific hotfixes. When fixing a caller, fix the caller — keep the accessor as the indirection boundary. If an accessor is genuinely missing/broken, extend it minimally without collapsing the indirection or duplicating its logic inline via `get_float`.