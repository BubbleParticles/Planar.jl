import ..Instances: PositionOpen, PositionUpdate, PositionChange, Position
import ..OrderTypes: Trade

call!(::Strategy, ii, trade, ::NewTrade) = nothing

# Callback when a position is opened
function call!(::MarginStrategy, ii, trade::Trade, ::Position, ::PositionOpen)
    nothing
end

# Callback when a position is updated from a trade
function call!(::MarginStrategy, ii, trade::Trade, ::Position, ::PositionUpdate)
    nothing
end

# Callback when a position is updated from a candle (for SimMode position updates)
function call!(::MarginStrategy, ii, date::DateTime, ::Position, ::PositionUpdate)
    nothing
end

# Callback for position close (if needed)
function call!(::MarginStrategy, ii, ::Position, ::PositionClose)
    nothing
end
