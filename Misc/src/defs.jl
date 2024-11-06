call!(args...; kwargs...) = error("Not implemented")
call!(args...; kwargs...) = error("Not implemented")

start!(args...; kwargs...) = error("not implemented")
stop!(args...; kwargs...) = error("not implemented")
isrunning(args...; kwargs...) = error("not implemented")
load!(args...; kwargs...) = error("not implemented")

export start!, stop!, isrunning
export load!
export call!, call!
