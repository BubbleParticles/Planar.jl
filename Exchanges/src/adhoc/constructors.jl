using .ExchangeTypes: HOOKS

_doinit() = begin
    nothing
end

_authenticate!(exc::Exchange{ExchangeID{:phemex}}) = nothing
