macro compile_call()
    expr = quote
        @eval begin
            isdefined(@__MODULE__, :OrderTypes) || using .OrderTypes: OrderTypes as ot
            using .OrderTypes: Buy, Sell
            using .Lang: @ignore, @precomp
            isdefined(@__MODULE__, :Executors) ||
                using .Executors: call!, Executors as ect
        end

        let
            ai = first(s.universe)
            amount = ai.limits.amount.min
            prc = min(ai.limits.price.min * 10, ai.limits.price.max)
            date = now()
            function dispatched_orders()
                out = Type{<:Order}[]
                for name in names(ot; all=true)
                    name == :Order && continue
                    otp = getproperty(ot, name)
                    if otp isa Type && otp <: ot.Order
                        if applicable(ot.ordertype, otp{Buy})
                            push!(out, otp{Buy})
                            push!(out, otp{Sell})
                        end
                    end
                end
                out
            end
            @precomp @ignore @sync begin
                for otp in dispatched_orders()
                    if !Base.generating_output()
                        try
                            @async call!(s, ai, otp; amount, date, prc, synced=false)
                        catch e
                            if e isa InterruptException
                                rethrow(e)
                            end
                            @error "Precompile call! failed for order type" order_type=otp exception=(e, catch_backtrace())
                        end
                    end
                end
                if !Base.generating_output()
                    try
                        @async call!(
                            Returns(nothing),
                            s,
                            ect.InitData();
                            cols=(:abc,),
                            timeframe=tf"1d",
                            synced=false,
                        )
                    catch e
                        if e isa InterruptException
                            rethrow(e)
                        end
                        @error "Precompile call! failed for InitData" exception=(e, catch_backtrace())
                    end
                end
                if !Base.generating_output()
                    try
                        @async call!(
                            Returns(nothing),
                            s,
                            ect.UpdateData();
                            cols=(:abc,),
                            timeframe=tf"1d",
                            synced=false,
                        )
                    catch e
                        if e isa InterruptException
                            rethrow(e)
                        end
                        @error "Precompile call! failed for UpdateData" exception=(e, catch_backtrace())
                    end
                end
                if !Base.generating_output()
                    try
                        @async call!(s, ect.WatchOHLCV(), synced=false)
                    catch e
                        if e isa InterruptException
                            rethrow(e)
                        end
                        @error "Precompile call! failed for WatchOHLCV" exception=(e, catch_backtrace())
                    end
                end
                if !Base.generating_output()
                    try
                        @async call!(s, ai, 1.0, ect.UpdateLeverage(); pos=Long(), synced=false)
                    catch e
                        if e isa InterruptException
                            rethrow(e)
                        end
                        @error "Precompile call! failed for UpdateLeverage" exception=(e, catch_backtrace())
                    end
                end
                if !Base.generating_output()
                    try
                        @async call!(s, ai, Short(), date, ect.PositionClose(), synced=false)
                    catch e
                        if e isa InterruptException
                            rethrow(e)
                        end
                        @error "Precompile call! failed for PositionClose" exception=(e, catch_backtrace())
                    end
                end
                if !Base.generating_output()
                    try
                        @async call!(s, ai, ect.CancelOrders(), synced=false)
                    catch e
                        if e isa InterruptException
                            rethrow(e)
                        end
                        @error "Precompile call! failed for CancelOrders" exception=(e, catch_backtrace())
                    end
                end
            end
        end
    end
    esc(expr)
end