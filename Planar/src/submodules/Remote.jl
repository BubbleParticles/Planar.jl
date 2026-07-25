module Remote
    using PrettyTables, Telegram
    include("../Remote/module.jl")
    isdefined(@__MODULE__, :__doinit__) && __doinit__()
end
