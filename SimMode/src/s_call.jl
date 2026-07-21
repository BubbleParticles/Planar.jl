import .Instances: PositionOpen, PositionUpdate, PositionChange, Position
import .OrderTypes: Trade

call!(::Strategy, ai, trade, ::NewTrade) = nothing

# Callback when a position is opened
function call!(::MarginStrategy, ai, trade::Trade, ::Position, ::PositionOpen)
    nothing
end

# Callback when a position is updated from a trade
function call!(::MarginStrategy, ai, trade::Trade, ::Position, ::PositionUpdate)
    nothing
end

# Callback when a position is updated from a candle (for SimMode position updates)
function call!(::MarginStrategy, ai, date::DateTime, ::Position, ::PositionUpdate)
    nothing
end

# Callback for position close (if needed)
function call!(::MarginStrategy, ai, ::Position, ::PositionClose)
    nothing
end
