using .ExchangeTypes: HOOKS

_doinit() = begin
    # Bybit: old code registered _load_time_diff hook for clock sync
    # Phemex: old code registered _override_phemex hook (creates Python class
    # at runtime to override handle_message for WebSocket position messages).
    # These cannot be replicated without the Python subprocess.
    nothing
end

_authenticate!(exc::Exchange{ExchangeID{:phemex}}) = nothing
