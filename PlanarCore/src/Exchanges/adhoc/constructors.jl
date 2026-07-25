using .ExchangeTypes: HOOKS

_doinit() = begin
    # Bybit: old code registered _load_time_diff hook for clock sync.
    # Now handled by gateway subprocess init (load_time_difference).
    # Phemex: old code registered _override_phemex hook (creates Python class
    # at runtime to override handle_message for WebSocket position messages).
    # Cannot be replicated without Python subprocess modifications.
    nothing
end

_authenticate!(exc::Exchange{ExchangeID{:phemex}}) = nothing
